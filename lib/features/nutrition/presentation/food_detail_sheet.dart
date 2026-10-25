import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/utils/food_name.dart';
import 'package:localfit_ai/utils/text_utils.dart';

/// 食物详情弹层（docs/28 §5.2，N9 / N10；docs/29 §P8a 需求 28）。
///
/// 用户 2026-10-04 原话：「这里边不需要有份量（输入弹窗也不需要填写份量），
/// 营养修订也不需要，来源证据也不需要」+「这里需要的是食物名称，以及营养的
/// 图表，要可视化的图形风格界面」。于是那一版把弹层从「五段文字」改成
/// **一张图 + 三行**：
///
/// ```
/// 食物详情（弹层标题）
/// 【hero】52 R16 `--bg` 图标块 + 食物名（20px）+ 品牌 + 自建/内置徽标
/// 【营养面板】小环（每 100g 热量，满刻度 0–1000 kcal/100g）+ 三行克数
/// 「营养不完整，暂不可加入确认计划」（仅不可加入时）
/// 行动：编辑 · 删除（仅自建条目）
/// ```
///
/// **2026-10-21（ADR-036）**：meta 行不再写分类——种类是**列表的筛选维度**
/// （搜索行下面的 `food-library-category-row`），详情只讲这条食物自己的字段
/// （名称 / 品牌 / 热量 / 三宏量 / 自建·内置）。
///
/// 2026-10-14（Round7 阶段 3 · 3-2d，D46–D50）：hero（52 R16 `--bg` 图标块 /
/// 20px 标题 / 12px muted meta）、营养面板（r16 + 1px `--border` + `--bg` +
/// 内衬 18 + 环列 56 + 间距 24）、口径注居中、行动行（1px `--track` 上边线 +
/// 两钮 46 + 图标）按 A `app.js:369` 收口——上一版的「标题 + 品牌行 + 环与
/// 三格同行」形态退场（三格改三行是 2026-10-08 的事，本轮把它放进 A 的面板）。
///
/// 2026-10-05 用户走查又点了这一屏（需求 28）：「详情抽屉与卡片一致；圆环小
/// 一点（三个营养同行）；单位注意；只要克数不要百分比；0g 也要写」。本轮三处
/// 调整都是为了让这一屏与**卡片**说同一套话：
///
///  * 环 88/8 → [LfDimens.foodKcalRingLargeSize] 56dp / [LfDimens
///    .foodKcalRingLargeStroke] 6dp，环下标签与卡片统一写 `kcal/100g`；
///  * **供能占比行整行删除**（原 `_macroRatios()`、`MacroRatioRow` 调用与那套
///    「并排 / 竖排」的宽度判据一起删）：同一份数据在一屏上既写百分比又写克数，
///    两套口径迟早互相打架，而用户明确只要克数；
///  * 三格克数行与环**同行**（环列 56 + 16 = 72dp，剩余宽度给三格），缺值与
///    0 都写 `0g`（判据与卡片共用 [macroGramsOnScreen]，一处定义）。
///
/// 三节被删的内容在别处仍有归属：许可证与来源在 我的 → 「数据来源与许可证」
/// （`settings_page.dart`），份量与修订在数据层照旧（`FoodDetailLoader` 与
/// 表都没动，只是不再往这一屏上堆）。
///
/// 图形口径**不编数**：热量缺失时环里写 `—`、环下写 `无热量数据`（[kcalOrMissing]
/// 的「事实判断」档）。三格写 `0g` 是**显示约定**（位置固定、三列不错位），
/// 与热量那一格的口径不同且各自成立；「这一条营养不完整」这件事仍由下面那句
/// 文字承担——两者并存、互不替代。
class FoodDetailSheet extends StatefulWidget {
  const FoodDetailSheet({
    super.key,
    required this.item,
    required this.load,
    this.onEdit,
    this.onDelete,
  });

  /// 列表行（标题与来源标签先渲染，详情随后到）。
  final FoodLibraryItem item;

  /// 详情装载（失败时抛错，弹层显示失败态而不是空数据）。
  final Future<FoodDetail?> Function() load;

  /// 编辑（null = 不渲染按钮）。只有自建条目才该给这两个入口（D1）。
  final Future<void> Function()? onEdit;

  /// 删除（null = 不渲染按钮）。
  final Future<void> Function()? onDelete;

  @override
  State<FoodDetailSheet> createState() => _FoodDetailSheetState();

