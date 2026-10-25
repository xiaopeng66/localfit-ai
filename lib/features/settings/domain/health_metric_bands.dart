/// 健康数据三张图形卡的**分档口径**（docs/29 §P2 / 裁决 D10）。
///
/// 为什么单独一份：三张卡各自要回答一个「这个数算高还是低」的问题，而
/// 「分档」是**健康口径**（谁算正常、边界在哪），不是画法。画法在
/// `lib/app/design/widgets/lf_metric_gauge.dart`，口径在本文件——
/// 两者分开后，改边界只改一处，且边界可以被单测逐个钉住。
///
/// 三条口径的**来源**（都不许在实现里另发明）：
/// - BMI：中国成人标准 WS/T 428-2013 的四档（<18.5 偏瘦 / 18.5–23.9 正常 /
///   24.0–27.9 超重 / ≥28.0 肥胖）。**本文件是这个分档在本仓库的唯一出处**：
///   `docs/21 §7.1` 只写了 BMI 的派生公式（`w / (h/100)²`），没写过边界；
///   改边界只改这里一处，`docs/21 §5.6` 与 `docs/29 §P2` 只描述形态。
/// - 基础代谢率（BMR）：**不做医学分档**（没有公认的「正常 BMR 区间」，
///   编一个就是伪造语义——D10 的理由栏）。这里只回答「静息消耗相对于
///   你自己的每日目标热量区间在哪一边」，区间取 `Goals.calorieMin/Max`
///   （App 自己在引导页算出来、也在今日页展示过的同一组数）。
/// - 水分：达成度 = 今日已饮 / 目标（0..1，超出 1 由画法侧限幅，
///   但**报告给用户的百分比是真实值**，不截断）。
library;

/// BMI 四档（`docs/21 §7.2` 边界：18.5 / 24.0 / 28.0）。
enum BmiTier {
  thin,
  normal,
  over,
  obese;

  /// 档位文字（图形卡右上角徽标；空态**不给**这个词）。
  String get label => switch (this) {
    BmiTier.thin => '偏瘦',
    BmiTier.normal => '正常',
    BmiTier.over => '超重',
    BmiTier.obese => '肥胖',
  };
}

/// BMI 分档。null（体重或身高缺失）⇒ null：**不猜档**，调用方走诚实空态。
///
/// 边界归属：`18.4 ⇒ 偏瘦，18.5 ⇒ 正常`、`23.9 ⇒ 正常，24.0 ⇒ 超重`、
/// `27.9 ⇒ 超重，28.0 ⇒ 肥胖`（左闭右开，符合「18.5–23.9 为正常」的读法）。
BmiTier? bmiTierOf(double? bmi) {
  if (bmi == null || !bmi.isFinite) return null;
  if (bmi < 18.5) return BmiTier.thin;
  if (bmi < 24.0) return BmiTier.normal;
  if (bmi < 28.0) return BmiTier.over;
  return BmiTier.obese;
}

/// 静息消耗（BMR）相对「每日目标热量区间」的位置。
enum BmrPosition {
  below,
  within,
  above;

  String get label => switch (this) {
    BmrPosition.below => '低于目标区间',
    BmrPosition.within => '落在目标区间内',
    BmrPosition.above => '高于目标区间',
  };
}

/// BMR 位置。三者任一缺失 ⇒ null（无区间就不给位置文字——「无从比较」
/// 不等于「在中间」）。
BmrPosition? bmrPositionOf({
  required int? bmrKcal,
  required double? calorieMinKcal,
  required double? calorieMaxKcal,
}) {
  if (bmrKcal == null || calorieMinKcal == null || calorieMaxKcal == null) {
    return null;
  }
  if (calorieMaxKcal < calorieMinKcal) return null;
  if (bmrKcal < calorieMinKcal) return BmrPosition.below;
  if (bmrKcal > calorieMaxKcal) return BmrPosition.above;
  return BmrPosition.within;
}
