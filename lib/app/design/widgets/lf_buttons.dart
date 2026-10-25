/// 按钮族（docs/21 §3.8 B1–B8）。
///
/// 【为什么需要这一层】§3 原先有容器/图表/表单/对话/徽章/导航/动效七类而
/// **没有按钮类**，于是实现层各自裸用 Material 默认样式：`FilledButton.tonal`
/// 的底色走 `ColorScheme` 回落链 `secondaryContainer ?? secondary`，也就是
/// 与「实心主按钮」同色的 mint-600——用户 2026-10-03 点名的
/// 今日页「记录第一条」就是它（`dashboard_weight_card.dart:256`）。本件把 HTML
/// 里那套按钮语言固化成九型，是全 App 唯一的按钮形态来源。
///
/// 【薄封装】内部仍渲染**原生** `FilledButton`/`TextButton`，并且把 [key]
/// 一并落到内层按钮上。因此既有的
/// `find.byKey(k)` + `tester.widget<FilledButton>(find.byKey(k))` /
/// `find.byType(FilledButton)` 继续成立——迁移时不必改写一大批测试。
///
/// 【语义】`button: true` 与文本标签由内层原生按钮提供。本件**不再包一层
/// `Semantics`**：原生按钮已经成立，多包一层只会多出一个无标签的重复节点
/// （敲「必须有语义标签」这条硬规则靠的是内层，不是外层）。
///
/// 【配色单一来源】实心按钮**不自己设 `backgroundColor`**：颜色由
/// `app_theme.dart` 的 `filledButtonTheme` 给出（亮 mint-600 / 高对比 mint-700 /
/// 暗 primary），与 §3.8「实心档位随主题走，不得另起一套」一致。需要读同一
/// 档位的地方用 [lfSolidButtonFill]。
library;

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/widgets/dashed_border.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';

/// 实心档背景（与 `app_theme.dart` 的 `filledButtonTheme` **同源**）。
///
/// 从主题读而不是自己算 `mint.tone(600)/tone(700)/primary`：§3.8 硬规则要求
/// 「实心档位随主题走，不得另起一套」，读主题就天然只有一处真相。主题缺席
/// （裸 `MaterialApp` 的测试）时回落 `colorScheme.primary`。
Color lfSolidButtonFill(BuildContext context) {
  final theme = Theme.of(context);
  return theme.filledButtonTheme.style?.backgroundColor?.resolve(
        const <WidgetState>{},
      ) ??
      theme.colorScheme.primary;
}

/// 按钮标签（可选前置图标 + 文本）。图标 16dp、图标与文字间距 6dp。
Widget _lfButtonLabel(
  BuildContext context,
  String label,
  IconData? icon,
  TextStyle style, {
  bool loading = false,
}) {
  if (loading) {
    return Semantics(
      label: '$label，处理中',
      liveRegion: true,
      child: const ExcludeSemantics(child: AppButtonDotsLoader()),
    );
  }
  if (icon == null) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium!.merge(style),
      textAlign: TextAlign.center,
    );
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: LfDimens.iconSm),
      const SizedBox(width: LfDimens.spaceTiny),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium!.merge(style),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

