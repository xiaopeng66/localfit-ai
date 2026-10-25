import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';
import 'package:localfit_ai/features/campus_menus/presentation/menu_tab_view.dart';
import 'package:localfit_ai/features/nutrition/application/add_canteen_dishes_to_library.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 食堂目录 ⇄ 菜品库**是同一个库**（2026-10-24 用户：
/// 「加入菜品目录里不能自动加入菜品库吗…我希望他们就是一个库，不要分开，
/// 不要自己加入。这样就不需要整理重复菜品和关联到食堂菜品」）。
///
/// 这份用例取代了原来窗口卡上那个「加入菜品库 N 道」按钮的用例：
/// 装配方式与 `main.dart` 一致（仓储钩子 → 自动同步服务），因此它同时钉住
/// 「接线断了会自动同步消失」这条最容易复发的缺口。
void main() {
  late AppDatabase database;
  late CanteenRepository canteen;
  late DishLibraryRepository dishes;
  late AddCanteenDishesToLibrary sync;
  final now = DateTime.utc(2026, 9, 28, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _Ids('dish'),
      clock: FixedAppClock(now),
    );
    // 与 main.dart 同构：仓储先建、服务后建，钩子在写入那一刻才解引用。
    late final AddCanteenDishesToLibrary service;
    canteen = CanteenRepository(
      database: database,
      idGenerator: _Ids('canteen'),
      clock: FixedAppClock(now),
      onDishUpserted: (dishId) => service.syncDish(dishId),
      onDishDeleted: (dishId) => service.removeDish(dishId),
    );
    service = AddCanteenDishesToLibrary(dishLibrary: dishes, canteen: canteen);
    sync = service;
  });

  tearDown(() => database.close());

  Future<String> seedWindow({
    String openTime = '11:00',
    String closeTime = '13:30',
  }) async {
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    return canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: openTime,
      closeTime: closeTime,
    );
  }

  Future<String> seedAnalyzedDish(
    String windowId, {
    String name = '番茄炒蛋',
    double kcalPer100g = 142,
    String origin = 'ai_estimate',
  }) async {
    final dishId = await canteen.createDish(windowId: windowId, name: name);
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: kcalPer100g,
      proteinPer100g: 8.4,
      carbsPer100g: 6.2,
      fatPer100g: 9.1,
      grade: 'B',
      confidence: 0.8,
      origin: origin,
    );
    return dishId;
  }

  test('建菜（还没营养）：菜品库里不写空卡，等分析完自动进', () async {
    final windowId = await seedWindow();
    await canteen.createDish(windowId: windowId, name: '红烧肉');

    expect(
      await database.select(database.dishLibrary).get(),
      isEmpty,
      reason: '没有营养的菜进库只会得到一张全是「—」的卡；不进库才是诚实的',
    );
  });

  test('写营养即自动进菜品库：一行、按来源键、值 = per100g × 份量', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId);
    // 同一道菜再分析一次（用户改了依据/重跑）：仍然是同一行。
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 150,
      proteinPer100g: 8.4,
      carbsPer100g: 6.2,
      fatPer100g: 9.1,
      grade: 'B',
      confidence: 0.8,
    );

    final rows = await database.select(database.dishLibrary).get();
    expect(rows, hasLength(1), reason: '一个库：一道菜一行');
    expect(rows.single.name, '番茄炒蛋');
    expect(rows.single.sourceType, kCanteenSourceType);
    expect(rows.single.sourceId, dishId);
    expect(rows.single.kcal, 150, reason: '份量缺省 100g ⇒ 每份 = per100g');
    expect(
      rows.single.mealSlot,
      'lunch',
      reason: '窗口 11:00–13:30 ⇒ 午餐（落库存枚举值）',
    );
    expect(rows.single.servingWindow, '11:00-13:30');
    expect(rows.single.source, 'ai_estimate');
  });

  test('手填营养来源如实标 manual；引用食物库标 food_library', () async {
    final windowId = await seedWindow();
    await seedAnalyzedDish(windowId, name: '手填菜', origin: 'user_input');
    await seedAnalyzedDish(windowId, name: '引用菜', origin: 'food_library');

    final rows = {
      for (final row in await database.select(database.dishLibrary).get())
        row.name: row.source,
    };
    expect(rows['手填菜'], 'manual');
    expect(rows['引用菜'], 'food_library');
  });

  test('改名：同一行更新，不新增第二张同名卡', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId);
    final beforeId =
        (await database.select(database.dishLibrary).getSingle()).id;

    await canteen.updateDish(dishId: dishId, name: '番茄炒蛋（微辣）');

    final rows = await database.select(database.dishLibrary).get();
    expect(rows, hasLength(1), reason: '改名不是新建');
    expect(rows.single.id, beforeId, reason: 'id 稳定 ⇒ 菜单页排序/引用不跳');
    expect(rows.single.name, '番茄炒蛋（微辣）');
    expect(rows.single.sourceId, dishId);
  });

  test('改份量：每份值跟着重算，仍是同一行', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId);

    await canteen.updateDishTagsAndIngredients(
      dishId: dishId,
      tags: const [],
      ingredients: CanteenIngredientInfo.empty,
      servingGrams: 200,
      setServingGrams: true,
    );

    final row = await database.select(database.dishLibrary).getSingle();
    expect(row.servingGrams, 200);
    expect(row.kcal, 284, reason: '142 × 200/100');
  });

  test('删菜：菜品库同源行跟着删，不留幽灵', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId);
    expect(await database.select(database.dishLibrary).get(), hasLength(1));

    await canteen.deleteDish(dishId);

    expect(await database.select(database.dishLibrary).get(), isEmpty);
  });

  test('删窗口：窗口下所有菜的库行一起删；删地点同理', () async {
    final windowId = await seedWindow();
    await seedAnalyzedDish(windowId, name: '菜一');
    await seedAnalyzedDish(windowId, name: '菜二');
    expect(await database.select(database.dishLibrary).get(), hasLength(2));

    await canteen.deleteWindow(windowId);
    expect(await database.select(database.dishLibrary).get(), isEmpty);

    // 地点级：重建一个地点/窗口/菜，再删地点。
    final venueId = await canteen.createVenue(name: '西区食堂', campusName: '');
    final window2 = await canteen.createWindow(
      venueId: venueId,
      name: '二楼',
      openTime: '17:00',
      closeTime: '19:30',
    );
    await seedAnalyzedDish(window2, name: '菜三');
    expect(await database.select(database.dishLibrary).get(), hasLength(1));

    await canteen.deleteVenue(venueId);
    expect(await database.select(database.dishLibrary).get(), isEmpty);
  });

  test('同步失败不阻断目录写入（派生视图的取舍）', () async {
    final windowId = await seedWindow();
    final failing = CanteenRepository(
      database: database,
      idGenerator: _Ids('failing'),
      clock: FixedAppClock(now),
      onDishUpserted: (_) async => throw StateError('boom'),
    );
    final dishId = await failing.createDish(windowId: windowId, name: '番茄炒蛋');
    await failing.recordNutrition(
      dishId: dishId,
      kcalPer100g: 100,
      proteinPer100g: 1,
      carbsPer100g: 1,
      fatPer100g: 1,
      grade: 'C',
      confidence: 0.5,
    );

    expect(
      (await failing.findDish(dishId))?.name,
      '番茄炒蛋',
      reason: '钩子抛异常不该让「菜没建成」',
    );
    // 修好钩子后可补同步（重新分析或补一次 syncDish 都会补齐）。
    await sync.syncDish(dishId);
    expect(await database.select(database.dishLibrary).get(), hasLength(1));
  });

  // 2026-10-24 复核抓到的自伤：`_updated` 原先把 `userEdited` 直接写成草稿值
  // （默认 false），于是一次自动同步就把用户「我手改过这一行」的标记抹掉。
  // 【语义变更，不是删断言换绿】`RV4-P2-09`（`docs/56` R10-c，已锁裁决 D2）：
  // 自动同步现在**跳过** `userEdited` 行（用户手改即冻结）。
  // 这条用例原来断言「标记置位、但**数值仍跟着来源走**（160）」——那正是
  // 决策要改掉的行为（用户改的数被悄悄改回去）。断言的**对象语义变了**：
  // 从「只置位不清零」变为「置位 + 数值冻结」，强度不降（另加 `userEdited` 仍为 true）。
  test('自动同步不清零「我手改过」标记，且数值被冻结（P2-09）', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId);
    final before = await database.select(database.dishLibrary).getSingle();
    await (database.update(database.dishLibrary)
          ..where((row) => row.id.equals(before.id)))
        .write(const DishLibraryCompanion(userEdited: Value(true)));

    // 重新分析一次：自动同步会 upsert 同一行。
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 160,
      proteinPer100g: 8.4,
      carbsPer100g: 6.2,
      fatPer100g: 9.1,
      grade: 'B',
      confidence: 0.8,
    );

    final after = await database.select(database.dishLibrary).getSingle();
    expect(after.id, before.id, reason: '同一行');
    expect(after.kcal, 142, reason: '用户手改即冻结：数值保持用户的值（P2-09 之前的断言是 160）');
    expect(after.userEdited, isTrue, reason: '标记不能被自动同步清零');
  });

  test('升级补齐 backfillAll：老库里「分析过没加过」的菜一次补进菜品库，幂等', () async {
    final windowId = await seedWindow();
    await seedAnalyzedDish(windowId, name: '菜一');
    await seedAnalyzedDish(windowId, name: '菜二');
    await canteen.createDish(windowId: windowId, name: '还没分析的菜');
    // 模拟老版本：把已经写进去的两行删掉（相当于用户从没点过「加入菜品库」）。
    await database.delete(database.dishLibrary).go();

    final first = await sync.backfillAll();
    expect(first.written, 2, reason: '只补已分析的');
    expect(first.skipped, 1, reason: '未分析的如实计跳过');
    expect(await database.select(database.dishLibrary).get(), hasLength(2));

    final second = await sync.backfillAll();
    expect(second.written, 2, reason: '第二次仍是同一批（按来源 upsert）');
    final rows = await database.select(database.dishLibrary).get();
    expect(rows, hasLength(2), reason: '幂等：不产生重复行');
  });

  test('syncDish：菜不存在时是空操作（不抛、不写）', () async {
    final result = await sync.syncDish('ghost');
    expect(result.written, 0);
    expect(await database.select(database.dishLibrary).get(), isEmpty);
  });

  // ---------- RV4-P1-03：照片必须进菜品库 ----------
  //
  // 审查结论（`docs/57` §3 + 变异 M2）：`AddCanteenDishesToLibrary.run` 构造
  // `DishDraft` 时**没传 `imagePath`** ⇒ 菜品库那一行的 `imagePath` 恒为 null，
  // `DishCard` 那套 4:3 封面 + `Image.file` 永远走渐变占位。
  // 变异实验证明：把 `imagePath` 补上后 **12 条测试全绿不变** = 零覆盖。
  // 下面三条补上这个盲区。

  test('P1-03 带照片的食堂菜 → 菜品库同一行有同一个 imagePath', () async {
    final windowId = await seedWindow();
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '有照片的菜',
      imagePath: 'photos/a.jpg',
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 200,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 8,
      grade: 'B',
      confidence: 0.8,
    );

    final row = await database.select(database.dishLibrary).getSingle();
    expect(row.imagePath, 'photos/a.jpg', reason: '照片必须跟着进菜品库（否则卡上永远只有渐变占位）');
  });

  test('P1-03 换照片：同一行跟着换', () async {
    final windowId = await seedWindow();
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '换照片的菜',
      imagePath: 'photos/old.jpg',
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 200,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 8,
      grade: 'B',
      confidence: 0.8,
    );
    await canteen.updateDish(
      dishId: dishId,
      name: '换照片的菜',
      imagePath: 'photos/new.jpg',
      setImagePath: true,
    );

    final row = await database.select(database.dishLibrary).getSingle();
    expect(row.imagePath, 'photos/new.jpg');
  });

  test('P1-03 删照片：同一行跟着清空（不留幽灵路径）', () async {
    final windowId = await seedWindow();
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '删照片的菜',
      imagePath: 'photos/old.jpg',
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 200,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 8,
      grade: 'B',
      confidence: 0.8,
    );
    await canteen.updateDish(
      dishId: dishId,
      name: '删照片的菜',
      imagePath: null,
      setImagePath: true,
    );

    final row = await database.select(database.dishLibrary).getSingle();
    expect(row.imagePath, isNull, reason: '删了照片，库里不该还留着旧路径');
  });

  // ---------- RV4-P2-09：用户手改即冻结 ----------
  //
  // 决策 D2 之后「陈旧提示 + 手动同步」整族退役，自动同步成为唯一路径。
  // 这条路径必须**尊重用户手改**：`userEdited` 的行不被食堂侧的更新覆盖，
  // 否则「我改的数字被悄悄改回去」比不更新更严重。

  test('P2-09 用户手改后食堂再写营养 → 菜品库仍是用户的值（手改即冻结）', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId, kcalPer100g: 142);
    final before = await database.select(database.dishLibrary).getSingle();
    // 用户手改：营养 + userEdited 标记（界面上改营养写的就是同两列）。
    await (database.update(
      database.dishLibrary,
    )..where((row) => row.id.equals(before.id))).write(
      const DishLibraryCompanion(
        kcal: Value(99),
        proteinG: Value(1),
        carbsG: Value(1),
        fatG: Value(1),
        source: Value('manual'),
        userEdited: Value(true),
      ),
    );

    // 食堂侧再分析一次（新值 160）。
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 160,
      proteinPer100g: 8.4,
      carbsPer100g: 6.2,
      fatPer100g: 9.1,
      grade: 'B',
      confidence: 0.8,
    );

    final after = await database.select(database.dishLibrary).getSingle();
    expect(after.id, before.id, reason: '仍是同一行');
    expect(after.kcal, 99, reason: '用户手改的值必须冻结（自动同步不得覆盖 userEdited 行）');
    expect(after.userEdited, isTrue);
  });

  test('P2-09 用户没手改时自动同步照常生效（冻结只对 userEdited 行）', () async {
    final windowId = await seedWindow();
    final dishId = await seedAnalyzedDish(windowId, kcalPer100g: 142);
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 160,
      proteinPer100g: 8.4,
      carbsPer100g: 6.2,
      fatPer100g: 9.1,
      grade: 'B',
      confidence: 0.8,
    );
    final after = await database.select(database.dishLibrary).getSingle();
    expect(after.kcal, 160, reason: '没手改的行跟着来源走（原有行为不变）');
  });

  testWidgets('窗口卡上不再有「加入菜品库」按钮（自动同步取代手动入口）', (tester) async {
    final windowId = await seedWindow();
    await seedAnalyzedDish(windowId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MenuTabView(repository: canteen)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('canteen-add-to-library-$windowId')),
      findsNothing,
      reason: '2026-10-24：用户不需要自己加入，按钮整枚退场',
    );
    expect(find.textContaining('加入菜品库'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);
  final String _prefix;
  var _value = 0;

  @override
  String next() => '$_prefix-${++_value}';
}
