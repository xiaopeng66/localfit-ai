import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

/// 「我的」页身份卡所需的档案事实：目标类型 + 当前生效的每日目标。
final class ProfileIdentity {
  const ProfileIdentity({
    required this.goal,
    required this.calorieMaxKcal,
    required this.proteinMinGrams,
    required this.proteinMaxGrams,
    required this.carbsMinGrams,
    required this.carbsMaxGrams,
    required this.fatMinGrams,
    required this.fatMaxGrams,
  });

  final HealthGoal goal;
  final double calorieMaxKcal;
  final double proteinMinGrams;
  final double proteinMaxGrams;
  final double carbsMinGrams;
  final double carbsMaxGrams;
  final double fatMinGrams;
  final double fatMaxGrams;
}

/// 个人资料编辑页（docs/29 §P1 / D3）用于回填的身体档案事实。
///
/// 三个字段都对应 `Profiles` 的既有可空列，`null` = 该档案从未填写，
/// 界面留空、保存时原样写回（不把「未填」伪造成 0 或默认值）。
final class BodyProfile {
  const BodyProfile({this.heightCm, this.birthYear, this.biologicalSex});

  /// `Profiles.heightCm`。
  final double? heightCm;

  /// `Profiles.birthYear`（年龄按「当前年 − 出生年」派生，与
  /// `complete_onboarding.dart` 同一口径）。
  final int? birthYear;

  /// `Profiles.biologicalSex`，存枚举名字符串（'female' / 'male'）；
  /// 未知或空值原样保留、不猜测。
  final String? biologicalSex;
}

/// 个人资料编辑页用于回填的「当前训练目标」（docs/29 §P1）。
///
/// 选行口径与 [ProfileIdentityRepository.updateGoal] **逐字一致**（最新
/// `effectiveFrom` 那条，不筛 `status`）——两者必须是同一行，否则界面回填的
/// 目标与保存时要覆盖的行可能不是同一条，用户会看到 A 却写掉 B。
final class GoalProfile {
  const GoalProfile({required this.goal, this.targetWeightKg});

  final HealthGoal goal;
  final double? targetWeightKg;
}

final class ProfileIdentityRepository {
  const ProfileIdentityRepository({required this.database});

  final AppDatabase database;

  /// 读取 [localDate]（YYYY-MM-DD）当天生效的最近一条每日目标及其所属目标类型。
  /// 未建档或历史数据缺少目标类型时返回 null，界面降级为占位卡。
  Future<ProfileIdentity?> loadActive({required String localDate}) async {
    final targetQuery = database.select(database.dailyTargets)
      ..where((row) => row.effectiveDate.isSmallerOrEqualValue(localDate))
      ..orderBy([(row) => OrderingTerm.desc(row.effectiveDate)])
      ..limit(1);
    final targetRow = await targetQuery.getSingleOrNull();
    if (targetRow == null) return null;
    final goalRow =
        await (database.select(database.goals)
              ..where((row) => row.id.equals(targetRow.goalId))
              ..limit(1))
            .getSingleOrNull();
    if (goalRow == null) return null;
    HealthGoal? byName;
    try {
      byName = HealthGoal.values.byName(goalRow.type);
    } on Object {
      byName = null;
    }
    // 兼容蛇形写法（如 'lose_fat'）；未知值降级为占位卡。
    final goal =
        byName ??
        switch (goalRow.type) {
          'lose_fat' => HealthGoal.loseFat,
          'gain_muscle' => HealthGoal.gainMuscle,
          'maintain' => HealthGoal.maintain,
          _ => null,
        };
    if (goal == null) return null;
    return ProfileIdentity(
      goal: goal,
      calorieMaxKcal: targetRow.calorieMaxKcal,
      proteinMinGrams: targetRow.proteinMinGrams,
      proteinMaxGrams: targetRow.proteinMaxGrams,
      carbsMinGrams: targetRow.carbsMinGrams,
      carbsMaxGrams: targetRow.carbsMaxGrams,
      fatMinGrams: targetRow.fatMinGrams,
      fatMaxGrams: targetRow.fatMaxGrams,
    );
  }