  static Future<void> show(
    BuildContext context, {
    required FoodLibraryItem item,
    required Future<FoodDetail?> Function() load,
    Future<void> Function()? onEdit,
    Future<void> Function()? onDelete,
  }) => AppSheet.showCustom<void>(
    context,
    builder: (_) => FoodDetailSheet(
      item: item,
      load: load,
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
}

/// 详情抽屉的状态壳（docs/32 §4 T5 / 需求 67）。
///
/// **为什么必须是 StatefulWidget**：`FutureBuilder(future: load())` 写在
/// `build` 里时，把手拖动的起止会 `setState` 切换 `WidgetState.dragged`
/// （Flutter `material/bottom_sheet.dart:269-273,297-299`）⇒ 重建整棵子树
/// ⇒ **重新执行 `load()`** ⇒ 命中 waiting 分支的进度圈 ⇒ 高度跳变 + 闪加载。
/// 实测（本包测试）：拖两次把手，loader 调用数 1 → 5。
///
/// 修法：future 在 `initState` 里建一次并持有；只有 `load` 或 `item` 真的换了
/// （`didUpdateWidget`）才重新装载。
class _FoodDetailSheetState extends State<FoodDetailSheet> {
  late Future<FoodDetail?> _detail;

  @override
  void initState() {
    super.initState();
    _detail = widget.load();
  }

  @override
  void didUpdateWidget(covariant FoodDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.load, widget.load) ||
        oldWidget.item.id != widget.item.id) {
      _detail = widget.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final split = splitFoodName(item.name);
    final name = normalizeFoodName(split.name);
    final brand = _brand(item.brand) ?? _brand(split.brand);
    // 分类判据与列表行**同一处**（`food_library_view.dart` 的行也是这么取的）：
    // hero 图标必须与刚才点进来的那一行是同一枚，否则「点 A 看到 B」。
    final category = FoodCategory.classify(
      name: item.name,
      rawCategory: item.category,
    );
    return Column(
      key: const Key('food-detail-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 弹层标题（D50）：A `openSheet('食物详情', …)` 的第一参。
        Text('食物详情', style: LfText.headline),
        const SizedBox(height: LfDimens.spaceMedium),
        // hero（D46）：A `.food-detail-hero`——52 R16 `--bg` 图标块 + 20px 标题
        // + 12px muted meta；padding `2 0 4` 是 A 的实测值。
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
          child: Row(
            key: const Key('food-detail-hero'),
            children: [
              FoodCategoryIcon(
                foodId: item.id,
                category: category,
                size: 52,
                // A `.food-detail-icon img{40×40}` ⇒ (52−40)/2 = 6。
                padding: const EdgeInsets.all(LfDimens.spaceTiny),
                background: context.lf.background,
                radius: LfDimens.radiusLg,
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A `.food-detail-title` 20px w650；仓内字阶只到 600
                    // （与 D37/胶囊同一映射口径）。`overflow-wrap:anywhere`
                    // 在 Flutter 里就是默认折行，不额外设置。
                    Text(name, style: LfText.headline.copyWith(fontSize: 20)),
                    // A `margin-top:7px` 的实测值。
                    const SizedBox(height: 7),
                    _detailMeta(
                      brand: brand,
                      isUserCreated: item.isUserCreated,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        Flexible(
          child: SingleChildScrollView(
            child: FutureBuilder<FoodDetail?>(
              future: _detail,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    key: Key('food-detail-loading'),
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    key: Key('food-detail-error'),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: AppErrorText('食物详情加载失败，请重试。'),
                  );
                }
                final detail = snapshot.data;
                if (detail == null) {
                  // 分片被移除、条目被删：如实说找不到，不显示半张卡片。
                  return const Padding(
                    key: Key('food-detail-missing'),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: AppErrorText('这条食物已不在本地数据里。'),
                  );
                }
                return _FoodDetailContent(detail: detail);
              },
            ),
          ),
        ),
        // 行动行固定在弹层底部（内容滚走也不动，docs/21 §3.1 大弹层的写法）。
        // 按钮用设计系统的 B6/B7（`LfTextButton`/`LfDangerButton`）——B7 的
        // 约定就是「破坏性操作一律文字型 + 二次确认」，确认浮层在调用点。
        //
        // 两件行动都**先关掉本层再交给调用点**：编辑/删除都会改掉弹层正在
        // 显示的这份数据（名称、品牌、营养），留在原地就是给用户看旧值。
        // 这里的 context 属于弹层自己的路由（弹层走根导航器），pop 关的是
        // 弹层本身，不会误关底下的页面。
        if (item.isUserCreated &&
            (widget.onEdit != null || widget.onDelete != null)) ...[
          const SizedBox(height: LfDimens.spaceLarge),
          // 行动行（D49）：A `.food-detail-actions`——上边 1px `--track`、
          // padding `12 0 2`、两钮 flex:1 min-height 46 + 图标。
          //
          // **按钮仍是 B6/B7 文字型**（2026-10-03 裁决：破坏性操作一律文字钮
          // + 二次确认）；A 画的是描边型（outline-brand / danger 描边），
          // 登记为偏离，与空态 B6 同一口径。
          Container(
            key: const Key('food-detail-actions'),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.lfc.ringTrack)),
            ),
            child: Row(
              children: [
                if (widget.onEdit case final edit?)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 46),
                      child: LfTextButton(
                        key: const Key('food-detail-edit'),
                        label: '编辑',
                        icon: Icons.edit_outlined,
                        // A 的 46 是**连热区一起的盒高**（`min-height:46px`）：
                        // Material 默认 `padded` 会把布局盒撑到 48（3-2a 给
                        // `LfFilterChip` 记过的同一件事）。
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () {
                          Navigator.of(context).pop();
                          unawaited(edit());
                        },
                      ),
                    ),
                  ),
                if (widget.onEdit != null && widget.onDelete != null)
                  const SizedBox(width: 10),
                if (widget.onDelete case final remove?)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 46),
                      child: LfDangerButton(
                        key: const Key('food-detail-delete'),
                        label: '删除',
                        icon: Icons.delete_outline,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () {
                          Navigator.of(context).pop();
                          unawaited(remove());
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: LfDimens.spaceSmall),
      ],
    );
  }