/// B1 主按钮（docs/21 §3.8）：实心 / 16 圆角 / h40 / 14 w600 / 无阴影。
/// 用于表单与弹层主行动（「保存」「确认」「生成」）。
///
/// [LfPrimaryButton.emphasized] 是 B1e：同一几何，底色换成
/// `cta-write-plan` 的 135° mint-400→mint-500 渐变 + `aiPrimaryCta` 35% 阴影，
/// 只给 AI 类主 CTA 用（全设计稿只有一处）。
///
/// 【触达】视觉高度 40，命中盒靠 Material 的 `padded` 触达膨胀补到 48
/// （§3.8 硬规则 ≥44），与 B4 图标钮「视觉 36 / 触达 44」是同一手法。
/// 【key 只落内层】构造参数 `key` 不交给外层包装，而是转发给内层原生按钮；
/// 外层元素一律 `super(key: null)`。若两边都挂同一个 key，`find.byKey(k)` 会命中
/// 两个元素、`evaluate().single` 直接抛 `Bad state: Too many elements`——而本仓
/// 大量断言正是 `find.byKey(k)…as TextButton`（键认的是**原生控件**，不是包装）。
/// 写成显式 `super(key: null)` 而不是省略，是因为
/// `use_key_in_widget_constructors` 只认「构造里出现了 key 形参且交给了 super」。
class LfPrimaryButton extends StatelessWidget {
  const LfPrimaryButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.semanticLabel,
    this.fitLabel = false,
  }) : _innerKey = key,
       emphasized = false,
       super(key: null);

  const LfPrimaryButton.emphasized({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.semanticLabel,
    this.fitLabel = false,
  }) : _innerKey = key,
       emphasized = true,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 进行中：显示三点跳动并禁用点击（[AppButtonDotsLoader]）。
  final bool busy;

  /// 撑满可用宽度（`w-full`）。表单主行动一般为 true。
  final bool expand;

  /// B1e 渐变强调形态。
  final bool emphasized;

  /// 语义标签与可视文案不同时用（docs/07 §9.3：按钮文案可能被压缩，
  /// 语义必须完整）。给定时它取代按钮内的可视文本成为无障碍名称。
  final String? semanticLabel;

  /// 标签放不下时**等比缩小、不折行**（窄坑位里的既有兜底口径，与
  /// `LfStatTile` / `MacroDotLine` 的 `FittedBox.scaleDown` 同）。
  ///
  /// Round7 阶段 3 · 裁决 ④（2026-10-15）：剩餐编辑器的确认钮在 360dp 的三分
  /// 之一宽坑位里，5 字标签会折成两行并把整排按钮拉得不等高（比 3 行按钮还
  /// 难看）；宁可等比缩小，也不让「入账」两个字被拆开。默认 false ⇒ 既有
  /// 调用点零变化。
  final bool fitLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final Widget rawInner = _lfButtonLabel(
      context,
      label,
      icon,
      LfText.bodyStrong.copyWith(
        color: busy || onPressed == null
            ? c.mutedForeground
            : c.primaryForeground,
      ),
      loading: busy,
    );
    // 无界宽度下 `Text` 永不折行 ⇒ scaleDown 缩到坑位宽即可（单行保真）。
    final Widget inner = fitLabel
        ? FittedBox(fit: BoxFit.scaleDown, child: rawInner)
        : rawInner;
    final button = FilledButton(
      key: _innerKey,
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: expand ? const Size.fromHeight(44) : const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: LfDimens.spaceLarge),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LfDimens.buttonRadius),
        ),
        textStyle: LfText.bodyStrong,
        elevation: 0,
      ),
      child: semanticLabel == null
          ? inner
          : Semantics(
              label: semanticLabel,
              child: ExcludeSemantics(child: inner),
            ),
    );
    return PressableScale(child: button);
  }
}

/// B2 底部确认按钮：实心 / h48 / 14 w600 / 12 圆角 / 无阴影。
///
/// 用于流程末端的确认：固定底栏主行动、**弹层底部主行动**（§3.8 裁决：
/// HTML 没有弹层内按钮，弹层底部主行动归 B2，弹层内次级行动归 B6）。
///
/// Round7 A 有效值（`refinement.css:3`）：圆角与其余按钮同为 12（旧稿的
/// 「full 圆角胶囊 + 40% 彩色阴影」被覆盖——A 的 `.btn.confirm` 只改
/// `min-height:48px`，不改圆角、不画阴影）。
class LfConfirmButton extends StatelessWidget {
  const LfConfirmButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  /// h48 的圆角半径（与其余按钮同源；按钮外不再画阴影）。
  static const double _radius = LfDimens.buttonRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return PressableScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: const [],
        ),
        child: FilledButton(
          key: _innerKey,
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: expand
                ? const Size.fromHeight(LfDimens.primaryActionHeight)
                : const Size(0, LfDimens.primaryActionHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: LfDimens.spaceLarge,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LfDimens.buttonRadius),
            ),
            textStyle: LfText.bodyStrong,
            elevation: 0,
          ),
          child: _lfButtonLabel(
            context,
            label,
            icon,
            LfText.bodyStrong.copyWith(
              color: busy || onPressed == null
                  ? c.mutedForeground
                  : c.primaryForeground,
            ),
            loading: busy,
          ),
        ),
      ),
    );
  }
}

