import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 新设计 token 层（docs/21 §2，逐字取自 `ui设计/pages/*.html` 的
/// `:root` 与 `html.dark` 块）。
///
/// 【唯一 token 来源】docs/22 阶段 I-3 已删除旧的 `AppColors`/`AppDimens`/
/// `AppTextStyles`/`AppSemanticColors`/`AppComponentColors` 五组 token，全部
/// 调用点迁到本文件（字阶在 `lf_text_styles.dart`、尺寸在 `lf_dimens.dart`）。
/// 名字与设计稿的 `--lf-*` 前缀一一对应，方便逐值溯源。
///
/// 三层结构：
///  * [LfColors] —— primitive：亮/暗各一套 ramp 与数据色（静态常量）；
///  * [LfSemanticColors] —— 语义表面 ThemeExtension（docs/21 §2.1.6
///    「组件取色的唯一入口」），经 `context.lf` 读取；
///  * [LfComponentColors] —— 组件专用组合（渐变/阴影/骨架屏），
///    经 `context.lfc` 读取。
abstract final class LfColors {
  // ── 品牌 ramp（mint，docs/21 §2.1.1 / §2.2.1）──────────────────────────
  // 暗色只覆盖 50–400（锚点从 500 提亮到 400）；500–900 两套同值。
  static const TonalRamp mintLight = TonalRamp({
    50: Color(0xFFECFBF5),
    100: Color(0xFFD2F5E6),
    200: Color(0xFFA8EBCF),
    300: Color(0xFF6FDBB0),
    400: Color(0xFF4ED9A6),
    500: Color(0xFF2FBE8F),
    600: Color(0xFF22A877),
    700: Color(0xFF1B8A62),
    800: Color(0xFF166B4D),
    900: Color(0xFF114A36),
  });
  static const TonalRamp mintDark = TonalRamp({
    50: Color(0xFF0F1412),
    100: Color(0xFF1F2823),
    200: Color(0xFF242E28),
    300: Color(0xFF2A3A32),
    400: Color(0xFF4ED9A6),
    500: Color(0xFF2FBE8F),
    600: Color(0xFF22A877),
    700: Color(0xFF1B8A62),
    800: Color(0xFF166B4D),
    900: Color(0xFF114A36),
  });

  // ── 中性 ramp（docs/21 §2.1.2 / §2.2.1）────────────────────────────────
  // 暗色方向相反：50 最深、900 最浅（分层深色 bg/surface/surfaceAlt =
  // neutral 50/100/200）。
  static const TonalRamp neutralLight = TonalRamp({
    50: Color(0xFFF7F9F8),
    100: Color(0xFFEFF3F1),
    200: Color(0xFFDDE5E1),
    300: Color(0xFFB8C6C0),
    400: Color(0xFF8FA09A),
    500: Color(0xFF6B7E78),
    600: Color(0xFF556760),
    700: Color(0xFF3D4A45),
    800: Color(0xFF2A342F),
    900: Color(0xFF1A201D),
  });
  static const TonalRamp neutralDark = TonalRamp({
    50: Color(0xFF0F1412),
    100: Color(0xFF171E1A),
    200: Color(0xFF1F2823),
    300: Color(0xFF2A342F),
    400: Color(0xFF3D4A45),
    500: Color(0xFF556760),
    600: Color(0xFF6B7E78),
    700: Color(0xFF8FA09A),
    800: Color(0xFFB8C6C0),
    900: Color(0xFFDDE5E1),
  });

  /// 按亮度取 ramp。页面代码**不要**直接挑散值——语义层已解析好；
  /// 这个入口仅供渐变/图表 painter 这类需要 ramp 档位的场景。
  static TonalRamp mint(Brightness brightness) =>
      brightness == Brightness.light ? mintLight : mintDark;

  static TonalRamp neutral(Brightness brightness) =>
      brightness == Brightness.light ? neutralLight : neutralDark;

  /// 文字级品牌绿（docs/21 §2.1.6：「文字级一律 600/700，暗色用提亮档」）：
  /// 亮色 mint-700、暗色 mint-400。用于浅底（`mint-100` 档）上的强调文字，
  /// 直接取 `primary` 在浅底上对比不足。
  static Color mintText(Brightness brightness) => brightness == Brightness.light
      ? const Color(0xFF187653)
      : mintDark.tone(400);

