import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/placeholder_feature_page.dart';
import 'package:localfit_ai/core/time/daily_rollover.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_ai_entry_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_calorie_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_greeting_header.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_meals_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_next_meal_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_weight_card.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/hydration/presentation/water_entry_dialog.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';
import 'package:localfit_ai/features/progress/presentation/weight_entry_dialog.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// 今日页（Round7 A 变体 A：`app.js:149-156` 的 `todayPage`）。
///
/// **无 AppBar**：问候头直接贴顶。卡片按 A 的顺序：
/// 热量（`energy`）→ 体重（`weightBlock`）→ 饮水/步数（`dailyMetrics`）→
/// 下一餐预算（`nextMeal`）→ 今日餐次（`meals`）→ AI 入口线（`ai`）。
/// A 的 `activity` 卡只在有进行中训练时出现，本页不实现（决策 D2）。
///
/// 旧的 bento 单元（计划时间线 / 快捷记录 / 训练达标 / 摄入趋势 / 置信摘要）
/// 按 docs/22 裁决 ② 收进二级入口，**数据与逻辑零删除**——它们的 widget 与
/// 测试都还在，只是不再挂在本页首屏。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.mealRepository,
    this.measurementRepository,
    this.waterRepository,
    this.stepsRepository,
    this.onOpenAiWorkbench,
    this.onOpenRecord,
    this.onLogMeal,
    this.onOpenSettings,
    this.identity,
    this.now,
  });

  final MealRepository? mealRepository;
  final MeasurementRepository? measurementRepository;

  /// 饮水仓储（schema 17 新增域）。未接线时饮水卡走诚实空态。
  final WaterRepository? waterRepository;

  /// 步数仓储（docs/29 §P9 需求 34）。未接线（或设备无计步传感器）时
  /// 步数卡走既有诚实空态。
  final StepsRepository? stepsRepository;

  /// AI 健康助手入口（`cta-ai-workbench`，docs/21 §5.1 交互表）。
  final VoidCallback? onOpenAiWorkbench;

  /// `cta-view-all-meals`：跳饮食页的**记录** tab（「查看全部」）。
  ///
  /// Round7 A 起本页不再有「菜单」快捷入口（`cta-view-menu` 退场，决策 D4）：
  /// A 的餐次卡只有「查看全部」；菜单首屏仍在底栏「饮食」页里。
  final VoidCallback? onOpenRecord;

  /// 「记录饮食」（参数 null）/「记录晚餐」（`MealSlot.dinner`）：打开餐食编辑
  /// 弹层并预选槽位（决策 D9 的一次性意向通道）。路由层负责导航到饮食页。
  final ValueChanged<MealSlot?>? onLogMeal;

  /// 头像：跳「我的」。
  final VoidCallback? onOpenSettings;

  /// 身份事实（昵称/头像，docs/32 §3 D9）。null = 未接线 → 回退。
  final IdentityProfile? identity;

  final DateTime? now;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with DailyRollover {
  @override
  void onNewDay(DateTime previousDay) {
    // 跨零点：今日 = 新的一天，所有 stream 的 localDate 都要跟着换。
    setState(() {});
  }

  String get _localDate => formatLocalDate(widget.now ?? observedToday);

  @override
  Widget build(BuildContext context) {
    final repository = widget.mealRepository;
    if (repository == null) {
      return const PlaceholderFeaturePage(
        title: '今日',
        icon: Icons.today_outlined,
        message: '热量、营养目标和今日训练将在这里汇总。',
      );
    }
    final localDate = _localDate;

    // 三条流分开订阅：任一数据源变化只重建它自己那块，不必整页重算。
    return StreamBuilder<DailyNutritionSummary>(
      stream: repository.watchNutritionForDate(localDate),
      builder: (context, nutritionSnapshot) {
        if (nutritionSnapshot.hasError) {
          return const AppErrorText('今日营养数据加载失败，请重试。');
        }
        if (!nutritionSnapshot.hasData) {
          // RV-P2-23：首帧用骨架而不是空转圈——结构与真实卡同形，避免
          // 「转圈 → 突然跳版」。
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: const [
              SkeletonBox(height: 22, width: 140),
              SizedBox(height: 12),
              SkeletonBox(height: 120),
              SizedBox(height: 12),
              SkeletonBox(height: 96),
            ],
          );
        }
        final summary = nutritionSnapshot.data!;
        return StreamBuilder<List<MealRecord>>(
          stream: repository.watchForDate(localDate),
          builder: (context, mealsSnapshot) {
            final meals = mealsSnapshot.data ?? const <MealRecord>[];
            return _DashboardBody(
              localDate: localDate,
              now: widget.now ?? observedToday,
              summary: summary,
              meals: meals,
              waterRepository: widget.waterRepository,
              measurementRepository: widget.measurementRepository,
              stepsRepository: widget.stepsRepository,
              onOpenAiWorkbench: widget.onOpenAiWorkbench,
              onOpenRecord: widget.onOpenRecord,
              onLogMeal: widget.onLogMeal,
              onOpenSettings: widget.onOpenSettings,
              identity: widget.identity,
              onRecordWeight: _recordWeight,
              onAddWater: _addWater,
            );
          },
        );
      },
    );
  }

  /// 体重记录：弹层负责取数 + 提交态，**落库在弹层的提交路径里**（N7）——
  /// 写失败时弹层不关、错误画在弹层内，用户填的内容不丢。
  ///
  /// 需求 33：弹层里可以改日期。**回到哪一天，就看那一天已有的记录**——
  /// 弹层默认给的 [initial] / [existing] 是「今天」的值；用户把日期改到
  /// 8 月 3 日时，`WeightEntryDialog` 会带着新日期回调 [onDateChanged]，
  /// 我们再把那天的值回填进去。改了日期却还留着今天的体重，保存就会把
  /// 今天这个数字写到 8 月 3 日上——那是伪造数据，不是「编辑」。
  Future<void> _recordWeight({
    double? initial,
    WeightMeasurement? existing,
  }) async {
    if (!mounted) return;
    await AppSheet.showCustom<WeightEntryResult>(
      context,
      builder: (_) => WeightEntryDialog(
        initialWeightKg: initial,
        todayLocalDate: _localDate,
        // 「添加」入口默认落在**今天**：existing 是「30 天里最新的一条」，多数
        // 时候不是今天（昨天称过、今天还没称）。把昨天的日期当默认值，用户
        // 一路点保存就会**把今天的体重写到昨天那条上**——那是改历史，不是
        // 记录今天。只有 existing 恰好是今天时才作为默认（编辑今天）。
        initialLocalDate: existing != null && existing.localDate == _localDate
            ? existing.localDate
            : _localDate,
        // 改了日期就把字段换成那天的值（见 `WeightEntryDialog.onDateChanged`）：
        // 不回填就等于把「今天这个数字」写到用户选的那天上去。
        onDateChanged: (date) async {
          final repository = widget.measurementRepository;
          if (repository == null) return null;
          final found = await repository.findByDate(date);
          if (found == null) return null;
          return WeightEntryResult(
            weightKg: found.weightKg,
            notes: found.notes,
          );
        },
        onSubmit: (result) async {
          final repository = widget.measurementRepository;
          if (repository == null) return '当前无法保存体重，请稍后重试。';
          final targetDate = result.localDate ?? _localDate;
          try {
            await repository.saveManualWeight(
              localDate: targetDate,
              weightKg: result.weightKg,
              notes: result.notes,
            );
            if (mounted) {
              // 提示带日期：回填历史时用户要能确认改的是哪一天（需求 33）。
              AppSnackBar.show(
                context,
                targetDate == _localDate
                    ? '体重已保存到本机。'
                    : '体重已保存到 ${formatMonthDayLabel(targetDate)}。',
                icon: AppSnackBar.successIcon,
              );
            }
            return null;
          } on FormatException catch (error) {
            return error.message;
          } catch (_) {
            return '体重保存失败，请重试。';
          }
        },
      ),
    );
  }

  /// 加水：弹层取量 + 提交态，**写库在弹层的提交路径里**（N7）——失败不关窗。
  Future<void> _addWater(double consumedMl) async {
    final repository = widget.waterRepository;
    if (repository == null) return;
    await AppSheet.showCustom<double>(
      context,
      builder: (_) => WaterEntryDialog(
        todayConsumedMl: consumedMl,
        onSubmit: (amount) async {
          try {
            await repository.add(localDate: _localDate, amountMl: amount);
            if (mounted) {
              AppSnackBar.show(
                context,
                '已记录 ${amount.round()} ml 饮水。',
                icon: AppSnackBar.successIcon,
              );
            }
            return null;
          } on FormatException catch (error) {
            return error.message;
          } catch (_) {
            return '饮水记录失败，请重试。';
          }
        },
      ),
    );
  }
}

