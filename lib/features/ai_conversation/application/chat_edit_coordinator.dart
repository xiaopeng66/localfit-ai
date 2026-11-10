import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_content_discipline.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_dependency.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_prose_meal.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/meal_item_labels.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_resolver.dart';

/// 库里有没有这个食材（需求 6d 的依赖预检用）。
///
/// 由组合根接线（`main.dart` 用 `FoodRepository`）；null = 不做预检
/// （行为与改动前完全一致——测试与未接线的嵌入点不需要它）。
typedef FoodExistenceProbe = Future<bool> Function(String reference);

/// 依赖确认回调：把**一次性列全**的缺失清单交给用户，返回 true = 先建再记。
///
/// 【为什么是「一次列全」】一张卡里可能同时缺两三种新食材；逐条弹窗会变成
/// 连环弹（用户点完一个还有一个）。这个回调一次拿到整个列表。
typedef ChatEditDependencyConfirm = Future<bool> Function(
  List<ChatEditFoodDependency> missing,
);

/// 应用前**日期确认**回调（docs/66 §6.5）：把本次实际要执行的命令里出现的
/// 非今天 `localDate` 集合交给页面弹一次确认，返回 true = 照常执行。
///
/// 由控制器在执行前统一调用（整卡 / 分组 / 旧卡 suggestion / 选卡重放都
/// 经过同一守卫）；回调缺失或返回 false / 抛异常 = 不写库。
typedef ConfirmEditDates = Future<bool> Function(Set<String> dates);

/// 应用前「今天已有相同记录」提示探针（2026-11-07·重复可见化）。
///
/// 实现方查当天已有的事实（餐/饮水/体重），返回 rowIndex → 人话提示；
/// 组合根注入（需要仓储）。null = 不做提示（测试/未接线嵌入点行为不变）。
typedef DuplicateProbe = Future<Map<int, String>> Function(ChatEditTurn turn);

/// 把「快照构建、协议注入、信封解码、落库执行」粘在一起的对象；
/// ConversationController 只认它，不直接碰任何仓储（docs/23 §0）。
///
/// null 安全：未接线（`chatEdit == null`）时对话退回纯聊天，所有编辑路径
/// 都不激活——与对话服务未配置时的降级同一套哲学。
final class ChatEditCoordinator {
  ChatEditCoordinator({
    required this.contextBuilder,
    required this.executor,
    ChatEditCommandRegistry? registry,
    AppClock? clock,
    this.auditor,
    this.foodExists,
    this.catalogResolver,
    this.duplicateProbe,
    this.database,
  }) : registry = registry ?? ChatEditCommandRegistry();

  final ChatEditContextBuilder contextBuilder;

  /// 解析 `items[].food` 的展示名要用（只读）；null = 不解析，卡片回退到
  /// 原始引用（不影响任何写库行为）。
  final AppDatabase? database;
  final ChatEditExecutor executor;
  final ChatEditCommandRegistry registry;

  /// 提案审查器（2026-10-24）。null = 未接线，卡片不显示审查警告
  /// （行为与改动前完全一致）。
  final ChatEditAuditor? auditor;

  /// 食材存在性探针（需求 6d）。null = 跳过依赖预检（既有行为）。
  final FoodExistenceProbe? foodExists;

  /// 食物/菜品统一解析（Phase 1）。null = 未接线：同名双库的「选择卡」
  /// 不可用（失败文案仍会如实说明两库都有）。
  final CatalogResolver? catalogResolver;

  /// 应用前「今天已有相同记录」提示探针（2026-11-07·重复可见化）。
  /// null = 不提示（测试与未接线嵌入点行为不变）。
  final DuplicateProbe? duplicateProbe;

  /// 同名双库的候选清单（选择卡数据源）。只对 ambiguous 返回非空；
  /// 其它结局（missing/needsAnalysis/唯一命中）都返回 null——调用方据此
  /// 决定要不要弹选择卡。
  Future<CatalogCandidates?> resolveCatalogCandidates(String reference) async {
    final resolver = catalogResolver;
    if (resolver == null) return null;
    final resolution = await resolver.resolve(reference);
    return switch (resolution) {
      CatalogAmbiguous(
        :final reference,
        :final foods,
        :final dishes,
        :final supplies,
      ) =>
        CatalogCandidates(
          reference: reference,
          foods: foods,
          dishes: dishes,
          supplies: supplies,
        ),
      _ => null,
    };
  }

