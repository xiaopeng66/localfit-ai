// 重复可见化的取数层（ExistingFactProbe）：用真实内存库验证「查今天已有」。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/existing_fact_probe.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

final _today = DateTime.utc(2026, 11, 7, 12);

void main() {
  late AppDatabase db;
  late WaterRepository water;
  late MeasurementRepository weight;
  late MealRepository meals;
  final registry = ChatEditCommandRegistry();
  final idGen = _SeqIds();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    water = WaterRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(_today),
    );
    weight = MeasurementRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(_today),
    );
    meals = MealRepository(
      database: db,
      idGenerator: idGen,
      clock: FixedAppClock(_today),
    );
  });

  tearDown(() => db.close());

  ExistingFactProbe probe() => ExistingFactProbe(
    mealRepository: meals,
    waterRepository: water,
    measurementRepository: weight,
    clock: FixedAppClock(_today),
  );

  ChatEditTurn turnOf(List<(String, Map<String, Object>)> commands) {
    return ChatEditTurn(
      reply: '记一下',
      rows: [
        for (var i = 0; i < commands.length; i++)
          ChatEditTurnItem(
            index: i,
            raw: {'action': commands[i].$1, 'args': commands[i].$2},
            command: ChatEditCommand(
              spec: registry.specOf(commands[i].$1)!,
              args: validateChatEditArgs(
                registry.specOf(commands[i].$1)!,
                commands[i].$2,
              ),
            ),
          ),
      ],
    );
  }

  test('饮水：今天已有相同容量 ⇒ 提示；不同容量 ⇒ 不提示', () async {
    await water.add(localDate: '2026-11-07', amountMl: 250);
    await water.add(localDate: '2026-11-07', amountMl: 250);

    final same = await probe().call(
      turnOf([
        ('water.add', {'amountMl': 250.0}),
      ]),
    );
    expect(same[0], contains('2 次'));
    expect(same[0], contains('250ml'));

    final different = await probe().call(
      turnOf([
        ('water.add', {'amountMl': 300.0}),
      ]),
    );
    expect(different, isEmpty);
  });

  test('体重：今天已有 ⇒ 提示会覆盖；没有 ⇒ 不提示', () async {
    // 体重写入需要先有本地建档（正常 App 流程由引导页完成）。
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: _today,
            updatedAt: _today,
          ),
        );
    await weight.saveManualWeight(localDate: '2026-11-07', weightKg: 72.5);

    final hits = await probe().call(
      turnOf([
        ('weight.log', {'weightKg': 73.0}),
      ]),
    );
    expect(hits[0], contains('72.5'));
    expect(hits[0], contains('覆盖'));

    // 补记昨天：不同日期不该提示（今天是 11-07）。
    final otherDay = await probe().call(
      turnOf([
        ('weight.log', {'weightKg': 73.0, 'localDate': '2026-11-06'}),
      ]),
    );
    expect(otherDay, isEmpty);
  });

  test('记餐：空库 ⇒ 无提示（不会凭空说「已有」）', () async {
    final hints = await probe().call(
      turnOf([
        (
          'meal.create',
          {
            'slot': '午餐',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          },
        ),
      ]),
    );
    expect(hints, isEmpty);
  });

  test('探针不认识的命令（删除/新建）不给提示', () async {
    final hints = await probe().call(
      turnOf([
        ('water.delete', {'waterId': 'nope'}),
        (
          'food.create',
          {
            'name': '自制蛋糕',
            'kcalPer100g': 350,
            'proteinPer100g': 6,
            'carbsPer100g': 40,
            'fatPer100g': 18,
          },
        ),
      ]),
    );
    expect(hints, isEmpty);
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
