import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/lf_evidence_badge.dart'
    show LfEvidenceGrade;
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_evidence.dart'
    show evidenceGradeForSource;
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealSlot;

/// 三餐推荐引擎（docs/28 §4.3）：六条规则逐条钉住。
///
/// 引擎是纯函数（输入含「现在几点」「已记录的餐」），所以这里不需要数据库、
/// 也不需要假装时间。每条断言都对应方案里的一条规则，并各自是变异红证的目标：
/// 去掉规则 → 这条测试必须先红。
void main() {
  final stamp = DateTime.utc(2026, 10, 4, 8);

  DishRecord dish({
    required String id,
    String? name,
    String mealSlot = 'lunch',
    String? servingWindow = '11:00-14:00',
    double kcal = 500,
    String source = 'ai_estimate',
  }) => DishRecord(
    id: id,
    name: name ?? id,
    mealSlot: mealSlot,
    servingWindow: servingWindow,
    kcal: kcal,
    proteinG: 20,
    carbsG: 50,
    fatG: 10,
    source: source,
    createdAt: stamp,
    updatedAt: stamp,
  );

  MealRecommendation forSlot(DailyMealRecommendation result, MealSlot slot) =>
      result.meals.firstWhere((meal) => meal.slot == slot);

  group('规则 1 时段过滤（窗口是更强的事实）', () {
    test('窗口只覆盖早餐时，这道菜只属于早餐', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'ex-b', mealSlot: 'breakfast', servingWindow: '06:00-09:30'),
        ],
        nowMinute: 6 * 60,
      );
      expect(forSlot(result, MealSlot.breakfast).primary?.id, 'ex-b');
      expect(forSlot(result, MealSlot.lunch).primary, isNull);
      expect(forSlot(result, MealSlot.dinner).primary, isNull);
    });

    test('窗口横跨午晚时，两餐都能拿到候选（跨餐重复另用规则 3 拦）', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'd1', mealSlot: 'dinner', servingWindow: '11:00-20:00'),
          dish(id: 'd2', mealSlot: 'dinner', servingWindow: '11:00-20:00'),
        ],
        nowMinute: 10 * 60,
      );
      expect(forSlot(result, MealSlot.lunch).primary?.id, 'd1');
      expect(forSlot(result, MealSlot.dinner).primary?.id, 'd2');
    });

    test('没有供应时段的菜退回它自己的餐次标签', () {
      final result = buildDailyMealRecommendation(
        dishes: [dish(id: 'n1', mealSlot: 'breakfast', servingWindow: null)],
        nowMinute: 6 * 60,
      );
      expect(forSlot(result, MealSlot.breakfast).primary?.id, 'n1');
      expect(forSlot(result, MealSlot.lunch).primary, isNull);
    });

    test('供应时段格式不合法时不拿坏字符串猜，只认标签', () {
      final result = buildDailyMealRecommendation(
        dishes: [dish(id: 'bad', mealSlot: 'lunch', servingWindow: '十一点到两点')],
        nowMinute: 10 * 60,
      );
      expect(forSlot(result, MealSlot.lunch).primary?.id, 'bad');
    });

    test('窗口完全在时段带之外 → 给不出推荐，并说清是窗口不在这个时段营业', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'late', mealSlot: 'lunch', servingWindow: '21:00-23:00'),
        ],
        nowMinute: 10 * 60,
      );
      final lunch = forSlot(result, MealSlot.lunch);
      expect(lunch.state, MealRecommendationState.empty);
      expect(lunch.reason, contains('09:30–14:00'));
      expect(lunch.reason, contains('营业'));
      expect(lunch.action, MealEmptyAction.openCanteen);
    });
  });

  group('规则 2 营养预算（按剩余目标分配）', () {
    test('没有记录时按 早30% / 午40% / 晚30% 分全天目标', () {
      final result = buildDailyMealRecommendation(
        dishes: const [],
        dailyTargetKcal: 2000,
        nowMinute: 6 * 60,
      );
      expect(
        forSlot(result, MealSlot.breakfast).budgetKcal,
        closeTo(600, 0.01),
      );
      expect(forSlot(result, MealSlot.lunch).budgetKcal, closeTo(800, 0.01));
      expect(forSlot(result, MealSlot.dinner).budgetKcal, closeTo(600, 0.01));
    });

    test('已记录的餐不参与分配，剩余目标只分给还没吃的餐位', () {
      final result = buildDailyMealRecommendation(
        dishes: [dish(id: 'd1', servingWindow: '11:00-20:00')],
        recordedKcalBySlot: const {MealSlot.lunch: 800},
        dailyTargetKcal: 2000,
        nowMinute: 6 * 60,
      );
      final lunch = forSlot(result, MealSlot.lunch);
      expect(lunch.state, MealRecommendationState.planned);
      expect(lunch.kcal, 800);
      expect(lunch.budgetKcal, isNull);
      // 剩 1200 只分给早/晚（份额 0.3 + 0.3）⇒ 每餐 600。
      expect(
        forSlot(result, MealSlot.breakfast).budgetKcal,
        closeTo(600, 0.01),
      );
      expect(forSlot(result, MealSlot.dinner).budgetKcal, closeTo(600, 0.01));
    });

    test('目标已经吃满时预算为 0 而不是负数', () {
      final result = buildDailyMealRecommendation(
        dishes: const [],
        recordedKcalBySlot: const {MealSlot.breakfast: 2200},
        dailyTargetKcal: 1800,
        nowMinute: 6 * 60,
      );
      expect(forSlot(result, MealSlot.lunch).budgetKcal, 0);
      expect(forSlot(result, MealSlot.dinner).budgetKcal, 0);
    });

    test('没有当日目标时三餐都没有预算', () {
      final result = buildDailyMealRecommendation(
        dishes: const [],
        nowMinute: 6 * 60,
      );
      expect(result.meals.map((meal) => meal.budgetKcal), everyElement(isNull));
    });
  });

  group('规则 3 不跨餐重复（D8）', () {
    test('候选用光时该餐给空态，不拿别餐已推过的菜填位', () {
      final result = buildDailyMealRecommendation(
        dishes: [dish(id: 'only', servingWindow: '11:00-20:00')],
        nowMinute: 10 * 60,
      );
      expect(forSlot(result, MealSlot.lunch).primary?.id, 'only');
      final dinner = forSlot(result, MealSlot.dinner);
      expect(dinner.primary, isNull, reason: '同一道菜不能跨餐重复出现');
      expect(dinner.state, MealRecommendationState.empty);
      expect(dinner.reason, contains('不跨餐重复'));
    });

    test('被前面餐次主推过的菜不会再当后面餐次的主推', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          for (final id in ['a', 'b', 'c'])
            dish(id: id, servingWindow: '11:00-20:00'),
        ],
        nowMinute: 10 * 60,
      );
      final lunch = forSlot(result, MealSlot.lunch);
      final dinner = forSlot(result, MealSlot.dinner);
      expect(lunch.primary?.id, 'a');
      expect(lunch.alternatives.map((dish) => dish.id), ['b', 'c']);
      // 备选**不算**已推过：晚餐可以接着用 b（它只是午餐的一个备选）。
      expect(dinner.primary?.id, 'b');
      // 但午餐的主推 a 不会再出现。
      expect(dinner.alternatives.map((dish) => dish.id), isNot(contains('a')));
    });

    test('候选够多时两餐各有主推，且两条主推不是同一道菜', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          for (var i = 0; i < 14; i++)
            dish(id: 'd$i'.padLeft(4, '0'), servingWindow: '11:00-20:00'),
        ],
        nowMinute: 10 * 60,
      );
      final lunch = forSlot(result, MealSlot.lunch);
      final dinner = forSlot(result, MealSlot.dinner);
      expect(lunch.alternatives, hasLength(mealAlternativeLimit));
      expect(dinner.primary, isNotNull);
      expect(dinner.primary!.id, isNot(lunch.primary!.id));
    });
  });

  group('规则 4 证据等级优先、营养不全不当候选', () {
    test('同样离预算近时先给已确认的那条', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'estimated', kcal: 500, source: 'ai_estimate'),
          dish(id: 'confirmed', kcal: 500, source: 'manual'),
        ],
        dailyTargetKcal: 2000,
        nowMinute: 10 * 60,
      );
      expect(forSlot(result, MealSlot.lunch).primary?.id, 'confirmed');
      expect(
        forSlot(result, MealSlot.lunch).alternatives.map((dish) => dish.id),
        ['estimated'],
      );
    });

    test('热量为 0（分析没给出结果）的条目不进候选', () {
      final result = buildDailyMealRecommendation(
        dishes: [dish(id: 'zero', kcal: 0)],
        nowMinute: 10 * 60,
      );
      final lunch = forSlot(result, MealSlot.lunch);
      expect(lunch.state, MealRecommendationState.empty);
      expect(lunch.reason, '这一餐还没有已分析的菜品');
    });

    test('菜品库没有「待补全」档：营养不全在这条链路上就等于热量为 0', () {
      // `evidenceGradeForSource` 只产出 confirmed / estimated，所以引擎里
      // 「营养不全不当候选」落到「热量为 0 不当候选」这一条上（上面那例）。
      // 这里把映射本身钉住：某天有人让 `incomplete` 变得可达时，这条会红，
      // 提醒去补「待补全不进候选」的实现与测试。
      expect(evidenceGradeForSource('incomplete'), LfEvidenceGrade.estimated);
      expect(evidenceGradeForSource('ai_estimate'), LfEvidenceGrade.estimated);
      expect(evidenceGradeForSource('manual'), LfEvidenceGrade.confirmed);
    });
  });

  group('规则 5 稳定排序（同输入必然同输出）', () {
    test('两次调用结果逐字段相同', () {
      final dishes = [
        dish(id: 'b', kcal: 400),
        dish(id: 'a', kcal: 400),
        dish(id: 'c', kcal: 900),
      ];
      DailyMealRecommendation run() => buildDailyMealRecommendation(
        dishes: dishes,
        dailyTargetKcal: 2000,
        nowMinute: 10 * 60,
      );
      final first = run();
      final second = run();
      for (var i = 0; i < first.meals.length; i++) {
        expect(second.meals[i].primary?.id, first.meals[i].primary?.id);
        expect(
          second.meals[i].alternatives.map((dish) => dish.id),
          first.meals[i].alternatives.map((dish) => dish.id),
        );
      }
    });

    test('平票按 id 升序，与输入顺序无关', () {
      final ascending = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'a', kcal: 500),
          dish(id: 'b', kcal: 500),
        ],
        dailyTargetKcal: 2000,
        nowMinute: 10 * 60,
      );
      final reversed = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'b', kcal: 500),
          dish(id: 'a', kcal: 500),
        ],
        dailyTargetKcal: 2000,
        nowMinute: 10 * 60,
      );
      expect(forSlot(ascending, MealSlot.lunch).primary?.id, 'a');
      expect(forSlot(reversed, MealSlot.lunch).primary?.id, 'a');
    });

    test('有预算时先给离预算最近的', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'far', kcal: 400),
          dish(id: 'near', kcal: 780),
        ],
        dailyTargetKcal: 2000, // 午餐预算 800 kcal
        nowMinute: 10 * 60,
      );
      expect(forSlot(result, MealSlot.lunch).primary?.id, 'near');
    });
  });

  group('规则 6 不猜：空态的成因与行动', () {
    test('一条候选都没有时说「还没有已分析的菜品」', () {
      final result = buildDailyMealRecommendation(
        dishes: const [],
        nowMinute: 10 * 60,
      );
      final lunch = forSlot(result, MealSlot.lunch);
      expect(lunch.state, MealRecommendationState.empty);
      expect(lunch.reason, '这一餐还没有已分析的菜品');
      expect(lunch.action, MealEmptyAction.openCanteen);
    });

    test('时段已经过了的餐位给空态，且**不给行动**（没有可执行的入口）', () {
      final result = buildDailyMealRecommendation(
        dishes: const [],
        nowMinute: 15 * 60,
      );
      final breakfast = forSlot(result, MealSlot.breakfast);
      expect(breakfast.state, MealRecommendationState.empty);
      expect(breakfast.reason, contains('早餐'));
      expect(breakfast.reason, contains('已经过了'));
      // 补救方式是去记录这一餐吃过什么，而记录入口不在这张页面上：
      // 画一个跳不过去的按钮就是撒谎（见 MealEmptyAction.none）。
      expect(breakfast.action, MealEmptyAction.none);
    });
  });

  group('汇总（hero 的「已安排 N 餐 · 预计 X kcal」）', () {
    test('已记录 + 有主推都算已安排，热量两者相加', () {
      final result = buildDailyMealRecommendation(
        dishes: [
          dish(id: 'd1', servingWindow: '11:00-14:00', kcal: 700),
          dish(id: 'd2', servingWindow: '14:00-20:00', kcal: 600),
        ],
        recordedKcalBySlot: const {MealSlot.breakfast: 400},
        dailyTargetKcal: 2000,
        nowMinute: 6 * 60,
      );
      expect(result.plannedMeals, 3);
      expect(result.plannedKcal, closeTo(400 + 700 + 600, 0.01));
    });

    test('一餐都安排不出来时为 0（页面据此写「—」而不是编一个数）', () {
      final result = buildDailyMealRecommendation(
        dishes: const [],
        nowMinute: 21 * 60,
      );
      expect(result.plannedMeals, 0);
      expect(result.plannedKcal, 0);
    });
  });
}
