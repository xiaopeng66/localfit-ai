import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../../../support/food_fixture.dart';

/// **快照必须告诉模型「上一张卡还没应用」**（2026-10-24 多轮实测）。
///
/// 用户要求「AI 要能正确调用软件功能，而不是只回复不操作」。多轮实测
/// （`ai_live_multi_turn_test.dart` 剧本 T02）暴露了一个真实的交互死角：
///
/// > 用户：我中午吃了米饭和鸡胸肉
/// > AI：（给出一张待应用卡片）我准备把午餐记为米饭 150g、鸡胸肉 150g
/// > 用户：米饭改成 100 克
/// > AI：**还没生成这条午餐记录，所以暂时改不了克数。等你应用上一步的
/// >     午餐记录后，我再把米饭改成 100 克。**
///
/// 模型说得**没错**——数据库里确实还没有那条记录（用户没点「应用」）。
/// 但它看不见「上一张卡还挂在屏幕上等着点」，于是把用户打发去点一次、
/// 再说一遍。用户要两步才能做完一件事，而且第二遍还得自己重述。
///
/// 修法：给快照加一段「**尚未应用的提议**」，把上一轮信封里的命令原样
/// 告诉模型。模型就知道「这三条是待应用状态，用户这句改口应当直接给一份
/// 新的、合并后的完整提议」，而不是让用户先应用再改。
///
/// 本文件只钉**快照的内容契约**（不改 wire、不改命令表）。
void main() {
  late AppDatabase database;
  late DriftChatEditContextLoader loader;

  final clock = FixedAppClock(DateTime(2026, 10, 24, 12).toUtc());
  final ids = _Ids();

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    loader = DriftChatEditContextLoader(
      database: database,
      clock: clock,
      mealRepository: MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      dishLibraryRepository: DishLibraryRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      waterRepository: WaterRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      canteenRepository: canteen,
      workoutPlanRepository: WorkoutPlanRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      workoutSessionRepository: WorkoutSessionRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
    );
  });

  tearDown(() => database.close());

  group('快照的「尚未应用的提议」段', () {
    test('传了待应用提议 → 段里出现命令名与关键参数', () async {
      final text = await loader.build(
        userMessage: '米饭改成 100 克',
        pendingProposal: const PendingProposal(
          summary: '我准备把午餐记为米饭 150g、鸡胸肉 150g',
          commands: [
            (
              action: 'meal.create',
              args: {
                'slot': 'lunch',
                'items': [
                  {'food': '米饭', 'grams': 150},
                  {'food': '鸡胸肉', 'grams': 150},
                ],
              },
            ),
          ],
        ),
      );
      expect(text, contains('尚未应用'), reason: '必须有一段明确告诉模型「上一张卡还等着点应用」');
      expect(text, contains('meal.create'));
      expect(text, contains('米饭'));
      expect(text, contains('150'));
      // 关键：必须点明「用户还没点应用，库里还没有这条记录」——否则模型
      // 仍会像实测那样回答「还没生成这条记录，改不了」。
      expect(
        text,
        anyOf(
          contains('还没点「应用」'),
          contains('还没点应用'),
          contains('尚未点应用'),
          contains('未点「应用」'),
        ),
        reason: '要明确告诉模型「数据库里还没有这条」的原因',
      );
    });

    test('没传待应用提议 → 不出现该段（旧行为完全不变）', () async {
      final text = await loader.build(userMessage: '今天吃了什么');
      expect(text, isNot(contains('尚未应用')));
    });

    test('传了空 commands → 等于没有提议，不出该段', () async {
      final text = await loader.build(
        userMessage: 'x',
        pendingProposal: const PendingProposal(summary: '空的', commands: []),
      );
      expect(text, isNot(contains('尚未应用')));
    });

    test('段里必须点明「用户这句是改口时，直接给合并后的新提议」', () async {
      final text = await loader.build(
        pendingProposal: const PendingProposal(
          summary: '我准备把午餐记为米饭 150g、鸡胸肉 150g',
          commands: [
            (
              action: 'meal.create',
              args: {
                'slot': 'lunch',
                'items': [
                  {'food': '米饭', 'grams': 150},
                ],
              },
            ),
          ],
        ),
      );
      expect(
        text,
        anyOf(contains('直接给'), contains('合并')),
        reason:
            '只列出「待应用」不够——实测模型会答「等你应用后我再改」。'
            '必须明确：用户改口时应当**直接给一份新的完整提议**。',
      );
    });
  });
}

class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'ctx-id-${_n++}';
}
