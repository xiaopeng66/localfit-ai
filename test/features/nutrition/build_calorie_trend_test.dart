import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

DailyIntakeRecord record(String localDate, double kcal) => DailyIntakeRecord(
  localDate: localDate,
  kcal: kcal,
  proteinGrams: 0,
  carbsGrams: 0,
  fatGrams: 0,
);

void main() {
  group('窗口与星期标签', () {
    test('窗口以 endDate 收尾，共 7 天且升序', () {
      final bars = buildCalorieTrendBars(
        records: const [],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.dates, [
        '2026-09-17',
        '2026-09-18',
        '2026-09-19',
        '2026-09-20',
        '2026-09-21',
        '2026-09-22',
        '2026-09-23',
      ]);
    });

    test('星期字按真实日期推导，不是设计稿写死的列', () {
      // 2026-09-23 是周三。若实现照抄设计稿的「二 23」这一列，这里会红。
      final bars = buildCalorieTrendBars(
        records: const [],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.weekdayLabels.last, '三');
      expect(bars.weekdayLabels, ['四', '五', '六', '日', '一', '二', '三']);
    });

    test('跨月窗口的日期与星期都正确', () {
      final bars = buildCalorieTrendBars(
        records: const [],
        endDate: DateTime(2026, 10, 2),
      );

      expect(bars.dates.first, '2026-09-26');
      expect(bars.dates.last, '2026-10-02');
      // 2026-10-02 是周五。
      expect(bars.weekdayLabels.last, '五');
    });
  });

  group('有记录 / 无记录的区分', () {
    test('缺记录的日子是 null，不是 0（「没吃」≠「吃了 0 千卡」）', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-23', 1500)],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.kcalByDay.last, 1500);
      expect(bars.kcalByDay.take(6), everyElement(isNull));
      expect(bars.trackedDays, 1);
    });

    test('真的记录了 0 千卡与没记录是两件事', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-23', 0)],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.kcalByDay.last, 0);
      expect(bars.trackedDays, 1, reason: '记了 0 千卡也算有记录');
    });

    test('窗口外的记录不影响柱图', () {
      final bars = buildCalorieTrendBars(
        records: [
          record('2026-09-16', 9999), // 窗口前一天
          record('2026-09-24', 8888), // 窗口后一天
          record('2026-09-20', 1200),
        ],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.trackedDays, 1);
      expect(bars.kcalByDay[3], 1200);
    });
  });

  group('柱高比例与坐标尺度', () {
    test('峰值柱为最高柱，比例上限不超过 1', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-22', 1200), record('2026-09-23', 2000)],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.fractions.last, lessThanOrEqualTo(1.0));
      expect(bars.fractions.last, greaterThan(bars.fractions[5]));
    });

    test('全空窗口不会产生 NaN（分母兜底为 A 的 2200 基数）', () {
      final bars = buildCalorieTrendBars(
        records: const [],
        endDate: DateTime(2026, 9, 23),
      );

      // 2B 步骤 4（D17）起分母口径 = A：max(2200, 目标, 峰值)。全空窗口
      // 因此落在 2200 基数上——空柱子依旧画得下，且没有 NaN。
      expect(bars.scaleMaxKcal, kTrendBaseKcal);
      expect(bars.fractions, everyElement(0));
      expect(bars.fractions.any((value) => value.isNaN), isFalse);
    });

    test('纵轴上界 = max(2200, 目标, 峰值)（D17 起按 A 口径，不留 1.1 余量）', () {
      // 峰值 800 只有基数的一半高 ⇒ 柱子读起来「就是小半碗饭」，而不是
      // 旧口径（800×1.1）那种「柱子顶天、轴印 880」的自相矛盾。
      final low = buildCalorieTrendBars(
        records: [record('2026-09-23', 330)],
        endDate: DateTime(2026, 9, 23),
      );
      expect(low.scaleMaxKcal, kTrendBaseKcal);

      final withTarget = buildCalorieTrendBars(
        records: [record('2026-09-23', 800)],
        endDate: DateTime(2026, 9, 23),
        targetMaxKcal: 2000,
      );
      expect(withTarget.scaleMaxKcal, closeTo(kTrendBaseKcal, 0.001));
      // 目标线必须落在画布内（<1.0），否则虚线会画在框外。
      expect(2000 / withTarget.scaleMaxKcal, lessThan(1.0));

      // 目标高于基数：上界跟到目标本身（3000），不是 3300。
      final aboveBase = buildCalorieTrendBars(
        records: [record('2026-09-23', 800)],
        endDate: DateTime(2026, 9, 23),
        targetMaxKcal: 3000,
      );
      expect(aboveBase.scaleMaxKcal, 3000);

      // 峰值高于基数与目标：上界跟到峰值。
      final peakAbove = buildCalorieTrendBars(
        records: [record('2026-09-23', 2600)],
        endDate: DateTime(2026, 9, 23),
        targetMaxKcal: 2000,
      );
      expect(peakAbove.scaleMaxKcal, 2600);
      expect(peakAbove.fractions.last, closeTo(1.0, 0.0001));
    });
  });

  group('达标天数', () {
    test('无目标时达标天数为 null（不编一个分母）', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-23', 1500)],
        endDate: DateTime(2026, 9, 23),
      );

      expect(bars.hitCount, isNull);
    });

    test('达标 = 未超上限（低于下限也计入），超上限不计', () {
      // 2026-10-23 用户：「今日达标但没变 0/7」——原口径要求落在
      // [min,max]，而区间是中心值 ±5%，摄入在 95% 上限附近时达成率
      // 看起来达标、达标天数却仍是 0。现在按「未超上限」判定。
      final bars = buildCalorieTrendBars(
        records: [
          record('2026-09-19', 1799), // 上限内
          record('2026-09-20', 1800), // 上界，含
          record('2026-09-21', 1400), // 下界，含
          record('2026-09-22', 1399), // 低于下限：未超上限，计入达标
          record('2026-09-23', 1801), // 高于上界：不计
        ],
        endDate: DateTime(2026, 9, 23),
        targetMinKcal: 1400,
        targetMaxKcal: 1800,
      );

      expect(bars.hitCount, 4);
      // 低于下限的日子单独计数（洞察据此提示「可能吃太少」）。
      expect(bars.belowMinCount, 1);
    });

    test('无记录的日子不计入达标天数', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-23', 1500)],
        endDate: DateTime(2026, 9, 23),
        targetMinKcal: 1400,
        targetMaxKcal: 1800,
      );

      expect(bars.hitCount, 1);
      expect(bars.belowMinCount, 0);
    });

    test('低于下限只计 belowMinCount，不改变「未超上限」的达标判定', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-23', 1200)],
        endDate: DateTime(2026, 9, 23),
        targetMinKcal: 1400,
        targetMaxKcal: 1800,
      );

      expect(bars.hitCount, 1);
      expect(bars.belowMinCount, 1);
    });

    test('目标区间退化为 0 宽（min == max）时只认不超过上限', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-22', 1800), record('2026-09-23', 1801)],
        endDate: DateTime(2026, 9, 23),
        targetMinKcal: 1800,
        targetMaxKcal: 1800,
      );

      expect(bars.hitCount, 1);
      expect(bars.belowMinCount, 0);
    });

    test('有 max 无 min 时仍能算达标，belowMinCount 为 null', () {
      final bars = buildCalorieTrendBars(
        records: [record('2026-09-22', 100), record('2026-09-23', 2500)],
        endDate: DateTime(2026, 9, 23),
        targetMaxKcal: 2000,
      );

      expect(bars.hitCount, 1);
      expect(bars.belowMinCount, isNull);
    });
  });
}
