import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';

import '../../support/food_fixture.dart';

/// 阶段 5 验收项「训练筛选真实影响列表」的行为测试。
///
/// 这条验收在原追踪表里挂在 `training-muscle-filter` 名下，但此前只有
/// **key 唯一性审计**（`route_unique_key_audit_test.dart`）提到它——那只证明
/// 屏上没有重复 key，**不证明筛选真的改变了列表内容**。这里守的是后者。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late ExerciseRepository exercises;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex-user'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 27, 10)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget page() =>
      MaterialApp(home: ExerciseLibraryPage(repository: exercises));

  /// 前缀相同但不是动作卡的 key（见 [visibleExerciseIds]）。
  const controlKeys = {
    'training-exercise-name',
    'training-exercise-muscle-group',
    'training-exercise-equipment',
    'training-exercise-save',
    'training-exercise-add',
    'training-exercise-search',
    'training-exercise-library-back',
  };

  /// 屏上当前渲染的动作卡 id 集合。
  ///
  /// 2026-10-03 改判理由（不是放宽判据）：原先遍历 `find.byType(InkWell)`——
  /// key 曾挂在网格 tile 自己画的 `InkWell` 上。卡片统一化后 tile 改走
  /// `DesignCard`（§2.3），key 随之落在 `DesignCard` 上，按实现类型遍历会
  /// 拿到 0 个（实测）。改成**从元素树收集**：与「key 挂在哪个实现件上」
  /// 解耦，断言语义仍是「屏上出现了哪些 `training-exercise-*` key」。
  Set<String> visibleExerciseIds(WidgetTester tester) {
    final ids = <String>{};
    for (final element in tester.allElements) {
      final key = element.widget.key;
      if (key is! ValueKey<String>) continue;
      final value = key.value;
      if (!value.startsWith('training-exercise-')) continue;
      // 同前缀的**控件** key（表单字段 / 顶栏 / 搜索框），不是动作卡：
      // 动作卡的 key 形如 `training-exercise-<动作id>`。
      if (controlKeys.contains(value)) continue;
      ids.add(value.substring('training-exercise-'.length));
    }
    return ids;
  }

  /// 筛选行里那枚肌群 chip。
  ///
  /// 限定在 `training-muscle-filter` 之内：格子副标题是「胸 · 杠铃」这类
  /// 拼接串（不会与裸肌群名撞车），但把定位收窄后这条测试就不依赖格子
  /// 文案的措辞。
  Finder chip(String label) => find.descendant(
    of: find.byKey(const Key('training-muscle-filter')),
    matching: find.text(label),
  );

  testWidgets('肌群筛选真实改变列表内容（不是只换 chip 高亮）', (tester) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final all = visibleExerciseIds(tester);
    expect(
      all.length,
      greaterThan(6),
      reason: '种子库应有多个动作；实际只渲染了 ${all.length} 个',
    );

    // 「列表变短了」要用**滚动体量**判，不能用屏上卡片数判。
    //
    // 2026-10-04 改判理由（不是放宽判据）：动作库扩到 312 条后，全量列表与任一
    // 单肌群列表都比视口高得多（视口 1700dp ≈ 8 行 16 格，chest 也有 42 条），
    // 屏上卡片数被视口钉死，两边都是 16 —— 「可见数」在这个尺度下量不出差别，
    // 而用户真正能感觉到的是「还有多少可滚」。maxScrollExtent 反映的是整表长度，
    // 不受视口与懒构建影响。
    final gridScrollable = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Scrollable),
    );
    double maxExtent() =>
        tester.state<ScrollableState>(gridScrollable).position.maxScrollExtent;

    final allExtent = maxExtent();
    expect(allExtent, greaterThan(0), reason: '全量列表应可滚动');

    // 逐一点肌群 chip，断言列表**真的变窄**且窄出来的项都属于该肌群。
    var trimmedAny = false;
    for (final group in MuscleGroup.values) {
      final chipFinder = chip(group.label);
      if (chipFinder.evaluate().isEmpty) continue;
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      final filtered = visibleExerciseIds(tester);
      expect(
        filtered.length,
        lessThanOrEqualTo(all.length),
        reason: '筛选「${group.label}」后不应出现更多动作',
      );
      if (maxExtent() < allExtent) trimmedAny = true;

      // 筛选结果里每个动作的肌群都必须等于选中项。
      for (final id in filtered) {
        final record = await exercises.getById(id);
        expect(
          record?.muscleGroup,
          group,
          reason: '筛选「${group.label}」却出现了肌群为 ${record?.muscleGroup} 的动作 $id',
        );
      }
    }
    expect(trimmedAny, isTrue, reason: '至少有一个肌群筛选应真的缩减列表');

    // 点回「全部」应恢复完整列表。
    await tester.tap(chip('全部'));
    await tester.pumpAndSettle();
    expect(visibleExerciseIds(tester), all, reason: '「全部」应恢复筛选前的完整列表');
    expect(maxExtent(), allExtent, reason: '「全部」应恢复整表长度');
  });

  testWidgets('筛选与搜索叠加生效', (tester) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 先按肌群收窄。
    final group = MuscleGroup.chest;
    await tester.tap(chip(group.label));
    await tester.pumpAndSettle();
    final byGroup = visibleExerciseIds(tester);
    expect(byGroup, isNotEmpty, reason: '胸部应有种子动作');

    // 再叠加一个能命中其中一项的搜索词。
    final sample = await exercises.getById(byGroup.first);
    final keyword = sample!.name.characters.first;
    await tester.enterText(
      find.byKey(const Key('training-exercise-search')),
      keyword,
    );
    await tester.pumpAndSettle();

    final both = visibleExerciseIds(tester);
    expect(both.length, lessThanOrEqualTo(byGroup.length), reason: '叠加搜索后不应变多');
    for (final id in both) {
      final record = await exercises.getById(id);
      expect(record?.muscleGroup, group, reason: '叠加搜索后仍须满足肌群条件');
      expect(
        record!.name.contains(keyword),
        isTrue,
        reason: '叠加搜索后「${record.name}」不含关键词「$keyword」',
      );
    }
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}
