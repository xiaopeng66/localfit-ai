import 'package:drift/drift.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/settings/domain/achievement_levels.dart';

/// 「我的」页（docs/21 §5.6）的派生只读事实 + 成就评估结果。
///
/// 全部口径来自 docs/21 §7.2 的派生指标表与成就定义表，实现不得再发明：
/// - streak：`Meals` 按日分组，**从今天向前**连续有记录的天数（今天没记录
///   就是从 0 开始——规范原文，不做「宽容到昨天」的变体）。
/// - BMI：`Measurements` 最新体重 + `Profiles.heightCm`。
/// - BMR：Mifflin-St Jeor（与 `NutritionTargetCalculator` 同一公式，本类只
///   在档案/体重齐备时复算展示值，不写库）。
/// - 成就：4 条定义（streak-7 / nutrition-master / workout-athlete /
///   healthy-diet），`unlockedAt` 一经写入**不可回退**。
final class LoadProfileOverview {
  const LoadProfileOverview({required this.database, required this.clock});

  final AppDatabase database;
  final AppClock clock;

  // 成就写回与事实读取同一事务，避免清空/恢复穿插后把旧进度写回新库。
  Future<ProfileOverview> run() => database.transaction(() async {
    final now = clock.nowUtc().toLocal();
    final today = _format(now);

    final weight = await _latestWeight();
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    final goal = await _activeGoal();
    final waterTarget = await _latestWaterTargetMl();
    final waterConsumed = await _waterConsumedMl(today);
    final totalMeals = await _countMeals();
    final streak = await _streakDays(today);
    final bmi = _bmi(weight?.weightKg, profile?.heightCm);
    final bmr = _bmrKcal(
      birthYear: profile?.birthYear,
      biologicalSex: profile?.biologicalSex,
      heightCm: profile?.heightCm,
      weightKg: weight?.weightKg,
      now: now,
    );
    final goalHitDays = await _goalHitDays();
    final finishedWorkouts = await _countFinishedWorkouts();
    final foodCount = await _countFoods();
    final userCreatedFoodCount = await _countUserCreatedFoods();

    final achievements = await _evaluateAchievements(
      streakDays: streak,
      goalHitDays: goalHitDays,
      finishedWorkouts: finishedWorkouts,
      totalMeals: totalMeals,
    );

    return ProfileOverview(
      goal: goal?.goal,
      targetWeightKg: goal?.targetWeightKg,
      currentWeightKg: weight?.weightKg,
      totalMealRecords: totalMeals,
      streakDays: streak,
      bmi: bmi,
      bmrKcal: bmr,
      waterTargetMl: waterTarget,
      waterConsumedMlToday: waterConsumed,
      calorieMinKcal: goal?.calorieMinKcal,
      calorieMaxKcal: goal?.calorieMaxKcal,
      foodCount: foodCount,
      userCreatedFoodCount: userCreatedFoodCount,
      achievements: achievements,
      displayName: profile?.displayName,
      avatarPath: profile?.avatarPath,
    );
  });

