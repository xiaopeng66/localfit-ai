/// 食物营养值在屏上的**显示口径**（docs/29 D14）——一处定义，三处消费：
/// 食物卡（`FoodCard`）、食物详情弹层（`FoodDetailSheet`）、以及食物库人工
/// 审核台的上屏预览（`tool/food_seed/review/`）。
///
/// 本文件**不导入 Flutter**：审核台的预览由 `dart run` 离线调用这里的同一批
/// 函数产出（`tool/food_seed/review/export_display_preview.dart`）。审核台的全部
/// 意义是「人看到的就是上屏的」，所以它不许用别处重写一遍规则——两份实现必然
/// 漂移，而漂移之后人审的就是一张并不存在的卡片。`test/utils/` 里有一条断言
/// 钉住这个文件与它的伴生文件都不含 `package:flutter` 导入。
library;

/// 克数显示：整数不拖小数点（与页面既有格式一致）。
String formatMacroGrams(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

/// 每 100g 热量：`null` 与 `0` 都当「没有这一项」，环里写 `—`、环下写
/// `无热量数据`。
///
/// 这一格保持**事实判断**（D14 里唯一没被 `0g` 口径覆盖的一格）：上游把「没填」
/// 写成 0（目录分片读取路径就是 `(row['x'] as num?)?.toDouble() ?? 0`），而随包
/// 种子行里 `kcal` 为 0 的有两百来行——一个真的零能量食物比「没填」罕见
/// 得多，写 `0 kcal` 是替上游编事实。数据事实与出处见 docs/07 数据契约。
double? kcalOrMissing(double? value) {
  final v = value ?? 0;
  return v > 0 ? v : null;
}

/// 一项宏量在屏上的克数（docs/29 D14 的**显式三态**）。
///
/// 旧判据 `nutrientOrMissing` 把 `null` 与 `0` 一起折成「没有」⇒ 缺哪个就少画
/// 哪一格、剩下两格各自撑宽，逐行错位（需求 21 点名的就是这件事）。现在三态
/// 分明：**上游没给**（`null`）与**上游把没填写成 0**（`0`）都上屏写 `0g`，
/// 只有真的有值才写值——三项因此恒占位。
///
/// 2026-10-08（docs/30 §2 D2）后消费点只剩**食物详情弹层**（三行竖排的
/// `MacroDotRows`）：食物列表卡已单行化、不再显示宏量，但「三项恒占位」这条
/// 口径没变——它现在是「三行的 y 坐标恒定、与环心那条对齐才有对象」的前提。
///
/// 「这一项没有」这件事改由「营养不完整」标记（列表卡上的警告图标 / 详情里
/// 那句话）承担（两者并存、互不替代）；`0g` 是**显示约定，不作为计算依据**
/// ——需要判断「有没有」的地方仍读原始值，不要拿这个函数的返回值去算。
double macroGramsOnScreen(double? value) => switch (value) {
  null => 0, // 上游没给这一项
  final v when v <= 0 => 0, // 上游把「没填」写成 0（异常负值同样按 0 上屏）
  final v => v, // 有实测值
};

/// 去空白后为空即 `null`（品牌列与拆分结果都可能是空串）。
String? trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// 一条食物在**卡上**的全部派生字符串。
///
/// 审核台显示「这条在卡上长这样」时读的就是这一份；卡片与详情弹层也调
/// [foodDisplayStrings]，所以预览与屏上不会有第二条实现路径。
class FoodDisplayStrings {
  const FoodDisplayStrings({
    required this.name,
    required this.brand,
    required this.kcalText,
    required this.kcalLabel,
    required this.proteinText,
    required this.carbsText,
    required this.fatText,
  });

  /// 上屏品名（`normalizeFoodName(splitFoodName(raw).name)`）。
  final String name;

  /// 品牌（数据列优先，其次拆分结果）；`null` = 卡上没有品牌 chip。
  final String? brand;

  /// 环心数字；无热量数据时是 `—`。
  final String kcalText;

  /// 环下口径：`kcal/100g`，无热量数据时是 `无热量数据`。
  final String kcalLabel;

  /// 三格宏量（缺值与 0 都写 `0g`，恒占位）。
  final String proteinText;
  final String carbsText;
  final String fatText;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'brand': brand,
    'kcal_text': kcalText,
    'kcal_label': kcalLabel,
    'protein_text': proteinText,
    'carbs_text': carbsText,
    'fat_text': fatText,
  };
}

/// 把一条食物的原始字段投影成上屏字符串（口径见文件头）。
///
/// 调用方必须先自己做名称清洗并把结果作为 [name] 传入——清洗用的
/// `splitFoodName` / `normalizeFoodName` 与本文件同属 `lib/utils/`，
/// 拆分的**依据**（品牌词表）只有一个来源，不在这里再拆一次。
FoodDisplayStrings foodDisplayStrings({
  required String name,
  String? brand,
  double? kcalPer100g,
  double? proteinPer100g,
  double? carbsPer100g,
  double? fatPer100g,
}) {
  final kcal = kcalOrMissing(kcalPer100g);
  return FoodDisplayStrings(
    name: name,
    brand: trimToNull(brand),
    kcalText: kcal == null ? '—' : '${kcal.round()}',
    kcalLabel: kcal == null ? '无热量数据' : 'kcal/100g',
    proteinText: '${formatMacroGrams(macroGramsOnScreen(proteinPer100g))}g',
    carbsText: '${formatMacroGrams(macroGramsOnScreen(carbsPer100g))}g',
    fatText: '${formatMacroGrams(macroGramsOnScreen(fatPer100g))}g',
  );
}
