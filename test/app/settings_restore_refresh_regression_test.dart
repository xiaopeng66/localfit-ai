import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/setting_row.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/local_ai_provider_settings_store.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

final _now = DateTime(2026, 10, 13, 9);
const _codec = LfbBackupCodec(iterations: 2000, derivesInIsolate: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overview reload after clear does not recreate database rows', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedProfile(database, '旧昵称');
    await _seedMeal(database);
    final loader = LoadProfileOverview(
      database: database,
      clock: FixedAppClock(_now.toUtc()),
    );
    expect((await loader.run()).totalMealRecords, 1);
    await ClearAllLocalData(database).clear();
    final overview = await loader.run();
    expect(overview.totalMealRecords, 0);
    expect(overview.achievements, hasLength(4));
    expect(
      overview.achievements.every(
        (item) => !item.unlocked && item.progress == 0,
      ),
      isTrue,
    );
    for (final table in database.allTables) {
      expect(
        await database.select(table).get(),
        isEmpty,
        reason:
            'Read-only empty display must not recreate ${table.actualTableName}.',
      );
    }
  });

  test(
    'overview in flight cannot write old achievements after a concurrent clear',
    () async {
      final timing = _HeldAchievements();
      final database = AppDatabase(
        NativeDatabase.memory().interceptWith(timing),
      );
      addTearDown(database.close);
      await _seedProfile(database, '旧昵称');
      await _seedMeal(database);
      final loading = LoadProfileOverview(
        database: database,
        clock: FixedAppClock(_now.toUtc()),
      ).run();
      await timing.captured.future;
      final clearing = ClearAllLocalData(database).clear();
      await Future<void>(() {});
      timing.release.complete();
      await loading;
      await clearing;
      for (final table in database.allTables) {
        expect(
          await database.select(table).get(),
          isEmpty,
          reason:
              'A pre-clear overview must not restore ${table.actualTableName}.',
        );
      }
    },
  );

  for (final operation in ['clear', 'restore']) {
    testWidgets(
      '$operation refreshes current Settings and mounted identity branches',
      (tester) async {
        final files = _Files();
        if (operation == 'restore') {
          final source = AppDatabase(NativeDatabase.memory());
          try {
            await _seedProfile(source, '新昵称');
            await _seedConfig(source, 'restored-model');
            files.picked = Uint8List.fromList(
              utf8.encode(
                await _codec.encode(
                  payload: await ExportLocalFitData(source).exportJson(),
                  password: 'test-only-password',
                ),
              ),
            );
          } finally {
            await source.close();
          }
        }
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final settings = AppSettingsRepository(database: database);
        await _seedProfile(database, '旧昵称');
        await _seedMeal(database);
        await settings.setBool(
          AppSettingsRepository.autoBackupEnabledKey,
          value: true,
        );
        await _seedConfig(database, 'old-model');
        final aiStore = LocalAiProviderSettingsStore(
          database: database,
          apiKeyStore: AiApiKeyStore(store: _EmptySecureStore()),
        );
        await _mount(
          tester,
          LocalFitApp(
            initialLocation: AppRoutes.dashboard,
            now: _now,
            conversationService: _OfflineAi(),
            mealRepository: MealRepository(
              database: database,
              idGenerator: const UuidV7Generator(),
              clock: FixedAppClock(_now.toUtc()),
            ),
            aiProviderSettingsStore: aiStore,
            createEncryptedBackup: CreateEncryptedBackup(
              database: database,
              fileStore: files,
              codec: _codec,
            ),
            restoreEncryptedBackup: RestoreEncryptedBackup(
              database: database,
              fileStore: files,
              codec: _codec,
            ),
            clearAllLocalData: ClearAllLocalData(database),
            exportCsvFiles: ExportCsvFiles(
              database: database,
              fileStore: files,
            ),
            profileIdentityRepository: ProfileIdentityRepository(
              database: database,
            ),
            profileOverviewLoader: LoadProfileOverview(
              database: database,
              clock: FixedAppClock(_now.toUtc()),
            ),
            appSettingsRepository: settings,
          ),
        );
        try {
          await _tap(tester, 'nav-ai-workbench');
          await _tap(tester, 'nav-settings');
          final state = tester.state(find.byType(SettingsPage));
          expect(find.text('旧昵称'), findsOneWidget);
          expect(_stat(tester), contains('1'));
          expect(_autoBackup(tester), isTrue);
          expect(find.text('old-model'), findsOneWidget);
          if (operation == 'clear') {
            await _tap(tester, 'cta-clear-data');
            await tester.enterText(
              find.byKey(const Key('backup-clear-confirm-text')),
              '全部清除',
            );
            await _tap(tester, 'backup-clear-confirm');
            expect(await database.select(database.profiles).get(), isEmpty);
            expect(find.text('旧昵称'), findsNothing);
            expect(
              tester
                  .widget<Text>(
                    find.byKey(const Key('settings-avatar-initial')),
                  )
                  .data,
              'Fit',
            );
          } else {
            await _tap(tester, 'cta-restore');
            await tester.enterText(
              find.byKey(const Key('backup-restore-password')),
              'test-only-password',
            );
            await _tap(tester, 'backup-restore-confirm');
            expect(
              (await database.select(database.profiles).getSingle())
                  .displayName,
              '新昵称',
            );
            expect(find.text('旧昵称'), findsNothing);
            expect(find.text('新昵称'), findsOneWidget);
          }
          expect(tester.state(find.byType(SettingsPage)), same(state));
          expect(await database.select(database.meals).get(), isEmpty);
          expect(_stat(tester), contains('0'));
          expect(_autoBackup(tester), isFalse);
          expect(find.text('old-model'), findsNothing);
          expect(
            tester
                .widget<SettingRow>(
                  find.byKey(const Key('settings-ai-model-row')),
                )
                .value,
            operation == 'restore' ? 'restored-model' : '未配置',
          );
          await _tap(tester, 'nav-dashboard');
          expect(
            find.text(operation == 'restore' ? '早安，新昵称' : '早安'),
            findsOneWidget,
          );
          await _tap(tester, 'nav-ai-workbench');
          expect(
            tester
                .widget<Text>(find.byKey(const Key('ai-chat-avatar-initial')))
                .data,
            operation == 'restore' ? '新' : 'Fit',
          );
          await _tap(tester, 'nav-settings');
          expect(_stat(tester), contains('0'));
          if (operation == 'clear') {
            for (final table in database.allTables) {
              expect(
                await database.select(table).get(),
                isEmpty,
                reason:
                    'Refreshing the cleared screen must not recreate ${table.actualTableName} rows.',
              );
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          await _drain(tester);
        }
      },
    );
  }

  testWidgets(
    'clear completion refreshes Settings after its confirmation sheet was dismissed',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedProfile(database, '旧昵称');
      await _seedMeal(database);
      await _seedConfig(database, 'old-model');
      final settings = AppSettingsRepository(database: database);
      await settings.setBool(
        AppSettingsRepository.autoBackupEnabledKey,
        value: true,
      );
      final media = _DelayedMedia();
      await _mount(
        tester,
        _replacementApp(
          database,
          secureStore: _EmptySecureStore(),
          media: media,
        ),
      );
      try {
        expect(_stat(tester), contains('1'));
        expect(_autoBackup(tester), isTrue);
        expect(find.text('old-model'), findsOneWidget);
        await _tap(tester, 'cta-clear-data');
        await tester.enterText(
          find.byKey(const Key('backup-clear-confirm-text')),
          '全部清除',
        );
        await _tap(tester, 'backup-clear-confirm');
        expect(media.started, isTrue);
        expect(await database.select(database.meals).get(), isEmpty);
        await tester.binding.handlePopRoute();
        await _frames(tester);
        expect(find.byKey(const Key('backup-clear-confirm')), findsNothing);
        media.completion.complete();
        await _frames(tester);
        expect(_stat(tester), contains('0'));
        expect(_autoBackup(tester), isFalse);
        expect(
          tester
              .widget<SettingRow>(
                find.byKey(const Key('settings-ai-model-row')),
              )
              .value,
          '未配置',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!media.completion.isCompleted) media.completion.complete();
        await _drain(tester);
      }
    },
  );

  for (final oldReadFails in [false, true]) {
    testWidgets(
      'late AI settings ${oldReadFails ? 'error' : 'success'} cannot overwrite a cleared snapshot',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        await _seedProfile(database, '旧昵称');
        await _seedConfig(database, 'old-model');
        final secure = _DelayedSecureStore();
        await _mount(tester, _replacementApp(database, secureStore: secure));
        try {
          expect(secure.firstReadStarted, isTrue);
          await _tap(tester, 'cta-clear-data');
          await tester.enterText(
            find.byKey(const Key('backup-clear-confirm-text')),
            '全部清除',
          );
          await _tap(tester, 'backup-clear-confirm');
          expect(
            await database.select(database.aiProviderConfigs).get(),
            isEmpty,
          );
          expect(
            find.byKey(const Key('settings-ai-model-row')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<SettingRow>(
                  find.byKey(const Key('settings-ai-model-row')),
                )
                .value,
            '未配置',
          );
          if (oldReadFails) {
            secure.first.completeError(
              StateError('test delayed storage failure'),
            );
          } else {
            secure.first.complete(null);
          }
          await _frames(tester);
          expect(find.text('无法读取本地 AI 配置，请重试。'), findsNothing);
          expect(
            find.byKey(const Key('settings-ai-model-row')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<SettingRow>(
                  find.byKey(const Key('settings-ai-model-row')),
                )
                .value,
            '未配置',
          );
          expect(find.text('old-model'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          if (!secure.first.isCompleted) secure.first.complete(null);
          await _drain(tester);
        }
      },
    );
  }

  testWidgets(
    'successful replacement reload clears an earlier AI settings error',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedProfile(database, '旧昵称');
      final secure = _DelayedSecureStore();
      await _mount(tester, _replacementApp(database, secureStore: secure));
      try {
        expect(secure.firstReadStarted, isTrue);
        secure.first.completeError(StateError('test initial storage failure'));
        await _frames(tester);
        expect(find.text('无法读取本地 AI 配置，请重试。'), findsOneWidget);
        await _tap(tester, 'cta-clear-data');
        await tester.enterText(
          find.byKey(const Key('backup-clear-confirm-text')),
          '全部清除',
        );
        await _tap(tester, 'backup-clear-confirm');
        expect(find.text('无法读取本地 AI 配置，请重试。'), findsNothing);
        expect(find.byKey(const Key('settings-ai-model-row')), findsOneWidget);
        expect(
          tester
              .widget<SettingRow>(
                find.byKey(const Key('settings-ai-model-row')),
              )
              .value,
          '未配置',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!secure.first.isCompleted) secure.first.complete(null);
        await _drain(tester);
      }
    },
  );

  testWidgets(
    'clear with media failure still refreshes committed database state',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedProfile(database, '旧昵称');
      await _seedMeal(database);
      await _mount(
        tester,
        LocalFitApp(
          initialLocation: AppRoutes.settings,
          now: _now,
          clearAllLocalData: ClearAllLocalData(
            database,
            dishImageStore: _FailingMedia(),
          ),
          profileIdentityRepository: ProfileIdentityRepository(
            database: database,
          ),
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(_now.toUtc()),
          ),
        ),
      );
      try {
        await _tap(tester, 'cta-clear-data');
        await tester.enterText(
          find.byKey(const Key('backup-clear-confirm-text')),
          '全部清除',
        );
        await _tap(tester, 'backup-clear-confirm');
        expect(find.textContaining('清除未完成'), findsOneWidget);
        expect(await database.select(database.profiles).get(), isEmpty);
        await tester.tap(find.text('取消'));
        await _frames(tester);
        expect(find.text('旧昵称'), findsNothing);
        expect(_stat(tester), contains('0'));
        for (final table in database.allTables) {
          expect(await database.select(table).get(), isEmpty);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _drain(tester);
      }
    },
  );
}

Future<void> _mount(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 24; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await _frames(tester);
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

List<String?> _stat(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('settings-stat-records')),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

bool _autoBackup(WidgetTester tester) => tester
    .widget<SettingToggle>(find.byKey(const Key('settings-auto-backup-toggle')))
    .value;

Future<void> _seedProfile(AppDatabase database, String name) async {
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'refresh-profile',
          activityLevel: 'moderate',
          displayName: Value(name),
          createdAt: _now.toUtc(),
          updatedAt: _now.toUtc(),
        ),
      );
}