  static Color brandSoft(Brightness brightness) =>
      brightness == Brightness.light
      ? const Color(0xFFECFBF5)
      : const Color(0xFF203C30);

  // ── 分类数据色（docs/21 §2.1.3：编码永不改变或调换）────────────────────
  static const proteinLight = Color(0xFFFF8A65);
  static const protein100Light = Color(0xFFFFE5DC);
  static const carbsLight = Color(0xFFFFC94D);
  static const carbs100Light = Color(0xFFFFF4D6);
  static const fatLight = Color(0xFFB39DDB);
  static const fat100Light = Color(0xFFEDE6F7);
  static const waterLight = Color(0xFFA8C4D9);
  static const weightLight = Color(0xFFC9A27E);

  static const proteinDark = Color(0xFFFF9D7E);
  static const protein100Dark = Color(0xFF3A2820);
  static const carbsDark = Color(0xFFFFD56B);
  static const carbs100Dark = Color(0xFF3A3320);
  static const fatDark = Color(0xFFC3B0E5);
  static const fat100Dark = Color(0xFF2A2438);
  static const waterDark = Color(0xFFB4D0E5);
  static const weightDark = Color(0xFFD4B08E);

  // ── 图片占位暖色（docs/21 §2.5，AI 工作页功能卡专用字面量）──────────────
  static const warmPlaceholder = [
    Color(0xFFD4A574),
    Color(0xFFE8C9A0),
    Color(0xFFC4956C),
  ];
}

/// 语义表面层（docs/21 §2.1.6「组件取色的唯一入口」+ §2.1.4 状态色 +
/// §2.1.5 证据分级色 + §2.1.3 数据色）。
@immutable
final class LfSemanticColors extends ThemeExtension<LfSemanticColors> {
  const LfSemanticColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.primary,
    required this.primaryForeground,
    required this.success,
    required this.successForeground,
    required this.warning,
    required this.warningForeground,
    required this.warningText,
    required this.error,
    required this.errorForeground,
    required this.errorText,
    required this.info,
    required this.infoForeground,
    required this.evidenceA,
    required this.evidenceB,
    required this.evidenceC,
    required this.protein,
    required this.protein100,
    required this.carbs,
    required this.carbs100,
    required this.fat,
    required this.fat100,
    required this.water,
    required this.weight,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;
  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color input;
  final Color ring;
  final Color primary;
  final Color primaryForeground;
  final Color success;
  final Color successForeground;
  final Color warning;
  final Color warningForeground;

  /// 「warning 当作**文字/图标**」时的颜色（2026-10-20 RV-P1-13）。
  ///
  /// `warning` 是填充色（#FF9800 对白底只有 2.16:1），直接当正文会不可读；
  /// 这个 token 是它的深色文字档（亮色 ≥4.5:1）。
  final Color warningText;

  final Color error;
  final Color errorForeground;

  /// 「error 当作**正文**」时的颜色（同上；`error` 作填充仍用原值）。
  final Color errorText;
  final Color info;
  final Color infoForeground;
  final Color evidenceA;
  final Color evidenceB;
  final Color evidenceC;
  final Color protein;
  final Color protein100;
  final Color carbs;
  final Color carbs100;
  final Color fat;
  final Color fat100;
  final Color water;
  final Color weight;

