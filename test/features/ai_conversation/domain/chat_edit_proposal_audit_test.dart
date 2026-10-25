import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

import '../../../support/food_fixture.dart';

/// **提案审查器**（2026-10-24 用户：要能发现「我要晚餐却给午餐」「漏食物」
/// 「重复食物」）。
///
/// 用户原话：「确保 ai 能正确合理的调用所有功能，而且不会出错，比如我要晚餐，
/// 给我午餐，漏掉食物或者重复食物等，**要有自己的去重和检测遗漏的机制**」。
///
/// 设计前提（重要）：**审查器只标注，不改数据**。
/// 模型给的东西可以错，但 App 不能替用户悄悄改——错的地方必须让用户在卡片上
/// 看见（「要注意：你说晚餐，提议的是午餐」），由用户决定应用与否。
///
/// 三类检查：
/// 1. **餐次不符**：用户这句话里明确说了餐次（「晚饭」「午餐」「早餐」），
///    而提议的 `slot` 与之不符 ⇒ 警告；
/// 2. **重复食物**：同一条 `meal.create` 的 `items` 里出现同名食物 ⇒ 警告
///    （执行器会去重，但用户得知道模型重复了）；
/// 3. **疑似遗漏**：用户这句话里点名的食物，在 `items` 里找不到 ⇒ 警告。
void main() {
  final registry = ChatEditCommandRegistry();
  final now = DateTime(2026, 10, 24, 12).toUtc();

  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    foods = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditProposalAudit audit({
    required String userText,
    required List<ChatEditCommand> commands,
  }) => ChatEditProposalAudit(
    userText: userText,
    commands: commands,
    foodRepository: foods,
    mealRepository: meals,
    clock: FixedAppClock(now),
  );

  group('餐次不符', () {
    test('用户说「晚饭」、提议 slot=dinner → 无警告', () async {
      final warnings = await audit(
        userText: '晚饭吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'dinner',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(warnings, isEmpty);
    });

    test('用户说「晚饭」、提议 slot=lunch → 警告餐次不符', () async {
      final warnings = await audit(
        userText: '晚饭吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(warnings, hasLength(1));
      expect(warnings.single.kind, ChatEditAuditKind.slotMismatch);
      expect(warnings.single.message, contains('晚餐'));
      expect(warnings.single.message, contains('午餐'));
    });

    test('用户说「晚餐」、提议 slot=dinner（中文归一）→ 无警告', () async {
      final warnings = await audit(
        userText: '晚餐吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': '晚餐',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(warnings, isEmpty);
    });

    test('用户没提餐次 → 不该报餐次不符（别瞎猜）', () async {
      final warnings = await audit(
        userText: '吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.slotMismatch),
        isEmpty,
      );
    });
  });

  group('重复食物', () {
    test('同一条 meal.create 里米饭出现两次 → 警告重复', () async {
      final warnings = await audit(
        userText: '午饭吃了米饭和鸡蛋',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
              {'food': '鸡蛋', 'grams': 50.0},
              {'food': '米饭', 'grams': 100.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.duplicateFood),
        hasLength(1),
      );
      expect(
        warnings
            .firstWhere((w) => w.kind == ChatEditAuditKind.duplicateFood)
            .message,
        contains('米饭'),
      );
    });

    test('两条 meal.create 都带米饭（同餐次）→ 也警告重复', () async {
      final warnings = await audit(
        userText: '午饭吃了米饭和鸡蛋',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 100.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.duplicateFood),
        hasLength(1),
      );
    });

    test('不同餐次各有一份米饭 → **不是**重复（用户可能真吃两顿）', () async {
      final warnings = await audit(
        userText: '午饭和晚饭都吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
          cmd('meal.create', {
            'slot': 'dinner',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.duplicateFood),
        isEmpty,
        reason: '跨餐次同名食物是正常的（真可能两顿都吃），不许当重复',
      );
    });
  });

  group('疑似遗漏', () {
    test('用户说「米饭和鸡蛋」，只提议米饭 → 警告漏了鸡蛋', () async {
      final warnings = await audit(
        userText: '午饭吃了米饭和鸡蛋',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      final missing = warnings.where(
        (w) => w.kind == ChatEditAuditKind.missingFood,
      );
      expect(missing, hasLength(1));
      expect(missing.single.message, contains('鸡蛋'));
    });

    test('用户说的食物都在 → 无遗漏警告', () async {
      final warnings = await audit(
        userText: '午饭吃了米饭和鸡蛋',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
              {'food': '鸡蛋', 'grams': 50.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.missingFood),
        isEmpty,
      );
    });

    test('用户说的食物库里没有（模型提议先建）→ 不算遗漏', () async {
      // 「麻辣烫」不在 fixture 里：模型提议 food.create + meal.create 是正确行为。
      final warnings = await audit(
        userText: '午饭吃了麻辣烫',
        commands: [
          cmd('food.create', {
            'name': '麻辣烫',
            'kcalPer100g': 90.0,
            'proteinPer100g': 6.0,
            'carbsPer100g': 8.0,
            'fatPer100g': 4.0,
          }),
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '麻辣烫', 'grams': 500.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.missingFood),
        isEmpty,
        reason: '同批提议里已经 food.create 了，不该报遗漏',
      );
    });

    test('用户没说具体食物（「随便吃点」）→ 不报遗漏', () async {
      final warnings = await audit(
        userText: '午饭随便吃了点',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.missingFood),
        isEmpty,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 2026-10-24：补上上一轮记下的两个局限
  // ══════════════════════════════════════════════════════════════════
  group('份量离谱（上轮局限 ①）', () {
    test('米饭 5000g → 警告份量偏大', () async {
      final warnings = await audit(
        userText: '午饭吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 5000.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.implausiblePortion),
        hasLength(1),
      );
      expect(
        warnings
            .firstWhere((w) => w.kind == ChatEditAuditKind.implausiblePortion)
            .message,
        contains('5000'),
      );
    });

    test('正常份量（150g）→ 不报', () async {
      final warnings = await audit(
        userText: '午饭吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.implausiblePortion),
        isEmpty,
      );
    });

    test('900g（大份但可能）→ 不报（门槛 1000g）', () async {
      final warnings = await audit(
        userText: '午饭吃了沙拉',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 900.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.implausiblePortion),
        isEmpty,
        reason: '门槛设 1000g 是为了只抓明显离谱的，不是为了管用户吃多少',
      );
    });
  });

  group('非常规餐次（上轮局限 ②）', () {
    test('「睡前那顿」→ 提示不确定是哪一餐（而不是瞎猜）', () async {
      final warnings = await audit(
        userText: '睡前那顿吃了点坚果',
        commands: [
          cmd('meal.create', {
            'slot': 'snack',
            'items': [
              {'food': '米饭', 'grams': 50.0},
            ],
          }),
        ],
      ).run();
      final vague = warnings.where(
        (w) => w.kind == ChatEditAuditKind.vagueSlot,
      );
      expect(vague, hasLength(1));
      expect(vague.single.message, contains('睡前那顿'));
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.slotMismatch),
        isEmpty,
        reason: '认不出是哪一餐时**不许**报餐次不符——那是瞎猜',
      );
    });

    test('标准说法「晚饭」→ 不报模糊', () async {
      final warnings = await audit(
        userText: '晚饭吃了米饭',
        commands: [
          cmd('meal.create', {
            'slot': 'dinner',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.vagueSlot),
        isEmpty,
      );
    });

    test('「饿了」这类不算餐次说法 → 不报模糊（别烦人）', () async {
      final warnings = await audit(
        userText: '我饿了',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      expect(
        warnings.where((w) => w.kind == ChatEditAuditKind.vagueSlot),
        isEmpty,
        reason: '「饿了」不是指一顿饭，提醒反而烦',
      );
    });
  });

  group('审查器不改数据（只标注）', () {
    test('跑完审查器，数据库里没有任何餐记录', () async {
      await audit(
        userText: '晚饭吃了米饭和鸡蛋',
        commands: [
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
      ).run();
      final rows = await database.select(database.meals).get();
      expect(rows, isEmpty, reason: '审查器必须只读——写库是 executor 的事');
    });
  });
}

class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'audit-${_n++}';
}
