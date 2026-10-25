import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late DishLibraryRepository dishes;
  final now = DateTime.utc(2026, 9, 28, 12);

  DishDraft draft({
    String name = '番茄炒蛋',
    String mealSlot = 'lunch',
    double kcal = 142,
    double proteinG = 8.4,
    double carbsG = 6.2,
    double fatG = 9.1,
    String source = 'manual',
    String? servingWindow,
    bool isHot = false,
    double? fiberG,
    double? sodiumMg,
    double? vitaminDMcg,
    String? comment,
    String? imagePath,
  }) => DishDraft(
    name: name,
    mealSlot: mealSlot,
    kcal: kcal,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    source: source,
    servingWindow: servingWindow,
    isHot: isHot,
    fiberG: fiberG,
    sodiumMg: sodiumMg,
    vitaminDMcg: vitaminDMcg,
    comment: comment,
    imagePath: imagePath,
  );

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  test('创建的菜品按餐次分组、组内保持创建顺序', () async {
    await dishes.create(draft(name: '小米粥', mealSlot: 'breakfast'));
    await dishes.create(draft(name: '番茄炒蛋'));
    await dishes.create(draft(name: '香菇青菜', mealSlot: 'dinner'));
    await dishes.create(draft(name: '清蒸鲈鱼'));

    final all = await dishes.watchAll().first;
    expect(all.map((dish) => '${dish.mealSlot}/${dish.name}'), [
      'breakfast/小米粥',
      'dinner/香菇青菜',
      'lunch/番茄炒蛋',
      'lunch/清蒸鲈鱼',
    ]);
  });

  test('按餐次过滤只返回该餐次的菜', () async {
    await dishes.create(draft(name: '小米粥', mealSlot: 'breakfast'));
    await dishes.create(draft(name: '番茄炒蛋'));

    final lunch = await dishes
        .watchAll(filter: const DishLibraryFilter(mealSlot: 'lunch'))
        .first;
    expect(lunch.map((dish) => dish.name), ['番茄炒蛋']);
  });

  test('热门过滤只看 isHot，AI 生成的菜默认不进热门', () async {
    await dishes.create(draft(name: '番茄炒蛋', isHot: true));
    await dishes.create(draft(name: '清蒸鲈鱼'));
    await dishes.create(
      draft(name: '牛肉面', source: 'ai_generated', isHot: false),
    );

    final hot = await dishes.watchHot().first;
    expect(hot.map((dish) => dish.name), ['番茄炒蛋']);
  });

  test('创建时保留营养师点评、供应时段与微量营养素', () async {
    final created = await dishes.create(
      draft(
        name: '番茄炒蛋',
        servingWindow: '11:00-13:30',
        fiberG: 1.4,
        sodiumMg: 620,
        vitaminDMcg: 1.2,
        comment: '蛋白质偏少，建议搭配一份豆制品。',
      ),
    );

    expect(created.servingWindow, '11:00-13:30');
    expect(created.fiberG, 1.4);
    expect(created.sodiumMg, 620);
    expect(created.vitaminDMcg, 1.2);
    expect(created.comment, '蛋白质偏少，建议搭配一份豆制品。');
    expect(created.createdAt, now);
    expect(created.updatedAt, now);

    final reloaded = (await dishes.watchAll().first).single;
    expect(reloaded.fiberG, 1.4);
    expect(reloaded.comment, '蛋白质偏少，建议搭配一份豆制品。');
  });

  test('空白点评与空白时段落库为 null（界面据此不渲染该块）', () async {
    final created = await dishes.create(
      draft(comment: '   ', servingWindow: '  '),
    );

    expect(created.comment, isNull);
    expect(created.servingWindow, isNull);

    final reloaded = (await dishes.watchAll().first).single;
    expect(reloaded.comment, isNull);
    expect(reloaded.servingWindow, isNull);
  });

  test('空白图片路径折算成 null（否则会去加载空路径）', () async {
    final created = await dishes.create(draft(imagePath: '  '));
    expect(created.imagePath, isNull);
    expect((await dishes.watchAll().first).single.imagePath, isNull);

    final withPhoto = await dishes.create(
      draft(name: '牛肉面', imagePath: 'E:/photos/beef-noodle.jpg'),
    );
    expect(withPhoto.imagePath, 'E:/photos/beef-noodle.jpg');
  });

  test('菜名首尾空白被去掉，纯空白菜名被拒绝', () async {
    final created = await dishes.create(draft(name: '  番茄炒蛋  '));
    expect(created.name, '番茄炒蛋');

    expect(
      () => dishes.create(draft(name: '   ')),
      throwsA(isA<FormatException>()),
    );
    expect(await dishes.watchAll().first, hasLength(1));
  });

  test('数值越界被拒且不落库', () async {
    Future<void> expectRejected(DishDraft bad) async {
      await expectLater(
        dishes.create(bad),
        throwsA(isA<FormatException>()),
        reason: '越界草稿必须被拒绝',
      );
    }

    await expectRejected(draft(kcal: 901));
    await expectRejected(draft(kcal: -1));
    await expectRejected(draft(proteinG: 101));
    await expectRejected(draft(fiberG: 101));
    await expectRejected(draft(sodiumMg: 20001));
    await expectRejected(draft(vitaminDMcg: 201));
    await expectRejected(draft(servingWindow: '11:00'));

    expect(await dishes.watchAll().first, isEmpty, reason: '一次都不能落库');
  });

  test('供应时段结束早于开始被拒', () async {
    expect(
      () => dishes.create(draft(servingWindow: '13:30-11:00')),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => dishes.create(draft(servingWindow: '11:00-11:00')),
      throwsA(isA<FormatException>()),
    );
  });

  test('删除返回被删记录，供撤销回写；删不存在的返回 null', () async {
    final created = await dishes.create(draft(name: '番茄炒蛋'));

    final removed = await dishes.delete(created.id);
    expect(removed?.name, '番茄炒蛋');
    expect(await dishes.watchAll().first, isEmpty);

    expect(await dishes.delete(created.id), isNull);

    await dishes.restore(removed!);
    final restored = (await dishes.watchAll().first).single;
    expect(restored.id, created.id);
    expect(restored.name, '番茄炒蛋');
    expect(restored.kcal, 142);
    expect(restored.source, 'manual');
  });

  test('无目标时占比返回 null（界面不画进度条）', () async {
    final created = await dishes.create(draft(kcal: 142));
    expect(created.targetProgress(null), isNull);
    expect(created.targetProgress(0), isNull);
    expect(created.targetProgress(2000), closeTo(0.071, 0.0001));
  });

  test('占比夹在 0..1，超目标的菜不会画出溢出条', () async {
    final created = await dishes.create(draft(kcal: 880));
    expect(created.targetProgress(300), 1.0);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'dish-${_value++}';
}