  static const light = LfSemanticColors(
    background: Color(0xFFF7F9F8),
    foreground: Color(0xFF1A201D),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF1A201D),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF1A201D),
    muted: Color(0xFFEFF3F1),
    mutedForeground: Color(0xFF5C7067),
    border: Color(0xFFDDE5E1),
    input: Color(0xFFDDE5E1),
    ring: Color(0xFF2FBE8F),
    primary: Color(0xFF2FBE8F),
    primaryForeground: Color(0xFF10271D),
    success: Color(0xFF2FBE8F),
    successForeground: Color(0xFFFFFFFF),
    warning: Color(0xFFFF9800),
    warningForeground: Color(0xFFFFFFFF),
    warningText: Color(0xFF9A5B00),
    error: Color(0xFFF44336),
    errorForeground: Color(0xFFFFFFFF),
    errorText: Color(0xFFB3261E),
    info: Color(0xFF42A5F5),
    infoForeground: Color(0xFFFFFFFF),
    evidenceA: Color(0xFFD2F5E6),
    evidenceB: Color(0xFFFFF4D6),
    evidenceC: Color(0xFFEDE6F7),
    protein: LfColors.proteinLight,
    protein100: LfColors.protein100Light,
    carbs: LfColors.carbsLight,
    carbs100: LfColors.carbs100Light,
    fat: LfColors.fatLight,
    fat100: LfColors.fat100Light,
    water: LfColors.waterLight,
    weight: LfColors.weightLight,
  );

  static const dark = LfSemanticColors(
    background: Color(0xFF0F1412),
    foreground: Color(0xFFDDE5E1),
    card: Color(0xFF171E1A),
    cardForeground: Color(0xFFDDE5E1),
    popover: Color(0xFF1F2823),
    popoverForeground: Color(0xFFDDE5E1),
    muted: Color(0xFF1F2823),
    mutedForeground: Color(0xFF8FA09A),
    border: Color(0xFF2A342F),
    input: Color(0xFF2A342F),
    ring: Color(0xFF4ED9A6),
    primary: Color(0xFF4ED9A6),
    primaryForeground: Color(0xFF10271D),
    success: Color(0xFF4ED9A6),
    successForeground: Color(0xFF0F1412),
    warning: Color(0xFFFFB74D),
    warningForeground: Color(0xFF0F1412),
    warningText: Color(0xFFFFB74D),
    error: Color(0xFFEF5350),
    errorForeground: Color(0xFFFFFFFF),
    errorText: Color(0xFFEF5350),
    info: Color(0xFF64B5F6),
    infoForeground: Color(0xFF0F1412),
    evidenceA: Color(0xFF1F2823),
    evidenceB: Color(0xFF2A2438),
    evidenceC: Color(0xFF242E28),
    protein: LfColors.proteinDark,
    protein100: LfColors.protein100Dark,
    carbs: LfColors.carbsDark,
    carbs100: LfColors.carbs100Dark,
    fat: LfColors.fatDark,
    fat100: LfColors.fat100Dark,
    water: LfColors.waterDark,
    weight: LfColors.weightDark,
  );

  @override
  LfSemanticColors copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? popover,
    Color? popoverForeground,
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? input,
    Color? ring,
    Color? primary,
    Color? primaryForeground,
    Color? success,
    Color? successForeground,
    Color? warning,
    Color? warningForeground,
    Color? warningText,
    Color? error,
    Color? errorForeground,
    Color? errorText,
    Color? info,
    Color? infoForeground,
    Color? evidenceA,
    Color? evidenceB,
    Color? evidenceC,
    Color? protein,
    Color? protein100,
    Color? carbs,
    Color? carbs100,
    Color? fat,
    Color? fat100,
    Color? water,
    Color? weight,
  }) => LfSemanticColors(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    card: card ?? this.card,
    cardForeground: cardForeground ?? this.cardForeground,
    popover: popover ?? this.popover,
    popoverForeground: popoverForeground ?? this.popoverForeground,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    border: border ?? this.border,
    input: input ?? this.input,
    ring: ring ?? this.ring,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    success: success ?? this.success,
    successForeground: successForeground ?? this.successForeground,
    warning: warning ?? this.warning,
    warningForeground: warningForeground ?? this.warningForeground,
    warningText: warningText ?? this.warningText,
    error: error ?? this.error,
    errorForeground: errorForeground ?? this.errorForeground,
    errorText: errorText ?? this.errorText,
    info: info ?? this.info,
    infoForeground: infoForeground ?? this.infoForeground,
    evidenceA: evidenceA ?? this.evidenceA,
    evidenceB: evidenceB ?? this.evidenceB,
    evidenceC: evidenceC ?? this.evidenceC,
    protein: protein ?? this.protein,
    protein100: protein100 ?? this.protein100,
    carbs: carbs ?? this.carbs,
    carbs100: carbs100 ?? this.carbs100,
    fat: fat ?? this.fat,
    fat100: fat100 ?? this.fat100,
    water: water ?? this.water,
    weight: weight ?? this.weight,
  );

  @override
  LfSemanticColors lerp(LfSemanticColors? other, double t) {
    if (other == null) return this;
    if (t == 0) return this;
    if (t == 1) return other;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return LfSemanticColors(
      background: mix(background, other.background),
      foreground: mix(foreground, other.foreground),
      card: mix(card, other.card),
      cardForeground: mix(cardForeground, other.cardForeground),
      popover: mix(popover, other.popover),
      popoverForeground: mix(popoverForeground, other.popoverForeground),
      muted: mix(muted, other.muted),
      mutedForeground: mix(mutedForeground, other.mutedForeground),
      border: mix(border, other.border),
      input: mix(input, other.input),
      ring: mix(ring, other.ring),
      primary: mix(primary, other.primary),
      primaryForeground: mix(primaryForeground, other.primaryForeground),
      success: mix(success, other.success),
      successForeground: mix(successForeground, other.successForeground),
      warning: mix(warning, other.warning),
      warningForeground: mix(warningForeground, other.warningForeground),
      warningText: mix(warningText, other.warningText),
      error: mix(error, other.error),
      errorForeground: mix(errorForeground, other.errorForeground),
      errorText: mix(errorText, other.errorText),
      info: mix(info, other.info),
      infoForeground: mix(infoForeground, other.infoForeground),
      evidenceA: mix(evidenceA, other.evidenceA),
      evidenceB: mix(evidenceB, other.evidenceB),
      evidenceC: mix(evidenceC, other.evidenceC),
      protein: mix(protein, other.protein),
      protein100: mix(protein100, other.protein100),
      carbs: mix(carbs, other.carbs),
      carbs100: mix(carbs100, other.carbs100),
      fat: mix(fat, other.fat),
      fat100: mix(fat100, other.fat100),
      water: mix(water, other.water),
      weight: mix(weight, other.weight),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LfSemanticColors &&
      other.background == background &&
      other.foreground == foreground &&
      other.card == card &&
      other.cardForeground == cardForeground &&
      other.popover == popover &&
      other.popoverForeground == popoverForeground &&
      other.muted == muted &&
      other.mutedForeground == mutedForeground &&
      other.border == border &&
      other.input == input &&
      other.ring == ring &&
      other.primary == primary &&
      other.primaryForeground == primaryForeground &&
      other.success == success &&
      other.successForeground == successForeground &&
      other.warning == warning &&
      other.warningForeground == warningForeground &&
      other.warningText == warningText &&
      other.error == error &&
      other.errorForeground == errorForeground &&
      other.errorText == errorText &&
      other.info == info &&
      other.infoForeground == infoForeground &&
      other.evidenceA == evidenceA &&
      other.evidenceB == evidenceB &&
      other.evidenceC == evidenceC &&
      other.protein == protein &&
      other.protein100 == protein100 &&
      other.carbs == carbs &&
      other.carbs100 == carbs100 &&
      other.fat == fat &&
      other.fat100 == fat100 &&
      other.water == water &&
      other.weight == weight;

  @override
  int get hashCode => Object.hashAll([
    background,
    foreground,
    card,
    cardForeground,
    popover,
    popoverForeground,
    muted,
    mutedForeground,
    border,
    input,
    ring,
    primary,
    primaryForeground,
    success,
    successForeground,
    warning,
    warningForeground,
    warningText,
    error,
    errorForeground,
    errorText,
    info,
    infoForeground,
    evidenceA,
    evidenceB,
    evidenceC,
    protein,
    protein100,
    carbs,
    carbs100,
    fat,
    fat100,
    water,
    weight,
  ]);
}

/// 组件专用组合（docs/21 §2.4 阴影 + §2.5 渐变 + 图表底轨/骨架屏）。
///
/// 渐变与阴影依赖解析后的 primary/background，必须按亮度成组给出，
/// 所以放进 ThemeExtension 而不是静态常量。
@immutable
final class LfComponentColors extends ThemeExtension<LfComponentColors> {
  const LfComponentColors({
    required this.heroGradient,
    required this.heroStops,
    required this.ringTrack,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.snackBarBackground,
    required this.onSnackBar,
    required this.waterIcon,
  });

  /// hero 渐变（docs/21 §2.5：全 App 仅限 5 处引用；[heroStops] 为三停靠位）。
  final List<Color> heroGradient;
  final List<double> heroStops;

  /// 圆环/微型图表的轨道色（= muted）。
  final Color ringTrack;

  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color snackBarBackground;
  final Color onSnackBar;

  /// 饮水卡的图标色（Round7 A `refinement.css:7 .water-icon{color:#54839F}`）。
  ///
  /// 与进度条填充 `--water`（= [LfSemanticColors.water]，亮 #A8C4D9 / 暗
  /// #B4D0E5）**不是同一个值**：A 把图标定成一个不随主题走的字面量，
  /// 深色层叠里也没有覆盖它，所以两个主题同值。
  final Color waterIcon;

  static const light = LfComponentColors(
    heroGradient: [Color(0xFF2FBE8F), Color(0xFFA8EBCF), Color(0xFFECFBF5)],
    heroStops: [0.0, 0.55, 1.0],
    ringTrack: Color(0xFFEFF3F1),
    skeletonBase: Color(0xFFDDE5E1),
    skeletonHighlight: Color(0xFFEFF3F1),
    snackBarBackground: Color(0xFF1A201D),
    onSnackBar: Color(0xFFFFFFFF),
    waterIcon: Color(0xFF54839F),
  );

  static const dark = LfComponentColors(
    heroGradient: [Color(0xFF166B4D), Color(0xFF1B8A62), Color(0xFF0F1412)],
    heroStops: [0.0, 0.5, 1.0],
    ringTrack: Color(0xFF26332C),
    skeletonBase: Color(0xFF242E28),
    skeletonHighlight: Color(0xFF2A342F),
    snackBarBackground: Color(0xFF171E1A),
    onSnackBar: Color(0xFFDDE5E1),
    waterIcon: Color(0xFF54839F),
  );

  @override
  LfComponentColors copyWith({
    List<Color>? heroGradient,
    List<double>? heroStops,
    Color? ringTrack,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? snackBarBackground,
    Color? onSnackBar,
    Color? waterIcon,
  }) => LfComponentColors(
    heroGradient: heroGradient ?? this.heroGradient,
    heroStops: heroStops ?? this.heroStops,
    ringTrack: ringTrack ?? this.ringTrack,
    skeletonBase: skeletonBase ?? this.skeletonBase,
    skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    snackBarBackground: snackBarBackground ?? this.snackBarBackground,
    onSnackBar: onSnackBar ?? this.onSnackBar,
    waterIcon: waterIcon ?? this.waterIcon,
  );

  @override
  LfComponentColors lerp(LfComponentColors? other, double t) {
    if (other == null) return this;
    if (t == 0) return this;
    if (t == 1) return other;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return LfComponentColors(
      heroGradient: [
        for (var i = 0; i < heroGradient.length; i++)
          mix(heroGradient[i], other.heroGradient[i]),
      ],
      heroStops: [
        for (var i = 0; i < heroStops.length; i++)
          heroStops[i] + (other.heroStops[i] - heroStops[i]) * t,
      ],
      ringTrack: mix(ringTrack, other.ringTrack),
      skeletonBase: mix(skeletonBase, other.skeletonBase),
      skeletonHighlight: mix(skeletonHighlight, other.skeletonHighlight),
      snackBarBackground: mix(snackBarBackground, other.snackBarBackground),
      onSnackBar: mix(onSnackBar, other.onSnackBar),
      waterIcon: mix(waterIcon, other.waterIcon),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LfComponentColors &&
      listEquals(other.heroGradient, heroGradient) &&
      listEquals(other.heroStops, heroStops) &&
      other.ringTrack == ringTrack &&
      other.skeletonBase == skeletonBase &&
      other.skeletonHighlight == skeletonHighlight &&
      other.snackBarBackground == snackBarBackground &&
      other.onSnackBar == onSnackBar &&
      other.waterIcon == waterIcon;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(heroGradient),
    Object.hashAll(heroStops),
    ringTrack,
    skeletonBase,
    skeletonHighlight,
    snackBarBackground,
    onSnackBar,
    waterIcon,
  );
}

/// 阴影公式（docs/21 §2.4）。数值逐字取自设计稿；静态表面 alpha 上限 0.05。
abstract final class LfShadows {
  /// `--lf-shadow-1` 静态表面默认阴影（设计稿全稿 38 次）。
  /// 暗色下改为 1px 白色描边（docs/21 §2.2.2）——`spreadRadius` 必须给 1：
  /// 设计稿那条是 `0 0 0 1px rgba(255,255,255,.04)`，blur 与 offset 都是 0，
  /// 少了 spread 就等于零面积阴影（画出来什么都没有）。
  static List<BoxShadow> surface(bool isLight) => isLight
      ? const [
          BoxShadow(
            offset: Offset(0, 1),
            blurRadius: 3,
            color: Color(0x0A0F241C), // rgba(15,36,28,.04)
          ),
          BoxShadow(
            offset: Offset(0, 1),
            blurRadius: 2,
            color: Color(0x080F241C), // rgba(15,36,28,.03)
          ),
        ]
      : const [
          BoxShadow(
            spreadRadius: 1,
            color: Color(0x0AFFFFFF), // rgba(255,255,255,.04)
          ),
        ];

  /// `--lf-shadow-float`：仅浮层（modal/popover/dropdown/drawer/overlay）。
  static List<BoxShadow> float(bool isLight) => isLight
      ? const [
          BoxShadow(
            offset: Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -8,
            color: Color(0x0A0F241C),
          ),
        ]
      : const [
          BoxShadow(
            offset: Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -8,
            color: Color(0x0A000000),
          ),
        ];

  /// `--lf-shadow-float-lg`：大浮层。
  static List<BoxShadow> floatLg(bool isLight) => isLight
      ? const [
          BoxShadow(
            offset: Offset(0, 24),
            blurRadius: 60,
            spreadRadius: -20,
            color: Color(0x0D0F241C), // rgba(15,36,28,.05)
          ),
        ]
      : const [
          BoxShadow(
            offset: Offset(0, 24),
            blurRadius: 60,
            spreadRadius: -20,
            color: Color(0x0D000000),
          ),
        ];

  // ── 彩色阴影白名单（docs/21 §2.4：仅主操作元素，N ∈ {25,30,35,40}）──────

  /// 底栏凸起圆：`0 0 0 2px var(--lf-background), 0 4px 12px rgba(47,190,143,.3)`。
  static List<BoxShadow> navBump(Color background) => [
    BoxShadow(color: background, spreadRadius: 2),
    const BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 12,
      color: Color(0x4D2FBE8F), // rgba(47,190,143,.3)
    ),
  ];

  /// 进行中训练横幅：primary 25%。
  static List<BoxShadow> activeBanner(Color primary) => [
    BoxShadow(
      offset: const Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -8,
      color: primary.withValues(alpha: 0.25),
    ),
  ];

  /// AI 主按钮 `cta-write-plan`：primary 35%（有负 spread，与 FAB 那条不同）。
  static List<BoxShadow> aiPrimaryCta(Color primary) => [
    BoxShadow(
      offset: const Offset(0, 4),
      blurRadius: 16,
      spreadRadius: -4,
      color: primary.withValues(alpha: 0.35),
    ),
  ];

  /// 拍照页确认按钮 `cta-confirm-scan`：primary 40%（20px/−4px，勿与上一条混）。
  static List<BoxShadow> scanConfirmCta(Color primary) => [
    BoxShadow(
      offset: const Offset(0, 4),
      blurRadius: 20,
      spreadRadius: -4,
      color: primary.withValues(alpha: 0.40),
    ),
  ];

  /// 训练页 FAB `cta-new-plan`：primary 40%（**无负 spread**）。
  static List<BoxShadow> fabPrimary(Color primary) => [
    BoxShadow(
      offset: const Offset(0, 4),
      blurRadius: 16,
      color: primary.withValues(alpha: 0.40),
    ),
  ];

  /// 饮食·记录页 FAB（docs/29 §P6 需求 13「更浮空、与下边分层」）：
  /// primary 40%、`0 6px 20px`。
  ///
  /// 【为什么不是 docs/29 原文的 38%】设计源 `饮食 · 记录.html:547` 是
  /// `0 4px 12px …30%`，docs/29 §P6 要 blur 12→20、α .30→.38、offset y 4→6；
  /// 而 docs/21 §2.4 的彩色阴影白名单是 **N ∈ {25,30,35,40}** 且明写「不新增
  /// 阴影 token」。38 不在白名单里 ⇒ 取最近档 **40%**（38 与 40 在屏上不可
  /// 分辨，白名单才是硬约束），并把这条偏离记进 `docs/21 §2.4` 与 P6 证据文件。
  /// blur 20 / offset y 6 照 docs/29。
  static List<BoxShadow> recordFab(Color primary) => [
    BoxShadow(
      offset: const Offset(0, 6),
      blurRadius: 20,
      color: primary.withValues(alpha: 0.40),
    ),
  ];

  /// 图片移除按钮 `btn-remove-image`：error 30%。
  static const List<BoxShadow> removeImage = [
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 6,
      color: Color(0x4DF44336), // rgba(244,67,54,.3)
    ),
  ];
}

