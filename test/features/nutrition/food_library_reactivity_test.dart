import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show
        Value,
        QueryExecutor,
        QueryInterceptor,
        ApplyInterceptor,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_page.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

final _now = DateTime(2026, 10, 13, 9);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'B07 My manual add refreshes the retained Nutrition count and card',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedProfile();
        await h.seedFood('builtin-1', '原始米饭');
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        expect(_count(tester), '1 种食物');
        final state = tester.state(find.byType(FoodLibraryView));
        await _tap(tester, 'nav-settings');
        await _scrollTo(tester, 'settings-food-data');
        await _tap(tester, 'settings-food-data');
        await _tap(tester, 'food-data-sheet-manual');
        for (final entry in {
          'new-food-name': '新建测试食物',
          'new-food-每 100g 热量': '100',
          'new-food-每 100g 蛋白质': '2',
          'new-food-每 100g 碳水': '20',
          'new-food-每 100g 脂肪': '1',
        }.entries) {
          await tester.enterText(find.byKey(Key(entry.key)), entry.value);
        }
        await _tap(tester, 'new-food-save');
        expect(await h.foods.count(), 2);
        expect(find.text('2 条（自建 1 条）'), findsOneWidget);
        await _tap(tester, 'nav-nutrition');

        expect(
          identical(state, tester.state(find.byType(FoodLibraryView))),
          isTrue,
        );
        expect(_count(tester), '2 种食物');
        expect(find.text('新建测试食物'), findsOneWidget);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B07 My CSV preview execute refreshes retained same-query cache',
    (tester) async {
      final h = _Harness();
      final originalPicker = FilePickerPlatform.instance;
      final picker = _MemoryPicker(
        Uint8List.fromList(
          utf8.encode(
            'name,brand,category,kcal_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g\n'
            '米饭新增,,,100,2,20,1\n',
          ),
        ),
      );
      FilePickerPlatform.instance = picker;
      try {
        await h.seedProfile();
        await h.seedFood('builtin-1', '米饭');
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        expect(_count(tester), '1 种食物');
        final state = tester.state(find.byType(FoodLibraryView));
        await _tap(tester, 'nav-settings');
        await _scrollTo(tester, 'settings-food-data');
        await _tap(tester, 'settings-food-data');
        await _tap(tester, 'food-data-sheet-import');
        expect(picker.calls, 1);
        expect(find.byKey(const Key('food-import-count-new')), findsOneWidget);
        expect(
          await h.foods.count(),
          1,
          reason: 'Preview must not write the new row.',
        );
        await _tap(tester, 'food-import-import-all');
        expect(await h.foods.count(), 2);
        expect((await h.foods.search('新增')).single.kcalPer100g, 100);
        // 2026-10-23：导入行是**内置**，不是自建——自建数保持 0。
        expect(find.text('2 条（自建 0 条）'), findsOneWidget);
        await _tap(tester, 'nav-nutrition');

        expect(
          identical(state, tester.state(find.byType(FoodLibraryView))),
          isTrue,
        );
        expect(_count(tester), '2 种食物');
        expect(find.text('米饭新增'), findsOneWidget);
        await _query(tester, '米饭');
        expect(_count(tester), '2 种食物');
        expect(find.text('米饭新增'), findsOneWidget);
        expect(await h.library.count('米饭'), 2);
      } finally {
        FilePickerPlatform.instance = originalPicker;
        await _close(tester, h);
      }
    },
  );

  // 【测试退役】B07 两条「页尾链」用例随 `RV4-P2-10`（页尾条整族退役，
  // `docs/56` R9）删除：断言的**对象**（`food-library-footer` 的两条链）已不
  // 存在。能力本身没删——导入与「添加食物数据」仍在设置页，由
  // `settings_page` 系列与 `food_import_preview_sheet_test` 覆盖；
  // 「页尾不存在 + 列表末行不被遮挡」由 `food_library_no_footer_test` 反向钉住。

  testWidgets(
    'B07 My clear builtin removes ghost cards and refreshes retained total',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedProfile();
        await h.seedFood('builtin-1', '内置米饭');
        await h.seedFood('builtin-2', '内置鸡蛋');
        await h.seedFood('user-1', '自建食物', user: true);
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        expect(_count(tester), '3 种食物');
        final state = tester.state(find.byType(FoodLibraryView));
        await _tap(tester, 'nav-settings');
        await _scrollTo(tester, 'settings-clear-builtin-foods');
        await _tap(tester, 'settings-clear-builtin-foods');
        await _tap(tester, 'clear-builtin-foods-confirm');
        expect(await h.foods.count(), 1);
        expect(find.text('1 条（自建 1 条）'), findsOneWidget);
        await _tap(tester, 'nav-nutrition');

        expect(
          identical(state, tester.state(find.byType(FoodLibraryView))),
          isTrue,
        );
        expect(_count(tester), '1 种食物');
        expect(
          find.byKey(const Key('food-library-item-builtin-1')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('food-library-item-builtin-2')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('food-library-item-user-1')),
          findsOneWidget,
        );
        await _query(tester, '内置');
        expect(find.text('没有找到这类食物'), findsOneWidget);
      } finally {
        await _close(tester, h);
      }
    },
  );

  for (final query in ['', '米饭']) {
    testWidgets(
      'B07 external repository same-ID update refreshes ${query.isEmpty ? 'browse' : 'search'} with unchanged count',
      (tester) async {
        final h = _Harness();
        try {
          await h.seedFood('user-1', '米饭旧名称', user: true);
          await _mount(tester, h);
          await _tap(tester, 'nutrition-tab-foodlib');
          if (query.isNotEmpty) await _query(tester, query);
          expect(_card(tester, 'user-1').kcalPer100g, 100);
          final external = h.externalRepository();
          await external.update('user-1', _food('米饭新名称', kcal: 250));
          await _frames(tester);

          expect(await external.count(), 1);
          expect((await external.getById('user-1'))!.name, '米饭新名称');
          // Round7 阶段 3（D32）：结果头只有一种措辞了，浏览/搜索的
          // 区分不再由计数文字承担（旧断言读的正是「全部 1 条 / 搜到
          // 1 条」这对措辞）。本条要保护的事实没变：外部改名之后，
          // 两条路径的总数都还是 1——本循环的 `query` 变量仍然分别
          // 跑浏览与搜索两条路径。
          expect(_count(tester), '1 种食物');
          expect(_card(tester, 'user-1').kcalPer100g, 250);
          expect(find.text('米饭新名称'), findsOneWidget);
          expect(find.text('米饭旧名称'), findsNothing);
        } finally {
          await _close(tester, h);
        }
      },
    );
  }

  testWidgets(
    'B07 absent food subtab still invalidates cached search on external create',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedFood('user-1', '米饭', user: true);
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        expect(await h.library.count('米饭'), 1);
        await _tap(tester, 'nutrition-tab-record');
        expect(find.byType(FoodLibraryView), findsNothing);
        await h.externalRepository().create(_food('米饭新增'));
        await _frames(tester);

        expect(
          await h.library.count('米饭'),
          2,
          reason: 'Cache invalidation belongs to the Nutrition page, not the currently mounted subtab.',
        );
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        expect(_count(tester), '2 种食物');
        expect(find.text('米饭新增'), findsOneWidget);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B07 external delete clears same-query ghost and empty cache can reload',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedFood('user-1', '米饭', user: true);
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        final external = h.externalRepository();
        await external.delete('user-1');
        await _frames(tester);

        expect(await external.getById('user-1'), isNull);
        expect(find.byKey(const Key('food-library-item-user-1')), findsNothing);
        expect(find.text('没有找到这类食物'), findsOneWidget);
        expect(await h.library.count('米饭'), 0);
        final created = await external.create(_food('米饭重新添加', kcal: 180));
        await _frames(tester);
        expect(_count(tester), '1 种食物');
        expect(_card(tester, created.id).kcalPer100g, 180);
        expect(find.text('米饭重新添加'), findsOneWidget);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B07 transaction batch triggers one bounded search reload and ignores unrelated writes',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedFood('user-1', '米饭', user: true);
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        final before = h.queries.foodSelects;
        await h.db.transaction(() async {
          await h.foods.createMany([
            for (var i = 0; i < 100; i++) _food('米饭批次 $i'),
          ]);
        });
        await _frames(tester);

        expect(_count(tester), '101 种食物');
        expect(
          h.queries.foodSelects - before,
          1,
          reason:
              'One committed import batch must not schedule per-row searches.',
        );
        expect(
          h.queries.unboundedFoodReads,
          0,
          reason: 'Food change detection must not materialize the food table.',
        );
        final loaded = h.queries.foodSelects;
        await h.seedProfile();
        await _frames(tester);
        expect(h.queries.foodSelects, loaded);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await h.foods.create(_food('米饭卸载后'));
        await tester.pump(const Duration(milliseconds: 1));
        expect(h.queries.foodSelects, loaded);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B07 repository-only Nutrition search also refreshes external same-ID changes',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedFood('user-1', '米饭旧记录', user: true);
        await _mount(tester, h, withController: false);
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        expect(find.text('米饭旧记录'), findsOneWidget);
        await h.externalRepository().update(
          'user-1',
          _food('米饭新记录', kcal: 280),
        );
        await _frames(tester);

        expect(find.text('米饭新记录'), findsOneWidget);
        expect(find.text('米饭旧记录'), findsNothing);
        expect(tester.widget<FoodCard>(find.byType(FoodCard)).kcalPer100g, 280);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B07 replacing the repository rebinds changes and drops the previous page cache',
    (tester) async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarning,
      );
      final first = _Harness();
      final second = _Harness();
      try {
        await first.seedFood('old', '旧数据库食物', user: true);
        await second.seedFood('new', '新数据库食物', user: true, kcal: 200);
        tester.view.physicalSize = const Size(900, 1900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Widget host(_Harness h) => MaterialApp(
          home: NutritionPage(
            repository: h.foods,
            foodLibraryController: h.library,
            mealRepository: MealRepository(
              database: h.db,
              idGenerator: h.ids,
              clock: h.clock,
            ),
            now: _now,
          ),
        );
        await tester.pumpWidget(host(first));
        await _frames(tester);
        await _tap(tester, 'nutrition-tab-foodlib');
        expect(find.text('旧数据库食物'), findsOneWidget);
        await tester.pumpWidget(host(second));
        await _frames(tester);

        expect(find.text('新数据库食物'), findsOneWidget);
        expect(find.text('旧数据库食物'), findsNothing);
        await second.foods.update('new', _food('新数据库已更新', kcal: 300));
        await _frames(tester);
        expect(_card(tester, 'new').kcalPer100g, 300);
        final reads = second.queries.foodSelects;
        await first.foods.update('old', _food('旧库不应刷新新库', kcal: 400));
        await _frames(tester);
        expect(second.queries.foodSelects, reads);
        expect(find.text('新数据库已更新'), findsOneWidget);
      } finally {
        await _close(tester, first);
        await second.db.close();
      }
    },
  );

  testWidgets(
    'B07 direct table replacement refreshes cards without local callbacks',
    (tester) async {
      final h = _Harness();
      try {
        await h.seedFood('user-1', '米饭旧记录', user: true);
        await _mount(tester, h);
        await _tap(tester, 'nutrition-tab-foodlib');
        await _query(tester, '米饭');
        await h.db.transaction(() async {
          await h.db.delete(h.db.foods).go();
          await h.seedFood('user-1', '米饭恢复记录', user: true, kcal: 320);
        });
        await _frames(tester);

        expect(await h.foods.count(), 1);
        expect(_count(tester), '1 种食物');
        expect(_card(tester, 'user-1').kcalPer100g, 320);
        expect(find.text('米饭恢复记录'), findsOneWidget);
        expect(find.text('米饭旧记录'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await h.externalRepository().create(_food('卸载后写入'));
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, h);
      }
    },
  );
}