/// B3 小胶囊档位（docs/21 §3.8）：`full` 圆角 / h32 / 12 w500 / 无阴影。
/// 用于内联动作、筛选、快捷值（「加入早餐」「100g」），以及压在照片上的
/// 带字胶囊（`overlay` 档，「重新拍摄」）。
enum LfPillTone {
  /// 品牌实心：主色底 + `primaryForeground` 字。主行动。
  solid,

  /// muted 底 + mutedForeground 字。并列的次要选项。
  muted,

  /// 浅品牌底 + 品牌字。**轻强调动作**（识餐修正 / 饮水快捷值 / 训练开始）。
  ///
  /// **不是选中档**：`#ECFBF5` 对白卡只有 1.07:1，比未选中的 `muted`
  /// （1.12:1）更接近背景——用它表达选中会让「选中」比「常态」更不显眼
  /// （`RV4-P1-07`）。选中语义请用 [selected]。
  soft,

  /// 选中档（2026-10-24，`RV4-P1-07` / D7）：**必须比未选中更远离背景**。
  ///
  /// 亮色 `mint-200 #A8EBCF` + `mint-900 #114A36`（字对比 7.51）；
  /// 暗色 `mint-300 #2A3A32` + `mint-400 #4ED9A6`（字对比 6.74）。
  /// 底 vs 卡面 1.36 / 1.41 > 未选中 `muted` 的 1.12 / 1.14 ⇒ 可见度顺序正确。
  /// 与 [solid]（实底主色）区分得开，不会让「选中」看起来像「主行动按钮」。
  selected,

  /// `card`@90% 底 + `foreground` 字：**压在照片上的带字胶囊**
  /// （`拍照识餐.html:327` 的 `cta-retake` 就是 `card`/90% + foreground）。
  /// 与 [LfCircleIconButtonVariant.overlay] 同一套「浮在图上」取色，区别只是
  /// 这一档带文字而不是纯图标。
  overlay,
}

class LfPillButton extends StatelessWidget {
  const LfPillButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.tone = LfPillTone.muted,
    this.selected = false,
    this.icon,
    this.height,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final LfPillTone tone;

  /// 选中语义：**发 `Semantics(selected:)`** 并把 [tone] 提升为
  /// [LfPillTone.selected] 档（仅当 tone 是默认的 [LfPillTone.muted] 时）。
  ///
  /// 两件事都必要，缺一个就是缺陷：
  /// - 不发 `selected` → 读屏听不出哪枚被选中（`RV4-P1-09`）；
  /// - 提到 `soft` 档 → 选中比未选中更接近背景（`RV4-P1-07`，1.07 vs 1.12）。
  final bool selected;

  final IconData? icon;

