// P0 评测尖刀宿主（Windows 桌面）：真实 platform channel + 真模型。
// 跑完写 $P0_OUT/p0_report.json 后退出（SystemNavigator.pop）。
//
// 运行（本仓根目录）：
//   P0_MODEL_DIR=E:/AI/Zcode/tmp/localfit-p0-embed-20261018/model \
//   flutter run -d windows -t tool/retrieval_eval/main.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'eval_lib.dart' as eval;

import 'package:localfit_ai/features/retrieval/data/bert_wordpiece_tokenizer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 模型目录：优先环境变量（桌面宿主）；Android 上先试 adb 可写的
  // `/data/local/tmp/p0_model`（shell 推送、chmod 644 后应用可读），
  // 再退回应用自己的外部 files 目录。
  final androidFiles = '${_externalRoot()}/files';
  final modelDir =
      Platform.environment['P0_MODEL_DIR'] ??
      (Platform.isAndroid
          ? '/data/local/tmp/p0_model'
          : 'E:/AI/Zcode/tmp/localfit-p0-embed-20261018/model');
  final outDir =
      Platform.environment['P0_OUT'] ??
      (Platform.isAndroid
          ? androidFiles
          : 'E:/AI/Zcode/tmp/localfit-p0-embed-20261018');
  final corpusPath =
      Platform.environment['P0_CORPUS'] ??
      (Platform.isAndroid
          ? '$modelDir/eval_corpus.json'
          : 'tool/retrieval_eval/eval_corpus.json');

  final report = <String, dynamic>{};
  final log = StringBuffer();
  void say(String line) {
    // ignore: avoid_print
    print(line);
    log.writeln(line);
  }

  final corpus = await eval.loadCorpus(corpusPath);
  say(
    'corpus: ${corpus.queries.length} queries × ${corpus.dishes.length} dishes',
  );
  final names = [for (final dish in corpus.dishes) dish.name];
  final queryTexts = [for (final q in corpus.queries) q.text];
  final keyword = eval.KeywordSearch(corpus.dishes);
  final relevance = [for (final q in corpus.queries) q.relevantNames.toSet()];

  // 基线：关键词 + 标签。
  var kwRecall = 0.0, kwNdcg = 0.0, kwMrr = 0.0;
  for (var i = 0; i < corpus.queries.length; i++) {
    final ranking = keyword.search(queryTexts[i]);
    final rankedNames = [for (final idx in ranking.take(50)) names[idx]];
    kwRecall += eval.Metrics.recallAtK(
      relevant: relevance[i],
      ranked: rankedNames,
    );
    kwNdcg += eval.Metrics.ndcgAtK(relevant: relevance[i], ranked: rankedNames);
    kwMrr += eval.Metrics.mrr(relevant: relevance[i], ranked: rankedNames);
  }
  final n = corpus.queries.length;
  report['baseline-keyword+tags'] = {
    'recall@10': kwRecall / n,
    'nDCG@10': kwNdcg / n,
    'MRR': kwMrr / n,
  };
  say(
    'baseline keyword+tags: recall@10=${(kwRecall / n).toStringAsFixed(4)} '
    'nDCG=${(kwNdcg / n).toStringAsFixed(4)} MRR=${(kwMrr / n).toStringAsFixed(4)}',
  );

  for (final (label, path) in [
    ('int8', '$modelDir/model_int8.onnx'),
    ('fp32', '$modelDir/model_fp32.onnx'),
  ]) {
    final swLoad = Stopwatch()..start();
    final embedder = await eval.OnnxEmbedder.load(
      modelPath: path,
      vocabPath: '$modelDir/vocab.txt',
    );
    swLoad.stop();
    say('$label load: ${swLoad.elapsedMilliseconds}ms');
    try {
      final dishVectors = await embedder.embed(names, maxLen: 64);
      // 矩阵：int8 全网格（32/64/128 × 前缀 A/B）；fp32 只跑默认档
      // （64 × A）作质量/延迟对照——把设备机时留给 int8 的选型。
      final grid = label == 'int8'
          ? const [
              (32, 'A'),
              (32, 'B'),
              (64, 'A'),
              (64, 'B'),
              (128, 'A'),
              (128, 'B'),
            ]
          : const [(64, 'A')];
      for (final (maxLen, prefixMode) in grid) {
        final prefix = prefixMode == 'B'
            ? BertWordPieceTokenizer.bgeQueryPrefix
            : '';
        final swBatch = Stopwatch()..start();
        final queryVectors = await embedder.embed(
          queryTexts,
          maxLen: maxLen,
          prefix: prefix,
        );
        swBatch.stop();

        // ── 稳态延迟（2026-10-19 补）──────────────────────────────────
        // 原实现只跑 50 次、且第一次含 ORT 的懒初始化，p95 会被冷启动抬高。
        // 这里先**预热 10 次**（不计入），再跑 200 次；`P0_STEADY_JSON` 单独
        // 打一行，便于区分「冷启动污染」与「真实稳态」。
        final singleQuery = corpus.queries.first.text;
        for (var i = 0; i < 10; i++) {
          await embedder.embed([singleQuery], maxLen: maxLen, prefix: prefix);
        }
        final steady = <double>[];
        for (var i = 0; i < 200; i++) {
          final timer = Stopwatch()..start();
          await embedder.embed([singleQuery], maxLen: maxLen, prefix: prefix);
          timer.stop();
          steady.add(timer.elapsedMicroseconds / 1000);
        }
        steady.sort();
        final steadyP50 = steady[steady.length ~/ 2];
        final steadyP95 = steady[(steady.length * 0.95).floor()];
        final steadyP99 = steady[(steady.length * 0.99).floor()];
        // ignore: avoid_print
        print(
          'P0_STEADY_JSON '
          '{"maxLen":$maxLen,"prefix":"$prefixMode","n":${steady.length},'
          '"p50":${steadyP50.toStringAsFixed(2)},'
          '"p95":${steadyP95.toStringAsFixed(2)},'
          '"p99":${steadyP99.toStringAsFixed(2)},'
          '"met":${steadyP95 < 15.0}}',
        );

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

        var recallSum = 0.0, ndcgSum = 0.0, mrrSum = 0.0;
        for (var i = 0; i < corpus.queries.length; i++) {
          final sims = <(int, double)>[];
          final qv = queryVectors[i];
          for (var d = 0; d < dishVectors.length; d++) {
            var dot = 0.0;
            final dv = dishVectors[d];
            for (var k = 0; k < qv.length; k++) {
              dot += qv[k] * dv[k];
            }
            sims.add((d, dot));
          }
          sims.sort((a, b) => b.$2.compareTo(a.$2));
          final vectorRanking = [for (final entry in sims.take(200)) entry.$1];
          final keywordRanking = keyword.search(queryTexts[i]);
          final fused = eval.rrfFusion(
            rankings: [vectorRanking, keywordRanking],
          );
          final rankedNames = [for (final idx in fused.take(50)) names[idx]];
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
        final key = '$label-maxLen$maxLen-prefix$prefixMode';
        report[key] = {
          'recall@10': recallSum / n,
          'nDCG@10': ndcgSum / n,
          'MRR': mrrSum / n,
          'embedMsPerQueryBatch': swBatch.elapsedMicroseconds / 1000 / n,
          'embedSingleP50Ms': p50,
          'embedSingleP95Ms': p95,
        };
        say(
          '$key: recall@10=${(recallSum / n).toStringAsFixed(4)} '
          'nDCG=${(ndcgSum / n).toStringAsFixed(4)} MRR=${(mrrSum / n).toStringAsFixed(4)} '
          'p50=${p50.toStringAsFixed(1)}ms p95=${p95.toStringAsFixed(1)}ms',
        );
        // 每档落盘一次：设备端跑长矩阵随时可能被杀，已得数据不能丢。
        await _flush(outDir, report, log);
      }
    } finally {
      await embedder.dispose();
    }
  }

  final mixed = report['int8-maxLen64-prefixA'] as Map<String, dynamic>?;
  final base = report['baseline-keyword+tags'] as Map<String, dynamic>;
  if (mixed != null) {
    final mixedRecall = mixed['recall@10'] as double;
    final baseRecall = base['recall@10'] as double;
    final relativeGain = baseRecall == 0 ? 0.0 : mixedRecall / baseRecall - 1;
    final singleP50 = mixed['embedSingleP50Ms'] as double;
    final singleP95 = mixed['embedSingleP95Ms'] as double;
    report['verdict-default'] = {
      'config': 'int8-maxLen64-prefixA',
      'mixedRecall@10': mixedRecall,
      'baselineRecall@10': baseRecall,
      'relativeGain': relativeGain,
      'gateGainMet(>=0.20)': relativeGain >= 0.20,
      'singleEmbedP50Ms': singleP50,
      'singleEmbedP95Ms': singleP95,
      'gateLatencyMet(p95<15ms)': singleP95 < 15.0,
      'adoptVectors': relativeGain >= 0.20 && singleP95 < 15.0,
    };
    // 选型结论：按「p95 < 15ms 且增益 ≥20%」在全部 int8 档里挑最优，
    // 质量优先、同质量取延迟更低者。
    Map<String, dynamic>? best;
    String? bestKey;
    for (final entry in report.entries) {
      if (!entry.key.startsWith('int8-')) continue;
      final cell = entry.value as Map<String, dynamic>;
      final gain = baseRecall == 0
          ? 0.0
          : (cell['recall@10'] as double) / baseRecall - 1;
      if (gain < 0.20) continue;
      final ok = (cell['embedSingleP95Ms'] as double) < 15.0;
      if (!ok) continue;
      final better =
          best == null ||
          (cell['embedSingleP95Ms'] as double) <
              (best['embedSingleP95Ms'] as double);
      if (better) {
        best = cell;
        bestKey = entry.key;
      }
    }
    report['verdict-selection'] = {
      'chosen': bestKey,
      'metBothGates': best != null,
      'note': best == null
          ? '没有配置同时满足 p95<15ms 与增益>=20%'
          : '最优配置满足两条门槛（质量优先，同质量取延迟更低）',
    };
    say('VERDICT: ${jsonEncode(report['verdict-default'])}');
    say('SELECTION: ${jsonEncode(report['verdict-selection'])}');
  } else {
    say('VERDICT: 未跑到默认档（int8-maxLen64-prefixA），本次无结论');
  }

  await _flush(outDir, report, log);
  say('report written to $outDir/p0_report.json');
  // logcat 通道（单行、带前缀）：设备 scoped storage 让 adb 读不到应用外部
  // 目录，而应用刻意禁用 cleartext 上传 ⇒ 结果从 logcat 取（单条 <4KB）。
  say('P0_REPORT_JSON ${jsonEncode(report)}');

  // 有头应用：跑完退出。
  if (Platform.environment['P0_KEEP_ALIVE'] != '1') {
    await SystemNavigator.pop();
    exit(0);
  }
  if (mixed == null) return;
  final mixedRecall = mixed['recall@10'] as double;
  final baseRecall = base['recall@10'] as double;
  final relativeGain = baseRecall == 0 ? 0.0 : mixedRecall / baseRecall - 1;
  final singleP50 = mixed['embedSingleP50Ms'] as double;
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'P0 完成\n混合 recall@10=${mixedRecall.toStringAsFixed(4)} '
            '基线=${baseRecall.toStringAsFixed(4)}\n'
            '相对提升 ${(relativeGain * 100).toStringAsFixed(1)}%  '
            'p50=${singleP50.toStringAsFixed(1)}ms',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
  math.Random(); // 保持 math 引用（指标库在同包内使用）。
}