  /// 给 `meal.create` / `meal.update` 行补**展示名**（`[food:id]` → 食物名）。
  ///
  /// 只影响上屏：卡片标题、组摘要、数字接地报错都读它。查询失败或未接线
  /// （[database] 为 null）就原样返回——展示名缺了顶多回退到原始引用，
  /// 不能因此挡住一张卡。
  Future<ChatEditTurn> annotateItemLabels(ChatEditTurn turn) async {
    final db = database;
    if (db == null) return turn;
    var changed = false;
    final rows = <ChatEditTurnItem>[];
    for (final row in turn.rows) {
      final command = row.command;
      final items = command?.args['items'];
      if (command == null ||
          (command.action != 'meal.create' &&
              command.action != 'meal.update') ||
          items is! List) {
        rows.add(row);
        continue;
      }
      Map<String, String> labels;
      try {
        labels = await MealItemLabels.resolve(db, items);
      } on Object {
        rows.add(row);
        continue;
      }
      if (labels.isEmpty) {
        rows.add(row);
        continue;
      }
      changed = true;
      rows.add(row.copyWith(itemLabels: labels));
    }
    if (!changed) return turn;
    return ChatEditTurn(
      reply: turn.reply,
      rows: rows,
      suggestions: turn.suggestions,
      warnings: turn.warnings,
    );
  }

  /// 每次发送前调用：协议段 + 快照段。[userMessage] 是本次要发送的用户
  /// 消息（可空 = 既有调用点行为不变），快照构建器用它做消息相关的预检索
  /// （docs/40 §2.4 食物库 top3）。构建失败返回 null（本次不带快照，
  /// 对话照常），绝不让快照问题挡住一次对话（docs/23 §3）。
  ///
  /// [pendingProposal] 非空时把「上一张还没点应用的卡」告诉模型——否则
  /// 用户对着那张卡说「米饭改成 100 克」时，模型只看得见数据库（还没有那条
  /// 记录），会回答「等你先应用后我再改」，把两轮才能做完的事拖成四轮。
  ///
  /// 【docs/66】旧路径（`manualCardGeneration=false`）继续用本方法；新模式
  /// 用 [buildChatContext]（聊天）/ [buildEditContext]（手动编译）拆分后的
  /// 两份上下文。
  Future<String?> buildSystemContext({
    String? userMessage,
    PendingProposal? pendingProposal,
  }) async {
    try {
      final snapshot = await contextBuilder.build(
        userMessage: userMessage,
        pendingProposal: pendingProposal,
      );
      return '${registry.renderProtocol()}\n\n$snapshot';
    } on Object {
      return null;
    }
  }

  /// 【docs/66 §5.1】普通聊天的系统上下文：**内容纪律 + 能力边界 + 数据
  /// 快照**，不含 chat-edit 命令清单/JSON 协议——正常对话不再给模型「必须
  /// 输出信封」的压力，token 也省下协议那 6k 字。
  ///
  /// 失败语义（与旧 `buildSystemContext` 的关键差别）：**始终返回**内容
  /// 纪律；快照整体抛错时只省略快照段，不返回 null——「快照抖动」不能让
  /// 对话变成裸奔。
  ///
  /// [pendingProposal] 必须继续接（2026-10-24 修过的回归）：用户对着上一张
  /// 待应用卡说「米饭改成 100 克」时，内容 AI 不能再回「等你先应用再说」。
  Future<String> buildChatContext({
    String? userMessage,
    PendingProposal? pendingProposal,
  }) async {
    final snapshot = await _snapshotQuietly(
      userMessage: userMessage,
      pendingProposal: pendingProposal,
    );
    final buffer = StringBuffer()..write(chatContentDiscipline);
    if (snapshot != null) {
      buffer
        ..writeln()
        ..write(snapshot);
    }
    return buffer.toString();
  }

  /// 【docs/66 §5.1】手动编译的系统上下文：**完整 chat-edit 协议 + 数据
  /// 快照**（协议用编译模式变体）。同样始终返回协议；快照失败只省略快照段。
  ///
  /// [foodQuery] 只驱动食物库预览（docs/66 §5.2）：传「用户请求 + 目标回复
  /// （截断）」，菜品推荐门控与记忆检索仍按真实 [userMessage]。
  Future<String> buildEditContext({
    String? userMessage,
    String? foodQuery,
    PendingProposal? pendingProposal,
  }) async {
    final snapshot = await _snapshotQuietly(
      userMessage: userMessage,
      foodQuery: foodQuery,
      pendingProposal: pendingProposal,
    );
    final buffer = StringBuffer()
      ..write(registry.renderProtocol(compileMode: true));
    if (snapshot != null) {
      buffer
        ..writeln()
        ..write(snapshot);
    }
    return buffer.toString();
  }

