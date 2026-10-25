import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';

import '../../support/food_fixture.dart';

/// RV-P1-01：**旧备份必须能恢复**——schema 28 新增的非空列在旧包里不存在。
///
/// 这条模拟的是「用户用 v27 时代的 App 导出的包，装上新版后恢复」：
/// 把当前导出里的 schema-28/29 新键删掉，再恢复。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase source;

  setUp(() async {
    source = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(source);
  });

  tearDown(() => source.close());

  test('缺 schema 28 新列的旧包可以恢复，默认值落库', () async {
    final now = DateTime.utc(2026, 10, 20, 4);
    await source
        .into(source.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await source
        .into(source.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-10-20',
            slot: 'lunch',
            eatenAt: now,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await source
        .into(source.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-1',
            mealId: 'meal-1',
            foodNameSnapshot: '米饭',
            grams: 150,
            kcalSnapshot: 174,
            proteinSnapshot: 3.9,
            carbsSnapshot: 38.9,
            fatSnapshot: 0.5,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await source
        .into(source.aiMemories)
        .insert(
          AiMemoriesCompanion.insert(
            id: 'memory-1',
            textContent: '周三晚上练腿',
            kind: 'habit',
            domain: 'training',
            source: 'explicit',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final exported = jsonDecode(
      utf8.decode(await ExportLocalFitData(source).exportJson()),
    ) as Map<String, dynamic>;
    final tables = exported['tables'] as Map<String, dynamic>;

    // 旧包缺的键（schema 28/29 之后新增的非空列）。
    for (final row in (tables['meal_items'] as List)) {
      (row as Map<String, dynamic>).remove('sourceType');
    }
    for (final row in (tables['ai_memories'] as List)) {
      (row as Map<String, dynamic>)
        ..remove('importance')
        ..remove('useCount');
    }

    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    await RestoreLocalFitData(target).restore(_bytesOf(exported));

    final item = (await target.select(target.mealItems).get()).single;
    expect(item.foodNameSnapshot, '米饭');
    expect(item.sourceType, 'manual', reason: '旧包缺列 ⇒ 走默认值，不是恢复失败');
    final memory = (await target.select(target.aiMemories).get()).single;
    expect(memory.textContent, '周三晚上练腿');
    expect(memory.importance, 50);
    expect(memory.useCount, 0);
  });

  test('缺菜品库 schema 28 列的旧包也能恢复', () async {
    final now = DateTime.utc(2026, 10, 20, 4);
    await source
        .into(source.dishLibrary)
        .insert(
          DishLibraryCompanion.insert(
            id: 'dish-1',
            name: '番茄牛腩饭',
            mealSlot: 'lunch',
            kcal: 200,
            proteinG: 8,
            carbsG: 30,
            fatG: 5,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final exported = jsonDecode(
      utf8.decode(await ExportLocalFitData(source).exportJson()),
    ) as Map<String, dynamic>;
    final tables = exported['tables'] as Map<String, dynamic>;
    for (final row in (tables['dish_library'] as List)) {
      (row as Map<String, dynamic>)
        ..remove('nutritionBasis')
        ..remove('basisAssumed')
        ..remove('userEdited');
    }

    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    await RestoreLocalFitData(target).restore(_bytesOf(exported));

    final dish = (await target.select(target.dishLibrary).get()).single;
    expect(dish.name, '番茄牛腩饭');
    expect(dish.nutritionBasis, 'perServing');
    expect(dish.basisAssumed, isTrue, reason: '旧行份量未知 ⇒ 标「按 100g 估算」');
    expect(dish.userEdited, isFalse);
  });
}

/// 把导出 JSON 重新编码成 `restore` 收的字节（测试内小工具）。
Uint8List _bytesOf(Map<String, dynamic> document) =>
    Uint8List.fromList(utf8.encode(jsonEncode(document)));
