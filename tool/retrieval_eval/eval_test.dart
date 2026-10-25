// P0 评测执行入口（docs/41 §12 P0）。真实模型只在宿主跑：
// `P0_MODEL_DIR` 指向含 model_int8.onnx / model_fp32.onnx / vocab.txt 的目录；
// 未设置时整组跳过（门禁零外呼、零模型依赖不受影响）。
//
// 产出（写入 $P0_MODEL_DIR/p0_report.json + stdout 表）：
//   int8 vs fp32 延迟 / maxLen 32·64·128 / 前缀 A·B / recall@10·nDCG·MRR /
//   混合 vs「关键词+标签」相对提升 / 单条嵌入延迟。
// 门槛（docs/39 §10）：混合 ≥ 关键词+标签 ×1.20 且 单条嵌入 p50 < 15ms。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/retrieval/data/bert_wordpiece_tokenizer.dart';

import 'eval_lib.dart' as eval;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final modelDir = Platform.environment['P0_MODEL_DIR'];
  if (modelDir == null || modelDir.isEmpty) {
    test('P0 评测（需要 P0_MODEL_DIR，未设置则整组跳过）', () {
      markTestSkipped('P0_MODEL_DIR 未设置：真实模型评测仅在宿主显式执行');
    });
    return;
  }

  final corpusPath =
      Platform.environment['P0_CORPUS'] ??
      'tool/retrieval_eval/eval_corpus.json';
  final vocabPath = '$modelDir/vocab.txt';
  final int8Path = '$modelDir/model_int8.onnx';
  final fp32Path = '$modelDir/model_fp32.onnx';

  late ({List<eval.Dish> dishes, List<eval.QueryCase> queries}) corpus;

  setUpAll(() async {
    corpus = await eval.loadCorpus(corpusPath);
    expect(corpus.queries.length, greaterThanOrEqualTo(100));
  });

  test('P0 评测：int8/fp32 × maxLen × 前缀 A/B 全矩阵 + 门槛判定', () async {
    final report = <String, dynamic>{
      'corpus': {
        'queries': corpus.queries.length,
        'dishes': corpus.dishes.length,
      },
    };
    final names = [for (final dish in corpus.dishes) dish.name];
    final queryTexts = [for (final q in corpus.queries) q.text];
    final keyword = eval.KeywordSearch(corpus.dishes);
    final relevance = [for (final q in corpus.queries) q.relevantNames.toSet()];

    for (final variant in [('int8', int8Path), ('fp32', fp32Path)]) {
      final (label, path) = variant;
      final embedder = await eval.OnnxEmbedder.load(
        modelPath: path,
        vocabPath: vocabPath,
      );
      try {
        // 索引向量（菜名，无前缀——文档侧语义）。
        final dishVectors = await embedder.embed(names, maxLen: 64);
        for (final maxLen in [32, 64, 128]) {
          for (final prefixMode in ['A', 'B']) {
            final prefix = prefixMode == 'B'
                ? BertWordPieceTokenizer.bgeQueryPrefix
                : '';
            final sw = Stopwatch()..start();
            final queryVectors = await embedder.embed(
              queryTexts,
              maxLen: maxLen,
              prefix: prefix,
            );
            sw.stop();
            final embedMs = sw.elapsedMicroseconds / 1000 / queryTexts.length;

            // 单条嵌入延迟（p50 over 50 次短文本）。
            final singles = <double>[];
            for (var i = 0; i < 50; i++) {
              final timer = Stopwatch()..start();
              await embedder.embed(
                [corpus.queries[i % corpus.queries.length].text],
                maxLen: maxLen,
                prefix: prefix,
              );
              timer.stop();
              singles.add(timer.elapsedMicroseconds / 1000);
            }
            singles.sort();
            final p50 = singles[singles.length ~/ 2];
            final p95 = singles[(singles.length * 0.95).floor()];

            // 混合检索（向量 + 关键词 RRF）。
            var recallSum = 0.0;
            var ndcgSum = 0.0;
            var mrrSum = 0.0;
            for (var i = 0; i < corpus.queries.length; i++) {
              final sims = <(int, double)>[];
              for (var d = 0; d < dishVectors.length; d++) {
                var dot = 0.0;
                final qv = queryVectors[i];
                final dv = dishVectors[d];
                for (var k = 0; k < qv.length; k++) {
                  dot += qv[k] * dv[k];
                }
                sims.add((d, dot));
              }
              sims.sort((a, b) => b.$2.compareTo(a.$2));
              final vectorRanking = [
                for (final entry in sims.take(200)) entry.$1,
              ];
              final keywordRanking = keyword.search(queryTexts[i]);
              final fused = eval.rrfFusion(
                rankings: [vectorRanking, keywordRanking],
              );
              final rankedNames = [
                for (final idx in fused.take(50)) names[idx],
              ];
              recallSum += eval.Metrics.recallAtK(
                relevant: relevance[i],
                ranked: rankedNames,
              );
              ndcgSum += eval.Metrics.ndcgAtK(
                relevant: relevance[i],
                ranked: rankedNames,
              );
              mrrSum += eval.Metrics.mrr(
                relevant: relevance[i],
                ranked: rankedNames,
              );
            }
            final n = corpus.queries.length;
            final key = '$label-maxLen$maxLen-prefix$prefixMode';
            report[key] = {
              'recall@10': recallSum / n,
              'nDCG@10': ndcgSum / n,
              'MRR': mrrSum / n,
              'embedMsPerQueryBatch': embedMs,
              'embedSingleP50Ms': p50,
              'embedSingleP95Ms': p95,
            };
          }
        }
      } finally {
        await embedder.dispose();
      }
    }

    // 基线：关键词 + 标签（RRF 只挂关键词一路 = 关键词序）。
    var kwRecall = 0.0;
    var kwNdcg = 0.0;
    var kwMrr = 0.0;
    for (var i = 0; i < corpus.queries.length; i++) {
      final ranking = keyword.search(queryTexts[i]);
      final rankedNames = [for (final idx in ranking.take(50)) names[idx]];
      kwRecall += eval.Metrics.recallAtK(
        relevant: relevance[i],
        ranked: rankedNames,
      );
      kwNdcg += eval.Metrics.ndcgAtK(
        relevant: relevance[i],
        ranked: rankedNames,
      );
      kwMrr += eval.Metrics.mrr(relevant: relevance[i], ranked: rankedNames);
    }
    final n = corpus.queries.length;
    report['baseline-keyword+tags'] = {
      'recall@10': kwRecall / n,
      'nDCG@10': kwNdcg / n,
      'MRR': kwMrr / n,
    };

    // 门槛判定（docs/39 §10）：默认档（int8/maxLen64/前缀A）混合比基线
    // 相对提升 ≥20%，单条嵌入 p50 < 15ms。
    final mixed = report['int8-maxLen64-prefixA'] as Map<String, dynamic>;
    final mixedRecall = mixed['recall@10'] as double;
    final baseRecall =
        (report['baseline-keyword+tags'] as Map)['recall@10'] as double;
    final relativeGain = baseRecall == 0 ? 0.0 : mixedRecall / baseRecall - 1;
    final singleP50 = mixed['embedSingleP50Ms'] as double;
    final verdict = {
      'relativeGain': relativeGain,
      'gateGainMet': relativeGain >= 0.20,
      'singleEmbedP50Ms': singleP50,
      'gateLatencyMet': singleP50 < 15.0,
      'adoptVectors': relativeGain >= 0.20 && singleP50 < 15.0,
    };
    report['verdict-default'] = verdict;

    // 逐键打印 + 落盘。
    final encoder = const JsonEncoder.withIndent('  ');
    // ignore: avoid_print
    print(encoder.convert(report));
    await File('$modelDir/p0_report.json')
        .writeAsString(encoder.convert(report));

    // 门槛本身不 assert 通过与否（不达标就登记不上向量），但数值必须产出。
    expect(mixedRecall, greaterThanOrEqualTo(0));
    expect(singleP50, greaterThanOrEqualTo(0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
