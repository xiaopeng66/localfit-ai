import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// 真实模型只允许挑现有供应，返回值经过生产推荐用例的本地时段校验。
/// 若用例返回不可用却被当成成功，或模型越过午餐窗口，或推荐擅自记餐，必红。
/// 默认不外呼；凭据只从进程环境读取，不写入日志或测试数据库。
void main() {
  final env = Platform.environment;
  final key = env['LF_LIVE_KEY'] ?? '';
  final base = env['LF_LIVE_BASE'] ?? '';
  final model = env['LF_LIVE_MODEL'] ?? '';
  final enabled = key.isNotEmpty && base.isNotEmpty && model.isNotEmpty;

  test(
    'AI 换一套：真实模型限定午餐窗口，只显示建议不记餐',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const ids = UuidV7Generator();
      final now = DateTime.utc(2026, 11, 10, 12);
      final clock = FixedAppClock(now);
      final catalog = FoodCatalogService(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final canteen = CanteenRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final venue = await canteen.createVenue(
        name: '合成测试食堂',
        campusName: '示范大学',
      );
      final window = await canteen.createWindow(
        venueId: venue,
        name: '合成午餐窗口',
        openTime: '11:00',
        closeTime: '14:00',
      );
      final expectedKcal = <String, double>{};
      for (final fixture in [
        ('合成米饭', 116.0),
        ('合成青菜', 60.0),
        ('合成蒸蛋', 135.0),
      ]) {
        final food = await catalog.createMasterFood(
          name: fixture.$1,
          kcalPer100g: fixture.$2,
          proteinPer100g: 10,
          carbsPer100g: 12,
          fatPer100g: 5,
        );
        final dish = await canteen.createDish(
          windowId: window,
          name: fixture.$1,
          foodId: food,
          servingGrams: 100,
        );
        expectedKcal[dish] = fixture.$2;
      }
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final service = OpenAiCompatibleConversationService(
        dio: dio,
        configurationReader: _LiveConfiguration(
          AiProviderConfiguration(
            baseUrl: base,
            model: model,
            protocol: AiProviderProtocol.fromStorage(env['LF_LIVE_PROTOCOL']),
          ),
        ),
        apiKeyStore: AiApiKeyStore(store: _LiveKey(key)),
      );
      final result = await SwapDailySetWithAi(
        service: service,
        canteenRepository: canteen,
        supplyCatalog: SupplyCatalogRepository(database: database),
        now: () => now,
      ).runDetailed();
      expect(result.unavailableReason, isNull);
      expect(result.bySlot.keys, [MealSlot.lunch]);
      final dishes = result.bySlot[MealSlot.lunch]!;
      expect(dishes, isNotEmpty);
      expect(dishes.map((dish) => dish.id).toSet(), hasLength(dishes.length));
      for (final dish in dishes) {
        expect(expectedKcal, contains(dish.id));
        expect(dish.servingGrams, 100);
        expect(dish.kcal, expectedKcal[dish.id]);
      }
      expect(await database.select(database.meals).get(), isEmpty);
      expect(await database.select(database.mealItems).get(), isEmpty);
    },
    skip: enabled ? false : '未注入 LF_LIVE_KEY/BASE/MODEL，不外呼',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

final class _LiveConfiguration implements AiProviderConfigurationReader {
  const _LiveConfiguration(this.configuration);

  final AiProviderConfiguration configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => configuration;
}

final class _LiveKey implements SecureKeyValueStore {
  const _LiveKey(this.key);

  final String key;

  @override
  Future<String?> read(String key) async =>
      key == AiApiKeyStore.storageKey ? this.key : null;

  @override
  Future<void> write(String key, String value) async =>
      throw UnsupportedError('Read-only live fixture');

  @override
  Future<void> delete(String key) async =>
      throw UnsupportedError('Read-only live fixture');
}