/// 页面主体：按 Round7 A 变体 A 的卡片顺序排列（`app.js:154`）。
class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.localDate,
    required this.now,
    required this.summary,
    required this.meals,
    required this.measurementRepository,
    required this.waterRepository,
    required this.stepsRepository,
    required this.onRecordWeight,
    required this.onAddWater,
    this.onOpenAiWorkbench,
    this.onOpenRecord,
    this.onLogMeal,
    this.onOpenSettings,
    this.identity,
  });

  final String localDate;
  final DateTime now;
  final DailyNutritionSummary summary;
  final List<MealRecord> meals;
  final MeasurementRepository? measurementRepository;
  final WaterRepository? waterRepository;
  final StepsRepository? stepsRepository;
  final Future<void> Function({double? initial, WeightMeasurement? existing})
  onRecordWeight;
  final Future<void> Function(double consumedMl) onAddWater;
  final VoidCallback? onOpenAiWorkbench;
  final VoidCallback? onOpenRecord;
  final ValueChanged<MealSlot?>? onLogMeal;
  final VoidCallback? onOpenSettings;

  /// 身份事实（昵称/头像，docs/32 §3 D9）。null = 未接线 → 回退。
  final IdentityProfile? identity;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: LfDimens.pagePadding);
    return ListView(
      // extendBody 后内容延伸到贴底栏下方：给列表末尾留出栏高 + 上凸余量。
      // 顶部另加系统叠层（docs/21 §5.8.5）：本页没有贴顶 hero，整块内容下移。
      padding: EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        LfDimens.spaceSmall + LfInsets.top(context),
        LfDimens.pagePadding,
        LfInsets.navReserve(context),
      ),
      children: [
        DashboardGreetingHeader(
          now: now,
          localDate: localDate,
          // docs/32 §3 D9：昵称/头像由路由注入的 `identity` 提供；未接线
          // （测试/旧调用点）时两个都是 null → 问候语回到「早安」、头像「Fit」。
          displayName: identity?.displayName,
          avatarPath: identity?.avatarPath,
          onTapAvatar: onOpenSettings,
        ),
        gap,
        // A `energy()`：热量卡（剩余额度行也随之搬进卡内 foot，决策 D6）。
        DashboardCalorieCard(
          consumed: summary.consumed,
          target: summary.target,
        ),
        if (measurementRepository != null) ...[
          gap,
          StreamBuilder<WeightOverview>(
            stream: measurementRepository!.watchWeightOverview(
              endLocalDate: localDate,
            ),
            builder: (context, snapshot) {
              // 2026-10-21 RV-P2-23：流报错不能静默显示「无记录」。
              if (snapshot.hasError) {
                return const AppErrorText('体重数据加载失败，请重试。');
              }
              final overview = snapshot.data;
              if (overview == null) {
                return DashboardWeightCard(
                  overview: const WeightOverview(
                    measurements: [],
                    latest: null,
                    sevenDayAverageKg: null,
                    sampleDays: 0,
                  ),
                  endLocalDate: localDate,
                  onRecord: () => onRecordWeight(),
                );
              }
              return DashboardWeightCard(
                overview: overview,
                endLocalDate: localDate,
                onRecord: () => onRecordWeight(
                  initial: overview.latest?.weightKg,
                  existing: overview.latest,
                ),
              );
            },
          ),
        ],
        gap,
        // A `dailyMetrics()`：饮水 / 步数两格（在体重卡之后、下一餐之前）。
        if (waterRepository == null)
          DashboardQuickStatsRow(
            water: WaterSummary.empty,
            stepsRepository: stepsRepository,
            localDate: localDate,
          )
        else
          StreamBuilder<WaterSummary>(
            stream: waterRepository!.watchDay(localDate),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const AppErrorText('饮水数据加载失败，请重试。');
              }
              return DashboardQuickStatsRow(
                water: snapshot.data ?? WaterSummary.empty,
                onTapWater: () => onAddWater(snapshot.data?.consumedMl ?? 0),
                stepsRepository: stepsRepository,
                localDate: localDate,
              );
            },
          ),
        gap,
        // A `nextMeal()`：下一餐预算卡（剩余额度 / 进度轨 / 笔数与目标 /
        // 记录晚餐）。
        DashboardNextMealCard(
          consumedKcal: summary.consumed.kcal,
          targetKcal: summary.target?.calorieMaxKcal,
          mealCount: meals.length,
          onLogDinner: onLogMeal == null
              ? null
              : () => onLogMeal!(MealSlot.dinner),
        ),
        gap,
        // A `meals`：今日餐次卡（行列表 / 空态 / 置信摘要 / 记录饮食）。
        DashboardMealsCard(
          entries: buildMealTimeline(meals: meals),
          meals: meals,
          onViewAll: onOpenRecord,
          onLogMeal: onLogMeal == null ? null : () => onLogMeal!(null),
        ),
        if (onOpenAiWorkbench != null) ...[
          gap,
          // A `ai`：入口线（`.ai-entry-line`）。
          DashboardAiEntryCard(onTap: onOpenAiWorkbench!),
        ],
      ],
    );
  }
}
