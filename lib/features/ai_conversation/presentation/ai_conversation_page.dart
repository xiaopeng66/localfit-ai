import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_bubbles.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_input.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_dependency.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/application/conversation_controller.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:localfit_ai/features/ai_conversation/application/pick_chat_image.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_record_launcher.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/catalog_choice_sheet.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_memory/application/ai_memory_candidates.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// AI 对话页（docs/21 §5.7 / `AI 工作.html`）。
///
/// 结构（设计稿逐节点）：顶栏（返回 + 吉祥物 + `LocalFit AI` + 用户头像）
/// → 消息区（六种形态）→ 固定底部输入区（快捷 chip + 图片预览条 + 双状态
/// 输入栏 + 免责声明）。
///
/// 本页是 shell 分支（底栏中央槽），`extendBody` 让内容延伸到导航栏下方：
/// 输入区自己留出 `MediaQuery.padding.bottom`（键盘收起时 = 底栏高度，
/// 键盘弹起时 shell 已把 body 收缩到键盘上沿，该值为 0）。
class AiConversationPage extends StatefulWidget {
  const AiConversationPage({
    this.service,
    this.suggestionService,
    this.historyRepository,
    this.chatImagePicker,
    this.onOpenNewFoodWithName,
    this.onOpenNewExerciseWithName,
    this.onOpenNewVenueWithName,
    this.onOpenNewWindowWithName,
    this.onOpenAiCreate,
    this.onOpenProfile,
    this.onBack,
    this.clock,
    this.chatEdit,
    this.pendingStarter,
    this.pendingStarterImage,
    this.identity,
    this.aiMemoryRepository,
    this.memoryExtraction,
    this.aiConnectivity,
    this.conversationHistory,
    this.chatImageStore,
    this.mealRepository,
    this.foodRepository,
    this.dishLibraryRepository,
    this.onAddDishToMeal,
    this.manualCardGeneration = false,
    super.key,
  });

  /// AI 对话服务。null＝未接线，发送时报诚实错误。
  final AiConversationService? service;

  /// 「AI 聊天建议」专用服务（2026-10-23 用户：用**单独配置的模型**理解当前
  /// 输出，给 2–3 个建议气泡）。null = 不请求建议（既有测试与未接线页面
  /// 行为不变）；路由注入时通常复用对话服务，也可注入一个不同模型的实例。
  final AiConversationService? suggestionService;

  /// 聊天记录仓储（`RV4-P2-06` 的「清除聊天记录」入口用它判断是否渲染）。
  ///
  /// null = 未接仓储 ⇒ 「清除聊天记录」入口不渲染（不给点了没反应的按钮）。
  final ConversationMessageRepository? conversationHistory;

  /// 聊天图片副本存储（清除历史时一并清；null = 只有文本，没有副本要清）。
  final ChatImageStore? chatImageStore;

  /// 「今天还剩多少」的数据源（`RV4-R16` chip 1）：null = chip 不渲染。
  final MealRepository? mealRepository;

  /// 「记一餐」的依赖（`RV4-R16` chip 2，复用 B3 的 `openMealRecordSheet`）：
  /// 三者缺一就不渲染该 chip（不给点了没反应的按钮）。
  final FoodRepository? foodRepository;
  final DishLibraryRepository? dishLibraryRepository;
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
  onAddDishToMeal;

  /// 【docs/66】按需生成应用卡片（v2 方案）。默认 false = 既有自动弹卡行为
  /// （测试与未接线嵌入点不变）；正式入口由 app_router 显式传 true。
  final bool manualCardGeneration;

  /// 聊天记录仓储（docs/21 §5.7 新增域）。null = 不落库，重启不留历史。
  final ConversationMessageRepository? historyRepository;

  /// 相册选图（图片消息）。null = `btn-image-upload` 提示未配置。
  final PickChatImage? chatImagePicker;

  /// 打开**预填名称**的新建食物弹层（2026-10-16：编辑卡的「缺食材」修复
  /// 按钮）。null = 未接线，点了给诚实提示。**不替用户填营养值**——那是
  /// 用户/表单的事。
  final Future<void> Function(String name)? onOpenNewFoodWithName;

  /// 新建动作弹层（缺动作的修复按钮；同一套预填口径）。
  final Future<void> Function(String name)? onOpenNewExerciseWithName;

  /// 添加食堂地点弹层（缺地点的修复按钮）。
  final Future<void> Function(String name)? onOpenNewVenueWithName;

  /// 添加窗口弹层（缺窗口的修复按钮；必须带归属地点 id）。
  final Future<void> Function(String venueId, String name)?
  onOpenNewWindowWithName;

  /// 快捷 chip「AI 创作」→ 起手画廊（Round7 逐页对账批次 2：A
  /// `app.js:207` 的第三条 quick chip 是「AI 创作」，点开的是创作页）。
  /// null = chip 仍在，点了给诚实提示（测试/未接线）。
  final VoidCallback? onOpenAiCreate;

  /// 顶栏用户头像 → 「我的」（docs/32 §3 D9）。null = 不可点（测试/未接线）。
  final VoidCallback? onOpenProfile;

  /// 身份事实（昵称/头像，docs/32 §3 D9）。null = 回退「Fit」/person 图标。
  final IdentityProfile? identity;

  /// 顶栏返回（回今日分支）。
  final VoidCallback? onBack;

  /// 注入时钟（测试确定性；缺省系统时钟）。
  final AppClock? clock;

  /// 通用编辑协调器（docs/23）。null = 纯聊天，不出现编辑卡。
  final ChatEditCoordinator? chatEdit;

  /// 「AI 创作」卡生成的启动提示词（docs/32 §4 T6b / §3 D5）。
  ///
  /// 路由级 `ValueNotifier`：画廊页写入 → 切到本分支 → 这里消费一次并
  /// **自动发送**；`isReplying` 时只预填不发送（避免打断进行中的回复）。
  ///
  /// `RV4-P2-03`（D5）：值是 `(display, send)` 两段——`display` 进用户气泡，
  /// `send` 发给模型（带 `[canteen-dish:<id>]` 定位）。两者相同时传同一个串。
  final ValueNotifier<({String display, String send})?>? pendingStarter;

  /// 起手请求随附的图片路径（2026-10-16，N2：分析菜品时把菜品照片一起发出去）。
  /// 消费一次即清空；文件读不到/解码失败就当没有图（只发文字）——绝不发假图。
  final ValueNotifier<String?>? pendingStarterImage;

  /// 长期记忆仓储（docs/38 v2「提炼记忆」）。null = 顶栏不出提炼按钮。
  final AiMemoryRepository? aiMemoryRepository;

  /// 会话结束提炼进「待确认」（docs/43 B8）。null = 顶栏不出「结束本次会话」。
  final MemoryExtractionQueue? memoryExtraction;

  /// 断网证据（2026-10-21 裁决 D-2）。null＝不显示断网提示。
  final AiConnectivityMonitor? aiConnectivity;

  @override
  State<AiConversationPage> createState() => _AiConversationPageState();
}

class _AiConversationPageState extends State<AiConversationPage> {
  /// 设计稿的欢迎语（AI 自己的第一句话，不是用户数据）。
  static const _greeting = '你好！我是你的 AI 健康助手。今天想和你一起规划饮食和运动，有什么我能帮你的吗？';

  late final ConversationController _controller;
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  final FocusNode _inputFocus = FocusNode();

  // 【R-10（2026-10-29 用户：希望能多加图片，而不是只能加一张、新加入的
  // 替换上一个）】待发图片从「一个槽位」改成**列表**：选图是追加不是替换，
  // 每张可单独移除。本版消息表只存单图（schema 30 不动）——发送时第一张
  // 随消息发出、其余留在输入区继续发，界面上一行小字如实说明。
  final List<ChatImage> _pendingImages = [];

  /// 待发图片上限（2026-11-07 用户要「图片多选」：3 → 9，仍防误选整相册）。
  static const int _maxPendingImages = 9;

  /// 有图片正在后台处理时，发送键**置灰不可点**（2026-11-07 用户要求）：
  /// 副本就绪前发出去，聊天记录里存的会是系统缓存路径。处理完成后自动恢复。
  bool get _imagesPreparing => _materializing.isNotEmpty;

  /// 正在后台处理（缩放/重编码/落盘）的占位预览 → 完成信号。
  ///
  /// 【2026-11-07 用户：选中后要等一秒缩略图才出现】原链路把「读字节 → isolate
  /// 解码 → 重编码 → 写副本」全部做完才上屏。现在**先把原图挂上预览**，重活放
  /// 后台；完成后再把占位换成文档目录的副本（长期保留的是副本）。
  final Map<String, Future<void>> _materializing = {};
  bool _pickingImage = false;
  bool _extractingMemory = false;

  /// 「起手随附照片」在飞的解码（需求 4）。
  ///
  /// 文字消费要 await 它，才能保证「文字 + 照片一次发出」；`null` = 当前没有
  /// 在解码的起手照片（相册选图走另一条路，不经这里）。
  Future<void>? _starterImageLoad;

  /// 本次对话是否已被用户显式结束（`RV4-P2-05`）。
  ///
  /// 结束时在消息流尾部画一条分隔线「本次对话已结束 · HH:mm」，输入框占位
  /// 改为「开始新对话…」；再点一次只提示（幂等，不再重复入队）。
  bool _sessionEnded = false;
  DateTime? _sessionEndedAt;

  /// 「今天还剩多少」的本地计算结果气泡（**不入库、不发给模型**）。
  final List<({String id, String text})> _localResults = [];

  /// 每条助手消息的建议回复（message.id → 2–3 句短回复）。
  final Map<String, List<String>> _suggestions = {};

  /// 已请求过建议的消息 id（每条只请求一次，避免重复计费）。
  final Set<String> _suggestionRequested = {};

  /// 消息定位键（docs/66 §6.4）：挂卡成功后 `Scrollable.ensureVisible` 用它
  /// 把目标卡片滚进视口（只在必要时最小滚动，不拽到会话底部）。
  final Map<String, GlobalKey> _messageKeys = {};

  /// 滚动隔离（§6.4）：新模式下只对「消息条数变化 / 发送状态切换」滚到底，
  /// 单纯的消息内容替换（同一条消息挂卡）不滚。旧模式保留原行为
  /// （任何状态变化都滚到底，不让回滚路径的行为变）。
  int _lastScrollMessageCount = 0;
  bool _lastScrollIsReplying = false;