  /// 视觉高度（dp）。缺省 32（B3 档，见 §3.8）。
  ///
  /// 2026-10-11（docs/32 §4 T3，需求 65）：今日推荐卡同一排里主按钮与三枚次级
  /// 胶囊高度不一致，用户看到「两个按钮上下宽度不一样」。Round7 A 起主按钮
  /// 是 `.btn` 基档 44（`styles.css:147`），该卡把本件显式提到 44 对齐；
  /// **不改 B3 的全局档位**（其余页面仍是 32，逐页迁移时按 A 的
  /// `.btn.small{min-height:44px}` 复核）。
  final double? height;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    // D7（`RV4-P1-07`）：选中语义走**专用档** `selected`，不是 `soft`。
    // `soft` 表达的是「轻强调动作」（5 处：识餐修正 / 饮水快捷值 / 菜单去维护 /
    // 训练开始 ×2），把它当选中档会让选中比未选中更不显眼。
    // 显式传了非 muted 的 tone 时尊重调用方（例如「应用」行级按钮传 soft）。
    final effectiveTone = selected && tone == LfPillTone.muted
        ? LfPillTone.selected
        : tone;
    // 【与规范字面的差异，如实记录】§3.8 写 `soft` 用 mint-50 底，但暗色 ramp
    // 的 50 档就是页面底色 `#0F1412`（mintDark.tone(50)）——画上去等于没有底。
    // 因此沿用本仓既有约定（`AppMorphChip` 选中态、`navigationBarTheme`
    // indicator 都用 100 档）：亮 mint-100 / 暗 mintDark-100，配
    // `LfColors.mintText`（亮 700 / 暗 400）保证浅底上的对比。
    // `overlay` 是「浮在照片上」的半透明档，与 LfCircleIconButton 的
    // overlay 变体取同一组色（card@90% + foreground）。
    final (bg, fg) = switch (effectiveTone) {
      LfPillTone.solid => (lfSolidButtonFill(context), c.primaryForeground),
      LfPillTone.muted => (c.muted, c.mutedForeground),
      LfPillTone.soft => (
        LfColors.brandSoft(brightness),
        LfColors.mintText(brightness),
      ),
      // `RV4-P1-07` 新档：底必须比未选中 `muted` 更远离卡面（1.36/1.41 > 1.12）。
      LfPillTone.selected => (
        LfColors.mint(brightness)
            .tone(brightness == Brightness.dark ? 300 : 200),
        LfColors.mint(brightness)
            .tone(brightness == Brightness.dark ? 400 : 900),
      ),
      LfPillTone.overlay => (c.card.withValues(alpha: 0.9), c.foreground),
    };
    // `RV4-P1-09`：类注释一直写「选中加 Semantics(selected)」，实现里却没有
    // ——读屏听不出哪枚被选中。
    //
    // 【为什么只包 `Semantics(selected:)` 而不像 `LfFilterChip` 那样再加
    // `ExcludeSemantics`】本件同时被当**动作按钮**用（「查看菜单」「加入早餐」
    // 等 13 处），内层 `TextButton` 自带 label + tap + focus 语义是必需的。
    // 加 `ExcludeSemantics` 会把这些节点的可读性整体吞掉：批次 4 实测
    // `next_meal_decision_card_test` 立刻红（label 丢失、`hasSelectedState`
    // 恒在）。所以这里用 `Semantics(container: false, selected: …)` 叠加——
    // 只在**选择语义**上补一个旗标，不动按钮原有的 label/动作。
    //
    // `selected: false` 时也不省略：整组胶囊必须都带 `hasSelectedState`，
    // 读屏才会读成「单选组」而不是「一排按钮」。
    return Semantics(
      container: false,
      selected: selected,
      child: PressableScale(
        child: TextButton(
          key: _innerKey,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            minimumSize: Size(0, height ?? 32),
            padding: const EdgeInsets.symmetric(
              horizontal: LfDimens.spaceMediumPlus,
            ),
            shape: const StadiumBorder(),
            textStyle: LfText.captionStrong.copyWith(color: fg),
            iconColor: fg,
          ),
          child: _lfButtonLabel(
            context,
            label,
            icon,
            LfText.captionStrong.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

/// B10 软底强调按钮（Round7 A `.btn.outline-brand`）：brand-soft 底 +
/// brand-strong 字 / R12 / h44 / 14 w500 / 可选前置图标（16dp，间距 6）。
///
/// 【与 B3 软档的区别】[LfPillButton] 的 `soft` 是**胶囊**（`StadiumBorder`，
/// 默认 h32、12px 字），服务卡片内的轻强调；本件是 A 的 `.btn` 基档几何
/// （R12、min-height 44、`refinement.css:3` 的 14px 字），服务页面/卡片的
/// **块级行动**（A 用 `block outline-brand` 画「记录饮食」「记录晚餐」）。
///
/// 【为什么底色明写而不是走主题】`.btn.outline-brand` 的身份就是这对
/// brand-soft/brand-strong 值（`styles.css:153`；refinement 只改圆角与字号，
/// 不改这两个值）。与 [LfPillButton] 同一取舍：这一档的颜色是本件的定义，
/// 不是主题的派生。
class LfSoftButton extends StatelessWidget {
  const LfSoftButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
    this.semanticLabel,
    this.dense = false,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;

  /// 前置图标（16dp，A `.btn{gap:6px}`）。
  final IconData? icon;

  /// 撑满可用宽度（A `.btn.block{width:100%}`）。
  final bool expand;

  final bool busy;

  /// 语义标签与可视文案不同时用。
  final String? semanticLabel;

  /// 紧凑档（2026-10-24 编辑卡组级按钮）：14px 字 / 12px 内边距。
  ///
  /// 用在**同一张卡里还有更高一级主行动**的场合（编辑卡的「应用本组」旁边
  /// 就是卡底「全部应用」）。**不改档位**——仍是 B10 软底，只是横向与字号
  /// 收敛，免得它压过主行动。
  ///
  /// 【高度仍是 48，刻意如此】实测 `minimumSize` 写 36 也被 Material 的
  /// `tapTargetSize` 抬到 48 —— 那是对的：可点控件的触控目标不该为了好看
  /// 低于无障碍下限（`LfDimens.minTouchTarget` 44/48）。所以 dense 只收
  /// 横向与字号，**不动高度**。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = LfColors.mintText(brightness);
    final disabledFg = context.lf.mutedForeground;
    final inner = _lfButtonLabel(
      context,
      label,
      icon,
      (dense ? LfText.captionStrong : LfText.body).copyWith(
        fontWeight: FontWeight.w500,
        color: busy || onPressed == null ? disabledFg : fg,
      ),
      loading: busy,
    );
    return PressableScale(
      child: TextButton(
        key: _innerKey,
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: LfColors.brandSoft(brightness),
          foregroundColor: busy || onPressed == null ? disabledFg : fg,
          minimumSize: expand
              ? Size.fromHeight(dense ? 36 : 44)
              : Size(0, dense ? 36 : 44),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? LfDimens.spaceMedium : LfDimens.spaceLarge,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LfDimens.buttonRadius),
          ),
          textStyle: (dense ? LfText.captionStrong : LfText.body).copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        child: semanticLabel == null
            ? inner
            : Semantics(
                label: semanticLabel,
                child: ExcludeSemantics(child: inner),
              ),
      ),
    );
  }
}

/// B9 纯图标圆钮（docs/31 §2 D4，2026-10-09 需求 44「只要图标，不要添加
/// 两个字」）。
///
/// 与 [LfCircleIconButton]（顶栏件，`lf_top_bar.dart`）的区别在**取色档**：
/// 那件是 `muted` / `primary` / `overlay` 三档、服务导航与浮层；本件是
/// `mint-100` 浅品牌底 + `mintText` 品牌字，服务**卡片内的强调动作**
/// （体重卡的「添加」）。两件都遵守同一条几何契约：**视觉圆 28dp、
/// 布局盒 = 命中盒 = 44dp**（[LfDimens.minTouchTarget]），视觉圆在盒内居中。
///
/// 【为什么不做「视觉 28 + 命中 44 且不撑布局」】做不到：Flutter 的父级
/// `hitTest` 先查 `size.contains`，超出布局盒的点击根本传不进来（这与 CSS
/// 能用伪元素/负 margin 扩大可点区不同）。所以命中盒必须**真的**占 44dp，
/// 卡片行高因此是 44。
///
/// 【无障碍】纯图标钮**必须**给 [semanticLabel]：没有可见文字，读屏就只剩
/// 一个「按钮」。与 §5.8.3 同一条硬规则（图标钮要有 tooltip / 语义标签）。
class LfIconButton extends StatelessWidget {
  const LfIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.iconSize,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// 读屏标签（纯图标钮必填，见类文档）。
  final String semanticLabel;