/// 渐变（docs/21 §2.5：全设计稿 9 条，不得新增第 10 条）。
abstract final class LfGradients {
  /// 凸起圆：mint-500 → mint-600（135°）。
  static LinearGradient navBump(Brightness brightness) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      LfColors.mint(brightness).tone(500),
      LfColors.mint(brightness).tone(600),
    ],
  );

  /// 用户消息气泡 / AI 主按钮：mint-400 → mint-500（135°）。
  static LinearGradient userBubble(Brightness brightness) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      LfColors.mint(brightness).tone(400),
      LfColors.mint(brightness).tone(500),
    ],
  );

  /// 进行中训练横幅：primary → mint-600（135°）。
  static LinearGradient activeBanner(Color primary, Brightness brightness) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, LfColors.mint(brightness).tone(600)],
      );

  /// 图片占位（暖）：AI 工作页功能卡专用。
  static const LinearGradient warmPlaceholder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: LfColors.warmPlaceholder,
  );

  /// 图片占位（蛋白色系）：`protein-100` 打底 + carbs 20% 叠加（菜单页用）。
  static LinearGradient proteinPlaceholder(LfSemanticColors c) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.protein100, c.carbs.withValues(alpha: 0.2)],
      );

  /// 图片占位（mint 色系）。
  static LinearGradient mintPlaceholder(Brightness brightness) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          LfColors.mint(brightness).tone(100),
          LfColors.mint(brightness).tone(200).withValues(alpha: 0.2),
        ],
      );

  /// 图片占位（脂肪色系）。
  static LinearGradient fatPlaceholder(LfSemanticColors c) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [c.fat100, c.fat.withValues(alpha: 0.2)],
  );
}

