import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// G23 时间语义（docs/41 §11 范围变更 S14，schema 29）的判据。
///
/// 语义只有三条，全部钉死：
/// 1. 新建即生效：`validFrom = 创建时刻`、`validTo = null`；
/// 2. **改口闭合旧条**：`supersede` 把旧条的 `validTo` 设成改口时刻
///    （与 `supersededById` 同时写），旧条不删、历史可看；
/// 3. `listAsOf(t)` 回答「t 时刻成立的是什么」——包含已被改口、但在 t 时
///    仍然有效的旧条；撤销改口后窗口重新打开。
void main() {
  late AppDatabase db;
  late AiMemoryRepository memories;

  final day1 = DateTime.utc(2026, 10, 1, 9);
  final day2 = DateTime.utc(2026, 10, 10, 9);
  final day3 = DateTime.utc(2026, 10, 19, 9);

  late _MutableClock clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = _MutableClock(day1);
    memories = AiMemoryRepository(
      database: db,
      clock: clock,
      idGenerator: const _SeqIds(),
    );
  });

  tearDown(() => db.close());

  test('新建即生效：validFrom = 创建时刻，validTo 为空', () async {
    final memory = await memories.remember(text: '我在减脂');
    expect(memory.validFrom?.toUtc(), day1);
    expect(memory.validTo, isNull);
    expect(memory.isValidAt(day1), isTrue);
    expect(memory.isValidAt(day3), isTrue);
  });

  test('改口：旧条 validTo = 改口时刻；「当时是什么」按日期返回旧/新条', () async {
    final old = await memories.remember(text: '我在减脂');
    clock.value = day2;
    final fresh = await memories.remember(text: '我改成增肌了');
    await memories.supersede(oldId: old.id, newId: fresh.id);

    final closed = await memories.listActive();
    // 改口后默认列表只有新条。
    expect(closed.map((item) => item.text), ['我改成增肌了']);

    // 10 月 1 日问「当时」⇒ 减脂（旧条），不是增肌。
    final atDay1 = await memories.listAsOf(day1);
    expect(atDay1.map((item) => item.text), ['我在减脂']);

    // 10 月 10 日（改口当天）⇒ 新条生效。
    final atDay2 = await memories.listAsOf(day2);
    expect(atDay2.map((item) => item.text), ['我改成增肌了']);

    // 旧条的窗口是 [day1, day2)。
    final oldRow = (await memories.history()).singleWhere(
      (item) => item.id == old.id,
    );
    expect(oldRow.validFrom?.toUtc(), day1);
    expect(oldRow.validTo?.toUtc(), day2);
    expect(oldRow.isValidAt(day1), isTrue);
    expect(oldRow.isValidAt(day2), isFalse, reason: '改口时刻起旧条不再成立');
  });

  test('撤销改口：窗口重新打开，validTo 清空', () async {
    final old = await memories.remember(text: '我在减脂');
    clock.value = day2;
    final fresh = await memories.remember(text: '我改成增肌了');
    await memories.supersede(oldId: old.id, newId: fresh.id);

    await memories.undoSupersede(old.id);

    final reopened = (await memories.history()).singleWhere(
      (item) => item.id == old.id,
    );
    expect(reopened.supersededById, isNull);
    expect(reopened.validTo, isNull);
    expect(reopened.isValidAt(day3), isTrue);
  });

  test('导出/导入保留有效期（closed 条带 validTo）', () async {
    final old = await memories.remember(text: '我在减脂');
    clock.value = day2;
    final fresh = await memories.remember(text: '我改成增肌了');
    await memories.supersede(oldId: old.id, newId: fresh.id);

    final document = await memories.exportDocument();
    final entries = (document['memories'] as List).cast<Map>();
    // 导出只导出当前有效的条目：新条带 validFrom、不带 validTo。
    expect(entries, hasLength(1));
    expect(entries.single['text'], '我改成增肌了');
    expect(entries.single['validFrom'], day2.toIso8601String());
    expect(entries.single['validTo'], isNull);
  });

  testWidgets('记忆页「按日期回看」：选 cross 改口前那天，列出旧条而不是新条', (tester) async {
    final old = await memories.remember(text: '我在减脂');
    clock.value = day2;
    final fresh = await memories.remember(text: '我改成增肌了');
    await memories.supersede(oldId: old.id, newId: fresh.id);
    clock.value = day3;

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AiMemoryPage(
          repository: memories,
          onClose: () {},
          // 固定选 10 月 1 日（改口之前）。
          pickAsOfDate: (_) async => DateTime(2026, 10, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-memory-asof')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-memory-asof-sheet')), findsOneWidget);
    expect(
      find.byKey(Key('ai-memory-asof-row-${old.id}')),
      findsOneWidget,
      reason: '10 月 1 日成立的只有「我在减脂」',
    );
    expect(
      find.byKey(Key('ai-memory-asof-row-${fresh.id}')),
      findsNothing,
      reason: '新条 10 月 10 日才生效，不能出现在 10 月 1 日的结果里',
    );

    // 收尾：卸页面让 drift 的取消订阅计时器跑掉，再关库。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });

  test('迁移 29：历史行回填 validFrom = created_at，validTo 为空', () async {
    final dir = Directory.systemTemp.createTempSync('localfit-v29-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}v28.sqlite';

    final raw = sqlite.sqlite3.open(path);
    raw.execute(
      'CREATE TABLE ai_memories ('
      'id TEXT NOT NULL PRIMARY KEY, text TEXT NOT NULL, kind TEXT NOT NULL, '
      'domain TEXT NOT NULL, tags_json TEXT NOT NULL DEFAULT \'[]\', '
      'pinned INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL, '
      'status TEXT NOT NULL DEFAULT \'active\', created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL, importance INTEGER NOT NULL DEFAULT 50, '
      'last_used_at TEXT, use_count INTEGER NOT NULL DEFAULT 0, '
      'superseded_by_id TEXT, expires_at TEXT, source_message_id TEXT, '
      'linked_entity_type TEXT, linked_entity_id TEXT, related_ids TEXT)',
    );
    raw.execute(
      'INSERT INTO ai_memories '
      '(id, text, kind, domain, source, created_at, updated_at) VALUES '
      "('m1', '老记忆', 'fact', 'general', 'manual', "
      '${DateTime.utc(2026, 9, 1, 8).millisecondsSinceEpoch ~/ 1000}, '
      '${DateTime.utc(2026, 9, 1, 8).millisecondsSinceEpoch ~/ 1000})',
    );
    raw.execute('PRAGMA user_version = 28');
    raw.dispose();

    final upgraded = AppDatabase(NativeDatabase(File(path)));
    addTearDown(upgraded.close);
    final row = await (upgraded.select(
      upgraded.aiMemories,
    )..where((item) => item.id.equals('m1'))).getSingle();

    expect(
      row.validFrom?.toUtc(),
      DateTime.utc(2026, 9, 1, 8),
      reason: '回填用 created_at，不能凭空造一个「现在」',
    );
    expect(row.validTo, isNull);
  });
}

class _SeqIds implements IdGenerator {
  const _SeqIds();

  static int _next = 0;

  @override
  String next() => 'id-${++_next}';
}

/// 可推进的测试时钟（改口发生在另一天）。
class _MutableClock implements AppClock {
  _MutableClock(this.value);

  DateTime value;

  @override
  DateTime nowUtc() => value;
}
