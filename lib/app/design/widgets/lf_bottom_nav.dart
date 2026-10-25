import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 新底栏（docs/21 §3.6 **重写** / §4.1）：贴底 64dp 直角容器
/// （`border-t` + card 95% + backdrop-blur，grid 5 槽，px-2），
/// **不是旧悬浮胶囊**；旧 mint 滑动指示器取消。
///
/// 中央槽 = 56×56 全圆凸起（A 有效值：`refinement.css:3`
/// `.nav-ai .nav-icon{width:46px;height:46px;border-width:5px;box-sizing:content-box;
/// background:var(--brand);color:#10271D}` → 实心品牌底 + 5dp 卡片色描边 +
/// 深色 sparkles；覆盖 `styles.css:118` 的 52px 渐变版），净上凸 9.5dp
/// （docs/21 §5.8.4 实测；位移量 16 是 CSS margin，不是视觉量）。
///
/// 几何硬约束（§5.8.4 历史教训）：凸起圆的盒**必须真的覆盖上凸带**——
/// 只靠 Transform 上移会被祖先裁剪器削平且点不到；凸起圆画在毛玻璃容器
/// **之外**的兄弟层，blur 矩形不会裁它。
class LfBottomNav extends StatelessWidget {
  const LfBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _labels = ['今日', '饮食', 'AI', '训练', '我的'];
  static const _icons = [
    Icons.home_outlined, // home
    Icons.restaurant_outlined, // utensils
    Icons.auto_awesome, // sparkles（凸起圆内，白色）
    Icons.fitness_center_outlined, // dumbbell
    Icons.person_outline, // user
  ];

  /// 槽位稳定 Key（HTML `nav-*` 迁移锚点，docs/21 §4.1：中间槽 = AI 对话）。
  static const slotKeys = [
    'nav-dashboard',
    'nav-nutrition',
    'nav-ai-workbench',
    'nav-training',
    'nav-settings',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 底部手势带算进**栏体自己**（设计稿给 fixed bottom surface 留的
    // `.pb-safe { padding-bottom: env(safe-area-inset-bottom) }` 就是这个意思）：
    // 毛玻璃要一直铺到屏幕底边。此前是整条栏被 SafeArea 抬上去，结果手势带
    // 里既没有栏体也没有底色，页面内容从栏下裸露出 49dp（阶段 J 真机实测可见）。
    final inset = LfInsets.bottom(context);
    return SizedBox(
      height: LfInsets.navReserve(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / 5;
          final bumpLeft =
              slotWidth * 2 + (slotWidth - LfDimens.navBumpSize) / 2;
          return Stack(
            children: [
              // 贴底直角栏（blur 矩形覆盖 64dp 栏体 + 底部手势带）。
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: LfInsets.navBarHeight(context) + inset,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      key: const Key('lf-bottom-nav'),
                      decoration: BoxDecoration(
                        color: c.card.withValues(alpha: 0.95),
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: LfDimens.spaceSmall,
                          right: LfDimens.spaceSmall,
                          bottom: inset,
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < 5; i++)
                              Expanded(
                                child: i == 2
                                    ? _CenterSlotLabel(
                                        selected: currentIndex == 2,
                                        onTap: () => onTap(2),
                                      )
                                    : _NavSlot(
                                        index: i,
                                        label: _labels[i],
                                        icon: _icons[i],
                                        selected: currentIndex == i,
                                        onTap: onTap,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 凸起圆：画在 blur 容器外的兄弟层，盒顶贴 Stack 顶
              // （= 栏顶 - 净上凸 9.5），盒必须覆盖整个圆。
              Positioned(
                left: bumpLeft,
                top: 0,
                width: LfDimens.navBumpSize,
                height: LfDimens.navBumpSize,
                child: Semantics(
                  button: true,
                  selected: currentIndex == 2,
                  label: 'AI 对话',
                  child: GestureDetector(
                    key: const Key('nav-ai-workbench'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(2),
                    child: Center(
                      child: Container(
                        width: LfDimens.navBumpSize,
                        height: LfDimens.navBumpSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.primary,
                          border: Border.all(color: c.card, width: 5),
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: LfDimens.iconMd,
                          color: c.primaryForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 普通槽位：24→20px 图标 + 10px 标签竖排（gap 2），整槽 64dp 命中区。
class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // A `styles.css:115` `.nav-item[aria-current="page"]{color:var(--brand-strong);
    // font-weight:600}`：选中态是**文字级品牌绿**（亮 #187653 / 暗 #4ED9A6），
    // 不是实心主按钮那种 brand——它是浅底上的文字，用 brand 对比不足。
    final brightness = Theme.of(context).brightness;
    final color = selected ? LfColors.mintText(brightness) : c.mutedForeground;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: Key(LfBottomNav.slotKeys[index]),
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: LfDimens.iconMd, color: color),
            const SizedBox(height: LfDimens.spaceMicro),
            Text(
              label,
              style: LfText.micro.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中央槽的「AI」标签：贴在栏底（凸起圆下方，gap 2）。
/// 标签区也在命区内（设计稿整个槽是一个链接）；凸起圆作为上层兄弟
/// 覆盖圆区，两块命中区互补不重叠。
///
/// A 里中央槽也是 `.nav-item`（`styles.css:117-119`）：`aria-current="page"`
/// 时同样吃 `--brand-strong` + w600，所以它在 AI 页上要和其余四槽一样点亮。
class _CenterSlotLabel extends StatelessWidget {
  const _CenterSlotLabel({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final color = selected
        ? LfColors.mintText(Theme.of(context).brightness)
        : c.mutedForeground;
    return InkWell(
      onTap: onTap,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          // A `styles.css:119` `.nav-ai > span:last-child{margin-top:-4px}`：
          // 中央槽的标签比普通槽再上提 4（5.5 → 1.5）。
          padding: const EdgeInsets.only(bottom: 1.5),
          child: Text(
            'AI',
            style: LfText.micro.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
