import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';

/// RV-P1-17：`importDocument` 必须**整单原子**——第 N 条不合规时，
/// 前 N-1 条（以及它们的向量行）不能留下。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AiMemoryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(DateTime.utc(2026, 10, 20, 4)),
      idGenerator: _SeqIds(),
    );
  });

  tearDown(() => database.close());

  test('第二条不合规：整单回滚，库与索引都是 0 行', () async {
    await expectLater(
      repository.importDocument({
        'version': 1,
        'memories': [
          {'text': '周三晚上练腿'},
          // 敏感红线（身份证号）⇒ 必须拒绝。
          {'text': '我的身份证号是 110101199001011234'},
        ],
      }),
      throwsA(isA<FormatException>()),
    );

    expect(
      await database.select(database.aiMemories).get(),
      isEmpty,
      reason: '第 1 条不能留下（整单拒绝 = 整单不写）',
    );
    expect(await database.select(database.embeddingIndex).get(), isEmpty);
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
