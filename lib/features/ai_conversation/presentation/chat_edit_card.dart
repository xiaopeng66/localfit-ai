import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_reply_display.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/sections/plan_draft_card.dart';

/// AI 对话的「编辑卡」（docs/21 §5.7 第七种消息形态，docs/23 §5）。
///
/// 展示模型提议的逐条修改 + 应用结果；**按钮只是触发器**，真正的写库在
/// controller → executor，这条卡自身绝不碰数据。
///
/// **2026-10-16 用户裁决**（「功能卡片太丑，要做成小卡片，而不是堆在下边」）：
/// 原来是**裸 `Column`**（行与按钮直接堆在对话流里，没有卡壳），现改为
/// `DesignCard` 卡壳：卡头一行「待你确认的修改 / 这次修改的结果」+ 汇总
/// 徽标，行级状态也由裸文字改成 `LfBadge`。Key 与行为都不变。
class ChatEditCard extends StatelessWidget {
  const ChatEditCard({
    super.key,
    required this.index,
    required this.message,
    required this.onApply,
    required this.onApplyRows,
    required this.onDismiss,
    required this.onApplySuggestion,
    required this.onRepair,
  });

  /// 消息在列表里的下标（Key 命名沿用本页 `btn-*-<index>` 惯例）。
  final int index;
  final ConversationMessage message;
  final VoidCallback onApply;

  /// 按类分组的「应用本组」（2026-10-23 用户：卡片按类分组、可单独应用）。
  /// 参数是这一组里**待应用行**的信封下标。
  final ValueChanged<Set<int>> onApplyRows;
  final VoidCallback onDismiss;

  /// 点了某条「推荐按钮」（2026-10-16）：下标对位，控制器执行那条命令。
  final ValueChanged<int> onApplySuggestion;

  /// 点了行级「新建 X」修复按钮：把整条 [ChatEditRepair] 交给页面
  /// （页面按 kind 开对应弹层并预填名称）。表单里的其余字段仍由用户填，
  /// App 不替用户编数据。
  final ValueChanged<ChatEditRepair> onRepair;

  /// 计划草案行渲染成共享计划卡的动作名（docs/23 §2 注册表里的那一条）。
  static const String workoutPlanCreateAction = 'workout.plan.create';

  ChatEditTurn get _turn => message.editTurn!;

  bool get _busy => _turn.isApplying;