Future<void> _seedMeal(AppDatabase database) async {
  await database
      .into(database.meals)
      .insert(
        MealsCompanion.insert(
          id: 'refresh-meal',
          localDate: '2026-10-13',
          slot: 'lunch',
          eatenAt: _now.toUtc(),
          source: 'manual',
          createdAt: _now.toUtc(),
          updatedAt: _now.toUtc(),
        ),
      );
}

class _Files implements BackupFileStore {
  Uint8List? picked;
  @override
  Future<Uint8List?> pickRestoreFile() async => picked;
  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async => null;
}

class _FailingMedia implements DishImageStoreRef {
  @override
  Future<void> clearAll() async =>
      throw StateError('test media cleanup failed');
}

Future<void> _seedConfig(AppDatabase database, String model) => database
    .into(database.aiProviderConfigs)
    .insert(
      AiProviderConfigsCompanion.insert(
        id: 'default',
        baseUrl: 'https://example.invalid/v1',
        model: model,
      ),
    );

LocalFitApp _replacementApp(
  AppDatabase database, {
  required SecureKeyValueStore secureStore,
  DishImageStoreRef? media,
}) {
  final files = _Files();
  final keys = AiApiKeyStore(store: secureStore);
  return LocalFitApp(
    initialLocation: AppRoutes.settings,
    now: _now,
    aiProviderSettingsStore: LocalAiProviderSettingsStore(
      database: database,
      apiKeyStore: keys,
    ),
    createEncryptedBackup: CreateEncryptedBackup(
      database: database,
      fileStore: files,
      codec: _codec,
    ),
    restoreEncryptedBackup: RestoreEncryptedBackup(
      database: database,
      fileStore: files,
      codec: _codec,
    ),
    clearAllLocalData: ClearAllLocalData(
      database,
      dishImageStore: media,
      apiKeyStore: keys,
    ),
    exportCsvFiles: ExportCsvFiles(database: database, fileStore: files),
    profileIdentityRepository: ProfileIdentityRepository(database: database),
    profileOverviewLoader: LoadProfileOverview(
      database: database,
      clock: FixedAppClock(_now.toUtc()),
    ),
    appSettingsRepository: AppSettingsRepository(database: database),
  );
}

class _HeldAchievements extends QueryInterceptor {
  final captured = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('FROM "achievements"') && !captured.isCompleted) {
      captured.complete();
      await release.future;
    }
    return rows;
  }
}

class _DelayedMedia implements DishImageStoreRef {
  final completion = Completer<void>();
  bool started = false;

  @override
  Future<void> clearAll() {
    started = true;
    return completion.future;
  }
}

class _DelayedSecureStore implements SecureKeyValueStore {
  final first = Completer<String?>();
  bool firstReadStarted = false;

  @override
  Future<String?> read(String key) async {
    if (!firstReadStarted) {
      firstReadStarted = true;
      return first.future;
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

class _EmptySecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

class _OfflineAi implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) => const Stream.empty();
}
