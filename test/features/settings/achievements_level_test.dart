import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_achievement_row.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/domain/achievement_levels.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// 成就分级与进度（docs/29 §P3 / 需求 5）。
///
/// 原来的四格灰瓦片只分「解锁 / 未解锁」两态，说不出「离达标还差多少」，2.0×
/// 字号下名称还会折行。换成的行卡要自证三件事：**等级**（铜/银/金）、
/// **进度**（环 + 条）、**差多少**（`n / 目标`）。这一组测试钉的就是这三件事，
/// 外加三处容易说谎的地方：
///
/// 1. **档位边界**（0.49 / 0.5 / 0.99 / 1.0）与**计数**（`progress × target`
///    向下取整）——尤其「银档把数字显示成 7/7」这种自相矛盾；
/// 2. **等级 / 进度 / 计数三者同源**：环的弧长、条的长度、`n/目标` 里的 n，
///    都只由同一个 `progress`（历史最大值）决定，且目标分母取自
///    `AchievementSpec` 而不是页面里再抄一遍；
/// 3. **信息不许丢**：名称在 2.0× / 320dp 下仍是完整单行（不省略、不折行、
///    不被纵向裁半截），且**解锁态与未解锁态的行等高**（解锁只是把第 2 行的
///    `n/目标` 原位换成「已解锁」，不新增行）。
void main() {
  final now = DateTime.utc(2026, 9, 12, 10);

  void viewport(WidgetTester tester, Size size, {double scale = 1}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget page(AppDatabase database) => MaterialApp(
    theme: AppTheme.light(),
    home: SettingsPage(
      profileOverviewLoader: LoadProfileOverview(
        database: database,
        clock: FixedAppClock(now),
      ),
    ),
  );

  /// 直接往成就表里塞一行。`progress` 是**历史最大值**（`max(存库值, 当前值)`），
  /// 所以塞进去的值只要 ≥ 实时进度（空库 ⇒ 0）就会被原样读出——不必造出真实
  /// 的行为数据，就能把任意档位摆到页面上。
  Future<void> seedAchievement(
    AppDatabase database, {
    required String key,
    required double progress,
    bool unlocked = false,
  }) async {
    await database
        .into(database.achievements)
        .insert(
          AchievementsCompanion.insert(
            id: 'ach-$key',
            key: key,
            progress: Value(progress),
            unlockedAt: Value(unlocked ? now : null),
          ),
        );
  }

  Future<void> pumpAndScroll(
    WidgetTester tester,
    AppDatabase database, {
    int toRow = 4,
  }) async {
    await tester.pumpWidget(page(database));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(Key('settings-achievement-$toRow')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Finder inRow(int index, Finder matching) => find.descendant(
    of: find.byKey(Key('settings-achievement-$index')),
    matching: matching,
  );

  /// 行内某个带 key 的元素（徽标挂在容器上、计数挂在文字上）的文字；
  /// 不存在 ⇒ null（用 `isNot('已解锁')` 这种写法时不会因为「找不到」而假绿）。
  String? textIn(WidgetTester tester, int index, String subKey) {
    final finder = inRow(index, find.byKey(Key(subKey)));
    if (finder.evaluate().isEmpty) return null;
    final widget = tester.widget(finder);
    if (widget is Text) return widget.data;
    return tester
        .widget<Text>(find.descendant(of: finder, matching: find.byType(Text)))
        .data;
  }

  /// 勋章「内盘」的底色（已解锁 = 实心等级色 / 未解锁 = muted）。
  Color? medalPlateColor(WidgetTester tester, int index) {
    final medal = inRow(
      index,
      find.descendant(
        of: find.byKey(const Key('lf-achievement-medal')),
        matching: find.byType(Container),
      ),
    );
    for (final container in tester.widgetList<Container>(medal)) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
        return decoration.color;
      }
    }
    return null;
  }

  /// 勋章环的画法（弧长比例 + 弧色）。
  LfRingPainter medalPainter(WidgetTester tester, int index) {
    final paint = tester.widget<CustomPaint>(
      inRow(
        index,
        find.descendant(
          of: find.byKey(const Key('lf-achievement-medal')),
          matching: find.byType(CustomPaint),
        ),
      ).first,
    );
    return paint.painter! as LfRingPainter;
  }

  double rowHeight(WidgetTester tester, int index) =>
      tester.getRect(find.byKey(Key('settings-achievement-$index'))).height;

  group('档位与计数口径（纯函数，边界逐个钉）', () {
    test('等级：< 0.5 铜、[0.5, 1) 银、1.0 金（边界含等号）', () {
      expect(achievementLevelOf(0), AchievementLevel.bronze);
      expect(achievementLevelOf(0.49), AchievementLevel.bronze);
      // 0.5 就是银：不是「大于 0.5 才升级」。
      expect(achievementLevelOf(0.5), AchievementLevel.silver);
      expect(achievementLevelOf(0.99), AchievementLevel.silver);
      // 只有满进度才给金（金与「已解锁」同义，不能提前给）。
      expect(achievementLevelOf(1.0), AchievementLevel.gold);
      expect(achievementLevelOf(1.5), AchievementLevel.gold);
    });

    test('等级：非有限值与负数按铜兜底（脏数据不谎报解锁）', () {
      expect(achievementLevelOf(double.nan), AchievementLevel.bronze);
      expect(achievementLevelOf(double.infinity), AchievementLevel.bronze);
      expect(
        achievementLevelOf(double.negativeInfinity),
        AchievementLevel.bronze,
      );
      expect(achievementLevelOf(-0.2), AchievementLevel.bronze);
    });

    test('计数：向下取整，且未解锁永不等于目标', () {
      expect(achievementCountOf(progress: 0, target: 7), 0);
      expect(achievementCountOf(progress: 5 / 7, target: 7), 5);
      // 0.99 不许四舍五入成 7：银档配「7/7」是自相矛盾。
      expect(achievementCountOf(progress: 0.99, target: 7), 6);
      expect(achievementCountOf(progress: 0.999999, target: 7), 6);
      // 浮点误差把乘积顶到目标线（1 - 1e-10 乘 7 加 ε 后是 7.0000000003）时
      // 也不许显示 7/7：`target - 1` 那道上限就是为这一步存在的。
      expect(achievementCountOf(progress: 1 - 1e-10, target: 7), 6);
      expect(achievementCountOf(progress: 1 - 1e-12, target: 30), 29);
      expect(achievementCountOf(progress: 1.0, target: 7), 7);
      expect(achievementCountOf(progress: 7 / 30, target: 30), 7);
      expect(achievementCountOf(progress: 0.5, target: 7), 3);
      // 无目标 / 脏数据不给数字（也不编一个「0/0」出来）。
      expect(achievementCountOf(progress: 0.5, target: 0), 0);
      expect(achievementCountOf(progress: 0.5, target: -3), 0);
      expect(achievementCountOf(progress: double.nan, target: 7), 0);
      expect(achievementCountOf(progress: -1, target: 7), 0);
    });

    test('四条成就的目标值：7 / 7 / 10 / 30（key 与页面顺序一致）', () {
      expect(
        [for (final spec in AchievementSpec.values) spec.key],
        ['streak-7', 'nutrition-master', 'workout-athlete', 'healthy-diet'],
      );
      expect(
        [for (final spec in AchievementSpec.values) spec.target],
        [7, 7, 10, 30],
      );
    });

    testWidgets('等级色板：铜 = weight、银 = mutedForeground、金 = carbs（三色都不新造）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const SizedBox()),
      );
      final context = tester.element(find.byType(SizedBox));
      final light = LfSemanticColors.light;
      expect(medalTierStyle(context, LfMedalTier.bronze).accent, light.weight);
      expect(
        medalTierStyle(context, LfMedalTier.silver).accent,
        light.mutedForeground,
      );
      expect(medalTierStyle(context, LfMedalTier.gold).accent, light.carbs);
      expect(
        [
          for (final tier in LfMedalTier.values)
            medalTierStyle(context, tier).label,
        ],
        ['铜', '银', '金'],
      );
    });
  });

  group('成就行卡（页面接线）', () {
    testWidgets('空库：四行都是铜档锁态，目标分母来自 spec（0/7、0/7、0/10、0/30）', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await pumpAndScroll(tester, database);

      expect(
        [for (var i = 1; i <= 4; i++) textIn(tester, i, 'lf-achievement-tier')],
        ['铜', '铜', '铜', '铜'],
        reason: '进度 0 的行只能是铜档',
      );
      expect(
        [
          for (var i = 1; i <= 4; i++)
            textIn(tester, i, 'lf-achievement-count'),
        ],
        ['0/7', '0/7', '0/10', '0/30'],
        reason: '分母是各成就的目标值：页面不许自己认 7/10/30',
      );
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
      expect(find.text('已解锁'), findsNothing, reason: '一行都没解锁，就不该出现「已解锁」');
      expect(tester.takeException(), isNull);
    });

    testWidgets('银档：0.5 起算，计数与同一 progress 同源（3/7、29/30）', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await seedAchievement(database, key: 'nutrition-master', progress: 0.5);
      await seedAchievement(database, key: 'workout-athlete', progress: 0.49);
      await seedAchievement(database, key: 'healthy-diet', progress: 0.99);
      await pumpAndScroll(tester, database);

      expect(textIn(tester, 2, 'lf-achievement-tier'), '银');
      expect(textIn(tester, 2, 'lf-achievement-count'), '3/7');
      // 0.49 仍是铜（0.5 才是银）。
      expect(textIn(tester, 3, 'lf-achievement-tier'), '铜');
      expect(textIn(tester, 3, 'lf-achievement-count'), '4/10');
      // 0.99 是银，数字取整后是 29 —— 绝不能显示成 30/30。
      expect(textIn(tester, 4, 'lf-achievement-tier'), '银');
      expect(textIn(tester, 4, 'lf-achievement-count'), '29/30');
      expect(find.text('30/30'), findsNothing);
      expect(find.text('已解锁'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('解锁行：金档 + 实心金盘 + 原位换「已解锁」，且四行仍等高', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await seedAchievement(
        database,
        key: 'healthy-diet',
        progress: 1.0,
        unlocked: true,
      );
      await pumpAndScroll(tester, database);

      expect(textIn(tester, 4, 'lf-achievement-tier'), '金');
      expect(textIn(tester, 4, 'lf-achievement-count'), '已解锁');
      expect(find.text('30/30'), findsNothing, reason: '解锁后满进度已无信息量，且不许变成两行');
      // 「换实心色」：解锁行的内盘是金档 token，未解锁行是 muted。
      final light = LfSemanticColors.light;
      expect(medalPlateColor(tester, 4), light.carbs);
      expect(medalPlateColor(tester, 1), light.muted);
      // 解锁行换成该成就自己的图标，锁只剩 3 个。
      expect(find.byIcon(Icons.apple_outlined), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
      // 弧画满且用金档色。
      expect(medalPainter(tester, 4).ratio, 1.0);
      expect(medalPainter(tester, 4).progress, light.carbs);

      // 混态也要等高：解锁行只把第 2 行的文字换掉，不加行、不加块。
      final heights = [for (var i = 1; i <= 4; i++) rowHeight(tester, i)];
      expect(
        heights.reduce((a, b) => a > b ? a : b) -
            heights.reduce((a, b) => a < b ? a : b),
        lessThan(0.5),
        reason: '解锁态与未解锁态必须等高：$heights',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('等级 / 进度 / 计数同源：弧长与条宽都只由 progress 决定', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await seedAchievement(database, key: 'streak-7', progress: 0.2);
      await seedAchievement(database, key: 'nutrition-master', progress: 0.5);
      await seedAchievement(database, key: 'workout-athlete', progress: 0.9);
      await pumpAndScroll(tester, database);

      const progress = <int, double>{1: 0.2, 2: 0.5, 3: 0.9};
      final light = LfSemanticColors.light;
      for (final entry in progress.entries) {
        final painter = medalPainter(tester, entry.key);
        expect(
          painter.ratio,
          entry.value,
          reason: '第 ${entry.key} 行的环必须画到 $entry.value',
        );
        final barWidth = tester
            .getSize(inRow(entry.key, find.byType(LfProgressBar)))
            .width;
        final fillWidth = tester
            .getSize(inRow(entry.key, find.byType(FractionallySizedBox)))
            .width;
        expect(
          fillWidth,
          closeTo(barWidth * entry.value, 1.0),
          reason: '第 ${entry.key} 行的条长必须是 progress × 条宽',
        );
      }
      // 档位色：铜 / 银 / 银（0.9 还没满，不许提前给金）。
      expect(medalPainter(tester, 1).progress, light.weight);
      expect(medalPainter(tester, 2).progress, light.mutedForeground);
      expect(medalPainter(tester, 3).progress, light.mutedForeground);
      // 条也同色（等级感在环与条上是同一支色）。
      expect(
        tester
            .widget<LfProgressBar>(inRow(1, find.byType(LfProgressBar)))
            .color,
        light.weight,
      );
      // 单调：progress 越大的行条越长。
      final widths = [
        for (final index in [1, 2, 3])
          tester.getSize(inRow(index, find.byType(FractionallySizedBox))).width,
      ];
      expect(widths[0], lessThan(widths[1]));
      expect(widths[1], lessThan(widths[2]));
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.0× 字号 + 320dp：四行名称仍是完整单行，且不越出卡片', (tester) async {
      viewport(tester, const Size(320, 900), scale: 2);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await pumpAndScroll(tester, database);

      const names = ['7天连续打卡', '营养达人', '运动健将', '健康饮食'];
      for (var index = 1; index <= 4; index++) {
        final nameFinder = inRow(
          index,
          find.byKey(const Key('lf-achievement-name')),
        );
        expect(nameFinder, findsOneWidget, reason: '第 $index 行要有名称');
        final name = names[index - 1];
        expect(tester.widget<Text>(nameFinder).data, name);
        // 名称外面必须套着「放不下就整体等比缩小」的兜底（不是省略、不是折行）。
        // 320dp 下这个兜底**还用不到**（实测：最长的名字要 157.5dp，可用 161.75dp），
        // 所以这里钉结构、下一条用例钉它真触发时的行为。
        final fallback = find.ancestor(
          of: nameFinder,
          matching: find.byType(FittedBox),
        );
        expect(fallback, findsOneWidget, reason: '$name 外面少了缩小兜底');
        expect(
          tester.widget<FittedBox>(fallback).fit,
          BoxFit.scaleDown,
          reason: '$name 的兜底必须是「只缩不放」',
        );
        final paragraph = tester.renderObject<RenderParagraph>(nameFinder);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$name 行数超限（信息性文本不许省略或截断）',
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: paragraph.text.toPlainText().length,
          ),
        );
        expect(
          boxes.map((box) => box.top).toSet(),
          hasLength(1),
          reason: '$name 折成了多行',
        );
        expect(
          paragraph.size.width + 0.5,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
          reason: '$name 的排版宽度不够，会被裁',
        );
        final bottom = boxes
            .map((box) => box.bottom)
            .reduce((a, b) => a > b ? a : b);
        expect(
          bottom,
          lessThanOrEqualTo(paragraph.size.height + 1.0),
          reason: '$name 被纵向裁半截',
        );
      }

      final card = tester.getRect(
        find.byKey(const Key('settings-achievements')),
      );
      for (var i = 1; i <= 4; i++) {
        final row = tester.getRect(find.byKey(Key('settings-achievement-$i')));
        expect(
          row.right,
          lessThanOrEqualTo(card.right + 0.5),
          reason: '第 $i 行越出了卡片右沿',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('名称兜底：2.0× + 300dp 真放不下时整体缩小，不省略也不折行', (tester) async {
      // 上一条用的 320dp 是需求里的最窄视口，但名称在那里**还排得下**（实测
      // 需要 157.5dp、可用 161.75dp），所以缩小兜底在 320dp 下不参与工作——
      // 少了它也照样绿。这条把视口收到 300dp，让兜底真的介入：
      // 名称固有宽 157.5dp > 可用 141.75dp ⇒ 必须整体缩小（≈0.90×）。
      viewport(tester, const Size(300, 900), scale: 2);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await pumpAndScroll(tester, database);

      const names = ['7天连续打卡', '营养达人', '运动健将', '健康饮食'];
      for (var index = 1; index <= 4; index++) {
        final name = names[index - 1];
        final nameFinder = inRow(
          index,
          find.byKey(const Key('lf-achievement-name')),
        );
        final boxWidth = tester
            .getSize(inRow(index, find.byType(FittedBox)))
            .width;
        expect(
          tester.getSize(nameFinder).width,
          index == 1 ? greaterThan(boxWidth) : lessThanOrEqualTo(boxWidth),
          reason: index == 1
              // 只有最长的「7天连续打卡」超宽（157.5dp > 141.75dp），兜底为它介入
              ? '$name 在这个宽度下应当触发缩小兜底（否则这条用例失去意义）'
              : '$name 不该超宽（超宽说明可用宽度量错了）',
        );
        final paragraph = tester.renderObject<RenderParagraph>(nameFinder);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$name 被省略了');
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: paragraph.text.toPlainText().length,
          ),
        );
        expect(
          boxes.map((box) => box.top).toSet(),
          hasLength(1),
          reason: '$name 折成了多行',
        );
        expect(
          paragraph.size.width + 0.5,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
          reason: '$name 的排版宽度不够，会被裁',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });
}
