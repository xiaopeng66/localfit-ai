import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// 生成的 AppDatabase 也导出一个 ConversationMessage 行类：用前缀避开歧义。
import 'package:localfit_ai/data/database/app_database.dart' as db;
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';

/// 聊天记录落库（docs/21 §7.2 契约 / 表 `ConversationMessages`）。
///
/// 表里没有 kind 列：形态由 `imagePath`（图片）与 `durationMs`（语音，
/// 音频转写后即删所以只剩时长）推导——这层推导错了，重启后消息会换形态，
/// 所以每一种形态都要有往返断言。
///
/// P10（需求 36）：语音输入已整族删除，但 `durationMs` 列与
/// `ConversationMessageKind.voice` **保留**（D8：历史库里可能已有语音消息，
/// 老数据必须还能读回来）——所以这条往返断言留在测试里守着旧数据兼容，
/// 只是**再没有新代码能写出 voice 消息**。
void main() {
  late db.AppDatabase database;
  late DriftConversationMessageRepository repository;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftConversationMessageRepository(database: database);
  });

  tearDown(() => database.close());

  test('文本消息往返：角色、正文、状态、形态', () async {
    final message = ConversationMessage(
      id: 'm1',
      role: ConversationRole.user,
      text: '午饭吃了鸡胸肉',
      createdAt: DateTime.utc(2026, 10, 1, 12, 0, 0),
      status: ConversationMessageStatus.sent,
    );

    await repository.save(message);
    final loaded = await repository.loadRecent();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'm1');
    expect(loaded.single.role, ConversationRole.user);
    expect(loaded.single.text, '午饭吃了鸡胸肉');
    expect(loaded.single.kind, ConversationMessageKind.text);
    expect(loaded.single.status, ConversationMessageStatus.sent);
    expect(loaded.single.imagePath, isNull);
    expect(loaded.single.durationMs, isNull);
    // drift 的 dateTime 列按本地时间串存回：读回来是**同一时刻**的本地
    // DateTime（时区标记会变），所以比时刻而不是比字面时区。
    expect(
      loaded.single.createdAt.isAtSameMomentAs(DateTime.utc(2026, 10, 1, 12)),
      isTrue,
    );
  });

  test('图片消息往返：kind=image 且带路径与文件名', () async {
    await repository.save(
      ConversationMessage(
        id: 'm1',
        role: ConversationRole.user,
        text: '这是午饭',
        createdAt: DateTime.utc(2026, 10, 1, 12),
        status: ConversationMessageStatus.sent,
        kind: ConversationMessageKind.image,
        imagePath:
            '/docs/localfit_ai/chat_images/photo_20261001_120000_ab12.jpg',
      ),
    );

    final loaded = await repository.loadRecent();

    expect(loaded.single.kind, ConversationMessageKind.image);
    expect(
      loaded.single.imagePath,
      '/docs/localfit_ai/chat_images/photo_20261001_120000_ab12.jpg',
    );
    expect(loaded.single.text, '这是午饭');
  });

  test('语音消息往返（P10 遗留兼容）：音频已删，形态靠时长记住', () async {
    await repository.save(
      ConversationMessage(
        id: 'm1',
        role: ConversationRole.user,
        text: '午饭吃了鸡胸肉',
        createdAt: DateTime.utc(2026, 10, 1, 12),
        status: ConversationMessageStatus.sent,
        kind: ConversationMessageKind.voice,
        durationMs: 3200,
      ),
    );

    final loaded = await repository.loadRecent();

    expect(loaded.single.kind, ConversationMessageKind.voice);
    expect(loaded.single.durationMs, 3200);
    expect(loaded.single.text, '午饭吃了鸡胸肉');
  });

  test('助手回复的失败态往返：failed ↔ error', () async {
    await repository.save(
      ConversationMessage(
        id: 'a1',
        role: ConversationRole.assistant,
        text: '',
        createdAt: DateTime.utc(2026, 10, 1, 12),
        status: ConversationMessageStatus.error,
      ),
    );

    final loaded = await repository.loadRecent();

    expect(loaded.single.role, ConversationRole.assistant);
    expect(loaded.single.status, ConversationMessageStatus.error);
  });

  test('发送中态往返：sending 不丢', () async {
    await repository.save(
      ConversationMessage(
        id: 'a1',
        role: ConversationRole.assistant,
        text: '',
        createdAt: DateTime.utc(2026, 10, 1, 12),
        status: ConversationMessageStatus.sending,
      ),
    );

    expect(
      (await repository.loadRecent()).single.status,
      ConversationMessageStatus.sending,
    );
  });

  test('同一秒内的多条消息按插入顺序返回（时间列只有秒精度）', () async {
    final at = DateTime.utc(2026, 10, 1, 12, 0, 0);
    for (var i = 0; i < 5; i++) {
      await repository.save(
        ConversationMessage(
          id: 'm$i',
          role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
          text: '第 $i 条',
          createdAt: at,
          status: ConversationMessageStatus.sent,
        ),
      );
    }

    final loaded = await repository.loadRecent();

    expect(loaded.map((m) => m.text), [for (var i = 0; i < 5; i++) '第 $i 条']);
  });

  test('limit 取最近 N 条，返回仍是时间正序', () async {
    for (var i = 0; i < 10; i++) {
      await repository.save(
        ConversationMessage(
          id: 'm$i',
          role: ConversationRole.user,
          text: '第 $i 条',
          createdAt: DateTime.utc(2026, 10, 1, 12, 0, i),
          status: ConversationMessageStatus.sent,
        ),
      );
    }

    final loaded = await repository.loadRecent(limit: 3);

    expect(loaded.map((m) => m.text), ['第 7 条', '第 8 条', '第 9 条']);
  });

  test('limit <= 0 返回空且不查库', () async {
    await repository.save(_text('m1', '在吗'));

    expect(await repository.loadRecent(limit: 0), isEmpty);
    expect(await repository.loadRecent(limit: -5), isEmpty);
  });

  test('会话隔离：别的 sessionId 不串进来', () async {
    await repository.save(_text('m1', '默认会话'));
    await repository.save(_text('m2', '别的会话'), sessionId: 'other');

    final loaded = await repository.loadRecent();

    expect(loaded.map((m) => m.text), ['默认会话']);
    expect(await repository.loadRecent(sessionId: 'other'), hasLength(1));
    expect(
      (await repository.loadRecent(sessionId: 'other')).single.text,
      '别的会话',
    );
  });

  test('同一 id 重复保存是覆盖而不是新增（乐观 UI 定稿重写）', () async {
    await repository.save(_text('m1', '第一版'));
    await repository.save(_text('m1', '第二版'));

    final loaded = await repository.loadRecent();

    expect(loaded, hasLength(1));
    expect(loaded.single.text, '第二版');
  });

  test('乐观 UI 的 sending 占位在定稿后被 sent 覆盖', () async {
    await repository.save(
      ConversationMessage(
        id: 'a1',
        role: ConversationRole.assistant,
        text: '',
        createdAt: DateTime.utc(2026, 10, 1, 12),
        status: ConversationMessageStatus.sending,
      ),
    );
    await repository.save(
      ConversationMessage(
        id: 'a1',
        role: ConversationRole.assistant,
        text: '完整回复',
        createdAt: DateTime.utc(2026, 10, 1, 12),
        status: ConversationMessageStatus.sent,
      ),
    );

    final loaded = await repository.loadRecent();

    expect(loaded, hasLength(1));
    expect(loaded.single.text, '完整回复');
    expect(loaded.single.status, ConversationMessageStatus.sent);
  });
}

ConversationMessage _text(String id, String text) => ConversationMessage(
  id: id,
  role: ConversationRole.user,
  text: text,
  createdAt: DateTime.utc(2026, 10, 1, 12),
  status: ConversationMessageStatus.sent,
);