  static String? _brand(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// meta 行（D46）：A `.food-detail-meta`——`flex-wrap` + gap 6 + 12px `--muted`，
  /// 品牌 + 来源 pill。
  ///
  /// **2026-10-21（ADR-036，用户「种类在顶部进行筛选」）把分类移出这一行**：
  /// 详情弹层只讲这条食物**自己**的字段（名称 / 品牌 / 热量 / 三宏量 / 自建·
  /// 内置），分类是**列表的筛选维度**——它由搜索行下面的
  /// `food-library-category-row` 承担，同一个值在一屏上说两遍只会互相打架
  /// （同一行点进来时它必然等于筛选项本身）。分类的**图形**仍在 hero 的
  /// 图标块上（`FoodCategoryIcon`，与刚才点进来的那一行同一枚），图标是识别
  /// 线索，不是第二处文字断言。
  ///
  /// 品牌那格是裸品牌名的独立 `Text`（键 `food-detail-brand`）：两处既有判据
  /// 按**精确值**断言「品牌从哪一列来」（名称清洗 / 数据层品牌优先）。
  ///
  /// 徽标留用共享件（`LfBadge` 11px 档）：A 详情档的 `.pill`（10px 2/8）是
  /// `.pill` 的特例，不为 1px 分叉。
  Widget _detailMeta({required String? brand, required bool isUserCreated}) {
    final style = LfText.caption.copyWith(color: context.lf.mutedForeground);
    final brandName = brand;
    return Wrap(
      key: const Key('food-detail-meta'),
      spacing: LfDimens.spaceTiny,
      runSpacing: LfDimens.spaceTiny,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (brandName != null)
          Text(
            brandName,
            key: const Key('food-detail-brand'),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        // D2：与卡片同一句话（自建 / 内置），详情里不再出现「主库/目录」。
        if (isUserCreated)
          const LfBadge.mint('自建')
        else
          const LfBadge.neutral('内置'),
      ],
    );
  }
}

/// 【图形化营养】小环 + **三行**克数（N10；docs/29 需求 28 收小环；
/// docs/30 §2 D2 需求 1「三行数据的所在行需要与圆环的圆心上下对齐」）。
///
/// **2026-10-08 的两处改动**（用户原话：「点击后的卡片才显示详细的三营养数据，
/// 三行数据的所在行需要与圆环的圆心上下对齐」）：
///
/// 1. **三格一行 → 三行竖排**（每行：彩点 6dp + 名称 + 克数）。
/// 2. **环那一列只放环**（56dp）——环下的 `kcal/100g` 口径标签**移出该列**，
///    改到整块下方一行小字（`FoodDensityScaleNote`）。
///
/// 第 2 条是这次对齐能成立的前提，也是上一版对齐失败的原因：旧版环列 =
/// 环 56 + `spaceMicro` 2 + 标签 14 = **72dp**，而 `CrossAxisAlignment.center`
/// 居中的是**整列**（不是环）⇒ 三格文字块的中心落在列中心（环心下方 8dp）。
/// 列里加任何东西，`center` 就会把「那件东西」算进中线，所以口径标签必须出去。
///
/// 对齐后的几何（三行块 = 3 × 17 + 2 × 8 = 67dp > 环 56dp）：行高由三行块决定，
/// 环被下推 (67 − 56) / 2 = 5.5dp，环心落在 28 + 5.5 = **33.5dp**；三行块中心
/// 也是 67 / 2 = **33.5dp**。两者相等 ⇒ 环心与三行块中心同高。
///
/// 克数口径不变：缺值与 0 都写 `0g`（`macroGramsOnScreen`，D14 既定口径）。
class _FoodDetailContent extends StatelessWidget {
  const _FoodDetailContent({required this.detail});