  /// 上一次状态里的编辑卡 id 集合（挂卡增量检测）。
  Set<String> _lastEditProposalIds = const {};

  @override
  void initState() {
    super.initState();
    _controller = ConversationController(
      widget.service,
      repository: widget.historyRepository,
      clock: widget.clock,
      chatEdit: widget.chatEdit,
      connectivity: widget.aiConnectivity,
      manualCardGeneration: widget.manualCardGeneration,
      // 需求 6d：应用记餐前若发现「缺食材 + 同卡有创建」，由页面弹一次确认
      // （控制器不持有 BuildContext；弹层在页面这一层画）。
      editDependencyConfirm: _confirmEditDependency,
      // docs/66 §6.5：应用前发现非今天日期时由页面确认（同一分工）。
      confirmEditDates: _confirmEditDates,
    );
    _textController = TextEditingController();
    _scrollController = ScrollController();
    _controller.addListener(_onControllerChanged);
    _controller.addListener(_reportPersistError);
    _controller.addListener(_maybeRequestSuggestions);
    unawaited(_controller.loadHistory());
    widget.pendingStarter?.addListener(_consumePendingStarter);
    widget.pendingStarterImage?.addListener(_consumePendingStarterImage);
    // 冷启动：如果本页是因为 pending 才被建出来的（对话分支未建过），
    // initState 里先读一次（addListener 不会补发已有值）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingStarter();
      _consumePendingStarterImage();
    });
  }

  /// 消费一次「起手请求随附的图片」：挂成输入区的待发图片（用户可见、可移除），
  /// 由用户按发送键时才随消息出去（与相册选图同一条路径，见 S1 的多模态上行）。
  ///
  /// 尺寸要在挂上前解出来（`ChatImage` 需要宽高）；读不到/解码失败就当作没有
  /// 这张图——**不发半张**，也不谎报「已添加」。
  ///
  /// 【需求 4（2026-10-25）：文字与照片必须**一次发出**】食堂菜「AI 分析」把
  /// 菜名与照片一起写进 pending，而解码是真异步的。所以：
  /// * 在飞的解码记在 [_starterImageLoad] 上，[Future] 可重入——文字消费那边
  ///   能 await 它，不会出现「文字先出去、照片留在输入区」的错序（那正是用户
  ///   实测的现象：「点击后只会发送文本，图片需要再点一次」）；
  /// * 解码完只**挂**在输入区（不自己发送）：没有 pending 文字时它仍等用户按
  ///   发送键，与相册选图一致。
  Future<void> _consumePendingStarterImage() {
    final inFlight = _starterImageLoad;
    if (inFlight != null) return inFlight;
    final path = widget.pendingStarterImage?.value;
    if (path == null || path.isEmpty || !mounted) return Future<void>.value();
    widget.pendingStarterImage?.value = null;
    final load = _loadStarterImage(path)
        .whenComplete(() => _starterImageLoad = null);
    _starterImageLoad = load;
    return load;
  }

  Future<void> _loadStarterImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final width = decoded.width;
      final height = decoded.height;
      decoded.dispose();
      if (!mounted) return;
      setState(
        () => _pendingImages.add(
          ChatImage(
            path: path,
            fileName: path.split(RegExp(r'[\/]')).last,
            width: width,
            height: height,
          ),
        ),
      );
    } on Object {
      // 图片读不到：只发文字，并且如实说一句（不静默）。
      if (mounted) _snack('这道菜的照片读不到了，这次只发文字。');
    }
  }

  /// 消费一次启动提示词：空闲时**自动发送**；正在回复时只预填（不打断）。
  void _consumePendingStarter() {
    unawaited(_consumePendingStarterAsync());
  }

  Future<void> _consumePendingStarterAsync() async {
    final prompt = widget.pendingStarter?.value;
    if (prompt == null || prompt.display.isEmpty || !mounted) return;
    // 消费即清空：同一请求只生效一次（回退再进不会重发）。
    widget.pendingStarter?.value = null;
    // 【需求 4】先把同一批的随附照片解码挂好，再决定「发」还是「预填」。
    // 顺序反了就是用户实测的缺陷：文字单独先发出去，照片留在输入区等他再点一次。
    await _consumePendingStarterImage();
    if (!mounted) return;
    if (_controller.isReplying) {
      // 守卫：进行中的回复不打断——预填给用户，由他自己决定何时发。
      // 预填的是**显示版**（用户看到的就是他将会看到的气泡文本）。
      _textController.text = prompt.display;
      _textController.selection = TextSelection.collapsed(
        offset: prompt.display.length,
      );
      _snack('正在回复上一条，已把内容填进输入框。');
      return;
    }
    await _sendStarterPrompt(prompt.display, prompt.send);
  }

  /// 发送启动提示词：**显示文本与发送文本可能不同**（`RV4-P2-03` / D5）。
  Future<void> _sendStarterPrompt(String display, String send) async {
    _textController.text = display;
    if (display == send) {
      await _sendCurrent();
      return;
    }
    // 分离路径：不走 `_sendCurrent`（它只读输入框），直接交给控制器。
    if (_controller.isReplying) return;
    _textController.clear();
    final image = _pendingImages.isEmpty ? null : _pendingImages.first;
    if (image != null) setState(() => _pendingImages.removeAt(0));
    if (image != null) {
      // 带图时**同样**要把 `send`（含 `[canteen-dish:<id>]` 定位）交给模型：
      // 否则照片发了、模型却不知道这道菜是哪一条目录项，`canteen.dish.nutrition`
      // 只能靠菜名猜。
      await _controller.sendImageMessage(
        image: image,
        caption: display,
        wireText: send,
      );
    } else {
      await _controller.sendMessageWithWire(display, wireText: send);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.positions.last;
      if (position.maxScrollExtent > 0 &&
          position.pixels < position.maxScrollExtent) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 控制器状态变化 → 是否滚到底（docs/66 §6.4）：
  /// * 旧模式：任何变化都滚（2115 行为不变）；
  /// * 新模式：只有**消息条数变化**（新气泡）或**回复开始/结束**（输入栏
  ///   状态切换）才滚；手动生成状态走独立 notifier 本来就不进这里，挂卡
  ///   造成的内容替换也不滚——正在翻历史的用户不被拽走。
  void _onControllerChanged() {
    if (!widget.manualCardGeneration) {
      _scrollToBottom();
      return;
    }
    final count = _controller.state.messages.length;
    final replying = _controller.isReplying;
    final shouldScroll =
        count != _lastScrollMessageCount || replying != _lastScrollIsReplying;
    _lastScrollMessageCount = count;
    _lastScrollIsReplying = replying;
    if (shouldScroll) {
      _scrollToBottom();
      return;
    }
    // 挂卡成功 = 消息条数不变、但编辑卡集合出现新成员：定位到目标卡片
    // （§6.4：只在卡片不在视口内时最小滚动，不跳会话底部）。
    final attached = _detectNewlyAttachedCard();
    if (attached != null) _ensureCardVisible(attached);
  }

  /// 对比两次状态之间的编辑卡 id 集合；返回本次新出现的（至多一条）。
  String? _detectNewlyAttachedCard() {
    final current = {
      for (final message in _controller.state.messages)
        if (message.isEditProposal) message.id,
    };
    final added = current.difference(_lastEditProposalIds);
    _lastEditProposalIds = current;
    if (added.isEmpty) return null;
    return added.first;
  }

  /// 挂卡成功 → `Scrollable.ensureVisible` 定位到目标消息（§6.4）：
  /// 只在目标不在视口内时滚动（最小滚动），不跳会话底部。
  void _ensureCardVisible(String messageId) {
    final key = _messageKeys[messageId];
    final context = key?.currentContext;
    if (context == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.15,
      );
    });
  }

  /// 需求 6d：「记一餐要用到的新食材还没建」时的确认（一次列全）。
  ///
  /// 用户原话：「我点击鸡蛋水煮的应用的时候，应该弹窗提示是否应用创建食材
  /// 鸡蛋水煮，我选择确认后又可以继续应用该早餐添加」。所以这里问的是
  /// **一整批**（可能缺两三样），确认后由协调器先建再记。
  ///
  /// Key：`chat-edit-dependency-confirm`（层）/`-ok`（确认）/`-cancel`（拒绝）。
  Future<bool> _confirmEditDependency(
    List<ChatEditFoodDependency> missing,
  ) async {
    final names = missing.map((d) => d.foodName).toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        key: const Key('chat-edit-dependency-confirm'),
        title: const Text('要先创建食材吗？'),
        content: Text(
          '这一餐用到的食材${names.map((n) => '「$n」').join('、')}'
          '食物库里还没有。\n\n'
          '点「创建并记入」会先把'
          '${names.length > 1 ? '它们' : '它'}建进食物库，再记这一餐。',
        ),
        actions: [
          LfTextButton(
            key: const Key('chat-edit-dependency-confirm-cancel'),
            label: '先不记',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          LfPrimaryButton(
            key: const Key('chat-edit-dependency-confirm-ok'),
            label: '创建并记入',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// docs/66 §6.5：应用前**日期确认**——本次要执行的命令里有非今天的
  /// `localDate` 时弹一次（文案写清每个目标日期）。确认才执行；拒绝 /
  /// 弹层异常都按 false 处理（控制器侧绝不静默应用）。
  ///
  /// Key：`chat-edit-date-confirm`（层）/`-ok`（确认）/`-cancel`（拒绝）。
  Future<bool> _confirmEditDates(Set<String> dates) async {
    if (dates.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        key: const Key('chat-edit-date-confirm'),
        title: const Text('记录到其他日期？'),
        content: Text(
          '这张卡记录的是 ${dates.join('、')}，'
          '应用后会写到那一天（不是今天）。',
        ),
        actions: [
          LfTextButton(
            key: const Key('chat-edit-date-confirm-cancel'),
            label: '取消',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          LfPrimaryButton(
            key: const Key('chat-edit-date-confirm-ok'),
            label: '仍要应用',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 落库失败也要说（消息在屏幕上但重启会丢）。
  void _reportPersistError() {
    final message = _controller.takePersistError();
    if (message == null || !mounted) return;
    AppSnackBar.show(context, message, icon: AppSnackBar.errorIcon);
  }

  void _snack(String message, {bool informational = false}) {
    AppSnackBar.show(
      context,
      message,
      icon: informational ? AppSnackBar.infoIcon : AppSnackBar.errorIcon,
    );
  }

  /// 按修复建议的种类开对应的**预填名称**弹层（2026-10-16）。
  ///
  /// 四类都只预填「名字」，其余字段留给用户：App 不替用户编营养值、时间、
  /// 分类这些事实。未接线的种类给诚实提示（与其它未接线入口同一口径）。
  ///
  /// 【2026-11-05 选择卡】`chooseCatalog`（同名双库）先查候选，弹食物/菜品
  /// 选择层；选中后控制器把该行的引用改写成 `[food:id]`/`[dish:id]` 并重放。
  Future<void> _openEditRepair(
    String messageId,
    ChatEditRepair repair, {
    int? rowIndex,
  }) async {
    if (repair.kind == ChatEditRepairKind.chooseCatalog) {
      await _openCatalogChoice(messageId, repair, rowIndex: rowIndex);
      return;
    }
    await _openRepairForm(repair);
  }

  Future<void> _openCatalogChoice(
    String messageId,
    ChatEditRepair repair, {
    int? rowIndex,
  }) async {
    ConversationMessage? message;
    for (final item in _controller.state.messages) {
      if (item.id == messageId) {
        message = item;
        break;
      }
    }
    final turn = message?.editTurn;
    if (rowIndex == null && turn != null) {
      for (final row in turn.rows) {
        if (row.status == ChatEditRowStatus.failed &&
            row.repair?.kind == ChatEditRepairKind.chooseCatalog &&
            row.repair?.name == repair.name) {
          rowIndex = row.index;
          break;
        }
      }
    }
    final targetRow = rowIndex;
    if (targetRow == null) {
      _snack('找不到要重放的那一行，请重新发一次。');
      return;
    }

    final candidates = await _controller.resolveCatalogCandidates(repair.name);
    if (!mounted) return;
    if (candidates == null || candidates.isEmpty) {
      _snack('现在查不到「${repair.name}」的候选，稍后再试。');
      return;
    }
    final pick = await showCatalogChoiceSheet(context, candidates: candidates);
    if (!mounted || pick == null) return;
    final reference = switch (pick.kind) {
      CatalogPickKind.food => '[food:${pick.id}]',
      CatalogPickKind.supply => '[canteen-dish:${pick.id}]',
      CatalogPickKind.dish => '[dish:${pick.id}]',
    };
    await _controller.retryEditRowWithReference(
      messageId: messageId,
      rowIndex: targetRow,
      originalReference: repair.name,
      newReference: reference,
    );
  }

  Future<void> _openRepairForm(ChatEditRepair repair) async {
    switch (repair.kind) {
      case ChatEditRepairKind.createFood:
        final open = widget.onOpenNewFoodWithName;
        if (open == null) {
          _snack('新建食物尚未配置。');
          return;
        }
        await open(repair.name);
      case ChatEditRepairKind.createExercise:
        final open = widget.onOpenNewExerciseWithName;
        if (open == null) {
          _snack('新建动作尚未配置。');
          return;
        }
        await open(repair.name);
      case ChatEditRepairKind.createVenue:
        final open = widget.onOpenNewVenueWithName;
        if (open == null) {
          _snack('添加食堂地点尚未配置。');
          return;
        }
        await open(repair.name);
      case ChatEditRepairKind.createWindow:
        final open = widget.onOpenNewWindowWithName;
        final venueId = repair.venueId;
        if (open == null || venueId == null) {
          _snack('添加窗口尚未配置。');
          return;
        }
        await open(venueId, repair.name);
      case ChatEditRepairKind.chooseCatalog:
        // 已在上层 _openEditRepair 分流（需要 messageId，不在这里处理）。
        return;
    }
  }

  /// 长按气泡：把这一条的正文放进剪贴板（2026-10-16 用户「对话内容要能
  /// 长按复制」）。**整条复制**而不是划选——对话里要复制的基本就是那一句，
  /// 划选在窄气泡里又难选中。气泡只回传长按，剪贴板与提示留在页面。
  Future<void> _copyMessage(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // 2026-10-23 用户：「长按复制提示时间太长」——复制是一次性轻动作，
    // 1.2 s 足够读到「已复制」，不压着底栏挡下一句话。
    AppSnackBar.show(
      context,
      '已复制',
      icon: AppSnackBar.infoIcon,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    widget.pendingStarter?.removeListener(_consumePendingStarter);
    widget.pendingStarterImage?.removeListener(_consumePendingStarterImage);
    _controller.removeListener(_onControllerChanged);
    _controller.removeListener(_reportPersistError);
    _inputFocus.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ---- 发送 ------------------------------------------------------------

  /// 发送**在途**标志（2026-11-07 复查补的并发守卫）。
  ///
  /// `_sendCurrent` 中间有 `await _awaitPendingImages()`：等待窗口内按钮虽已
  /// 灰，但快捷 chip / 建议气泡等入口仍能触发第二次发送——两次都穿过开头的
  /// `isReplying` 检查（第一次还没真正发出去），就会同一条消息发两遍。
  bool _sendInFlight = false;

  Future<void> _sendCurrent() async {
    if (_sendInFlight || _controller.isReplying) return;
    _sendInFlight = true;
    try {
      // 后台还在处理刚选的图片：等它换成文档目录副本再发（否则聊天记录里
      // 存的是系统缓存路径，重启/系统清理后图就没了）。通常已经完成，无感。
      await _awaitPendingImages();
      if (!mounted || _controller.isReplying) return;
      await _sendNow();
    } finally {
      _sendInFlight = false;
    }
  }

  /// 真正的发送（读输入框/待发图 → 清空 → 交给控制器）。入口守卫在
  /// [_sendCurrent]。
  Future<void> _sendNow() async {
    final text = _textController.text;
    // 【2026-10-31 用户：多张图片点击发送时一起发送】全部 pending 图一次发。
    final images = List<ChatImage>.of(_pendingImages);
    if (images.isEmpty && text.trim().isEmpty) return;

    // 【2026-10-25 缺陷修复】结束会话后**无法新开对话**：
    // `_sessionEnded` 只在「清空聊天记录」里被重置，发送时从不重置，于是
    // 分隔线「本次对话已结束」和输入框占位「开始新对话…」永久留在屏幕上，
    // 用户以为发不出去。现在：**一发送就开新会话**——清掉边界标记，
    // 分隔线随之消失（历史消息里那条边界记录仍保留，不会被抹掉）。
    final startingNewSession = _sessionEnded;
    _textController.clear();
    setState(() {
      _pendingImages.clear();
      if (startingNewSession) {
        _sessionEnded = false;
        _sessionEndedAt = null;
      }
    });
    if (images.isNotEmpty) {
      // 图已作为消息发出：文件归消息所有，输入区不再持有它们。
      // 多图一次发送 = N 条用户气泡 + **一条** AI 请求（控制器批量路径）。
      await _controller.sendImageBatch(images: images, caption: text);
    } else {
      await _controller.sendMessage(text);
    }
  }

  // ---- AI 聊天建议（2026-10-23 用户）------------------------------------
  //
  // 每条助手文本回复完成后，用**独立的一次模型调用**读这条回复，给出
  // 2–3 句用户口吻的短回复，渲染成气泡；点一下直接发送。失败静默
  // （建议是增强内容，不该在对话里弹错），每条消息只请求一次。

  void _maybeRequestSuggestions() {
    if (!mounted || _controller.isReplying) return;
    final service = widget.suggestionService;
    if (service == null) return;
    final messages = _controller.state.messages;
    for (final message in messages.reversed) {
      if (message.role != ConversationRole.assistant ||
          message.status != ConversationMessageStatus.sent ||
          message.isEditProposal ||
          message.text.trim().isEmpty) {
        continue;
      }
      // 自动催的中间气泡不渲染，别为它再发一次建议请求（否则每轮修改多打
      // 一次模型，结果却没有任何界面承载）。
      if (_controller.isHiddenRetryBubble(message.id)) return;
      if (_suggestionRequested.contains(message.id)) return;
      _suggestionRequested.add(message.id);
      unawaited(_requestSuggestions(message));
      return;
    }
  }

  Future<void> _requestSuggestions(ConversationMessage message) async {
    final service = widget.suggestionService;
    if (service == null) return;
    final buffer = StringBuffer();
    try {
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'chat-suggestion-${message.id}',
                role: ConversationRole.user,
                text:
                    'AI 刚才回复了：\n${message.text}\n\n'
                    '请给出用户接下来最可能想发的 2–3 句短回复。',
                createdAt: (widget.clock?.nowUtc() ?? DateTime.now().toUtc()),
              ),
            ],
            onProgress: buffer.write,
            systemContext:
                '你是对话建议器。只输出 2–3 行，每行一句用户口吻的短回复'
                '（不超过 20 字），不要编号、不要引号、不要解释。',
          )
          .drain<void>();
    } on Object {
      return;
    }
    final lines = buffer
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (!mounted || lines.isEmpty) return;
    setState(() => _suggestions[message.id] = lines);
  }

  void _sendSuggestion(String text) {
    if (_controller.isReplying) {
      _prefillInput(text);
      return;
    }
    _textController.text = text;
    unawaited(_sendCurrent());
  }

  // ---- 图片 ------------------------------------------------------------

  /// 「+」= 三选弹层（2026-10-31 用户：点加号不再直接进相册）：
  /// 拍照 / 从相册选择 / 发送文件（txt·md·csv）。
  /// 【2026-11-02 用户】不要说明行：三个按钮横向排列，名称在图标下方。
  Future<void> _onAddAttachment() async {
    final choice = await AppSheet.show<_AttachmentSource>(
      context,
      title: '添加内容',
      // 用弹层内 Builder 的 context 关自己：`AppSheet` 挂在根导航器上，
      // 页面 context 会 pop 到分支导航器（2026-11-02 候选黑屏同源问题）。
      // 【2026-11-07 用户（附截图）】三项做成**等宽大方块、占满一行**：
      // 浅灰底、圆角、图标在上、两个字在下。原来三个圆图标被 Spacer 推开，
      // 中间空得厉害。
      content: Builder(
        builder: (sheetContext) => Row(
          children: [
            for (var i = 0; i < _AttachmentSource.values.length; i++) ...[
              if (i > 0) const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: _buildAttachmentTile(
                  sheetContext,
                  _AttachmentSource.values[i],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AttachmentSource.camera:
        await _pickImage(MealImageSource.camera);
      case _AttachmentSource.gallery:
        await _pickImage(MealImageSource.gallery);
      case _AttachmentSource.file:
        await _pickFile();
    }
  }

  /// 单个附件入口：**等宽大方块**（浅灰底 16 圆角，图标 28 在上、两个字
  /// 在下），整块可点（命中盒远大于 44dp）。
  ///
  /// 【2026-11-07 用户（附截图）】原实现是圆形图标块 + Spacer 推开，
  /// 三个入口之间空得厉害；现在按截图做成三等分卡片。
  Widget _buildAttachmentTile(
    BuildContext sheetContext,
    _AttachmentSource source,
  ) {
    final c = context.lf;
    final (label, icon) = switch (source) {
      _AttachmentSource.camera => ('拍照', Icons.photo_camera_outlined),
      _AttachmentSource.gallery => ('相册', Icons.photo_outlined),
      // 用户要求**两个字**：原「发送文件」缩成「文件」。
      _AttachmentSource.file => ('文件', Icons.description_outlined),
    };
    void close() => Navigator.of(sheetContext).pop(source);
    return Semantics(
      button: true,
      label: label,
      onTap: close,
      child: InkWell(
        key: Key('attachment-pick-${source.name}'),
        onTap: close,
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceLarge),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: c.foreground),
              const SizedBox(height: LfDimens.spaceSmall),
              Text(
                label,
                style: LfText.body.copyWith(
                  color: c.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送文件（一期 txt / md / csv）：读出文本预填进输入框——文件名注明，
  /// 内容随消息正文发给 AI。超长内容截断并如实标注（prompt 预算保护）。
  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'csv'],
      );
      if (!mounted) return;
      final path = file?.path;
      if (path == null || file == null) return; // 用户取消
      final raw = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final body = raw.length > _maxFileChars
          ? '${raw.substring(0, _maxFileChars)}\n…（文件过长，已截断）'
          : raw;
      _prefillInput('【文件：${file.name}】\n$body');
    } on Object {
      if (mounted) _snack('读取文件失败，请重试。');
    }
  }

  Future<void> _pickImage(MealImageSource source) async {
    final picker = widget.chatImagePicker;
    if (picker == null) {
      _snack('图片选择尚未配置。');
      return;
    }
    if (_pickingImage) return;
    final remaining = _maxPendingImages - _pendingImages.length;
    if (remaining <= 0) {
      _snack('最多先选 $_maxPendingImages 张；发送几张后再加。');
      return;
    }
    setState(() => _pickingImage = true);
    try {
      // 【2026-11-07】支持多选的选图器：先拿路径立刻上屏，后台再处理。
      if (picker.supportsFastPreview) {
        final refs = await picker.pickRefs(source: source, limit: remaining);
        if (!mounted) return;
        if (refs.isEmpty) return; // 用户取消
        _addPendingImages(picker, refs.take(remaining).toList());
        return;
      }
      // 老链路（选图器不支持多选/路径）：仍等处理完成再上屏。
      final picked = await picker.pick(source: source);
      if (!mounted) {
        if (picked != null) await _safeDiscard(picker, picked);
        return;
      }
      if (picked == null) return;
      setState(() => _pendingImages.add(picked));
    } on MealImageFailure catch (failure) {
      if (mounted) _snack(failure.message);
    } on ChatImageFailure catch (failure) {
      if (mounted) _snack(failure.message);
    } on Object {
      if (mounted) _snack('选择图片失败，请重试。');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  /// 把选中的原图**立刻**挂成预览，再在后台换成文档目录副本。
  void _addPendingImages(
    PickChatImage picker,
    List<SelectedMealImageRef> refs,
  ) {
    if (refs.isEmpty) return;
    final placeholders = [
      for (final ref in refs)
        ChatImage(
          // 系统相册选出来的原路径 App 本来就可读；预览条按 cover 固定 56dp，
          // 不依赖宽高，所以这里先给 0。
          path: ref.path,
          fileName: ref.fileName,
          width: 0,
          height: 0,
        ),
    ];
    // 先把「处理中」登记上，再通知 UI：发送键在这一帧就该是灰的。
    for (final ref in refs) {
      _materializing[ref.path] = _materializeOne(picker, ref);
    }
    setState(() => _pendingImages.addAll(placeholders));
  }

  /// 处理单张（缩放/重编码/写副本），完成后把占位换成副本并放行发送键。
  Future<void> _materializeOne(
    PickChatImage picker,
    SelectedMealImageRef ref,
  ) async {
    try {
      final image = await picker.materialize(ref);
      if (!mounted) {
        unawaited(_safeDiscard(picker, image));
        return;
      }
      final index = _pendingImages.indexWhere((item) => item.path == ref.path);
      if (index < 0) {
        // 处理期间用户已经移除了这张：副本没人要，删掉。
        unawaited(_safeDiscard(picker, image));
        return;
      }
      setState(() => _pendingImages[index] = image);
    } on Object catch (error) {
      if (!mounted) return;
      // 处理失败：撤掉这张占位并如实说（不留一张发不出去的预览）。
      setState(() {
        _pendingImages.removeWhere((item) => item.path == ref.path);
      });
      _snack(
        error is MealImageFailure
            ? error.message
            : error is ChatImageFailure
            ? error.message
            : '这张图片读不出来，已移除。',
      );
    } finally {
      // 无论成败都要从「处理中」摘掉，按钮才会恢复可点。
      if (mounted) {
        // 注意：`Map<String, Future>.remove` 返回被移除的 Future，
        // 不能写成 `setState(() => ...)`（setState 禁止回调返回 Future）。
        setState(() {
          _materializing.remove(ref.path);
        });
      } else {
        _materializing.remove(ref.path);
      }
    }
  }

  /// 发送前等后台处理落地：聊天记录里要存**文档目录副本**，不能存系统缓存
  /// 里的临时路径（重启或系统清理后图就没了）。
  Future<void> _awaitPendingImages() async {
    if (_materializing.isEmpty) return;
    await Future.wait(_materializing.values.toList());
  }

  Future<void> _safeDiscard(PickChatImage picker, ChatImage image) async {
    try {
      await picker.discard(image);
    } on Object {
      // 删除失败不影响主流程：残留文件由「清除全部本地数据」兜底。
    }
  }

  Future<void> _removePendingImage([int index = 0]) async {
    if (index < 0 || index >= _pendingImages.length) return;
    final image = _pendingImages.removeAt(index);
    // 还在后台处理的占位：从登记表里摘掉，完成回调会发现原件已不在列表，
    // 直接丢弃副本（不留孤儿文件）。
    _materializing.remove(image.path);
    setState(() {});
    final picker = widget.chatImagePicker;
    if (picker != null) await _safeDiscard(picker, image);
  }

  // ---- 快捷 chip -------------------------------------------------------

  /// 把一句话预填进输入框并聚焦：**不替用户发送**（发送键在用户手里）。
  void _prefillInput(String text) {
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
    _inputFocus.requestFocus();
  }

  void _onChipTap(ChatQuickChip chip) {
    switch (chip) {
      case ChatQuickChip.remainingToday:
        // `RV4-R16` 方案 A：**本地算**，不发模型、不入库。
        unawaited(_showRemainingToday());
      case ChatQuickChip.logMeal:
        // 复用 B3 的 launcher：不离开对话页、不新增写路径。
        unawaited(_logMealFromChat());
      case ChatQuickChip.aiCreate:
        final open = widget.onOpenAiCreate;
        if (open == null) {
          _snack('AI 创作尚未配置。');
          return;
        }
        open();
    }
  }

  /// 「今天还剩多少」（`RV4-R16` 方案 A，chip 1）：**纯本地计算**，不发模型。
  ///
  /// 数据源与今日页热量卡/营养分析卡**同一份口径**（`watchNutritionForDate`
  /// 的 `consumed` + `target`），不另算一套。结果作为一条**本地**助手消息
  /// 插进对话流（不入库、不计费）。
  ///
  /// 三条边界如实说（不美化）：
  /// 1. 没有目标（`daily_targets` 空）→ 「还没设营养目标」+ 去设置；
  /// 2. 今日 0 条记录 → 「今天还没记任何东西，剩余 = 全天目标」；
  /// 3. 某项已超 → 明说「已超 N」而不是显示负数。
  Future<void> _showRemainingToday() async {
    final meals = widget.mealRepository;
    if (meals == null) {
      _snack('餐食仓储尚未配置，算不了剩余。');
      return;
    }
    final summary = await meals
        .watchNutritionForDate(formatLocalDate(DateTime.now()))
        .first;
    if (!mounted) return;
    final consumed = summary.consumed;
    final target = summary.target;
    final buffer = StringBuffer();
    if (target == null) {
      buffer.write(
        '还没设营养目标；去「我的 → 目标」设一个我才能算差额。'
        '（今天已摄入 ${consumed.kcal.round()} kcal）',
      );
    } else {
      if (consumed.kcal <= 0) {
        buffer.write(
          '今天还没记任何东西，剩余 = 全天目标 '
          '${target.calorieMinKcal.round()}–${target.calorieMaxKcal.round()} kcal。',
        );
      } else {
        final remainLow = target.calorieMinKcal - consumed.kcal;
        final remainHigh = target.calorieMaxKcal - consumed.kcal;
        if (remainHigh < 0) {
          buffer.write(
            '今天已摄入 ${consumed.kcal.round()} / 目标 '
            '${target.calorieMinKcal.round()}–${target.calorieMaxKcal.round()} '
            'kcal（已超 ${(-remainHigh).round()} kcal）',
          );
        } else {
          buffer.write(
            '今天还剩 ${remainLow.clamp(0, double.infinity).round()}–'
            '${remainHigh.round()} kcal（已摄入 ${consumed.kcal.round()} / 目标 '
            '${target.calorieMinKcal.round()}–${target.calorieMaxKcal.round()} kcal）',
          );
        }
      }
      buffer.write('\n');
      buffer.write(
        _macroLine(
          '蛋白质',
          consumed.proteinGrams,
          target.proteinMinGrams,
          target.proteinMaxGrams,
        ),
      );
      buffer.write(' · ');
      buffer.write(
        _macroLine(
          '碳水',
          consumed.carbsGrams,
          target.carbsMinGrams,
          target.carbsMaxGrams,
        ),
      );
      buffer.write(' · ');
      buffer.write(
        _macroLine(
          '脂肪',
          consumed.fatGrams,
          target.fatMinGrams,
          target.fatMaxGrams,
        ),
      );
    }
    setState(() {
      _localResults.add((
        id: 'remaining-${DateTime.now().microsecondsSinceEpoch}',
        text: buffer.toString(),
      ));
    });
    _scrollToBottom();
  }

  /// 单项宏量：未到写「还差 N」，超出写「已超 N」（不给负数）。
  String _macroLine(String label, double consumed, double min, double max) {
    final missing = max - consumed;
    if (missing < 0) return '$label 已超 ${(-missing).round()}g';
    return '$label 还差 ${missing.round()}g';
  }

  /// 「记一餐」（chip 2）：复用 B3 的 launcher，**不离开对话页**。
  Future<void> _logMealFromChat() async {
    final foods = widget.foodRepository;
    final meals = widget.mealRepository;
    final add = widget.onAddDishToMeal;
    if (foods == null || meals == null) {
      _snack('餐食仓储尚未配置，记不了。');
      return;
    }
    await openMealRecordSheet(
      context,
      foods: foods,
      meals: meals,
      dishes: widget.dishLibraryRepository,
      addDish: add,
    );
  }

  // ---- 构建 ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 键盘收起时 = 底栏占位（shell 的 extendBody 覆盖层）；键盘弹起时
    // shell 已把 body 收缩到键盘上沿，该值为 0（见类注释）。
    final bottomGap = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          // 顶栏自己吃顶部叠层（docs/21 §5.8.5）；这里再套 SafeArea 会双倍。
          _header(context),
          Expanded(child: _chatArea(context)),
          if (widget.aiConnectivity case final monitor?)
            AiOfflineBanner(monitor: monitor),
          _inputSection(context, bottomGap: bottomGap),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return LfTopBar(
      // 2026-10-23 用户：「删『AI 助手』下方描述并对齐图标」——副题整条
      // 退场，标题回到单行，32dp 吉祥物与单行标题垂直居中（`LfTopBar` 的
      // Row 默认 center；有副题时它对齐的是两行文本块）。
      title: 'AI 助手',
      titleKey: const Key('ai-chat-title'),
      backKey: const Key('ai-chat-back'),
      onBack: widget.onBack ?? () => Navigator.maybePop(context),
      titleLeading: const AiMascotAvatar(size: 32),
      actions: [
        // `RV4-P2-04/05` / D4（2026-10-24 已裁决）：原来的两枚按钮
        // （「从对话提炼记忆」/「结束本次会话」）**合并为一枚**
        // 「结束本次对话」：
        //   · 语义上它们是同一件事（都要「结算这段对话」）；
        //   · 区别只有「是否受自动提炼开关约束」——裁决明确：**显式动作不受
        //     开关约束**（开关只管后台自动跑）；
        //   · 合并后结束会有可见变化（分隔线 + 输入框占位），不再是「点了
        //     只弹一条 snackbar」。
        // 按钮任何时候可点（2026-10-23 用户口径），回复中先 `cancel()`。
        if (widget.aiMemoryRepository != null ||
            widget.memoryExtraction != null)
          LfIconButton(
            key: const Key('ai-chat-end-session'),
            icon: Icons.task_alt,
            iconSize: 20,
            semanticLabel: '结束本次对话',
            onPressed: () => unawaited(_endConversation()),
          ),
        // `RV4-P2-06`：清除聊天记录（破坏性操作 → 二次确认 + 如实报数）。
        // 只在接了仓储时渲染（不给点了没反应的按钮）。
        if (widget.conversationHistory != null)
          LfIconButton(
            key: const Key('ai-chat-clear-history'),
            icon: Icons.delete_sweep_outlined,
            iconSize: 20,
            semanticLabel: '清除聊天记录',
            onPressed: () => unawaited(_confirmClearHistory()),
          ),
        // 用户头像（docs/32 §3 D9）：**可点 → 我的**；有图显图、无图首字、
        // 无昵称「Fit」。AI 吉祥物头像（左侧）不是用户头像，不动。
        Semantics(
          button: widget.onOpenProfile != null,
          label: '我的',
          child: GestureDetector(
            key: const Key('ai-chat-user-avatar'),
            onTap: widget.onOpenProfile,
            behavior: HitTestBehavior.opaque,
            child: UserAvatar(
              displayName: widget.identity?.displayName,
              avatarPath: widget.identity?.avatarPath,
              size: 36,
              imageKey: const Key('ai-chat-avatar-image'),
              initialKey: const Key('ai-chat-avatar-initial'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chatArea(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        // `RV4-R16`：本地算出来的结果卡也是「对话里有东西」——不能因为
        // `messages` 还空着就整页退回欢迎区（那样 chip 点了看不到任何反应）。
        if (state.messages.isEmpty && _localResults.isEmpty) {
          // 读取失败 ≠ 没有记录（docs/21 §5.8.1）：先给错误态，别拿空态冒充。
          final loadError = state.loadError;
          if (loadError != null) return _historyError(loadError);
          return _welcome();
        }
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            LfDimens.spaceLarge,
            LfDimens.spaceLarge,
            LfDimens.spaceLarge,
            LfDimens.spaceSmall,
          ),
          children: [
            // `RV4-P2-04`：提炼进行中的忙态行（不是消息，不入库）。
            if (_extractingMemory)
              const Padding(
                key: Key('ai-chat-extracting'),
                padding: EdgeInsets.only(bottom: LfDimens.spaceMedium),
                child: AiMessageRow(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: LfDimens.spaceSmall),
                      Flexible(child: Text('正在从这段对话提炼记忆…')),
                    ],
                  ),
                ),
              ),
            for (var index = 0; index < state.messages.length; index++)
              // 【2026-11-02 用户：AI 自动接话停不下来】自动催信封的中间气泡
              // 不渲染——否则一次修改请求会多出两段重复的「我准备记…」。
              if (!_controller.isHiddenRetryBubble(state.messages[index].id))
                _messageItem(index, state.messages[index]),
            // `RV4-P2-05`：会话边界（不是消息，不入库）。
            for (final result in _localResults)
              Padding(
                key: Key('ai-chat-remaining-card'),
                padding: const EdgeInsets.only(bottom: LfDimens.spaceMedium),
                child: AiMessageRow(
                  child: AiMessageBubble(
                    key: Key('ai-chat-remaining-${result.id}'),
                    text: result.text,
                    markdown: false,
                    onLongPress: () => unawaited(_copyMessage(result.text)),
                  ),
                ),
              ),
            if (_sessionEnded && _sessionEndedAt != null)
              Padding(
                key: const Key('ai-chat-session-ended'),
                padding: const EdgeInsets.symmetric(
                  vertical: LfDimens.spaceMedium,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LfDimens.spaceSmall,
                      ),
                      child: Text(
                        '本次对话已结束 · '
                        '${_sessionEndedAt!.hour.toString().padLeft(2, '0')}:'
                        '${_sessionEndedAt!.minute.toString().padLeft(2, '0')}',
                        style: LfText.caption.copyWith(
                          color: context.lf.mutedForeground,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// 提炼记忆（docs/38 v2）：把最近对话拼成转录 → 让模型给候选 →
  /// 弹层展示 → **用户点选才写库**（source=extracted）。任何失败都如实
  /// 提示；候选保存时的重复/敏感拒绝也如实显示。
  Future<void> _extractMemories() async {
    final repository = widget.aiMemoryRepository;
    if (repository == null) return;
    if (_extractingMemory) {
      AppSnackBar.show(context, '正在提炼，请稍候。', icon: AppSnackBar.infoIcon);
      return;
    }
    // 2026-10-23 用户：「随时可点、点击即主动结算」——回复中先停止当前流，
    // 再拿已经落屏的内容提炼；不把按钮做成灰的让人猜「什么时候能点」。
    if (_controller.isReplying) {
      await _controller.cancel();
      if (!mounted) return;
    }
    final messages = _controller.state.messages;
    final usable = messages
        .where(
          (message) =>
              message.text.trim().isNotEmpty &&
              message.status != ConversationMessageStatus.error,
        )
        .toList(growable: false);
    if (usable.isEmpty) {
      AppSnackBar.show(context, '还没有可提炼的对话内容。');
      return;
    }
    final transcript = [
      for (final message in usable.take(40))
        '${message.role == ConversationRole.user ? 'U' : 'A'}: '
            '${message.text.trim()}',
    ].join('\n');
    setState(() => _extractingMemory = true);
    final AiMemoryCandidateParse parse;
    try {
      final service = widget.service;
      if (service == null) {
        AppSnackBar.show(context, 'AI 未配置，无法提炼记忆。');
        return;
      }
      final buffer = StringBuffer();
      // sendMessage 返回的是流（本页其它调用走 await for）；提炼只关心
      // 最终全文，用 fold 收完即得。
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'memory-extract-${DateTime.now().microsecondsSinceEpoch}',
                role: ConversationRole.user,
                text: aiMemoryExtractPrompt(transcript),
                createdAt: DateTime.now().toUtc(),
              ),
            ],
            onProgress: buffer.write,
            systemContext: null,
          )
          .drain<void>();
      parse = parseAiMemoryCandidates(buffer.toString());
    } on Object {
      if (!mounted) return;
      AppSnackBar.show(context, '提炼失败，请稍后重试。');
      return;
    } finally {
      if (mounted) setState(() => _extractingMemory = false);
    }
    if (!mounted) return;
    if (parse.candidates.isEmpty) {
      AppSnackBar.show(
        context,
        parse.reply.isEmpty ? '这段对话没有值得记住的内容。' : parse.reply,
      );
      return;
    }
    // 【需求 16b（2026-10-25）】已有记忆的候选**不再列出来**：同一次会话里
    // 再次提炼时，模型往往把上一轮已保存的又说一遍——候选层照原样列出来，
    // 用户看到的是「我明明存过了，它又问一遍」。
    //
    // 判据用 `normalizeAiMemoryText`（仓储写入侧防重的同一把尺子）：
    // **完全相同**的文本被滤掉；**相近但不同**的仍保留——那正是「要不要更新
    // 旧记忆」的有效提示，滤掉它等于把功能做没了。
    final existing = await repository.listActive();
    if (!mounted) return;
    final known = {
      for (final memory in existing) normalizeAiMemoryText(memory.text),
    };
    final fresh = [
      for (final candidate in parse.candidates)
        if (!known.contains(normalizeAiMemoryText(candidate.text))) candidate,
    ];
    if (fresh.isEmpty) {
      AppSnackBar.show(
        context,
        '这次提炼出的 ${parse.candidates.length} 条都已经在记忆里了。',
        icon: AppSnackBar.infoIcon,
      );
      return;
    }
    final saved = await _showMemoryCandidateSheet(
      AiMemoryCandidateParse(reply: parse.reply, candidates: fresh),
      repository,
    );
    if (!mounted) return;
    if (saved > 0) {
      AppSnackBar.show(context, '已保存 $saved 条记忆。');
    }
  }

  /// 「结束本次对话」（`RV4-P2-05` / D4）：**合并**原「提炼记忆」与「结束会话」。
  ///
  /// 行为（按 D4 裁决）：
  /// 1. 回复中先 `cancel()`（沿用）；
  /// 2. 消息不足 [kMemoryExtractionMinMessages] → 如实提示（沿用）；
  /// 3. 已是结束态 → 幂等提示，**不重复入队 / 不再画第二条分隔线**；
  /// 4. 有记忆仓储就走**同步候选层**（`_showMemoryCandidateSheet`，保存即写），
  ///    **不看「自动提炼」开关**——显式动作不受开关约束；
  /// 5. 写会话边界（`_sessionEnded` / `_sessionEndedAt`）→ 消息尾部画分隔线
  ///    「本次对话已结束 · HH:mm」，输入框占位改为「开始新对话…」。
  Future<void> _endConversation() async {
    if (_sessionEnded) {
      AppSnackBar.show(context, '本次对话已结束。', icon: AppSnackBar.infoIcon);
      return;
    }
    final memoryRepository = widget.aiMemoryRepository;
    final queue = widget.memoryExtraction;
    if (memoryRepository == null && queue == null) return;
    if (_controller.isReplying) {
      await _controller.cancel();
      if (!mounted) return;
    }
    final messages = _controller.state.messages;
    final usable = [
      for (final message in messages)
        if (message.text.trim().isNotEmpty &&
            message.status != ConversationMessageStatus.error)
          message,
    ];
    // 太短时**不画分割线、不进入已结束态**（不变量，不是本轮新行为）。
    //
    // 【2026-10-25 复核更正】我先前在这里写过「原代码太短时照常画分割线、
    // 置已结束态」，**那是错的**：这条路径原本就 `return`，既有测试
    // 「消息不足 6 条：如实提示、不画分隔线」在本轮之前一直是绿的，
    // 证明原行为如此。
    //
    // 本处**唯一**的改动是**文案**：原文「先多聊几句」没说清「对话会怎样」，
    // 用户会以为「点了结束 → 没提炼 → 卡住了」。现在明确说「没法提炼记忆；
    // 对话会继续保持，可以接着聊」——如实告知状态，不改任何控制流。
    if (usable.length < kMemoryExtractionMinMessages) {
      AppSnackBar.show(
        context,
        '这段对话还太短（至少 $kMemoryExtractionMinMessages 条），没法提炼记忆；'
        '对话会继续保持，可以接着聊。',
        icon: AppSnackBar.errorIcon,
      );
      return;
    }

    // 同步候选层：保存即写（显式动作不看开关）。
    if (memoryRepository != null) {
      await _extractMemories();
      if (!mounted) return;
    } else if (queue != null) {
      // 没接记忆仓储（只接了队列）：退回入队，结果如实上屏。
      final conversationId =
          '${ConversationMessageRepository.defaultSessionId}:${usable.last.id}';
      final result = await queue.endSession(
        conversationId: conversationId,
        messages: messages,
        // D4：显式动作不受「自动提炼」开关约束。
        explicit: true,
      );
      if (!mounted) return;
      AppSnackBar.show(
        context,
        result.message,
        icon: result.ok ? AppSnackBar.successIcon : AppSnackBar.errorIcon,
      );
    }

    if (!mounted) return;
    setState(() {
      _sessionEnded = true;
      _sessionEndedAt = DateTime.now();
    });
    _scrollToBottom();
  }

  /// 清除聊天记录（`RV4-P2-06`）：二次确认 → 清库 + 清聊天图片副本 → 报数。
  ///
  /// 破坏性操作的纪律：不静默、不「删了就说删了」——确认框写清后果，
  /// 完成后如实说清除了多少条。取消则一条不少。
  Future<void> _confirmClearHistory() async {
    final history = widget.conversationHistory;
    if (history == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('ai-chat-clear-history-confirm'),
        title: const Text('清除全部聊天记录？'),
        content: const Text('这会删除本机上的全部对话消息与聊天图片副本，无法恢复。'),
        // 统一走设计系统件（`unified_card_button_audit_test` 的冻结预算：
        // 业务页面不许新增裸 TextButton）。
        actions: [
          LfTextButton(
            key: const Key('ai-chat-clear-history-cancel'),
            label: '取消',
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          LfTextButton(
            key: const Key('ai-chat-clear-history-confirm-ok'),
            label: '清除',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await _controller.clearHistory();
    // 清空后消息已不在列表，定位用的 GlobalKey 一并释放（否则长会话里
    // 这些 key 会一直挂在页面上）。
    _messageKeys.clear();
    // 待发预览也要清：正在后台处理的占位被移除后，完成回调会把副本丢掉
    // （不留孤儿）；已就绪的占位随聊天清空一并退场。
    _pendingImages.clear();
    _materializing.clear();
    if (mounted) setState(() {});
    // 聊天图片副本一并清（聊天副本本来就是「随清全清」语义）。
    try {
      await widget.chatImageStore?.clearAll();
    } on Object {
      // 图片清不掉不该谎报「全清了」——下面按实际条数说，并补一句提示。
      if (!mounted) return;
      AppSnackBar.show(
        context,
        '已清除 $removed 条消息，但聊天图片副本未能全部清掉。',
        icon: AppSnackBar.errorIcon,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _sessionEnded = false;
      _sessionEndedAt = null;
    });
    AppSnackBar.show(
      context,
      removed == 0 ? '没有可清除的聊天记录。' : '已清除 $removed 条消息。',
      icon: AppSnackBar.successIcon,
    );
  }

  /// 候选弹层：复选 + 编辑框；返回保存条数。
  Future<int> _showMemoryCandidateSheet(
    AiMemoryCandidateParse parse,
    AiMemoryRepository repository,
  ) async {
    final selected = <int>{for (var i = 0; i < parse.candidates.length; i++) i};
    final saved = await showModalBottomSheet<int>(
      context: context,
      // docs/21 附录 D8：shell 是 extendBody 结构，默认分支导航器会把
      // 弹层最后一行压到贴底栏下面（保存钮点不到）。
      useRootNavigator: true,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + sheetBottomInset(sheetContext),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parse.reply.isEmpty ? '从这段对话提炼的记忆' : parse.reply,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: LfDimens.spaceSmall),
                for (var index = 0; index < parse.candidates.length; index++)
                  CheckboxListTile(
                    key: Key('ai-memory-candidate-$index'),
                    value: selected.contains(index),
                    title: Text(parse.candidates[index].text),
                    subtitle: Text(
                      '${parse.candidates[index].kind.label} · '
                      '${parse.candidates[index].domain.label}',
                    ),
                    onChanged: (value) => setSheetState(() {
                      final checked = value ?? false;
                      if (checked) {
                        selected.add(index);
                      } else {
                        selected.remove(index);
                      }
                    }),
                  ),
                const SizedBox(height: LfDimens.spaceSmall),
                // 16a（2026-10-25 用户：记忆弹窗里那两件贴在一起）：
                // 两枚 `Expanded` 原来直接相邻 ⇒ 水平间距 **0dp**，两个按钮
                // 连成一块，用户看到的是「一整条灰带」。插 `spaceSmallPlus`
                // 让「取消」与「保存所选」各自成立（判据：间距 ≥ 10dp）。
                Row(
                  children: [
                    Expanded(
                      child: LfTextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(0),
                        label: '取消',
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceSmallPlus),
                    Expanded(
                      child: LfPrimaryButton(
                        key: const Key('ai-memory-candidate-save'),
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                var count = 0;
                                for (final index in selected) {
                                  final candidate = parse.candidates[index];
                                  try {
                                    await repository.remember(
                                      text: candidate.text,
                                      kind: candidate.kind,
                                      domain: candidate.domain,
                                      tags: candidate.tags,
                                      source: 'extracted',
                                    );
                                    count++;
                                  } on AiMemoryException {
                                    // 单条被拒（重复/敏感）不中断其余；
                                    // 成功数如实汇报。
                                  }
                                }
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop(count);
                                }
                              },
                        label: '保存所选',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return saved ?? 0;
  }

  Widget _historyError(String message) {
    final c = context.lf;
    return Center(
      key: const Key('ai-chat-history-error'),
      child: Padding(
        padding: const EdgeInsets.all(LfDimens.spaceLargePlus),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: LfText.body.copyWith(color: c.mutedForeground),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            // 空/错误态的行动 = §3.8 B6 主色文字按钮（2026-10-03 用户裁决）。
            LfTextButton(
              key: const Key('ai-chat-history-retry'),
              label: '重试',
              onPressed: () => unawaited(_controller.loadHistory()),
            ),
          ],
        ),
      ),
    );
  }

  /// 空对话的欢迎区：吉祥物打招呼 + 功能卡（只展示能力，无 CTA）。
  ///
  /// 原先功能卡底部还有「立即查看专属理想方案」主按钮与「点击查看」徽章，
  /// 两者都跳去食谱计划；该功能在 docs/28 的 W4 整族下线后无可跳转的页面，
  /// 按 §6.8「不做补偿入口」一并移除（卡片只留 3 个特性列）。
  Widget _welcome() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceLarge,
        LfDimens.spaceLarge,
        LfDimens.spaceLarge,
        LfDimens.spaceSmall,
      ),
      children: [
        KeyedSubtree(
          key: const Key('ai-chat-welcome'),
          child: Column(
            children: [
              AiMessageRow(
                child: AiMessageBubble(
                  text: _greeting,
                  onLongPress: () => unawaited(_copyMessage(_greeting)),
                ),
              ),
              const SizedBox(height: LfDimens.spaceLarge),
              // Round7 逐页对账批次 4：A `app.js:207` 的两条 starter 行
              // （「今天晚餐怎么搭配？」/「制定轻量训练计划」）。
              // 行为与「我可以吃吗」chip 同一条诚实口径：**只预填、不替用户
              // 发送**（A 的 starter 是对话起点，真正的发送键在用户手里）。
              for (final (starterKey, starterText, starterIcon) in const [
                (
                  Key('ai-chat-starter-dinner'),
                  '今天晚餐怎么搭配？',
                  Icons.restaurant_menu,
                ),
                (
                  Key('ai-chat-starter-plan'),
                  '制定轻量训练计划',
                  Icons.fitness_center_outlined,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
                  child: AiStarterRow(
                    rowKey: starterKey,
                    icon: starterIcon,
                    text: starterText,
                    onTap: () => _prefillInput(starterText),
                  ),
                ),
              const SizedBox(height: LfDimens.spaceSmall),
              // 2026-10-16：功能卡从「消息列里的大块」改成**三张小卡**（用户：
              // 「功能卡片太丑，要做成小卡片」）。小卡形态下消息列的可用宽
              // （减去 36dp 头像与间距后只剩 ≈89dp/张）放不下 A 的 5 字标签，
              // 会折成「三餐控热/量」——故这一块**铺满内容宽**，不挂在
              // `AiMessageRow` 里；无 CTA 的纪律不变。
              const FeatureCardMessage(
                features: [
                  (Icons.local_fire_department_outlined, '三餐控热量'),
                  (Icons.my_location, '个性化定制'),
                  (Icons.pie_chart_outline, '营养巧分配'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messageItem(int index, ConversationMessage message) {
    // 挂卡后 ensureVisible 的定位键（按消息 id，列表重排也稳定）。
    final key = _messageKeys.putIfAbsent(message.id, GlobalKey.new);
    return KeyedSubtree(
      key: key,
      child: Padding(
        key: Key('ai-chat-message-$index'),
        padding: const EdgeInsets.only(bottom: LfDimens.spaceLarge),
        child: switch (message.role) {
          ConversationRole.assistant => _assistantItem(index, message),
          ConversationRole.user => _userItem(index, message),
        },
      ),
    );
  }

  Widget _assistantItem(int index, ConversationMessage message) {
    if (message.status == ConversationMessageStatus.sending &&
        message.text.isEmpty) {
      return const AiMessageRow(child: TypingIndicator());
    }
    if (message.isEditProposal) {
      // docs/23 §5：reply 气泡在前，编辑卡（逐条提议+结果）随后。
      return AiMessageRow(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiMessageBubble(
              text: message.text,
              onLongPress: () => unawaited(_copyMessage(message.text)),
            ),
            const SizedBox(height: 8),
            ChatEditCard(
              index: index,
              message: message,
              onApply: () => unawaited(_controller.applyEdits(message.id)),
              onApplyRows: (rowIndexes) => unawaited(
                _controller.applyEdits(message.id, rowIndexes: rowIndexes),
              ),
              onDismiss: () => unawaited(_controller.dismissEdits(message.id)),
              onApplySuggestion: (suggestionIndex) => unawaited(
                _controller.applySuggestion(message.id, suggestionIndex),
              ),
              onRepair: (repair) =>
                  unawaited(_openEditRepair(message.id, repair)),
              onRepairAtRow: (rowIndex, repair) => unawaited(
                _openEditRepair(message.id, repair, rowIndex: rowIndex),
              ),
            ),
          ],
        ),
      );
    }
    if (message.status == ConversationMessageStatus.sending &&
        _looksLikeEnvelope(message.text)) {
      // 模型在按协议输出 JSON：把原始 JSON 藏起来，只说正在整理方案
      // （docs/23 §1 流式显示规则）。解析失败会在完成时回退为普通文本。
      return const AiMessageRow(child: TypingIndicator());
    }
    if (message.status == ConversationMessageStatus.error) {
      return AiMessageRow(
        child: Semantics(
          button: true,
          label: '重试发送',
          child: GestureDetector(
            key: Key('btn-retry-$index'),
            onTap: () => unawaited(_controller.retryLast()),
            child: AiMessageBubble(text: _errorText(message)),
          ),
        ),
      );
    }
    // 2026-10-16：这条是「用户要改数据、模型却只回文字」的残留态
    // （自动催过一次仍未给信封）⇒ 气泡下给一枚手动催的入口，别让对话
    // 停在死文字上（用户原话：「而不是空回文字」）。新模式下这个入口恒为
    // false（needsEnvelopeRetry 直接短路），换成「生成应用卡片」按钮。
    final offerRetry =
        !_controller.isReplying && _controller.needsEnvelopeRetry(message.id);
    return AiMessageRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiMessageBubble(
            text: message.text,
            onLongPress: () => unawaited(_copyMessage(message.text)),
            // docs/66 §6.1：按钮在气泡内部底行、右对齐（仅新模式）。
            footer: widget.manualCardGeneration
                ? _generationFooter(index, message)
                : null,
          ),
          // 2026-10-23 用户：「要 AI 聊天建议（2–3 个建议气泡点击直接发送）」。
          if (_suggestions[message.id] case final suggestions?
              when suggestions.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Wrap(
              spacing: LfDimens.spaceSmall,
              runSpacing: LfDimens.spaceSmall,
              children: [
                for (var i = 0; i < suggestions.length; i++)
                  _SuggestionBubble(
                    key: Key('ai-chat-suggestion-$index-$i'),
                    text: suggestions[i],
                    onTap: () => _sendSuggestion(suggestions[i]),
                  ),
              ],
            ),
          ],
          if (offerRetry) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            // 【2026-10-29（R-7 兜底卡）】词条升级为卡片：残留态必须足够显眼
            // （用户原话「AI 总是不给我应用卡片」），且把模型原话亮出来供核对。
            _EnvelopeFallbackCard(
              key: Key('envelope-fallback-card-$index'),
              replyText: message.text,
              onRetry: () => unawaited(_controller.requestEnvelope(message.id)),
              onDismiss: () => _controller.dismissEnvelopeRetry(message.id),
            ),
          ],
        ],
      ),
    );
  }

  /// 是否像 chat-edit 信封的开头（docs/23 §1）：只看首个非空白字符，
  /// 宁可把「恰好以 { 开头的普通回复」藏到完成后再显示，也不把 JSON
  /// 半截亮给用户。完成后的文本由 controller 落定，不受这里影响。
  bool _looksLikeEnvelope(String text) => text.trim().startsWith('{');

  /// 「生成应用卡片」的**气泡内底行**（docs/66 §3.1 / §6.2）。
  ///
  /// 只由 `_assistantItem` 的普通文本分支传入（仅新模式）。状态机：
  /// * `idle` — 有资格（`canGenerateCard`）时显示按钮 + 可选「尚未写入」提示；
  /// * `generating` — 三点 loader + 「生成中…」 + 「取消」（不用
  ///   `LfTextButton(busy:)`，那会把 label 换成三点 loader）；
  /// * `empty` — 「重新检查」 + muted 原因；
  /// * `failed` — retryable 时「重试生成」 + error 原因；不可重试只有原因
  ///   （重试也不会变好，假按钮反而误导）。
  ///
  /// 只监听控制器独立的 `cardGeneration` notifier（§6.4）：生成状态不触发
  /// 页面「滚到底」，按钮那一小块单独重建。
  Widget _generationFooter(int index, ConversationMessage message) {
    return ValueListenableBuilder<Map<String, CardGenerationState>>(
      valueListenable: _controller.cardGeneration,
      builder: (context, states, _) {
        final state =
            states[message.id] ??
            const CardGenerationState(CardGenerationPhase.idle);
        final c = context.lf;
        final messageId = message.id;

        Widget statusWrap(Widget child) => Container(
          key: Key('ai-chat-card-generation-status-$index'),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: child,
        );

        Widget hint() {
          if (!_claimsUnwrittenChanges(message)) return const SizedBox.shrink();
          return Padding(
            key: Key('ai-chat-not-written-$index'),
            padding: const EdgeInsets.only(right: LfDimens.spaceXSmall),
            child: Text(
              '尚未写入',
              style: LfText.micro.copyWith(color: c.mutedForeground),
            ),
          );
        }

        final Widget? action;
        if (state.phase == CardGenerationPhase.generating) {
          action = statusWrap(
            Semantics(
              liveRegion: true,
              label: '正在生成应用卡片',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 三点 loader 的自然宽度约 21px（3 点 + 2 间隔）；SizedBox
                  // 只钳高度，宽度留足，避免窄盒溢出。
                  SizedBox(width: 24, height: 14, child: AppButtonDotsLoader()),
                  const SizedBox(width: LfDimens.spaceXSmall),
                  Text(
                    '生成中…',
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                  LfTextButton(
                    key: Key('ai-chat-generate-card-$index-cancel'),
                    label: '取消',
                    onPressed: () =>
                        _controller.cancelCardGeneration(messageId),
                  ),
                ],
              ),
            ),
          );
        } else if (state.phase == CardGenerationPhase.empty) {
          action = statusWrap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                LfTextButton(
                  key: Key('ai-chat-generate-card-$index'),
                  label: '重新检查',
                  onPressed: () =>
                      unawaited(_controller.generateEditCard(messageId)),
                ),
                Text(
                  state.message ?? '这条回复没有可应用的操作',
                  textAlign: TextAlign.end,
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          );
        } else if (state.phase == CardGenerationPhase.failed) {
          action = statusWrap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.retryable)
                  LfTextButton(
                    key: Key('ai-chat-generate-card-$index'),
                    label: '重试生成',
                    onPressed: () =>
                        unawaited(_controller.generateEditCard(messageId)),
                  ),
                Text(
                  state.message ?? '生成失败，请重试。',
                  textAlign: TextAlign.end,
                  style: LfText.micro.copyWith(color: c.errorText),
                ),
              ],
            ),
          );
        } else {
          // idle：只有有资格的消息才有入口（页面不自己拼条件，只调控制器）。
          if (!_controller.canGenerateCard(messageId)) {
            return const SizedBox.shrink();
          }
          // 【2026-11-09 审查修复】原来是 Row：2.0 字号下「尚未写入」提示
          // 与按钮的自然宽超出气泡可用宽（360dp 溢 39px、320dp 溢 79px）。
          // Wrap 让提示退到按钮上面一行，1.0 字号下观感与原来一致。
          action = Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: LfDimens.spaceXSmall,
            runSpacing: 2,
            children: [
              hint(),
              LfTextButton(
                key: Key('ai-chat-generate-card-$index'),
                label: '生成应用卡片',
                icon: Icons.auto_awesome_outlined,
                onPressed: () =>
                    unawaited(_controller.generateEditCard(messageId)),
              ),
            ],
          );
        }
        return action;
      },
    );
  }

  /// §5.5 的「假完成态」判定：用户这条像修改请求（或带图）、回复命中
  /// `replyClaimsChanges`、且这一轮没有卡 ⇒ 按钮旁显示中性提示「尚未写入」。
  /// 这是诚实性保护：不改内容、不触发任何生成或写库。
  bool _claimsUnwrittenChanges(ConversationMessage message) {
    if (!replyClaimsChanges(message.text)) return false;
    final messages = _controller.state.messages;
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index <= 0) return false;
    for (var i = index - 1; i >= 0; i--) {
      final user = messages[i];
      if (user.role != ConversationRole.user) continue;
      return user.kind == ConversationMessageKind.image ||
          looksLikeModificationRequest(user.textForRequest);
    }
    return false;
  }

  Widget _userItem(int index, ConversationMessage message) {
    switch (message.kind) {
      case ConversationMessageKind.image:
        // 【2026-10-31 用户重定稿】只留图：原始宽高比 contain 完整显示，
        // 无放大角标/文件名药丸/对勾徽章；点击打开全屏查看（root navigator）。
        return ImageMessage(
          key: Key('ai-chat-image-$index'),
          image: _imageWidget(message),
          caption: message.text,
          onZoom: () => _openImageZoom(index, message),
        );
      case ConversationMessageKind.voice:
        // P10（需求 36）：语音输入已删，但历史库里的旧语音消息（D8 保留
        // kind 与 durationMs 列）仍要能读回来。波形气泡件已删，这里按
        // 「转写文本就是消息正文」降级成普通用户气泡——那正是它发出时的
        // 真实内容，时长信息不再是可交互的东西。
        return UserMessageBubble(
          key: Key('ai-chat-voice-$index'),
          text: message.text,
          onLongPress: () => unawaited(_copyMessage(message.text)),
        );
      case ConversationMessageKind.text:
      case ConversationMessageKind.editProposal:
        // 编辑卡只出现在助手侧（仓储/控制器都保证）；防御性当纯文本。
        return UserMessageBubble(
          text: message.text,
          onLongPress: () => unawaited(_copyMessage(message.text)),
        );
    }
  }

  Widget _imageWidget(ConversationMessage message) {
    final path = message.imagePath;
    // 文件被系统/用户清掉时如实给「已清理」占位，而不是留一块假缩略图。
    if (path == null || !File(path).existsSync()) return _missingImage();
    // 【2026-10-31 用户重定稿】原始宽高比完整显示（contain，不裁剪）——
    // 外层的 ConstrainedBox 限宽 232 / 高 280，比例由图片自身决定。
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _missingImage(),
    );
  }

  /// 全屏看大图（需求 3）。
  ///
  /// 【为什么用 `useRootNavigator: true`】对话页挂在 shell 的**分支导航器**上，
  /// 分支导航器的高度不含底栏 ⇒ 用默认导航器打开的全屏层会被底栏切掉一截
  /// （与 `_showMemoryCandidateSheet` 同一理由，docs/21 附录 D8）。
  ///
  /// 【关掉后再点还能开】每次点击都新建一个路由，没有缓存层——图片是只读的，
  /// 不持有任何状态，重复打开不会串味。
  Future<void> _openImageZoom(int index, ConversationMessage message) {
    final path = message.imagePath;
    final hasImage = path != null && File(path).existsSync();
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: LfColors.scrimSolid,
      builder: (dialogContext) => ChatImageZoomView(
        key: Key('ai-chat-image-zoom-$index'),
        caption: message.text,
        // 大图与缩略图用**同一个 builder**：两处不会出现「缩略有图、大图空白」
        // 的分叉；文件期间被清掉时大图也如实说「图片已清理」。
        image: hasImage
            ? Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _missingImage(),
              )
            : _missingImage(),
      ),
    );
  }

  Widget _missingImage() {
    final c = context.lf;
    return ColoredBox(
      color: c.muted,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: LfDimens.iconLg,
            color: c.mutedForeground,
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text('图片已清理', style: LfText.micro.copyWith(color: c.mutedForeground)),
        ],
      ),
    );
  }

  String _errorText(ConversationMessage message) {
    final text = message.text.trim();
    return text.isEmpty ? '发送失败，点击重试。' : '$text\n\n发送失败，点击重试。';
  }

  /// 【2026-10-31 用户：缩略图需要能点击放大】全屏查看**待发送**图片。
  ///
  /// 【2026-11-09 全量审查】原来这里是第二个全屏实现（`Dialog.fullscreen`
  /// + `Colors.black` + 裸 `TextStyle`），与对话里看大图的 `ChatImageZoomView`
  /// 各写一套：关闭键用 `Positioned(top: 32)` 没有 `SafeArea`（刘海/状态栏
  /// 高的机器上会压到系统区域）、配色绕过 `LfColors.scrimSolid`、且没有
  /// `Semantics`（读屏只念到一个无名可点节点）。现在复用同一个共享件。
  Future<void> _showImageFull(ChatImage image) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: LfColors.scrimSolid,
      builder: (dialogContext) => ChatImageZoomView(
        key: const Key('ai-chat-attachment-zoom'),
        image: Image.file(
          File(image.path),
          errorBuilder: (_, _, _) => _missingImage(),
        ),
      ),
    );
  }

  Widget _inputSection(BuildContext context, {required double bottomGap}) {
    final c = context.lf;
    final hasImage = _pendingImages.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 【2026-10-31 用户：预览条在最顶】待发图悬浮在快捷 chips 之上
          // （整个输入区最顶），不是夹在 chips 和输入框中间。
          if (hasImage)
            ImagePreviewStrip(
              images: _pendingImages,
              onRemove: (index) => unawaited(_removePendingImage(index)),
              // 【2026-10-31 用户：缩略图需要能点击放大】点缩略图开全屏查看。
              onInspect: (image) => unawaited(_showImageFull(image)),
              thumbnailBuilder: (image, index) => Image.file(
                File(image.path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _missingImage(),
              ),
            ),
          ChatQuickChips(onChipTap: _onChipTap),
          // 必须在监听回调里现读：写在外层 build 会把值「定住」，
          // 回复结束后发送键就再也换不回来（阶段 G 测试抓到的缺陷）。
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => ChatInputBar(
              controller: _textController,
              focusNode: _inputFocus,
              onSendText: (_) => unawaited(_sendCurrent()),
              onPickImage: () => unawaited(_onAddAttachment()),
              sending: _controller.isReplying,
              // 图片副本还没就绪 ⇒ 发送键置灰（就绪后自动恢复）。
              canSend: !_imagesPreparing,
              onStop: () => unawaited(_controller.cancel()),
              // `RV4-P2-05`：会话结束后占位改为「开始新对话…」（可见变化之一）。
              hintText: _sessionEnded ? '开始新对话…' : null,
            ),
          ),
          // P10（需求 35）：底部免责声明已删（原 ChatDisclaimer 挂载点）。
        ],
      ),
    );
  }
}

/// 「+」三选弹层的选项（2026-10-31）。
enum _AttachmentSource { camera, gallery, file }

/// 文件预填进正文的字符上限（超出截断并如实标注）。
const int _maxFileChars = 20000;

/// 「AI 聊天建议」气泡（2026-10-23 用户）：一句用户口吻的短回复，点一下
/// 直接发送。形态与快捷 chip 同级（描边胶囊），但内容是**这一轮回复**的
/// 后续说法，不是固定的起手模板。
class _SuggestionBubble extends StatelessWidget {
  const _SuggestionBubble({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 14,
              // 2026-11-09 审查：白卡上 primary 只有 2.36:1，图标用文字档。
              color: LfColors.mintText(Theme.of(context).brightness),
            ),
            const SizedBox(width: LfDimens.spaceTiny),
            Flexible(
              child: Text(
                text,
                style: LfText.captionStrong.copyWith(color: c.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 兜底卡（2026-10-29，R-7：AI 声称改了数据却没给出可执行指令）。
///
/// 【为什么是卡不是词条】词条（描边胶囊）太不显眼，用户的实测体感是「AI 总是
/// 不给我应用卡片」。残留态必须**一眼看到 + 一键处理**：卡片里亮出模型原话
/// （供核对它声称了什么）、「重新生成可应用指令」走既有的加强催链路
/// （`requestEnvelope` → 拿到真信封 → 常规应用卡 → 用户核对后才写库），
/// 「知道了」收卡（`dismissEnvelopeRetry`，防重启复活）。
class _EnvelopeFallbackCard extends StatelessWidget {
  const _EnvelopeFallbackCard({
    super.key,
    required this.replyText,
    required this.onRetry,
    required this.onDismiss,
  });

  final String replyText;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      padding: const EdgeInsets.all(LfDimens.spaceMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: c.warningText),
              const SizedBox(width: LfDimens.spaceXSmall),
              Expanded(
                child: Text(
                  // 2026-11-03：模型并不一定说过「改好了」（也可能只是反问
                  // 要不要生成 / 引用了不存在的应用卡），标题改为中性描述，
                  // 不再替它编一句它没说过的话。
                  '这条回复没有可应用的操作',
                  style: LfText.bodyStrong.copyWith(color: c.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text(
            '这段回复里没有可应用的指令（点「应用」才能真正记上）。'
            'AI 的原话如下：',
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text(
            replyText.trim(),
            key: const Key('envelope-fallback-reply'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: LfText.caption.copyWith(color: c.foreground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          // 【2026-11-09 审查修复】Row + spaceBetween 在窄屏/大字号下会把
          // 「重新生成可应用指令」挤出卡外（自然宽约 384dp @2.0×）。
          // OverflowBar 放不下时自动竖排。
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: LfDimens.spaceSmall,
            overflowSpacing: LfDimens.spaceXSmall,
            children: [
              LfTextButton(
                key: const Key('envelope-fallback-dismiss'),
                label: '知道了',
                onPressed: onDismiss,
              ),
              LfConfirmButton(
                key: const Key('envelope-fallback-retry'),
                label: '重新生成可应用指令',
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 断网提示条（2026-10-21 裁决 D-2）。
///
/// 只在 `AiConnectivityMonitor` 有「刚连不上」的证据时出现；一次成功请求
/// 即消失。文案必须说清「什么不能用、什么照常」，不把本地功能一起说坏。
class AiOfflineBanner extends StatelessWidget {
  const AiOfflineBanner({super.key, required this.monitor});

  final AiConnectivityMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        if (!monitor.isOffline) return const SizedBox.shrink();
        return Container(
          key: const Key('ai-chat-offline-note'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: c.muted,
          child: Text(
            '当前连不上网络：AI 回复不可用；本地记录、搜索与记忆写入不受影响。',
            style: LfText.caption.copyWith(color: c.cardForeground),
          ),
        );
      },
    );
  }
}
