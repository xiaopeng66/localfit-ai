import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_worker.dart';

/// 语义嵌入 worker 的**传输层**判据（docs/39 §4.3「长驻单 worker + 命令队列」）。
///
/// 用测试自带的假 worker（同一条消息协议）把传输层钉死：握手、并发请求按 id
/// 配对、失败与死亡都要变成 [EmbeddingUnavailable]（调用方据此降级），不能
/// 挂死也不能抛裸异常。真模型只在自己的 isolate 里（`embeddingWorkerMain`），
/// 不在本文件测试范围。
void main() {
  // 与 `embeddingWorkerMain` 相同的协议：先发 ready（带 dim 与请求端口），
  // 之后逐条处理 embed 请求。text 含「boom」⇒ 回 failure。
  Future<Isolate> fakeWorker(List<dynamic> seed) {
    return Isolate.spawn(_fakeWorkerMain, seed);
  }

  Future<EmbeddingWorkerConnection> connect() async {
    final reply = ReceivePort();
    final isolate = await fakeWorker([reply.sendPort, 8]);
    return EmbeddingWorkerConnection.connect(
      isolate: isolate,
      toWorker: null, // 由 ready 消息给出
      fromWorker: reply,
    );
  }

  test('握手 + 单条嵌入：返回与 dim 一致的向量', () async {
    final connection = await connect();
    addTearDown(connection.dispose);

    final vectors = await connection.embed(['番茄炒蛋'], maxLen: 32);
    expect(vectors, hasLength(1));
    expect(vectors.single, hasLength(8));
    expect(connection.dim, 8);
  });

  test('并发请求互不串线（按 id 配对）', () async {
    final connection = await connect();
    addTearDown(connection.dispose);

    // 三个字的 rune mod 8 落在不同桶（2/1/4），向量必然互不相同。
    final results = await Future.wait([
      connection.embed(['甲'], maxLen: 32),
      connection.embed(['乙'], maxLen: 32),
      connection.embed(['水'], maxLen: 32),
    ]);
    // 假 worker 对不同文本给出不同向量：三个请求都各自拿到自己的答案。
    expect(results[0].single, isNot(equals(results[1].single)));
    expect(results[1].single, isNot(equals(results[2].single)));
    expect(results, hasLength(3));
  });

  test('worker 回 failure ⇒ embed 抛 EmbeddingUnavailable（不挂死）', () async {
    final connection = await connect();
    addTearDown(connection.dispose);

    await expectLater(
      connection.embed(['boom'], maxLen: 32),
      throwsA(isA<EmbeddingUnavailable>()),
    );
    // 失败之后连接仍然可用（一次推理失败不该废掉整条路）。
    final vectors = await connection.embed(['恢复'], maxLen: 32);
    expect(vectors.single, hasLength(8));
  });

  test('worker 死亡 ⇒ 在途与后续请求都以 EmbeddingUnavailable 失败', () async {
    final connection = await connect();
    final inFlight = connection.embed(['番茄炒蛋'], maxLen: 32);

    connection.dispose(); // kill isolate
    await expectLater(inFlight, throwsA(isA<EmbeddingUnavailable>()));
    await expectLater(
      connection.embed(['再来一条'], maxLen: 32),
      throwsA(isA<EmbeddingUnavailable>()),
      reason: '连接已断：后续请求快速失败，而不是无限等待',
    );
  });

  test('worker 协议用**字节**而不是资产路径（rootBundle 不能在后台 isolate 用）', () async {
    // 2026-10-20 设备实测：worker 里 `rootBundle.load` 抛
    // 「Null check operator used on a null value」，语义路整条失效。
    // 判据：`embeddingWorkerMain` 的 seed[1]/seed[2] 必须是 Uint8List，
    // 且 `WorkerEmbeddingEngine` 在主 isolate 先把资产读成字节。
    final source = File('lib/features/retrieval/data/embedding_worker.dart')
        .readAsStringSync();
    expect(source, contains('seed[1] as Uint8List'));
    expect(source, contains('seed[2] as Uint8List'));
    expect(
      source,
      contains('rootBundle.load(modelAssetPath)'),
      reason: '资产必须在主 isolate 读（spawn 之前）',
    );
    expect(
      source,
      isNot(contains('OnnxEmbeddingEngine.load(')),
      reason: 'worker 里不得再按资产路径加载（只能 loadFromBytes）',
    );
    // ONNX 插件走平台通道：后台 isolate 必须先用根 isolate token 初始化，
    // 否则插件调用抛 BackgroundIsolateBinaryMessenger 的 Bad state。
    expect(
      source,
      contains('BackgroundIsolateBinaryMessenger.ensureInitialized(token)'),
    );
    expect(source, contains('RootIsolateToken.instance'));
  });

  test('握手失败（worker 报 error）⇒ connect 抛 EmbeddingUnavailable', () async {
    final reply = ReceivePort();
    final isolate = await Isolate.spawn(_brokenWorkerMain, reply.sendPort);
    await expectLater(
      EmbeddingWorkerConnection.connect(
        isolate: isolate,
        toWorker: null,
        fromWorker: reply,
      ),
      throwsA(isA<EmbeddingUnavailable>()),
    );
  });
}

/// 假 worker：与 `embeddingWorkerMain` 同一条协议（ready → embed 请求）。
/// 文本含「boom」⇒ 回 failure；否则返回按字符直方图构造的 8 维向量。
void _fakeWorkerMain(List<dynamic> seed) {
  final reply = seed[0] as SendPort;
  final dim = seed[1] as int;
  final requests = ReceivePort();
  reply.send({'type': 'ready', 'dim': dim, 'requests': requests.sendPort});
  requests.listen((message) {
    if (message is! Map) return;
    final id = message['id'] as int;
    final texts = (message['texts'] as List).cast<String>();
    if (texts.any((text) => text.contains('boom'))) {
      reply.send({'type': 'failure', 'id': id, 'message': '假 worker：模拟推理失败'});
      return;
    }
    reply.send({
      'type': 'result',
      'id': id,
      'vectors': [for (final text in texts) _histogramVector(text, dim)],
    });
  });
}

/// 一启动就报 error 的 worker（模拟模型缺失/加载失败）。
void _brokenWorkerMain(SendPort reply) {
  reply.send({'type': 'error', 'message': '假 worker：模拟模型加载失败'});
}

List<double> _histogramVector(String text, int dim) {
  final vector = List<double>.filled(dim, 0);
  for (final rune in text.runes) {
    vector[rune % dim] += 1;
  }
  return vector;
}
