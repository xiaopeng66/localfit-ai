import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// `RV4-R16`（`docs/56` §8 已裁决方案 A / D6）：输入框上方两枚 chip 换成
/// 「今天还剩多少」+「记一餐」，`AI 创作` 原位不动。
///
/// chip 1 是**本地计算**（不发模型、不入库），三条边界必须如实：
/// ① 没有目标 → 「还没设营养目标」+ 去设置；
/// ② 今日 0 条记录 → 「剩余 = 全天目标」；
/// ③ 某项已超 → 明说「已超 N」，不显示负数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late MealRepository meals;
  late FoodRepository foods;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 10, 24, 2));
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
    foods = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
  });
  tearDown(() => database.close());

  Future<void> pumpPage(
    WidgetTester tester, {
    MealRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AiConversationPage(
          service: _SilentService(),
          mealRepository: repository ?? meals,
          foodRepository: foods,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> tapRemaining(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai-chat-chip-remaining')));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> seedTargets() async {
    final nowUtc = DateTime.utc(2026, 10, 24, 2);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            profileId: 'profile-1',
            type: 'maintain',
            calorieMinKcal: 1800,
            calorieMaxKcal: 2000,
            effectiveFrom: nowUtc,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'target-1',
            goalId: 'goal-1',
            effectiveDate: _today(),
            calorieMinKcal: 1800,
            calorieMaxKcal: 2000,
            proteinMinGrams: 100,
            proteinMaxGrams: 140,
            carbsMinGrams: 200,
            carbsMaxGrams: 260,
            fatMinGrams: 50,
            fatMaxGrams: 70,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
  }

  testWidgets('chip 1：有目标 + 有记录 → 结果卡出现且不发消息', (tester) async {
    await seedTargets();
    final now = DateTime.now().toUtc();
    await _seedMeal(
      database,
      id: 'meal-1',
      now: now,
      kcal: 1240,
      protein: 62,
      carbs: 104,
      fat: 56,
    );

    await pumpPage(tester);
    await tapRemaining(tester);

    expect(
      find.byKey(const Key('ai-chat-remaining-card')),
      findsOneWidget,
      reason: '结果卡必须出现在对话流里',
    );
    expect(
      find.textContaining('560'),
      findsOneWidget,
      reason: '剩余下限 1800-1240',
    );
    expect(find.textContaining('1,240'), findsNothing); // 无千分位，明文
    expect(find.textContaining('1240'), findsOneWidget, reason: '已摄入');
    await unmount(tester);
  });

  testWidgets('chip 1 边界①：没有目标 → 明确说「还没设营养目标」', (tester) async {
    await pumpPage(tester);
    await tapRemaining(tester);
    expect(find.textContaining('还没设营养目标'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('chip 1 边界②：今日 0 条记录 → 剩余 = 全天目标', (tester) async {
    await seedTargets();
    await pumpPage(tester);
    await tapRemaining(tester);
    expect(find.textContaining('今天还没记任何东西'), findsOneWidget);
    expect(find.textContaining('1800'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('chip 1 边界③：已超 → 「已超 N」且不出现负号', (tester) async {
    await seedTargets();
    final now = DateTime.now().toUtc();
    await _seedMeal(
      database,
      id: 'meal-2',
      now: now,
      kcal: 2300,
      protein: 95,
      carbs: 210,
      fat: 60,
    );

    await pumpPage(tester);
    await tapRemaining(tester);

    expect(find.textContaining('已超'), findsOneWidget);
    expect(find.textContaining('-3'), findsNothing, reason: '超了就说「已超 N」，不显示负数');
    await unmount(tester);
  });

  testWidgets('chip 2：点「记一餐」开记录入口，不离开对话页', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('ai-chat-chip-log-meal')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      find.byKey(const Key('meal-entry-chooser')),
      findsOneWidget,
      reason: '复用 B3 的 launcher（不新增第三条记录路径）',
    );
    expect(
      find.byKey(const Key('ai-chat-title')),
      findsOneWidget,
      reason: '仍停在对话页（没跳页）',
    );
    await unmount(tester);
  });
}

/// 造一餐 + 一条条目（营养值在条目快照上，`meals` 表本身不存总量）。
Future<void> _seedMeal(
  AppDatabase database, {
  required String id,
  required DateTime now,
  required double kcal,
  required double protein,
  required double carbs,
  required double fat,
}) async {
  await database
      .into(database.meals)
      .insert(
        MealsCompanion.insert(
          id: id,
          localDate: _today(),
          slot: 'lunch',
          eatenAt: now,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.mealItems)
      .insert(
        MealItemsCompanion.insert(
          id: '$id-item',
          mealId: id,
          foodNameSnapshot: '测试食物',
          grams: 100,
          kcalSnapshot: kcal,
          proteinSnapshot: protein,
          carbsSnapshot: carbs,
          fatSnapshot: fat,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

String _today() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

class _SilentService implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    yield '';
  }
}

final class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'id-${_v++}';
}