  final double? iconSize;

  /// 视觉圆直径（dp）。
  static const double visualSize = 28;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    final enabled = onPressed != null;
    final fg = enabled
        ? LfColors.mintText(brightness)
        : context.lf.mutedForeground;
    final circle = Material(
      // 禁用时落 muted 底：与可用态（mint-100）区分得开，不靠降透明度。
      color: enabled ? mint.tone(100) : context.lf.muted,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: visualSize,
          height: visualSize,
          child: Icon(icon, size: iconSize ?? LfDimens.iconMd, color: fg),
        ),
      ),
    );
    return Tooltip(
      // 标签由下面的 `Semantics` 提供，tooltip 不再重复挂一个同名节点
      // （两个同名节点会让 `bySemanticsLabel` 的 `findsOneWidget` 变脆）。
      message: semanticLabel,
      excludeFromSemantics: true,
      child: Semantics(
        label: semanticLabel,
        button: true,
        enabled: enabled,
        onTap: onPressed,
        container: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onPressed,
          child: SizedBox(
            width: LfDimens.minTouchTarget,
            height: LfDimens.minTouchTarget,
            child: Center(child: ExcludeSemantics(child: circle)),
          ),
        ),
      ),
    );
  }
}

/// B5 虚线按钮（docs/21 §3.8）：`full` 圆角 / h28 / 10 w500 / mint-300 虚线边 /
/// 透明底 / 品牌字。用于「添加」类（添加图片、添加菜品、添加食材）。
///
/// 【为什么内部结构比别的按钮复杂】虚线必须画在 **28dp 的可视胶囊**上，
/// 而命中盒要被触达膨胀撑到 48——`padded` 膨胀发生在按钮外框上，若直接用
/// 按钮的尺寸画虚线，画出来会是一圈 48 高的框。做法是把虚线画在按钮的
/// **子内容**上（`CustomPaint` → `Padding` → 28 高的 `Row`），外层的膨胀区
/// 保持透明。这样既满足 ≥44 触达，又不放大虚线胶囊。
class LfDashedButton extends StatelessWidget {
  const LfDashedButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.width,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 固定宽度（设计稿是内容宽度，一般传 null）。
  final double? width;

