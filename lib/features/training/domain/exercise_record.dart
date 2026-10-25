final class ExerciseRecord {
  const ExerciseRecord({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.difficulty,
    required this.popularity,
    required this.isUserCreated,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final MuscleGroup muscleGroup;
  final Equipment equipment;

  /// 难度（docs/21 §5.5）。null＝未标注，界面显示「难度未知」。
  final ExerciseDifficulty? difficulty;

  /// 常用度 0–100（docs/21 §5.5）。null＝未标注。
  final int? popularity;
  final bool isUserCreated;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 动作难度（docs/21 §5.5「难度」）。
///
/// 与 [MuscleGroup] 不同，这里**不抛错**：该列可空且历史行本就无值，
/// 「未标注」是合法状态而不是脏数据——抛错会把整份旧库存变成打不开的库。
enum ExerciseDifficulty {
  beginner('初级'),
  intermediate('中级'),
  advanced('高级');

  const ExerciseDifficulty(this.label);
  final String label;

  static ExerciseDifficulty? fromStoredValue(String? value) {
    if (value == null) return null;
    for (final item in ExerciseDifficulty.values) {
      if (item.name == value) return item;
    }
    return null;
  }
}

final class NewExercise {
  const NewExercise({
    required this.name,
    required this.muscleGroup,
    required this.equipment,
  });

  final String name;
  final MuscleGroup muscleGroup;
  final Equipment equipment;
}

enum MuscleGroup {
  chest('胸'),
  back('背'),
  legs('腿'),
  shoulders('肩'),
  arms('手臂'),
  core('核心'),
  fullBody('全身');

  const MuscleGroup(this.label);
  final String label;

  static MuscleGroup fromStoredValue(String value) =>
      MuscleGroup.values.firstWhere(
        (group) => group.name == value,
        orElse: () => throw FormatException('未知的肌群：$value'),
      );
}

enum Equipment {
  bodyweight('自重'),
  barbell('杠铃'),
  dumbbell('哑铃'),
  machine('器械'),
  cable('绳索'),
  other('其他');

  const Equipment(this.label);
  final String label;

  static Equipment fromStoredValue(String value) => Equipment.values.firstWhere(
    (item) => item.name == value,
    orElse: () => throw FormatException('未知的器械类型：$value'),
  );
}
