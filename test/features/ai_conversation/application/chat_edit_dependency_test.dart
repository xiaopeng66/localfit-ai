import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_dependency.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// 需求 6d（docs/60 §1）：**点「记一餐」时把同卡的新建食材串起来做**。
///
/// 用户原话：「我点击鸡蛋水煮的应用的时候，应该弹窗提示是否应用创建食材
/// 鸡蛋水煮，我选择确认后又可以继续应用该早餐添加，而不是我点击应用后，
/// 因为下边的卡片没有点击应用，导致食物库没有鸡蛋水煮，从而添加失败。」
///
/// 七条硬要求（用户任务书 §6d）逐条落在本文件：
/// 1. 缺 + 同卡有创建 ⇒ 弹一次（`confirm` 被调到）；
/// 2. 确认 ⇒ 先建再记，**两条都变已应用**；
/// 3. 拒绝 ⇒ 记餐失败并如实说明，**一条都不写**；
/// 4. 缺但同卡**没有**创建 ⇒ 不弹（走既有修复按钮）；
/// 5. 已存在 ⇒ 不弹（不能每次记餐都问）；
/// 6. 一次多条缺失 ⇒ **一次性列全**（一次回调拿到全部）；
/// 7. 创建失败 ⇒ 不重试记餐，如实报错；重试前重新读一次食物库。
void main() {
  final registry = ChatEditCommandRegistry();

  /// 用信封文本造一张卡（与真实解码同路径：`parseChatEditTurn`）。
  ChatEditTurn turnOf(String editsJson) {
    final turn = parseChatEditTurn(
      '{"reply":"好了","edits":$editsJson}',
      registry,
    );
    expect(turn, isNotNull, reason: '测试信封本身要合法');
    return turn!;
  }

  /// 「鸡蛋水煮」这条新食材 + 一条用到它的早餐（与用户原话同一场景）。
  ChatEditTurn eggScenario({String food = '鸡蛋水煮'}) => turnOf(
    '[{"action":"meal.create","args":{"slot":"breakfast","items":'
    '[{"food":"$food","grams":100}]}},'
    '{"action":"food.create","args":{"name":"$food","kcalPer100g":155,'
    '"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":10.6}}]',
  );

  /// 记录执行器 + 迷你食物库（两者共用同一份库状态，见 [_TinyLibrary]）。
  late List<String> applied;
  late _TinyLibrary library;

  ChatEditCoordinator coordinator({
    required Set<String> existingFoods,
    FoodExistenceProbe? probeOverride,
    bool createFails = false,
  }) {
    applied = [];
    library = _TinyLibrary(existingFoods);
    return ChatEditCoordinator(
      contextBuilder: _NoopContextBuilder(),
      executor: _RecordingExecutor(
        applied: applied,
        library: library,
        createFails: createFails,
      ),
      foodExists: probeOverride ?? (name) async => library.has(name),
    );
  }

  Future<ChatEditTurn> apply(
    ChatEditCoordinator coordinator,
    ChatEditTurn turn, {
    required ChatEditDependencyConfirm? confirm,
    Set<int>? onlyIndexes,
  }) => coordinator.applyProposed(
    turn,
    onlyIndexes: onlyIndexes,
    confirmDependencies: confirm,
  );

  test('1+2：缺食材且同卡有创建 ⇒ 弹一次；确认后先建再记、两条都变已应用', () async {
    final turn = eggScenario();
    final c = coordinator(existingFoods: const {});
    List<ChatEditFoodDependency>? asked;
    final result = await apply(
      c,
      turn,
      confirm: (missing) async {
        asked = missing;
        return true;
      },
    );

    expect(asked, isNotNull, reason: '缺食材 + 同卡有创建时必须弹确认（要求 1）');
    expect(asked!.single.foodName, '鸡蛋水煮');
    expect(applied, [
      'food.create',
      'meal.create',
    ], reason: '必须先建食材再记餐（要求 2 的顺序）');
    final statuses = {
      for (final row in result.rows) row.command!.action: row.status,
    };
    expect(
      statuses['food.create'],
      ChatEditRowStatus.applied,
      reason: '创建那条也变已应用（用户原话「两条都变已应用」）',
    );
    expect(statuses['meal.create'], ChatEditRowStatus.applied);
  });

  test('2（只选记餐那组）：确认后创建行**即使不在选择范围**也要被应用', () async {
    final turn = eggScenario();
    final c = coordinator(existingFoods: const {});
    final mealRowIndex = turn.rows
        .firstWhere((row) => row.command!.action == 'meal.create')
        .index;
    final result = await apply(
      c,
      turn,
      onlyIndexes: {mealRowIndex},
      confirm: (_) async => true,
    );

    expect(applied, [
      'food.create',
      'meal.create',
    ], reason: '用户只点了「记一餐」那组——创建行是被依赖方，必须跟着走');
    expect(
      result.rows
          .firstWhere((row) => row.command!.action == 'food.create')
          .status,
      ChatEditRowStatus.applied,
    );
  });

  test('3：拒绝 ⇒ 记餐行失败并如实说明，且**一条创建都没写**', () async {
    final turn = eggScenario();
    final c = coordinator(existingFoods: const {});
    final result = await apply(c, turn, confirm: (_) async => false);

    expect(applied, isEmpty, reason: '拒绝之后不许留半条记录（要求 3）');
    final mealRow = result.rows.firstWhere(
      (row) => row.command!.action == 'meal.create',
    );
    expect(mealRow.status, ChatEditRowStatus.failed);
    expect(mealRow.resultMessage, contains('鸡蛋水煮'));
    final foodRow = result.rows.firstWhere(
      (row) => row.command!.action == 'food.create',
    );
    expect(
      foodRow.status,
      ChatEditRowStatus.proposed,
      reason: '创建那条仍是「待应用」——用户之后还能单独应用它',
    );
  });

  test('4：缺食材但同卡**没有**创建 ⇒ 不弹（走既有修复按钮）', () async {
    final turn = turnOf(
      '[{"action":"meal.create","args":{"slot":"breakfast","items":'
      '[{"food":"某个库里没有的菜","grams":100}]}}]',
    );
    final c = coordinator(existingFoods: const {});
    var asked = 0;
    final result = await apply(
      c,
      turn,
      confirm: (_) async {
        asked++;
        return true;
      },
    );

    expect(asked, 0, reason: '同卡没有创建 ⇒ 不该弹确认（要求 4）');
    expect(applied, ['meal.create'], reason: '照常应用，让执行器给失败 + 修复按钮');
    final mealRow = result.rows.single;
    expect(mealRow.status, ChatEditRowStatus.failed);
    expect(
      mealRow.repair?.kind.name,
      'createFood',
      reason: '失败仍要挂「新建食材」修复动作（既有能力不变）',
    );
  });

  test('5：食材已存在 ⇒ 什么都不弹（不能每次记餐都问）', () async {
    final turn = eggScenario();
    final c = coordinator(existingFoods: const {'鸡蛋水煮'});
    var asked = 0;
    final result = await apply(
      c,
      turn,
      confirm: (_) async {
        asked++;
        return true;
      },
    );

    expect(asked, 0, reason: '已存在就不许问（要求 5）');
    // 已在库里 ⇒ 不进确认分支，「全部应用」照旧逐条跑（行序 = 信封序）。
    // 创建那条被执行器按「库里已有同名」拒绝——既有的诚实失败，与本需求
    // 无关（这里只钉「没弹确认」+ 记餐那条真的成了）。
    expect(applied, ['meal.create', 'food.create']);
    expect(
      result.rows
          .firstWhere((row) => row.command!.action == 'meal.create')
          .status,
      ChatEditRowStatus.applied,
    );
  });

  test('6：一次缺两样 ⇒ **一次**回调拿到全部（不逐条连环弹）', () async {
    final turn = turnOf(
      '[{"action":"meal.create","args":{"slot":"breakfast","items":'
      '[{"food":"鸡蛋水煮","grams":100},{"food":"麻辣烫","grams":200}]}},'
      '{"action":"food.create","args":{"name":"鸡蛋水煮","kcalPer100g":155,'
      '"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":10.6}},'
      '{"action":"food.create","args":{"name":"麻辣烫","kcalPer100g":90,'
      '"proteinPer100g":6,"carbsPer100g":9,"fatPer100g":3}}]',
    );
    final c = coordinator(existingFoods: const {});
    var calls = 0;
    List<ChatEditFoodDependency>? asked;
    final result = await apply(
      c,
      turn,
      confirm: (missing) async {
        calls++;
        asked = missing;
        return true;
      },
    );

    expect(calls, 1, reason: '一次列全，不逐条弹（要求 6）');
    expect(asked!.map((d) => d.foodName).toSet(), {'鸡蛋水煮', '麻辣烫'});
    expect(
      applied.where((a) => a == 'food.create').length,
      2,
      reason: '两条创建都要先应用',
    );
    expect(
      result.rows
          .firstWhere((row) => row.command!.action == 'meal.create')
          .status,
      ChatEditRowStatus.applied,
    );
  });

  test('7：创建失败 ⇒ 不重试记餐，如实报错（不留半条）', () async {
    final turn = eggScenario();
    final c = coordinator(existingFoods: const {}, createFails: true);
    final result = await apply(c, turn, confirm: (_) async => true);

    expect(applied, ['food.create'], reason: '创建失败就不许再打记餐那条（要求 7）');
    final mealRow = result.rows.firstWhere(
      (row) => row.command!.action == 'meal.create',
    );
    expect(mealRow.status, ChatEditRowStatus.failed);
    expect(mealRow.resultMessage, contains('鸡蛋水煮'));
    expect(
      result.rows
          .firstWhere((row) => row.command!.action == 'food.create')
          .status,
      ChatEditRowStatus.failed,
      reason: '创建那条如实标失败',
    );
  });

  test('7：重试前**重新读一次**食物库（探针被二次调用）', () async {
    final turn = eggScenario();
    var probes = 0;
    final c = coordinator(
      existingFoods: const {},
      probeOverride: (name) async {
        probes++;
        return library.has(name);
      },
    );
    final result = await apply(c, turn, confirm: (_) async => true);
    expect(
      probes,
      greaterThanOrEqualTo(2),
      reason: '预检一次 + 重试前复核一次（防并发重复建，要求 7）',
    );
    expect(
      result.rows.first.status,
      ChatEditRowStatus.applied,
      reason: '复核通过后才允许真记餐',
    );
  });

  test('未接探针（foodExists 为 null）⇒ 不弹、行为与改动前一致', () async {
    final turn = eggScenario();
    applied = [];
    library = _TinyLibrary();
    final c = ChatEditCoordinator(
      contextBuilder: _NoopContextBuilder(),
      executor: _RecordingExecutor(applied: applied, library: library),
    );
    var asked = 0;
    await apply(
      c,
      turn,
      confirm: (_) async {
        asked++;
        return true;
      },
    );
    expect(asked, 0, reason: '未接探针 ⇒ 跳过预检，不弹');
    // 「全部应用」照旧逐条跑（行序 = 信封序）；记餐那条会因库里没有而失败——
    // 那正是改动前的行为（依赖串联是**新增**能力，不是替换旧路径）。
    expect(applied, ['meal.create', 'food.create']);
  });

  group('19 的判据（呈现层与执行层共用同一份）', () {
    test('服务于某一餐的 food.create：`isFoodCreateUsedByMeal` 为真', () {
      final turn = eggScenario();
      final foodRow = turn.rows.firstWhere(
        (row) => row.command!.action == 'food.create',
      );
      expect(isFoodCreateUsedByMeal(turn, foodRow), isTrue);
    });

    test('纯新建食材（用户只说「加一个叫麻辣烫的食材」）为假 ⇒ 保留独立板块', () {
      final turn = turnOf(
        '[{"action":"food.create","args":{"name":"麻辣烫","kcalPer100g":90}}]',
      );
      expect(isFoodCreateUsedByMeal(turn, turn.rows.single), isFalse);
    });

    test('记餐行里第几个食材是新建的（挂徽标的下标）', () {
      final turn = eggScenario();
      final mealRow = turn.rows.firstWhere(
        (row) => row.command!.action == 'meal.create',
      );
      final createRows = foodCreateRowIndexByName(turn);
      expect(isNewlyCreatedMealItem(mealRow, 0, createRows), isTrue);
      expect(isNewlyCreatedMealItem(mealRow, 1, createRows), isFalse);
    });
  });
}