NewFood _food(String name, {double kcal = 100}) => NewFood(
  name: name,
  kcalPer100g: kcal,
  proteinPer100g: 2,
  carbsPer100g: 20,
  fatPer100g: 1,
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Harness h, {
  bool withController = true,
}) async {
  tester.view.physicalSize = const Size(900, 1900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(h.app(withController: withController));
  await _frames(tester);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await _frames(tester);
}

Future<void> _query(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('food-library-search')), value);
  await _frames(tester);
}

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await _frames(tester);
}

Future<void> _close(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await h.db.close();
  await tester.pump(const Duration(milliseconds: 1));
}

String? _count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('food-library-count'))).data;

FoodCard _card(WidgetTester tester, String id) =>
    tester.widget<FoodCard>(find.byKey(Key('food-library-item-$id')));

class _Harness {
  final queries = _FoodReads();
  late final db = AppDatabase(NativeDatabase.memory().interceptWith(queries));
  final ids = _Ids('nutrition');
  late final clock = FixedAppClock(_now.toUtc());
  late final foods = FoodRepository(
    database: db,
    idGenerator: ids,
    clock: clock,
  );
  late final library = FoodLibraryController(
    repository: foods,
    catalogSearch: CatalogSearchService(shardPaths: const []),
  );

  FoodRepository externalRepository() =>
      FoodRepository(database: db, idGenerator: _Ids('external'), clock: clock);

