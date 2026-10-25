import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';

/// 3.0 食堂目录：**地点 → 窗口 → 菜品** 三级自建结构（取代导入快照路径）。
///
/// 覆盖：三级 CRUD、级联删除、营养写入与「取最新」、只写区间的历史行按
/// 无营养处理、时间戳单调（同毫秒重复写入不会选错行）。
void main() {
  late AppDatabase database;
  late CanteenRepository repository;
  final now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CanteenRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> seedVenue() =>
      repository.createVenue(name: '东区食堂', campusName: '示范大学');

  test('空库没有地点', () async {
    expect(await repository.listVenues(), isEmpty);
  });

  test('创建地点：校园按名 find-or-create，同一校园复用一个 campus 行', () async {
    final first = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final second = await repository.createVenue(
      name: '西区食堂',
      campusName: '示范大学',
    );

    final campuses = await database.select(database.campusProfiles).get();
    expect(campuses, hasLength(1), reason: '同名校园不重复建行');
    final venues = await repository.listVenues();
    expect(venues, hasLength(2));
    expect(venues.map((venue) => venue.id), containsAll([first, second]));
    expect(venues.first.campusName, '示范大学');
  });

  test('校园名留空时归入「我的校园」而不是空串', () async {
    await repository.createVenue(name: '一食堂', campusName: '  ');
    final campuses = await database.select(database.campusProfiles).get();
    expect(campuses.single.name, '我的校园');
  });

  test('地点名为空拒绝写入', () async {
    expect(
      () => repository.createVenue(name: '   ', campusName: '示范大学'),
      throwsA(isA<CanteenWriteException>()),
    );
    expect(await database.select(database.campusProfiles).get(), isEmpty);
  });

  test('创建窗口：时刻校验（格式 / 结束早于开始）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    expect(windowId, isNotEmpty);

    expect(
      () => repository.createWindow(
        venueId: venueId,
        name: '错格式',
        openTime: '8:00',
        closeTime: '13:00',
      ),
      throwsA(isA<CanteenWriteException>()),
      reason: 'HH:MM 必须两位小时',
    );
    expect(
      () => repository.createWindow(
        venueId: venueId,
        name: '倒挂',
        openTime: '13:00',
        closeTime: '08:00',
      ),
      throwsA(isA<CanteenWriteException>()),
      reason: '结束必须晚于开始',
    );
    expect(
      () => repository.createWindow(
        venueId: 'venue-missing',
        name: '孤儿窗口',
        openTime: '08:00',
        closeTime: '09:00',
      ),
      throwsA(isA<CanteenWriteException>()),
    );
  });

  test('窗口视图带营业时段文案与菜品计数', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createDish(windowId: windowId, name: '番茄炒蛋');

    final windows = await repository.listWindows(venueId);
    expect(windows, hasLength(1));
    expect(windows.single.windowLabel, '08:00–13:30');
    expect(windows.single.dishes, hasLength(1));
    expect(windows.single.analyzedCount, 0);
  });

  // 2026-10-16（S8-b 用户要求删掉菜品价格）：原名「新增/改名改价/价格非负」
  // ——价格参数与「价格非负」校验随列一起退役，只留新增与改名。
  test('菜品：新增、改名（价格已退役，列不存在）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );

    var dishes = await repository.listDishes(windowId);
    expect(dishes.single.name, '番茄炒蛋');
    expect(dishes.single.hasNutrition, isFalse);
    // 表里已经没有价格列（v26 减法迁移）。
    final menuItemColumns = await database
        .customSelect("SELECT name FROM pragma_table_info('menu_items')")
        .get();
    expect(
      menuItemColumns.map((row) => row.read<String>('name')),
      isNot(contains('price_minor')),
    );

    await repository.updateDish(dishId: dishId, name: '西红柿炒鸡蛋');
    dishes = await repository.listDishes(windowId);
    expect(dishes.single.name, '西红柿炒鸡蛋');
    expect(
      () => repository.createDish(windowId: windowId, name: '  '),
      throwsA(isA<CanteenWriteException>()),
    );
  });

  test('写入营养：每 100g 代表值 + 等级 + 状态 estimated', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );

    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 92,
      proteinPer100g: 5.4,
      carbsPer100g: 6.1,
      fatPer100g: 5.2,
      grade: 'C',
      confidence: 0.6,
      kcalMin: 80,
      kcalMax: 110,
      sourceText: '同类菜品常见配比',
    );

    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.hasNutrition, isTrue);
    expect(dish.kcalPer100g, 92);
    expect(dish.proteinPer100g, 5.4);
    expect(dish.carbsPer100g, 6.1);
    expect(dish.fatPer100g, 5.2);
    expect(dish.evidenceGrade, 'C');
    expect(dish.itemStatus, 'estimated');
    expect(dish.evidence!.origin, 'ai_estimate');
    expect(dish.evidence!.kcalMin, 80);
    expect(dish.evidence!.kcalMax, 110);
    expect(dish.evidence!.confidence, 0.6);
  });

  test('等级白名单：A/B/C/D 之外拒绝', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );

    expect(
      () => repository.recordNutrition(
        dishId: dishId,
        kcalPer100g: 90,
        proteinPer100g: 5,
        carbsPer100g: 6,
        fatPer100g: 5,
        grade: 'E',
        confidence: 0.5,
      ),
      throwsA(isA<CanteenWriteException>()),
    );
    expect(
      (await repository.listDishes(windowId)).single.hasNutrition,
      isFalse,
    );
  });

  test('重复分析：读取只认最新一条证据（同毫秒也单调）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );

    // 固定时钟：两次写入落在同一时刻，靠仓储内部单调戳保证顺序。
    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 90,
      proteinPer100g: 5,
      carbsPer100g: 6,
      fatPer100g: 5,
      grade: 'D',
      confidence: 0.4,
    );
    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 105,
      proteinPer100g: 6,
      carbsPer100g: 7,
      fatPer100g: 6,
      grade: 'B',
      confidence: 0.8,
    );

    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.kcalPer100g, 105, reason: '第二次分析应覆盖展示值');
    expect(dish.evidenceGrade, 'B');

    final evidenceRows = await database
        .select(database.menuItemNutritionEvidence)
        .get();
    expect(evidenceRows, hasLength(2), reason: '历史证据保留可追溯');
  });

  test('只有区间的历史行按「无营养」处理（不取中点）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    // 直接插一条 v15 之前那种「只有区间」的证据行。
    await database
        .into(database.menuItemNutritionEvidence)
        .insert(
          MenuItemNutritionEvidenceCompanion.insert(
            id: 'legacy-evidence',
            menuItemId: dishId,
            grade: 'D',
            origin: 'legacy',
            kcalMin: const Value(80),
            kcalMax: const Value(120),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.hasNutrition, isFalse, reason: '没有代表值就不算已分析');
    expect(dish.kcalPer100g, isNull);
  });

  test('待分析列表只含无营养的菜品', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final analyzed = await repository.createDish(
      windowId: windowId,
      name: '已分析菜',
    );
    await repository.createDish(windowId: windowId, name: '待分析菜');
    await repository.recordNutrition(
      dishId: analyzed,
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 5,
      fatPer100g: 5,
      grade: 'C',
      confidence: 0.5,
    );

    final pending = await repository.listDishesNeedingAnalysis(windowId);
    expect(pending, hasLength(1));
    expect(pending.single.name, '待分析菜');
  });

  test('地点视图计数：窗口/菜品/已分析', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final analyzed = await repository.createDish(
      windowId: windowId,
      name: '已分析菜',
    );
    await repository.createDish(windowId: windowId, name: '待分析菜');
    await repository.recordNutrition(
      dishId: analyzed,
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 5,
      fatPer100g: 5,
      grade: 'C',
      confidence: 0.5,
    );

    final venue = (await repository.listVenues()).single;
    expect(venue.windowCount, 1);
    expect(venue.dishCount, 2);
    expect(venue.analyzedCount, 1);
    expect(venue.hasDishes, isTrue);
    expect(venue.fullyAnalyzed, isFalse);
  });

  test('删除窗口：菜品与营养证据级联删除', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 5,
      fatPer100g: 5,
      grade: 'C',
      confidence: 0.5,
    );

    await repository.deleteWindow(windowId);

    expect(await repository.listWindows(venueId), isEmpty);
    expect(await database.select(database.menuItems).get(), isEmpty);
    expect(
      await database.select(database.menuItemNutritionEvidence).get(),
      isEmpty,
    );
  });

  test('删除地点：目录快照、窗口、菜品一并清掉（不留孤儿）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createDish(windowId: windowId, name: '番茄炒蛋');

    await repository.deleteVenue(venueId);

    expect(await repository.listVenues(), isEmpty);
    expect(await database.select(database.menuServices).get(), isEmpty);
    expect(await database.select(database.menuItems).get(), isEmpty);
    expect(
      await database.select(database.menuSnapshots).get(),
      isEmpty,
      reason: '内部目录快照不能留成孤儿',
    );
  });

  test('自建目录快照：status=catalog、固定业务日期、不自动过期', () async {
    final venueId = await seedVenue();
    await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );

    final snapshot =
        (await database.select(database.menuSnapshots).get()).single;
    expect(snapshot.id, CanteenRepository.catalogSnapshotIdFor(venueId));
    expect(snapshot.status, 'catalog');
    expect(snapshot.businessDate, catalogBusinessDate);
    expect(snapshot.expiresAt, isNull, reason: '常驻目录不设过期');
    expect(snapshot.venueId, venueId);
    // 来源行记录条款状态（docs/07 §6.1），不留下未审计的来源。
    final source = (await database.select(database.menuSources).get()).single;
    expect(source.sourceType, 'manual');
    expect(source.license, 'user-provided');
  });

  test('同一地点重复加窗口不会重复建快照', () async {
    final venueId = await seedVenue();
    await repository.createWindow(
      venueId: venueId,
      name: '窗口 A',
      openTime: '08:00',
      closeTime: '09:00',
    );
    await repository.createWindow(
      venueId: venueId,
      name: '窗口 B',
      openTime: '10:00',
      closeTime: '11:00',
    );
    expect(await database.select(database.menuSnapshots).get(), hasLength(1));
    expect(await database.select(database.menuSources).get(), hasLength(1));
  });

  // ── 菜品照片（docs/29 §P7 需求 16）──────────────────────────────────

  test('照片路径落库并可读回；stationName 一并读回（需求 17 副行数据）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createDish(
      windowId: windowId,
      name: '红烧排骨',
      stationName: '川湘窗口',
      imagePath: '/docs/localfit_ai/dish_images/dish_1.jpg',
    );

    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.imagePath, '/docs/localfit_ai/dish_images/dish_1.jpg');
    expect(dish.hasPhoto, isTrue);
    expect(dish.stationName, '川湘窗口');
  });

  test('编辑：setImagePath=false 时照片列一字不动（用户没碰照片字段）', () async {
    final venueId = await seedVenue();
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '红烧排骨',
      imagePath: '/docs/dish_old.jpg',
    );

    await repository.updateDish(dishId: dishId, name: '红烧排骨（大份）');

    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.name, '红烧排骨（大份）');
    expect(dish.imagePath, '/docs/dish_old.jpg', reason: '列保持原值');
  });

  test('编辑：setImagePath=true 覆盖为新图，旧文件尽力删除', () async {
    final store = _RecordingImageStore();
    final scoped = CanteenRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
      dishImageStore: store,
    );
    final venueId = await scoped.createVenue(name: '东区食堂', campusName: '');
    final windowId = await scoped.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await scoped.createDish(
      windowId: windowId,
      name: '红烧排骨',
      imagePath: '/docs/dish_old.jpg',
    );

    await scoped.updateDish(
      dishId: dishId,
      name: '红烧排骨',
      imagePath: '/docs/dish_new.jpg',
      setImagePath: true,
    );

    expect(
      (await scoped.listDishes(windowId)).single.imagePath,
      '/docs/dish_new.jpg',
    );
    expect(store.deleted, ['/docs/dish_old.jpg'], reason: '旧文件删掉，不留孤儿');
  });

  test('编辑：setImagePath=true 传 null＝移除照片（列清空 + 删文件）', () async {
    final store = _RecordingImageStore();
    final scoped = CanteenRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
      dishImageStore: store,
    );
    final venueId = await scoped.createVenue(name: '东区食堂', campusName: '');
    final windowId = await scoped.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await scoped.createDish(
      windowId: windowId,
      name: '红烧排骨',
      imagePath: '/docs/dish_old.jpg',
    );

    await scoped.updateDish(
      dishId: dishId,
      name: '红烧排骨',
      imagePath: null,
      setImagePath: true,
    );

    final dish = (await scoped.listDishes(windowId)).single;
    expect(dish.imagePath, isNull);
    expect(dish.hasPhoto, isFalse);
    expect(store.deleted, ['/docs/dish_old.jpg'], reason: '移除=删旧文件');
  });

  test('删除菜品：照片文件一并清理', () async {
    final store = _RecordingImageStore();
    final scoped = CanteenRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
      dishImageStore: store,
    );
    final venueId = await scoped.createVenue(name: '东区食堂', campusName: '');
    final windowId = await scoped.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await scoped.createDish(
      windowId: windowId,
      name: '红烧排骨',
      imagePath: '/docs/dish_old.jpg',
    );

    await scoped.deleteDish(dishId);

    expect(await scoped.listDishes(windowId), isEmpty);
    expect(store.deleted, ['/docs/dish_old.jpg']);
  });

  test('地点改名', () async {
    final venueId = await seedVenue();
    await repository.renameVenue(venueId, '东区食堂（翻新后）');
    expect((await repository.listVenues()).single.name, '东区食堂（翻新后）');

    expect(
      () => repository.renameVenue(venueId, '  '),
      throwsA(isA<CanteenWriteException>()),
    );
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'canteen-id-${++_value}';
}

/// 记录删除了哪些路径的假照片存储：真实文件 IO 在 `dish_image_store_test`
/// 里覆盖，这里只关心「仓库有没有按语义调用删除」。
final class _RecordingImageStore extends DishImageStore {
  _RecordingImageStore() : super(idGenerator: _IncrementingIdGenerator());

  final List<String> deleted = [];

  @override
  Future<String> copyBytes(
    Uint8List bytes, {
    required DateTime createdAt,
    String extension = '.jpg',
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteQuietly(String? filePath) async {
    if (filePath != null) deleted.add(filePath);
  }
}