  bool get _showActions => _turn.hasProposed && !_busy;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      key: Key('chat-edit-card-$index'),
      padding: const EdgeInsets.all(LfDimens.spaceMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHead(index: index, turn: _turn, badge: _headlineBadge),
          const SizedBox(height: LfDimens.spaceTiny),
          // 2026-10-24 用户选定**方案 B（清单式）**：条目进浅灰分块（`MutedBlock`），
          // 靠底色把「一组」框起来。
          //
          // 原来行是直接铺在白卡上的：卡头 / 分组头 / 行 / 卡底按钮四个层级
          // **全是同一档灰字**，行标题 13px 与摘要 11px 只差 2px —— 眼睛扫
          // 过去找不到「这次到底要改什么」。分块是 B 的核心。
          for (final group in _groups) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            _GroupHeader(
              group: group,
              cardIndex: index,
              busy: _busy,
              onApplyRows: onApplyRows,
            ),
            const SizedBox(height: LfDimens.spaceXSmall),
            MutedBlock(
              key: Key('chat-edit-block-$index-${group.kind.name}'),
              padding: const EdgeInsets.symmetric(
                horizontal: LfDimens.spaceMedium,
                vertical: LfDimens.spaceSmall,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 设计稿 B 的行是**一个食物**（米饭 150g / 鸡胸肉 150g /
                  // 牛奶 200ml 三行），不是一条命令。所以这里把一条命令
                  // **展开成它的子条目**；非记餐命令仍是一行。
                  //
                  // 用户裁决：按钮只在组级——执行器按命令粒度，行内给
                  // 「应用」会让三行都实现同一个动作，误导用户。
                  for (var i = 0; i < group.items.length; i++)
                    for (
                      var j = 0;
                      j < _subItemsOf(group.items[i]).length;
                      j++
                    ) ...[
                      if (i > 0 || j > 0)
                        // 设计稿 `divide-y`：极淡分隔线。
                        Divider(
                          height: LfDimens.spaceMedium,
                          thickness: 1,
                          color: c.border.withValues(alpha: 0.5),
                        ),
                      // 每个子条目都要有自己的 Key（设计稿：一食物一行）。
                      // 旧的行级 Key 另用 `KeyedSubtree` 挂在**主**子条目上，
                      // 既有测试与页面定位不受影响。
                      KeyedSubtree(
                        key: j == 0
                            ? Key(
                                'chat-edit-row-$index-'
                                '${group.items[i].index}',
                              )
                            : null,
                        child: _EditRow(
                          key: Key(
                            'chat-edit-subitem-$index-${group.items[i].index}-$j',
                          ),
                          item: group.items[i],
                          cardIndex: index,
                          subIndex: j,
                          subItem: _subItemsOf(group.items[i])[j],
                          ordinal: _globalOrdinal(group, i, j),
                          repairKey: Key(
                            'chat-edit-repair-$index-${group.items[i].index}',
                          ),
                          onRepair: onRepair,
                          busy: _busy,
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
          // 提案审查警告（2026-10-24 用户：「要有自己的去重和检测遗漏的机制」）。
          // 放在**行之后、按钮之前**：用户读完「要改什么」正好看到「有什么问题」，
          // 然后才决定点不点应用。**只提示，不阻断**——应用按钮照常可点。
          if (_turn.warnings.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            for (var i = 0; i < _turn.warnings.length; i++)
              Padding(
                key: Key('chat-edit-warning-$index-$i'),
                padding: EdgeInsets.only(
                  top: i == 0 ? 0 : LfDimens.spaceXSmall,
                ),
                child: _AuditWarningRow(warning: _turn.warnings[i]),
              ),
          ],
          if (_turn.suggestions.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            // 推荐按钮（2026-10-16 用户要的「可点选按钮」）：点了就等于
            // 应用那条命令。`Wrap` 而不是横滑——一个都不藏起来，
            // 大字号下折行不溢出。
            Wrap(
              spacing: LfDimens.spaceSmall,
              runSpacing: LfDimens.spaceSmall,
              children: [
                for (var i = 0; i < _turn.suggestions.length; i++)
                  _SuggestionChip(
                    key: Key('chat-edit-suggest-$index-$i'),
                    suggestion: _turn.suggestions[i],
                    onTap: () => onApplySuggestion(i),
                  ),
              ],
            ),
          ],
          if (_finishedSuggestionNotes != null)
            Padding(
              padding: const EdgeInsets.only(top: LfDimens.spaceTiny),
              child: Text(
                _finishedSuggestionNotes!,
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ),
          const SizedBox(height: LfDimens.spaceSmall),
          if (_busy)
            Text(
              '正在应用修改…',
              style: LfText.micro.copyWith(color: c.mutedForeground),
            )
          else if (_showActions)
            // 设计稿 B 的卡底：主按钮 `flex: 1` **撑满剩余宽度**、副按钮「忽略」
            // 紧贴其后。用 `Row` + `Expanded` 还原（不是两个等宽按钮）。
            //
            // 窄屏 × 2.0 字号下的溢出由 `Expanded` 承担：主按钮吃掉剩余空间、
            // 「忽略」占自然宽，`FittedBox.scaleDown` 会在必要时缩文字（
            // `LfPrimaryButton.fitLabel`），不会撑破。
            Row(
              children: [
                Expanded(
                  child: LfPrimaryButton(
                    key: Key('chat-edit-apply-$index'),
                    label: '全部应用',
                    onPressed: onApply,
                    fitLabel: true,
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmallPlus),
                LfTextButton(
                  key: Key('chat-edit-dismiss-$index'),
                  label: '忽略',
                  onPressed: onDismiss,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 卡头徽标（与行级徽标同样的三态口径）。
  Widget get _headlineBadge {
    if (_busy) return const LfBadge.neutral('处理中');
    if (_turn.hasProposed) {
      // 结论行已经写了「N 条修改」，徽标再写一遍是重复噪音。
      // 待确认态改用「待确认」——它提供的是**状态**，不是数量。
      return const LfBadge.outlinedBrand('待确认');
    }
    if (_turn.rows.isEmpty) {
      return LfBadge.outlinedBrand('${_turn.suggestions.length} 个可选项');
    }
    return const LfBadge.mint('已完成');
  }

  /// 点过的推荐按钮的结果汇总（一个都没点过 → null，不占位）。
  String? get _finishedSuggestionNotes {
    final notes = [
      for (final suggestion in _turn.suggestions)
        if (suggestion.resultMessage != null)
          '${suggestion.label}：${suggestion.resultMessage}',
    ];
    return notes.isEmpty ? null : notes.join('；');
  }

  /// 按命令类别分组：记一餐 / 新建食材 / 其他修改。
  ///
  /// 组的顺序固定（`_EditGroupKind.values`），组内行保持信封原顺序——
  /// 同一份提议每次渲染的分组与顺序都一致，用户不会看到卡片「自己重排」。
  List<_EditGroup> get _groups {
    final groups = <_EditGroup>[];
    for (final kind in _EditGroupKind.values) {
      final items = [
        for (final row in _turn.rows)
          if (_kindOf(row) == kind) row,
      ];
      if (items.isNotEmpty) groups.add(_EditGroup(kind, items));
    }
    return groups;
  }

  static _EditGroupKind _kindOf(ChatEditTurnItem item) {
    final action = item.command?.action;
    if (action == null) return _EditGroupKind.other;
    if (action.startsWith('meal.')) return _EditGroupKind.meal;
    if (action == 'food.create') return _EditGroupKind.food;
    return _EditGroupKind.other;
  }

  /// 组内第 [itemIndex] 条命令、它的第 [subIndex] 个子条目的**全局序号**
  /// （组内从 1 连排）。设计稿序号是 1/2/3 一路排下来，不是每条命令都从 1 起。
  static int _globalOrdinal(_EditGroup group, int itemIndex, int subIndex) {
    var n = 0;
    for (var i = 0; i < itemIndex; i++) {
      n += _subItemsOf(group.items[i]).length;
    }
    return n + subIndex + 1;
  }
}

/// 编辑卡上的一个**子条目**（设计稿 B 的一行）。
///
/// 记餐类命令（`meal.create`）带 `items` 列表：设计稿要求"米饭 / 鸡胸肉 /
/// 牛奶"各占一行，所以这里把一条命令展开成 N 个子条目。其它命令没有子条目
/// 概念，整条命令就是**一个**子条目（`isPrimary = true`，承载结果与修复）。
final class _SubItem {
  const _SubItem({
    required this.title,
    this.subtitle = '',
    this.isPrimary = false,
    this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
  });

  /// 主标题：记餐是「米饭 · 150 g」；其它命令是命令标题（「记一笔饮水」）。
  final String title;

  /// 副标题：记餐是餐次（「午餐」）；**方案 B 的食材行不用它**（改由
  /// 热量块 + 三色点宏量表达）。
  final String subtitle;

  /// 是不是这条命令的"主"子条目（结果文案/修复按钮只挂在主条目上，
  /// 免得同一个结果在三个食物行上各显示一遍）。
  final bool isPrimary;

  // ── 方案 B（2026-10-25 用户选定）：食材行的营养四件套 ──────────────
  /// 每 100g 热量。非 null 表示这是**食材行**，渲染成方案 B
  /// （大热量右侧 + 三色点宏量）。
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;

  /// 是不是食材行（有营养数据才走方案 B 版式）。
  bool get isFoodRow => kcalPer100g != null;
}

/// 把一条命令展开成子条目列表（记餐 = 每个食物一条；其它 = 单条）。
List<_SubItem> _subItemsOf(ChatEditTurnItem item) {
  final command = item.command;
  if (command == null) {
    return [
      _SubItem(
        title: '无法识别的修改',
        subtitle: item.decodeError ?? '',
        isPrimary: true,
      ),
    ];
  }
  // 方案 B（用户选定）：`food.create` 渲染成**食材行**——名称 + 大热量 +
  // 三色点宏量。原来它走 `summarize()` 的压缩写法
  // 「新建食材「鸡蛋水煮」：155 kcal/100g（P13/C1.1/F10.6）」，
  // 用户原话「挤在一起很丑」。
  if (command.action == 'food.create') {
    final args = command.args;
    double? num_(String key) => (args[key] as num?)?.toDouble();
    return [
      _SubItem(
        // 标题就是**食材名**（不再带「新建食材」前缀——组头已经说了）。
        title: (args['name'] as String? ?? '').trim(),
        isPrimary: true,
        kcalPer100g: num_('kcalPer100g'),
        proteinPer100g: num_('proteinPer100g'),
        carbsPer100g: num_('carbsPer100g'),
        fatPer100g: num_('fatPer100g'),
      ),
    ];
  }
  if (command.action != 'meal.create') {
    return [
      _SubItem(
        title: command.spec.title,
        subtitle: _displaySummaryOf(command),
        isPrimary: true,
      ),
    ];
  }
  final raw = command.args['items'];
  if (raw is! List || raw.isEmpty) {
    return [
      _SubItem(
        title: command.spec.title,
        subtitle: _displaySummaryOf(command),
        isPrimary: true,
      ),
    ];
  }
  final slotLabel = _mealSlotLabelOf(command.args['slot']);
  return [
    for (var i = 0; i < raw.length; i++)
      if (raw[i] is Map)
        _SubItem(
          // 设计稿：「米饭 · 150 g」——食物名 + 中点 + 克数（带空格）。
          title:
              '${((raw[i] as Map)['food'] as String? ?? '').trim()} · '
              '${_formatGrams((raw[i] as Map)['grams'], foodName: (raw[i] as Map)['food'] as String? ?? '')}',
          subtitle: slotLabel,
          isPrimary: i == 0,
        ),
  ];
}

/// 方案 B 的三色点宏量（蛋白橙 / 碳水黄 / 脂肪紫）。
///
/// 与营养卡同一套语义色（`LfSemanticColors.protein/carbs/fat`）——不新造
/// 一套配色，用户在两处看到的是同一种橙/黄/紫。
///
/// **取整规则**：≥10g 取整（「31g」），<10g 保留一位小数（「3.6g」）——
/// 宏量在 1g 量级的精度对用户没意义，但 0.5g 的差别有意义（一份奶的脂肪）。
final class _MacroDots extends StatelessWidget {
  const _MacroDots({
    required this.cardIndex,
    required this.itemIndex,
    required this.subIndex,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final int cardIndex;
  final int itemIndex;
  final int subIndex;
  final double protein;
  final double carbs;
  final double fat;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final entries = [(c.protein, protein), (c.carbs, carbs), (c.fat, fat)];
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (var i = 0; i < entries.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                key: Key('chat-edit-food-dot-$cardIndex-$itemIndex-$i'),
                decoration: BoxDecoration(
                  color: entries[i].$1,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 6, height: 6),
              ),
              const SizedBox(width: 3),
              Text(
                _grams(entries[i].$2),
                key: Key('chat-edit-food-macro-$cardIndex-$itemIndex-$i'),
                style: LfText.label.copyWith(
                  color: c.mutedForeground,
                  height: 1.3,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 宏量克数：≥10 取整，<10 保留一位（见 [_MacroDots] 注释）。
String _grams(double value) {
  final text = value >= 10
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '${text}g';
}

/// 热量数字：整数不带小数点（「155」而不是「155.0」）。
String _kcalText(double? value) {
  if (value == null) return '—';
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// 上屏用的行摘要：先让注册表给出人话，**再剥掉内部 id**。
///
/// 【2026-10-25 缺陷修复】12 条命令的 `summarize()` 会把快照 id 直接拼进文案
/// （「删除饮水记录 water-3f2a」「[canteen-dish:mx-3] 每 100g…」）。那是给
/// 模型看的坐标，不是人话——用户实测抓到卡片上显示一堆 id。
///
/// 修法分两层：
/// * 菜品营养那条从**源头**去掉了 id（`chat_edit_registry.dart`）；
/// * 其余仍带 id 的命令（删除/修改类，id 是**用户唯一能指认它**的东西，
///   直接删掉会变成「删除餐 」这种半句话）在这里统一换成**短尾号**：
///   `water-3f2a9b` → `…3f2a9b`，既可辨认又不泄露内部格式。
String _displaySummaryOf(ChatEditCommand command) {
  final raw = command.summarize();
  // 先剥方括号引用（`[canteen-dish:xxx]` 整段消失）。
  final stripped = stripInternalRefs(raw);
  // 再把残留的裸 id（uuid / 前缀-id 形态）换成短尾号。
  return stripped
      .replaceAllMapped(_bareId, (match) {
        final value = match.group(0)!;
        final tail = value.length <= 6
            ? value
            : value.substring(value.length - 6);
        return '…$tail';
      })
      .replaceAll(RegExp(r'[ 	]{2,}'), ' ')
      .trim();
}

/// 裸 id 形态：带连字符的前缀-id（`water-3f2a`）、纯 uuid、或 8 位以上十六进制。
///
/// **保守**：只认这些形状，中文正文不会命中（不会把「米饭」这类词切掉）。
final RegExp _bareId = RegExp(
  r'[a-z]{2,12}-[0-9a-z]{4,}'
  r'|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
  r'|[0-9a-f]{12,}',
);

/// 克数显示：整数不带小数点（「150 g」而不是「150.0 g」）。
///
/// 液体用 `ml`：设计稿里牛奶是「200 ml」而不是「200 g」。判据是**食物名**
/// 里的液体词——这不是营养学精确判断，只是显示口径（千卡按克算，不影响
/// 任何计算）。
String _formatGrams(Object? raw, {String foodName = ''}) {
  final value = (raw as num?)?.toDouble();
  if (value == null) return '—';
  final text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  final unit = _isLiquid(foodName) ? 'ml' : 'g';
  return '$text $unit';
}

/// 这个食物名是不是液体（牛奶/水/豆浆/汁/茶/咖啡…）。
///
/// **只影响显示单位**：底层仍按克记（食物库口径一致）。
///
/// 【判据必须是**结尾**匹配，不能是包含】（2026-10-25 缺陷）：
/// 原实现用 `contains('水')`，于是「鸡蛋**水**煮」被判成液体，显示成
/// 「鸡蛋水煮 · 100 ml」——用户实测抓到的错。同类误判还有「水煮蛋」
/// 「油麦菜」「汤面」（含「汤」）。液体词只在**词尾**才成立。
bool _isLiquid(String foodName) {
  final name = foodName.trim();
  if (name.isEmpty) return false;
  const liquidSuffixes = [
    '奶', // 牛奶、豆浆奶
    '水', // 白开水、蜂蜜水
    '浆', // 豆浆、米浆
    '汁', // 橙汁
    '茶', // 绿茶
    '咖啡',
    '汤', // 紫菜汤
    '酒',
  ];
  return liquidSuffixes.any(name.endsWith);
}

/// 餐次 storedValue → 中文标签。
String _mealSlotLabelOf(Object? raw) {
  if (raw is! String) return '';
  return switch (raw) {
    'breakfast' => '早餐',
    'lunch' => '午餐',
    'dinner' => '晚餐',
    'snack' => '加餐',
    // 参数校验阶段已归一成 storedValue；走到这里说明是没见过的值，
    // 原样显示比编一个更诚实。
    _ => raw,
  };
}

/// 卡头（方案 B）：**结论行 + 明细行** + 状态徽标。
///
/// 原来卡头只有一句「待你确认的修改」——那句话对每张卡都一样，等于没说；
/// 用户必须逐行读摘要才知道这次要改什么。
///
/// B 的做法：结论行给出**能读懂的结论**（「午餐 · 3 条修改」），明细行列出
/// 这条要记的东西（「午餐：米饭 150g、鸡胸肉 150g、牛奶 200ml」）。两者都从
/// **已校验的命令参数**里取（`summarize()` / `items`），不查库、不编数字——
/// 卡只拿得到模型给的参数，热量要另查食物库才准，所以这里**刻意不显示热量**。
final class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.index,
    required this.turn,
    required this.badge,
  });

  final int index;
  final ChatEditTurn turn;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mintText = LfColors.mintText(Theme.of(context).brightness);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 设计稿 B 第一行：kicker 11px w700 + 品牌色 + 字距 .4。
              // 中文没有大小写，用「加粗 + 品牌色 + 字距」表达同一档小标签。
              Text(
                _kicker,
                style: LfText.label.copyWith(
                  color: mintText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  _headline,
                  key: Key('chat-edit-card-headline-$index'),
                  // 设计稿：15px w600。
                  // `LfText.title` 就是 15px——设计稿的标题档，用档位不写字面量。
                  style: LfText.title.copyWith(
                    color: c.cardForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _summary!,
                    key: Key('chat-edit-card-summary-$index'),
                    // 设计稿：meta 12px muted。
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: LfDimens.spaceSmall),
        badge,
      ],
    );
  }

  /// kicker 小标签（设计稿 B 的第一行）。
  String get _kicker => turn.hasProposed ? '待你确认' : '修改结果';

  /// 结论行：「午餐 · 3 条修改」 / 「记一笔饮水 · 1 条修改」。
  ///
  /// 记餐类命令才说餐次——喝水不该被说成「某一餐」。
  String get _headline {
    final count = turn.rows.length;
    if (!turn.hasProposed) return '这次修改的结果';
    final slot = _mealSlotLabel();
    if (slot != null) return '$slot · $count 条修改';
    return '$count 条修改';
  }

  /// 明细行：把这条要记/要改的东西列出来（只列参数里有的）。
  ///
  /// 多于 3 条时只列前 3 条并加「等 N 项」——两行内读得完。
  String? get _summary {
    final parts = <String>[];
    for (final kind in _EditGroupKind.values) {
      // 记餐类：设计稿的 meta 就是「米饭 150g、鸡胸肉 150g、牛奶 200ml」——
      // **直接列食物**，不是把 summarize() 整句拼起来（那会变成
      // 「午餐：米饭 150.0g + 鸡胸肉 150.0g」，多一个餐次前缀和加号）。
      final foods = <String>[
        if (kind == _EditGroupKind.meal)
          for (final row in turn.rows)
            if (row.command != null && _kindOf(row) == kind)
              ..._foodLabelsOf(row.command!),
      ];
      if (foods.isNotEmpty) {
        parts.add(
          foods.length <= 3
              ? foods.join('、')
              : '${foods.take(3).join('、')} 等 ${foods.length} 样',
        );
        continue;
      }
      // 食材类：设计稿 B 的 meta 是「鸡蛋水煮 155 kcal/100g」——
      // **不带 P/C/F 压缩写法**（那是行内三色点的活，重复一次只会更挤）。
      final foodsMeta = <String>[
        if (kind == _EditGroupKind.food)
          for (final row in turn.rows)
            if (row.command != null && _kindOf(row) == kind)
              _foodCreateLabelOf(row.command!),
      ];
      if (foodsMeta.isNotEmpty) {
        parts.add(foodsMeta.join('、'));
        continue;
      }
      final summaries = [
        for (final row in turn.rows)
          if (row.command != null &&
              _kindOf(row) == kind &&
              row.command!.summarize().trim().isNotEmpty)
            row.command!.summarize().trim(),
      ];
      if (summaries.isEmpty) continue;
      parts.add(
        summaries.length <= 2
            ? summaries.join('、')
            : '${summaries.take(2).join('、')} 等 ${summaries.length} 项',
      );
    }
    if (parts.isEmpty) return null;
    return parts.join('；');
  }

  /// `food.create` 的 meta 短标签（「鸡蛋水煮 155 kcal/100g」）：
  /// 只留名称与热量，**不重复行内已经用三色点表达的 P/C/F**。
  static String _foodCreateLabelOf(ChatEditCommand command) {
    final name = (command.args['name'] as String? ?? '').trim();
    final kcal = (command.args['kcalPer100g'] as num?)?.toDouble();
    if (kcal == null) return name;
    return '$name ${_kcalText(kcal)} kcal/100g';
  }

  /// 记餐命令的食物短标签（「米饭 150g」），meta 行用。
  static List<String> _foodLabelsOf(ChatEditCommand command) {
    final raw = command.args['items'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          '${((item['food'] as String? ?? '').trim())}'
              '${_gramsText(item['grams'])}',
    ];
  }

  /// 克数文本：整数不带小数点，与数字之间留一个空格（设计稿「米饭 150g」）。
  static String _gramsText(Object? raw) {
    final value = (raw as num?)?.toDouble();
    if (value == null) return '';
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return ' $text'
        'g';
  }

  static _EditGroupKind _kindOf(ChatEditTurnItem item) {
    final action = item.command?.action;
    if (action == null) return _EditGroupKind.other;
    if (action.startsWith('meal.')) return _EditGroupKind.meal;
    if (action == 'food.create') return _EditGroupKind.food;
    return _EditGroupKind.other;
  }

  /// 这条卡对应的餐次（**只在全部行都是同一餐的记餐命令**时返回）。
  ///
  /// 混合卡（记餐 + 新建食材）或一行午餐一行晚餐时返回 null——那时说
  /// 「午餐」会误导。
  String? _mealSlotLabel() {
    if (turn.rows.isEmpty) return null;
    String? label;
    for (final row in turn.rows) {
      final command = row.command;
      if (command == null || command.action != 'meal.create') return null;
      final raw = command.args['slot'];
      if (raw is! String) return null;
      final slotLabel = switch (raw) {
        'breakfast' => '早餐',
        'lunch' => '午餐',
        'dinner' => '晚餐',
        'snack' => '加餐',
        _ => raw,
      };
      if (label == null) {
        label = slotLabel;
      } else if (label != slotLabel) {
        return null; // 一行午餐一行晚餐：不属于同一餐
      }
    }
    return label;
  }
}

enum _EditGroupKind {
  meal('记一餐'),
  food('新建食材'),
  other('其他修改');

  const _EditGroupKind(this.label);
  final String label;
}

final class _EditGroup {
  const _EditGroup(this.kind, this.items);

  final _EditGroupKind kind;
  final List<ChatEditTurnItem> items;

  bool get hasProposed => items.any(
    (item) => item.status == ChatEditRowStatus.proposed && item.command != null,
  );

  Set<int> get proposedIndexes => {
    for (final item in items)
      if (item.status == ChatEditRowStatus.proposed && item.command != null)
        item.index,
  };
}

/// 分组头：组名 + 条数 + 「应用本组」（只有待应用行时才画按钮）。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.cardIndex,
    required this.busy,
    required this.onApplyRows,
  });

  final _EditGroup group;
  final int cardIndex;
  final bool busy;
  final ValueChanged<Set<int>> onApplyRows;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      key: Key('chat-edit-group-$cardIndex-${group.kind.name}'),
      padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
      child: SizedBox(
        width: double.infinity,
        // `Wrap` 而不是 `Row`：窄气泡（250dp）与 2.0× 下「组名 + 条数 +
        // 应用本组」放不进一行，`Row` 会溢出 57px（2026-10-23 实测）。
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceXSmall,
          children: [
            Wrap(
              spacing: LfDimens.spaceTiny,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  group.kind.label,
                  style: LfText.microStrong.copyWith(color: c.mutedForeground),
                ),
                Text(
                  '${group.items.length} 条',
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
            // 设计稿 B 的组级按钮 = **mini 小按钮**：白底 + 1px 薄荷描边 +
            // 12px w600 品牌字，紧贴分块右上角。它不是实心主按钮（那是卡底
            // 「全部应用」），也不是软底块（太重）——是一枚轻量描边钮。
            //
            // 2026-10-24 用户先要「显眼一些」（当时是纯文本），随后选定方案 B：
            // 设计稿给了明确的档位，按稿实现。**触控高度仍保持 44**（视觉
            // 内边距小、命中区大），不破坏无障碍下限。
            if (group.hasProposed && !busy)
              _GroupApplyButton(
                buttonKey: Key(
                  'chat-edit-group-apply-$cardIndex-${group.kind.name}',
                ),
                onPressed: () => onApplyRows(group.proposedIndexes),
              ),
          ],
        ),
      ),
    );
  }
}

/// 组级「应用本组」按钮（设计稿 B 的 mini 档）。
///
/// 视觉：白底 + 1px `mint-300` 描边 + R8 + 12px w600 `mintText` 字 +
/// 左右 12 / 上下 6 内边距（设计稿 `.mini`）。
///
/// 命中：`ConstrainedBox` 保证**至少 44 高**（无障碍下限），视觉高度靠
/// 内边距压到 ~30——用户看到的是小按钮，手指仍点得准。
final class _GroupApplyButton extends StatelessWidget {
  const _GroupApplyButton({required this.buttonKey, required this.onPressed});

  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = LfColors.mintText(brightness);
    final border = LfColors.mint(brightness).tone(300);
    // 命中区是**外层**（44dp），视觉小方块在里面；两层都挂同一个 Key 会
    // 出现重复 Key。Key 放在真正接收点击的 `InkWell` 上，外层 `SizedBox`
    // 只负责撑高度——`getSize` 量 InkWell 得到的仍是 44 高。
    // 命中区 = InkWell 本身，高度用 `ConstrainedBox` 抬到 44；
    // 视觉块（白底描边）由内层 `Container` 画，`Center` + `widthFactor: 1`
    // 让它只占内容宽（不撑满整行）。
    // InkWell 自己撑到 44 高（命中区），视觉块（白底描边）在它内部居中、
    // 只占内容宽——用户看到的是小按钮，手指点得到 44dp。
    return InkWell(
      key: buttonKey,
      onTap: onPressed,
      borderRadius: BorderRadius.circular(LfDimens.radiusSm),
      child: SizedBox(
        height: LfDimens.minTouchTarget,
        child: Align(
          alignment: Alignment.center,
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.lf.card,
              borderRadius: BorderRadius.circular(LfDimens.radiusSm),
              border: Border.all(color: border),
            ),
            child: Text(
              '应用本组',
              style: LfText.captionStrong.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 提案审查的一条警告（2026-10-24）。
///
/// 视觉口径：**honey 底 + 深字**（与「失败」徽标同族），不用 error 红——
/// 这些是「可能不对，你看一眼」，不是「出错了」。图标按类型区分，扫一眼
/// 就知道是餐次问题、重复还是漏项。
final class _AuditWarningRow extends StatelessWidget {
  const _AuditWarningRow({required this.warning});

  final ChatEditAuditWarning warning;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final icon = switch (warning.kind) {
      ChatEditAuditKind.slotMismatch => Icons.schedule_outlined,
      ChatEditAuditKind.duplicateFood => Icons.content_copy_outlined,
      ChatEditAuditKind.missingFood => Icons.playlist_add_outlined,
      ChatEditAuditKind.implausiblePortion => Icons.scale_outlined,
      ChatEditAuditKind.vagueSlot => Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmallPlus,
        vertical: LfDimens.spaceSmall,
      ),
      decoration: BoxDecoration(
        color: c.carbs100,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: c.cardForeground),
          const SizedBox(width: LfDimens.spaceTiny),
          Expanded(
            child: Text(
              warning.message,
              style: LfText.micro.copyWith(
                color: c.cardForeground,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条「推荐按钮」（2026-10-16）：图标 + 短文案 + 终态勾/叹号。
final class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    super.key,
    required this.suggestion,
    required this.onTap,
  });

  final ChatEditSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    final proposed = suggestion.status == ChatEditRowStatus.proposed;
    final failed = suggestion.status == ChatEditRowStatus.failed;
    final (bg, fg, border) = switch (suggestion.status) {
      ChatEditRowStatus.applied => (
        mint.tone(50),
        LfColors.mintText(Theme.of(context).brightness),
        mint.tone(200),
      ),
      ChatEditRowStatus.failed => (c.carbs100, c.cardForeground, c.border),
      _ => (c.card, c.foreground, c.border),
    };
    // 参数不全的建议（`needsMoreInfo`）：如实标「还差信息」——它是入口，
    // 不是可执行命令，用户点了会先被补问（不假装一次点完）。
    final trailing = switch (suggestion.status) {
      ChatEditRowStatus.applying => '应用中…',
      ChatEditRowStatus.applied => '已应用',
      ChatEditRowStatus.failed => '失败',
      _ => suggestion.needsMoreInfo ? '还差信息' : null,
    };
    return InkWell(
      onTap: proposed ? onTap : null,
      borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed
                  ? Icons.error_outline
                  : suggestion.status == ChatEditRowStatus.applied
                  ? Icons.check_circle_outline
                  : suggestion.needsMoreInfo
                  ? Icons.more_horiz
                  : Icons.add_circle_outline,
              size: 14,
              color: failed ? c.error : fg,
            ),
            const SizedBox(width: LfDimens.spaceTiny),
            Text(
              trailing == null
                  ? suggestion.label
                  : '${suggestion.label}（$trailing）',
              style: LfText.captionStrong.copyWith(
                color: proposed ? c.foreground : fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.item,
    required this.cardIndex,
    required this.subIndex,
    required this.subItem,
    required this.ordinal,
    required this.repairKey,
    required this.onRepair,
    required this.busy,
  });

  final ChatEditTurnItem item;

  /// 卡片下标（Key 里带它，跨卡不冲突）。
  final int cardIndex;

  /// 在本条命令的子条目里的下标（0 起）。
  final int subIndex;

  /// 这一行显示的子条目（记餐 = 一个食物；其它命令 = 命令自身）。
  final _SubItem subItem;

  /// 显示用的序号（组内跨命令连续，1 起）。设计稿序号是 1/2/3 连排。
  final int ordinal;

  /// 修复按钮的 Key（`chat-edit-repair-<卡下标>-<行下标>`）。
  final Key repairKey;

  /// 点修复按钮：把整条修复建议交给页面（kind 决定开哪个表单）。
  final ValueChanged<ChatEditRepair> onRepair;

  /// 整卡忙碌（`_turn.isApplying`）。
  ///
  /// 行内**不再有**「应用」按钮（用户裁决：按钮只在组级）——执行器按
  /// 命令粒度，三行各给一个「应用」会让用户以为能单独应用某一个食物，
  /// 实际点哪个都是整条写入。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final title = subItem.title;
    final summary = subItem.subtitle;
    final resultMessage = subItem.isPrimary ? item.resultMessage : null;
    final repair = subItem.isPrimary ? item.repair : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 设计稿 B：序号是**白底 + 1px 描边的小方块**（18×18、R6、
          // 10.5px w700），不是裸数字。它在灰底分块上把「第几条」框出来。
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: Text(
              '$ordinal',
              key: Key(
                'chat-edit-subitem-ordinal-$cardIndex-${item.index}-$subIndex',
              ),
              // 设计稿写 10.5px；token 里没有该档，用最接近的 `label`(11px)
              // **不新起一个档位**——序号是装饰性数字，11 与 10.5 的差肉眼不可辨。
              style: LfText.label.copyWith(
                color: c.mutedForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // 设计稿 B 的行只有「序号 + 文字」。类型图标（加号/铅笔/垃圾桶）
          // 在同一条命令的多个食物行上会重复出现（三行三个加号），
          // 既没增加信息又挤占宽度——2026-10-24 用户：「食材前边那个加号
          // 没啥用，可以删掉」。
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: Key(
                    'chat-edit-subitem-title-$cardIndex-${item.index}-$subIndex',
                  ),
                  // 设计稿：14px w600、行高 1.35。
                  style: LfText.body.copyWith(
                    color: c.foreground,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // 方案 B（用户选定）：食材行 = 三色点宏量；其它行仍是副标题。
                if (subItem.isFoodRow)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _MacroDots(
                      cardIndex: cardIndex,
                      itemIndex: item.index,
                      subIndex: subIndex,
                      protein: subItem.proteinPer100g ?? 0,
                      carbs: subItem.carbsPer100g ?? 0,
                      fat: subItem.fatPer100g ?? 0,
                    ),
                  )
                else if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      summary,
                      // 设计稿：12px muted、行高 1.45。
                      style: LfText.caption.copyWith(
                        color: c.mutedForeground,
                        height: 1.45,
                      ),
                    ),
                  ),
                if (resultMessage != null)
                  Text(
                    resultMessage,
                    style: LfText.micro.copyWith(
                      color: item.status == ChatEditRowStatus.failed
                          ? c.error
                          : c.primary,
                    ),
                  ),
                // 训练计划草案：这一行直接渲染**共享计划卡**（2026-10-16
                // 用户：「AI 生成训练计划时在对话框里输出这样一个卡片」）。
                // 参数里的 `exercise` 本来就是动作名（allow-list 里的名字），
                // 所以这里 nameOf 用恒等——不查库、不猜。
                if (item.command?.action ==
                    ChatEditCard.workoutPlanCreateAction) ...[
                  const SizedBox(height: LfDimens.spaceSmall),
                  PlanDraftCard(
                    days: _planDraftDays(item.command!.args),
                    nameOf: (name) => name,
                    keyPrefix: 'chat-plan-draft-day',
                    dense: true,
                  ),
                ],
                // 失败但可修复（缺食材）：给一个**能点的下一步**，而不是
                // 让用户自己去食物库摸路（2026-10-16 用户要求）。
                if (repair != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        key: repairKey,
                        onTap: () => onRepair(repair),
                        borderRadius: BorderRadius.circular(
                          LfDimens.radiusFull,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: c.muted,
                            borderRadius: BorderRadius.circular(
                              LfDimens.radiusFull,
                            ),
                            border: Border.all(color: c.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                size: 14,
                                color: c.primary,
                              ),
                              const SizedBox(width: LfDimens.spaceTiny),
                              // 方案 B 把行收窄了（分块 + 序号 + 图标 + 状态
                              // 徽标），修复按钮的长文案（「新建窗口「四号
                              // 窗口」」）会顶破 1px。`Flexible` + 省略号吸收。
                              Flexible(
                                child: Text(
                                  repair.label,
                                  style: LfText.captionStrong.copyWith(
                                    color: c.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 行内**没有**按钮（用户裁决 2026-10-24）：执行器按命令粒度，
          // 三行各给一个「应用」会让用户以为能单独应用某个食物，实际点哪个
          // 都是整条写入。批量动作在组头，单条快照在组内序号——不需要行内按钮。
          //
          // 状态徽标仍保留（待应用 / 已应用 / 失败 / 已忽略）：它是**状态**，
          // 不是动作，放在行尾不会误导。
          //
          // 食材行（方案 B）也保留——2026-10-25 第一版为「不挤」把它去掉了，
          // 结果用户看不出这一行到底应用了没有（既有测试也立刻抓到：
          // 「已忽略」徽标少一个）。改为**热量块下方另起一行**：热量在上、
          // 状态在下，两者都保得住。
          const SizedBox(width: 8),
          if (subItem.isFoodRow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _kcalText(subItem.kcalPer100g),
                  key: Key('chat-edit-food-kcal-$cardIndex-${item.index}'),
                  style: LfText.title.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.foreground,
                    height: 1.1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _statusBadge,
                ),
              ],
            )
          else
            _statusBadge,
        ],
      ),
    );
  }

  /// `workout.plan.create` 的 `days` 参数 → 计划卡要的草案天列表。
  ///
  /// 结构已由 `ChatEditArgType.planDays` 校验过（weekday 1–7、每天 1–20 条、
  /// sets/reps 正整数、weightKg 可选非负），这里只做形状搬运。
  List<AiWorkoutPlanDayDraft> _planDraftDays(Map<String, Object> args) {
    final days = args['days'] as List;
    return [
      for (final day in days.cast<Map<String, Object>>())
        AiWorkoutPlanDayDraft(
          weekday: day['weekday'] as int,
          entries: [
            for (final entry
                in (day['entries'] as List).cast<Map<String, Object>>())
              PlannedExerciseDraft(
                exerciseId: entry['exercise'] as String,
                targetSets: entry['sets'] as int,
                targetReps: entry['reps'] as int,
                targetWeightKg: entry['weightKg'] as double?,
              ),
          ],
        ),
    ];
  }

  /// 行状态徽标（文案与改造前的裸文字逐字一致，只是换了呈现）。  /// 行状态徽标（文案与改造前的裸文字逐字一致，只是换了呈现）。
  LfBadge get _statusBadge => switch (item.status) {
    ChatEditRowStatus.proposed => const LfBadge.neutral('待应用'),
    ChatEditRowStatus.applying => const LfBadge.neutral('应用中…'),
    ChatEditRowStatus.applied => const LfBadge.mint('已应用'),
    ChatEditRowStatus.failed => const LfBadge.honey('失败'),
    ChatEditRowStatus.dismissed => const LfBadge.dashed('已忽略'),
  };
}