  /// 可视胶囊高度（`px-2.5 py-1.5` + 10px 文字 ≈ 28）。
  static const double _height = 28;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    final fg = LfColors.mintText(brightness);
    final pill = CustomPaint(
      foregroundPainter: DashedBorderPainter(
        color: mint.tone(300),
        radius: _height / 2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: _height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: LfDimens.iconSm, color: fg),
                const SizedBox(width: LfDimens.spaceXSmall),
              ],
              // 族必须从主题 bodyMedium 里 merge 进来：`TextButton` 自带的
              // `DefaultTextStyle` 会**替换**环境那层（主题正文的族），只留
              // 按钮样式声明过的字段，于是裸 `LfText.microStrong` 在这里族为
              // null（2026-10-16 食堂目录捕获面：CJK 整串渲染成豆腐块）。
              // 与 `_lfButtonLabel` 对其它按钮的口径一致。
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium!
                    .merge(LfText.microStrong)
                    .copyWith(color: fg),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
    return TextButton(
      key: _innerKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: fg,
        iconColor: fg,
        // 内边距全在子内容里（虚线框住的就是它）。
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: width == null ? pill : SizedBox(width: width, child: pill),
    );
  }
}

/// 纯文字按钮的公共骨架（B6/B7 只差一个字色）。
class _LfTextualButton extends StatelessWidget {
  const _LfTextualButton({
    Key? key,
    required this.label,
    required this.color,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.tapTargetSize = MaterialTapTargetSize.padded,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// 触达盒策略。默认 `padded`（Material 会把布局盒撑到 48）；传 `shrinkWrap`
  /// 时布局盒 = 内容高——食物详情行动行按 A `.food-detail-actions .btn{
  /// min-height:46px}` 要的是 **46 就是盒高**（连热区一起），与 3-2a 给
  /// `LfFilterChip` 定的口径同一条（`tapTargetSize: shrinkWrap` 是必须的，
  /// 否则布局盒凭空 +2dp）。热区由调用点自己给的 `minHeight` 保证 ≥44。
  final MaterialTapTargetSize tapTargetSize;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: _innerKey,
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        iconColor: color,
        // 内边距随文本（§3.8 B6），不做 `w-full`。
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.spaceSmall,
          vertical: LfDimens.spaceTiny,
        ),
        minimumSize: Size.zero,
        tapTargetSize: tapTargetSize,
      ),
      child: _lfButtonLabel(
        context,
        label,
        icon,
        LfText.body.copyWith(color: color, fontWeight: FontWeight.w500),
        loading: busy,
      ),
    );
  }
}

