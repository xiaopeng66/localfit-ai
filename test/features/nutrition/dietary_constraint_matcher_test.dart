import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/nutrition/application/dietary_constraint_matcher.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

void main() {
  final stamp = DateTime.utc(2026, 11, 2, 8);

  DishRecord dish(String name) => DishRecord(
    id: name,
    name: name,
    mealSlot: 'lunch',
    kcal: 500,
    proteinG: 20,
    carbsG: 50,
    fatG: 10,
    source: 'manual',
    createdAt: stamp,
    updatedAt: stamp,
  );

  test('自定义忌口按菜名包含匹配', () {
    const c = PlanningConstraints(allergenAvoidances: ['芒果']);
    expect(dishConflictsWithConstraints(dish('芒果班戟'), c), isTrue);
    expect(dishConflictsWithConstraints(dish('鸡胸肉饭'), c), isFalse);
  });

  test('预设「蛋类」命中鸡蛋，不只看字面「蛋类」', () {
    const c = PlanningConstraints(allergenAvoidances: ['蛋类']);
    expect(dishConflictsWithConstraints(dish('番茄炒蛋'), c), isTrue);
    expect(dishConflictsWithConstraints(dish('鸡蛋灌饼'), c), isTrue);
    expect(dishConflictsWithConstraints(dish('牛奶燕麦'), c), isFalse);
  });

  test('素食排除肉/鱼，但保留蛋奶；纯素再排除蛋奶', () {
    const vegetarian = PlanningConstraints(
      dietaryLabels: [DietaryLabel.vegetarian],
    );
    expect(dishConflictsWithConstraints(dish('红烧牛肉'), vegetarian), isTrue);
    expect(dishConflictsWithConstraints(dish('清蒸鲈鱼'), vegetarian), isTrue);
    expect(dishConflictsWithConstraints(dish('番茄炒蛋'), vegetarian), isFalse);
    expect(dishConflictsWithConstraints(dish('牛奶燕麦'), vegetarian), isFalse);

    const vegan = PlanningConstraints(dietaryLabels: [DietaryLabel.vegan]);
    expect(dishConflictsWithConstraints(dish('番茄炒蛋'), vegan), isTrue);
    expect(dishConflictsWithConstraints(dish('牛奶燕麦'), vegan), isTrue);
  });

  test('无麸质排除面包面条，不误伤米饭', () {
    const c = PlanningConstraints(dietaryLabels: [DietaryLabel.glutenFree]);
    expect(dishConflictsWithConstraints(dish('全麦面包'), c), isTrue);
    expect(dishConflictsWithConstraints(dish('牛肉面'), c), isTrue);
    expect(dishConflictsWithConstraints(dish('米饭配青菜'), c), isFalse);
  });

  test('空约束不排除任何菜；提示词行只在有约束时生成', () {
    const empty = PlanningConstraints();
    expect(dishConflictsWithConstraints(dish('花生酱拌面'), empty), isFalse);
    expect(dietaryConstraintsPromptLine(empty), isNull);

    const c = PlanningConstraints(
      dietaryLabels: [DietaryLabel.vegan],
      allergenAvoidances: ['花生'],
    );
    final line = dietaryConstraintsPromptLine(c)!;
    expect(line, contains('纯素'));
    expect(line, contains('花生'));
    expect(line, contains('硬约束'));
  });
}
