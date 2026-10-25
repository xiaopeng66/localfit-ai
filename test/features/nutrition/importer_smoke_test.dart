import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';

/// 用户 8 列 xlsx 转出 CSV 的**真实导入冒烟**（docs 之外的临时验证，跑一次留档）。
///
/// 夹具是**随包资产** `assets/seed/user_foods_8col.v1.csv`（21 列契约子集：
/// 食品ID/品牌/食物名称/一级分类/四项营养）。2026-10-20 审查 RV-P1-16：
/// 原先读仓库外的临时转换产物，临时目录被清理后门禁直接掉红——门禁必须自包含。
/// 判据：23,919 行全部可解析（0 错误）；**归一化名称后**有 3 组「同一食物被写了
/// 两遍」的源数据（重复前缀），按（名称, 品牌）判重后新增 23,916、文件内重复 3：
/// `鸭脖鸭脖/鸭脖`（绝味）、`紫菜紫菜/紫菜`（四洲）、`明珠明珠甘栗仁/明珠甘栗仁`（燕山）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('冒烟：用户 8 列食物库转换 CSV 被真实导入器全量吃下', () async {
    final csv = File('assets/seed/user_foods_8col.v1.csv');
    if (!csv.existsSync()) {
      fail('缺随包 CSV：assets/seed/user_foods_8col.v1.csv（应由 pubspec 随包）');
    }
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = FoodRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    );
    final importer = FoodCsvImporter(repository: repository);

    final preview = await importer.preview(csv.readAsBytesSync());
    expect(preview.errorCount, 0, reason: '全部行都应通过校验');
    // ADR-037：名称固定格式会把「鸭脖鸭脖」收成「鸭脖」，于是这 3 组在
    // （名称, 品牌）上**本来就该是同一条**——判重是正确行为，不是丢数据。
    expect(preview.newCount, 23916, reason: '全新内存库：23,919 − 3 组重复前缀');
    expect(preview.duplicateCount, 3);
    expect(preview.duplicates.map((duplicate) => duplicate.name).toSet(), {
      '鸭脖',
      '紫菜',
      '明珠甘栗仁',
    });
    expect(preview.newFoods.first.brand, isNull, reason: '乳类行无品牌');

    final result = await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    expect(result.imported, 23916);
    expect(result.failed, 0);

    final count = await (db.selectOnly(
      db.foods,
    )..addColumns([db.foods.id.count()])).getSingle();
    expect(count.read(db.foods.id.count()), 23916);
  });
}
