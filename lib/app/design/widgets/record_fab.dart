import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';

/// 右下主操作圆钮（docs/21 §5.2 `nutrition-record-fab` / §2.4 彩色阴影白名单
/// `LfShadows.recordFab`）。
///
/// 位置：`right: 16`，底边抬到导航栏之上。设计稿
/// `bottom-[calc(80px_+_env(safe-area-inset-bottom))]` 给的是 80；docs/29 §P6
/// 需求 13（「要更浮空、与下边分层」）把它抬到 **96**，阴影同步加强
/// （见 `LfShadows.recordFab`）。
///
/// 【曾经量出来的真实间距】docs/29 说底距 80 时只离凸起圆 6.5dp（= 80 − 73.5），
/// 但那是**设计稿的算术**，不是实现的实际值：当时的底距是按
/// `MediaQuery.paddingOf(context).bottom` 算的，而 shell 的
/// `Scaffold(extendBody:true)` 会把 body 的 padding.bottom 顶成**底栏高度**
/// （73.5dp + 手势带，见 `_BodyBuilder`），FAB 等于把底栏又加了一遍。2026-10-06
/// P6 用测试与设备截图实测：间距恒等于 `bottomOffset` 本身（80 / 96），
/// 凸起圆上缘到 FAB 下缘是 81.5dp 而不是 6.5dp——**用户说的「贴住了」在旧实现里
/// 其实够不着那个成因**。改用 [LfInsets.bottom]（读视图的真实手势带）后，
/// 间距才等于设计稿的算术 `96 − 73.5 = 22.5dp`，与 docs/29 的目标值一致。
class RecordFab extends StatelessWidget {
  const RecordFab({super.key, required this.onPressed, this.tooltip = '记录一餐'});

  final VoidCallback? onPressed;
  final String tooltip;

  /// 设计稿 `bottom-[80px]`；docs/29 §P6 需求 13 抬到 96（理由见类注释）。
  /// 这里是**距真机手势带之上**的净底距：间距 = 本值 − 底栏预留 73.5
  /// （详见 [PositionedRecordFab] 对 `paddingOf` 的说明）。
  static const double bottomOffset = 96;

  /// 圆钮自身的占位（48）+ 外层 1dp 内衬两侧 = 50。
  static const double footprint = 50;

  /// 滚动容器末尾至少要留出的高度：**让最后一行内容能滚出圆钮的覆盖带**。
  ///
  /// RV2-P2-06（`docs/52`）：FAB 是浮层，2.0× 字号下营养卡的「还可摄入 X kcal」
  /// 会正好落在它下面。只留 `navReserve`（73.5）不够——圆钮顶边在
  /// `bottomOffset + footprint = 146`，内容必须能滚到 146 之上才算「可读」。
  /// 取两者较大值：手势带很大时也不少于 `navReserve`。
  static double contentClearance(BuildContext context) {
    final reserve = LfInsets.navReserve(context);
    final aboveFab = LfInsets.bottom(context) + bottomOffset + footprint;
    return aboveFab > reserve ? aboveFab : reserve;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final button = PressableScale(
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          key: const Key('nutrition-record-fab'),
          color: c.primary,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Tooltip(
              message: tooltip,
              child: Icon(Icons.add, size: 24, color: c.primaryForeground),
            ),
          ),
        ),
      ),
    );
    // 阴影单独一层：Material 的 elevation 会连带影响 ink 绘制，设计稿的
    // 彩色阴影要精确控制，用 DecoratedBox 包在外层更可控。
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: LfShadows.recordFab(c.primary),
      ),
      child: Padding(padding: const EdgeInsets.all(1), child: button),
    );
  }
}

/// 把 [RecordFab] 定位到页面右下（设计稿 `fixed bottom-[80px] right-4`）。
///
/// 独立成件而不是用 `Scaffold.floatingActionButton`：本页是 shell 分支内的
/// 页面，`extendBody` 后 FAB 的默认 16dp 底边距会落进导航栏体里。
class PositionedRecordFab extends StatelessWidget {
  const PositionedRecordFab({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 必须用 [LfInsets.bottom]（读 View 的物理手势带），**不能**用
    // `MediaQuery.paddingOf(context).bottom`：shell 的 `Scaffold(extendBody:true)`
    // 会把 body 的 `padding.bottom` 顶成 `max(手势带, 底栏高)`，也就是 73.5dp
    // （`_BodyBuilder` 的既有行为），于是 FAB 等于把底栏高度**又加了一遍**，
    // 实测漂到间距 97dp（应为 22.5dp）——2026-10-06 P6 走查量出来的。
    // 同文件历史注释早就写明「extendBody 后 FAB 会落进导航栏体里」，这里
    // 就是那条坑的真实形态。
    final safeBottom = LfInsets.bottom(context);
    return Positioned(
      right: LfDimens.pagePadding,
      bottom: RecordFab.bottomOffset + safeBottom,
      child: RecordFab(onPressed: onPressed),
    );
  }
}
