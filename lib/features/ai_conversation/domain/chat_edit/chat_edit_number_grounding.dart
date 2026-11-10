/// 手动编译卡片的**数字接地闸门**（docs/66 §5.2.1，P0）。
///
/// 【为什么必须有】「内容优先」会把「没写克数」变成「编译器偷偷补 150g」，
/// 或者生成用户完全没看过、也没有可见依据的数值。闸门规则：
///
/// * 注册表中每个**数值型写入字段**都要有显式接地策略；新增数值字段若没有
///   策略，手动编译**默认拒绝挂卡**（fail-closed，见 `_coverage` 的兜底）。
/// * 除下述例外，每个数值都必须在「用户请求 + 目标回复」中有可见依据；
///   按数字边界匹配（`150` 可匹配 `150g/150 克/150.0`，不能匹配 `1500`）。
///   不要求对象邻近；只出现在无关旧消息里的数字不作为依据。
/// * 语义别名接地：`weekday=1` 可由明确的「周一」接地。
/// * `food.create` 的每 100g 营养估算字段（kcalPer100g /
///   proteinPer100g / carbsPer100g / fatPer100g）不要求出现在原文——应用前
///   的编辑卡会完整显示数值与单位；`servingGrams` 仍须接地。
/// * `canteen.dish.nutrition` 的默认元数据 `confidence=0.5` 与省略等价；
///   非默认 confidence、营养数值和每份克数估算（servingGrams）仍须接地。
/// * 任一数值缺接地 ⇒ 整张卡拒绝（不静默丢某一行）。
///
/// 本模块是**纯函数**：不碰状态、不碰库，控制器在挂卡前调用。
library;

import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// `food.create` 的每 100g 营养估算例外（应用前的编辑卡会完整显示数值
/// 与单位，docs/66 §5.2.1）。`servingGrams` **不在**此例外里。
const _foodCreateNutritionExemption = <String>{
  'kcalPer100g',
  'proteinPer100g',
  'carbsPer100g',
  'fatPer100g',
};

/// 星期语义别名（weekday 的接地来源；数字「1」本身不算依据）。
const _weekdayAliases = <int, List<String>>{
  1: ['周一', '星期一', '礼拜一', '周1', '星期1'],
  2: ['周二', '星期二', '礼拜二', '周2', '星期2'],
  3: ['周三', '星期三', '礼拜三', '周3', '星期3'],
  4: ['周四', '星期四', '礼拜四', '周4', '星期4'],
  5: ['周五', '星期五', '礼拜五', '周5', '星期5'],
  6: ['周六', '星期六', '礼拜六', '周6', '星期6', '周六日'],
  7: ['周日', '星期日', '礼拜日', '星期天', '礼拜天', '周天', '周7', '星期7'],
};

/// 顶层接地策略：action → 直接数值参数名（嵌套载荷在 `_validateNested`）。
const _policies = <String, Set<String>>{
  'weight.log': {'weightKg'},
  'water.add': {'amountMl'},
  'meal.create': {'items[].grams'},
  'meal.item.update': {'grams'},
  'targets.update': {'waterMl', 'steps'},
  'set.log': {'weightKg', 'reps', 'rpe'},
  'plan.entry.add': {'weekday', 'sets', 'reps', 'weightKg'},
  'workout.plan.create': {
    'days[].entries[].sets',
    'days[].entries[].reps',
    'days[].entries[].weightKg',
    'days[].weekday',
  },
  'profile.body.update': {'heightCm', 'birthYear'},
  'profile.goal.update': {'targetWeightKg'},
  'dish.upsert': {'kcal', 'protein', 'carbs', 'fat', 'servingGrams'},
  // docs/67 §6.2：新信封可以把"这个窗口一份多少克"写进卡片；它同样是数值
  // 写入，必须有接地策略（未配置就整卡拒绝，fail-closed）。
  'canteen.dish.create': {'servingGrams'},
  'canteen.dish.nutrition': {
    'kcalPer100g',
    'proteinPer100g',
    'carbsPer100g',
    'fatPer100g',
    'confidence',
    // 2026-11-11：分析命令新增的每份克数估算同样是数值写入——必须能在
    // 「用户请求 + 目标回复」里找到（识别回复按要求写「一份约Xg」），编造
    // 依然整卡拒绝。
    'servingGrams',
  },
  'food.create': {'servingGrams'},
  'food.update': {
    'kcalPer100g',
    'proteinPer100g',
    'carbsPer100g',
    'fatPer100g',
    'servingGrams',
  },
};

