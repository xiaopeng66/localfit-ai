import 'package:flutter/material.dart';

/// 动效令牌单源（docs/21 §2.9）：全 App 统一时长、曲线与弹簧，
/// 禁止散落魔法数。
abstract final class AppMotion {
  /// 小控件反馈（按压缩放、选中态等微交互）。
  static const Duration fast = Duration(milliseconds: 150);

  /// 常规转场与列表入场（docs/21 §2.9：250ms）。
  static const Duration base = Duration(milliseconds: 250);

  /// 强调型首绘动效（CalorieRing 扫描，docs/21 §2.9：600ms，唯一非交互动效）。
  static const Duration emphasis = Duration(milliseconds: 600);

  /// 统一缓动：进入、出场、入场一律 easeOutCubic（docs/21 §2.9 easeInfo）。
  static const Curve curve = Curves.easeOutCubic;

  /// 列表入场相邻项的错峰间隔。
  static const Duration stagger = Duration(milliseconds: 30);

  /// 列表入场错峰的最大项数（第 7 项起与第 6 项同时入场，避免长列表尾延迟）。
  static const int maxStaggerItems = 6;

  // 弹簧档位（docs/21 §2.9）：需要真实惯性的组件用 SpringSimulation 驱动。
  // springQuick ≈240ms——按压回弹、chip 变形；springStandard ≈380ms（轻微
  // 过冲 ~2%）——卡片入场、选中胶囊位移；springSlow ≈550ms——弹层、页面转场、
  // 形状大变形。

  /// 按压回弹、chip 变形（stiffness 500 / damping 30 / mass 1）。
  static const SpringDescription springQuick = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 30,
  );

  /// 卡片入场、选中胶囊位移（stiffness 380 / damping 26，轻微过冲）。
  static const SpringDescription springStandard = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 26,
  );

  /// 弹层、页面转场、形状大变形（stiffness 260 / damping 24）。
  static const SpringDescription springSlow = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 24,
  );

  /// 隐式动画（AnimatedContainer 等）配套弹簧档的等效时长。
  static const Duration springQuickDuration = Duration(milliseconds: 240);
  static const Duration springStandardDuration = Duration(milliseconds: 380);
  static const Duration springSlowDuration = Duration(milliseconds: 550);

  /// 数字 count-up（docs/21 §3）：环心热量、宏量胶囊数值的数据刷新滚动。
  /// 首帧直显终值（不与首绘入场叠加），只在数值变化时滚动。
  static const Duration countUp = Duration(milliseconds: 800);
  static const Curve countUpCurve = Curves.easeOutExpo;

  /// 错误抖动（docs/21 §3）：400ms 双周期正弦，峰 ±[shakeAmplitude] dp。
  static const Duration shake = Duration(milliseconds: 400);
  static const double shakeAmplitude = 4;

  /// 三点跳动上浮幅度（docs/21 §3 按钮加载态）。
  static const double dotsLift = 4;

  /// 系统开启「减弱动画」时跳过一切装饰动效（退化为直接显示/纯淡入）。
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