  /// 更新训练目标（2.0-6f）：更新最近一条目标的类型与可选目标体重。
  /// 没有历史目标时静默返回（界面仍以占位卡展示）。
  Future<void> updateGoal({
    required HealthGoal goal,
    double? targetWeightKg,
  }) async {
    final goalRow =
        await (database.select(database.goals)
              ..orderBy([(row) => OrderingTerm.desc(row.effectiveFrom)])
              ..limit(1))
            .getSingleOrNull();
    if (goalRow == null) return;
    await (database.update(
      database.goals,
    )..where((row) => row.id.equals(goalRow.id))).write(
      GoalsCompanion(
        type: Value(goal.name),
        // 2026-10-20 全应用审查 RV-P1-14：可选参数缺省 = **不改**。
        // 原来无条件写 Value(null)，用户说「目标改成减脂」就把既有目标
        // 体重静默清空（AI 命令是唯一会省略它的调用方）。
        targetWeightKg: targetWeightKg == null
            ? const Value.absent()
            : Value(targetWeightKg),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// 读取「当前训练目标」及其可选目标体重，供编辑页回填（docs/29 §P1）。
  ///
  /// **选行口径与 [updateGoal] 逐字一致**（最新 `effectiveFrom` 那条）；未建档
  /// 或目标类型无法识别时返回 null，界面回落默认档。不回填就会出数据事故：
  /// 页面默认「维持」+ 目标体重空 ⇒ 保存时 `updateGoal` 会把用户的真实目标
  /// 与目标体重**静默覆盖**成「维持 / 无」。
  Future<GoalProfile?> loadGoalProfile() async {
    final row =
        await (database.select(database.goals)
              ..orderBy([(g) => OrderingTerm.desc(g.effectiveFrom)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    HealthGoal? goal;
    try {
      goal = HealthGoal.values.byName(row.type);
    } on Object {
      goal = null;
    }
    // 兼容蛇形写法（如 'lose_fat'）；未知值不回填、由界面回落默认档。
    goal ??= switch (row.type) {
      'lose_fat' => HealthGoal.loseFat,
      'gain_muscle' => HealthGoal.gainMuscle,
      'maintain' => HealthGoal.maintain,
      _ => null,
    };
    if (goal == null) return null;
    return GoalProfile(goal: goal, targetWeightKg: row.targetWeightKg);
  }

  /// 读取建档时写入的身体指标（身高 / 出生年 / 性别），供编辑页回填
  /// （docs/29 §P1 / D3）。未建档返回 null；建档但从未填写某项时该项为 null
  /// （界面留空，不伪造 0 / 默认值）。
  Future<BodyProfile?> loadBodyProfile() async {
    final row = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (row == null) return null;
    return BodyProfile(
      heightCm: row.heightCm,
      birthYear: row.birthYear,
      biologicalSex: row.biologicalSex,
    );
  }

  /// 读取身份显示事实（docs/32 §3 D9，schema 23）：昵称 + 头像路径。
  ///
  /// 未建档返回 null（界面回退「Fit」与首字母）；建档但从未填写的字段为
  /// null（**不编造名字**，与 `avatarInitial` 的既有口径一致）。
  Future<IdentityProfile?> loadIdentity() async {
    final row = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (row == null) return null;
    return IdentityProfile(
      displayName: row.displayName,
      avatarPath: row.avatarPath,
    );
  }

  Stream<IdentityProfile?> watchIdentity() =>
      (database.select(database.profiles)..limit(1))
          .watchSingleOrNull()
          .map(
            (row) => row == null
                ? null
                : IdentityProfile(
                    displayName: row.displayName,
                    avatarPath: row.avatarPath,
                  ),
          )
          .distinct(
            (previous, next) =>
                previous?.displayName == next?.displayName &&
                previous?.avatarPath == next?.avatarPath &&
                (previous == null) == (next == null),
          );

  /// 写昵称（docs/32 §3 D9）：trim 后 1–20 字符；其余一律拒绝（抛
  /// [ProfileIdentityException]，界面把原因上屏）。
  ///
  /// **空串不落库**：用户说「不要这个昵称了」与「填了个空」是两件事——
  /// 前者应显式清空（走 [clearDisplayName]），后者是输入错误。
  Future<void> updateDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw const ProfileIdentityException('昵称不能为空');
    }
    if (trimmed.length > 20) {
      throw const ProfileIdentityException('昵称最多 20 个字符');
    }
    await _writeIdentity(displayName: Value(trimmed));
  }

  /// 清空昵称（界面回退「Fit」）。身份卡暂不提供入口，保留给将来的
  /// 「恢复默认」；写 null 而不是空串（未填 ≠ 空昵称）。
  Future<void> clearDisplayName() async =>
      _writeIdentity(displayName: const Value(null));

  /// 写头像路径（docs/32 §3 D9）。传 null = 移除头像（回退首字母）。
  ///
  /// **路径越界防护**：只接受应用文档目录下的路径——`.lfb` 是从文件系统
  /// 里挑的包，一个被篡改的包塞进私有目录以外的路径就能让恢复后的应用
  /// 去读别处（与 `DishImageStore.deleteQuietly` 同一条防线）。
  /// 判定放在 store 层（它知道文档目录），此处只做非空/无 `..` 的便宜检查。
  Future<void> updateAvatarPath(String? avatarPath) async {
    final value = avatarPath?.trim();
    if (value != null && value.isNotEmpty) {
      if (value.contains('\u0000') ||
          value.split(RegExp(r'[\/]')).contains('..')) {
        throw const ProfileIdentityException('头像路径无效');
      }
    }
    await _writeIdentity(
      avatarPath: Value((value == null || value.isEmpty) ? null : value),
    );
  }

  Future<void> _writeIdentity({
    Value<String?> displayName = const Value.absent(),
    Value<String?> avatarPath = const Value.absent(),
  }) async {
    final row = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (row == null) return;
    await (database.update(
      database.profiles,
    )..where((r) => r.id.equals(row.id))).write(
      ProfilesCompanion(
        displayName: displayName,
        avatarPath: avatarPath,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// 更新身体指标（docs/29 §P1 / D3）：只写 [Profiles] 的三列，不动目标表。
  ///
  /// 与 [updateGoal] 同风格——没有档案行时静默返回（界面仍以空值展示）。
  /// 传 null 是把该项写回「未填写」，不是「保留原值」：编辑页回填后原样写回，
  /// 未填的字段才不会被悄悄清空（回填由 [loadBodyProfile] 负责）。
  Future<void> updateBodyProfile({
    required double? heightCm,
    required int? birthYear,
    required String? biologicalSex,
  }) async {
    final row = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (row == null) return;
    await (database.update(
      database.profiles,
    )..where((r) => r.id.equals(row.id))).write(
      ProfilesCompanion(
        heightCm: Value(heightCm),
        birthYear: Value(birthYear),
        biologicalSex: Value(biologicalSex),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

/// 身份显示事实（docs/32 §3 D9）：昵称与头像路径。
///
/// 与 [ProfileIdentity]（目标事实）、[BodyProfile]（身体事实）刻意分开：
/// 三者语义不同，混成一个类型会让「谁该为空」变模糊。
final class IdentityProfile {
  const IdentityProfile({this.displayName, this.avatarPath});

  /// 昵称（`Profiles.displayName`）。null = 没填过。
  final String? displayName;

  /// 头像文件路径（`Profiles.avatarPath`）。null = 没设过；
  /// 非 null 但文件不存在时界面回退首字母（`.lfb` 只带路径不带字节）。
  final String? avatarPath;
}

/// 身份写入被拒绝（昵称空/超长、头像路径非法）。message 可直接上屏。
final class ProfileIdentityException implements Exception {
  const ProfileIdentityException(this.message);

  final String message;

  @override
  String toString() => message;
}
