import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/presentation/legacy_migration_sheet.dart';

/// 旧数据「原始资料」必须**在界面上读得到**（docs/67 §5.4）。
///
/// 方案原话：保存在 JSON 里但界面永远读不到，不算保全完成。这里钉住：
/// 待补全原因上屏、原口径/原值/点评/图片路径可见、已转换项能看出去了哪。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> insertMapping({
    required String id,
    required String kind,
    required String outcome,
    String? reasonCode,
    String? reasonText,
    String? foodId,
    String? preserved,
  }) async {
    final now = DateTime.utc(2026, 11, 9);
    await database
        .into(database.legacyEntityMappings)
        .insert(
          LegacyEntityMappingsCompanion.insert(
            id: id,
            legacyKind: kind,
            legacyId: id,
            sourceFingerprint: 'fp-$id',
            conversionVersion: 'legacy-nutrition-v1',
            outcome: outcome,
            originalBasis: 'perServing',
            preservedJson: preserved ?? '{}',
            createdAt: now,
            updatedAt: now,
            reasonCode: Value(reasonCode),
            reasonText: Value(reasonText),
            foodId: Value(foodId),
          ),
        );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: LegacyMigrationSheet(database: database)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('待补全项：原因与原值都上屏', (tester) async {
    await insertMapping(
      id: 'd1',
      kind: 'dish_library',
      outcome: 'needs_completion',
      reasonCode: 'assumed_serving',
      reasonText: '旧记录只有"一份"营养，份量是历史假设的 100g，不能据此换算每 100 g。',
      preserved: jsonEncode({
        'name': '宫保鸡丁',
        'basis': 'perServing',
        'servingGrams': 100,
        'basisAssumed': true,
        'kcal': 400,
        'comment': '偏油',
        'imagePath': '/data/docs/localfit_ai/dish_images/a.jpg',
      }),
    );
    await pump(tester);

    expect(find.textContaining('待补全（1）'), findsOneWidget);
    expect(find.textContaining('宫保鸡丁'), findsOneWidget);
    expect(find.textContaining('不能据此换算每 100 g'), findsOneWidget);
    expect(find.textContaining('原口径：每一份'), findsOneWidget);
    expect(find.textContaining('原值：400 kcal'), findsOneWidget);
    expect(find.textContaining('点评：偏油'), findsOneWidget);
    expect(find.textContaining('原图：已保留路径'), findsOneWidget);
  });

  testWidgets('已转换项：能看出去了哪条主食物', (tester) async {
    await insertMapping(
      id: 'd2',
      kind: 'dish_library',
      outcome: 'converted',
      foodId: 'food-1',
      preserved: jsonEncode({
        'name': '番茄炒蛋',
        'basis': 'perServing',
        'servingGrams': 200,
        'kcal': 240,
      }),
    );
    await pump(tester);
    expect(find.textContaining('已换算进食物库（1）'), findsOneWidget);
    expect(find.textContaining('主食物：food-1'), findsOneWidget);
  });

  testWidgets('空台账：给出可读空态，不是空白页', (tester) async {
    await pump(tester);
    expect(find.text('没有旧数据需要处理。'), findsOneWidget);
  });

  testWidgets('保全 JSON 损坏：页面仍可用', (tester) async {
    await insertMapping(
      id: 'd3',
      kind: 'menu_item',
      outcome: 'conflict',
      reasonCode: 'source_changed',
      reasonText: '旧记录在上次归一之后又被改过，需要重新确认。',
      preserved: '{not json',
    );
    await pump(tester);
    expect(find.textContaining('需要你确认（1）'), findsOneWidget);
    expect(find.textContaining('需要重新确认'), findsOneWidget);
  });
}
