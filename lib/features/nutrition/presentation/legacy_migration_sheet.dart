import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 「旧数据怎么处理的」**可查看**（docs/67 §5.4）。
///
/// 方案里有一句硬话：保存在 JSON 里但界面永远读不到，不算保全完成。
/// 所以这里把 `legacy_entity_mappings` 摊开给用户看：
/// * 已转换 / 复用：去了哪条主食物；
/// * 待补全 / 冲突：为什么没换算、原值是什么；
/// * 原始资料：名称、原口径、原四项值、点评、图片路径、来源。
///
/// 只读：不提供"忽略 / 删除"这类会掩盖问题的动作。
final class LegacyMigrationSheet extends StatefulWidget {
  const LegacyMigrationSheet({super.key, required this.database});

  final AppDatabase database;

  static Future<void> show(BuildContext context, AppDatabase database) =>
      AppSheet.show<void>(
        context,
        title: '旧数据迁移记录',
        content: LegacyMigrationSheet(database: database),
      );

  @override
  State<LegacyMigrationSheet> createState() => _LegacyMigrationSheetState();
}

class _LegacyMigrationSheetState extends State<LegacyMigrationSheet> {
  Future<List<LegacyEntityMappingRow>>? _rows;

  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<List<LegacyEntityMappingRow>> _load() async {
    final rows = await widget.database
        .select(widget.database.legacyEntityMappings)
        .get();
    rows.sort((left, right) {
      final byOutcome = _rank(left.outcome).compareTo(_rank(right.outcome));
      if (byOutcome != 0) return byOutcome;
      return left.legacyKind.compareTo(right.legacyKind);
    });
    return rows;
  }

  static int _rank(String outcome) => switch (outcome) {
    'conflict' => 0,
    'needs_completion' => 1,
    'converted' => 2,
    'reused' => 3,
    _ => 4,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LegacyEntityMappingRow>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox(
            height: 120,
            child: Center(child: AppErrorText('迁移记录读取失败，请重试。')),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(LfDimens.spaceMedium),
            child: Text(
              '没有旧数据需要处理。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        final grouped = <String, List<LegacyEntityMappingRow>>{};
        for (final row in rows) {
          (grouped[row.outcome] ??= []).add(row);
        }
        return ListView(
          shrinkWrap: true,
          children: [
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: LfDimens.spaceSmall,
                  bottom: LfDimens.spaceTiny,
                ),
                child: Text(
                  '${_outcomeLabel(entry.key)}（${entry.value.length}）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final row in entry.value) _LegacyRow(row: row),
            ],
          ],
        );
      },
    );
  }

  static String _outcomeLabel(String outcome) => switch (outcome) {
    'converted' => '已换算进食物库',
    'reused' => '已复用现有食物',
    'needs_completion' => '待补全',
    'conflict' => '需要你确认',
    _ => outcome,
  };
}

class _LegacyRow extends StatelessWidget {
  const _LegacyRow({required this.row});

  final LegacyEntityMappingRow row;

  @override
  Widget build(BuildContext context) {
    final original = _decodePreserved(row.preservedJson);
    final name = original['name'] ?? original['displayName'] ?? row.legacyId;
    final kind = row.legacyKind == 'dish_library' ? '旧菜品' : '食堂供应';
    final details = <String>[
      if (original['basis'] != null)
        '原口径：${_basisLabel(original['basis'] as String?)}',
      if (original['servingGrams'] != null)
        '原每份：${original['servingGrams']}g'
      else if (row.originalServingGrams != null)
        '原每份：${row.originalServingGrams}g',
      if (original['kcal'] != null)
        '原值：${original['kcal']} kcal'
      else if (original['canteenEvidence'] is Map &&
          (original['canteenEvidence'] as Map)['kcalPer100g'] != null)
        '原值：${(original['canteenEvidence'] as Map)['kcalPer100g']} kcal/100g',
      if (original['comment'] != null && '${original['comment']}'.isNotEmpty)
        '点评：${original['comment']}',
      if (original['imagePath'] != null &&
          '${original['imagePath']}'.isNotEmpty)
        '原图：已保留路径',
      if (row.foodId != null) '主食物：${row.foodId}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$kind · $name', style: Theme.of(context).textTheme.bodyLarge),
          if (row.reasonText != null && row.reasonText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.reasonText!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                details.join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _decodePreserved(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // 保全资料损坏不该让整页打不开；下面按"没有可读字段"处理。
    }
    return const {};
  }

  static String _basisLabel(String? basis) => switch (basis) {
    'perServing' => '每一份',
    'per100g' => '每 100g',
    _ => basis ?? '未知',
  };
}
