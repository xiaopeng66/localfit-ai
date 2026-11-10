import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';

/// 【2026-10-30 实机缺陷】T11（2026-10-23）之前 CSV 导入走逐行 `create`，
/// 整批目录行被标成「自建」（is_user_created=1）——用户实机 2w+ 条目录
/// 全顶着「自建」。`backfillImportedFoodIdentity` 按**批量信号**回填：
/// 同一分钟创建 ≥ 30 行的桶 = 一次批量导入 → 翻成内置；孤立行（手动
/// 新建）保持自建。KV 门槛保证只跑一次。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 30, 8)),
    );
  });

  tearDown(() => database.close());

  /// 直接以**T11 前旧库形态**插行：is_user_created=1、source='user'、
  /// 同一分钟内连续 created_at（批量导入的时间指纹）。
  Future<void> seedImported({required int count, required DateTime at}) async {
    for (var i = 0; i < count; i++) {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'old-$i',
              name: '目录食物$i',
              defaultServingGrams: const Value(100),
              kcalPer100g: 100 + i.toDouble(),
              proteinPer100g: 5,
              carbsPer100g: 20,
              fatPer100g: 3,
              source: 'user',
              isUserCreated: const Value(true),
              state: const Value('user_created'),
              licenseStatus: const Value('unknown'),
              createdAt: at.add(Duration(seconds: i)),
              updatedAt: at.add(Duration(seconds: i)),
            ),
          );
    }
  }

  test('同一分钟 ≥30 行的桶翻成内置；孤立手动行保持自建', () async {
    // 一次「批量导入」：同一分钟 40 行。
    await seedImported(count: 40, at: DateTime.utc(2026, 9, 20, 10, 30));
    // 孤立手动新建（不同分钟）：保持自建。
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'manual-1',
            name: '手做的菜',
            kcalPer100g: 80,
            proteinPer100g: 4,
            carbsPer100g: 10,
            fatPer100g: 2,
            source: 'user',
            isUserCreated: const Value(true),
            state: const Value('user_created'),
            licenseStatus: const Value('unknown'),
            createdAt: DateTime.utc(2026, 10, 25, 18, 0),
            updatedAt: DateTime.utc(2026, 10, 25, 18, 0),
          ),
        );

    final flipped = await foods.backfillImportedFoodIdentity();
    expect(flipped, 40, reason: '批量桶整体翻成内置');

    final rows = await database.select(database.foods).get();
    final bulk = rows.where((r) => r.name.startsWith('目录食物'));
    final manual = rows.where((r) => r.name == '手做的菜');
    for (final row in bulk) {
      expect(row.isUserCreated, isFalse, reason: '${row.name} 应翻成内置');
      expect(row.source, 'import');
      expect(row.state, 'verified');
    }
    expect(manual.single.isUserCreated, isTrue, reason: '手动新建保持自建');
  });

  test('KV 门槛：只跑一次（第二次无行可翻）', () async {
    await seedImported(count: 30, at: DateTime.utc(2026, 9, 20, 10, 30));
    expect(await foods.backfillImportedFoodIdentity(), 30);
    // 再跑：行已经是内置，批量桶为空 → 0。
    expect(await foods.backfillImportedFoodIdentity(), 0);
  });

  test('批量桶不足 30 行（少量导入）不算批量，保持自建', () async {
    await seedImported(count: 5, at: DateTime.utc(2026, 9, 20, 10, 30));
    final flipped = await foods.backfillImportedFoodIdentity();
    expect(flipped, 0, reason: '少量手动建行不该被误翻（用户口径：App 内新建 = 自建）');
  });
}

final class _SeqIds implements IdGenerator {
  int value = 0;

  @override
  String next() => 'gen-${value++}';
}