/// B6 文字按钮（docs/21 §3.8）：透明底 / 品牌字 / 14 w500 / 无阴影。
///
/// **空态行动一律用它**（2026-10-03 用户裁决）——空态的入口不该与页面主行动
/// 抢视觉；也是设计稿里「查看全部」「取消」的形态（`今日.html:481-484`）。
///
/// 【字色】走既有 `LfColors.mintText`（亮 mint-700 / 暗 mint-400，§2.1.6
/// 「文字级一律 600/700」）。HTML 写的是 mint-600，落在该规则的 600/700 档内；
/// 取 700 是因为 600 在浅底上的对比仍不足 4.5:1。
class LfTextButton extends StatelessWidget {
  const LfTextButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.tapTargetSize = MaterialTapTargetSize.padded,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// 触达盒策略（默认 `padded` = 既有行为；`shrinkWrap` 的用途见
  /// [_LfTextualButton.tapTargetSize]）。
  final MaterialTapTargetSize tapTargetSize;

  @override
  Widget build(BuildContext context) {
    return _LfTextualButton(
      // key 落进内层原生 TextButton（见文件头「key 只落内层」）。
      key: _innerKey,
      label: label,
      color: LfColors.mintText(Theme.of(context).brightness),
      onPressed: onPressed,
      icon: icon,
      busy: busy,
      tapTargetSize: tapTargetSize,
    );
  }
}

/// B7 危险文字按钮（docs/21 §3.8）：透明底 / `--lf-state-error` 字 / 14 w500。
///
/// **必须配二次确认浮层**——设计稿没有实心 error 按钮，破坏性操作一律
/// 「文字型 + 确认」（「清除全部数据」「删除计划」）。
class LfDangerButton extends StatelessWidget {
  const LfDangerButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.tapTargetSize = MaterialTapTargetSize.padded,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// 触达盒策略（默认 `padded` = 既有行为；`shrinkWrap` 的用途见
  /// [_LfTextualButton.tapTargetSize]）。
  final MaterialTapTargetSize tapTargetSize;

  @override
  Widget build(BuildContext context) {
    return _LfTextualButton(
      key: _innerKey,
      label: label,
      color: context.lf.error,
      onPressed: onPressed,
      icon: icon,
      busy: busy,
      tapTargetSize: tapTargetSize,
    );
  }
}

