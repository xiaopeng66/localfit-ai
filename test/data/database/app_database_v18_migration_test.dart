import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/24 §2：schema 17 → 18 迁移。
///
/// 造一个**有 AI 配置行的 v17 库** → 迁移 → 断言「只增不改不删」：
///  * 既有行原样保留（base_url / model 逐字不变）；
///  * 新列 protocol 为 null＝「从未选过协议」，而不是被填成某个默认值——
///    这一点是刻意的：把「不知道」写成 'chat_completions' 会让后来读的人
///    以为用户显式选过；
///  * 读回路径（[AiProviderProtocol.fromStorage]）把 null 回落成
///    Chat Completions，即旧行为逐字节不变；
///  * 新值可写可读（选 Responses 后不丢）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v18-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrades a populated v17 database and keeps the protocol unset',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV17Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
      });

      // ① 既有配置行原样保留。
      final row =
          (await database.select(database.aiProviderConfigs).get()).single;
      expect(row.id, 'default');
      expect(row.baseUrl, 'https://api.example.com/v1/');
      expect(row.model, 'legacy-model');

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      // 这条 fixture 只关心 protocol 列（v18 新增）；用户版本号随
      // schemaVersion 一起走，现在是 19（docs/28 的 W4 删表）。
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);

      // ② 新列为 null：是「从未选过」而不是被迁移填了一个值。
      expect(row.protocol, isNull);
      // ③ 读回口径：null 回落 Chat Completions（旧行为）。
      expect(
        AiProviderProtocol.fromStorage(row.protocol),
        AiProviderProtocol.chatCompletions,
      );
      // 未知字符串同样回落（库里可能来自更新版本或手工改动）。
      expect(
        AiProviderProtocol.fromStorage('something-else'),
        AiProviderProtocol.chatCompletions,
      );

      // ④ 新值可写可读：显式选 Responses 后不丢。
      await (database.update(
        database.aiProviderConfigs,
      )..where((config) => config.id.equals('default'))).write(
        AiProviderConfigsCompanion(
          protocol: Value(AiProviderProtocol.responses.storageValue),
        ),
      );
      final updated =
          (await database.select(database.aiProviderConfigs).get()).single;
      expect(
        AiProviderProtocol.fromStorage(updated.protocol),
        AiProviderProtocol.responses,
      );
      // 其他列仍未被触碰。
      expect(updated.baseUrl, 'https://api.example.com/v1/');
      expect(updated.model, 'legacy-model');
    },
  );
}

/// 最小复现：只建迁移要触碰的 ai_provider_configs 表（仓库惯例，见
/// app_database_v17_migration_test 的 fixture 说明）。
void _createV17Database(String path) {
  final database = sqlite.sqlite3.open(path);
  database.execute('PRAGMA user_version = 17');
  database.execute('''
CREATE TABLE ai_provider_configs (
  id TEXT NOT NULL PRIMARY KEY,
  base_url TEXT NOT NULL,
  model TEXT NOT NULL
);
''');
  database.execute(
    "INSERT INTO ai_provider_configs (id, base_url, model) VALUES "
    "('default', 'https://api.example.com/v1/', 'legacy-model')",
  );
  database.dispose();
}
