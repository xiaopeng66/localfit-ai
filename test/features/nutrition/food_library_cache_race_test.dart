import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

void main() {
  late AppDatabase db;
  late FoodRepository foods;
  late FoodLibraryController controller;
  late _HeldSearch interceptor;

  setUp(() async {
    interceptor = _HeldSearch();
    db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    foods = FoodRepository(
      database: db,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 13)),
    );
    await foods.create(_food('米饭', 100));
    await foods.create(_food('鸡蛋', 160));
    controller = FoodLibraryController(
      repository: foods,
      catalogSearch: CatalogSearchService(shardPaths: const []),
    );
  });

  tearDown(() async {
    interceptor.release();
    await db.close();
  });

  test('B07 invalidation retries an in-flight same-query read before publishing or caching it', () async {
    interceptor.holdNext = true;
    final older = controller.page('米饭', offset: 0, limit: 50);
    await interceptor.captured.future;
    await foods.update('cache-food-0', _food('米饭', 250));
    controller.invalidate();
    final fresh = await controller.page('米饭', offset: 0, limit: 50);
    expect(fresh.single.kcalPer100g, 250);
    interceptor.release();
    final late = await older;

    expect(
      late.single.kcalPer100g,
      250,
      reason: 'An invalidated snapshot must not be returned to an awaiting consumer.',
    );
    expect(
      (await controller.page('米饭', offset: 0, limit: 50)).single.kcalPer100g,
      250,
    );
    expect(await controller.count('米饭'), 1);
    expect(
      interceptor.searches,
      2,
      reason: 'A current cached result should satisfy the invalidated waiter without a third query.',
    );
  });

  test(
    'B07 late different-query completion cannot evict the latest cached search',
    () async {
      interceptor.holdNext = true;
      final rice = controller.page('米饭', offset: 0, limit: 50);
      await interceptor.captured.future;
      final eggs = await controller.page('鸡蛋', offset: 0, limit: 50);
      expect(eggs.single.name, '鸡蛋');
      expect(eggs.single.kcalPer100g, 160);
      interceptor.release();
      expect((await rice).single.name, '米饭');
      expect(await controller.count('鸡蛋'), 1);
      expect(
        (await controller.page('鸡蛋', offset: 0, limit: 50)).single.kcalPer100g,
        160,
      );

      expect(
        interceptor.searches,
        2,
        reason:
            'Older requests must not replace the last requested query cache.',
      );
    },
  );

  testWidgets(
    'B07 stale page completion keeps the replacement page request deduplicated',
    (tester) async {
      final paging = _HeldPages(repository: foods);
      var revision = 0;
      late StateSetter rebuild;
      tester.view.physicalSize = const Size(900, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return FoodLibraryView(
                    controller: paging,
                    revision: revision,
                  );
                },
              ),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(paging.requests.length, 1);
        final rice = (await foods.search('米饭')).single;
        await foods.update(rice.id, _food('米饭', 250));
        rebuild(() => revision++);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(paging.requests.length, 2);
        paging.requests.first.complete();
        await tester.pump();
        rebuild(() {});
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          paging.requests.length,
          2,
          reason: 'An old generation must not clear the new generation pending-page marker.',
        );
        paging.requests[1].complete();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FoodCard>(find.byKey(Key('food-library-item-${rice.id}')))
              .kcalPer100g,
          250,
        );
      } finally {
        paging.releaseAll();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      }
    },
  );

  test(
    'B07 invalidation during a read cannot resurrect a deleted search result',
    () async {
      interceptor.holdNext = true;
      final older = controller.page('米饭', offset: 0, limit: 50);
      await interceptor.captured.future;
      await foods.delete('cache-food-0');
      controller.invalidate();
      interceptor.release();

      expect(await older, isEmpty);
      expect(await controller.count('米饭'), 0);
      expect(await controller.page('米饭', offset: 0, limit: 50), isEmpty);
    },
  );
}

NewFood _food(String name, double kcal) => NewFood(
  name: name,
  kcalPer100g: kcal,
  proteinPer100g: 2,
  carbsPer100g: 20,
  fatPer100g: 1,
);

class _Ids implements IdGenerator {
  int value = 0;
  @override
  String next() => 'cache-food-${value++}';
}

class _HeldPages extends FoodLibraryController {
  _HeldPages({required super.repository})
    : super(catalogSearch: CatalogSearchService(shardPaths: const []));

  final requests = <Completer<void>>[];

  @override
  Future<List<FoodLibraryItem>> page(
    String query, {
    required int offset,
    required int limit,
    FoodCategory? category,
  }) async {
    final release = Completer<void>();
    requests.add(release);
    final rows = await super.page(
      query,
      offset: offset,
      limit: limit,
      category: category,
    );
    await release.future;
    return rows;
  }

  void releaseAll() {
    for (final request in requests) {
      if (!request.isCompleted) request.complete();
    }
  }
}

class _HeldSearch extends QueryInterceptor {
  bool holdNext = false;
  int searches = 0;
  final captured = Completer<void>();
  final _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final isSearch = statement.contains('foods') && statement.contains('LIKE');
    final hold = isSearch && holdNext;
    if (isSearch) searches++;
    if (hold) holdNext = false;
    final rows = await executor.runSelect(statement, args);
    if (hold) {
      captured.complete();
      await _released.future;
    }
    return rows;
  }
}
