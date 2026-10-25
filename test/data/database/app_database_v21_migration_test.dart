import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/29 §P7（菜品照片 + 每日步数表，20→21 一次迁移）：
///  * v20 库的 `menu_items` 没有 `image_path` 列 ⇒ addColumn 补上，旧行
///    保持 null＝无照片，读取侧按「无图」渲染（诚实空态）；
///  * `steps_daily` 新表一建即全列（P9 接功能，本包只保证表在且形状对）；
///  * v1 库（`from < 12` 建表分支）一路升上来不抛错，`menu_items` 一建就
///    带全列（下界守卫防 duplicate column）。
///
/// **为什么不是 docs/29 原文写的 19→20**：v20 已被 P4 的 reasoning 列发给
/// 线上设备，`from < 20` 分支在已升级的库上不会再跑——往里加列等于没加，
/// 所以顺延为 20→21 新开一步（docs/21 §3.12 同日注记）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v21-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('upgrades a populated v20 database to v21 and adds imagePath', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV20Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    // ① 版本号走到**当前** schemaVersion（22 起迁移链在 v21 之后还会
    //    继续走减列那步——本测的是「20→21 这步发生了」，不是终点版本号）。
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);

    // ② imagePath 列已补上，且只有一列（下界守卫失效时会重复加列）。
    final columns = await database
        .customSelect('PRAGMA table_info(menu_items)')
        .get();
    final names = columns.map((row) => row.data['name']).toList();
    expect(names, contains('image_path'));
    expect(names.where((name) => name == 'image_path'), hasLength(1));

    // ③ steps_daily 已建，形状是「一天一行」：local_date 唯一。
    final stepsColumns = await database
        .customSelect('PRAGMA table_info(steps_daily)')
        .get();
    expect(
      stepsColumns.map((row) => row.data['name']),
      containsAll(['local_date', 'steps', 'source', 'recorded_at']),
    );
    await database
        .into(database.stepsDaily)
        .insert(
          StepsDailyCompanion.insert(
            id: 'steps-1',
            localDate: '2026-10-06',
            steps: 5234,
            source: 'health-platform',
            recordedAt: DateTime.utc(2026, 10, 6, 8),
            createdAt: DateTime.utc(2026, 10, 6, 8),
            updatedAt: DateTime.utc(2026, 10, 6, 8),
          ),
        );
    await expectLater(
      database
          .into(database.stepsDaily)
          .insert(
            StepsDailyCompanion.insert(
              id: 'steps-2',
              localDate: '2026-10-06',
              steps: 1,
              source: 'health-platform',
              recordedAt: DateTime.utc(2026, 10, 6, 9),
              createdAt: DateTime.utc(2026, 10, 6, 9),
              updatedAt: DateTime.utc(2026, 10, 6, 9),
            ),
          ),
      throwsA(anything),
      reason: '同一天重复写入必须撞唯一约束（一天一行的口径钉在 schema 上）',
    );

    // ④ 旧行一字不动（image_path 为 null＝无照片，不是空串也不是占位）。
    final row = await (database.select(
      database.menuItems,
    )..where((item) => item.id.equals('item-v20'))).getSingle();
    expect(row.displayName, '番茄炒蛋');
    // 2026-10-16（S8-b，用户删掉菜品价格）：升级到 v26 后 `price_minor`
    // 列必须**消失**（旧 fixture 里那行还写着 1200——见下面原生 SQL 建表）。
    final menuItemColumns = await database
        .customSelect("SELECT name FROM pragma_table_info('menu_items')")
        .get();
    expect(
      menuItemColumns.map((row) => row.read<String>('name')),
      isNot(contains('price_minor')),
      reason: 'v26 减法迁移要把价格列删掉',
    );
    expect(row.imagePath, isNull);

    // ⑤ 新写入走完整语义：照片路径原样落库、按菜品删除后随行消失。
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'item-new',
            serviceId: 'svc-v20',
            displayName: '红烧排骨',
            imagePath: const Value('/data/dish_images/dish_1.jpg'),
            createdAt: DateTime.utc(2026, 10, 6, 8),
            updatedAt: DateTime.utc(2026, 10, 6, 8),
          ),
        );
    final inserted = await (database.select(
      database.menuItems,
    )..where((item) => item.id.equals('item-new'))).getSingle();
    expect(inserted.imagePath, '/data/dish_images/dish_1.jpg');
  });

  test(
    'upgrades a trimmed v1 database straight to v21 without throwing',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createTrimmedV1Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], database.schemaVersion);

      // v1 库的 menu_items 由 `from < 12` 分支用**当前**表定义建出：一建
      // 就带 imagePath，`from < 21` 的 addColumn 必须被下界守卫跳过——
      // 若守卫写错（如去掉 from >= 12），这里会 duplicate column 崩溃。
      final columns = await database
          .customSelect('PRAGMA table_info(menu_items)')
          .get();
      final names = columns.map((row) => row.data['name']).toList();
      expect(names.where((name) => name == 'image_path'), hasLength(1));

      final hasStepsDaily = await database
          .customSelect(
            "SELECT 1 FROM sqlite_master "
            "WHERE type = 'table' AND name = 'steps_daily'",
          )
          .getSingleOrNull();
      expect(hasStepsDaily, isNotNull);
    },
  );

  test(
    'upgrades a v20 database that already has image_path without throwing',
    () async {
      // **设备走查抓到的真缺陷的回归**：本包开发期曾按 docs/29 原稿把
      // imagePath 放进 `from < 20` 分支（与 P4 同版），于是中途构建过的库
      // `user_version = 20` 但列已存在；只按版本区间判断会在真机上崩
      // `duplicate column name: image_path`。修法是按**列存在性**判断，
      // 这条用例钉住它：同一种库形态必须幂等走过。
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV20DatabaseWithImagePath(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], database.schemaVersion);

      final columns = await database
          .customSelect('PRAGMA table_info(menu_items)')
          .get();
      final names = columns.map((row) => row.data['name']).toList();
      expect(
        names.where((name) => name == 'image_path'),
        hasLength(1),
        reason: '列已存在时不能重复加（幂等）',
      );

      // 旧行的照片路径一字不动。
      final row = await (database.select(
        database.menuItems,
      )..where((item) => item.id.equals('item-v20'))).getSingle();
      expect(row.imagePath, '/data/old_dish.jpg');
    },
  );
}

