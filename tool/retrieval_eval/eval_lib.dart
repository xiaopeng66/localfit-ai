// P0 检索尖刀（docs/41 §12 P0 / docs/39 §4、§10）：端上嵌入评测工具。
//
// 用法（宿主上跑，不进 App 包）：
//   flutter run --dart-define-from-file=tool/retrieval_eval/config.json \
//     -t tool/retrieval_eval/main.dart
//
// 或以纯 Dart（flutter_test 的宿主通道）方式由
// `flutter test tool/retrieval_eval/eval_test.dart` 驱动——测试宿主能加载
// 插件（Windows 桌面通道），模型路径经环境变量 P0_MODEL_DIR 注入。
//
// 评测内容（docs/39 §4/§10 的 P0 清单）：
//  * int8 vs fp32 延迟与质量；
//  * maxLen 32/64/128；
//  * BGE 前缀 A（无前缀）/ B（检索前缀）；
//  * 100 条中文口语查询 × 100 道菜：recall@10 / nDCG@10 / MRR；
//  * 混合（向量 + bigram 关键词 + 标签，RRF）vs「关键词 + 标签」基线，
//    门槛：相对提升 ≥ 20%；单条嵌入 < 15ms。
// 门槛不达标 ⇒ **不上向量**（如实登记，转而加强标签与关键词）。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:localfit_ai/features/retrieval/data/bert_wordpiece_tokenizer.dart';

/// 评测语料（tool/retrieval_eval/eval_corpus.json）：100 道菜 + 100 条
/// 中文口语查询（方言/别名/槽位混合，含 hard negatives）。
Future<({List<Dish> dishes, List<QueryCase> queries})> loadCorpus(
  String path,
) async {
  final data =
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  final dishes = [
    for (final raw in data['dishes'] as List)
      Dish(
        name: raw['name'] as String,
        aliases: (raw['aliases'] as List).cast<String>(),
        window: raw['window'] as String,
        tags: (raw['tags'] as List).cast<String>(),
      ),
  ];
  final queries = [
    for (final raw in data['queries'] as List)
      QueryCase(
        text: raw['q'] as String,
        relevantNames: (raw['relevant'] as List).cast<String>(),
      ),
  ];
  return (dishes: dishes, queries: queries);
}

final class Dish {
  Dish({
    required this.name,
    required this.aliases,
    required this.window,
    required this.tags,
  });

  final String name;
  final List<String> aliases;
  final String window;
  final List<String> tags;
}

final class QueryCase {
  QueryCase({required this.text, required this.relevantNames});
  final String text;
  final List<String> relevantNames;
}

/// 端上嵌入器：flutter_onnxruntime + 本仓 Dart WordPiece。
///
/// BGE 的池化是 CLS？不——BGE 系列用 **mean pooling**（1_Pooling/config）
/// 后 L2 归一。输入 [CLS] tokens [SEP]。
final class OnnxEmbedder {
  OnnxEmbedder._(this._session, this._tokenizer);

  final OrtSession _session;
  final BertWordPieceTokenizer _tokenizer;

  static Future<OnnxEmbedder> load({
    required String modelPath,
    required String vocabPath,
    int intraOpThreads = 1,
  }) async {
    final tokenizer = await BertWordPieceTokenizer.loadVocabFile(vocabPath);
    final ort = OnnxRuntime();
    final session = await ort.createSession(
      modelPath,
      options: OrtSessionOptions(
        intraOpNumThreads: intraOpThreads,
        providers: const [OrtProvider.CPU],
      ),
    );
    return OnnxEmbedder._(session, tokenizer);
  }