  final FoodDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 主表热量为 0 = 上游没给这项（不是「零卡食物」）：按缺失处理，环里写
    // `—`，不画一个 0% 的假空环。判据与卡片共用 [kcalOrMissing]。
    final kcal = kcalOrMissing(detail.kcalPer100g);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 营养面板（D47）：A `.food-nutrition-panel`——r16 + 1px `--border` 实
        // 描边 + 底 `--bg` + 内衬 18，环列 56 与宏量列间距 24（A 的 grid gap）。
        // **不用 `lfCardDecoration`**：它在浅色下画卡阴影并把描边设成透明，
        // A 的面板是「卡内嵌块」——实描边、无阴影。
        Container(
          key: const Key('food-detail-panel'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
            border: Border.all(color: c.border),
          ),
          child: Row(
            // 环列**只含环**（56dp）⇒ `center` 居中的就是环本身，环心即列中心。
            // 三行块比环高（67 > 56），行高由三行块决定，环被下推 5.5dp ⇒ 环心
            // = 33.5dp = 三行块中心（算式见类文档）。
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LfFoodKcalRing(
                kcalPer100g: kcal,
                keyPrefix: 'food-detail-ring',
                size: LfDimens.foodKcalRingLargeSize,
                stroke: LfDimens.foodKcalRingLargeStroke,
              ),
              // A `.food-nutrition-panel{gap:24px}`。
              const SizedBox(width: 24),
              Expanded(
                child: MacroDotRows(
                  protein: macroGramsOnScreen(detail.proteinPer100g),
                  carbs: macroGramsOnScreen(detail.carbsPer100g),
                  fat: macroGramsOnScreen(detail.fatPer100g),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        // 环的口径（原先挂在环下方、把环列撑到 72dp 的那一行）。它讲的是**环**
        // 这件事，与三行营养无关，所以放在整块下面单独一行。
        //
        // 两档二选一，与旧版环下标签同一口径：有热量时讲**满刻度**（文案与列表
        // 头的 `FoodDensityScaleNote` 同源，改刻度时两处一起变，不再逐卡重复）；
        // 没有热量时如实写「无热量数据」——环里那个 `—` 需要一句话解释它为什么
        // 是空的，这时讲 0–1000 刻度没有意义（[kcalOrMissing] 的事实判断档）。
        // 口径行横跨整宽、文字居中（D48：A `.food-density-note{text-align:center}`）
        // ——`SizedBox(width: double.infinity)` 是必须的：不给满宽时 `Text` 会
        // 收缩到内容宽，多行时第二行按第一行居中而不是按整块，居中位置随文案
        // 长度漂移。`textAlign` 走共享件的可选参数（列表头继续左对齐）。
        if (kcal == null)
          SizedBox(
            width: double.infinity,
            child: Text(
              '无热量数据',
              key: const Key('food-detail-ring-label'),
              style: LfText.micro.copyWith(color: c.mutedForeground),
              textAlign: TextAlign.center,
            ),
          )
        else
          const SizedBox(
            width: double.infinity,
            child: FoodDensityScaleNote(
              key: Key('food-detail-ring-label'),
              textAlign: TextAlign.center,
            ),
          ),
        if (!detail.canJoinPlan) ...[
          const SizedBox(height: LfDimens.spaceMedium),
          // docs/07 §9.3：能搜到不等于能进计划，理由要写在明面上。
          // 三行写 `0g` 是显示约定，「这一条不完整」由这句话说。
          Text(
            '营养不完整，暂不可加入确认计划',
            style: LfText.label.copyWith(color: c.mutedForeground),
          ),
        ],
      ],
    );
  }
}
