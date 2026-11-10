import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';

import '../ai_conversation/application/chat_edit_executor_test.dart'
    show IdsForTest;

/// 16a：**记忆弹窗里那两件挨在一起的东西**（用户反馈第 16 条 a）。
///
/// 【这条需求的两个落点，都测】`docs/60` §4 写的是「分类选择按钮贴太近」，
/// 方案是「间距提到 `spaceSmallPlus`(10)」。逐字核代码，`偏好` 与 `其他`
/// 同时出现、且相邻的地方有两处，两处都是**紧挨着**的：
///
/// 1. **「添加记忆」弹层**：`类型`（缺省显示「偏好」）与 `领域`（缺省显示
///    「其他」）两个控件上下直接相邻，中间没有任何 `SizedBox`；
/// 2. **对话页「结束本次对话」的候选弹层**：底部「取消 / 保存所选」两枚
///    按钮是两个 `Expanded` 直接相邻——**水平间距 0dp**，视觉上连成一块。
///
/// 判据统一为 `docs/60` §12.9 给出的那条：相邻两件之间的**几何间距 ≥ 10dp**
/// （`a.right/ bottom + 10 <= b.left/top`），量 `getRect`，不量代码。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AiMemoryRepository memoryRepository;
  late DriftConversationMessageRepository historyRepository;
  late _ReplayService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    memoryRepository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(DateTime.utc(2026, 10, 17, 12)),
      idGenerator: IdsForTest(),
    );
    historyRepository = DriftConversationMessageRepository(database: database);
    service = _ReplayService();
  });

  tearDown(() async {
    // 收尾顺序由每个用例的 `disposePage` 负责（先卸页面、再关库）。顺序反了会踩
    // drift 的 `Timer.run`：页面还挂着就 close，tearDown 会等那个计时器直到超时
    // （`ai_memory_page_test.dart` 记着同一条教训：实测挂满 10 分钟）。
  });

  /// 先卸页面（取消 drift 流订阅）→ pump 一拍让零延迟计时器跑掉 → 关库。
  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
  }

  testWidgets('「添加记忆」弹层：类型（偏好）/ 领域（其他）上下间距 ≥ 10dp', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: AiMemoryPage(repository: memoryRepository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-memory-add')));
    await tester.pumpAndSettle();

    final kind = tester.getRect(find.byKey(const Key('ai-memory-editor-kind')));
    final domain = tester.getRect(
      find.byKey(const Key('ai-memory-editor-domain')),
    );
    expect(
      kind.bottom + LfDimens.spaceSmallPlus,
      lessThanOrEqualTo(domain.top + 0.01),
      reason:
          '「类型（偏好）」与「领域（其他）」贴在一起'
          '（垂直间距 ${domain.top - kind.bottom}dp）',
    );
    await disposePage(tester);
  });

  testWidgets('对话页候选弹层：取消 / 保存所选 水平间距 ≥ 10dp', (tester) async {
    for (var i = 0; i < 6; i++) {
      await historyRepository.save(
        ConversationMessage(
          id: 'pad-$i',
          role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
          text: '补充对话 $i',
          createdAt: DateTime.utc(2026, 10, 17, 9, i),
        ),
      );
    }
    service.reply =
        '{"reply":"找到 1 条","candidates":[{"text":"不吃香菜",'
        '"kind":"preference","domain":"nutrition","tags":["香菜"]}]}';
    await tester.pumpWidget(
      MaterialApp(
        home: AiConversationPage(
          service: service,
          historyRepository: historyRepository,
          aiMemoryRepository: memoryRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-chat-end-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-memory-candidate-save')), findsOneWidget);

    // 候选行副标题就是「偏好 · 饮食」这档分类信息；要量的是它下面那两枚按钮。
    //
    // 【量的是按钮不是文字】两枚按钮都在 `Expanded` 里，按钮本身撑满半行、
    // 文字居中——量文字会得到「文字之间有空隙」的假象。所以按
    // `TextButton`（`LfTextButton` 的内层原生件）取矩形。
    final cancel = tester.getRect(
      find
          .ancestor(of: find.text('取消'), matching: find.byType(TextButton))
          .first,
    );
    final save = tester.getRect(
      find.byKey(const Key('ai-memory-candidate-save')),
    );
    expect(
      cancel.right + LfDimens.spaceSmallPlus,
      lessThanOrEqualTo(save.left + 0.01),
      reason: '两枚按钮贴在一起（间距 ${save.left - cancel.right}dp）',
    );
    await disposePage(tester);
  });
}

/// 回放式假服务（与 `ai_conversation_extract_memory_test.dart` 同一手法）。
final class _ReplayService implements AiConversationService {
  String reply = '';

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    for (var index = 0; index < reply.length; index += 7) {
      final end = (index + 7).clamp(0, reply.length);
      final chunk = reply.substring(index, end);
      onProgress(chunk);
      yield chunk;
    }
  }
}
