import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/bundled_user_food_importer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 随包用户食物库引导（2026-10-20 用户拍板内置 8 列 CSV）。
///
/// 用**小型内联 CSV**钉行为：幂等（KV 标记）、计数如实、行是**内置**
/// （2026-10-23 用户：导入的食物都属内置，只有 App 内新建才是自建）。
/// 资产本身的行数与形状由隐私审计与导入冒烟钉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const csv = '''
食品ID,品牌,食物名称,一级分类,热量(kcal/100g),蛋白质(g/100g),碳水化合物(g/100g),脂肪(g/100g)
CN000001,测试牌,测试燕麦片,谷物及主食,367.0,15.0,61.0,7.0
CN000002,,无品牌酸奶,乳类及制品,59.0,2.0,8.6,2.0
''';
  late AppDatabase db;
  late BundledUserFoodImporter baseImporter;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _assetText = csv;
    db = AppDatabase(NativeDatabase.memory());
    baseImporter = BundledUserFoodImporter(
      repository: FoodRepository(
        database: db,
        idGenerator: SeqIds(),
        clock: FixedAppClock(DateTime.utc(2026, 10, 20, 8)),
      ),
      loadAsset: _loadAsset,
    );
  });

  tearDown(() async => db.close());

  test('首启导入：计数如实、行是内置（isUserCreated=false、source=import）', () async {
    final target = baseImporter;

    final result = await target.importIfNeeded();
    expect(result.alreadyImported, isFalse);
    expect(result.imported, 2);
    expect(result.failed, 0);

    final rows = await db.select(db.foods).get();
    expect(rows, hasLength(2));
    expect(
      rows.every((row) => !row.isUserCreated),
      isTrue,
      reason: '导入行一律内置：不可编辑/删除，「清除所有数据」不清它们',
    );
    expect(rows.every((row) => row.source == 'import'), isTrue);
    final oat = rows.firstWhere((row) => row.name == '测试燕麦片');
    expect(oat.brand, '测试牌');
    expect(oat.kcalPer100g, 367.0);
    expect(oat.category, 'staple', reason: '谷物及主食 → FoodCategory.staple');
    final yogurt = rows.firstWhere((row) => row.name == '无品牌酸奶');
    expect(yogurt.brand, isNull);
    expect(yogurt.category, 'dairy');
    final settings = AppSettingsRepository(database: db);
    expect(
      await settings.getBool(kBundledUserFoodImportedKey),
      isTrue,
      reason: '成功后打 KV 标记',
    );
  });

  test('幂等：第二次调用直接跳过（不重复导入、alreadyImported=true）', () async {
    final target = baseImporter;
    await target.importIfNeeded();
    final second = await target.importIfNeeded();
    expect(second.alreadyImported, isTrue);
    expect(second.imported, 0);
    final rows = await db.select(db.foods).get();
    expect(rows, hasLength(2), reason: '不重复写');
  });

  test('「清除所有数据」会连 KV 一起清 ⇒ 重新导入（同一判定来源）', () async {
    final target = baseImporter;
    await target.importIfNeeded();
    // 模拟清除：正表与 app_settings 都清（clear_all 的 allTables 覆盖两者）。
    await db.delete(db.foods).go();
    await db.delete(db.appSettings).go();
    final third = await target.importIfNeeded();
    expect(third.alreadyImported, isFalse);
    expect(third.imported, 2, reason: '数据与标记都没了就该重导');
  });

  test('坏 CSV：异常上抛（调用方在后台吞掉，不静默当成功）', () async {
    final bad = BundledUserFoodImporter(
      repository: baseImporter.repository,
      assetPath: 'test/bundled-user-food.bad.csv',
      loadAsset: _loadAsset,
    );
    await expectLater(bad.importIfNeeded(), throwsA(isA<FormatException>()));
    final settings = AppSettingsRepository(database: db);
    expect(
      await settings.getBool(kBundledUserFoodImportedKey),
      isFalse,
      reason: '导入抛异常不打标：下次启动会重试',
    );
  });
}

/// 测试用资产加载（不走 Flutter 资产通道：rootBundle 是 CachingAssetBundle，
/// 按路径缓存，连续测试会互相污染——这里直接注入闭包）。
String _assetText = '';

Future<String> _loadAsset(String path) async {
  if (path.endsWith('.bad.csv')) throw const FormatException('坏 CSV');
  return _assetText;
}

class SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'food-${_n++}';
}