  Future<({double weightKg})?> _latestWeight() async {
    final row =
        await (database.select(database.measurements)
              ..orderBy([
                (row) => OrderingTerm.desc(row.localDate),
                (row) => OrderingTerm.desc(row.updatedAt),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return (weightKg: row.weightKg);
  }

  Future<
    ({
      HealthGoal goal,
      double? targetWeightKg,
      double calorieMinKcal,
      double calorieMaxKcal,
    })?
  >
  _activeGoal() async {
    final row =
        await (database.select(database.goals)
              ..where((goal) => goal.status.equals('active'))
              ..orderBy([(goal) => OrderingTerm.desc(goal.effectiveFrom)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    final goal = HealthGoal.values.byName(row.type);
    return (
      goal: goal,
      targetWeightKg: row.targetWeightKg,
      // 每日目标热量区间：**同一行已有列**，只为「BMR 区间指示」透传
      // （docs/29 §P2）。不是新派生，也不改引导页算出来的任何数。
      calorieMinKcal: row.calorieMinKcal,
      calorieMaxKcal: row.calorieMaxKcal,
    );
  }

  Future<double?> _latestWaterTargetMl() async {
    final row =
        await (database.select(database.dailyTargets)
              ..orderBy([(row) => OrderingTerm.desc(row.effectiveDate)])
              ..limit(1))
            .getSingleOrNull();
    return row?.waterTargetMl;
  }

  /// 今天已记录的饮水量合计（docs/29 §P2 的「饮水进度环」要达成度）。
  ///
  /// 与 `WaterRepository.watchDay` 同口径（按 `localDate` 汇总、无记录 = 0，
  /// 不拿默认目标冒充）。这里只是**再读一次**给「我的」页用——本页是快照，
  /// 不做监听（已知限制见 `docs/21 §5.6` F2）。
  Future<double> _waterConsumedMl(String today) async {
    final amount = database.waterIntakes.amountMl.sum();
    final query = database.selectOnly(database.waterIntakes)
      ..addColumns([amount])
      ..where(database.waterIntakes.localDate.equals(today));
    final row = await query.getSingle();
    return row.read(amount) ?? 0;
  }

  Future<int> _countMeals() async {
    final count = database.meals.id.count();
    final query = database.selectOnly(database.meals)..addColumns([count]);
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<int> _countFoods() async {
    final count = database.foods.id.count();
    final query = database.selectOnly(database.foods)..addColumns([count]);
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// 用户自建的食物条数（docs/28 §5.6：「食材数据库」行要说清总里有多少自建）。
  ///
  /// 以 `foods.isUserCreated` 为准，不看 `state`——`state='user_created'` 是
  /// 派生写法，迁移 v11 才回填，而 `isUserCreated` 是写入时的那一列（同一
  /// 口径，卡上的「自建 / 内置」徽标读的也是它）。
  Future<int> _countUserCreatedFoods() async {
    final count = database.foods.id.count();
    final query = database.selectOnly(database.foods)
      ..addColumns([count])
      ..where(database.foods.isUserCreated.equals(true));
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<int> _countFinishedWorkouts() async {
    final count = database.workoutSessions.id.count();
    final query = database.selectOnly(database.workoutSessions)
      ..addColumns([count])
      ..where(database.workoutSessions.status.equals('finished'));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// 从 [today] 向前连续「有餐记录」的天数（§7.2）。
  Future<int> _streakDays(String today) async {
    final dates =
        (await (database.select(
              database.meals,
            )..orderBy([(row) => OrderingTerm.desc(row.localDate)])).get())
            .map((row) => row.localDate)
            .toSet();
    if (!dates.contains(today)) return 0;
    var day = DateTime.parse(today);
    var streak = 0;
    while (dates.contains(_format(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 累计「达标天数」（§7.2 nutrition-master）：当日摄入**未超过**当前生效
  /// 目标的上限（`<= calorieMax`）。与 `LoadIntakeTrend` / 分析卡同一口径
  /// （2026-10-23：达标按「未超上限」判定，低于下限另由分析卡提示）；
  /// 目标区间取**当前生效**一条，不按历史日逐日回溯。
  Future<int> _goalHitDays() async {
    final goalRow =
        await (database.select(database.goals)
              ..where((goal) => goal.status.equals('active'))
              ..orderBy([(goal) => OrderingTerm.desc(goal.effectiveFrom)])
              ..limit(1))
            .getSingleOrNull();
    if (goalRow == null) return 0;
    final kcal = database.mealItems.kcalSnapshot.sum();
    final query = database.selectOnly(database.meals).join([
      innerJoin(
        database.mealItems,
        database.mealItems.mealId.equalsExp(database.meals.id),
      ),
    ]);
    query.addColumns([database.meals.localDate, kcal]);
    query.groupBy([database.meals.localDate]);
    final rows = await query.get();
    var hits = 0;
    for (final row in rows) {
      final value = row.read(kcal) ?? 0;
      if (value <= goalRow.calorieMaxKcal) {
        hits++;
      }
    }
    return hits;
  }

  double? _bmi(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || heightCm <= 0) return null;
    final meters = heightCm / 100;
    return weightKg / (meters * meters);
  }

  /// Mifflin-St Jeor（公式与 `NutritionTargetCalculator` 一致）。
  /// 性别/年龄/身高/体重任一缺失 → null（诚实空态，不估算）。
  int? _bmrKcal({
    required int? birthYear,
    required String? biologicalSex,
    required double? heightCm,
    required double? weightKg,
    required DateTime now,
  }) {
    if (birthYear == null || heightCm == null || weightKg == null) return null;
    final sex = switch (biologicalSex) {
      'male' => BiologicalSex.male,
      'female' => BiologicalSex.female,
      _ => null,
    };
    if (sex == null) return null;
    final age = now.year - birthYear;
    if (age <= 0) return null;
    final adjustment = switch (sex) {
      BiologicalSex.male => 5,
      BiologicalSex.female => -161,
    };
    return (10 * weightKg + 6.25 * heightCm - 5 * age + adjustment).round();
  }

  /// 读取 + 评估 + 落库成就。解锁是**写一次**：`unlockedAt` 已非空的行不再
  /// 更新（即使数据被删导致进度回落，成就保持——§7.2 规则）。
  Future<List<ProfileAchievement>> _evaluateAchievements({
    required int streakDays,
    required int goalHitDays,
    required int finishedWorkouts,
    required int totalMeals,
  }) async {
    final computed = <(AchievementSpec, double)>[
      (
        AchievementSpec.streak7,
        _fraction(streakDays, AchievementSpec.streak7.target),
      ),
      (
        AchievementSpec.nutritionMaster,
        _fraction(goalHitDays, AchievementSpec.nutritionMaster.target),
      ),
      (
        AchievementSpec.workoutAthlete,
        _fraction(finishedWorkouts, AchievementSpec.workoutAthlete.target),
      ),
      (
        AchievementSpec.healthyDiet,
        _fraction(totalMeals, AchievementSpec.healthyDiet.target),
      ),
    ];
    final existing = {
      for (final row in await database.select(database.achievements).get())
        row.key: row,
    };
    final result = <ProfileAchievement>[];
    for (final (spec, progress) in computed) {
      final key = spec.key;
      final row = existing[key];
      var unlocked = row?.unlockedAt != null;
      var stored = progress;
      if (row != null && row.progress > progress) stored = row.progress;
      if (progress >= 1.0 && !unlocked) {
        unlocked = true;
        final now = clock.nowUtc();
        if (row == null) {
          await database
              .into(database.achievements)
              .insert(
                AchievementsCompanion.insert(
                  id: 'achievement-$key',
                  key: key,
                  progress: Value(stored),
                  unlockedAt: Value(now),
                ),
              );
        } else {
          await (database.update(database.achievements)
                ..where((entry) => entry.key.equals(key)))
              .write(AchievementsCompanion(unlockedAt: Value(now)));
        }
      } else if (row == null && stored > 0) {
        // 未产生进度的空态只展示，清空后的页面重读不重新创建行。
        await database
            .into(database.achievements)
            .insert(
              AchievementsCompanion.insert(
                id: 'achievement-$key',
                key: key,
                progress: Value(stored),
              ),
            );
      } else if (row != null && stored != row.progress) {
        await (database.update(database.achievements)
              ..where((entry) => entry.key.equals(key)))
            .write(AchievementsCompanion(progress: Value(stored)));
      }
      result.add(
        ProfileAchievement(
          key: key,
          label: spec.label,
          unlocked: unlocked,
          progress: stored.clamp(0.0, 1.0),
          target: spec.target,
        ),
      );
    }
    return result;
  }

  static double _fraction(int value, int target) =>
      target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);

  static String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

final class ProfileOverview {
  const ProfileOverview({
    required this.goal,
    required this.targetWeightKg,
    required this.currentWeightKg,
    required this.totalMealRecords,
    required this.streakDays,
    required this.bmi,
    required this.bmrKcal,
    required this.waterTargetMl,
    this.waterConsumedMlToday,
    this.calorieMinKcal,
    this.calorieMaxKcal,
    required this.foodCount,
    this.userCreatedFoodCount = 0,
    required this.achievements,
    this.displayName,
    this.avatarPath,
  });

  final HealthGoal? goal;
  final double? targetWeightKg;
  final double? currentWeightKg;

  /// 昵称（`Profiles.displayName`，docs/32 §3 D9）。null = 没填过。
  final String? displayName;

  /// 头像路径（`Profiles.avatarPath`，docs/32 §3 D9）。null = 没设过；
  /// 非 null 但文件不存在时界面回退首字母（`.lfb` 只带路径不带字节）。
  final String? avatarPath;

  /// `Meals` 总条数（「总记录」，§7.2）。
  final int totalMealRecords;
  final int streakDays;
  final double? bmi;

  /// Mifflin-St Jeor，kcal/天；档案不全为 null（§6.2 裁决 8：必须带单位）。
  final int? bmrKcal;

  /// `DailyTargets.waterTargetMl`（最新一条）。
  final double? waterTargetMl;

  /// 今天已记录的饮水量合计（`WaterIntakes` 按 `localDate` 汇总，无记录 = 0）。
  /// docs/29 §P2：饮水的「达成度」只能由它算，拿目标当进度是伪造。
  final double? waterConsumedMlToday;

  /// 当前生效目标的每日热量区间（`Goals.calorieMin/Max`，同一行已有列）。
  /// docs/29 §P2：BMR 的「区间指示」拿它当参照物——**不是**医学上的
  /// 「正常 BMR 区间」（那种区间没有公认值，编一个就是伪造语义）。
  final double? calorieMinKcal;
  final double? calorieMaxKcal;
  final int foodCount;

  /// 其中用户自建（`foods.isUserCreated`）的条数（docs/28 §5.6）。
  final int userCreatedFoodCount;
  final List<ProfileAchievement> achievements;
}

final class ProfileAchievement {
  const ProfileAchievement({
    required this.key,
    required this.label,
    required this.unlocked,
    required this.progress,
    required this.target,
  });

  final String key;
  final String label;
  final bool unlocked;

  /// 0..1；未解锁时按进度展示，解锁后恒 1。
  final double progress;

  /// 达标值（[AchievementSpec.target] 原样透传）。「n / 目标」的分母来自它，
  /// 页面不再自己认 7/10/30 这些数。
  final int target;
}
