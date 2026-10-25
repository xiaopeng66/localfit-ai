import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

import '../../support/food_fixture.dart';

/// 单个反斜杠。写成常量而不是内联字面量：`'\'` 在 Dart 里是转义起始符，
/// `r'\'` 又不合法，内联写法很容易在编辑过程中被吃掉一个反斜杠。
const _backslash = '\\';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late ExerciseRepository exercises;
  late FixedAppClock clock;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    clock = FixedAppClock(DateTime.utc(2026, 9, 12, 10));
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  test('searches seeded exercises by name substring', () async {
    final results = await exercises.search('卧推');

    expect(results.map((exercise) => exercise.name), contains('杠铃卧推'));
    expect(results.map((exercise) => exercise.name), contains('哑铃卧推'));
    expect(results.every((exercise) => exercise.name.contains('卧推')), isTrue);
  });

  test('search treats LIKE wildcards as literal text', () async {
    expect(await exercises.search('%'), isEmpty);
    expect(await exercises.search('_'), isEmpty);
    // 反斜杠是 ESCAPE 字符本身：必须先被转义，否则末尾一个 `\` 会把后面
    // 拼上的 `%` 转义掉，通配符逃逸、搜索变成「匹配一切」。
    expect(await exercises.search(_backslash), isEmpty);
    expect(await exercises.search('$_backslash%'), isEmpty);
    expect(await exercises.search('卧%推'), isEmpty);
  });

  test('ranks user-created exercises before seeded ones', () async {
    await exercises.create(
      const NewExercise(
        name: '自定义卧推',
        muscleGroup: MuscleGroup.chest,
        equipment: Equipment.machine,
      ),
    );

    final results = await exercises.search('卧推');

    expect(results.first.name, '自定义卧推');
    expect(results.first.isUserCreated, isTrue);
    expect(results.first.muscleGroup, MuscleGroup.chest);
    expect(results.first.equipment, Equipment.machine);
  });

  test('rejects a blank user exercise name without writing', () async {
    await expectLater(
      exercises.create(
        const NewExercise(
          name: '   ',
          muscleGroup: MuscleGroup.chest,
          equipment: Equipment.barbell,
        ),
      ),
      throwsFormatException,
    );
    expect(await database.select(database.exercises).get(), hasLength(312));
  });

  test('an empty query returns the whole seeded library (limit 500)', () async {
    // docs/28 §7.4：`limit` 从 100 提到 500。种子扩到 312 条后，100 会让
    // 「不搜任何词」的列表少一截，而用户看不出少了（没有分页提示）。
    final results = await exercises.search('');

    expect(results, hasLength(312));
  });

  test('breaks name ties by id, so LIMIT order is stable', () async {
    // docs/28 §7.4：排序末尾补 `id ASC`。v2 里真的存在同名行（两条「绳索
    // 下压」），只按 name 排时 SQLite 对同名的相对顺序不作承诺 —— LIMIT 截断
    // 下取谁看运气。种子 v3 已无重名（另有测试钉住），所以这里只能自己造一对。
    final now = DateTime.utc(2026, 1, 1);
    await database.batch((batch) {
      batch.insertAll(database.exercises, [
        for (final id in ['ex-dup-b', 'ex-dup-a'])
          ExercisesCompanion.insert(
            id: id,
            name: '同名动作',
            muscleGroup: 'chest',
            equipment: 'barbell',
            source: 'seed-v3',
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });

    final results = await exercises.search('同名动作');

    expect(results, hasLength(2));
    expect(results.map((exercise) => exercise.id).toList(), [
      'ex-dup-a',
      'ex-dup-b',
    ]);
  });

  test('loads an exercise by id', () async {
    final seeded = await exercises.search('杠铃深蹲');

    // 扩到 312 条后「杠铃深蹲」不再唯一命中（宽站距/窄站距/箱上…都含这四个字），
    // 所以按名字精确定位，不用 `.single`。
    final loaded = await exercises.getById(
      seeded.firstWhere((exercise) => exercise.name == '杠铃深蹲').id,
    );

    expect(loaded?.name, '杠铃深蹲');
    expect(loaded?.muscleGroup, MuscleGroup.legs);
    expect(loaded?.equipment, Equipment.barbell);
    expect(loaded?.isUserCreated, isFalse);
  });

  test(
    'lists same-muscle-group alternatives without the exercise itself',
    () async {
      final squat = (await exercises.search('杠铃深蹲'))
          .firstWhere((exercise) => exercise.name == '杠铃深蹲');

      final alternatives = await exercises.listAlternatives(squat.id);

      expect(
        alternatives.map((exercise) => exercise.id),
        isNot(contains(squat.id)),
      );
      expect(
        alternatives.every(
          (exercise) => exercise.muscleGroup == MuscleGroup.legs,
        ),
        isTrue,
      );
      // 同组替代按名称升序取前 6 条：随包动作库扩充后具体成员会变，
      // 这里只锁「同肌群、非自身、非空、升序」这些不变量。
      expect(alternatives, isNotEmpty);
      expect(
        alternatives.map((exercise) => exercise.name).toList(),
        orderedEquals(
          alternatives.map((exercise) => exercise.name).toList()..sort(),
        ),
      );
    },
  );

  test('returns empty alternatives for an unknown exercise', () async {
    expect(await exercises.listAlternatives('ex-missing'), isEmpty);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'ex-user-${_value++}';
}
