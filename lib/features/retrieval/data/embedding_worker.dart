import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken, rootBundle;
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';

/// 嵌入 worker 的消息协议（docs/39 §4.3「长驻单 worker isolate + 命令队列」）。
///
/// **主 isolate 只做传输**：分词与 ORT 推理全部发生在 worker 里，UI 线程
/// 不再承担 24MB 模型加载与每条推理（2026-10-19 设备实测：主 isolate 加载
/// 模型会把低内存设备的界面拖死）。协议只有三条消息：
///
/// ```
/// 主 → worker（经 ready 里带回的 requests 端口）：
///   {'type': 'embed', 'id': int, 'texts': List<String>, 'maxLen': int, 'prefix': String}
/// worker → 主（经握手 reply 端口）：
///   {'type': 'ready', 'dim': int, 'requests': SendPort}
///   {'type': 'result',   'id': int, 'vectors': List<List<double>>}
///   {'type': 'failure',  'id': int, 'message': String}
///   {'type': 'error',    'message': String}   // 握手前的致命错误
/// ```
///
/// `id` 是主侧分配的单调递增序号——并发请求靠它配对，谁先回来算谁的。

/// worker 入口：加载模型（**在 worker isolate 里**），回 ready，然后循环
/// 处理 embed 请求。加载失败回 error 后退出。
Future<void> embeddingWorkerMain(List<dynamic> seed) async {
  final reply = seed[0] as SendPort;
  // 资产**字节**由主 isolate 读好传来：后台 isolate 里 `rootBundle` 不可用
  // （没有 ServicesBinding，读到的是 null ⇒「Null check operator used on a
  // null value」，2026-10-20 设备实测）。
  final modelBytes = seed[1] as Uint8List;
  final vocabBytes = seed[2] as Uint8List;
  final token = seed.length > 3 ? seed[3] as RootIsolateToken? : null;
  try {
    // ONNX Runtime 走平台通道：后台 isolate 必须先用**根 isolate 的 token**
    // 初始化 BackgroundIsolateBinaryMessenger，否则插件调用抛
    // 「The BackgroundIsolateBinaryMessenger.instance value is invalid…」
    // （2026-10-20 设备实测）。
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    final engine = await OnnxEmbeddingEngine.loadFromBytes(
      modelBytes: modelBytes,
      vocabBytes: vocabBytes,
    );
    final requests = ReceivePort();
    reply.send({
      'type': 'ready',
      'dim': engine.dim,
      'requests': requests.sendPort,
    });
    await for (final message in requests) {
      if (message is! Map) continue;
      final id = message['id'] as int?;
      if (id == null) continue;
      try {
        final vectors = await engine.embed(
          (message['texts'] as List).cast<String>(),
          maxLen: message['maxLen'] as int? ?? kDishEmbedMaxLen,
          prefix: message['prefix'] as String? ?? '',
        );
        reply.send({'type': 'result', 'id': id, 'vectors': vectors});
      } on Object catch (error) {
        reply.send({'type': 'failure', 'id': id, 'message': '$error'});
      }
    }
  } on Object catch (error) {
    reply.send({'type': 'error', 'message': '$error'});
  }
}

/// 主侧的一条连接：握手、按 id 配对、死亡兜底。
final class EmbeddingWorkerConnection {
  EmbeddingWorkerConnection._({
    required this.isolate,
    required this.requests,
    required this.dim,
  }) {
    // isolate 一死（kill / 内部崩溃），errorListener 会把错误送到这里；
    // 所有在途与后续请求快速失败。
    _errors.listen(
      (message) => _failAll('worker 崩溃：$message'),
      onError: (Object error) => _failAll('worker 崩溃：$error'),
      cancelOnError: false,
    );
    isolate.addErrorListener(_errors.sendPort);
    // `kill` 的 KillPortMessage 不走 errorListener，所以 dispose 后由本地
    // 标志位直接拒绝后续请求（SendPort 没有「存活探测」）。
  }