  /// 嵌入一批文本；返回 L2 归一后的向量（每条 [dim]）。
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = 64,
    String prefix = '',
  }) async {
    final batch = _tokenizer.encodeBatch([
      for (final t in texts) '$prefix$t',
    ], maxLen: maxLen);
    // 必须显式 Int64List：BERT/BGE 的三个输入都是 int64；传 List<int>
    // 会被插件推断成 Int32List，喂给 int64 输入在 ORT JNI 里是**原生崩溃**
    // （模拟器实测 SIGABRT，栈顶 OrtSession.run），不是可捕获异常。
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
    final dim = 512;
    final seqLen = batch.shape[1];
    final out = <List<double>>[];
    for (var b = 0; b < batch.shape[0]; b++) {
      var sumSq = 0.0;
      final vector = List<double>.filled(dim, 0.0);
      var count = 0.0;
      for (var s = 0; s < seqLen; s++) {
        final mask = batch.attentionMask[b * seqLen + s];
        if (mask == 0) continue;
        count += 1;
        final base = (b * seqLen + s) * dim;
        for (var d = 0; d < dim; d++) {
          final value = hidden[base + d].toDouble();
          vector[d] += value;
        }
      }
      for (var d = 0; d < dim; d++) {
        vector[d] /= math.max(count, 1e-9);
        sumSq += vector[d] * vector[d];
      }
      final norm = math.sqrt(sumSq);
      for (var d = 0; d < dim; d++) {
        vector[d] /= norm;
      }
      out.add(vector);
    }
    return out;
  }

  Future<void> dispose() => _session.close();
}

/// 检索路径：关键词（字符 bigram 含匹配）与标签。
final class KeywordSearch {
  const KeywordSearch(this.dishes);
  final List<Dish> dishes;

  /// 返回按分数降序的菜名下标（分数 = bigram 命中数 + 标签命中数）。
  List<int> search(String query, {String? slot}) {
    final q = query.trim();
    final bigrams = <String>{
      for (var i = 0; i + 2 <= q.length; i++) q.substring(i, i + 2),
      if (q.isNotEmpty) q,
    };
    final scored = <(int, double)>[];
    for (var i = 0; i < dishes.length; i++) {
      final dish = dishes[i];
      var score = 0.0;
      for (final gram in bigrams) {
        if (dish.name.contains(gram)) score += 1.0;
        for (final alias in dish.aliases) {
          if (alias.contains(gram) || gram.contains(alias)) {
            score += 0.8;
          }
        }
      }
      for (final tag in dish.tags) {
        if (q.contains(tag) || tag.contains(q)) score += 1.2;
      }
      if (score > 0) scored.add((i, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final entry in scored) entry.$1];
  }
}

/// RRF（Reciprocal Rank Fusion，docs/39 §0.2）：score = Σ 1/(60+rank)。
List<int> rrfFusion({required List<List<int>> rankings, int topK = 200}) {
  final scores = <int, double>{};
  for (final ranking in rankings) {
    for (var rank = 0; rank < ranking.length && rank < topK; rank++) {
      scores[ranking[rank]] =
          (scores[ranking[rank]] ?? 0) + 1 / (60 + rank + 1);
    }
  }
  final entries = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final entry in entries) entry.key];
}

/// 评测指标。
final class Metrics {
  static double recallAtK({
    required Set<String> relevant,
    required List<String> ranked,
    int k = 10,
  }) {
    if (relevant.isEmpty) return 0;
    final hits = ranked.take(k).where(relevant.contains).length;
    return hits / relevant.length;
  }

  static double ndcgAtK({
    required Set<String> relevant,
    required List<String> ranked,
    int k = 10,
  }) {
    if (relevant.isEmpty) return 0;
    var dcg = 0.0;
    for (var i = 0; i < ranked.length && i < k; i++) {
      if (relevant.contains(ranked[i])) {
        dcg += 1 / _log2(i + 2);
      }
    }
    var idcg = 0.0;
    for (var i = 0; i < math.min(relevant.length, k); i++) {
      idcg += 1 / _log2(i + 2);
    }
    return dcg / idcg;
  }

  static double mrr({
    required Set<String> relevant,
    required List<String> ranked,
  }) {
    for (var i = 0; i < ranked.length; i++) {
      if (relevant.contains(ranked[i])) return 1 / (i + 1);
    }
    return 0;
  }

  static double _log2(num x) => math.log(x) / math.ln2;
}