/// 与 `_createV20Database` 同形，但 `menu_items` **已带** image_path
/// （开发中途构建的真实形态：user_version=20 且列已在）。
void _createV20DatabaseWithImagePath(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    database.execute('''
      CREATE TABLE menu_services (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        open_time TEXT NOT NULL,
        close_time TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE menu_items (
        id TEXT NOT NULL PRIMARY KEY,
        service_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        station_name TEXT NULL,
        price_minor INTEGER NULL,
        raw_text TEXT NULL,
        image_path TEXT NULL,
        evidence_grade TEXT NOT NULL DEFAULT 'D',
        item_status TEXT NOT NULL DEFAULT 'unresolved',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO menu_services
        VALUES ('svc-v20', '一楼快餐', '08:00', '13:30', 1780000000000, 1780000000000);
      INSERT INTO menu_items
        VALUES ('item-v20', 'svc-v20', '番茄炒蛋', NULL, 1200, NULL,
                '/data/old_dish.jpg', 'C', 'unresolved',
                1780000000000, 1780000000000);
      PRAGMA user_version = 20;
    ''');
  } finally {
    database.dispose();
  }
}

/// v20 线上库的相关部分：`menu_services` + `menu_items` 一行（**没有**
/// image_path 列，与 v20 的表定义一致）。
void _createV20Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    database.execute('''
      CREATE TABLE menu_services (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        open_time TEXT NOT NULL,
        close_time TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE menu_items (
        id TEXT NOT NULL PRIMARY KEY,
        service_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        station_name TEXT NULL,
        price_minor INTEGER NULL,
        raw_text TEXT NULL,
        evidence_grade TEXT NOT NULL DEFAULT 'D',
        item_status TEXT NOT NULL DEFAULT 'unresolved',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO menu_services
        VALUES ('svc-v20', '一楼快餐', '08:00', '13:30', 1780000000000, 1780000000000);
      INSERT INTO menu_items
        VALUES ('item-v20', 'svc-v20', '番茄炒蛋', NULL, 1200, NULL, 'C', 'unresolved', 1780000000000, 1780000000000);
      PRAGMA user_version = 20;
    ''');
  } finally {
    database.dispose();
  }
}

/// 裁剪过的 v1 库：只建迁移链会触碰到的表（仓库惯例；参见
/// `app_database_v20_migration_test.dart` 的 `_createTrimmedV1Database`）。
///
/// **刻意不建** menu_items / steps_daily —— 它们分别由 `from < 12` 与
/// `from < 21` 分支用当前表定义建出，这正是下界守卫要防的 duplicate
/// column 场景。
void _createTrimmedV1Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    const timestamp = 1780000000000;
    database.execute('''
      CREATE TABLE profiles (
        id TEXT NOT NULL PRIMARY KEY,
        birth_year INTEGER NULL,
        biological_sex TEXT NULL,
        height_cm REAL NULL,
        activity_level TEXT NOT NULL,
        dietary_preferences_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE foods (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        kcal_per100g REAL NOT NULL,
        protein_per100g REAL NOT NULL,
        carbs_per100g REAL NOT NULL,
        fat_per100g REAL NOT NULL,
        source TEXT NOT NULL,
        is_user_created INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE measurements (
        id TEXT NOT NULL PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id),
        local_date TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meals (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        eaten_at INTEGER NOT NULL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meal_items (
        id TEXT NOT NULL PRIMARY KEY,
        meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
        food_id TEXT NULL REFERENCES foods(id),
        food_name_snapshot TEXT NOT NULL,
        grams REAL NOT NULL,
        kcal_snapshot REAL NOT NULL,
        protein_snapshot REAL NOT NULL,
        carbs_snapshot REAL NOT NULL,
        fat_snapshot REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO profiles VALUES ('profile-v1', 1990, 'female', 165, 'moderate', '[]', $timestamp, $timestamp);
      INSERT INTO foods VALUES ('food-v1', '米饭', 116.0, 2.6, 25.9, 0.3, 'seed-v1', 0, $timestamp, $timestamp);
      INSERT INTO measurements VALUES ('measurement-v1', 'profile-v1', '2026-09-10', 70, $timestamp, $timestamp);
      INSERT INTO meals VALUES ('meal-v1', '2026-09-10', 'lunch', $timestamp, 'manual', $timestamp, $timestamp);
      INSERT INTO meal_items VALUES ('item-v1', 'meal-v1', 'food-v1', '米饭', 180, 209, 4.7, 46.5, 0.5, $timestamp, $timestamp);
      PRAGMA user_version = 1;
    ''');
  } finally {
    database.dispose();
  }
}