/// B8 小实心按钮（docs/21 §3.8）：**12 圆角** / h36 / 12 w500 / 实心品牌底。
/// 设计稿只有一处用例——`我的.html:425` 的「保存配置」。12 是实测特例。
class LfSmallButton extends StatelessWidget {
  const LfSmallButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return PressableScale(
      child: FilledButton(
        key: _innerKey,
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: LfDimens.spaceLarge),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LfDimens.radiusMd),
          ),
          textStyle: LfText.captionStrong,
          elevation: 0,
        ),
        child: _lfButtonLabel(
          context,
          label,
          icon,
          LfText.captionStrong.copyWith(
            color: busy || onPressed == null
                ? c.mutedForeground
                : c.primaryForeground,
          ),
          loading: busy,
        ),
      ),
    );
  }
}

/// B11 链接按钮（Round7 A `.link-button`，`styles.css:135`）：透明底 /
/// 12 w500 `--brand-strong` / 最小 44×44 / 可选 16dp 前置图标（间距 5）/
/// 可选 10px `--muted` 副行。
///
/// 【为什么单列一型】A 的 `.link-button` 与 B6 文字按钮**不是同一档**：B6 是
/// 14 w500、没有最小尺寸（内衬随文本），本件是 12px 的链接语言，而且
/// `min-height:44px`（`styles.css:135`）+ `min-width:44px`（`refinement.css:18`）
/// ——页面上最轻的一档，但触达不许缩水。食物库页尾（A `.library-footer`）
/// 就是它：两行文字的主行 + 副行只有这一型表达得了。
///
/// 【副行的排版】A `polish.css:28-29`：`>span` 列排、start 对齐、`line-height:1.6`；
/// `small` 是 10px `--muted`。副行与主行同链（同一个触达盒），所以整条链的
/// 高度是 44（两行本身 35.2，装在 44 的盒里）——不是两枚独立控件。
///
/// 【字族】两行都走 `主题 bodyMedium.merge(…)`（同 `_lfButtonLabel` 的既有
/// 口径）：`ButtonStyleButton` 会**替换**环境 `DefaultTextStyle`，自建
/// `TextStyle` 不带字体族时测试帧里会渲染成 .notdef 空方框（阶段 3 步骤 2b 的
/// 缺陷 ⑫）。
class LfLinkButton extends StatelessWidget {
  const LfLinkButton({
    Key? key,
    required this.label,
    this.subtitle,
    this.icon,
    this.onPressed,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;

  /// 副行（A `.library-footer .link-button small`）：10px `--muted`，主行之下。
  final String? subtitle;

  /// 前置图标（16dp，A `icon('file-import', 16)` 与 `.btn{gap:6px}` 的链接档）。
  final IconData? icon;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = LfColors.mintText(brightness);
    final base = Theme.of(context).textTheme.bodyMedium!;
    final sub = subtitle;
    // 行高 1.6 是 A 给**两行的那个 span** 的（`polish.css:28`）；单行的链接
    // （「食物管理」）没有这条覆盖，走 captionStrong 自己的 1.4。
    final labelStyle = base.merge(
      LfText.captionStrong.copyWith(
        color: color,
        height: sub == null ? null : 1.6,
      ),
    );

    Widget text = Text(label, style: labelStyle, textAlign: TextAlign.center);
    if (sub != null) {
      text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          Text(
            sub,
            style: base.merge(
              LfText.micro.copyWith(
                color: context.lf.mutedForeground,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
    }
    final glyph = icon;
    if (glyph != null) {
      text = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(glyph, size: 16),
          const SizedBox(width: 5),
          Flexible(child: text),
        ],
      );
    }

    return TextButton(
      key: _innerKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        iconColor: color,
        // A `padding: 0 3px`：内衬只为了不让字贴着触达盒边缘。
        padding: const EdgeInsets.symmetric(horizontal: 3),
        // A `min-height:44px` + `refinement.css:18` 的 `min-width:44px`。
        minimumSize: const Size(44, 44),
        // 命中盒再按本仓 §3.8 硬规则膨胀到 48（可视盒仍是 44）。
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: text,
    );
  }
}
