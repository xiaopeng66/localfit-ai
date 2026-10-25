// 转发导出：食物卡、详情弹层与食物库人工审核台的上屏预览共用 D14 的同一批显示
// 口径函数（`lib/utils/food_display.dart`）。既有的 `food_card.dart` 导入点
// （详情弹层等）照旧取得到它们，不必各自改导入路径。
export 'package:localfit_ai/utils/food_display.dart';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/utils/food_display.dart';
import 'package:localfit_ai/utils/food_name.dart';
import 'package:localfit_ai/utils/text_utils.dart';

/// 食物结果**行**（docs/28 §5.1，docs/29 §P8a，docs/30 §2 D1；Round7 阶段 3
/// 由「卡」改成 A `app.js:195` 的 `.food-row`）：食物库与仓库直连搜索共用。
///
/// 用户 2026-10-03 走查原话：「食物库的界面也很丑，食物卡片的表现形式不直观」；
/// 2026-10-04 第二轮点名「右上角 n kcal 每 100g 的标识太丑了，最好是图形化」
/// (N13)、「修订所有食物名称…品牌在卡片的下边显示」(N11)、「添加标识分开自建和
/// 内置」(D2)；2026-10-05 第三轮又点名「标题与图标中心不同高」(20)、「宏量指标
/// 位置要固定，没有的写 0g」(21)、「右上角热量没有单位」(22)、「自建/内置放右下
/// 角」(24)、「品牌做带边框小标签放左下角」(26)、「卡片底部边距不要太多」(27)。
///
/// **2026-10-08 第四轮（docs/30 §2 D1）把上面那些逐轮加出来的四行全部收回，
/// 行恒为一行三件**——用户原话：「主界面只显示图标，名称和再小一点的热量圆环，
/// 都在一行，水平居中，卡片缩短上下宽度，点击后的卡片才显示详细的三营养数据」：
///
///  * **单行三件**：40dp 分类图标 + 清洗后的产品名 + 能量密度环
///    （`LfDimens.foodKcalRingSmallSize` 36dp，比上轮 44 再小一档），三件
///    `CrossAxisAlignment.center` 共一条水平中线；
///  * 内边距由 `12/12/12/8` 收到 **`0/8`**（A `.food-row{padding:8px 0}`：左右
///    的 12 由列表卡给，见 `FoodListCard.rowInset`）⇒ 行高恒 ≈ 56dp；
///  * **删掉**：环下口径行、宏量三彩点行、品牌 chip + 自建/内置徽标行、
///    「营养不完整」文字行。这些信息全部退到**详情弹层**（点行才有）；
///  * **但「不可加入计划」是功能事实，不能只活在详情里**（`docs/07 §9.3`
///    「能搜到不等于能进计划」）：`canJoinPlan == false` 时在**名称之后**内联
///    一枚 16dp 信息图标 + `Semantics`。它不占独立行、不加行高。
///
/// **2026-10-14（Round7 阶段 3 · D36/D37/D38）行搬进单卡列表**：本件不再自带
/// 卡面（A 的行住在 `.card.food-list` 里，看 `FoodListCard`），段距改 A 的
/// 10 / 6 / 14（`.food-row{gap:10px}`、`.food-main{gap:6px}`、
/// `.food-density{margin-left:4px}`），图标块改 A 的 `.food-symbol`
/// （图形充满 40dp、底 `--bg`），警告图标形状随 A 改成 `info_outline`。
///
/// **两条有意保留的偏离**（登记在阶段 3 的 D38）：
///  * 警告图标仍是 `--warning` 色 + 16dp（A：`--muted` + 14dp）——它承载的是
///    功能事实而不是装饰，用信息色说「这条不能进计划」比 muted 更该被看见；
///  * 名称仍是 14 w600（A：14 w550）——本仓字重表只有 400/500/600/700 四档。
///
/// **「水平居中」的落点 = 三件沿同一条水平中线**，不是「整行内容在卡内水平
/// 居中」：名称长度天然不一，整行居中会让扫一列行时名称起点逐行跳动，可扫
/// 视性受损。图标 → 名称 → 环三段在同一中线上已经是「一行、居中」的视觉。
///
/// 名称清洗仍在**行内**做（[splitFoodName]）：两条数据路径都只传原始 `name`，
/// 谁也不会忘（旧版把清洗放在调用点，`food_library_view` 与 `food_search_tab`
/// 各写一遍，一处漏改就两屏不同）。搜索仍按原始 `name` 匹配——搜「Beretta」
/// 照样找得到，只是行上不再显示前缀。
class FoodCard extends StatelessWidget {
  const FoodCard({
    super.key,
    required this.id,
    required this.name,
    required this.category,
    this.brand,
    this.isUserCreated = false,
    this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.canJoinPlan = true,
    this.onTap,
  });

