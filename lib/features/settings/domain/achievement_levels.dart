/// 成就的定义、等级与进度计数（docs/29 §P3 / 需求 5）。
///
/// 这一层只做**纯派生**，不落库、不改 schema（`Achievements` 表仍然只有
/// `progress` / `unlockedAt` 两列）：
///
/// 1. [AchievementSpec]：四条成就的 key / 名称 / 目标值——**唯一来源**。
///    `LoadProfileOverview._evaluateAchievements` 用它算 `progress`，页面拿它
///    画占位空态行，「n / 目标」里的目标也来自这里。三处各写一份字面量就迟早
///    会漂（今天 `_defaultAchievements` 里那份名称就是抄的）。
/// 2. [achievementLevelOf]：`progress` → 铜 / 银 / 金。
/// 3. [achievementCountOf]：`progress` × `target` → 展示用的「当前」计数。
///
/// 两条派生口径都必须跟落库语义对齐：`progress` 是**历史最大值**
/// （`_evaluateAchievements` 用 `max(存库值, 当前值)` 单调写回），所以等级与
/// 计数同样只增不减；而 `unlockedAt` 一经写入不再回收，于是 `progress >= 1`
/// 与 `unlocked` 永远同步——页面上「金 ⇔ 已解锁」不会闪。
library;

/// 四条成就的静态定义（key = 落库行 key，label = 页面文案，target = 达标值）。
///
/// 声明顺序即页面展示顺序（`settings-achievement-1..4`）。
enum AchievementSpec {
  streak7(key: 'streak-7', label: '7天连续打卡', target: 7),
  nutritionMaster(key: 'nutrition-master', label: '营养达人', target: 7),
  workoutAthlete(key: 'workout-athlete', label: '运动健将', target: 10),
  healthyDiet(key: 'healthy-diet', label: '健康饮食', target: 30);

  const AchievementSpec({
    required this.key,
    required this.label,
    required this.target,
  });

  final String key;
  final String label;

  /// 达标值（天数 / 次数 / 条数），恒 > 0。
  final int target;
}

/// 成就等级：纯展示层概念，没有对应的数据库列。
enum AchievementLevel { bronze, silver, gold }

/// `progress`（0..1）→ 等级：`< 0.5` 铜、`[0.5, 1)` 银、`1.0` 金。
///
/// 边界**含等号**：0.5 就是银（不是「大于 0.5 才升级」），0.99 仍是银——只有
/// 真正满进度才给金，因为金在页面上与「已解锁」同义，提前给就是谎报。
/// 非有限值（NaN / ±∞，只可能来自脏数据）按铜兜底：宁可显示低档。
AchievementLevel achievementLevelOf(double progress) {
  if (!progress.isFinite) return AchievementLevel.bronze;
  if (progress >= 1.0) return AchievementLevel.gold;
  if (progress >= 0.5) return AchievementLevel.silver;
  return AchievementLevel.bronze;
}

/// 「n / 目标」里的 n：`progress × target` 向下取整，且**未解锁时永不等于
/// 目标**（上限 `target - 1`）。
///
/// 为什么不用实时计数：进度条画的是 `progress`（历史最大值）。数字若取实时
/// 计数，就会出现「条满着、数字却掉下来」的自相矛盾。
/// 为什么不四舍五入：`progress = 0.99`、`target = 7` 时 round 给出 `7/7`，
/// 与「还没解锁」的银档直接打架；向下取整让数字与档位永远一致。
/// 为什么加 ε：`5 / 7 * 7` 在 double 里可能落到 4.999…，裸 floor 会少报一格。
int achievementCountOf({required double progress, required int target}) {
  if (target <= 0) return 0;
  if (!progress.isFinite || progress <= 0) return 0;
  if (progress >= 1.0) return target;
  final count = (progress * target + 1e-9).floor();
  if (count < 0) return 0;
  return count > target - 1 ? target - 1 : count;
}
