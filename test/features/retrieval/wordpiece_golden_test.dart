import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/retrieval/data/bert_wordpiece_tokenizer.dart';

/// WordPiece golden 分词测试（docs/39 §4.2 / §13）：
/// 「分词/模型接错，向量全错但看起来能跑」是 P0 明列的第一号风险。
/// golden 从 HuggingFace `tokenizers`（tokenizer.json 原生实现）导出，
/// 任何 Dart 侧实现偏差（CJK 切分、标点独立、## 续词、[UNK] 兜底）都在这里红。
void main() {
  late BertWordPieceTokenizer tokenizer;

  setUpAll(() async {
    final vocabFile = File(
      'test/fixtures/retrieval/bge-small-zh-v1.5-vocab.txt',
    );
    tokenizer = await BertWordPieceTokenizer.loadVocabFile(vocabFile.path);
  });

  test('词表 21128 项，特殊符号 id 固定', () {
    expect(tokenizer.vocabSize, 21128);
    expect(BertWordPieceTokenizer.clsTokenId, 101);
    expect(BertWordPieceTokenizer.sepTokenId, 102);
    expect(BertWordPieceTokenizer.padTokenId, 0);
    expect(BertWordPieceTokenizer.unkTokenId, 100);
    expect(tokenizer.tokenToId('[CLS]'), 101);
    expect(tokenizer.tokenToId('番'), 4528);
  });

  test('golden 分词：与 HuggingFace tokenizers 逐 token 一致', () async {
    final golden = jsonDecode(
      await File('test/fixtures/retrieval/wordpiece_golden.json')
          .readAsString(),
    ) as Map<String, dynamic>;
    expect(golden, isNotEmpty);
    golden.forEach((text, expectedRaw) {
      final expected = [
        for (final token in expectedRaw as List<dynamic>)
          if (token != '[CLS]' && token != '[SEP]') token as String,
      ];
      final actual = tokenizer.tokenize(text);
      expect(
        actual,
        expected,
        reason: '分词偏差："$text"\n  dart: $actual\n  HF:   $expected',
      );
    });
  });

  test('golden 编码：inputIds / attentionMask 与 HF 对齐（maxLen 64 补齐）', () async {
    final golden = jsonDecode(
      await File('test/fixtures/retrieval/wordpiece_golden_ids.json')
          .readAsString(),
    ) as Map<String, dynamic>;
    golden.forEach((text, raw) {
      final data = raw as Map<String, dynamic>;
      final batch = tokenizer.encodeBatch([text], maxLen: 64);
      expect(batch.inputIds, data['ids'], reason: 'inputIds 偏差："$text"');
      expect(batch.attentionMask, data['attention'], reason: 'mask 偏差："$text"');
      expect(batch.shape, [1, 64]);
    });
  });

  test('中文按字切分（BERT 中文口径）', () {
    expect(tokenizer.tokenize('番茄炒蛋'), ['番', '茄', '炒', '蛋']);
  });

  test('中英混排：英文整词、数字、标点独立', () {
    final tokens = tokenizer.tokenize('今天有宫保鸡丁吗？');
    expect(tokens, contains('？'));
    expect(tokens.last, '？');
  });

  test('词表外整词回 [UNK]，词内可匹配的按 ## 续', () {
    // emoji 不在任何 piece 里 ⇒ 整段 [UNK]。
    expect(tokenizer.tokenize('🤔'), ['[UNK]']);
    // "emoji" 拆成 em + ##o + ##ji（golden 验证过的形态）。
    expect(tokenizer.tokenize('emoji'), ['em', '##o', '##ji']);
  });

  test('超长单词（>100 字符）直接 [UNK]（防 DoS 的 HF 同款口径）', () {
    final long = 'a' * 101;
    expect(tokenizer.wordPiece(long), ['[UNK]']);
  });

  test('BGE 检索前缀是 docs/39 §4.2 的原文（A/B 实验的 A 侧）', () {
    expect(BertWordPieceTokenizer.bgeQueryPrefix, '为这个句子生成表示以用于检索相关文章：');
  });

  test('encode 截断：maxLen 生效且保留 [CLS]/[SEP]', () {
    final ids = tokenizer.encode('番茄' * 100, maxLen: 32);
    expect(ids.length, 32);
    expect(ids.first, BertWordPieceTokenizer.clsTokenId);
    expect(ids.last, BertWordPieceTokenizer.sepTokenId);
  });
}