  /// 与一个已 spawn 的 worker 握手。[toWorker] 为 null 时表示端口由 ready
  /// 消息带回（标准路径）。
  /// 与一个已 spawn 的 worker 握手。**ReceivePort 只能 listen 一次**，
  /// 所以这里一次性挂好监听：第一条消息必须是 ready，之后的
  /// result/failure/error 都走同一个回调（`_onMessage`）。
  static Future<EmbeddingWorkerConnection> connect({
    required Isolate isolate,
    required SendPort? toWorker,
    required ReceivePort fromWorker,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final handshake = Completer<Map>();
    final connection = Completer<EmbeddingWorkerConnection>();
    late final EmbeddingWorkerConnection wired;
    late final StreamSubscription<dynamic> subscription;
    void handleMessage(dynamic raw) {
      if (raw is! Map) return;
      if (!handshake.isCompleted) {
        handshake.complete(Map<dynamic, dynamic>.from(raw));
        return;
      }
      wired._onMessage(raw);
    }

    subscription = fromWorker.listen(
      handleMessage,
      onError: (Object error) {
        if (!handshake.isCompleted) {
          handshake.completeError(EmbeddingUnavailable('worker 崩溃：$error'));
        } else {
          wired._failAll('worker 崩溃：$error');
        }
      },
      onDone: () {
        if (!handshake.isCompleted) {
          handshake.completeError(const EmbeddingUnavailable('worker 已退出'));
        } else {
          wired._failAll('worker 已退出');
        }
      },
    );
    handshake.future
        .timeout(
          timeout,
          onTimeout: () {
            throw const EmbeddingUnavailable('嵌入 worker 握手超时');
          },
        )
        .then((message) {
          if (message['type'] != 'ready') {
            throw EmbeddingUnavailable('嵌入 worker 加载失败：${message['message']}');
          }
          wired = EmbeddingWorkerConnection._(
            isolate: isolate,
            requests: message['requests'] as SendPort,
            dim: message['dim'] as int,
          );
          wired._fromWorker = fromWorker;
          wired._subscription = subscription;
          connection.complete(wired);
        })
        .onError<Object>((error, _) {
          subscription.cancel();
          fromWorker.close();
          connection.completeError(error);
        });
    return connection.future;
  }

  final Isolate isolate;
  final SendPort requests;
  final int dim;

  ReceivePort? _fromWorker;
  StreamSubscription<dynamic>? _subscription;
  final _pending = <int, Completer<List<List<double>>>>{};
  final _errors = ReceivePort();
  int _nextId = 0;
  bool _dead = false;

  void _onMessage(dynamic message) {
    if (message is! Map) return;
    final id = message['id'] as int?;
    switch (message['type']) {
      case 'result':
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete([
            for (final vector in (message['vectors'] as List))
              (vector as List).cast<double>(),
          ]);
        }
      case 'failure':
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            EmbeddingUnavailable('${message['message']}'),
          );
        }
      case 'error':
        _failAll('worker 加载失败：${message['message']}');
    }
  }

  void _failAll(String message) {
    if (_dead) return;
    _dead = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(EmbeddingUnavailable(message));
      }
    }
    _pending.clear();
  }

  /// 发一批文本过去；worker 死亡/推理失败都会以 [EmbeddingUnavailable] 抛。
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) {
    if (_dead) {
      return Future.error(const EmbeddingUnavailable('嵌入 worker 已退出'));
    }
    final id = _nextId++;
    final completer = Completer<List<List<double>>>();
    _pending[id] = completer;
    requests.send({
      'type': 'embed',
      'id': id,
      'texts': texts,
      'maxLen': maxLen,
      'prefix': prefix,
    });
    return completer.future;
  }

  void dispose() {
    _failAll('嵌入 worker 已退出');
    _errors.close();
    _subscription?.cancel();
    _fromWorker?.close();
    isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

/// 长驻语义 worker 的持有者（`SemanticRuntime` 用它替代直接持引擎）。
///
/// 惰性 spawn：第一次请求才起 isolate；spawn/握手失败记入 `_loadError`
/// 并让后续调用快速降级（与直连引擎同一条降级路径）。
final class WorkerEmbeddingEngine implements EmbeddingEngine {
  WorkerEmbeddingEngine({
    this.modelAssetPath = OnnxEmbeddingEngine.modelAsset,
    this.vocabAssetPath = OnnxEmbeddingEngine.vocabAsset,
  });

  final String modelAssetPath;
  final String vocabAssetPath;

  EmbeddingWorkerConnection? _connection;
  Object? _loadError;
  Future<EmbeddingWorkerConnection>? _starting;

  @override
  int get dim => kEmbeddingDim;

  Future<EmbeddingWorkerConnection> _ensureConnection() async {
    final ready = _connection;
    if (ready != null) return ready;
    if (_loadError case final error?) {
      throw EmbeddingUnavailable('语义 worker 不可用：$error');
    }
    // 并发调用共享同一次启动。
    final starting = _starting ??= _start();
    try {
      final connection = await starting;
      return _connection = connection;
    } on Object catch (error) {
      _loadError = error;
      _starting = null;
      throw EmbeddingUnavailable('语义 worker 不可用：$error');
    }
  }

  Future<EmbeddingWorkerConnection> _start() async {
    // `rootBundle` 只能在主 isolate 用；先把两份资产读成字节，再 spawn。
    // 失败（资产缺失）按加载失败处理，调用方降级为关键词 + 标签。
    final model = await rootBundle.load(modelAssetPath);
    final vocab = await rootBundle.load(vocabAssetPath);
    // 根 isolate token：worker 里用它初始化平台通道（ONNX 插件要用）。
    final token = RootIsolateToken.instance;
    final reply = ReceivePort();
    final isolate = await Isolate.spawn(embeddingWorkerMain, [
      reply.sendPort,
      model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      vocab.buffer.asUint8List(vocab.offsetInBytes, vocab.lengthInBytes),
      token,
    ], debugName: 'embedding-worker');
    try {
      final connection = await EmbeddingWorkerConnection.connect(
        isolate: isolate,
        toWorker: null,
        fromWorker: reply,
      );
      return connection;
    } on Object {
      isolate.kill(priority: Isolate.beforeNextEvent);
      reply.close();
      rethrow;
    }
  }

  /// 空闲预热：spawn + 握手 + 跑一条真实推理（首次调用含模型加载，秒级）。
  /// 失败只记日志——真正用到时还有一次降级机会。
  Future<void> warmUp() async {
    try {
      final connection = await _ensureConnection();
      await connection.embed(['预热'], maxLen: kDishEmbedMaxLen);
    } on Object catch (error) {
      debugPrint('语义 worker 预热失败（检索会降级为关键词+标签）：$error');
    }
  }

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async {
    final connection = await _ensureConnection();
    return connection.embed(texts, maxLen: maxLen, prefix: prefix);
  }

  Future<void> dispose() async {
    _connection?.dispose();
    _connection = null;
  }
}

/// 把 `[List<double>]` 压成 `Float32List`（写 `embedding_index.vector` 用）；
/// 与 `SemanticRuntime` 的编解码同口径，放在这里供 worker 侧复用。
Uint8List float32Bytes(List<double> vector) {
  final data = Float32List.fromList(vector);
  return data.buffer.asUint8List();
}