  /// 快照构建（吞异常返回 null，docs/23 §3 的段级失败同一哲学）。
  Future<String?> _snapshotQuietly({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async {
    try {
      return await contextBuilder.build(
        userMessage: userMessage,
        pendingProposal: pendingProposal,
        foodQuery: foodQuery,
      );
    } on Object {
      return null;
    }
  }

  /// 给每条命令挂上「今天已有相同记录」的提示（只提示，不阻断、不改命令）。
  ///
  /// 失败静默返回原 turn：提示是旁注，绝不因为它让卡片出不来。
  Future<ChatEditTurn> annotateDuplicates(ChatEditTurn turn) async {
    final probe = duplicateProbe;
    if (probe == null || turn.rows.isEmpty) return turn;
    try {
      final hints = await probe(turn);
      if (hints.isEmpty) return turn;
      return ChatEditTurn(
        reply: turn.reply,
        rows: [
          for (final row in turn.rows)
            row.duplicateHint == null && hints[row.index] != null
                ? row.copyWith(duplicateHint: hints[row.index])
                : row,
        ],
        suggestions: turn.suggestions,
        warnings: turn.warnings,
      );
    } on Object {
      return turn;
    }
  }

  /// 解析助手输出；非信封返回 null（调用方按纯文本渲染）。
  ChatEditTurn? decode(String rawOutput) =>
      parseChatEditTurn(rawOutput, registry);

  /// 信封解析失败后的**散文抢救**：只认「餐次 + 食物克数清单 + 应用口吻」
  /// 的记餐提案（见 `parseProseMealProposal`）。其余散文仍按纯文本渲染。
  ChatEditTurn? decodeProseMealFallback(String rawOutput) =>
      parseProseMealProposal(rawOutput, registry);

  /// 应用**一条**推荐按钮的命令（2026-10-16 的 `suggestions` 通道）：
  /// 与编辑卡走同一个执行器、同一套失败翻译——点按钮本身就是用户的确认。
  Future<ChatEditApplyResult> applyOne(ChatEditCommand command) =>
      executor.apply(command);

  /// 需求 6d 的**预检**：本卡里「记一餐要用、库里没有、而同卡有 `food.create`」
  /// 的食材清单（按名字去重，附上创建行与用到它的记餐行）。
  ///
  /// 三条边界：
  /// * 库里**已有**该食材 ⇒ 不进清单（「不能每次记餐都问」）；
  /// * 同卡**没有**对应创建 ⇒ 不进清单（那种情况走既有的行级「新建食材」
  ///   修复按钮，不该弹确认）；
  /// * 没接探针（`foodExists == null`）⇒ 恒空清单（跳过预检）。
  Future<List<ChatEditFoodDependency>> pendingDependencies(
    ChatEditTurn turn, {
    Set<int>? onlyIndexes,
  }) async {
    final probe = foodExists;
    if (probe == null) return const [];
    final structural = structuralDependenciesOf(turn, onlyIndexes: onlyIndexes);
    if (structural.isEmpty) return const [];
    final out = <ChatEditFoodDependency>[];
    for (final dependency in structural) {
      // 探针失败（读库异常）当「存在」处理：宁可不弹确认、让执行器按老路
      // 报「找不到食材」，也不因为一次读库抖动把用户挡在确认框前。
      var exists = true;
      try {
        exists = await probe(dependency.foodName);
      } on Object {
        exists = true;
      }
      if (!exists) out.add(dependency);
    }
    return out;
  }

  /// 逐条执行提议（按序；单条失败不连坐）。处理「可执行」的行：
  /// `command != null` 且状态为 proposed / applying（控制器先把要执行的
  /// 行标成 applying 以挡双击，这里两种都认）；解码失败的行已是 failed，
  /// 直接跳过。
  ///
  /// [onlyIndexes] 非空 = 只执行这些行（编辑卡按类分组的「应用本组」）；
  /// 未选中的行原样保留（proposed 仍是 proposed，之后还能单独应用）。
  ///
  /// [confirmDependencies] 非空时启用**需求 6d 的依赖串联**：
  /// 预检发现「缺食材 + 同卡有创建」⇒ 先问一次（一次列全）——
  /// * 用户确认 ⇒ **先应用那些 `food.create`**，再重试记餐（两条都变已应用）；
  /// * 用户拒绝 ⇒ 记餐行失败并如实说明缺什么，**一条都不写**（不许留半条）；
  /// * 创建失败 ⇒ 不重试记餐，如实报错；重试前重新读一次食物库
  ///   （防并发重复建）。
  Future<ChatEditTurn> applyProposed(
    ChatEditTurn turn, {
    Set<int>? onlyIndexes,
    ChatEditDependencyConfirm? confirmDependencies,
  }) async {
    var current = turn;
    final confirm = confirmDependencies;
    if (confirm != null && foodExists != null) {
      final missing = await pendingDependencies(
        current,
        onlyIndexes: onlyIndexes,
      );
      if (missing.isNotEmpty) {
        final approved = await confirm(missing);
        if (!approved) {
          return _failMealRows(
            current,
            missing,
            reason:
                '还没创建食材${_quoteAll(missing.map((d) => d.foodName))}。'
                '先在卡片上创建它，或换一个食物库里已有的食材。',
          );
        }
        // ① 先建：把这些创建行应用掉（它们可能不在本次选择范围内——那正是
        //    用户「只点了记一餐那组」的场景）。
        current = await _applyRows(
          current,
          onlyIndexes: {
            for (final dependency in missing) dependency.createRowIndex,
          },
        );
        final failedCreates = [
          for (final dependency in missing)
            if (_rowById(current, dependency.createRowIndex)?.status ==
                ChatEditRowStatus.failed)
              dependency,
        ];
        if (failedCreates.isNotEmpty) {
          return _failMealRows(
            current,
            failedCreates,
            reason:
                '先创建食材${_quoteAll(failedCreates.map((d) => d.foodName))}失败了，'
                '这一餐没有写入；请先单独应用那条创建，再回来记这一餐。',
          );
        }
        // ② 重试前**重新读一次**食物库（需求 6d 第 7 条：防并发重复建）。
        final stillMissing = await pendingDependencies(
          current,
          onlyIndexes: onlyIndexes,
        );
        if (stillMissing.isNotEmpty) {
          return _failMealRows(
            current,
            stillMissing,
            reason:
                '食材${_quoteAll(stillMissing.map((d) => d.foodName))}刚创建过，'
                '但食物库里读不到唯一一条；这一餐没有写入，请到食材库确认后再记。',
          );
        }
      }
    }
    return _applyRows(current, onlyIndexes: onlyIndexes);
  }

  /// 逐条应用 [onlyIndexes] 指定的行（null = **全部**待应用行），其余原样保留。
  ///
  /// 【易错点（真踩过）】「先建再记」那一步必须传**创建行的下标集合**：
  /// 传 null 会变成「全部应用」，于是记餐行在创建行之前先跑——
  /// 顺序反了正是需求 6d 要修的那件事（实测 `applied` 顺序
  /// `[meal.create, food.create]` 就是这么来的）。
  Future<ChatEditTurn> _applyRows(
    ChatEditTurn turn, {
    required Set<int>? onlyIndexes,
  }) async {
    final rows = <ChatEditTurnItem>[];
    for (final row in turn.rows) {
      final command = row.command;
      final selected = onlyIndexes == null || onlyIndexes.contains(row.index);
      final runnable =
          row.status == ChatEditRowStatus.proposed ||
          row.status == ChatEditRowStatus.applying;
      if (!runnable || command == null || !selected) {
        rows.add(row);
        continue;
      }
      final result = await executor.apply(command);
      rows.add(
        row.copyWith(
          status: result.ok
              ? ChatEditRowStatus.applied
              : ChatEditRowStatus.failed,
          resultMessage: result.message,
          // 按食物的结果说明（2026-11-07 用户）：记餐应用后每样食物行下
          // 各挂各的说明，不再在卡片末尾堆一句汇总。
          itemNotes: result.itemNotes,
          // 失败带可点修复动作（缺食材 → 「创建食材 X」）时如实挂到那一行。
          repair: result.repair,
        ),
      );
    }
    return ChatEditTurn(
      reply: turn.reply,
      rows: rows,
      // 推荐按钮不是「行」，与执行过程无关——重建轮次时必须原样带走
      // （丢在这里＝用户点完「全部应用」按钮就消失）。
      suggestions: turn.suggestions,
    );
  }

  /// 把依赖涉及的记餐行标成失败并写清原因（**不写任何数据**）。
  ChatEditTurn _failMealRows(
    ChatEditTurn turn,
    List<ChatEditFoodDependency> dependencies, {
    required String reason,
  }) {
    final targets = {
      for (final dependency in dependencies) ...dependency.mealRowIndexes,
    };
    return ChatEditTurn(
      reply: turn.reply,
      rows: [
        for (final row in turn.rows)
          if (targets.contains(row.index))
            row.copyWith(
              status: ChatEditRowStatus.failed,
              resultMessage: reason,
            )
          else
            row,
      ],
      suggestions: turn.suggestions,
    );
  }

  ChatEditTurnItem? _rowById(ChatEditTurn turn, int index) {
    for (final row in turn.rows) {
      if (row.index == index) return row;
    }
    return null;
  }

  static String _quoteAll(Iterable<String> names) =>
      names.map((name) => '「$name」').join('、');
}
