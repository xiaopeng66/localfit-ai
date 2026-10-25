import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';

/// 需求 75 / docs/32 §4 T13：**不再随包内置食物种子**。
///
/// 这条纪律要同时钉住三个高度，缺任何一个都会退化：
///   1. **仓库里没有**：文件、pubspec 声明、构建脚本都不再提它（静态面）。
///      文件级清单由 `test/privacy/privacy_statement_audit_test.dart` 的
///      「随包种子文件就是审计过的这三个」兜住，这里不重复那份白名单；
///   2. **运行时真的没有**：`rootBundle` 取不到这两个路径——pubspec 声明删了
///      却忘了删文件、或者反过来，打包时会静默缺文件，这条会先红；
///   3. **没有被顺手读回来**：测试过去到处用真实种子当 fixture（26 个测试文件
///      里喂的是 v5 的 49,444 条），退役后如果谁又写一句「顺手读个种子」，
///      静态扫描那一条会红——而不是等到真机首启慢 842 ms 才发现。
///
/// 历史数据本身没删：归档在仓库外的 `../archive/food-seed-2026-10-13/`
/// （见那里的 README 与 `tool/food_seed/README.md` 的退役说明）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('退役的食物种子不再随包：rootBundle 取不到 v4/v5', () async {
    // pubspec 声明与打包内容必须一致：声明在而文件没了 → 打包报错；
    // 文件在而声明没了 → 打包静默少文件。两个都不许出现，所以这里以
    // 「运行时取不到」为准来断言「不再随包」。
    for (final path in const [
      'assets/seed/foods.v4.json',
      'assets/seed/foods.v5.json',
    ]) {
      await expectLater(
        rootBundle.loadString(path),
        throwsA(isA<FlutterError>()),
        reason: '$path 不该还在包里（退役：docs/32 §4 T13）',
      );
    }
  });

  test('随包的种子资产仍是可读的（上一条不是因为 bundle 整个坏了）', () async {
    // 反向对照：同一时刻、同一个 rootBundle，动作种子必须照旧读得到。
    // 少了这条，上面那条在「bundle 坏掉/路径写错」时也会通过。
    final exercises = jsonDecode(
      await rootBundle.loadString('assets/seed/exercises.v3.json'),
    ) as Map<String, Object?>;
    expect(exercises['version'], 3);
  });

  test('全新库跑完随包导入路径：foods 是空的，动作库照旧导入', () async {
    final database = AppDatabase(NativeDatabase.memory());
    // 随包导入路径现在只有动作库这一条（main.dart 里食物那一行已删）。
    await const ExerciseSeedImporter().importIfNeeded(database);

    expect(
      await database.select(database.foods).get(),
      isEmpty,
      reason: '不该有任何内置食物写进新库',
    );
    expect(await database.select(database.exercises).get(), hasLength(312));

    await database.close();
  });

  test('lib/ 里没有任何代码再加载退役种子（防止静默复活）', () {
    final root = Directory.current.path;
    final offenders = <String>[];
    for (final entity in Directory('$root/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceFirst('$root/', '').replaceAll('\\', '/');
      final source = entity.readAsStringSync();
      // 注释里记来源出处是**允许**的（`food_seed_count.g.dart`、`food_brands*.g.dart`
      // 等生成文件都写着种子路径与 sha256，那是历史交代），所以这里只找代码里的
      // 东西：资产的带引号字面量，以及退役导入器的类名。
      if (source.contains('FoodSeedImporter') ||
          source.contains("'assets/seed/foods") ||
          source.contains('"assets/seed/foods')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '退役的食物种子不该再被代码引用（docs/32 §4 T13）：$offenders',
    );
  });
}