  /// 食物 id：分类图标的语义 Key 用它（`food-category-icon-<分类>-<id>`）。
  final String id;

  /// **原始**名称（含品牌前缀）。卡内用 `splitFoodName` 拆成「产品名 + 品牌」。
  final String name;
  final FoodCategory category;

  /// 数据层的品牌列（自建食物/目录条目有值，种子条目为空——品牌在 [name] 里）。
  ///
  /// **单行卡不再显示它**（品牌退到详情弹层），但参数保留：调用点两处都还在传，
  /// 而删参数会牵动 `food_library_view`/`food_search_tab` 的构造（与本轮无关的
  /// 改动面）。它现在只用于……什么都不用于卡面，保留待详情侧复用。
  final String? brand;

  /// docs/28 §5.1 D2：`true` → 「自建」、其余 → 「内置」。**单行卡不再显示**
  /// （退到详情弹层），参数保留原因同 [brand]。
  final bool isUserCreated;

  /// null = 该来源没有热量数据（目录条目常见）。
  final double? kcalPer100g;

  /// 三项宏量。**单行卡不再显示**（退到详情弹层），参数保留原因同 [brand]；
  /// 三者的「缺值与 0 都写 `0g`」口径（D14）在详情弹层继续生效。
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;

  /// 不可加入确认计划（营养不完整）时，名称后内联一枚警告图标。
  final bool canJoinPlan;

  /// null = 无可展示详情：卡片不可点（点了没反应比没有入口更糟）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final split = splitFoodName(name);
    final displayName = normalizeFoodName(split.name);
    // `RV4-P2-11`（`docs/56` R8）：卡面直接显示品牌，同名食物才分得清
    // （真实库「米饭」四条：无品牌 / 叮咚 / 松屋 / 千丰香米）。
    // 双轨来源：`brand` 列优先；为空时用 `splitFoodName` 拆出的（种子库里
    // 品牌常写在名称头部，拆完 `name` 里就没它了）。
    final inlineBrand = (brand ?? split.brand)?.trim();
    final showBrand = inlineBrand != null && inlineBrand.isNotEmpty;
    // 环走「事实判断」：`0` 与 `null` 都当没有这一项（理由见 [kcalOrMissing]）。
    final kcal = kcalOrMissing(kcalPer100g);

