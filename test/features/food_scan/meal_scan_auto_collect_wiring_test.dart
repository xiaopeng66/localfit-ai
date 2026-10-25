import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production wiring persists unmatched AI food estimates locally', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('createFood: foodRepository.create'),
      reason: '未匹配候选必须接入 FoodRepository.create 才能自动收录到本地食物库',
    );
  });
}
