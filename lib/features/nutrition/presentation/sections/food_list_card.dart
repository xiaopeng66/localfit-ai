import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';

/// A `app.js:195` 的**单卡列表**：一张 `.card.food-list` 包住整列 `.food-row`。
///
/// 三轮原型都是这个形态：行与行之间只有 1px 分隔线，**行不再是各自的卡**
/// （本仓改造前是「每行一张白卡 + 8dp 间距」，扫一列时会看到一串各自带圆角与
/// 阴影的方块，与 A 的整块列表不是一回事）。
///
/// 三个件分工：
///  * [FoodListCard] —— 卡面本身（`DecoratedSliver`，装饰复用内容卡的
///    [lfCardDecoration]）+ 行的左右内衬 12（A `.food-list{padding:0 12px}`，
///    它盖掉了 `.card` 的 16，所以卡内上下为 0：上下 8 在行自己身上）；
///  * [FoodListRow] —— 行壳：在本行下缘画一条 1px 分隔线（**不参与布局**，
///    所以行高恒等于原型实测值，已知行高的跳转保护不变）；
///  * [_FoodListDividerLine] —— 那 1px 线（颜色 `--track`，A polish 把
///    `.food-row` 的 `border-bottom-color` 从 `--border` 改成它）。
///
/// **为什么用 `DecoratedSliver` 而不是给整个列表套一张卡**：卡面必须随列表
/// 一起滚（A 的 `.card` 就是列表的滚动内容），`DecoratedSliver` 的装饰范围 =
/// 整个 sliver 的绘制范围，圆角只在列表的首尾露出来 —— 与 A 的截图一致；
/// 而「套一张盒状卡 + 里面放 `ListView`」会要多一层无界高度的盒子。
///
/// 行高由谁定：仍由 `SliverPrototypeExtentList` 量原型（见
/// `food_library_view.dart` 的 `_prototypeCard`，那段 ANR 保护与理由一字未动）。
/// [FoodListRow] 只用 `Stack` 叠一条 `Positioned` 的分隔线，量到的高度不变。
class FoodListCard extends StatelessWidget {
  const FoodListCard({super.key, required this.sliver});

  /// 卡面里的 sliver（通常是那枚 `SliverPrototypeExtentList`）。
  final Widget sliver;

  /// 行的左右内衬（A `.food-list{padding:0 12px}`）。
  static const EdgeInsetsGeometry rowInset = EdgeInsets.symmetric(
    horizontal: LfDimens.spaceMedium,
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedSliver(
      // 底色必须由装饰自己画：sliver 上没有 `Material` 外壳。
      decoration: lfCardDecoration(context, color: context.lf.card),
      sliver: SliverPadding(padding: rowInset, sliver: sliver),
    );
  }
}

/// 一行（A `.food-row`）+ 它下缘的 1px 分隔线。
///
/// [dividerKey] 非空 = 画分隔线（并给它这个 Key，供测试定位）；末行传 null
/// ——A 用 `.food-row:last-child{border-bottom:0}` 表达同一件事。
///
/// 分隔线放在 `Stack` 里 `Positioned` 叠在行的下缘，**不占布局**：行高仍由
/// 内容（图标 40 + 上下 8）决定，与骨架逐项同构；A 是给行加 `border-bottom`，
/// CSS 里那条线会把行撑高 1px（`box-sizing` 之外），本仓不复制那 1px 的抖动。
class FoodListRow extends StatelessWidget {
  const FoodListRow({super.key, required this.child, this.dividerKey});

  final Widget child;
  final Key? dividerKey;

  @override
  Widget build(BuildContext context) {
    final divider = dividerKey;
    if (divider == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _FoodListDividerLine(key: divider),
        ),
      ],
    );
  }
}

/// 1px 分隔线（A `.food-row{border-bottom:1px solid var(--track)}`）。
class _FoodListDividerLine extends StatelessWidget {
  const _FoodListDividerLine({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 1, child: ColoredBox(color: context.lfc.ringTrack));
  }
}