/// 校验一整张手动卡：全部数值字段都有接地依据时返回 null；否则返回拒绝
/// 原因（人话，直接显示在「空结果」状态行）。
String? validateManualCardGrounding(
  ChatEditTurn turn, {
  required String userText,
  required String assistantReply,
}) {
  final scope = '${userText.trim()}\n${assistantReply.trim()}';
  for (final row in turn.rows) {
    final command = row.command;
    // 解码失败的行本来就是 failed，不参与接地（也不会被应用）。
    if (command == null) continue;
    final problem = _validateCommand(command, scope, labels: row.itemLabels);
    if (problem != null) return problem;
  }
  return null;
}

String? _validateCommand(
  ChatEditCommand command,
  String scope, {
  Map<String, String>? labels,
}) {
  final action = command.action;
  final policy = _policies[action];
  final args = command.args;

  // 1) 嵌套载荷（记一餐的 items / 训练计划的 days）。
  if (action == 'meal.create') {
    final problem = _validateMealItems(args, scope, labels: labels);
    if (problem != null) return problem;
  }
  if (action == 'workout.plan.create') {
    final problem = _validatePlanDays(args, scope);
    if (problem != null) return problem;
  }

  // 2) 直接数值参数：策略内逐个接地；策略外 fail-closed。
  for (final spec in command.spec.args) {
    if (spec.type != ChatEditArgType.number &&
        spec.type != ChatEditArgType.integer) {
      continue;
    }
    final isExempt =
        action == 'food.create' &&
        _foodCreateNutritionExemption.contains(spec.name);
    if (isExempt) continue;
    final isNested = policy == null || !policy.contains(spec.name);
    if (isNested) {
      return '数值参数「${spec.name}」还没有接地策略，已按规则拒绝挂卡。';
    }
    if (!args.containsKey(spec.name)) continue; // 可选参数缺省=没写，无需接地
    final value = args[spec.name];
    if (value is! num) continue; // 已被 decoder 归一化，防御
    // 与执行器省略 confidence 时的默认值等价；只豁免这一个元数据字段。
    // 放在策略检查之后，新增数值字段仍然 fail-closed。
    if (action == 'canteen.dish.nutrition' &&
        spec.name == 'confidence' &&
        value == 0.5) {
      continue;
    }
    if (spec.name == 'weekday') {
      if (!_groundedByWeekdayAlias(value, scope)) {
        return '星期几没有明确的依据（例如「周一」），不能替用户猜。';
      }
      continue;
    }
    if (!_groundedByNumber(value, anchor: null, scope: scope)) {
      return '数值 ${_displayNumber(value)}（${spec.name}）在这条回复里找不到依据。';
    }
  }
  return null;
}

/// 记一餐：每条用料的 grams 都要有接地；锚点 = 食物名（引用形态剥掉方括号
/// 后仍找不到就退回全局范围——快照引用不出现在对话原文里）。
String? _validateMealItems(
  Map<String, Object> args,
  String scope, {
  Map<String, String>? labels,
}) {
  final items = args['items'];
  if (items is! List) return null;
  // 本命令里**在原文出现过**的食物名（归属判定的候选锚点）。
  final anchors = <String>{
    for (final item in items)
      if (item is Map && item['food'] is String)
        if (_displayAnchor(item['food'] as String) case final name
            when name.isNotEmpty && scope.contains(name))
          name,
  };
  for (final item in items) {
    if (item is! Map) continue;
    final food = item['food'];
    final grams = item['grams'];
    if (grams is! num) continue;
    final anchor = food is String ? _displayAnchor(food) : null;
    if (!_groundedByNumber(
      grams,
      anchor: anchor,
      scope: scope,
      siblingAnchors: anchors,
    )) {
      // 报错里说**食物名**，不说 `[food:uuid]`——用户没法拿 id 去核对。
      var shown = anchor ?? '$food';
      if (food is String) {
        final label = labels?[food];
        if (label != null && label.trim().isNotEmpty) shown = label.trim();
      }
      return '食材「$shown」的克数 ${_displayNumber(grams)} '
          '在这条回复里找不到依据。';
    }
  }
  return null;
}

