import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A-5（docs/64）：餐食 / 食物 / 记忆三类**已有完整增改删**，这里只加一条
/// 回归：把「每类记录的增/改/删在 UI 上都可达」写成一张**静态扫描清单**，
/// 防止以后重构时又漏（与 C-1 的能力矩阵同一张表）。
///
/// 扫描方式与 C-1 一致：读 `lib/features/**/presentation/` 的源码文本，
/// 断言每条能力都能在 presentation 层找到它的调用点。**不引依赖、不跑运行时**。
void main() {
  final root = Directory('lib/features');
  final presentationSources = <File>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (!path.contains('/presentation/')) continue;
    if (!path.endsWith('.dart')) continue;
    presentationSources.add(entity);
  }
  // 路径解析失败时直接红（测试的前提坏了要比假绿好）。
  test('扫描前提：presentation 目录下有源码文件', () {
    expect(presentationSources, isNotEmpty);
  });

  /// (能力, 必须出现的调用点，格式 `文件:方法名`)。
  const capabilities = <String, List<String>>{
    // ── 餐食：增（记餐）/ 改（编辑弹层）/ 删（管理菜单，走 restore 撤销）──
    'meal.create': ['nutrition_actions.dart:meals.create'],
    'meal.update': ['nutrition_actions.dart:meals.update'],
    'meal.delete+restore': [
      'nutrition_actions.dart:repository.delete',
      'nutrition_actions.dart:repository.restore',
    ],
    // ── 食物库：增（新建食材弹层）/ 改（条目动作层）/ 删（条目动作层）──
    'food.create': ['nutrition_actions.dart:createFood'],
    'food.update': ['food_library_item_actions.dart:controller.updateFood'],
    'food.delete': ['food_library_item_actions.dart:controller.deleteFood'],
    // ── 记忆：添加（记忆页的添加流程走 save）/ 忘记（delete）──
    'memory.remember': ['ai_memory_page.dart:repository.remember'],
    'memory.forget': ['ai_memory_page.dart:repository.delete'],
    // ── 本轮补齐的四类（docs/64 阶段 1）：删 + 撤销在 presentation 可达 ──
    'water.add': ['dashboard_page.dart:repository.add'],
    'water.delete+restore': [
      'water_records_sheet.dart:repository.delete',
      'water_records_sheet.dart:repository.restore',
    ],
    'weight.saveManualWeight': [
      'dashboard_page.dart:repository.saveManualWeight',
    ],
    'weight.delete+restore': [
      'weight_records_sheet.dart:repository.delete',
      'weight_records_sheet.dart:repository.restore',
    ],
    // 2026-10-31：推荐卡的菜品删除菜单按用户要求退役，原
    // `dish.delete+restore` 行随之删除。替换为当前真实可达的「逐食物删除
    // +撤销」，防止能力清单继续声称一个已经不存在的入口。
    'meal.item.delete+restore': [
      'record_tab.dart:mealRepository.deleteItems',
      'nutrition_actions.dart:repository.restore',
    ],
    'session.deleteSet': ['training_page.dart:deleteSet'],
    'session.deleteSession': ['training_page.dart:deleteSession'],
  };

  for (final entry in capabilities.entries) {
    test('能力 ${entry.key}：UI 可达（presentation 有调用点）', () {
      final missing = <String>[];
      for (final marker in entry.value) {
        final colon = marker.indexOf('.dart:');
        final fileName = marker.substring(0, colon + 5);
        final symbol = marker.substring(colon + 6);
        final hit = presentationSources.any(
          (file) =>
              file.path.replaceAll('\\', '/').endsWith('/$fileName') &&
              file.readAsStringSync().contains(symbol),
        );
        if (!hit) missing.add(marker);
      }
      expect(
        missing,
        isEmpty,
        reason:
            '能力「${entry.key}」在 presentation 层找不到：${missing.join('、')}'
            '——删入口或撤销链断了，修回实现而不是改这条断言。',
      );
    });
  }
}