    // A `.food-row`：行不是卡。上下 8 是行自己的内衬（左右那 12 由列表卡给），
    // 上下 8 + 图标 40 = 行高 56 = 原型实测值（跳转保护依赖它，别加第三件）。
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceSmall),
      child: Row(
        // 需求 20（本轮沿用）：图标 40 / 名称 / 环共心中线（行高由最高的那件定）。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FoodCategoryIcon(
            foodId: id,
            category: category,
            size: LfDimens.foodCardIconSize,
            // A `.food-symbol`（polish 覆盖）：底 `--bg`、图形充满 40dp
            // （styles 里的 brand-soft 底与内衬都被 polish 拿掉了）。
            padding: EdgeInsets.zero,
            background: c.background,
          ),
          const SizedBox(width: LfDimens.spaceSmallPlus),
          // 名称 + （可选）警告图标同属一个 `Expanded`：警告图标要**紧贴名称
          // 之后**而不是贴右边缘（贴右会与环挤在一起，且看不出它修饰的是名称）。
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    key: Key('food-card-name-$id'),
                    style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 内联品牌：同一行、micro 档、不追加行高。名称优先省略，
                // 品牌跟随（`Flexible` 在外层，两者共享剩余宽）。
                if (showBrand)
                  Flexible(
                    child: Text(
                      ' · $inlineBrand',
                      key: Key('food-card-brand-$id'),
                      style: LfText.micro.copyWith(color: c.mutedForeground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (!canJoinPlan) ...[
                  const SizedBox(width: LfDimens.spaceTiny),
                  // docs/07 §9.3：能搜到不等于能进计划，这件事要写在明面上。
                  // 整行文字退场后，图标 + 语义标签是最低成本的保留：它不占
                  // 独立行、不加行高（原型仍是单行）。形状随 A 的 info（14dp
                  // muted），但色与尺寸按功能事实定为 warning/16dp（D38）。
                  Semantics(
                    label: '营养不完整，不可加入计划',
                    child: Icon(
                      Icons.info_outline,
                      key: Key('food-card-incomplete-$id'),
                      size: LfDimens.iconSm,
                      color: c.warningText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(
            // A：行内段距 10（`.food-row{gap:10px}`）+ 环前额外的
            // `.food-density{margin-left:4px}`。
            width: LfDimens.spaceSmallPlus + LfDimens.spaceXSmall,
          ),
          // 图形化热量：环 36dp（上轮 44）。环下的 `kcal/100g` 口径标签退到
          // 列表头的 `FoodDensityScaleNote`（那里已经写全「环 = 每 100g 能量
          // 密度 · 满刻度 1000 kcal/100g」），逐行重复一遍是噪声。
          LfFoodKcalRing(
            kcalPer100g: kcal,
            keyPrefix: 'food-card-ring-$id',
            size: LfDimens.foodKcalRingSmallSize,
            stroke: LfDimens.foodKcalRingSmallStroke,
          ),
        ],
      ),
    );
    // 整行可点（含上下 8 的内衬）。`MaterialType.transparency` 只为给 ink 一个
    // 落点，不画任何底色——卡面在列表那一层（`FoodListCard`）。
    // 读屏侧也要能区分同名（记餐结果行已有这条口径：`添加 米饭（千丰香米）`）。
    // 品牌为空时不额外包一层，语义树与改造前完全一致。
    return Material(
      type: MaterialType.transparency,
      // `container: true` 让这一行的 label 成为自己的节点（读屏读「米饭（千丰香米）」，
      // 而不是把品牌拆成第二个焦点）。
      child: Semantics(
        container: showBrand,
        label: showBrand ? '$displayName（$inlineBrand）' : null,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// 三行竖排的宏量块（每行：彩点 + 名称 + 克数），供食物详情弹层用
/// （docs/30 §2 D2 需求 1「三行数据的所在行需要与圆环的圆心上下对齐」）。
///
/// 与 [MacroDotLine] 的关系：**同一套排布骨架**，但两档的单项取值不同——
/// [MacroDotLine]（卡上/记录弹层的三项一行）保持 docs/28 §5.1 D6 的
/// 「点 6 + 名称 10px + 克数 12px w600」；本件（详情三行）按 Round7 A
/// `.food-macro-stack` 收到「**点 7 + 名称 12px + 克数 14px w600**」。
/// 克数口径完全共用 `macroGramsOnScreen`，不会两处漂。
///
/// **行高 17dp + 行间距 8dp 是 1.0× 口径**，不是随手取的：详情弹层的「三行块
/// 中心 = 环心」这条对齐（见 `food_detail_sheet.dart` 的 `_FoodDetailContent`）
/// 在 1.0× 下按 块高 = 3 × 17 + 2 × 8 = 67dp 算。Round7 阶段 3 · 3-2d（D47）
/// 起，17dp 不再是「caption 向上取整」而是 **A 写死的行高单源**
/// （`.food-macro-stack > div{line-height:17px}`，值 14px 的高度因子取
/// `17/14`）——名称与克数怎么长，行高都不动，对齐算式因此与 A 逐字相同。
///
/// 行高用 `minHeight` 而不是定高 `SizedBox(height:)`：定高在 2.0× 字号下会把
/// 文字拦腰截断（12px → 24px，行高 33.6dp 塞进 17dp 只能裁掉），而
/// `CrossAxisAlignment.center` 的对齐是按**实际高度**算的 —— 块变高，环跟着
/// 下推，环心仍在块中心，不靠固定高度维持对齐。
///
/// 行高用 `minHeight` 而不是定高 `SizedBox(height:)`：定高在 2.0× 字号下会把
/// 文字拦腰截断（12px → 24px，行高 33.6dp 塞进 17dp 只能裁掉），而
/// `CrossAxisAlignment.center` 的对齐是按**实际高度**算的 —— 块变高，环跟着
/// 下推，环心仍在块中心，不靠固定高度维持对齐。
class MacroDotRows extends StatelessWidget {
  const MacroDotRows({this.protein, this.carbs, this.fat, super.key});

  final double? protein;
  final double? carbs;
  final double? fat;

  /// 1.0× 下的单行行高。对齐算式的三个因子之一，改前先读类文档。
  static const double rowHeight = 17;

  /// 行间距（`spaceSmall`，与字号无关，任何字号下都不变）。
  static const double rowGap = LfDimens.spaceSmall;

  /// 1.0× 下的三行块总高（三行 + 两个间距）。测试钉它，弹层对齐断言也读它。
  static const double blockHeight = rowHeight * 3 + rowGap * 2;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 顺序恒为 蛋白质 → 碳水 → 脂肪（与 [MacroDotLine] 同）。缺项不出现在
    // 这里：弹层调用点已用 `macroGramsOnScreen` 把缺值与 0 都写成 0g，三项恒在。
    final entries = <(Color, String, double)>[
      if (protein case final value?) (c.protein, '蛋白质', value),
      if (carbs case final value?) (c.carbs, '碳水', value),
      if (fat case final value?) (c.fat, '脂肪', value),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: rowGap),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: rowHeight),
            child: _MacroDotItem(entry: entries[i], expanded: true),
          ),
        ],
      ],
    );
  }
}