final class _NoopContextBuilder implements ChatEditContextBuilder {
  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async => '（快照）';
}

/// 迷你食物库：**探针与执行器读同一份状态**。
///
/// 【为什么必须共用一个库】需求 6d 的整条链路就是「库里有没有」在驱动：
/// 探针答「有/没有」决定弹不弹，执行器写「有没有」决定记餐成不成。各写一份
/// 假状态的话，测试能全绿而真实链路仍然断（第一版就是这么把「先建再记」
/// 测成假的）。
final class _TinyLibrary {
  _TinyLibrary([Set<String>? initial]) : foods = {...?initial};

  final Set<String> foods;

  bool has(String name) => foods.contains(name);
}

/// 记录用执行器：按顺序记 action；行为按迷你食物库的真实状态给出。
final class _RecordingExecutor implements ChatEditExecutor {
  _RecordingExecutor({
    required this.applied,
    required this.library,
    this.createFails = false,
  });

  final List<String> applied;
  final _TinyLibrary library;
  final bool createFails;

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    applied.add(command.action);
    switch (command.action) {
      case 'food.create':
        if (createFails) {
          return ChatEditApplyResult.failure('创建食材失败（测试注入）。');
        }
        final name = (command.args['name'] as String? ?? '').trim();
        if (library.has(name)) {
          // 与真实执行器同口径：库里已有同名 ⇒ 拒绝建重复。
          return ChatEditApplyResult.failure('库里已经有「$name」了。');
        }
        library.foods.add(name);
        return ChatEditApplyResult.ok('已新建食材「$name」');
      case 'meal.create':
        for (final food in _foodsOf(command)) {
          if (!library.has(food)) {
            return ChatEditApplyResult.failure(
              '找不到食材「$food」。没有的食材要先用 food.create 创建。',
              repair: ChatEditRepair.createFood(name: food),
            );
          }
        }
        return ChatEditApplyResult.ok('已记一餐');
      default:
        return ChatEditApplyResult.ok('${command.action} 已应用');
    }
  }

  static List<String> _foodsOf(ChatEditCommand command) {
    final items = command.args['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) ((item['food'] as String?) ?? '').trim(),
    ];
  }
}