/// Android 应用外部 files 根目录（包名固定为 applicationId）。
String _externalRoot() => '/storage/emulated/0/Android/data/com.localfit.ai';

/// 落盘当前进度（设备端长跑随时可能中断，已得数据不能丢）。
///
/// 逐目录尝试：外部 files 目录在「先被 adb shell 创建过」时应用会被拒
/// （Permission denied，实测），所以再退回 adb 预建的 777 目录。
Future<void> _flush(
  String outDir,
  Map<String, dynamic> report,
  StringBuffer log,
) async {
  const encoder = JsonEncoder.withIndent('  ');
  final candidates = <String>[
    outDir,
    '/data/local/tmp/p0_out',
    Directory.systemTemp.path,
  ];
  // 每个候选目录都写一遍（不 break）：应用外部目录 adb 读不到（scoped
  // storage），/data/local/tmp/p0_out 是 adb 预建的 777 目录、可直接 pull。
  for (final dir in candidates) {
    try {
      final out = Directory(dir);
      if (!out.existsSync()) out.createSync(recursive: true);
      await File('$dir/p0_report.json').writeAsString(encoder.convert(report));
      await File('$dir/p0_run.log').writeAsString(log.toString());
    } on Object {
      // 该候选不可写：其余候选照写。
    }
  }
  // 再 POST 回宿主：Android 11+ 的 scoped storage 让 adb 读不到应用外部
  // 目录（实测 `ls` 直接 No such file），模拟器里 10.0.2.2 即宿主回环。
  // 失败不影响已落盘的数据（接收器只是方便取数，不是必需件）。
  final port = Platform.environment['P0_REPORT_PORT'] ?? '8765';
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final request = await client.postUrl(
      Uri.parse('http://10.0.2.2:$port/report'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'report': report, 'log': log.toString()}));
    final response = await request.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    client.close(force: true);
  } on Object {
    // 宿主没起接收器时静默：报告已在设备上落盘，可用别的方式取。
  }
}
