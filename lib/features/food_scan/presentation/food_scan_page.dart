import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/app_haptics.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/fixed_bottom_primary_action.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/food_scan/application/meal_intake_comparison.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/application/scan_conversation_intent.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/food_scan/presentation/chat_message_ui.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_widgets.dart';
import 'package:localfit_ai/features/food_scan/presentation/scan_candidate_editor.dart';

class FoodScanPage extends StatefulWidget {
  const FoodScanPage({
    this.prepareMealImage,
    this.recognizeConfirmedMealImage,
    this.resolveMealScanCandidates,
    this.mealRepository,
    this.measurementRepository,
    this.loadMealRecognitionDisclosure,
    this.now,
    this.onOpenManualEntry,
    this.onOpenSettings,
    this.onBackToNutrition,
    this.onOpenWorkoutPlan,
    this.initialImage,
    this.autoStartCamera = false,
    super.key,
  });

  final PrepareMealImage? prepareMealImage;
  final RecognizeConfirmedMealImage? recognizeConfirmedMealImage;
  final ResolveMealScanCandidates? resolveMealScanCandidates;
  final MealRepository? mealRepository;

  /// 对话式「记录体重」（docs/21 §5.4 能力 1）。null＝未接线，
  /// 该意图会回一句「体重记录尚未就绪」且不写库。
  final MeasurementRepository? measurementRepository;

  /// 发送披露（docs/21 §5.4「发送披露」）：把「发给谁」写实——
  /// 目的地主机 / Base URL / 模型。null＝未接线，只显示通用一行文案。
  final LoadMealRecognitionDisclosure? loadMealRecognitionDisclosure;

  final DateTime? now;
  final VoidCallback? onOpenManualEntry;
  final VoidCallback? onOpenSettings;

  /// 从拍照页返回来源饮食状态（docs/21 §3 `back-nutrition`）。
  final VoidCallback? onBackToNutrition;

  /// 对话式「创建训练计划」（docs/01 §5 能力 2）：跳到 AI 工作台的
  /// `workout-plan` 任务。null＝未接线，回一句引导。
  final VoidCallback? onOpenWorkoutPlan;

  /// P10（需求 37，拍照直通）：进页即开相机并对拿到的图自动开始识别。
  ///
  /// `true` 只该出现在「AI 对话 `cta-photo-scan` 带图进入」这一条路径——
  /// 页面自己弹相机（不再有落地菜单），用户拍照确认后无需再点一次
  /// 「使用 AI 分析餐食」。相机被取消（用户返回）时回到普通空态。
  final bool autoStartCamera;

  /// P10（需求 37）：带图进入时页面持有的那张图（拍照在**上一页**完成：
  /// AI 对话先开相机拍好，再 push 本页并自动开始识别）。
  final PreparedMealImage? initialImage;

  @override
  State<FoodScanPage> createState() => _FoodScanPageState();
}

class _FoodScanPageState extends State<FoodScanPage> {
  PreparedMealImage? _image;
  MealEstimateDraft? _draft;
  MealScanCandidateDraft? _candidateDraft;
  PreparedMealImage? _leftoverImage;
  MealScanCandidateDraft? _leftoverCandidateDraft;
  MealRecognitionCancellationToken? _recognitionCancellation;
  String? _error;
  String? _successMessage;
  bool _processing = false;
  bool _recognizing = false;
  bool _saving = false;
  bool _savedAwaitingCleanup = false;
  bool _suggestSettings = false;

  /// 是否处于「候选编辑」面（docs/21 §5.4：`cta-edit-items` 进入的二级
  /// 流程）。false = 只读结果视图（设计稿的主面），true = 候选编辑器。
  bool _editing = false;

  /// 对话式指令的输入与回复（docs/21 §5.4）。
  ///
  /// 与图片识别共用同一条时间线（`_conversationMessages`），所以这里只存
  /// 文本；不做「聊天记录」持久化——这些回复是当轮交互反馈，不是本地事实。
  final TextEditingController _commandController = TextEditingController();
  String? _commandReply;
  bool _commandBusy = false;

  /// 发送披露内容（目的地主机/模型）；null＝未接线或尚未加载完。
  MealRecognitionDisclosure? _disclosure;

  /// 上次读到披露时所处的可见性。用于识别「分支重新可见」：
  /// `AppRoutes.foodScan` 是 `StatefulShellRoute.indexedStack` 的保活分支，
  /// 切到「我的」改完 AI 配置再切回来时页面**不重建**（`initState` 不再跑），
  /// 只有 `Visibility.of` 会回调 `didChangeDependencies`。若不在那时重读，
  /// 披露会一直停在旧配置（或首次未配置时的通用兜底）。
  bool _wasVisible = true;

  /// 在途读取的序号：切回时可能已有一次读取在路上，用序号丢弃过期结果。
  int _disclosureRequest = 0;

  /// 直通自动识别只跑一次（拍照取消/失败后不循环拉相机）。
  bool _autoStarted = false;

  bool get _interactionBusy =>
      _processing || _recognizing || _saving || _commandBusy;

  bool get _recognitionAvailable =>
      _image != null && widget.recognizeConfirmedMealImage != null;

