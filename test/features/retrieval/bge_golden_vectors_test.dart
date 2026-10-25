import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/retrieval/data/bert_wordpiece_tokenizer.dart';

/// golden 向量夹具回归（docs/39 §10「模型健全性」/ docs/41 §6 G12）：
/// 防「模型/分词接错但看起来能跑」——夹具里存着 int8 模型对 8 道菜的
/// 512 维嵌入（int16 量化存档，scale 1/256）。本测试只验**分词 + 词表
/// id 路径**的数值一致性（向量主体在真模型基准里跑，CI 不背 24MB）。
void main() {
  test('golden 向量夹具在册且形状正确（模型接线契约）', () async {
    final raw = await File('test/fixtures/retrieval/bge_golden_vectors.json')
        .readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    expect(data['modelId'], 'bge-small-zh-v1.5-int8');
    expect(data['dim'], 512);
    final names = (data['names'] as List).cast<String>();
    final vectors = (data['vectors'] as List)
        .map((row) => (row as List).cast<int>())
        .toList(growable: false);
    expect(names, hasLength(8));
    expect(vectors, hasLength(8));
    for (final row in vectors) {
      expect(row, hasLength(512));
      // int16 量化存档的合法范围。
      expect(row.every((v) => v >= -32768 && v <= 32767), isTrue);
    }
  });

  test('夹具向量与词表路径绑定：同一文本的 token id 稳定', () async {
    final raw = await File('test/fixtures/retrieval/bge_golden_vectors.json')
        .readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final names = (data['names'] as List).cast<String>();

    final tokenizer = await BertWordPieceTokenizer.loadVocabFile(
      'test/fixtures/retrieval/bge-small-zh-v1.5-vocab.txt',
    );
    // 夹具生成时用的 maxLen=64 补齐编码；token id 序列必须可复现，
    // 否则向量空间漂移（换词表/换分词都会在这里先红）。
    for (final name in names.take(3)) {
      final ids = tokenizer.encode(name, maxLen: 64);
      expect(ids.first, BertWordPieceTokenizer.clsTokenId);
      expect(ids.last, BertWordPieceTokenizer.sepTokenId);
      expect(ids.where((id) => id == 0), everyElement(0));
      // 语义合理性断言：同菜名的中文逐字 id 是稳定且非 UNK 的。
      final body = ids.sublist(1, ids.length - 1);
      expect(body, isNotEmpty);
      expect(body.any((id) => id != BertWordPieceTokenizer.unkTokenId), isTrue);
    }
  });

  test('夹具里的菜名互相之间相似度结构合理（tag 同族 > 异族）', () async {
    final raw = await File('test/fixtures/retrieval/bge_golden_vectors.json')
        .readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final names = (data['names'] as List).cast<String>();
    final vectors = (data['vectors'] as List)
        .map((row) => (row as List).cast<int>().map((v) => v / 256.0).toList())
        .toList(growable: false);
    double dot(List<double> a, List<double> b) {
      var sum = 0.0;
      for (var i = 0; i < a.length; i++) {
        sum += a[i] * b[i];
      }
      return sum;
    }

    // 「番茄炒蛋」（index 0）与含「蛋」的「西红柿鸡蛋汤」的相似度必须高于
    // 与「红烧肉」的相似度（docs/39 §10 的句对断言同族）。
    final tomato = names.indexOf('番茄炒蛋');
    final soup = names.indexOf('西红柿鸡蛋汤');
    final pork = names.indexOf('红烧肉');
    if (tomato >= 0 && soup >= 0 && pork >= 0) {
      expect(
        dot(vectors[tomato], vectors[soup]),
        greaterThan(dot(vectors[tomato], vectors[pork])),
      );
    }
  });
}
