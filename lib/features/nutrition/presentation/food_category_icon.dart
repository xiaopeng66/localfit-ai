import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

/// 食物分类图标块：分类线稿 + 圆角方底。
///
/// 形状是 **44dp 圆角方块**（`radiusMd`，docs/21 §2.3「图片缩略」档）而不是
/// 旧版的 40dp 圆形：食物卡是列表项，圆角方块与设计稿的缩略图语言一致，也
/// 让 44dp 的触达尺寸与 [LfDimens.minTouchTarget] 对齐（用户 2026-10-03
/// 走查「食物卡片的表现形式不直观」，图标块是其中一项）。
///
/// **两条 A 的取值由调用点给**（默认值保留旧形态，别的屏不受影响）：
///  * [background]：null = mint-100 底（记录一餐弹层的已添加项列表行仍在用）；
///    食物行/食物详情传 `context.lf.background`（A `polish.css:20` 把
///    `.food-symbol` 的底从 brand-soft 改成 `--bg`）；
///  * [padding]：默认 10（图形缩在块里）；A 的 `.food-symbol img` 是
///    `width:40px;height:40px`（图形**充满**整块），那两处传 `EdgeInsets.zero`。
///
/// 语义：一个 `image` 节点，名字就是分类（「主食」…），供读屏与
/// `find.bySemanticsLabel` 使用；图标本身是 `ExcludeSemantics` 的装饰件。
final class FoodCategoryIcon extends StatelessWidget {
  const FoodCategoryIcon({
    required this.category,
    this.foodId,
    this.size = LfDimens.minTouchTarget,
    this.padding = const EdgeInsets.all(LfDimens.spaceSmallPlus),
    this.background,
    this.radius = LfDimens.radiusMd,
    super.key,
  });

  final FoodCategory category;
  final String? foodId;

  /// 图标块边长（默认 44dp）。
  final double size;

  /// 图形与块边缘之间的内衬。
  final EdgeInsetsGeometry padding;

  /// 图标块底色。null = mint-100（旧形态）。
  final Color? background;

  /// 圆角（默认 [LfDimens.radiusMd] = 12，列表行档）。
  ///
  /// Round7 阶段 3 · 3-2d（D46）：食物详情 hero 的图标块是 A
  /// `.food-detail-icon` 的 **r16**（52×52 / 图形 40）——同一枚分类图标在
  /// 「行」与「hero」两处只有尺寸与圆角两档不同，不为它另起一件。
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: foodId == null
          ? null
          : Key('food-category-icon-${category.id}-$foodId'),
      label: category.label,
      image: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                background ??
                LfColors.mint(Theme.of(context).brightness).tone(100),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: SizedBox.square(
            dimension: size,
            child: Padding(
              padding: padding,
              child: SvgPicture.asset(
                category.assetPath,
                // 资产自带的描边是 mint-strong（浅色下与主题色同值）；暗色下
                // 按主题给一枚可辨的 mint（A 那边等价的是
                // `filter:brightness(1.65) saturate(.8)`，这里用主题色代替一条
                // 手写的滤镜链）。
                colorFilter: ColorFilter.mode(
                  LfColors.mintText(Theme.of(context).brightness),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
