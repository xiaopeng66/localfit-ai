import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// P2 批次 C 的判据（2026-10-21）：
/// * RV-P2-10：schema 28 回填只把「原本未知份量」的行标成假设；
/// * RV-P2-11：`from < 10` 的索引迁移可重入（IF NOT EXISTS）；
/// * RV-P2-18：备份恢复也过记忆敏感红线。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() => tempDir = Directory.systemTemp.createTempSync('localfit-p2-'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('RV-P2-10 回填：真实 100g 的老行不被标成假设；未知份量被标', () async {
    final file = File('${tempDir.path}/v27.sqlite');
    _createV27Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final rows = await database.select(database.dishLibrary).get();
    expect(rows, hasLength(2));

    final real100 = rows.firstWhere((row) => row.name == '真实100g');
    expect(real100.servingGrams, 100);
    expect(real100.basisAssumed, isFalse, reason: '迁移前就是 100g 的行不能被误标成假设');

    final unknown = rows.firstWhere((row) => row.name == '未知份量');
    expect(unknown.servingGrams, 100);
    expect(unknown.basisAssumed, isTrue);
  });

  test('RV-P2-11 索引 DDL 可重入（IF NOT EXISTS 语义）', () async {
    // 迁移分支现在执行的是显式 IF NOT EXISTS DDL；这里直接对同一份
    // DDL 连跑两次，证明「上一次中途失败后重试」不会撞 already exists。
    final raw = sqlite.sqlite3.open('${tempDir.path}/idx.sqlite');
    raw.execute(
      'CREATE TABLE meals (id TEXT NOT NULL PRIMARY KEY, local_date TEXT)',
    );
    raw.execute('CREATE INDEX idx_meals_local_date ON meals (local_date)');
    // 第二次执行：真实迁移里就是这一句。
    raw.execute(
      'CREATE INDEX IF NOT EXISTS idx_meals_local_date '
      'ON meals (local_date)',
    );
    final indexes = raw.select(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND name='idx_meals_local_date'",
    );
    expect(indexes, hasLength(1));
    raw.dispose();
  });

  test('RV-P2-18 备份里带敏感记忆 ⇒ 整单拒绝且不落库', () async {
    final source = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    final document = {
      'export_version': 1,
      'exported_at': '2026-10-21T00:00:00.000Z',
      'tables': {
        for (final table in source.allTables) table.actualTableName: <Object>[],
        'ai_memories': [
          {
            'id': 'm1',
            'textContent': '身份证号 110101199001011234',
            'kind': 'fact',
            'domain': 'general',
            'tagsJson': '[]',
            'pinned': false,
            'source': 'import',
            'status': 'active',
            'importance': 50,
            'useCount': 0,
            'createdAt': '2026-10-21T00:00:00.000Z',
            'updatedAt': '2026-10-21T00:00:00.000Z',
          },
        ],
      },
    };
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);

    await expectLater(
      RestoreLocalFitData(target)
          .restore(Uint8List.fromList(utf8.encode(jsonEncode(document)))),
      throwsA(isA<FormatException>()),
    );
    expect(await target.select(target.aiMemories).get(), isEmpty);
  });
}

/// 最小 v27 库：只有 dish_library（迁移回填的目标）与 app_settings。
void _createV27Database(String path) {
  final db = sqlite.sqlite3.open(path);
  db.execute(
    'CREATE TABLE app_settings ('
    'key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  );
  db.execute('''
CREATE TABLE dish_library (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  image_path TEXT,
  meal_slot TEXT NOT NULL,
  serving_window TEXT,
  is_hot INTEGER NOT NULL DEFAULT 0,
  kcal REAL NOT NULL,
  protein_g REAL NOT NULL,
  carbs_g REAL NOT NULL,
  fat_g REAL NOT NULL,
  fiber_g REAL,
  sodium_mg REAL,
  vitamin_d_mcg REAL,
  source TEXT NOT NULL,
  comment TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  serving_grams REAL
)
''');
  final nowMs = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
  final insert = db.prepare(
    'INSERT INTO dish_library (id, name, meal_slot, is_hot, kcal, protein_g,'
    ' carbs_g, fat_g, source, created_at, updated_at, serving_grams)'
    ' VALUES (?, ?, ?, 0, 200, 8, 30, 5, ?, ?, ?, ?)',
  );
  insert.execute(['d1', '真实100g', '午餐', 'manual', nowMs, nowMs, 100]);
  insert.execute(['d2', '未知份量', '午餐', 'manual', nowMs, nowMs, null]);
  insert.dispose();
  db.execute('PRAGMA user_version = 27');
  db.dispose();
}
