import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:localfit_ai/features/retrieval/data/bert_wordpiece_tokenizer.dart';

/// 端上嵌入引擎（docs/39 §4、docs/41 §6）。
///
/// 抽象只暴露「一批文本 → L2 归一向量」这一件事：上层（索引、检索、记忆
/// 相关性）都只认这个接口，测试用 [FakeEmbeddingEngine] 注入确定性向量，
/// 真模型只在设备/基准上跑（与 P0 评测同一口径）。
abstract interface class EmbeddingEngine {
  /// 每条返回 [dim] 维、L2 归一后的向量。
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen,
    String prefix,
  });

  int get dim;
}

/// 档位常量（来自 P0 稳态复测 `docs/evidence/2026-10-18-p0-eval.md` §7）。
///
/// **为什么是两档而不是一个全局值**：菜名/食物名很短（≤15 字），32 token
/// 足够、p95 = 13.3 ms（过门槛）；记忆正文最长 140 字，32 token 会截断尾部，
/// 用 64（p95 ≈ 17.8 ms）。记忆每轮只有一次查询嵌入，落在「每轮额外 <30ms」
/// 的预算内。
const int kDishEmbedMaxLen = 32;
const int kMemoryEmbedMaxLen = 64;

/// 菜品语义检索的最低余弦。
///
/// **2026-10-20 真模型标定**（`docs/evidence/2026-10-20-full-app-review/perf/
/// semantic-threshold-calibration.md`）：int8 模型下无关查询最高 0.386、
/// 相关查询 0.389–0.500（分布重叠）。取 0.45 先保证「不把无关菜说成命中」；
/// 弱相关（0.39–0.45）宁可漏掉并如实提示，也不夸大成命中。
///
/// 低于它的菜**不算命中**：语义排序只负责「相关的排前面」，不负责
/// 「把不相关的也说成相关」。全体低于阈值 ⇒ 语义路整体不参与。
const double kDishSemanticMinCosine = 0.45;

/// 模型标识：写进 `embedding_index.modelId`，换模型必须换它并全量重建。
///
/// **换模型时必须同时重标 [kDishSemanticMinCosine]**（裁决 D-3）：余弦尺度
/// 随模型变，0.45 只对当前 int8 模型成立；标定方法见
/// `docs/evidence/2026-10-20-full-app-review/perf/semantic-threshold-calibration.md`。
const String kEmbeddingModelId = 'bge-small-zh-v1.5-int8-v1';

/// 向量维度（bge-small-zh-v1.5）。
const int kEmbeddingDim = 512;

/// 查询前缀（BGE v1.5 检索建议）：P0 A/B 里 B 档更优，故默认用 B。
const String kQueryPrefix = BertWordPieceTokenizer.bgeQueryPrefix;

/// true 型 ONNX 引擎：资产 → 临时文件 → OrtSession。
///
/// 三个必须照做的细节（全部来自 P0 的真实崩溃）：
/// 1. **显式 Int64List**：传 `List<int>` 会被插件推断成 int32，喂给 int64 输入
///    在 ORT JNI 里是原生 SIGABRT（不可捕获）；
/// 2. **intra-op = 1**：与 UI 抢核会让整机卡顿（docs/39 §4.3）；
/// 3. **资产要先落到文件**：ORT 只吃路径，`rootBundle` 给的是内存字节。
final class OnnxEmbeddingEngine implements EmbeddingEngine {
  OnnxEmbeddingEngine._(this._session, this._tokenizer, this._tempDir);

  final OrtSession _session;
  final BertWordPieceTokenizer _tokenizer;
  final Directory _tempDir;

  static const String modelAsset = 'assets/models/model_int8.onnx';
  static const String vocabAsset = 'assets/models/vocab.txt';

  @override
  int get dim => kEmbeddingDim;

