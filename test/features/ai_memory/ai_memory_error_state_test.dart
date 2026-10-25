import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';

/// RV-P1-12：记忆页的流报错时必须显示错误态，不能永久 spinner。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('数据库不可用 ⇒ 错误文案而非永久 spinner', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(DateTime.utc(2026, 10, 20, 4)),
      idGenerator: _SeqIds(),
    );
    await database.close();

    await tester.pumpWidget(
      MaterialApp(
        home: AiMemoryPage(
          repository: repository,
          // 真实的流错误（等价于磁盘损坏/库被删）。
          memoriesStream: Stream<List<AiMemory>>.error(
            StateError('database is closed'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('记忆加载失败，请重试。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
