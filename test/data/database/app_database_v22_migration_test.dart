import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/31 S2（21→22 一次迁移）：**数据层瘦身** —— 删体脂率/肌肉量/
/// 食物侧过敏原三列。这是本仓第一次**减列**迁移（此前 21 版全是加表/加列），
/// 所以本文件要钉住的不只是「列没了」，还有减法特有的三条：
///
///  * **其余列一字不动**：DROP COLUMN 在 SQLite 里是「重建表 + 拷数据」，
///    写错就可能丢掉没点名的列或行的默认值；
///  * **数据保住**：体重、日期、来源、备注、时间戳必须原样留下
///    （删的是「这次称重有没有量体脂」，不是「这次称重」本身）；
///  * **幂等**：列已不在的库再跑一遍不许抛错（`DROP COLUMN` 不带
///    `IF EXISTS`，第二次会 `no such column`）——按列存在性判断，与
///    v21 的 image_path 同一套判据。
///
/// 另有一条**备份兼容**的事实断言：旧 `.lfb` 包里的这两个键在恢复时被
/// 忽略并丢弃（drift 的 fromJson 只读 `data` 里认得的列），**不报错**。
/// 这是「删数据」的事实，钉在测试里免得下一轮又有人以为「旧包还能带回体脂」。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v22-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrades a populated v21 database to v22 and drops the three columns',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV21Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      // ① 版本号走到当前 schema（单一事实源，不写死 22 —— 下一次加版本时
      //    这条不该过期）。
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], database.schemaVersion);

      // ② 两个体成分列**不在** measurements 里了。
      final measurementColumns = await database
          .customSelect('PRAGMA table_info(measurements)')
          .get();
      final measurementNames = measurementColumns
          .map((row) => row.data['name'])
          .toList();
      expect(
        measurementNames,
        isNot(contains('body_fat_percent')),
        reason: '体脂率列必须被 drop（需求 45/46）',
      );
      expect(
        measurementNames,
        isNot(contains('muscle_mass_kg')),
        reason: '肌肉量列必须被 drop（需求 45/46）',
      );
      // ① 反面：**其余列一个都不许少**（减法迁移最容易误伤这里）。
      expect(
        measurementNames,
        containsAll(<String>[
          'id',
          'profile_id',
          'local_date',
          'weight_kg',
          'source',
          'notes',
          'created_at',
          'updated_at',
        ]),
        reason: 'DROP COLUMN 是重建表，别的列不许跟着掉',
      );

      // ③ 食物侧三个过敏原/饮食标签列**不在** foods 里了（需求 50）。
      final foodColumns = await database
          .customSelect('PRAGMA table_info(foods)')
          .get();
      final foodNames = foodColumns.map((row) => row.data['name']).toList();
      expect(foodNames, isNot(contains('allergens_json')));
      expect(foodNames, isNot(contains('dietary_labels_json')));
      expect(foodNames, isNot(contains('constraint_knowledge')));
      expect(
        foodNames,
        containsAll(<String>[
          'id',
          'name',
          'brand',
          'kcal_per_100g',
          'protein_per_100g',
          'carbs_per_100g',
          'fat_per_100g',
          'source',
          'is_user_created',
          'state',
          'category',
        ]),
        reason: '食物侧的四大指标/品牌/种类等列一个都不许少',
      );

      // ④ 体重的数据一字不动（删的是体成分两列，不是那条称重记录）。
      final row = (await database.select(database.measurements).get()).single;
      expect(row.id, 'm-v21');
      expect(row.weightKg, 69.4);
      expect(row.localDate, '2026-10-08');
      expect(row.source, 'manual');
      expect(row.notes, '早上称的');

      // ⑤ 迁移后仍可写读：新行不再需要那两个字段。
      await database
          .into(database.measurements)
          .insert(
            MeasurementsCompanion.insert(
              id: 'm-new',
              profileId: 'p-1',
              localDate: '2026-10-09',
              weightKg: 69.0,
              createdAt: DateTime(2026, 10, 9),
              updatedAt: DateTime(2026, 10, 9),
            ),
          );
      expect(
        (await database.select(database.measurements).get()),
        hasLength(2),
      );
    },
  );

  test(
    'is idempotent on a database whose columns are already dropped',
    () async {
      // 与 v21 的 image_path 同一种真实形态：开发中途构建过的库，
      // user_version 还没升但列已经没了。按列存在性判断才走得过去。
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV21DatabaseWithoutBodyComposition(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], database.schemaVersion);

      final columns = await database
          .customSelect('PRAGMA table_info(measurements)')
          .get();
      expect(
        columns
            .map((row) => row.data['name'])
            .where(
              (name) => name == 'body_fat_percent' || name == 'muscle_mass_kg',
            ),
        isEmpty,
      );
      // 数据仍在（幂等路径不许把表重建坏）。
      expect(
        (await database.select(database.measurements).get()).single.weightKg,
        69.4,
      );
    },
  );

  test(
    'a legacy .lfb row carrying body-fat keys restores with those keys dropped',
    () async {
      // **备份兼容的如实事实**：`.lfb` 的行是 drift 生成的 `toJson/fromJson`
      // 形状（camelCase 字段名，不是 SQL 的 snake_case 列名 —— 这里踩过：
      // 写成 `body_fat_percent` 时 `fromJson` 读不到 `bodyFatPercent`
      // 以外的必需列，直接抛 Null cast）。**没有列级版本门**：旧包里的
      // `bodyFatPercent` / `muscleMassKg` 两个键在 v22 的 `fromJson` 里
      // 根本不被读取，**静默忽略并丢弃**，不报错。
      // 钉住它，免得后来者以为「旧包还能把体脂带回来」，也免得有人以为
      // 「旧包会因此导不进来」。
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      final database = AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      final legacyJson = <String, dynamic>{
        'id': 'm-legacy',
        'profileId': 'p-1',
        'localDate': '2026-10-08',
        'weightKg': 69.4,
        // 下面两个键是 v21 及更早的包会带上的；v22 起认不得它们。
        'bodyFatPercent': 18.2,
        'muscleMassKg': 31.5,
        'source': 'manual',
        'notes': null,
        'createdAt': 1000,
        'updatedAt': 1000,
      };
      final restored = Measurement.fromJson(legacyJson);

      expect(restored.weightKg, 69.4, reason: '认得的列照常恢复');
      // measurements.profile_id 外键指向 profiles —— 先造父行再插。
      await database
          .into(database.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'p-1',
              activityLevel: 'moderate',
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          );
      await database.into(database.measurements).insert(restored);
      final rows = await database.select(database.measurements).get();
      expect(rows.single.weightKg, 69.4);
      // 表里根本没有那两列 —— 所以「丢弃」不是选择，是物理事实。
      final columns = await database
          .customSelect('PRAGMA table_info(measurements)')
          .get();
      expect(
        columns.map((row) => row.data['name']),
        isNot(contains('body_fat_percent')),
      );
    },
  );
}

