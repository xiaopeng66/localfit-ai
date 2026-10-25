import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/21 §7.2/§7.4：schema 16 → 17 迁移。
///
/// 造一个**有数据的 v16 库** → 迁移 → 断言「只增不改不删」：
///  * 既有 measurements 行原样保留（**体重**那一列；体成分两列见下）；
///  * 7 张新表全部可用（建行 → 读回）；
///  * 新表行数从 0 开始（不冒充历史数据）。
///
/// **2026-10-09（docs/31 S2）改口径**：v17 当年给 measurements 加的
/// `muscle_mass_kg` 列，在 schema 22 又被删了。所以本用例的终点不再是
/// 「muscleMassKg 列在且为 null」，而是**「走完 v16→当前 的完整链之后，
/// 那一列已经不在了，而体重数据完好」**——「只增不改不删」这句描述的是
/// **v17 那一步**的历史意图，不描述终点形状。
///
/// fixture 按仓库惯例是最小复现，且 v16 的 DDL **照历史原样保留**
/// （含 body_fat_percent）：fixture 是「那个版本的真实形状」，不是当前列清单。
/// 只有「断言迁移后列仍在」的那几句要按新终点改。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v17-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrades a populated v16 database to v17 with the new-domain tables',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV16Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
      });

      // ① 旧数据完整：measurement 行的**体重**原样保留。
      //    体成分两列已随 schema 22 删除（docs/31 S2）——下面单独断言
      //    「列真的没了」，而不是像旧版那样断言它们的值。
      final measurement =
          (await database.select(database.measurements).get()).single;
      expect(measurement.id, 'm-v16');
      expect(measurement.weightKg, 69.4);
      final measurementColumns = await database
          .customSelect('PRAGMA table_info(measurements)')
          .get();
      final measurementNames = measurementColumns
          .map((row) => row.data['name'])
          .toList();
      expect(measurementNames, isNot(contains('body_fat_percent')));
      expect(measurementNames, isNot(contains('muscle_mass_kg')));

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      // 终点是当前 schemaVersion（v18 → 19 只删表，见 docs/28 §6.5）。
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);

      // ② 新表可用：逐表建行并读回。
      await database
          .into(database.waterIntakes)
          .insert(
            WaterIntakesCompanion.insert(
              id: 'w-1',
              localDate: '2026-09-28',
              amountMl: 250,
              recordedAt: DateTime(2026, 9, 28, 10),
              createdAt: DateTime(2026, 9, 28, 10),
              updatedAt: DateTime(2026, 9, 28, 10),
            ),
          );
      final water = (await database.select(database.waterIntakes).get()).single;
      expect(water.amountMl, 250);

      await database
          .into(database.achievements)
          .insert(AchievementsCompanion.insert(id: 'a-1', key: 'streak-7'));
      // 未解锁成就：progress 默认 0，unlockedAt null。
      final achievement =
          (await database.select(database.achievements).get()).single;
      expect(achievement.progress, 0);
      expect(achievement.unlockedAt, isNull);
      // key 唯一约束真的存在。
      expect(
        () => database
            .into(database.achievements)
            .insert(AchievementsCompanion.insert(id: 'a-2', key: 'streak-7')),
        throwsA(anything),
      );

      await database
          .into(database.dishLibrary)
          .insert(
            DishLibraryCompanion.insert(
              id: 'd-1',
              name: '鸡胸沙拉',
              mealSlot: '午餐',
              kcal: 320,
              proteinG: 38,
              carbsG: 12,
              fatG: 9,
              source: 'user',
              createdAt: DateTime(2026, 9, 28),
              updatedAt: DateTime(2026, 9, 28),
            ),
          );
      final dish = (await database.select(database.dishLibrary).get()).single;
      expect(dish.isHot, isFalse, reason: 'isHot 默认 false');
      expect(dish.fiberG, isNull);

      await database
          .into(database.cardioPrescriptions)
          .insert(
            CardioPrescriptionsCompanion.insert(
              id: 'c-1',
              plannedExerciseId: 'pe-1',
              kind: 'pace',
              value: 5.5,
              unit: 'min/km',
            ),
          );
      expect(
        (await database.select(database.cardioPrescriptions).get()).single.kind,
        'pace',
      );

      await database
          .into(database.recognitionResults)
          .insert(
            RecognitionResultsCompanion.insert(
              id: 'r-1',
              capturedAt: DateTime(2026, 9, 28, 12),
              dishName: '米饭',
              confidence: 0.92,
              imagePath: '/tmp/a.jpg',
              estimatedKcal: 232,
              ingredientsJson: '[{"name":"米饭","grams":200}]',
              macroJson: '{"kcal":232}',
            ),
          );
      expect(
        (await database.select(database.recognitionResults).get())
            .single
            .mealId,
        isNull,
      );

      await database
          .into(database.conversationMessages)
          .insert(
            ConversationMessagesCompanion.insert(
              id: 'cm-1',
              sessionId: 's-1',
              role: 'user',
              textContent: '今天吃什么',
              createdAt: DateTime(2026, 9, 28, 12),
              status: 'sent',
            ),
          );
      final message =
          (await database.select(database.conversationMessages).get()).single;
      expect(message.textContent, '今天吃什么');

      await database
          .into(database.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'auto_backup', value: 'on'));
      expect(
        (await database.select(database.appSettings).get()).single.value,
        'on',
      );

      // ③ 既有表的数据不被迁移触碰（写读往返一次确认表仍可写）。
      //    写的是**现存**列（体重）；体成分列已删，改用 notes 做往返。
      await (database.update(database.measurements)
            ..where((row) => row.id.equals('m-v16')))
          .write(const MeasurementsCompanion(notes: Value('迁移后仍可写')));
      expect(
        (await database.select(database.measurements).get()).single.notes,
        '迁移后仍可写',
      );
    },
  );
}

void _createV16Database(String path) {
  final database = sqlite.sqlite3.open(path);
  database.execute('PRAGMA user_version = 16');
  database.execute('''
CREATE TABLE measurements (
  id TEXT NOT NULL PRIMARY KEY,
  profile_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  weight_kg REAL NOT NULL,
  body_fat_percent REAL NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  notes TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  database.execute(
    "INSERT INTO measurements (id, profile_id, local_date, weight_kg, "
    "body_fat_percent, created_at, updated_at) VALUES "
    "('m-v16', 'p-1', '2026-09-27', 69.4, 18.2, 1000, 1000)",
  );
  // FK 父表最小桩（fixture 只关心约束可满足）。
  database.execute(
    'CREATE TABLE planned_exercises (id TEXT NOT NULL PRIMARY KEY)',
  );
  database.execute("INSERT INTO planned_exercises (id) VALUES ('pe-1')");
  database.execute('CREATE TABLE meals (id TEXT NOT NULL PRIMARY KEY)');
  database.dispose();
}
