import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/food_preview_search.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';

/// 快照装配（docs/41 §9 G18）：分段并发 + 变更流失效复用 + 食物库预检索段。
/// 单一数据库夹具；每次用独立 loader（缓存按实例隔离）。
void main() {
  late AppDatabase db;
  late _Deps deps;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deps = _Deps(db);
  });

  tearDown(() async => db.close());

  test('食物库预检索：命中 ≤3 条，精确同名优先，带每 100g 值', () async {
    final now = DateTime.utc(2026, 10, 18);
    for (final (i, name) in ['米饭', '米饭饼', '紫米饭'].indexed) {
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-$i',
              name: name,
              kcalPer100g: 100.0 + i,
              proteinPer100g: 2,
              carbsPer100g: 20,
              fatPer100g: 1,
              source: 'catalog',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final hits = await deps.preview.search('我中午吃了米饭');
    expect(hits, hasLength(3));
    expect(hits.first.name, '米饭', reason: '精确同名优先');
    expect(hits.first.kcalPer100g, 100);
  });

  test('食物库预检索：长口语句子也要按词命中（不整句 LIKE）', () async {
    // 2026-11-11 复核：真实模型对「帮我记早餐：米饭 100 克和紫米饭 150 克，
    // 直接用食物库里已有的这两样，不要新建。」回「快照未提供食物库条目」。
    // 根因是预检索把**整句**拿去 LIKE，长句必然零命中 ⇒ 模型看不到库里的食物。
    final now2 = DateTime.utc(2026, 11, 11);
    for (final name in ['米饭', '紫米饭']) {
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'long-$name',
              name: name,
              kcalPer100g: 116,
              proteinPer100g: 2.6,
              carbsPer100g: 25.9,
              fatPer100g: 0.3,
              source: 'catalog',
              createdAt: now2,
              updatedAt: now2,
            ),
          );
    }
    final hits = await deps.preview.search(
      '帮我记早餐：米饭 100 克和紫米饭 150 克，直接用食物库里已有的这两样，不要新建。',
    );
    final names = hits.map((food) => food.name).toList();
    expect(names, contains('米饭'));
    expect(names, contains('紫米饭'));
  });

  test('食物库预检索：纯中文数量/餐次也要剥出食物名', () async {
    // 真实模型实测（C03）：「午饭吃了一碗米饭和两个鸡蛋」时预检索为空，
    // 模型于是自己 food.create 了同名食物，下一步按名记餐命中两条而拒绝。
    final now3 = DateTime.utc(2026, 11, 11);
    for (final name in ['米饭', '鸡蛋']) {
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'cq-$name',
              name: name,
              kcalPer100g: 116,
              proteinPer100g: 2.6,
              carbsPer100g: 25.9,
              fatPer100g: 0.3,
              source: 'catalog',
              createdAt: now3,
              updatedAt: now3,
            ),
          );
    }
    final hits = await deps.preview.search('午饭吃了一碗米饭和两个鸡蛋');
    final names = hits.map((food) => food.name).toList();
    expect(names, contains('米饭'));
    expect(names, contains('鸡蛋'));
  });

  test('食物库预检索：没有命中返回空（不编造）', () async {
    expect(await deps.preview.search('随便说点什么'), isEmpty);
    expect(await deps.preview.search(''), isEmpty);
  });

  test('快照 build({userMessage})：带消息时出现「食物库参考」段', () async {
    final now = DateTime.utc(2026, 10, 18);
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'f-rice',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'catalog',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final snapshot = await deps.loader.build(userMessage: '我吃了米饭');
    expect(snapshot, contains('【食物库参考】'));
    expect(snapshot, contains('[food:f-rice] 米饭'));
    expect(snapshot, contains('116 kcal/100g'));
  });

  test('快照 build()：不带消息时没有该段（旧行为逐字节兼容）', () async {
    final snapshot = await deps.loader.build();
    expect(snapshot, isNot(contains('【食物库参考】')));
  });

  test('G18 并发装配：输出顺序与段声明顺序一致（并发不改变拼接顺序）', () async {
    final snapshot = await deps.loader.build();
    final order = [
      '饮食偏好与忌口',
      '关于用户的长期记忆',
      '当前目标',
      '今日与昨日的餐记录',
      '菜品库',
      '食堂目录',
      '今日饮水',
      '最近体重',
      '训练计划',
      '自建食物',
      '本周训练统计',
      '进行中的训练',
    ];
    var last = -1;
    for (final title in order) {
      final at = snapshot.indexOf('【$title】');
      expect(at, greaterThan(last), reason: '【$title】 必须按声明顺序出现');
      last = at;
    }
  });

  test('G18 变更流复用：库未变时第二次 build 命中缓存（同实例逐字节相同）', () async {
    final loader = deps.loader;
    final first = await loader.build();
    final second = await loader.build();
    expect(second, first, reason: '未变更段必须逐字节复用');
  });

  test('G18 变更流失效：写入记忆表后下一次 build 反映新值', () async {
    final loader = deps.loader;
    final before = await loader.build();
    expect(before, contains('（空：还没有长期记忆）'));

    await db
        .into(db.aiMemories)
        .insert(
          AiMemoriesCompanion.insert(
            id: 'mem-1',
            textContent: '周三晚上练腿',
            kind: 'habit',
            domain: 'training',
            source: 'manual',
            createdAt: DateTime.utc(2026, 10, 18),
            updatedAt: DateTime.utc(2026, 10, 18),
          ),
        );
    // 真实事件循环跑一拍让 tableUpdates 送达。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final after = await loader.build();
    expect(after, contains('周三晚上练腿'));
  });

  test('G18 食堂三级查询：窗口树一次装配且计数口径不变', () async {
    final now = DateTime.utc(2026, 10, 18);
    await db
        .into(db.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final repository = deps.canteen;
    for (var w = 0; w < 2; w++) {
      final windowId = await repository.createWindow(
        venueId: 'venue-1',
        name: '窗口$w',
        openTime: '08:00',
        closeTime: '20:00',
      );
      for (var d = 0; d < 3; d++) {
        await repository.createDish(windowId: windowId, name: '菜$w-$d');
      }
    }
    final tree = await repository.listWindowsByVenue(
      venueIds: const ['venue-1'],
    );
    final windows = tree['venue-1']!;
    expect(windows, hasLength(2));
    expect(windows.every((w) => w.dishes.length == 3), isTrue);
    // 地点计数（窗口数/菜品数/已分析数）与旧实现同口径。
    final venues = await repository.listVenues();
    expect(venues.single.windowCount, 2);
    expect(venues.single.dishCount, 6);
    expect(venues.single.analyzedCount, 0);
  });

  test('G18 段级失效：写饮水只重算饮水段，其余段命中缓存', () async {
    final loader = deps.loader;
    final first = await loader.buildParts();
    expect(first.dynamicPart, contains('【今日饮水】'));

    // 只动饮水表。
    await db
        .into(db.waterIntakes)
        .insert(
          WaterIntakesCompanion.insert(
            id: 'water-1',
            localDate: '2026-10-18',
            amountMl: 250,
            recordedAt: DateTime.utc(2026, 10, 18, 9),
            createdAt: DateTime.utc(2026, 10, 18, 9),
            updatedAt: DateTime.utc(2026, 10, 18, 9),
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final second = await loader.buildParts();

    // 饮水段反映新值；餐记录段逐字节未变（段级缓存生效的直接证据）。
    String sectionOf(String text, String title) {
      final start = text.indexOf('【$title】');
      final end = text.indexOf('【', start + 1);
      return text.substring(start, end == -1 ? text.length : end);
    }

    expect(
      sectionOf(second.dynamicPart, '今日饮水'),
      isNot(sectionOf(first.dynamicPart, '今日饮水')),
      reason: '饮水段必须重算',
    );
    expect(
      sectionOf(second.dynamicPart, '今日与昨日的餐记录'),
      sectionOf(first.dynamicPart, '今日与昨日的餐记录'),
      reason: '写饮水不该让餐记录段重算（段级失效）',
    );
    expect(second.stablePrefix, first.stablePrefix);
  });

  test('G17 前缀稳定：动态段写入不会改变稳定前缀（会话内逐字节稳定）', () async {
    final loader = deps.loader;
    final first = await loader.buildParts();
    expect(first.stablePrefix, contains('【饮食偏好与忌口】'));
    expect(first.stablePrefix, contains('【关于用户的长期记忆】'));

    // 写一条餐记录（动态段），再取一次。
    final mealId =
        await MealRepository(
          database: db,
          idGenerator: idGen,
          clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
        ).create(
          MealDraft(
            localDate: '2026-10-18',
            slot: MealSlot.lunch,
            items: [
              MealItemDraft(
                foodName: '测试米饭',
                grams: 100,
                nutrition: const NutritionValues(
                  kcal: 116,
                  proteinGrams: 2.6,
                  carbsGrams: 25.9,
                  fatGrams: 0.3,
                ),
              ),
            ],
          ),
        );
    expect(mealId, isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final second = await loader.buildParts();

    expect(
      second.stablePrefix,
      first.stablePrefix,
      reason: '动态段变化不得影响稳定前缀（前缀缓存的前提）',
    );
    expect(second.dynamicPart, isNot(first.dynamicPart), reason: '动态段必须反映新写入');
  });
  // ── docs/66 §5.2：foodQuery 与 userMessage 拆分（手动编译的路由）────────
  test('build({foodQuery})：食物库预览段只看 foodQuery；门控仍按 userMessage', () async {
    final now = DateTime.utc(2026, 10, 18);
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-0',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'catalog',
            createdAt: now,
            updatedAt: now,
          ),
        );

    // foodQuery 驱动食物库预览：userMessage 是中性寒暄、foodQuery 是目标
    // 回复（含食物名）⇒ 预览段能命中米饭。
    final withFoodQuery = await deps.loader.build(
      userMessage: '你好',
      foodQuery: '你今天中午可以吃米饭 150g',
    );
    expect(withFoodQuery, contains('【食物库参考】'));
    expect(withFoodQuery, contains('米饭'));
    // 菜品推荐门控仍按真实 userMessage：「你好」没有吃/推荐意图 ⇒ 无候选菜品段。
    expect(withFoodQuery, isNot(contains('【候选菜品（本地检索）】')));

    // 不传 foodQuery（旧调用点）：预览退回 userMessage，行为不变。
    final withoutFoodQuery = await deps.loader.build(userMessage: '我中午吃了米饭');
    expect(withoutFoodQuery, contains('米饭'));
  });

  test('build({foodQuery})：foodQuery 为空串时退回 userMessage（不空段）', () async {
    final now = DateTime.utc(2026, 10, 18);
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-0',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'catalog',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final snapshot = await deps.loader.build(
      userMessage: '我中午吃了米饭',
      foodQuery: '   ',
    );
    expect(snapshot, contains('米饭'));
  });
}

final IdGenerator idGen = _SeqIds();

class _SeqIds implements IdGenerator {
  int n = 0;
  @override
  String next() => 'id-${n++}';
}

class _Deps {
  _Deps(this.db);
  final AppDatabase db;

  FoodPreviewSearch get preview => FoodPreviewSearch(database: db);

  DriftChatEditContextLoader get loader => DriftChatEditContextLoader(
    database: db,
    clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
    mealRepository: MealRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
    ),
    dishLibraryRepository: DishLibraryRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
    ),
    waterRepository: WaterRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
    ),
    canteenRepository: canteen,
    workoutPlanRepository: WorkoutPlanRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
    ),
    workoutSessionRepository: WorkoutSessionRepository(
      database: db,
      clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
      idGenerator: idGen,
    ),
    foodPreviewSearch: preview,
  );

  CanteenRepository get canteen => CanteenRepository(
    database: db,
    idGenerator: idGen,
    clock: FixedAppClock(DateTime.utc(2026, 10, 18)),
  );
}