/// 造一个**有数据的 v21 库**：measurements 带两个体成分列（v22 要删它们），
/// foods 带三个过敏原/饮食标签列（v22 要删它们）。fixture 按仓库惯例是
/// 最小复现：只建迁移要触碰的两张表 + 外键父表桩。
void _createV21Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    database.execute('PRAGMA user_version = 21');
    database.execute('''
CREATE TABLE measurements (
  id TEXT NOT NULL PRIMARY KEY,
  profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  weight_kg REAL NOT NULL,
  body_fat_percent REAL NULL,
  muscle_mass_kg REAL NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  notes TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    database.execute(
      "INSERT INTO measurements (id, profile_id, local_date, weight_kg, "
      "body_fat_percent, muscle_mass_kg, source, notes, created_at, updated_at) "
      "VALUES ('m-v21', 'p-1', '2026-10-08', 69.4, 18.2, 31.5, 'manual', "
      "'早上称的', 1000, 1000)",
    );
    database.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  brand TEXT NULL,
  default_serving_grams REAL NULL,
  kcal_per_100g REAL NOT NULL,
  protein_per_100g REAL NOT NULL,
  carbs_per_100g REAL NOT NULL,
  fat_per_100g REAL NOT NULL,
  source TEXT NOT NULL,
  is_user_created INTEGER NOT NULL DEFAULT 0,
  constraint_knowledge TEXT NOT NULL DEFAULT 'unknown',
  dietary_labels_json TEXT NOT NULL DEFAULT '[]',
  allergens_json TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'verified',
  locale TEXT NULL,
  category TEXT NULL,
  source_version INTEGER NULL,
  license_status TEXT NOT NULL DEFAULT 'unknown'
);
''');
    database.execute(
      "INSERT INTO foods (id, name, kcal_per_100g, protein_per_100g, "
      "carbs_per_100g, fat_per_100g, source, constraint_knowledge, "
      "dietary_labels_json, allergens_json, created_at, updated_at) VALUES "
      "('f-1', '鸡蛋', 144, 13.3, 2.8, 8.8, 'seed-v5', 'known', "
      "'[\"vegetarian\"]', '[\"egg\"]', 1000, 1000)",
    );
    // 外键父表最小桩。
    database.execute('CREATE TABLE profiles (id TEXT NOT NULL PRIMARY KEY)');
    database.execute("INSERT INTO profiles (id) VALUES ('p-1')");
  } finally {
    database.dispose();
  }
}

/// 同形，但两个体成分列**已经**不在（开发中途构建的真实形态）。
void _createV21DatabaseWithoutBodyComposition(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    database.execute('PRAGMA user_version = 21');
    database.execute('''
CREATE TABLE measurements (
  id TEXT NOT NULL PRIMARY KEY,
  profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  weight_kg REAL NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  notes TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    database.execute(
      "INSERT INTO measurements (id, profile_id, local_date, weight_kg, "
      "created_at, updated_at) VALUES ('m-v21', 'p-1', '2026-10-08', 69.4, "
      '1000, 1000)',
    );
    database.execute('CREATE TABLE foods (id TEXT NOT NULL PRIMARY KEY)');
    database.execute('CREATE TABLE profiles (id TEXT NOT NULL PRIMARY KEY)');
  } finally {
    database.dispose();
  }
}