  @override
  void initState() {
    super.initState();
    // 带图直通进入（P10 需求 37）：图在上一页已经准备好，这里只接住。
    _image = widget.initialImage;
    final prepare = widget.prepareMealImage;
    if (prepare != null) {
      prepare.initialize().catchError((_) {});
      // 恢复丢失数据只在「没有直通图」时做：直通图优先于历史恢复。
      if (_image == null) _recover(prepare);
    }
    _loadDisclosure();
    if (widget.autoStartCamera) {
      // 帧后启动：先画一帧预览（直通已带图）或空态，再触发识别，避免
      // initState 里直接改状态引发的「build 期间 setState」断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoStarted) _startDirectRecognition();
      });
    }
  }

  /// 带图直通的自动识别（P10）：图已在手，直接开始分析。
  void _startDirectRecognition() {
    _autoStarted = true;
    if (_image == null) return;
    unawaited(_analyze());
  }

  /// 取图后立即识别（与用户点 `scan-analyze` 等价，只是省掉那一下点击）。
  Future<void> _selectAndAnalyze(MealImageSource source) async {
    await _select(source);
    if (!mounted || _image == null) return; // 取消或失败：停在空态，不硬闯
    await _analyze();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 注册对 `IndexedStack`（go_router 分支容器）可见性的依赖，分支切回时
    // 本回调再次触发 ⇒ 重读配置，避免披露停在陈旧值。
    final isVisible = Visibility.of(context);
    if (isVisible && !_wasVisible) _loadDisclosure();
    _wasVisible = isVisible;
  }

  /// 发送披露文案：读到配置时写明目的地与模型，否则退回通用一行。
  String _disclosureText() {
    final disclosure = _disclosure;
    if (disclosure == null) {
      return '点击即把当前图片发送给你配置的 AI 服务（供应商与模型见设置）。';
    }
    return '点击即把当前图片发送给你配置的 AI 服务：'
        '${disclosure.destinationHost} · ${disclosure.model}。';
  }

  /// 读取发送披露（目的地主机/模型）。
  ///
  /// 失败**不上屏错误**：披露是辅助信息，读不到时退回通用一行文案即可，
  /// 不该因为「设置里没填 AI 配置」就在拍照页头顶挂个红字。真正需要配置
  /// 的时机是点「使用 AI 分析餐食」，那时由 `_recognize` 报可行动错误。
  ///
  /// 读取失败时**退回通用文案而非保留旧值**：披露的全部意义是如实告知
  /// 「发给谁」，写一个可能已经改掉的主机名比不写更糟——模糊但诚实优于
  /// 精确但可能失实。
  Future<void> _loadDisclosure() async {
    final load = widget.loadMealRecognitionDisclosure;
    if (load == null) return;
    final request = ++_disclosureRequest;
    MealRecognitionDisclosure? disclosure;
    try {
      disclosure = await load();
    } on AppFailure {
      disclosure = null;
    } catch (_) {
      disclosure = null;
    }
    if (mounted && request == _disclosureRequest) {
      setState(() => _disclosure = disclosure);
    }
  }

  @override
  void dispose() {
    _recognitionCancellation?.cancel();
    _commandController.dispose();
    final image = _image;
    if (image != null && !_saving && !_savedAwaitingCleanup) {
      widget.prepareMealImage?.discard(image).catchError((_) {});
    }
    final leftoverImage = _leftoverImage;
    if (leftoverImage != null && !_saving && !_savedAwaitingCleanup) {
      widget.prepareMealImage?.discard(leftoverImage).catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.prepareMealImage != null;
    final candidateDraft = _candidateDraft;
    // 内联编辑面在屏时，页级固定 CTA 让位：两者是**同一个动作**
    // （`_showSaveConfirmation`），同时可见就是两个按钮一件事。
    final inlineEditorVisible = _editing || _leftoverCandidateDraft != null;
    final c = context.lf;
    return Scaffold(
      // 顶栏用 LfTopBar（docs/21 §3.6 / §5.4）：36dp 圆形 muted 钮 +
      // 左对齐标题 + 底部分隔线。旧 AppBar 的居中标题与主题色图标不符新设计。
      appBar: LfTopBar(
        title: '拍照识餐',
        backKey: const Key('scan-back'),
        titleKey: const Key('scan-title'),
        // 回来源页（§4.2）。未接线时不接管返回，走 Navigator.maybePop。
        onBack: widget.onBackToNutrition,
        actions: [
          LfCircleIconButton(
            key: const Key('cta-rescan'),
            icon: Icons.refresh,
            tooltip: '重新拍摄',
            onPressed: !_interactionBusy && !_savedAwaitingCleanup
                ? _discardAll
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          // 本页是**推入式二级页**，不带底栏（docs/21 §6.2 裁决 6 记录了对
          // 设计稿的有意偏离：设计稿含 nav 块但没给任何槽打 active 标记）。
          // 底部留白给固定 CTA；用 padding 而不是末尾塞 SizedBox——后者会
          // 成为全页最深的渲染叶子。
          padding: const EdgeInsets.fromLTRB(
            LfDimens.pagePadding,
            LfDimens.pagePadding,
            LfDimens.pagePadding,
            LfDimens.navReservedSpace,
          ),
          children: [
            // 对话式状态行（docs/21 §5.4）：把「AI 正在分析 / 分析失败」
            // 也按对话气泡呈现，与下方卡片同一条时间线。只在有状态时出现。
            ..._conversationMessages(),
            if (_processing)
              const ScanProgressCard(
                key: Key('scan-processing'),
                message: '正在本机处理图片…',
              )
            else if (_recognizing)
              ScanRecognitionProgressCard(
                image: _image,
                onCancel: _cancelRecognition,
              )
            else if (_image != null)
              ScanPreviewCard(
                image: _image!,
                onDiscard: _discard,
                discardEnabled: !_interactionBusy,
              )
            else
              // P10（需求 37，D12）：落地屏（空态插画 + 拍摄/相册两钮 +
              // 未配置提示）整块删除。深链兜底 = 空态也给「拍摄」主按钮
              // （唯一入口，直接开相机）；相册入口保留在 AI 对话的图片按钮
              // 与剩余(餐前餐后)流程里。
              LfPrimaryButton(
                key: const Key('scan-camera'),
                label: '拍摄照片',
                icon: Icons.photo_camera_outlined,
                expand: true,
                onPressed:
                    configured && !_interactionBusy && !_savedAwaitingCleanup
                    ? () => _selectAndAnalyze(MealImageSource.camera)
                    : null,
              ),

            // 【分析按钮为什么在**所有**有图状态都留着】Round7 阶段 3 · 3-3
            // 审看曾把它当缺陷（在途时与卡内「正在发送并分析当前图片…」重复；
            // 有候选时再点会替换已改草稿）并试过隐藏，但**全量回归当场证伪**：
            // ① `food_scan_bruteforce_test` 的「识别在途连点 9 次不得重入」正是
            // 拿这枚按钮当探针；② 6 条视觉/流程判据（`scan_visual_components_test`
            // / `scan_design_spec_test` 几何探针）依赖它在有候选时仍可点（重分析）。
            // 隐藏它 = 削弱既有反重入探针 + 迁移 8 条在册判据 ⇒ 按「不放宽测试、
            // 不夹带语义变化」收回，登记为**待裁决**（文案/可见性），实现照旧。
            // 反重入本身由 `_interactionBusy` 保证（`_analyze` 入口先查它）。
            if (_image != null) ...[
              const SizedBox(height: LfDimens.spaceLarge),
              // 页面内主行动（§3.8 B1）；弹层/固定底栏的确认才是 B2
              // （本页的固定底部 CTA `cta-confirm-scan`）。
              LfPrimaryButton(
                key: const Key('scan-analyze'),
                // 裁决 ②（2026-10-15）：文案说它真实做的事——已有候选时再点
                // 会重发 AI 调用并替换当前草稿，那就写「重新分析」；无候选
                // （首次 / 失败 / 无结果）仍是「使用 AI 分析餐食」。
                label: candidateDraft == null ? '使用 AI 分析餐食' : '重新分析',
                icon: Icons.auto_awesome_outlined,
                expand: true,
                onPressed:
                    _recognitionAvailable &&
                        !_interactionBusy &&
                        !_savedAwaitingCleanup
                    ? _analyze
                    : null,
              ),
              if (!_recognitionAvailable) ...[
                const SizedBox(height: LfDimens.spaceSmall),
                Text(
                  '识别服务尚未配置；你仍可使用手动记餐。',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ],

            // 发送披露（docs/21 §5.4「发送披露」）：**常驻一行**，位置取
            // 「识别结果卡上方」这一档。弹层形式已被用户否决，内容不缩水——
            // 接了 `loadMealRecognitionDisclosure` 时写明「发给谁」。
            if (_image != null) ...[
              const SizedBox(height: LfDimens.spaceSmall),
              Text(
                _disclosureText(),
                key: const Key('scan-send-disclosure'),
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ],

            // ── 识别结果（只读主面 / 编辑面 二选一）─────────────────────
            //
            // §5.4 的交互写明「`cta-edit-items` 进入现有候选编辑器（保留，
            // 作为二级流程）」：结果卡是主面、编辑器是二级面。两面**互斥
            // 渲染**而不是上下叠放——同一份结果同时出现只读与可编辑两份
            // 就是重复信息，也会让页面长到要滚两屏。
            if (candidateDraft != null) ...[
              if (!_editing) ...[
                const SizedBox(height: LfDimens.cardGap),
                ScanResultOverviewCard(
                  candidates: candidateDraft.items,
                  onEditItems: _enterEditMode,
                  onOpenAnalysis: () => AppSheet.showCustom<void>(
                    context,
                    builder: (context) =>
                        ScanAnalysisSheet(draft: candidateDraft),
                  ),
                ),
                const SizedBox(height: LfDimens.cardGap),
                ScanIngredientsSection(candidates: candidateDraft.items),
                const SizedBox(height: LfDimens.cardGap),
                ScanNutritionBreakdown(candidates: candidateDraft.items),
                const SizedBox(height: LfDimens.cardGap),
                ScanAiAdviceCard(candidates: candidateDraft.items),
              ] else ...[
                const SizedBox(height: LfDimens.cardGap),
                ScanCandidateEditor(
                  draft: candidateDraft,
                  searchFoods: _searchLocalFoods,
                  onChanged: _updateCandidateDraft,
                  onCorrection: (index, corrected) => _updateCandidateDraft(
                    candidateDraft.replaceItem(index, corrected),
                  ),
                  onConfirm: _showSaveConfirmation,
                  confirmEnabled: _canSaveCandidate(candidateDraft),
                  saving: _saving,
                  onDismiss: _exitEditMode,
                ),
              ],
            ] else if (_draft case final draft?) ...[
              const SizedBox(height: LfDimens.cardGap),
              ScanDraftCard(draft: draft, onDismiss: _dismissDraft),
            ],

            // ── 剩余餐食（净摄入）────────────────────────────────────────
            // 设计稿未画到；按 §1.2 保留逻辑，收在识别结果之后。
            if (candidateDraft != null) ...[
              const SizedBox(height: LfDimens.cardGap),
              if (_leftoverImage == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: LfTextButton(
                    key: const Key('scan-leftover-gallery'),
                    label: '选择剩余餐食照片',
                    icon: Icons.photo_library_outlined,
                    onPressed: !_interactionBusy && !_savedAwaitingCleanup
                        ? () => _selectLeftover(MealImageSource.gallery)
                        : null,
                  ),
                ),
              if (_leftoverImage case final leftoverImage?) ...[
                if (_leftoverCandidateDraft == null) ...[
                  ScanPreviewCard(
                    // 与餐前预览卡区分：两张卡同屏，共用键会撞。
                    previewKey: const Key('scan-leftover-preview'),
                    image: leftoverImage,
                    onDiscard: _discardLeftover,
                    discardEnabled: !_interactionBusy,
                  ),
                  const SizedBox(height: LfDimens.spaceSmall),
                  SizedBox(
                    width: double.infinity,
                    // 可选子流程（净摄入）的触发走 B3 `muted`：不与主流程的
                    // B1「使用 AI 分析餐食」抢实心视觉（§3.8 无 outlined 档）。
                    child: LfPillButton(
                      key: const Key('scan-leftover-analyze'),
                      label: '分析剩余餐食',
                      icon: Icons.auto_awesome_outlined,
                      tone: LfPillTone.muted,
                      onPressed: !_interactionBusy && !_savedAwaitingCleanup
                          ? _analyzeLeftover
                          : null,
                    ),
                  ),
                ],
              ],
              if (_leftoverCandidateDraft case final leftoverDraft?) ...[
                // 克数约束与净摄入放在编辑器**之后**：编辑器保持在原位置，
                // 不把它挤出 ListView 的首屏构建范围。
                ScanCandidateEditor(
                  key: const Key('scan-leftover-editor'),
                  keyPrefix: 'scan-leftover-candidate',
                  draft: leftoverDraft,
                  searchFoods: _searchLocalFoods,
                  onChanged: _updateLeftoverCandidateDraft,
                  onCorrection: (index, corrected) =>
                      _updateLeftoverCandidateDraft(
                        leftoverDraft.replaceItem(index, corrected),
                      ),
                  onConfirm: _showSaveConfirmation,
                  confirmEnabled: _canSaveCandidate(leftoverDraft),
                  saving: _saving,
                  onDismiss: _dismissLeftoverDraft,
                  // 裁决 ④（2026-10-15）：缩短为「净摄入入账」——与主编辑器的
                  // 「确认入账」仍能区分，360dp 不再折两行。
                  confirmLabel: '净摄入入账',
                ),
                if (leftoverDraft.items.isNotEmpty) ...[
                  const SizedBox(height: LfDimens.spaceMedium),
                  _leftoverGramsGuidance(
                    draft: leftoverDraft,
                    aiEstimatedGrams:
                        leftoverDraft.items.first.estimate.estimatedGrams,
                  ),
                  const SizedBox(height: LfDimens.spaceSmall),
                  _leftoverNetIntakeSummary(
                    before: candidateDraft,
                    leftover: leftoverDraft,
                  ),
                ],
              ],
            ],

            if (_successMessage case final message?) ...[
              const SizedBox(height: LfDimens.cardGap),
              ScanSuccessCard(message: message),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: LfDimens.cardGap),
              ScanErrorCard(
                message: error,
                suggestSettings: _suggestSettings,
                onOpenSettings: widget.onOpenSettings,
                onManualEntry: widget.onOpenManualEntry,
              ),
            ],

            // ── 对话式指令栏（docs/21 §5.4）──────────────────────────────
            // 与拍照并列的第二类输入：图片走识别，文本走意图判别。
            // 设计稿未画到，按 §1.2 保留。
            const SizedBox(height: LfDimens.cardGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('scan-command-input'),
                    controller: _commandController,
                    enabled: !_savedAwaitingCleanup,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitCommand(),
                    decoration: const InputDecoration(
                      hintText: '说一句，如「记录今天体重 72.5kg」',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                // 输入栏发送 = §3.8 B4 的 `primary` 档（品牌实心圆、无阴影）。
                // 裸 `IconButton.filled` 走 M3 基线尺寸/圆角，主题管不到它。
                LfCircleIconButton(
                  key: const Key('scan-command-send'),
                  icon: Icons.send_outlined,
                  tooltip: '发送',
                  variant: LfCircleIconButtonVariant.primary,
                  onPressed: _interactionBusy || _savedAwaitingCleanup
                      ? null
                      : _submitCommand,
                ),
              ],
            ),
            if (widget.onOpenManualEntry != null) ...[
              const SizedBox(height: LfDimens.spaceSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: LfTextButton(
                  key: const Key('scan-manual-entry'),
                  label: '改为手动记餐',
                  icon: Icons.edit_note_outlined,
                  onPressed: _interactionBusy || _savedAwaitingCleanup
                      ? null
                      : widget.onOpenManualEntry,
                ),
              ),
            ],
          ],
        ),
      ),
      // 固定底部主操作（docs/21 §5.4 结构树末项 / §3.1
      // `FixedBottomPrimaryAction`）。用 `bottomNavigationBar` 而不是 Stack +
      // Positioned：前者在键盘弹起时随 viewInsets 上移，底部元素始终可点
      // （§5.8.3）。设计稿把它印在 `bottom: calc(80px + safe-area)`，那 80px
      // 是给它自己的底栏留的；本页无底栏（§6.2 裁决 6），故直接贴底。
      bottomNavigationBar: inlineEditorVisible
          ? null
          : FixedBottomPrimaryAction(
              child: _ConfirmScanButton(
                enabled:
                    candidateDraft != null &&
                    !_interactionBusy &&
                    !_savedAwaitingCleanup &&
                    _canSaveCandidate(candidateDraft),
                saving: _saving,
                onPressed: _showSaveConfirmation,
              ),
            ),
    );
  }

  /// 进入候选编辑面（`cta-edit-items`）。
  void _enterEditMode() => setState(() => _editing = true);

  /// 退出编辑面回到只读结果视图。
  ///
  /// **保留草案**（与旧行为「取消即丢弃识别结果、回到重拍」相反）：用户从
  /// 结果卡进来只是想改个克数，改完点「取消」不该把整份识别结果也丢掉——
  /// 丢了他得重新拍照识别。真要放弃照片仍可点照片上的丢弃键。
  void _exitEditMode() => setState(() => _editing = false);

  /// 对话式状态消息（docs/21 §5.4）：把 AI 侧的状态按气泡呈现，与候选
  /// 卡片同一条时间线。
  ///
  /// 只报「AI 在做什么/得到了什么」，**不复述错误卡片与成功卡片的正文**——
  /// 同一句话出现两遍既是噪音，也让读屏用户听到重复内容。具体错误文本与
  /// 重试/去设置入口仍由卡片承担。
  ///
  /// 「识别完成」这条只在既没出错也没保存成功时出现：出错时让用户去确认
  /// 结果、或已入账后还催确认，都是错误引导。
  List<Widget> _conversationMessages() {
    final messages = <Widget>[];
    if (_recognizing) {
      messages.add(
        const ChatMessageUI(
          key: Key('scan-chat-analyzing'),
          message: '正在分析这张照片，请稍候…',
          type: MessageType.loading,
        ),
      );
    } else if (_error == null &&
        _successMessage == null &&
        (_candidateDraft != null || _leftoverCandidateDraft != null)) {
      messages.add(
        const ChatMessageUI(
          key: Key('scan-chat-candidates'),
          message: '识别完成，请确认下面的结果；可以改克数或换成本地食物。',
          type: MessageType.ai,
        ),
      );
    }
    if (_commandBusy) {
      messages.add(
        const ChatMessageUI(
          key: Key('scan-chat-command-busy'),
          message: '正在处理这条指令…',
          type: MessageType.loading,
        ),
      );
    } else if (_commandReply case final reply?) {
      messages.add(
        ChatMessageUI(
          key: const Key('scan-chat-command-reply'),
          message: reply,
          type: MessageType.ai,
        ),
      );
    }
    if (messages.isEmpty) return const [];
    return [...messages, const SizedBox(height: 12)];
  }

  /// 对话式指令入口（docs/21 §5.4 能力 1–3）。
  ///
  /// 三条硬约束：
  /// 1. 意图判别走纯函数分类器，页面只做执行——判别逻辑可被穷举测试。
  /// 2. **认不出就不写**：`UnknownScanIntent` 只回引导文案，绝不猜参数。
  /// 3. 只有体重这一条会写库，且必须经 `MeasurementRepository` 的值域校验；
  ///    训练计划只是跳转入口，不在这里新建任何草案或事实。
  Future<void> _submitCommand() async {
    final input = _commandController.text.trim();
    if (input.isEmpty || _commandBusy) return;

    final intent = classifyScanIntent(input);
    setState(() {
      _commandBusy = true;
      _commandReply = null;
      _error = null;
      _suggestSettings = false;
    });

    late String reply;
    try {
      reply = switch (intent) {
        LogWeightIntent(:final weightKg, :final localDate) => await _logWeight(
          weightKg,
          localDate,
        ),
        CreateWorkoutPlanIntent() => _openWorkoutPlan(),
        UnknownScanIntent() =>
          '没听懂这句。你可以说「记录今天体重 72.5kg」，'
              '或说「帮我制定今天的训练计划」。',
      };
    } catch (_) {
      reply = '这条指令没能执行，请稍后再试。';
    }

    if (!mounted) return;
    setState(() {
      _commandBusy = false;
      _commandReply = reply;
    });
    // 成功后清空输入框，失败保留原文让用户能改一个数字重发。
    if (reply.startsWith('已记录')) _commandController.clear();
  }

  Future<String> _logWeight(double weightKg, String? explicitDate) async {
    final repository = widget.measurementRepository;
    if (repository == null) return '体重记录尚未就绪，请先在「我的」里完成建档。';
    final today = widget.now ?? DateTime.now();
    final localDate = explicitDate ?? formatLocalDate(today);
    // 仓储自己会再校验一次值域与建档状态；这里不预先吞掉异常，
    // 让它的错误信息原样回到对话里（异常只在此处转成文案，不做控制流）。
    await repository.saveManualWeight(localDate: localDate, weightKg: weightKg);
    final shown = weightKg == weightKg.roundToDouble()
        ? weightKg.toStringAsFixed(0)
        : weightKg.toStringAsFixed(1);
    return '已记录 $localDate 体重 $shown kg。';
  }

  String _openWorkoutPlan() {
    final open = widget.onOpenWorkoutPlan;
    if (open == null) return 'AI 训练计划尚未配置，请先在「我的」里设置 AI 服务。';
    open();
    return '正在打开 AI 训练计划…';
  }

  Future<void> _recover(PrepareMealImage prepare) async {
    try {
      final recovered = await prepare.recover();
      if (!mounted || recovered == null) return;
      setState(() => _image = recovered);
    } on MealImageFailure catch (error) {
      if (mounted) _setError(error.message);
    }
  }

  Future<void> _select(MealImageSource source) async {
    final prepare = widget.prepareMealImage!;
    setState(() {
      _processing = true;
      _error = null;
      _successMessage = null;
      _suggestSettings = false;
      _draft = null;
      _candidateDraft = null;
    });
    try {
      final prepared = await prepare.select(source, current: _image);
      if (!mounted || prepared == null) return;
      setState(() => _image = prepared);
    } on MealImageFailure catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) _setError('图片处理失败，请重新选择。');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _selectLeftover(MealImageSource source) async {
    final prepare = widget.prepareMealImage!;
    setState(() {
      _processing = true;
      _error = null;
      _successMessage = null;
      _suggestSettings = false;
      _leftoverCandidateDraft = null;
    });
    try {
      final prepared = await prepare.select(source, current: _leftoverImage);
      if (!mounted || prepared == null) return;
      setState(() => _leftoverImage = prepared);
    } on MealImageFailure catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) _setError('剩余餐食图片处理失败，请重新选择。');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _discardLeftover() async {
    final image = _leftoverImage;
    if (image == null || _interactionBusy) return;
    try {
      final prepare = widget.prepareMealImage;
      if (prepare == null) return;
      await prepare.discard(image);
      if (!mounted || _leftoverImage != image) return;
      setState(() {
        _leftoverImage = null;
        _leftoverCandidateDraft = null;
      });
    } on MealImageFailure catch (error) {
      if (mounted) _setError(error.message);
    }
  }

  Future<void> _analyzeLeftover() async {
    final image = _leftoverImage;
    final recognize = widget.recognizeConfirmedMealImage;
    if (image == null ||
        recognize == null ||
        _interactionBusy ||
        _savedAwaitingCleanup) {
      return;
    }

    final cancellation = MealRecognitionCancellationToken();
    setState(() {
      _recognitionCancellation = cancellation;
      _recognizing = true;
      _error = null;
      _successMessage = null;
      _suggestSettings = false;
      _leftoverCandidateDraft = null;
    });
    try {
      final draft = await recognize(image, cancellationToken: cancellation);
      if (!mounted ||
          _recognitionCancellation != cancellation ||
          cancellation.isCancelled ||
          _leftoverImage != image) {
        return;
      }
      final resolve = widget.resolveMealScanCandidates;
      if (resolve == null) return;
      final candidateDraft = await resolve(draft);
      if (!mounted ||
          _recognitionCancellation != cancellation ||
          cancellation.isCancelled ||
          _leftoverImage != image) {
        return;
      }
      setState(() => _leftoverCandidateDraft = candidateDraft);
    } on MealEstimateEmptyResult {
      if (mounted && _recognitionCancellation == cancellation) {
        _setError('剩余照片中未识别出可供确认的食物。');
      }
    } on AppFailure catch (failure) {
      if (!mounted || _recognitionCancellation != cancellation) return;
      if (failure is NetworkFailure &&
          failure.kind == NetworkFailureKind.cancelled) {
        return;
      }
      _setError(
        _safeFailureMessage(failure),
        settings: _needsSettings(failure),
      );
    } catch (_) {
      if (mounted && _recognitionCancellation == cancellation) {
        _setError('剩余餐食识别未能完成，请稍后重试。');
      }
    } finally {
      if (mounted && _recognitionCancellation == cancellation) {
        setState(() {
          _recognitionCancellation = null;
          _recognizing = false;
        });
      }
    }
  }

  Future<void> _discard() async {
    final image = _image;
    if (image == null || _interactionBusy) return;
    try {
      final prepare = widget.prepareMealImage;
      if (prepare == null) return;
      await prepare.discard(image);
      if (mounted) {
        setState(() {
          _image = null;
          _draft = null;
          _candidateDraft = null;
          _savedAwaitingCleanup = false;
          _error = null;
          _successMessage = null;
          _suggestSettings = false;
        });
      }
    } on MealImageFailure catch (error) {
      if (mounted) _setError(error.message);
    }
  }

  /// 点击即分析（用户反馈：去掉二次确认弹层）。发送范围以按钮下方一行
  /// 常驻披露文案表达（docs/21 §2.1 披露红线）。
  Future<void> _analyze() async {
    final image = _image;
    if (image == null || _interactionBusy || _savedAwaitingCleanup) return;
    await _recognize(image);
  }

  Future<void> _recognize(PreparedMealImage image) async {
    final recognize = widget.recognizeConfirmedMealImage;
    if (recognize == null || _recognizing || _image != image) return;

    final cancellation = MealRecognitionCancellationToken();
    setState(() {
      _recognitionCancellation = cancellation;
      _recognizing = true;
      _error = null;
      _successMessage = null;
      _suggestSettings = false;
      _draft = null;
      _candidateDraft = null;
      _savedAwaitingCleanup = false;
    });
    try {
      final draft = await recognize(image, cancellationToken: cancellation);
      if (!mounted ||
          _recognitionCancellation != cancellation ||
          cancellation.isCancelled) {
        return;
      }
      setState(() => _draft = draft);
      final resolve = widget.resolveMealScanCandidates;
      if (resolve == null) return;
      try {
        final candidateDraft = await resolve(draft);
        if (!mounted ||
            _recognitionCancellation != cancellation ||
            cancellation.isCancelled) {
          return;
        }
        setState(() => _candidateDraft = candidateDraft);
      } catch (_) {
        if (mounted && _recognitionCancellation == cancellation) {
          _setError('本地食物库暂时无法匹配候选；你仍可手动记餐。');
        }
      }
    } on MealEstimateEmptyResult {
      if (mounted && _recognitionCancellation == cancellation) {
        _setError('未识别出可供确认的食物。你可以调整照片后手动再次分析，或改为手动记餐。');
      }
    } on AppFailure catch (failure) {
      if (!mounted || _recognitionCancellation != cancellation) return;
      if (failure is NetworkFailure &&
          failure.kind == NetworkFailureKind.cancelled) {
        return;
      }
      _setError(
        _safeFailureMessage(failure),
        settings: _needsSettings(failure),
      );
    } catch (_) {
      if (mounted && _recognitionCancellation == cancellation) {
        _setError('识别请求未能完成，请稍后手动重试或改为手动记餐。');
      }
    } finally {
      if (mounted && _recognitionCancellation == cancellation) {
        setState(() {
          _recognitionCancellation = null;
          _recognizing = false;
        });
      }
    }
  }

  void _cancelRecognition() => _recognitionCancellation?.cancel();

  /// 丢弃所有（正在分析的图片 + 候选 + 剩余图片），回到 idle 态。
  Future<void> _discardAll() async {
    final prepare = widget.prepareMealImage;
    if (prepare == null) return;
    await prepare.discard(_image).catchError((_) {});
    setState(() {
      _image = null;
      _draft = null;
      _candidateDraft = null;
      _leftoverImage = null;
      _leftoverCandidateDraft = null;
      _error = null;
      _successMessage = null;
      _suggestSettings = false;
    });
  }

  Future<List<FoodRecord>> _searchLocalFoods(String query) async {
    final resolve = widget.resolveMealScanCandidates;
    if (resolve == null) return const [];
    return resolve.search(query);
  }

  bool _canSaveCandidate(MealScanCandidateDraft draft) =>
      widget.mealRepository != null &&
      draft.resolvedItems.isNotEmpty &&
      !draft.hasUnresolvedItems;

  Future<void> _showSaveConfirmation() async {
    final candidateDraft = _candidateDraft;
    final image = _image;
    if (candidateDraft == null ||
        image == null ||
        _interactionBusy ||
        !_canSaveCandidate(candidateDraft)) {
      return;
    }
    final leftoverDraft = _leftoverCandidateDraft;
    final leftoverImage = _leftoverImage;
    // 只选了剩余照片、还没点「分析剩余餐食」时草案仍是 null：此时若按餐前量入账，
    // 用户挂上的那张照片会被静默忽略、净摄入被高估。要求先分析或先丢弃。
    if (leftoverImage != null && leftoverDraft == null) {
      _setError('剩余餐食照片还没分析；请先点「分析剩余餐食」算出净摄入，或丢弃这张照片。');
      return;
    }
    // 剩余草案里有未匹配项时，`resolvedItems` 会静默丢掉那一项，剩余量被少算、
    // 净摄入被高估。宁可拦住让用户处理，也不拿算不全的剩余量凑一个偏大的数。
    if (leftoverDraft != null && leftoverDraft.hasUnresolvedItems) {
      _setError('剩余照片里还有未匹配本地食物的项，净摄入无法算全；请先为它们选择本地食物或移除该项。');
      return;
    }
    // 有剩余照片时按「餐前 − 剩余」计算净摄入；否则沿用餐前识别结果。
    final comparison = leftoverDraft == null
        ? null
        : MealIntakeComparison.compare(
            before: candidateDraft.resolvedItems,
            leftover: leftoverDraft.resolvedItems,
          );
    final items = comparison?.items ?? candidateDraft.resolvedItems;
    if (items.isEmpty) {
      // 到这里可能是「全部吃光（剩余=餐前）」也可能是「剩余量超过餐前量被按 0 扣掉」：
      // 两种原因的用户动作不同，先把计算过程给出的告警原样说清，再说结论。
      final reasons = comparison?.warnings ?? const <String>[];
      _setError(
        reasons.isEmpty
            ? '剩余量与餐前量相同，没有可入账的净摄入；请检查剩余照片或改为手动记餐。'
            : '${reasons.join('')}没有可入账的净摄入；请检查剩余照片或改为手动记餐。',
      );
      return;
    }
    final draft = MealDraft(
      localDate: formatLocalDate(widget.now ?? DateTime.now()),
      slot: candidateDraft.slot,
      notes: candidateDraft.notes,
      items: items,
    );
    final confirmed = await AppSheet.showCustom<bool>(
      context,
      builder: (context) => ScanMealSaveConfirmationDialog(
        draft: draft,
        warnings: comparison?.warnings ?? const [],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        _image != image ||
        _candidateDraft != candidateDraft ||
        _saving) {
      return;
    }
    await _saveCandidate(draft, image, leftoverImage: leftoverImage);
  }

  Future<void> _saveCandidate(
    MealDraft draft,
    PreparedMealImage image, {
    PreparedMealImage? leftoverImage,
  }) async {
    final repository = widget.mealRepository;
    if (repository == null || _saving || _image != image) return;
    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
      _suggestSettings = false;
    });
    try {
      await repository.create(draft, source: 'ai_scan');
    } on FormatException {
      if (mounted && _image == image) {
        setState(() {
          _saving = false;
          _error = '候选内容无效，请检查本地食物和克数后重试。';
        });
      }
      return;
    } catch (_) {
      if (mounted && _image == image) {
        setState(() {
          _saving = false;
          _error = '餐食未能保存到本机，请稍后重试。';
        });
      }
      return;
    }

    if (!mounted || _image != image) return;
    try {
      await widget.prepareMealImage?.discard(image);
      if (leftoverImage != null) {
        await widget.prepareMealImage?.discard(leftoverImage);
      }
      if (!mounted || _image != image) return;
      setState(() {
        _saving = false;
        _image = null;
        _draft = null;
        _candidateDraft = null;
        _leftoverImage = null;
        _leftoverCandidateDraft = null;
        _successMessage = '餐食已保存到本机，并已计入今日统计。';
        _savedAwaitingCleanup = false;
      });
      // docs/21 §3：确认成功 light 触觉。
      AppHaptics.light();
    } on MealImageFailure {
      if (!mounted || _image != image) return;
      setState(() {
        _saving = false;
        _draft = null;
        _candidateDraft = null;
        _leftoverImage = null;
        _leftoverCandidateDraft = null;
        _savedAwaitingCleanup = true;
        _error = '餐食已保存到本机，但临时图片尚未清理；请稍后重试丢弃。';
      });
    } catch (_) {
      if (!mounted || _image != image) return;
      setState(() {
        _saving = false;
        _draft = null;
        _candidateDraft = null;
        _leftoverImage = null;
        _leftoverCandidateDraft = null;
        _savedAwaitingCleanup = true;
        _error = '餐食已保存到本机，但临时图片尚未清理；请稍后重试丢弃。';
      });
    }
  }

  void _updateCandidateDraft(MealScanCandidateDraft value) {
    setState(() => _candidateDraft = value);
  }

  void _updateLeftoverCandidateDraft(MealScanCandidateDraft value) {
    setState(() => _leftoverCandidateDraft = value);
  }

  void _dismissLeftoverDraft() {
    setState(() => _leftoverCandidateDraft = null);
  }

  void _dismissDraft() => setState(() {
    _draft = null;
    _candidateDraft = null;
  });

  void _setError(String message, {bool settings = false}) {
    setState(() {
      _error = message;
      _suggestSettings = settings;
      _successMessage = null;
    });
  }

  /// 计算净摄入克数（餐前 - 剩余），用于 UI 展示。
  double _calculateNetIntake(
    MealScanCandidateDraft before,
    MealScanCandidateDraft leftover,
  ) {
    final comparison = MealIntakeComparison.compare(
      before: before.resolvedItems,
      leftover: leftover.resolvedItems,
    );
    return comparison.items.fold(0.0, (sum, item) => sum + item.grams);
  }

  /// 剩余克数的 AI 约束提示行（docs/07 §6.3 置信度 chip 同层级）。
  ///
  /// 克数本身由下方候选编辑器的步进/输入框唯一编辑，这里只做 AI 区间提示与
  /// 偏差提醒，避免同一克数出现两个可写控件导致显示与保存不一致。
  Widget _leftoverGramsGuidance({
    required MealScanCandidateDraft draft,
    required double aiEstimatedGrams,
  }) {
    final leftoverGrams = draft.items.fold(
      0.0,
      (sum, item) => sum + item.grams,
    );
    final deviation = leftoverGrams - aiEstimatedGrams;
    final significant = deviation.abs() > aiEstimatedGrams * 0.2;
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap 而不是 Row：320dp × 1.5× 下三段文字（剩余克数 / 合计 /
        // AI 建议）放不进一行，Row 会溢出。
        Wrap(
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceMicro,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('剩余克数', style: LfText.label.copyWith(color: c.foreground)),
            Text(
              '合计 ${leftoverGrams.toStringAsFixed(0)}g',
              style: LfText.label.copyWith(color: c.foreground),
            ),
            Text(
              'AI 建议 ${aiEstimatedGrams.toStringAsFixed(0)}g',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ],
        ),
        if (significant) ...[
          const SizedBox(height: LfDimens.spaceXSmall),
          SheetMessage(
            '你填写的剩余量与 AI 估算偏差较大，请核对餐前和剩余照片是否为同一餐食。',
            color: c.warning,
          ),
        ],
      ],
    );
  }

  /// 净摄入总计展示（docs/07 §6.3 置信度 chip 同层级）。
  Widget _leftoverNetIntakeSummary({
    required MealScanCandidateDraft before,
    required MealScanCandidateDraft leftover,
  }) {
    final netGrams = _calculateNetIntake(before, leftover);
    final c = context.lf;
    return Text(
      '净摄入: ${netGrams.toStringAsFixed(0)}g',
      style: LfText.label.copyWith(color: c.primary),
    );
  }

  bool _needsSettings(AppFailure failure) =>
      failure is ValidationFailure ||
      failure is StorageFailure ||
      failure is NetworkFailure &&
          failure.kind == NetworkFailureKind.authentication;

  String _safeFailureMessage(AppFailure failure) {
    if (failure is ValidationFailure || failure is StorageFailure) {
      return 'AI 配置不可用，请在设置中检查 Base URL、模型和 API Key。';
    }
    if (failure is NetworkFailure) {
      return switch (failure.kind) {
        NetworkFailureKind.timeout => '识别请求超时，请稍后手动重试。',
        NetworkFailureKind.connection => '网络连接不可用，请检查网络后手动重试。',
        NetworkFailureKind.secureConnection => '供应商的安全连接无法验证，请检查 AI 配置。',
        NetworkFailureKind.authentication => 'AI 配置验证失败，请在设置中检查 API Key。',
        NetworkFailureKind.rateLimited => '服务请求过于频繁，请稍后手动重试。',
        NetworkFailureKind.serviceUnavailable => '供应商暂时不可用，请稍后手动重试。',
        NetworkFailureKind.requestRejected => '供应商拒绝了该请求，请检查 AI 配置后重试。',
        NetworkFailureKind.invalidResponse => '供应商返回格式无法识别，请稍后手动重试。',
        NetworkFailureKind.cancelled => '识别已取消。',
      };
    }
    return '识别请求未能完成，请稍后手动重试或改为手动记餐。';
  }
}

/// 固定底部确认 CTA（`cta-confirm-scan`，docs/21 §5.4 结构树末项）。
///
/// 设计规格：`w-full rounded-full py-3.5 text-sm font-semibold` + primary 底
/// + `0 4px 20px -4px` 40% primary 阴影 + 前置 ✓ 图标——就是 §3.8 的 B2，
/// 所以直接走共享件（唯一本地差别是禁用态由共享件负责不画阴影）。
class _ConfirmScanButton extends StatelessWidget {
  const _ConfirmScanButton({
    required this.enabled,
    required this.saving,
    required this.onPressed,
  });

  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return LfConfirmButton(
      key: const Key('cta-confirm-scan'),
      label: saving ? '正在保存…' : '确认记录此餐',
      icon: Icons.check,
      busy: saving,
      onPressed: enabled ? onPressed : null,
    );
  }
}