/// 训练计划：每天 weekday 用语义别名；每条动作 sets/reps/weightKg 接地，
/// 锚点 = 动作名。
String? _validatePlanDays(Map<String, Object> args, String scope) {
  final days = args['days'];
  if (days is! List) return null;
  for (final day in days) {
    if (day is! Map) continue;
    final weekday = day['weekday'];
    if (weekday is! num || !_groundedByWeekdayAlias(weekday, scope)) {
      return '计划里的星期几没有明确的依据（例如「周一」），不能替用户猜。';
    }
    final entries = day['entries'];
    if (entries is! List) continue;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final exercise = entry['exercise'];
      final anchor = exercise is String ? _displayAnchor(exercise) : null;
      for (final field in const ['sets', 'reps', 'weightKg']) {
        final value = entry[field];
        if (value is! num) continue;
        if (!_groundedByNumber(value, anchor: anchor, scope: scope)) {
          return '动作「${anchor ?? exercise}」的 $field ${_displayNumber(value)} 在这条回复里找不到依据。';
        }
      }
    }
  }
  return null;
}

/// 锚点显示形态：`[food:xx]` 这类快照引用剥成 `food:xx`（原文里几乎不会
/// 出现完整方括号形态，但剥掉括号后有时能命中「food:xx」的字面）。
String _displayAnchor(String food) => food.trim();

/// 数字接地（**硬门**）：[value] 的边界匹配形态必须出现在 [scope]
/// （= 用户请求 + 目标回复）里。这是防「编译器偷偷补数」的唯一硬约束。
///
/// 【2026-11-07 真机两次反馈后的取舍】原先还要求「数字与食物名的间隔 ≤N 字」，
/// 结果把中文自然表述全判死：「白米饭（熟）这一小碗约 150g」里名字与数字隔了
/// 9 字、「豆腐+肉片+青菜的麻辣煲，…估算 400g」里编译器写的食物名与原文不
/// 逐字一致——用户点了「生成应用卡片」只能拿到「有数值没法核对」。用户两次
/// 明确：**点了就是要记入**。所以归属/邻近判定全部退场：
///
/// * 数字**在原文出现过** ⇒ 放行（它确实是抄来的，不是编的）；
/// * 对象是否配对 ⇒ 交给编辑卡核对（每行都写着食物名 + 克数，用户点应用前
///   看得见）与编译器 prompt（只按点击意图逐样转写，不新增对象）；
/// * 数字**不在原文** ⇒ 仍然拒绝（这条是 P0，绝不放松）。
///
/// [anchor] 与 [siblingAnchors] 保留在签名里给调用方表达意图，硬门不再依赖
/// 它们（引用型 `[food:id]` 本来就不会出现在原文）。
bool _groundedByNumber(
  num value, {
  required String? anchor,
  required String scope,
  Set<String> siblingAnchors = const {},
}) {
  final pattern = _numberPattern(value);
  if (pattern == null) return false;
  return pattern.hasMatch(scope);
}

/// weekday 的语义别名接地：数字本身不算依据（docs/66 §5.2.1）。
/// 匹配前压平空白（「周 1」「星期 一」也认）。
bool _groundedByWeekdayAlias(num value, String scope) {
  final aliases = _weekdayAliases[value.round()];
  if (aliases == null) return false;
  final flat = scope.replaceAll(RegExp(r'\s+'), '');
  return aliases.any(flat.contains);
}

/// 构造一个数字的**边界匹配**正则：`150` 命中 `150g` / `150 克` / `150.0`，
/// 不命中 `1500`、`1150`、`15.0`；`52.5` 命中 `52.5` / `52.50`。
RegExp? _numberPattern(num value) {
  if (value.isNaN || value.isInfinite) return null;
  final isInteger = value == value.truncateToDouble();
  final integerPart = value.truncate().toString();
  final body = isInteger
      ? '$integerPart(?:\\.0+)?'
      : '$integerPart\\.${_fractionDigits(value)}(?:0+)?';
  return RegExp('(?<![0-9.])$body(?![0-9])');
}

/// 小数部分的精确数字串（`52.5` → `5`；`0.125` → `125`）。
String _fractionDigits(num value) {
  final text = value.toString();
  final dot = text.indexOf('.');
  return dot == -1 ? '0' : text.substring(dot + 1);
}

/// 给用户看的数字（150.0 → 150）。
String _displayNumber(num value) => value == value.truncateToDouble()
    ? value.truncate().toString()
    : value.toString();
