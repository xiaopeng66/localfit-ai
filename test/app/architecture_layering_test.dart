import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RV2-P2-03（`docs/52`）：feature 之间 66 条 import、7 组双向环。
///
/// 目标分层是「core → data → feature，跨 feature 只允许 domain 接口」。真正解环
/// 要抽 domain 接口包并改 20+ 文件，而本轮**无法**证明「解环后行为不变」
/// （没有 golden 帧、也没有跨 feature 集成网），所以按 `docs/54` 的结论：
/// **不做重构，改成不让它继续变坏**。
///
/// 本测试做三件事：
/// 1. **锁死现有边集**：新增任何跨 feature import（新边）立刻红；
/// 2. **锁死分层底线**：`lib/core` 与 `lib/data` 不得 import `lib/features`
///    （当前都是 0 条，这条必须一直是 0）；
/// 3. **只许减**：白名单里写了但代码里已不存在的边，也红——逼着收窄。
///
/// 这样「解环」可以分批做（每拆一条就删一行白名单），而不会一边拆一边又被
/// 加回来。
void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');

  /// 2026-10-22 冻结的跨 feature 依赖边（`from->to`）。
  /// 只许删，不许加；每条都对应一处真实 import。
  const frozenEdges = <String>{
    'ai->settings',
    'ai_conversation->ai',
    'ai_conversation->ai_memory',
    'ai_conversation->campus_menus',
    'ai_conversation->daily_plan',
    'ai_conversation->food_scan',
    'ai_conversation->hydration',
    'ai_conversation->menu_normalize',
    'ai_conversation->nutrition',
    'ai_conversation->onboarding',
    'ai_conversation->progress',
    'ai_conversation->retrieval',
    'ai_conversation->settings',
    'ai_conversation->training',
    'ai_memory->ai_conversation',
    'ai_memory->daily_plan',
    'ai_memory->jobs',
    'ai_memory->settings',
    'ai_workbench->ai',
    'backup->ai_conversation',
    'backup->ai_memory',
    'backup->campus_menus',
    'backup->food_scan',
    'backup->nutrition',
    'backup->retrieval',
    'campus_menus->backup',
    'campus_menus->menu_normalize',
    'campus_menus->nutrition',
    'dashboard->hydration',
    'dashboard->nutrition',
    'dashboard->progress',
    'dashboard->settings',
    'dashboard->training',
    'food_scan->ai',
    'food_scan->nutrition',
    'food_scan->progress',
    'food_scan->settings',
    'hydration->progress',
    'menu_normalize->ai',
    'nutrition->ai_conversation',
    'nutrition->campus_menus',
    'nutrition->daily_plan',
    'nutrition->dashboard',
    'nutrition->food_scan',
    'nutrition->progress',
    'nutrition->retrieval',
    'nutrition->settings',
    'progress->nutrition',
    'retrieval->ai_memory',
    'retrieval->campus_menus',
    'retrieval->jobs',
    'retrieval->nutrition',
    'retrieval->settings',
    'settings->ai',
    'settings->backup',
    'settings->hydration',
    'settings->nutrition',
    'settings->onboarding',
    'settings->progress',
    // 'settings->training' 2026-10-24 消失：删「数据来源与许可证」时一并去掉
    // 了 `exerciseDataAttributions` 的 import（那是它唯一用途）。
    // 白名单**只许收窄**，所以从冻结集里删除这条——66→64 之后再减一条。
    'training->ai',
    'training->dashboard',
    'training->nutrition',
    'training->settings',
  };

  final importPattern = RegExp(r'package:localfit_ai/features/([a-z_]+)/');

  Set<String> featureEdges() {
    final edges = <String>{};
    for (final entity in Directory(
      '$repoRoot/lib/features',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final parts = entity.uri.pathSegments;
      // lib/features/<src>/...
      final srcIndex = parts.indexOf('features');
      if (srcIndex < 0 || parts.length <= srcIndex + 1) continue;
      final src = parts[srcIndex + 1];
      final text = entity.readAsStringSync();
      for (final match in importPattern.allMatches(text)) {
        final dst = match.group(1)!;
        if (dst != src) edges.add('$src->$dst');
      }
    }
    return edges;
  }

  List<String> layerViolations(String layer) {
    final out = <String>[];
    final dir = Directory('$repoRoot/lib/$layer');
    if (!dir.existsSync()) return out;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('package:localfit_ai/features/')) {
        out.add(entity.path.replaceFirst('$repoRoot/', ''));
      }
    }
    return out;
  }

  test('跨 feature import 只许减：新增边必须先在 docs/54 里规划', () {
    final actual = featureEdges();

    final added = [
      for (final edge in actual)
        if (!frozenEdges.contains(edge)) edge,
    ]..sort();
    expect(
      added,
      isEmpty,
      reason:
          '新增了跨 feature 依赖：${added.join('、')}。'
          '请改走 domain 接口/回调，或先在 docs/54 里登记并说明为什么必须直连。',
    );

    final removed = [
      for (final edge in frozenEdges)
        if (!actual.contains(edge)) edge,
    ]..sort();
    expect(
      removed,
      isEmpty,
      reason:
          '这些边已经不存在了，请从 frozenEdges 里删掉（白名单只许收窄）：'
          '${removed.join('、')}',
    );
  });

  test('core 与 data 不得依赖 features（分层底线，当前都是 0）', () {
    expect(
      layerViolations('core'),
      isEmpty,
      reason: 'lib/core 不许 import features',
    );
    expect(
      layerViolations('data'),
      isEmpty,
      reason: 'lib/data 不许 import features',
    );
  });
}
