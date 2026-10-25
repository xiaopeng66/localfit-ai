import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// 步数目标（docs/32 §4 T9 / §3 D11 需求 64）。
///
/// 契约（逐条对应下面的断言）：
/// - 未设置 = 10000（= 下线前硬编码在步数卡里的那个常量，旧行为逐字不变）；
/// - 写进去能读回来；
/// - 越界（1000–50000 之外）**拒绝写入**，不静默收敛成边界值；
/// - 存量坏值 / 越界值读出来按默认值处理（不抛、也不解释成别的数）；
/// - 有订阅方时写入即推送。
void main() {
  late AppDatabase database;
  late StepsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = StepsRepository(
      database: database,
      // 本文件不读传感器：只需要「有个通道」把仓储构造起来。
      channel: StepsChannel(),
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 13, 4)),
    );
  });

  tearDown(() => database.close());

  Future<void> seedGoal(String raw) => database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: StepsRepository.dailyGoalKey,
          value: raw,
        ),
      );

  Future<String?> storedGoal() async {
    final row =
        await (database.select(database.appSettings)
              ..where((r) => r.key.equals(StepsRepository.dailyGoalKey)))
            .getSingleOrNull();
    return row?.value;
  }

  test('缺键 ⇒ 默认 10000（旧行为不变）', () async {
    expect(await repository.readDailyGoal(), 10000);
    expect(StepsRepository.defaultDailyGoal, 10000);
  });

  test('写读往返：12000 进、12000 出', () async {
    await repository.updateDailyGoal(12000);
    expect(await repository.readDailyGoal(), 12000);
    // 落库形态是十进制整数字符串（键值表只有字符串列）。
    expect(await storedGoal(), '12000');
  });

  test('边界值 1000 / 50000 收下', () async {
    await repository.updateDailyGoal(1000);
    expect(await repository.readDailyGoal(), 1000);
    await repository.updateDailyGoal(50000);
    expect(await repository.readDailyGoal(), 50000);
  });

  test('越界拒绝：999 / 50001 抛 ArgumentError 且一个字都不落库', () async {
    await expectLater(
      repository.updateDailyGoal(999),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      repository.updateDailyGoal(50001),
      throwsA(isA<ArgumentError>()),
    );
    // 拒绝 = 没有写入（不是写了个边界值）。
    expect(await storedGoal(), isNull);
    expect(await repository.readDailyGoal(), StepsRepository.defaultDailyGoal);
  });

  test('存量坏值 / 越界值读出来按默认处理（不抛、也不冒充别的数）', () async {
    await seedGoal('abc');
    expect(await repository.readDailyGoal(), StepsRepository.defaultDailyGoal);
    await seedGoal('999999');
    expect(await repository.readDailyGoal(), StepsRepository.defaultDailyGoal);
    // 读的时候不纠正写回：读操作有写副作用会让「读」不再安全。
    expect(await storedGoal(), '999999');
  });

  test('watchDailyGoal：缺键先推默认值，写入后推新值', () async {
    final seen = <int>[];
    final subscription = repository.watchDailyGoal().listen(seen.add);
    await pumpEventQueue();
    await repository.updateDailyGoal(12000);
    await pumpEventQueue();
    await subscription.cancel();
    expect(seen.first, StepsRepository.defaultDailyGoal);
    expect(seen.last, 12000);
  });
}