  /// 加载模型（冷启动 <1.5s 量级；调用方应放在空闲时预热）。
  static Future<OnnxEmbeddingEngine> load({
    String modelAssetPath = modelAsset,
    String vocabAssetPath = vocabAsset,
    int intraOpThreads = 1,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('lf-embed-');
    final modelPath = await _materialize(modelAssetPath, tempDir, 'model.onnx');
    final vocabPath = await _materialize(vocabAssetPath, tempDir, 'vocab.txt');
    return loadFromFiles(
      modelPath: modelPath,
      vocabPath: vocabPath,
      tempDir: tempDir,
      intraOpThreads: intraOpThreads,
    );
  }

  /// 从**已落盘的字节**加载。
  ///
  /// worker isolate 走这条：`rootBundle` 只能在主 isolate 用（后台 isolate
  /// 没有 `ServicesBinding`，读资产会抛「Null check operator used on a null
  /// value」——2026-10-20 设备实测抓到），所以资产字节由主 isolate 读好后
  /// 传进来，worker 只负责写临时文件 + 建 ORT session。
  static Future<OnnxEmbeddingEngine> loadFromBytes({
    required Uint8List modelBytes,
    required Uint8List vocabBytes,
    int intraOpThreads = 1,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('lf-embed-');
    final modelPath = await _write(tempDir, 'model.onnx', modelBytes);
    final vocabPath = await _write(tempDir, 'vocab.txt', vocabBytes);
    return loadFromFiles(
      modelPath: modelPath,
      vocabPath: vocabPath,
      tempDir: tempDir,
      intraOpThreads: intraOpThreads,
    );
  }

  static Future<OnnxEmbeddingEngine> loadFromFiles({
    required String modelPath,
    required String vocabPath,
    required Directory tempDir,
    int intraOpThreads = 1,
  }) async {
    final tokenizer = await BertWordPieceTokenizer.loadVocabFile(vocabPath);
    final session = await OnnxRuntime().createSession(
      modelPath,
      options: OrtSessionOptions(
        intraOpNumThreads: intraOpThreads,
        providers: const [OrtProvider.CPU],
      ),
    );
    return OnnxEmbeddingEngine._(session, tokenizer, tempDir);
  }

  static Future<String> _materialize(
    String asset,
    Directory dir,
    String name,
  ) async {
    final data = await rootBundle.load(asset);
    return _write(
      dir,
      name,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  static Future<String> _write(
    Directory dir,
    String name,
    Uint8List bytes,
  ) async {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async {
    if (texts.isEmpty) return const [];
    final batch = _tokenizer.encodeBatch([
      for (final text in texts) '$prefix$text',
    ], maxLen: maxLen);
    final inputIds = await OrtValue.fromList(
      Int64List.fromList(batch.inputIds),
      batch.shape,
    );
    final attention = await OrtValue.fromList(
      Int64List.fromList(batch.attentionMask),
      batch.shape,
    );
    final tokenTypes = await OrtValue.fromList(
      Int64List.fromList(batch.tokenTypeIds),
      batch.shape,
    );
    final outputs = await _session.run({
      'input_ids': inputIds,
      'attention_mask': attention,
      'token_type_ids': tokenTypes,
    });
    final hidden = (await outputs['last_hidden_state']!.asFlattenedList())
        .cast<num>()
        .toList();
    final seqLen = batch.shape[1];
    final out = <List<double>>[];
    for (var b = 0; b < batch.shape[0]; b++) {
      final vector = List<double>.filled(kEmbeddingDim, 0.0);
      var count = 0.0;
      for (var s = 0; s < seqLen; s++) {
        if (batch.attentionMask[b * seqLen + s] == 0) continue;
        count += 1;
        final base = (b * seqLen + s) * kEmbeddingDim;
        for (var d = 0; d < kEmbeddingDim; d++) {
          vector[d] += hidden[base + d].toDouble();
        }
      }
      var sumSq = 0.0;
      for (var d = 0; d < kEmbeddingDim; d++) {
        vector[d] /= math.max(count, 1e-9);
        sumSq += vector[d] * vector[d];
      }
      final norm = math.sqrt(sumSq);
      for (var d = 0; d < kEmbeddingDim; d++) {
        vector[d] /= norm == 0 ? 1 : norm;
      }
      out.add(vector);
    }
    return out;
  }

  Future<void> dispose() async {
    await _session.close();
    await _tempDir.delete(recursive: true).catchError((_) => _tempDir);
  }
}

/// 确定性假引擎（测试与无模型环境）：把文本映射成一个稳定的 512 维向量。
///
/// 它**不是**语义模型——同义改写不会靠近（那是真模型的事）；它的用途是
/// 把「索引写入、余弦排序、门控、降级」这些**管道逻辑**钉死。
final class FakeEmbeddingEngine implements EmbeddingEngine {
  const FakeEmbeddingEngine({
    this.dimensions = kEmbeddingDim,
    this.failing = false,
  });

  final int dimensions;

  /// true ⇒ [embed] 抛错：用于钉「引擎失败必须降级、不能崩」。
  final bool failing;

  @override
  int get dim => dimensions;

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async {
    if (failing) {
      throw const EmbeddingUnavailable('假引擎：模拟模型加载失败');
    }
    final out = <List<double>>[];
    for (final text in texts) {
      final vector = List<double>.filled(dimensions, 0.0);
      for (final rune in ('$prefix$text').runes) {
        vector[rune % dimensions] += 1;
      }
      var sumSq = 0.0;
      for (final value in vector) {
        sumSq += value * value;
      }
      final norm = math.sqrt(sumSq);
      for (var d = 0; d < dimensions; d++) {
        vector[d] /= norm == 0 ? 1 : norm;
      }
      out.add(vector);
    }
    return out;
  }
}

/// 向量不可用（模型缺失/加载失败/推理异常）时抛；调用方据此降级到
/// 关键词 + 标签检索，并如实提示「语义检索不可用」（docs/39 §4.3）。
final class EmbeddingUnavailable implements Exception {
  const EmbeddingUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