  LocalFitApp app({bool withController = true}) => LocalFitApp(
    initialLocation: AppRoutes.nutrition,
    now: _now,
    profileIdentityRepository: ProfileIdentityRepository(database: db),
    profileOverviewLoader: LoadProfileOverview(database: db, clock: clock),
    foodRepository: foods,
    foodLibraryController: withController ? library : null,
    mealRepository: MealRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
    ),
    clearBuiltinFoods: ClearBuiltinFoods(db),
  );

  Future<void> seedProfile() async {
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'nutrition-profile',
            activityLevel: 'moderate',
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }

  Future<void> seedFood(
    String id,
    String name, {
    bool user = false,
    double kcal = 100,
  }) async {
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: id,
            name: name,
            kcalPer100g: kcal,
            proteinPer100g: 2,
            carbsPer100g: 20,
            fatPer100g: 1,
            source: user ? 'user' : 'seed',
            isUserCreated: Value(user),
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }
}

class _FoodReads extends QueryInterceptor {
  int foodSelects = 0;
  int unboundedFoodReads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('FROM "foods"')) {
      foodSelects++;
      if (!statement.contains('LIMIT') &&
          !statement.contains('COUNT(') &&
          !statement.contains('count(')) {
        unboundedFoodReads++;
      }
    }
    return executor.runSelect(statement, args);
  }
}

class _Ids implements IdGenerator {
  _Ids(this.prefix);
  final String prefix;
  int value = 0;
  @override
  String next() => '$prefix-food-${value++}';
}

class _MemoryPicker extends FilePickerPlatform {
  _MemoryPicker(this.bytes);
  final Uint8List bytes;
  int calls = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    return _MemoryFile(bytes);
  }
}

final class _MemoryFile extends PlatformFile {
  _MemoryFile(this.bytes);
  final Uint8List bytes;
  @override
  String get name => 'nutrition-regression.csv';
  @override
  Uri get uri => Uri.dataFromBytes(bytes, mimeType: 'text/csv');
  @override
  XFile get xFile => XFile.fromData(bytes, name: name, mimeType: 'text/csv');
  @override
  int lengthSync() => bytes.length;
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}