/// 语义/组件层便捷读取：`context.lf.background`、`context.lfc.heroGradient`。
extension LfTokensX on BuildContext {
  LfSemanticColors get lf =>
      Theme.of(this).extension<LfSemanticColors>() ?? LfSemanticColors.light;

  LfComponentColors get lfc =>
      Theme.of(this).extension<LfComponentColors>() ?? LfComponentColors.light;
}

/// 单色相 tonal ramp（docs/21 §2.1.1）：只定义 50..900 十档，500 为锚点。
/// 结构化取值让「亮暗各一组 tone 映射」成为唯一取色方式，暗色不再单独维护
/// hex 表。传入的 map 必须是 const 字面量（const 构造保证不可变）。
///
/// 阶段 I-3 从旧 `app_colors.dart` 迁入本文件：它是 [LfColors] 的支撑类型，
/// 原定义随旧 token 组一起搬到这里，避免新层反向依赖已删除的文件。
final class TonalRamp {
  const TonalRamp(Map<int, Color> tones) : _tones = tones;

  final Map<int, Color> _tones;

  /// 取指定档位；ramp 不做插值，档位必须落在 50..900 十档之内。
  Color tone(int tone) {
    final color = _tones[tone];
    if (color == null) {
      throw ArgumentError.value(tone, 'tone', 'ramp 只定义 50..900 十档');
    }
    return color;
  }

  /// 按档位升序（50→900）返回全部值。
  List<Color> get values {
    final tones = _tones.keys.toList()..sort();
    return [for (final tone in tones) _tones[tone]!];
  }
}