/// 三个宏量彩点行（与记录页餐卡/菜品卡同色）。缺项由调用点决定怎么摆——
/// 食物卡恒传三格（缺值 `0g`），记录一餐弹层与菜品卡仍只传有的那几项。
///
/// 食物卡与「记录一餐」弹层的已添加项共用它：一处定义，两处读到的彩点、
/// 文案与克数格式完全一致（否则同一份营养在两张屏上的写法会漂）。
///
/// 形态按 docs/28 §5.1 D6 定死：**独立成行、三项等宽**（`Row` + `Expanded`），
/// 每项 = 圆点(6dp) + 名称(10px muted) + 克数(12px w600 前景色)，顺序恒为
/// 蛋白质 → 碳水 → 脂肪。旧版是 `Wrap`：彩点行挤在名称列里、每项按内容伸缩，
/// 名称被压成一行省略，扫一列卡片时三列也对不齐。
///
/// 2.0× 字号：每项 `maxLines: 1` + `FittedBox.scaleDown` 兜底——把
/// 「蛋白质 12.3g」折成两行会让三列基线错位，宁可等比缩小。
class MacroDotLine extends StatelessWidget {
  const MacroDotLine({this.protein, this.carbs, this.fat, super.key});

  final double? protein;
  final double? carbs;
  final double? fat;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final entries = <(Color, String, double)>[
      if (protein case final value?) (c.protein, '蛋白质', value),
      if (carbs case final value?) (c.carbs, '碳水', value),
      if (fat case final value?) (c.fat, '脂肪', value),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: LfDimens.spaceSmall),
          Expanded(child: _MacroDotItem(entry: entries[i])),
        ],
      ],
    );
  }
}

/// 单项宏量：圆点 + 名称 + 克数，放不下时整项等比缩小（不折行）。
///
/// [expanded] = true 时名称那一格 `Expanded` 撑开、克数贴右边缘（三行竖排的
/// 形态：三行的克数右端对齐成一列，便于竖向比大小）；false 时整项按内容收
/// （一行并排的形态，三项等宽由外层 `Row` 的 `Expanded` 决定）。
///
/// **两档取值各有出处**（Round7 阶段 3 · 3-2d，D47）：
///  * expanded（详情三行）= A `.food-macro-stack`：点 **7**、点距 **8**、
///    名称 **12**（caption）、克数 **14 w600**（A w650 → 仓内 600）、
///    高度因子 `17/14`（A `line-height:17px` 的行高单源）；
///  * false（卡上三格 / 记录一餐弹层）= docs/28 §5.1 D6 的 点 6 / 距 4 /
///    名称 10（micro）/ 克数 12（caption w600）——**一字不动**。
class _MacroDotItem extends StatelessWidget {
  const _MacroDotItem({required this.entry, this.expanded = false});

  final (Color, String, double) entry;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final (color, label, grams) = entry;
    final dotSize = expanded ? 7.0 : 6.0;
    final dotGap = expanded ? LfDimens.spaceSmall : LfDimens.spaceXSmall;
    final labelStyle = expanded
        ? LfText.caption.copyWith(color: c.mutedForeground)
        : LfText.micro.copyWith(color: c.mutedForeground);
    final gramsStyle = expanded
        ? LfText.body.copyWith(
            color: c.cardForeground,
            fontWeight: FontWeight.w600,
            height: 17 / 14,
          )
        : LfText.caption.copyWith(
            color: c.cardForeground,
            fontWeight: FontWeight.w600,
          );
    final row = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: dotGap),
        // 文字自带宏量名（「蛋白质 2.6g」），彩点只是加速比对，
        // 所以不需要再补一层语义标签。
        if (expanded)
          Expanded(
            child: Text(
              label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$label ', style: labelStyle),
                TextSpan(
                  text: '${formatMacroGrams(grams)}g',
                  style: gramsStyle,
                ),
              ],
            ),
            maxLines: 1,
          ),
        if (expanded)
          Text('${formatMacroGrams(grams)}g', style: gramsStyle, maxLines: 1),
      ],
    );
    if (expanded) return row;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: row,
    );
  }
}
