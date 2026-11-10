import 'dart:async';

import 'package:flutter/services.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:localfit_ai/app/app_version.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/presentation/legacy_migration_sheet.dart';
import 'package:localfit_ai/features/settings/presentation/data_self_check_page.dart';
import 'package:localfit_ai/features/settings/application/platform_links.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/settings_group.dart';
import 'package:localfit_ai/app/design/widgets/setting_row.dart';
import 'package:localfit_ai/app/design/widgets/lf_achievement_row.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_markdown.dart';
import 'package:localfit_ai/app/design/widgets/lf_metric_gauge.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/dio_ai_endpoint_probe.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_data_flows.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/domain/achievement_levels.dart';
import 'package:localfit_ai/features/settings/domain/health_metric_bands.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/progress/presentation/weight_history_sheet.dart';
import 'package:localfit_ai/features/settings/presentation/steps_permission_sheet.dart';
import 'package:localfit_ai/features/settings/presentation/update_download_sheet.dart';
import 'package:localfit_ai/features/settings/domain/ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';
import 'package:localfit_ai/utils/number_format.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';

/// 数据管理二级弹层里选中的动作（关层后再执行，避免叠弹层）。
enum _DataAction {
  backup,
  restore,
  exportMeals,
  exportTraining,
  exportFoods,
  legacyMigration,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.settingsStore,
    this.endpointProbe,
    this.apiKeyStore,
    this.createEncryptedBackup,
    this.restoreEncryptedBackup,
    this.clearAllLocalData,
    this.clearBuiltinFoods,
    this.exportCsvFiles,
    this.profileIdentityRepository,
    this.catalogBootstrap,
    this.profileOverviewLoader,
    this.appSettingsRepository,
    this.onAddCustomFood,
    this.onImportFoodCsv,
    this.onOpenMenuSources,
    this.onOpenProfileEdit,
    this.onOpenAiMemory,
    this.onOpenRetrievalDebug,
    this.stepsRepository,
    this.scaleSync,
    this.measurementRepository,
    this.appVersion,
    this.now,
    this.helpContentLoader,
    this.appUpdateService,
    this.dietaryConstraintsSummary,
    this.onOpenDietaryConstraints,
    this.dataSelfCheck,
    this.database,
  });

  final AiProviderSettingsStore? settingsStore;

  /// 连通性测试 + 模型拉取（docs/29 §P4）。null 时用默认 Dio 实现；
  /// 测试注入 fake 以免触网。
  final AiEndpointProbe? endpointProbe;

  /// 已保存 Key 的读取口（连通性测试用：Key 框留空时探测存量凭据）。
  /// null 时只能用刚输入的 Key 探测。
  final AiApiKeyStore? apiKeyStore;

  final CreateEncryptedBackup? createEncryptedBackup;
  final RestoreEncryptedBackup? restoreEncryptedBackup;
  final ClearAllLocalData? clearAllLocalData;

  /// 「清空内置食物」（docs/32 §4 T11 需求 75）：升级安装里那几万行内置
  /// 食物的**唯一可点入口**。与 [_clearAllLocalData] 是两件事：那条清掉
  /// 所有用户字节，这条只删内置食物行。null = 不渲染该路。
  final ClearBuiltinFoods? clearBuiltinFoods;

  final ExportCsvFiles? exportCsvFiles;
  final ProfileIdentityRepository? profileIdentityRepository;

  /// 选头像（docs/32 §3 D9）。null = 身份卡头像不可点（测试/未接线）。

  /// 食物目录引导（docs/07 §5.6）。为空时（无目录能力的测试/旧接线）不显示这一节。
  final CatalogBootstrap? catalogBootstrap;

  /// 我的页派生只读数据（体重/总记录/连续天数/BMI/BMR/成就，docs/21
  /// §5.6）。为空时相关区块走诚实空态（「—」/0），不编演示值。
  final LoadProfileOverview? profileOverviewLoader;

  /// 「自动本地备份」开关的本地存储（裁决 ⑦：开关值存本地设置）。
  final AppSettingsRepository? appSettingsRepository;

  /// 「添加自定义食材」：复用饮食页既有的新建食物流程（NewFoodDialog）。
  /// null＝不渲染该入口。Future 在动作**写库结束**时完成（取消也算完成），
  /// 页面据此就地重读食材库计数——见 [_refreshOverviewAfterFoodWrite]。
  final Future<void> Function()? onAddCustomFood;

  /// 「从 CSV 文件导入」（docs/31 S5 需求 55/57）：挑文件 → 解析预览 →
  /// 用户决定「跳过重复/全部导入」。整条编排住在路由层，本页只留入口。
  /// null＝「添加食物数据」弹层不渲染导入动作。Future 语义同上。
  final Future<void> Function()? onImportFoodCsv;

  /// 「菜单来源管理」（docs/21 §5.6 🏫）：跳到饮食页的菜单 tab。
  /// null＝不渲染该入口。
  final VoidCallback? onOpenMenuSources;

  /// 「编辑资料」（docs/21 §5.6 身份卡）：push 到 /profile-edit。
  /// null＝不渲染该入口。
  final VoidCallback? onOpenProfileEdit;

  /// 「AI 记忆」（docs/38 S11）：push 到 /ai-memory。
  /// null＝未接线，不渲染 `settings-ai-memory-row`。
  final VoidCallback? onOpenAiMemory;

  /// 搜索调试面板（docs/39 G21）；null＝不渲染入口。
  final VoidCallback? onOpenRetrievalDebug;

  /// 本机步数仓储（docs/30 §2 D9 / 需求 3：授权状态与「去系统设置」）。
  /// null＝未接线，不渲染 `settings-steps-permission`。
  final StepsRepository? stepsRepository;

  /// 体重记录仓储（Round7 裁决 R5）。null = 身份卡「当前体重」不可点
  /// （没有历史可看时不画一个点了没反应的入口）。
  final MeasurementRepository? measurementRepository;

  /// 电子体重秤同步编排（docs/31 S6，需求 47 / D6）：授权状态 + 前台扫描
  /// + 落库（默认不覆盖同日手输值）。null＝未接线，不渲染 `settings-scale-row`。
  final ScaleSyncController? scaleSync;

  /// 版本号（docs/21 §5.6 📱）。null 时回落到随包版本（17c：永不显示「未知」）。
  final String? appVersion;
  final DateTime? now;

  /// 反馈链接（仓库 issue 新建页，**需求 17e**）。常量：链接是不可配置的
  /// 事实，不该由调用方各写一份。
  static const String feedbackIssueUrl =
      'https://github.com/xiaopeng66/localfit-ai/issues/new';

  /// 在线更新服务（**需求 17b**）。null = 用默认实现（真网络）。
  ///
  /// 注入是给测试用的：**不许**在 widget 测试里真的发网络请求。
  final AppUpdateService? appUpdateService;

  /// 「饮食约束」行（C-2，docs/64）：摘要与弹层都由路由层注入——本 feature
  /// 不直连 `daily_plan`（分层门禁只许减，docs/52）；仓储与弹层住在
  /// daily_plan feature，这里只留两个回调位。null＝不渲染该行。
  final Future<String> Function()? dietaryConstraintsSummary;
  final Future<void> Function()? onOpenDietaryConstraints;

  /// 「数据自检」（D-1/D-2，docs/64）：三类可检问题 + 最近一次备份。
  /// 由路由层用 database 组装。null＝未接线，不渲染 `data-self-check-entry`。
  final DataSelfCheck? dataSelfCheck;

  /// 只读查看旧数据迁移台账（docs/67 §5.4）。null＝未接线，不渲染该入口。
  final AppDatabase? database;

  /// 帮助正文加载器（**需求 17d**）。null = 读随包 `assets/help/*.md`。
  ///
  /// 测试注入用：`rootBundle` 是 `CachingAssetBundle`（按路径缓存、跨用例
  /// 互相污染），本仓既有做法是**注入闭包**而不是让 widget 测试去碰真实资产
  /// （见 `bundled_user_food_importer_test.dart` 的同一条注记）。
  final Future<String> Function()? helpContentLoader;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _loading = true;
  int _settingsLoad = 0;
  bool _saving = false;
  bool _updating = false;
  bool _hasApiKey = false;
  String? _error;

  /// 体重秤行重查计数：说明弹层关闭后自增，行以 `ValueKey` 重建并重查
  /// 权限状态（不带任何猜测缓存）。
  int _scaleNonce = 0;

  /// 供应商协议（docs/24）：默认 Chat Completions＝旧行为。
  AiProviderProtocol _protocol = AiProviderProtocol.chatCompletions;

  /// 推理开关（docs/29 §P4）：默认「关闭推理」＝推理型模型空回复的修复。
  AiReasoningMode _reasoning = AiReasoningMode.disabled;

  /// 连通性测试（docs/29 §P4）：探测是低频动作，Dio 实例只在真正用到时建。
  late final AiEndpointProbe _endpointProbe =
      widget.endpointProbe ?? DioAiEndpointProbe(dio: Dio());

  /// 身份卡/健康数据/成就/食材库计数共用的一次性派生加载。
  Future<ProfileOverview?>? _overviewFuture;

  /// 身份事实独立于概览监听；没有统计能力时昵称/头像仍可更新。
  final ValueNotifier<IdentityProfile?> _identity = ValueNotifier(null);
  StreamSubscription<IdentityProfile?>? _identitySubscription;

  /// 本分支上一次的可见性（见 [didChangeDependencies]）。
  bool? _branchVisible;

  /// 「自动本地备份」开关（裁决 ⑦）。写入失败要回滚 UI 并提示。
  bool _autoBackupEnabled = false;

  /// 局域网更新源（null/空 = 只走 GitHub）。
  String? _lanUpdateUrl;

  @override
  void initState() {
    super.initState();
    _load();
    final loader = widget.profileOverviewLoader;
    if (loader != null) {
      // 派生数据加载失败不红屏：各区块按「无数据」诚实降级。
      _overviewFuture = _safeOverview(loader);
    }
    _watchIdentity();
    _loadAutoBackup();
    unawaited(_loadLanUpdateUrl());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 派生数据是**加载那一刻**的快照，而「我的」是 shell 里常驻的分支：
    // 切走期间别的页面会写库（设备实测：今日页记 500ml 饮水后切回来，水分卡
    // 还停在 0%），不重读就会一直显示旧数字。
    //
    // 可见性靠 `TickerMode`：go_router 的 `StatefulShellRoute` 给非当前分支套
    // `Offstage(child: TickerMode(enabled: false))`（go_router 17.1.0
    // `src/route.dart:1695-1698`），切回来时翻回 true ⇒ 这里收到依赖变化。
    // 只在「重新可见」那一次重读；首帧（null → 值）只记录。
    //
    // 重读**不会闪空态**：`FutureBuilder` 换 future 时保留上一次的 data
    // （`AsyncSnapshot.withData(ConnectionState.waiting, 旧 data)`），各区块
    // 的判据又是 `snapshot.data`，所以旧值一直显示到新值到达。
    //
    // 根导航器的不透明二级页返回也会恢复 TickerMode；非不透明弹层的
    // 写入（食物、恢复、清空）则由动作结束处显式重读。
    final visible = TickerMode.valuesOf(context).enabled;
    final wasVisible = _branchVisible;
    _branchVisible = visible;
    final loader = widget.profileOverviewLoader;
    if (wasVisible == false && visible && loader != null) {
      _overviewFuture = _safeOverview(loader);
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileIdentityRepository !=
        widget.profileIdentityRepository) {
      _watchIdentity();
    }
    if (oldWidget.profileOverviewLoader != widget.profileOverviewLoader) {
      final loader = widget.profileOverviewLoader;
      _overviewFuture = loader == null ? null : _safeOverview(loader);
    }
  }

  Future<ProfileOverview?> _safeOverview(LoadProfileOverview loader) async {
    try {
      return await loader.run();
    } catch (_) {
      return null;
    }
  }

  void _watchIdentity() {
    unawaited(_identitySubscription?.cancel());
    _identity.value = null;
    _identitySubscription = widget.profileIdentityRepository
        ?.watchIdentity()
        .listen(
          (identity) {
            if (mounted) _identity.value = identity;
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) _identity.value = null;
          },
        );
  }

  void _refreshAfterDataReplacement() {
    if (!mounted) return;
    final loader = widget.profileOverviewLoader;
    setState(() {
      _overviewFuture = loader == null ? null : _safeOverview(loader);
    });
    unawaited(_loadAutoBackup());
    unawaited(_load());
  }

  Future<void> _loadAutoBackup() async {
    final repo = widget.appSettingsRepository;
    if (repo == null) return;
    final enabled = await repo.getBool(
      AppSettingsRepository.autoBackupEnabledKey,
    );
    if (!mounted) return;
    setState(() => _autoBackupEnabled = enabled);
  }

  Future<void> _loadLanUpdateUrl() async {
    final repo = widget.appSettingsRepository;
    if (repo == null) return;
    final value = await repo.getString(
      AppSettingsRepository.lanUpdateBaseUrlKey,
    );
    if (!mounted) return;
    setState(() => _lanUpdateUrl = value);
  }

  Future<void> _openLanUpdateDialog() async {
    final repo = widget.appSettingsRepository;
    if (repo == null) return;
    final result = await AppSheet.showStateful<String>(
      context,
      title: '局域网更新地址',
      bodyBuilder: (sheetContext) => _LanUpdateSheet(
        initialUrl: _lanUpdateUrl ?? '',
        onDone: (value) => Navigator.pop(sheetContext, value),
      ),
    );
    if (result == null || !mounted) return;
    if (result.isEmpty) {
      await repo.remove(AppSettingsRepository.lanUpdateBaseUrlKey);
      if (!mounted) return;
      setState(() => _lanUpdateUrl = null);
      AppSnackBar.show(context, '已清除局域网更新地址。', icon: AppSnackBar.successIcon);
      return;
    }
    await repo.setString(AppSettingsRepository.lanUpdateBaseUrlKey, result);
    if (!mounted) return;
    setState(() => _lanUpdateUrl = result);
    AppSnackBar.show(context, '已保存局域网更新地址。', icon: AppSnackBar.successIcon);
  }

  Future<void> _toggleAutoBackup(bool value) async {
    final repo = widget.appSettingsRepository;
    setState(() => _autoBackupEnabled = value);
    if (repo == null) return;
    try {
      await repo.setBool(
        AppSettingsRepository.autoBackupEnabledKey,
        value: value,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoBackupEnabled = !value);
      _showError('写入设置失败，请重试。');
    }
  }

  @override
  void dispose() {
    unawaited(_identitySubscription?.cancel());
    _identity.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_settingsLoad;
    final store = widget.settingsStore;
    if (store == null) {
      setState(() {
        _loading = false;
        _error = 'AI 配置未初始化。';
      });
      return;
    }
    try {
      final settings = await store.load();
      if (!mounted || request != _settingsLoad) return;
      setState(() {
        _error = null;
        _baseUrl.text = settings.configuration?.baseUrl ?? '';
        _model.text = settings.configuration?.model ?? '';
        _protocol =
            settings.configuration?.protocol ??
            AiProviderProtocol.chatCompletions;
        _reasoning =
            settings.configuration?.reasoning ?? AiReasoningMode.disabled;
        _hasApiKey = settings.hasApiKey;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _settingsLoad) {
        setState(() {
          _loading = false;
          _error = '无法读取本地 AI 配置，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 设计稿「我的」无 AppBar：页头是页内的一行文字（A `head()`），
      // 身份卡紧随其后；底栏由 shell 提供。
      body: ListView(
        // 顶部另加系统叠层（docs/21 §5.8.5）：身份卡不是贴顶铺满的 hero
        // （左右各有 16dp 边距），所以整块内容下移，不需要 bleed。
        padding: EdgeInsets.fromLTRB(
          LfDimens.pagePadding,
          LfDimens.spaceLargePlus + LfInsets.top(context),
          LfDimens.pagePadding,
          LfInsets.navReserve(context),
        ),
        children: [
          // Round7 A `app.js:271` 的页头（`head('我的', '关于你，也关于你的
          // 数据', …)`）：本页此前没有页头，与今日/训练两页不对称。
          // **不搬** A 页头右侧的「本地优先」徽章——docs/33 §3.8 明令不用它
          // 概括所有流向（外发是用户触发的事实），诚实披露由页尾隐私条与
          // 「数据来源与许可证」承担。哨兵断言在 `settings_page_test.dart`。
          const _SettingsPageHead(),
          const SizedBox(height: LfDimens.spaceLarge),
          _IdentityCard(
            overviewFuture: _overviewFuture,
            identityFuture: _identity,
            // Round7 裁决 R5：当前体重 → 只读「体重记录」弹层。
            onOpenWeightHistory: widget.measurementRepository == null
                ? null
                : () => showWeightHistorySheet(
                    context,
                    widget.measurementRepository!,
                  ),
            onEdit: widget.onOpenProfileEdit,
            // 2026-10-16 用户第二轮（原话）：「我的界面，头像和昵称不要能
            // 跳转点击，就在后边的编辑资料按钮点击就好了」——头像与昵称只
            // **展示**：不给按压态、不给跳转、不给语义按钮位；身份改动一律
            // 走右侧「编辑资料」按钮进资料页。
            onEditName: null,
            onPickAvatar: null,
          ),
          const SizedBox(height: LfDimens.spaceLarge),
          _HealthMetricsCard(overviewFuture: _overviewFuture),
          const SizedBox(height: LfDimens.spaceLarge),
          // C-2（docs/64）：饮食约束（素食标签 + 过敏原）。2026-11-02 用户：
          // 原先一行光秃秃挂在页面上、没有卡片占位，和上下分组不像一套；
          // 现在收进 `SettingsGroup`，与 AI / 数据 / 食材库同一卡片语言。
          if (widget.dietaryConstraintsSummary != null &&
              widget.onOpenDietaryConstraints != null)
            SettingsGroup(
              title: '饮食与偏好',
              titleKey: const Key('settings-group-dietary'),
              children: [
                _DietaryConstraintsRow(
                  summary: widget.dietaryConstraintsSummary!,
                  onOpen: widget.onOpenDietaryConstraints!,
                ),
              ],
            ),
          const SizedBox(height: LfDimens.spaceLarge),
          _AchievementsCard(overviewFuture: _overviewFuture),
          const SizedBox(height: LfDimens.spaceLarge),
          _aiGroup(),
          const SizedBox(height: LfDimens.spaceLargePlus),
          // 分组可见性与 _dataGroup 内部的自门控条件保持一致：有备份能力、
          // 注入了开关存储（裁决 ⑦）、接入了步数仓储（D9）或体重秤编排
          // （docs/31 S6）都渲染。
          if (_hasBackupCapabilities ||
              widget.appSettingsRepository != null ||
              widget.stepsRepository != null ||
              widget.scaleSync != null) ...[
            _dataGroup(),
            const SizedBox(height: LfDimens.spaceLargePlus),
          ],
          // docs/28 §5.6：独立的「食物目录」分组已删除，导入入口收进食材库。
          _foodGroup(),
          const SizedBox(height: LfDimens.spaceLargePlus),
          _aboutGroup(),
          const SizedBox(height: LfDimens.spaceLargePlus),
          const _PrivacyBadge(),
          const SizedBox(height: LfDimens.spaceMedium),
          _DangerFooter(appVersion: widget.appVersion),
        ],
      ),
    );
  }

  // ─── 分组构建（docs/21 §5.6：AI 配置 / 数据管理 / 食材库 / 关于） ───

  Widget _aiGroup() {
    final model = _model.text.trim();
    final modelLabel = _loading
        ? null
        : model.isEmpty
        ? '未配置'
        : model;
    return SettingsGroup(
      title: 'AI 配置',
      titleKey: const Key('settings-group-ai'),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(LfDimens.spaceLarge),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.all(LfDimens.spaceLarge),
            child: Text(
              _error!,
              style: LfText.body.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          SettingRow(icon: Icons.refresh, title: '重新加载', onTap: _load),
        ] else ...[
          // docs/29 §P4（需求 6）：协议 / Base URL / 模型 / API Key 全部收进
          // 同一个弹层——组内不再留「孤零零一行 Key」，页面只剩这一个入口行。
          SettingRow(
            key: const Key('settings-ai-model-row'),
            icon: Icons.psychology_outlined,
            title: 'AI 模型',
            value: modelLabel,
            showChevron: true,
            onTap: _openAiConfigSheet,
          ),
          // AI 记忆（docs/38 S11）：与 AI 模型同组；未接线时不渲染。
          if (widget.onOpenAiMemory != null)
            SettingRow(
              key: const Key('settings-ai-memory-row'),
              icon: Icons.memory,
              title: 'AI 记忆',
              value: '让 AI 记住你的习惯',
              showChevron: true,
              onTap: widget.onOpenAiMemory,
            ),
          // 搜索调试（docs/39 G21）：只读诊断面；未接线时不渲染。
          if (widget.onOpenRetrievalDebug != null)
            SettingRow(
              key: const Key('settings-retrieval-debug-row'),
              icon: Icons.troubleshoot_outlined,
              title: '搜索调试',
              value: '看检索为什么命中/不命中',
              showChevron: true,
              onTap: widget.onOpenRetrievalDebug,
            ),
        ],
      ],
    );
  }

  Widget _dataGroup() {
    // 备份/恢复/CSV 依赖备份能力注入；「自动本地备份」开关只依赖本地
    // 键值设置（裁决 ⑦）——两者独立判断，互不连坐。步数授权行只依赖
    // 步数仓储（docs/30 §2 D9），体重秤行只依赖秤编排（docs/31 S6）：
    // 各自**任一**在场就渲染本组。
    final hasBackup = _hasBackupCapabilities;
    if (!hasBackup &&
        widget.appSettingsRepository == null &&
        widget.stepsRepository == null &&
        widget.scaleSync == null) {
      return const SizedBox.shrink();
    }
    return SettingsGroup(
      title: '数据管理',
      titleKey: const Key('settings-group-data'),
      children: [
        // 【2026-11-02 用户：数据管理条目太多，汇总进二级弹层】备份/恢复/
        // 三个 CSV 导出收进「备份与导出」；自动备份开关留在行尾，常用状态
        // 一眼可见。内部行沿用原 Key，自动化与读屏定位不变。
        if (hasBackup)
          SettingRow(
            key: const Key('settings-backup-hub'),
            icon: Icons.folder_copy_outlined,
            title: '备份与导出',
            showChevron: true,
            trailing: widget.appSettingsRepository == null
                ? null
                : SettingToggle(
                    key: const Key('settings-auto-backup-toggle'),
                    value: _autoBackupEnabled,
                    onChanged: _toggleAutoBackup,
                    semanticLabel: '自动本地备份',
                  ),
            onTap: _openBackupExportSheet,
          )
        else if (widget.appSettingsRepository != null)
          SettingRow(
            icon: Icons.backup_outlined,
            title: '自动本地备份',
            trailing: SettingToggle(
              key: const Key('settings-auto-backup-toggle'),
              value: _autoBackupEnabled,
              onChanged: _toggleAutoBackup,
              semanticLabel: '自动本地备份',
            ),
          ),
        if (widget.dataSelfCheck != null)
          SettingRow(
            key: const Key('data-self-check-entry'),
            icon: Icons.fact_check_outlined,
            title: '数据自检',
            showChevron: true,
            onTap: _openDataSelfCheck,
          ),
        if (widget.stepsRepository != null)
          _StepsPermissionRow(
            repository: widget.stepsRepository!,
            onOpenSheet: _openStepsPermissionSheet,
          ),
        if (widget.scaleSync != null)
          _ScalePermissionRow(
            key: ValueKey('scale-row-$_scaleNonce'),
            sync: widget.scaleSync!,
            onOpenSheet: _openScaleSheet,
          ),
      ],
    );
  }

  /// 备份/恢复/导出的二级弹层（2026-11-02 用户：数据管理条目太多）。
  ///
  /// 二级只收纳**低频动作**；自动备份开关留在父行行尾。返回枚举后再执行，
  /// 不叠着弹层开下一个弹层（备份/恢复各自还有密码弹层）。
  Future<void> _openBackupExportSheet() async {
    final action = await AppSheet.show<_DataAction>(
      context,
      title: '备份与导出',
      content: Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingRow(
              key: const Key('cta-backup'),
              icon: Icons.download_outlined,
              title: '备份数据',
              showChevron: true,
              onTap: () => Navigator.of(sheetContext).pop(_DataAction.backup),
            ),
            SettingRow(
              key: const Key('cta-restore'),
              icon: Icons.upload_outlined,
              title: '恢复数据',
              showChevron: true,
              onTap: () => Navigator.of(sheetContext).pop(_DataAction.restore),
            ),
            SettingRow(
              key: const Key('cta-export-csv'),
              icon: Icons.table_view_outlined,
              title: '导出饮食记录',
              showChevron: true,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DataAction.exportMeals),
            ),
            SettingRow(
              key: const Key('backup-export-training-csv'),
              icon: Icons.table_view_outlined,
              title: '导出训练记录',
              showChevron: true,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DataAction.exportTraining),
            ),
            SettingRow(
              key: const Key('backup-export-foods-csv'),
              icon: Icons.table_view_outlined,
              title: '导出食物数据',
              showChevron: true,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_DataAction.exportFoods),
            ),
            if (widget.database != null)
              SettingRow(
                key: const Key('cta-legacy-migration'),
                icon: Icons.history_outlined,
                title: '旧数据迁移记录',
                showChevron: true,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_DataAction.legacyMigration),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _DataAction.backup:
        await _openExportDialog();
      case _DataAction.restore:
        await _openRestoreDialog();
      case _DataAction.exportMeals:
        await _exportMealsCsv();
      case _DataAction.exportTraining:
        await _exportTrainingCsv();
      case _DataAction.exportFoods:
        await _exportFoodsCsv();
      case _DataAction.legacyMigration:
        final database = widget.database;
        if (database != null) {
          await LegacyMigrationSheet.show(context, database);
        }
    }
  }

  /// 步数与身体活动（docs/30 §2 D9 / 需求 3）：授权状态 + 撤销/开启入口。
  /// 未接线时不渲染（与体重秤行同约定）。
  Future<void> _openStepsPermissionSheet() async {
    final repository = widget.stepsRepository;
    if (repository == null) return;
    await showStepsPermissionSheet(context, repository);
  }

  /// 电子体重秤说明 + 同步弹层（docs/31 S6 稿 ②③④）。
  ///
  /// 与步数行同一条纪律：权限状态不缓存；弹层关闭后自增 `_scaleNonce`
  /// 让行重查。扫描中可取消——取消只是关界面，原生侧的 10 秒窗口自己会
  /// 结束；完成后的结局处理都以 `mounted` 守卫，不往已关的弹层里塞东西。
  Future<void> _openScaleSheet() async {
    final sync = widget.scaleSync;
    if (sync == null) return;
    await AppSheet.showStateful<void>(
      context,
      title: '电子体重秤',
      bodyBuilder: (sheetContext) => _ScaleSheetBody(
        sync: sync,
        onOutcome: (outcome) => _handleScaleOutcome(outcome),
      ),
    );
    if (mounted) setState(() => _scaleNonce++);
  }

  /// 扫描结局的就地呈现：成功/失败走 snackbar，同日冲突走二选一弹层
  /// （默认保留原记录——D6 ③「覆盖要让用户明确选择」）。
  Future<void> _handleScaleOutcome(ScaleSyncOutcome outcome) async {
    final sync = widget.scaleSync;
    if (sync == null) return;
    switch (outcome) {
      case ScaleSyncSaved(:final weightKg):
        _showScaleMessage('已同步秤读数 ${weightKg.toStringAsFixed(2)} kg。');
      case ScaleSyncConflict(:final scaleWeightKg, :final existing):
        final overwrite = await _openScaleConflictSheet(
          scaleWeightKg: scaleWeightKg,
          existingKg: existing.weightKg,
          existingFromScale: existing.source == 'ble_scale',
        );
        if (overwrite == null || !mounted) return;
        if (!overwrite) {
          _showScaleMessage('已保留原记录。');
          return;
        }
        final saved = await sync.overwriteSameDay(scaleWeightKg: scaleWeightKg);
        if (!mounted) return;
        _showScaleMessage(
          '已用秤读数 ${saved.weightKg.toStringAsFixed(2)} kg 覆盖今天的记录。',
        );
      case ScaleSyncNoScale():
        _showScaleMessage(
          '未发现支持的电子秤。请站上秤唤醒它，'
          '或换用支持标准体重秤协议（Bluetooth SIG 0x181D）的秤。',
          error: true,
        );
      case ScaleSyncTimeout():
        _showScaleMessage('连上了秤，但没有等到读数。请再试一次。', error: true);
      case ScaleSyncPermissionDenied():
        _showScaleMessage('蓝牙权限未授予，无法同步电子秤。', error: true);
      case ScaleSyncUnsupported():
        _showScaleMessage('本机不支持电子秤同步（需要 Android 12 及以上）。', error: true);
      case ScaleSyncOutOfRange(:final weightKg):
        _showScaleMessage(
          '秤读数 ${weightKg.toStringAsFixed(2)} kg 超出可记录范围（35–300 kg）。',
          error: true,
        );
    }
  }

  void _showScaleMessage(String message, {bool error = false}) {
    AppSnackBar.show(
      context,
      message,
      icon: error ? AppSnackBar.errorIcon : AppSnackBar.successIcon,
    );
  }

  /// 同日冲突二选一（docs/31 S6 稿 ④）：返回 true = 用秤读数覆盖；
  /// false = 保留原记录；null = 取消（等于保留——默认不覆盖）。
  Future<bool?> _openScaleConflictSheet({
    required double scaleWeightKg,
    required double existingKg,
    required bool existingFromScale,
  }) {
    return AppSheet.show<bool>(
      context,
      title: '今天已有体重记录',
      content: Text(
        '今天已有一条${existingFromScale ? '秤同步' : '手输'}记录 '
        '${existingKg.toStringAsFixed(2)} kg，秤读到 ${scaleWeightKg.toStringAsFixed(2)} kg。'
        '要替换吗？不选就保留原记录。',
        key: const Key('scale-conflict-body'),
      ),
      actions: Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LfTextButton(
              key: const Key('scale-conflict-keep'),
              label: '保留原记录',
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
            const SizedBox(height: LfDimens.spaceSmall),
            LfConfirmButton(
              key: const Key('scale-conflict-overwrite'),
              label: '用秤读数覆盖',
              expand: true,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            const SizedBox(height: LfDimens.spaceSmall),
            Center(
              child: LfTextButton(
                label: '取消',
                onPressed: () => Navigator.pop(sheetContext, null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _foodGroup() {
    return SettingsGroup(
      title: '食材库',
      titleKey: const Key('settings-group-catalog'),
      children: [
        FutureBuilder<ProfileOverview?>(
          future: _overviewFuture,
          builder: (context, snapshot) {
            final overview = snapshot.data;
            return SettingRow(
              key: const Key('settings-food-db-row'),
              icon: Icons.storage_outlined,
              title: '食材数据库',
              // docs/28 §5.6：口径要能读出来「一共多少、其中自建多少」。
              // 总条数随库变（随包种子 + 导入目录 + 自建），所以两个数都从
              // 数据库实算，不把条数写死在界面上。
              value: overview == null
                  ? '—'
                  : '${formatGroupedInt(overview.foodCount)} 条'
                        '（自建 ${formatGroupedInt(overview.userCreatedFoodCount)} 条）',
            );
          },
        ),
        // 扩展目录恢复入口（docs/32 §3 D10）：**仅失败/分片缺失时渲染**。
        // 首启已自动导入（`main.dart` 的 `unawaited(importAvailable())`），
        // 常驻一行「可选导入」等于请用户重复做一件已经做完的事；但失败时
        // 的恢复路径必须不死——那正是这行留下的唯一理由。
        if (widget.catalogBootstrap case final bootstrap?)
          ValueListenableBuilder<CatalogBootstrapResult?>(
            valueListenable: bootstrap.lastResult,
            builder: (context, result, _) {
              if (!_catalogNeedsRecovery(result)) {
                return const SizedBox.shrink();
              }
              return SettingRow(
                key: const Key('settings-catalog-import'),
                icon: Icons.cloud_download_outlined,
                title: '导入扩展食物目录（可选）',
                subtitle: _catalogStatusText(result),
                showChevron: true,
                onTap: () => bootstrap.importAvailable(),
              );
            },
          ),
        // 「添加食物数据」（docs/31 S5 需求 55）：大库的批量入口（手动逐条
        // 走弹层里的「手动添加一种食物」；CSV 导入也从这行的弹层进）。两个
        // 回调都没接时不渲染，不摆一个点了没反应的行。
        if (widget.onAddCustomFood != null || widget.onImportFoodCsv != null)
          SettingRow(
            key: const Key('settings-food-data'),
            icon: Icons.library_add_outlined,
            title: '添加食物数据',
            showChevron: true,
            onTap: _openFoodDataSheet,
          ),
        if (widget.onOpenMenuSources != null)
          SettingRow(
            key: const Key('settings-menu-sources'),
            icon: Icons.storefront_outlined,
            title: '维护地点 / 窗口 / 菜品',
            showChevron: true,
            onTap: widget.onOpenMenuSources,
          ),
        // 「清空内置食物」（docs/32 §4 T11 需求 75）：放组末、与三个常驻行
        // 拉开距离，减少误触。**只有库里有内置行时才渲染**——全新安装
        // （T13 之后随包种子不再灌库）本就是 0 条，摆一个「删 0 条」的动作
        // 就是请用户做无用功。判据随概览走：它与计数行读同一个 future，
        // 清空后 [_refreshOverviewAfterFoodWrite] 一刷新，这行自己就消失。
        if (widget.clearBuiltinFoods case final clear?)
          FutureBuilder<ProfileOverview?>(
            future: _overviewFuture,
            builder: (context, snapshot) {
              final overview = snapshot.data;
              if (overview == null ||
                  overview.foodCount <= overview.userCreatedFoodCount) {
                return const SizedBox.shrink();
              }
              return SettingRow(
                key: const Key('settings-clear-builtin-foods'),
                icon: Icons.layers_clear_outlined,
                title: '清空内置食物数据',
                showChevron: true,
                destructive: true,
                onTap: () => _openClearBuiltinFoodsSheet(clear),
              );
            },
          ),
      ],
    );
  }

  /// 扩展目录是否需要恢复入口（docs/32 §3 D10）：**只在失败或分片缺失时为
  /// true**。`lastResult == null`（仍在检查）与成功（含「已在库中」）都为
  /// false——正常态零入口是用户的明确要求；失败态不渲染则会丢掉唯一的恢复
  /// 路径。两种失败形状各自可行动：`failure` 是检查/导入本身没成，
  /// `missingShards` 是只导了一部分（next 次点击会补剩下的分片）。
  static bool _catalogNeedsRecovery(CatalogBootstrapResult? result) {
    if (result == null) return false;
    return result.failure != null || result.missingShards.isNotEmpty;
  }

  /// 「导入扩展食物目录（可选）」的副标题：只陈述已经发生的事。
  ///
  /// 正常构建里没有随包目录分片（ADR-025：中文食物由随包种子承担），旧文案
  /// 「本次构建没有随包目录数据（中文食物已随包，目录按需导入）」等于把一句
  /// 自述不存在的句子常驻在设置页上——docs/28 §5.6 点名去掉。现在这一档只说
  /// 「没有可导入的分片」。
  String _catalogStatusText(CatalogBootstrapResult? result) {
    if (result == null) return '正在检查本地分片…';
    // 失败优先于「没有可导入的分片」：准备阶段就失败时 hasCatalog 也是 false，
    // 但那不是「没有分片」，而是「检查本身没成」。
    if (result.failure case final failure?) return '上次导入未完成：$failure';
    if (!result.hasCatalog) return '没有可导入的分片。';
    final missing = result.missingShards.isEmpty
        ? ''
        : ' · 未导入的分片：${result.missingShards.join('、')}';
    if (result.skippedEntirely) {
      return '已在库中，无需重复导入（${result.catalogVersion}）。$missing';
    }
    return '上次导入 ${formatGroupedInt(result.importedRows)} 条'
        '（${result.importedShards}/${result.totalShards} 个分片）。$missing';
  }

  /// 「添加食物数据」弹层（docs/31 S5 需求 55 / 稿 ③）：两个动作——手动
  /// 逐条（复用既有新建食物流程）与 CSV 批量导入。先关弹层再执行动作：
  /// 导入有自己的预览弹层，叠着开会把导航栈搞乱。
  ///
  /// Round7 阶段 3 · 3-2c：弹层与 CSV 通路都提成了共享件（`food_data_flows.dart`）
  /// ——食物库页尾的「食物管理」进的是同一个组件。本页的标题与 Key 一字不动
  /// （「添加食物数据」与 `food-data-sheet-*`），设置页自己的迁移在后面的阶段。
  Future<void> _openFoodDataSheet() => showFoodDataSheet(
    context,
    title: '添加食物数据',
    onAddCustomFood: widget.onAddCustomFood,
    onImportFoodCsv: widget.onImportFoodCsv,
    onFoodWritten: _refreshOverviewAfterFoodWrite,
  );

  /// 弹层动作（手动添加 / CSV 导入）写库返回后**就地重读**派生数据。
  ///
  /// [_overviewFuture] 的既有重读时机只有「分支重新可见」（[didChangeDependencies]
  /// 的 TickerMode 判据），分支内 push 的弹层返回不触发——设备走查实测：
  /// 导入 2 条自建食物回来，「食材数据库」行仍显示导入前的
  /// 「0 条（自建 0 条）」，要切走再切回才跟上。写库动作自己知道自己
  /// 什么时候结束，就在结束处重读；FutureBuilder 换 future 时保留旧值，
  /// 不会闪空态（同 [didChangeDependencies] 的既有说明）。
  void _refreshOverviewAfterFoodWrite() {
    final loader = widget.profileOverviewLoader;
    if (loader == null) return;
    setState(() {
      _overviewFuture = _safeOverview(loader);
    });
  }

  Widget _aboutGroup() {
    return SettingsGroup(
      title: '关于',
      titleKey: const Key('settings-group-about'),
      children: [
        SettingRow(
          key: const Key('settings-version-row'),
          icon: Icons.info_outline,
          title: '关于 LocalFit AI',
          value: _versionLabel,
          showChevron: true,
          onTap: _openAboutSheet,
        ),
        if (widget.appSettingsRepository != null)
          SettingRow(
            icon: Icons.lan_outlined,
            key: const Key('settings-lan-update'),
            title: '局域网更新',
            value: (_lanUpdateUrl ?? '').isEmpty ? '未设置' : _lanUpdateUrl,
            showChevron: true,
            onTap: _openLanUpdateDialog,
          ),
        SettingRow(
          icon: Icons.cloud_download_outlined,
          key: const Key('settings-check-update'),
          title: '检查更新',
          // 【2026-11-09 审查修复】原来只有一条会消失的 SnackBar：慢网时
          // 行内毫无变化，用户不知道点没点上，再点又被 `_updating` 静默
          // 忽略。现在行内直接显示「检查中…」作为 value。
          value: _updating ? '检查中…' : null,
          showChevron: true,
          onTap: _updating ? null : _checkUpdate,
        ),
        SettingRow(
          icon: Icons.help_outline,
          key: const Key('about-help'),
          title: '帮助文档',
          showChevron: true,
          onTap: _openHelp,
        ),
        SettingRow(
          icon: Icons.feedback_outlined,
          key: const Key('about-feedback'),
          title: '反馈',
          showChevron: true,
          onTap: _openFeedback,
        ),
        if (widget.clearAllLocalData != null)
          SettingRow(
            key: const Key('cta-clear-data'),
            icon: Icons.delete_forever_outlined,
            title: '清除所有数据',
            showChevron: true,
            destructive: true,
            onTap: _openClearAllDialog,
          ),
      ],
    );
  }

  bool get _hasBackupCapabilities =>
      widget.createEncryptedBackup != null &&
      widget.restoreEncryptedBackup != null &&
      widget.clearAllLocalData != null &&
      widget.exportCsvFiles != null;

  /// 帮助文档（docs/21 §5.6 📱）：内置离线说明。不联网、不引外部链接，
  /// 内容就是本应用自己的核心约定。
  Future<void> _openHelp() => AppSheet.show<void>(
    context,
    title: '帮助文档',
    // 弹层壳不给内容滚动（见 app_sheet 的说明），所以 7 组问答自己限制
    // 高度并滚动：不这样做底部问答会被屏幕切掉，看不全也点不到。
    content: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: SingleChildScrollView(
        child: _HelpContent(loader: widget.helpContentLoader),
      ),
    ),
  );

  /// 反馈（docs/21 §5.6 📱；**需求 17e** 2026-10-25 用户「按你的建议来」）。
  ///
  /// 三条都真能做事：
  /// 1. **可点链接**直达仓库 issue 新建页（`xiaopeng66/localfit-ai`，已 public）；
  /// 2. **复制环境信息**一键把「版本 / 机型 / Android / 当前页面」放进剪贴板；
  /// 3. 保留「没有内置上报通道」这句事实说明（不许为了有个按钮就把实话说没了）。
  ///
  /// 开链接走**自己的平台通道**（`PlatformLinks`，零新依赖）；打不开时如实
  /// 说一句并把链接复制到剪贴板——点了必须有反应。
  Future<void> _openFeedback() => AppSheet.show<void>(
    context,
    title: '反馈',
    content: _FeedbackContent(
      onOpenIssue: _openFeedbackIssue,
      onCopyEnv: _copyFeedbackEnv,
    ),
  );

  Future<void> _openFeedbackIssue() async {
    final opened = await PlatformLinks().openUrl(SettingsPage.feedbackIssueUrl);
    if (!mounted) return;
    if (opened) return;
    // 打不开（没有浏览器 / 平台拒绝）：把链接复制好并如实说明。
    await Clipboard.setData(
      const ClipboardData(text: SettingsPage.feedbackIssueUrl),
    );
    if (!mounted) return;
    _showMessage('没能打开浏览器，链接已复制到剪贴板。');
  }

  /// 复制环境信息（版本 / 机型 / Android / 当前页面）。
  ///
  /// 机型与系统版本从平台读（`PlatformLinks.deviceFacts`，**不含任何标识符**）；
  /// 读不到时如实写「机型未知」，不编一个。
  Future<void> _copyFeedbackEnv() async {
    final facts = await PlatformLinks().deviceFacts();
    if (!mounted) return;
    final text = [
      'LocalFit AI $_versionLabel',
      '机型：${facts.modelLabel}',
      facts.androidLabel,
      '页面：我的 → 反馈',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showMessage('环境信息已复制，粘到 issue 里就行。');
  }

  String? _baseUrlError(String? value) =>
      OpenAiCompatibleEndpoint.tryParse(value ?? '', protocol: _protocol) ==
          null
      ? '请输入有效的 HTTPS Base URL'
      : null;

  String? _modelError(String? value) =>
      value == null || value.trim().isEmpty ? '请填写模型名称' : null;

  String? _apiKeyError(String? value) {
    if (!_hasApiKey && (value == null || value.trim().isEmpty)) {
      return '请填写 API Key';
    }
    return null;
  }

  /// 校验 + 落库。返回是否成功：AI 配置弹层据此决定是否自动关闭。
  /// 校验口径与旧版一致（HTTPS URL / 模型名非空 / 首次必须填 Key）；
  /// 字段级错误由弹层里的 Form 校验器画在字段上；非字段错误走 [onError]
  /// 出口（§5.8.1 错误要可见）。
  ///
  /// [onError]：弹层挂在根导航器上、盖住页面，页面级 snackbar 会被遮得
  /// 看不见（曾经的缺陷：点保存零反馈），所以弹层里的保存**必须**传它。
  Future<bool> _saveConfig({void Function(String message)? onError}) async {
    final store = widget.settingsStore;
    if (store == null) return false;
    final formOk = _formKey.currentState?.validate() ?? true;
    if (!formOk) return false;
    final void Function(String message) reportError = onError ?? _showError;
    setState(() => _saving = true);
    try {
      await store.save(
        AiProviderSettingsInput(
          baseUrl: _baseUrl.text,
          model: _model.text,
          protocol: _protocol,
          reasoning: _reasoning,
          apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text,
        ),
      );
      if (!mounted) return false;
      setState(() {
        _hasApiKey = true;
        _apiKey.clear();
      });
      AppSnackBar.show(context, 'AI 配置已仅保存到本机。', icon: AppSnackBar.successIcon);
      return true;
    } on ValidationFailure catch (error) {
      reportError(error.message);
      return false;
    } catch (_) {
      reportError('保存失败，请重试。');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 清除已保存 Key 的二次确认 + 落地。返回是否真的清掉了——调用方（AI 配置
  /// 弹层）据此刷新「已保存」提示；不弹 snackbar：弹层挂在根导航器上会把它
  /// 盖住（同 [_saveConfig] 的 onError 注释）。
  Future<bool> _confirmClearApiKey() async {
    final confirmed = await AppSheet.show<bool>(
      context,
      title: '清除 API Key？',
      content: const Text('只会清除保存在系统安全存储中的 API Key，不会删除本地配置或餐食数据。'),
      // 弹层走根导航器（docs/21 §3.6），动作闭包须用弹层内 context 弹出。
      actions: Builder(
        builder: (sheetContext) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 清除凭据是破坏性动作：取消 = B6、确认 = B7（error 字色文字按钮，
            // 与 `我的.html:524-532` 的「清除所有数据」同形，设计稿无实心 error）。
            LfTextButton(
              label: '取消',
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
            LfDangerButton(
              label: '确认清除',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return false;

    setState(() => _saving = true);
    try {
      await widget.settingsStore!.clearApiKey();
      if (!mounted) return false;
      setState(() => _hasApiKey = false);
      return true;
    } catch (_) {
      _showError('清除失败，请重试。');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppSnackBar.show(context, message, icon: AppSnackBar.errorIcon);
  }

  /// AI 配置编辑弹层（docs/29 §P4 需求 6/7：配置统一 + 连通性测试 + 模型
  /// 拉取/选择 + 推理开关）。协议 / Base URL / 模型 / API Key / 推理 全部
  /// 收进这一处；「测试连通性」成功后给出可筛选的模型列表，点选即填入
  /// 模型字段（列表拉不到时手输名字永远可用，永不阻塞用户）。
  Future<void> _openAiConfigSheet() async {
    // 弹层局部状态：保存在闭包里，经 setDialogState 刷新（弹层挂在根导航
    // 器上，页面的 setState 刷不到它——同文件备份/恢复弹层的既有做法）。
    String? errorText;
    bool probing = false;
    String? probeMessage;
    List<String> probeModels = const [];
    String modelQuery = '';

    // 探测用 Key：刚输入的优先，留空则用已保存的。
    //
    // 2026-10-16 设备实测缺陷：这里原先把「读已保存 Key 抛异常」吞成空串
    // （注释写着「让供应商的 401 自己说话」），于是应用升级后系统凭据被重置、
    // Key 读不出来的那种情况，会**不带 Authorization 头**去探测 ⇒ 供应商
    // 直接断开连接 ⇒ 界面写「网络连接不可用，请检查网络后重试。」——诊断被
    // 彻底带偏（真因是本机 Key 读不出来）。现在：读失败就**不发请求**，并给出
    // 可行动文案（重新填写并保存）。
    Future<String?> resolveProbeKey() async {
      final typed = _apiKey.text.trim();
      if (typed.isNotEmpty) return typed;
      final store = widget.apiKeyStore;
      if (store == null) return '';
      try {
        return await store.read() ?? '';
      } on Object {
        return null;
      }
    }

    // 落库失败的出口画在弹层里（同文件备份/恢复/清除弹层的既有做法）：
    // 弹层挂在根导航器上盖住整页，页面级 snackbar 会被遮住看不见。
    await AppSheet.showForm<void>(
      context,
      title: 'AI 配置',
      body: (dialogContext, setDialogState) => Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LfSelectField<AiProviderProtocol>(
              fieldKey: const Key('ai-protocol'),
              label: '协议',
              value: _protocol,
              options: AiProviderProtocol.values,
              optionLabel: (protocol) => protocol.label,
              onChanged: (value) {
                setDialogState(() {
                  _protocol = value;
                  // 上一协议口径下的失败原因已不适用，换协议即清掉。
                  errorText = null;
                });
                // 协议一换，请求路径就变；Base URL 的校验口径（尾巴剥离）
                // 也跟着变，所以要立刻重验一次。
                _formKey.currentState?.validate();
              },
            ),
            const SizedBox(height: 8),
            LfTextField(
              fieldKey: const Key('ai-base-url'),
              label: 'Base URL',
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              hintText: 'https://api.example.com/v1',
              validator: _baseUrlError,
            ),
            const SizedBox(height: 8),
            LfTextField(
              fieldKey: const Key('ai-model'),
              label: '模型名称',
              controller: _model,
              validator: _modelError,
            ),
            const SizedBox(height: 8),
            // 连通性测试（docs/29 §P4 需求 7）：GET {base}/models，5s 超时，
            // 失败分档（401 Key 错 / 404 base 错 / 超时网络不可达），结果
            // 内联显示，不弹系统提示。
            LfSmallButton(
              key: const Key('ai-config-probe'),
              label: probing ? '正在测试…' : '测试连通性',
              busy: probing,
              onPressed: probing
                  ? null
                  : () async {
                      setDialogState(() {
                        probing = true;
                        probeMessage = null;
                        probeModels = const [];
                        errorText = null;
                      });
                      final apiKey = await resolveProbeKey();
                      if (!dialogContext.mounted) return;
                      if (apiKey == null) {
                        // 本机 Key 读不出来：这不是网络问题，也不是「没配 Key」
                        // ——如实说清楚，并告诉用户怎么做。
                        setDialogState(() {
                          probing = false;
                          probeMessage = kAiApiKeyUnreadableMessage;
                          probeModels = const [];
                        });
                        return;
                      }
                      final result = await _endpointProbe.probe(
                        baseUrl: _baseUrl.text,
                        protocol: _protocol,
                        apiKey: apiKey,
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        probing = false;
                        probeMessage = result.isSuccess
                            ? '连通成功，发现 ${result.models.length} 个模型'
                            : result.message;
                        probeModels = result.models;
                      });
                    },
            ),
            if (probeMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                probeMessage!,
                key: const Key('ai-config-probe-result'),
                style: LfText.bodySmall.copyWith(
                  color: probeModels.isEmpty
                      ? Theme.of(dialogContext).colorScheme.error
                      : Theme.of(dialogContext).colorScheme.primary,
                ),
              ),
            ],
            // 模型列表（探测成功后出现）：可搜索，点选即填入模型字段。
            if (probeModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('ai-model-search'),
                onChanged: (value) => setDialogState(() => modelQuery = value),
                style: LfText.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: '筛选模型…',
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final query = modelQuery.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? probeModels
                      : probeModels
                            .where((m) => m.toLowerCase().contains(query))
                            .toList();
                  if (filtered.isEmpty) {
                    return Text(
                      '没有匹配「$modelQuery」的模型',
                      style: LfText.bodySmall.copyWith(
                        color: context.lf.mutedForeground,
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 168),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < filtered.length; i++)
                            ChoiceChip(
                              key: Key('ai-model-option-$i'),
                              label: Text(filtered[i], style: LfText.bodySmall),
                              selected: _model.text.trim() == filtered[i],
                              onSelected: (_) {
                                _model.text = filtered[i];
                                setDialogState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
            LfSelectField<AiReasoningMode>(
              fieldKey: const Key('ai-reasoning'),
              label: '推理',
              value: _reasoning,
              options: AiReasoningMode.values,
              optionLabel: (mode) => mode.label,
              onChanged: (value) => setDialogState(() => _reasoning = value),
            ),
            const SizedBox(height: 8),
            LfTextField(
              fieldKey: const Key('ai-api-key'),
              label: 'API Key',
              controller: _apiKey,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              // Round7 阶段 6 · 缺陷 ㉕（渲染审看抓到）：未配置时占位原本是
              // `••••••••`——它与「已保存」的掩码长得一样，用户分不清「从没
              // 存过」和「已存了一把」（docs/33 §3.4 要求 未配置/已保存 两态
              // 可辨）。改成如实说明。
              hintText: _hasApiKey ? '已保存，留空保持不变' : '未配置 · 粘贴你的 API Key',
              validator: _apiKeyError,
            ),
            const SizedBox(height: 8),
            Text(
              '配置仅保存在本机；端点格式见「帮助文档」。',
              style: LfText.micro.copyWith(color: context.lf.mutedForeground),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText!,
                key: const Key('ai-config-sheet-error'),
                style: LfText.bodySmall.copyWith(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: (dialogContext, setDialogState) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_hasApiKey)
            // 清除凭据是破坏性动作 = B7（error 字色的实心按钮 + 二次确认）。
            LfDangerButton(
              key: const Key('ai-key-clear'),
              label: '清除 Key',
              onPressed: _saving
                  ? null
                  : () async {
                      final cleared = await _confirmClearApiKey();
                      if (cleared && dialogContext.mounted) {
                        setDialogState(() {});
                      }
                    },
            ),
          LfTextButton(
            label: '取消',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          // 弹层底部主行动 = B2（`拍照识餐.html:513` 的 full 圆角确认档）。
          LfConfirmButton(
            key: const Key('ai-config-sheet-save'),
            label: _saving ? '正在保存…' : '保存',
            busy: _saving,
            expand: false,
            onPressed: _saving
                ? null
                : () async {
                    setDialogState(() => errorText = null);
                    final ok = await _saveConfig(
                      // 弹层可能已被用户关掉（保存期间点取消/遮罩），
                      // 此时不能再 setDialogState。
                      onError: (message) {
                        if (dialogContext.mounted) {
                          setDialogState(() => errorText = message);
                        }
                      },
                    );
                    if (ok && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _exportMealsCsv() async {
    final path = await widget.exportCsvFiles!.mealsCsv();
    if (!mounted) return;
    _showMessage(
      path == null ? '已取消保存。' : '饮食 CSV 已保存：$path',
      icon: path == null ? AppSnackBar.infoIcon : AppSnackBar.successIcon,
    );
  }

  Future<void> _exportTrainingCsv() async {
    final path = await widget.exportCsvFiles!.trainingCsv();
    if (!mounted) return;
    _showMessage(
      path == null ? '已取消保存。' : '训练 CSV 已保存：$path',
      icon: path == null ? AppSnackBar.infoIcon : AppSnackBar.successIcon,
    );
  }

  Future<void> _exportFoodsCsv() async {
    final path = await widget.exportCsvFiles!.foodsCsv();
    if (!mounted) return;
    _showMessage(
      path == null ? '已取消保存。' : '食物库 CSV 已保存：$path',
      icon: path == null ? AppSnackBar.infoIcon : AppSnackBar.successIcon,
    );
  }

  /// 版本标签（17c）：**永不为「版本未知」**。
  ///
  /// 2026-10-25 用户实测看到「版本未知」——根因是构建时漏传
  /// `--dart-define=APP_VERSION=`。这里不再把「没注入」渲染成一句话，
  /// 而是回落到随包常量（`lib/app/app_version.dart`）——那也是一个**真实的**
  /// 构建号，不是编的。构建脚本 `tool/build_release.bat` 负责注入每个 ABI 的
  /// versionCode。
  String get _versionLabel =>
      'v${resolveAppVersion(injected: widget.appVersion)}';

  /// 关于弹层：应用名 + 版本 + 本地运行声明。
  Future<void> _openAboutSheet() {
    return AppSheet.show<void>(
      context,
      title: '关于 LocalFit AI',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('版本 $_versionLabel'),
          const SizedBox(height: 8),
          // 【2026-11-02 用户：文字说明太多，该有的放帮助里】长句删掉，
          // 保留一句事实标签；隐私细节在「帮助文档」里。
          const Text('数据仅保存在本机；AI 只在你主动调用时联网。'),
        ],
      ),
      actions: Builder(
        builder: (sheetContext) => Align(
          alignment: Alignment.centerRight,
          child: LfTextButton(
            label: '知道了',
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  /// **在线更新**（需求 17b，2026-10-25）：查最新版 → 有事说事。
  ///
  /// 【这条以前是假按钮】原来点它只弹一句「本应用完全本地运行，不会联网检查
  /// 更新」——而仓库早已 public、Release 也带了三个 ABI 的包。用户要的是
  /// 「点击检查更新并安装」，所以先把假话删掉，再真做：
  ///
  /// 1. `GET releases/latest` 拿最新 tag 与三个资产；
  /// 2. 用**本包 versionCode**（系统读出来的）与「本 ABI 那个包的 versionCode」
  ///    比大小——语义版本（0.1.0）在同一代内不变，比不出新旧；
  /// 3. 有新版：弹一层说明 + 「下载并安装」；下载完交给系统安装器
  ///    （FileProvider + ACTION_VIEW，见 `MainActivity.installApk`）；
  /// 4. 已是最新 / 连不上 / 没有本机可用的包：**各自如实说**，不假装检查过。
  Future<void> _checkUpdate() async {
    if (_updating) return;
    _updating = true;
    if (mounted) setState(() {});
    try {
      final service = widget.appUpdateService ?? AppUpdateService();
      AppSnackBar.show(context, '正在检查更新…', icon: AppSnackBar.infoIcon);
      final check = await service.checkLatest(lanBaseUrl: _lanUpdateUrl);
      if (!mounted) return;
      switch (check.kind) {
        case AppUpdateCheckKind.upToDate:
          AppSnackBar.show(
            context,
            '已是最新（$_versionLabel，versionCode ${check.localVersionCode}）。',
            icon: AppSnackBar.successIcon,
          );
        case AppUpdateCheckKind.failed:
          AppSnackBar.show(
            context,
            check.message ?? '检查更新失败。',
            icon: AppSnackBar.errorIcon,
          );
        case AppUpdateCheckKind.available:
          await _showUpdateSheet(service, check);
      }
    } finally {
      _updating = false;
      if (mounted) setState(() {});
    }
  }

  /// 「发现新版本」弹层：说清版本号与包大小，再给一个真的会下载的按钮。
  Future<void> _showUpdateSheet(
    AppUpdateService service,
    AppUpdateCheck check,
  ) async {
    final asset = check.asset!;
    final release = check.release!;
    final sizeText = (asset.sizeBytes ?? 0) <= 0
        ? '大小未知'
        : formatMegabytes(asset.sizeBytes!);
    final confirmed = await AppSheet.show<bool>(
      context,
      title: '发现新版本',
      content: Column(
        key: const Key('update-available-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${release.tagName}（本机 versionCode ${check.localVersionCode} → '
            '${asset.versionCode}）',
            style: LfText.bodyStrong.copyWith(color: context.lf.cardForeground),
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text(
            '将下载 ${asset.name}（$sizeText）并交给系统安装。',
            style: LfText.caption.copyWith(color: context.lf.mutedForeground),
          ),
        ],
      ),
      actions: Builder(
        // 【2026-11-09 审查修复】原来是 Row + spaceBetween：320dp 屏扣掉
        // 内边距后只有 288dp，两个按钮自然宽约 300dp ⇒ 2.0 字号下溢出。
        // `OverflowBar` 放不下时自动把按钮竖排（与 AppSheet 提交表单同口径）。
        builder: (sheetContext) => OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: LfDimens.spaceSmall,
          overflowSpacing: LfDimens.spaceXSmall,
          children: [
            LfTextButton(
              label: '以后再说',
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
            LfPrimaryButton(
              key: const Key('update-download-install'),
              label: '下载并安装',
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    await _downloadAndInstall(service, asset);
  }

  /// 下载期间**不再只给一句静态 SnackBar**（2026-11-04 用户：「根本不知道
  /// 下载到什么进度了」）：改为弹出进度弹层（百分比 + 已下载字节 + 取消），
  /// 结局（交给安装器 / 要权限 / 失败 / 取消）关层后如实提示。
  Future<void> _downloadAndInstall(
    AppUpdateService service,
    AppReleaseAsset asset,
  ) async {
    final result = await showUpdateDownloadSheet(
      context,
      service: service,
      asset: asset,
    );
    if (!mounted) return;
    // 遮罩/返回键返回 null 时，弹层已经立即发出取消，文件清理由 Dio 负责。
    // 不在这里宣称「已清理」：取消结果可能早于异步删除完成。
    final kind = result?.kind ?? AppUpdateInstallKind.cancelled;
    AppSnackBar.show(
      context,
      switch (kind) {
        AppUpdateInstallKind.installerOpened => '下载完成，已交给系统安装（在系统界面点安装即可）。',
        AppUpdateInstallKind.needPermission =>
          result?.message ?? '需要先允许本应用安装其它应用。',
        AppUpdateInstallKind.failed => result?.message ?? '安装没起来。',
        AppUpdateInstallKind.cancelled => '已取消下载。',
      },
      icon: switch (kind) {
        AppUpdateInstallKind.installerOpened => AppSnackBar.successIcon,
        AppUpdateInstallKind.needPermission => AppSnackBar.infoIcon,
        AppUpdateInstallKind.failed => AppSnackBar.errorIcon,
        AppUpdateInstallKind.cancelled => AppSnackBar.infoIcon,
      },
    );
  }
}

extension _BackupDialogs on _SettingsPageState {
  /// 打开数据自检弹层（D-1/D-2）。关了后重读页面概要（自检的修复会改库）。
  Future<void> _openDataSelfCheck() async {
    await showDataSelfCheckSheet(context, selfCheck: widget.dataSelfCheck!);
  }

  Future<void> _openExportDialog() async {
    var password = '';
    var confirm = '';
    String? errorText;
    var saving = false;
    await AppSheet.showForm<void>(
      context,
      title: '导出加密备份',
      body: (dialogContext, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LfTextField(
            fieldKey: const Key('backup-export-password'),
            label: '备份口令',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => password = value,
          ),
          const SizedBox(height: 8),
          LfTextField(
            fieldKey: const Key('backup-export-password2'),
            label: '再次输入口令',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => confirm = value,
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: (dialogContext, setDialogState) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LfTextButton(
            label: '取消',
            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
          ),
          LfConfirmButton(
            key: const Key('backup-export-confirm'),
            label: saving ? '正在导出…' : '导出并保存',
            busy: saving,
            expand: false,
            onPressed: saving
                ? null
                : () async {
                    if (password.trim().isEmpty) {
                      setDialogState(() => errorText = '请输入备份口令。');
                      return;
                    }
                    if (password != confirm) {
                      setDialogState(() => errorText = '两次输入的口令不一致。');
                      return;
                    }
                    setDialogState(() => saving = true);
                    try {
                      final path = await widget.createEncryptedBackup!.run(
                        password: password,
                      );
                      if (!dialogContext.mounted) return;
                      // D-2（docs/64）：备份成功就记时间，自检页的
                      // 「最近一次备份」读这一个键（没有就如实说没备份过）。
                      if (path != null) {
                        await widget.appSettingsRepository?.setString(
                          AppSettingsRepository.lastBackupAtKey,
                          DateTime.now().millisecondsSinceEpoch.toString(),
                        );
                      }
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      _showMessage(
                        path == null ? '已取消保存。' : '备份已保存：$path',
                        icon: path == null
                            ? AppSnackBar.infoIcon
                            : AppSnackBar.successIcon,
                      );
                    } on LfbBackupFailure catch (failure) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        saving = false;
                        errorText = failure.message;
                      });
                    } catch (_) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        saving = false;
                        errorText = '导出失败，请重试。';
                      });
                    }
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _openRestoreDialog() async {
    var password = '';
    String? errorText;
    var restoring = false;
    await AppSheet.showForm<void>(
      context,
      title: '恢复备份',
      body: (dialogContext, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('恢复会用备份内容替换当前全部数据，且不可撤销。'),
          const SizedBox(height: 12),
          LfTextField(
            fieldKey: const Key('backup-restore-password'),
            label: '备份口令',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => password = value,
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: (dialogContext, setDialogState) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LfTextButton(
            label: '取消',
            onPressed: restoring
                ? null
                : () => Navigator.of(dialogContext).pop(),
          ),
          LfConfirmButton(
            key: const Key('backup-restore-confirm'),
            label: restoring ? '正在恢复…' : '选择文件并恢复',
            busy: restoring,
            expand: false,
            onPressed: restoring
                ? null
                : () async {
                    if (password.trim().isEmpty) {
                      setDialogState(() => errorText = '请输入备份口令。');
                      return;
                    }
                    setDialogState(() => restoring = true);
                    try {
                      final summary = await widget.restoreEncryptedBackup!.run(
                        password: password,
                      );
                      if (summary != null) _refreshAfterDataReplacement();
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      if (summary != null) {
                        // 2026-10-21 RV-P2-12：数据已替换成功；索引重建没
                        // 入队时如实说「数据已恢复、索引待重建」，不报失败。
                        // docs/67 §7.4：`.lfb` 不含图片字节，跨设备恢复后
                        // 照片/语音会缺——如实说出缺几张，不写"完整恢复"。
                        final missingNote = summary.missingMediaCount > 0
                            ? '；${summary.missingMediaCount} 张照片/语音在本机不存在'
                                  '（备份只带路径，不含图片字节）'
                            : '';
                        _showMessage(
                          summary.indexRebuildPending
                              ? '备份已恢复（导出于 ${summary.exportedAt}）；'
                                    '派生索引待重建，搜索可能暂时退化$missingNote。'
                              : '备份已恢复（导出于 ${summary.exportedAt}）$missingNote。',
                          icon:
                              summary.indexRebuildPending ||
                                  summary.missingMediaCount > 0
                              ? AppSnackBar.infoIcon
                              : AppSnackBar.successIcon,
                        );
                      }
                    } on LfbBackupFailure catch (failure) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        restoring = false;
                        errorText = failure.message;
                      });
                    } on FormatException catch (error) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        restoring = false;
                        errorText = error.message;
                      });
                    } catch (_) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        restoring = false;
                        errorText = '恢复失败，当前数据未受影响。';
                      });
                    }
                  },
          ),
        ],
      ),
    );
  }

  /// 「清空内置食物」入口（docs/32 §4 T11 需求 75）：确认弹层 → 执行 → 就地刷新。
  ///
  /// 弹层上的数字是**现算的**（[ClearBuiltinFoods.preview]），不是概览里的
  /// 旧快照：那是「加载那一刻」的数，用户可能已经翻了几分钟，而确认框要写
  /// 的是「将要发生的事」。预览为空时不弹层——拿一个「删 0 条」的确认框当
  /// 流程是请用户做无用功（那条路径如实回一句「没有内置食物可清空」）。
  Future<void> _openClearBuiltinFoodsSheet(ClearBuiltinFoods clear) async {
    final ClearBuiltinFoodsPreview preview;
    try {
      preview = await clear.preview();
    } catch (_) {
      // 读库失败不假装：没有数字就不摆确认框。
      _showMessage('没有读到食物库数据，请稍后再试。', icon: AppSnackBar.errorIcon);
      return;
    }
    if (!mounted) return;
    if (preview.isEmpty) {
      // 竞态：行是按旧概览画的，别处已经清过。如实说，并把行本身带回真实态。
      _refreshOverviewAfterFoodWrite();
      _showMessage('没有内置食物可清空。', icon: AppSnackBar.infoIcon);
      return;
    }

    var clearing = false;
    String? errorText;
    await AppSheet.showForm<void>(
      context,
      title: '清空内置食物数据？',
      body: (sheetContext, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _clearBuiltinFoodsBody(preview),
            key: const Key('clear-builtin-foods-body'),
          ),
          if (errorText != null) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Text(
              errorText!,
              style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: (sheetContext, setSheetState) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LfTextButton(
            label: '取消',
            onPressed: clearing ? null : () => Navigator.of(sheetContext).pop(),
          ),
          // 与「清除所有数据」同一条既有形式（§3.8 B7）：error 字色的**文字**
          // 按钮，不是实心 error 底——设计稿里没有后者。
          LfDangerButton(
            key: const Key('clear-builtin-foods-confirm'),
            label: clearing ? '正在清空…' : '清空内置食物数据',
            busy: clearing,
            onPressed: clearing
                ? null
                : () async {
                    setSheetState(() => clearing = true);
                    final ClearBuiltinFoodsResult result;
                    try {
                      result = await clear.call();
                    } catch (_) {
                      // 失败要复位并说明，否则弹层永久卡在「正在清空…」。
                      // 用例是单事务：失败就是没删成，这里敢说「请再点一次」。
                      if (!sheetContext.mounted) return;
                      setSheetState(() {
                        clearing = false;
                        errorText = '清空未完成，请再点一次；仍失败请检查设备存储空间。';
                      });
                      return;
                    }
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    if (!mounted) return;
                    // 计数行与这行的渲染都读同一个 future：重读一次，
                    // 两处一起回到真实态（弹层返回不触发 TickerMode 重读）。
                    _refreshOverviewAfterFoodWrite();
                    _showMessage(
                      _clearBuiltinFoodsResultText(result),
                      icon: AppSnackBar.deleteIcon,
                    );
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _openClearAllDialog() async {
    var confirmation = '';
    var clearing = false;
    String? errorText;
    await AppSheet.showForm<void>(
      context,
      title: '清除全部本地数据？',
      body: (dialogContext, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '将删除全部档案、餐食、训练与统计，以及导入的校园菜单；'
            '内置食物库（含导入的食物）会保留，可在「食材库」里单独清空。'
            '此操作不可撤销，也不会删除已导出的备份文件。',
          ),
          const SizedBox(height: 12),
          LfTextField(
            fieldKey: const Key('backup-clear-confirm-text'),
            label: '输入「全部清除」以确认',
            onChanged: (value) => setDialogState(() => confirmation = value),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              errorText!,
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: (dialogContext, setDialogState) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LfTextButton(
            label: '取消',
            onPressed: clearing
                ? null
                : () => Navigator.of(dialogContext).pop(),
          ),
          // 「清除所有数据」= §3.8 B7（`我的.html:524-532`）：error 字色的
          // **文字**按钮，不是实心 error 底——设计稿里没有后者。
          LfDangerButton(
            key: const Key('backup-clear-confirm'),
            label: clearing ? '正在清除…' : '全部清除',
            busy: clearing,
            onPressed: confirmation.trim() != '全部清除' || clearing
                ? null
                : () async {
                    setDialogState(() => clearing = true);
                    try {
                      await widget.clearAllLocalData!.clear();
                    } catch (_) {
                      _refreshAfterDataReplacement();
                      // 清除失败必须复位 clearing 并展示错误，否则弹层永久卡在「正在清除…」。
                      // 不写「数据未受影响」：数据库行的事务在字节清理之前就已
                      // 提交，失败多半发生在图片/原文这一步，此时数据其实已经
                      // 删了（2026-10-08 缺陷排查）。这里只说清楚状态未知 + 怎么办。
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        clearing = false;
                        errorText = '清除未完成，请再点一次；仍失败请检查设备存储空间。';
                      });
                      return;
                    }
                    _refreshAfterDataReplacement();
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    _showMessage('本地数据已全部清除。', icon: AppSnackBar.deleteIcon);
                  },
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {IconData? icon}) {
    if (!mounted) return;
    AppSnackBar.show(context, message, icon: icon);
  }
}

/// 确认弹层正文（docs/32 §4 T11）：只念非零的账。M / K 为 0 的那句整条不提——
/// 「0 条记录会受影响」不是信息，是噪音。数字走项目的千位分隔符口径。
String _clearBuiltinFoodsBody(ClearBuiltinFoodsPreview preview) {
  return [
    '将删除 ${formatGroupedInt(preview.builtinFoods)} 条内置食物（自建食物保留）。',
    if (preview.linkedMealItems > 0)
      '有 ${formatGroupedInt(preview.linkedMealItems)} 条饮食记录引用了这些食物：'
          '记录本身保留，其中的食物会被清空。',
    if (preview.menuMatches > 0)
      '有 ${formatGroupedInt(preview.menuMatches)} 条菜单匹配会移除'
          '（菜品行保留，菜单页会重新给建议）。',
    '设置、AI 配置与照片不受影响；此操作不可撤销。',
  ].join('\n');
}

/// 执行后的如实报数（snackbar）。一条都没删也算一种结局，照实说。
String _clearBuiltinFoodsResultText(ClearBuiltinFoodsResult result) {
  if (result.deletedFoods == 0) return '没有内置食物可清空。';
  final unlinked = result.unlinkedMealItems > 0
      ? '，${formatGroupedInt(result.unlinkedMealItems)} 条记录的食物引用已清空'
      : '';
  return '已清空内置食物：删除 ${formatGroupedInt(result.deletedFoods)} 条$unlinked。';
}

/// 设置页「步数与身体活动」行（docs/30 §2 D9 / 需求 3）。
///
/// **四种状态各自说实话**，短词只回答「现在能不能读」，不猜：
/// `available` → 已授权、`denied` → 未授权、`noSensor` → 设备不支持、
/// 其余（含 `noReading` 与首帧未读到）→ 状态未知。
///
/// 读数用 [StepsChannel.read]（经 [StepsRepository.readAvailability]）——
/// **与今日页步数卡同一个来源**，所以两处不会各说一套。这里**不请求权限、
/// 不落库**：请求动作只在今日页步数卡（用户看到卡片才会想授权），设置页
/// 只负责「看状态 + 去系统设置」。
///
/// 状态用 [LfBadge] 表达而不是 `SettingRow.value`：短词要**带底色**才能一眼
/// 分清「可用 / 不可用」，而 `value` 格是纯文字（muted），四态在它上面长得
/// 一模一样。
class _StepsPermissionRow extends StatefulWidget {
  const _StepsPermissionRow({
    required this.repository,
    required this.onOpenSheet,
  });

  final StepsRepository repository;
  final VoidCallback onOpenSheet;

  @override
  State<_StepsPermissionRow> createState() => _StepsPermissionRowState();
}

class _StepsPermissionRowState extends State<_StepsPermissionRow> {
  /// 本行自己的读数结果；null = 还没读到（显示「状态未知」，不显示假的
  /// 「已授权」）。
  StepsAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final availability = await widget.repository.readAvailability();
    if (!mounted) return;
    setState(() => _availability = availability);
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    // 状态 → (短词, 徽章档)。四态**不合并**：合并会把「用户点一下就能有」
    // 和「这台设备永远没有」画成同一句话。
    final (label, badge) = switch (availability) {
      StepsAvailability.available => ('已授权', LfBadge.mint('已授权')),
      StepsAvailability.denied => ('未授权', LfBadge.honey('未授权')),
      StepsAvailability.noSensor => ('设备不支持', LfBadge.neutral('设备不支持')),
      _ => ('状态未知', LfBadge.neutral('状态未知')),
    };
    return SettingRow(
      key: const Key('settings-steps-permission'),
      icon: Icons.directions_run_outlined,
      title: '步数与身体活动',
      trailing: Semantics(
        // 徽章本身是纯视觉标签，朗读时要说清它是什么的状态，否则读屏用户
        // 只听到一个孤立的「已授权」。
        label: '步数权限：$label',
        child: badge,
      ),
      showChevron: true,
      onTap: widget.onOpenSheet,
    );
  }
}

/// 设置页「饮食约束」行（C-2，docs/64）：值显示当前约束摘要（「素食 · 忌口
/// 2 项」/「未设置」——措辞来自 `PlanningConstraints.summaryLabel`），点开
/// 弹层；弹层回来后**重读**摘要（不许拿打开时的旧值继续显示）。仓储与弹层
/// 都在 daily_plan feature，这里只拿两个回调（分层门禁只许减）。
class _DietaryConstraintsRow extends StatefulWidget {
  const _DietaryConstraintsRow({required this.summary, required this.onOpen});

  final Future<String> Function() summary;
  final Future<void> Function() onOpen;

  @override
  State<_DietaryConstraintsRow> createState() => _DietaryConstraintsRowState();
}

class _DietaryConstraintsRowState extends State<_DietaryConstraintsRow> {
  String? _summary;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final summary = await widget.summary();
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  Future<void> _open() async {
    await widget.onOpen();
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final value = _summary ?? '';
    return SettingRow(
      key: const Key('settings-dietary-constraints'),
      icon: Icons.no_food_outlined,
      title: '饮食约束',
      trailing: Text(
        value,
        style: LfText.caption.copyWith(color: context.lf.mutedForeground),
      ),
      showChevron: true,
      onTap: _open,
    );
  }
}

/// 设置页「电子体重秤」行（docs/31 S6，需求 47 / D6）。
///
/// 与步数行同构：**三态各自说实话**，短词只回答「现在能不能同步」——
/// `ready` → 已授权、`denied` → 未授权、`unsupported` → 设备不支持
/// （API ≤ 30 或没有蓝牙适配器；D6 备注不加定位权限后的诚实降级），
/// 首帧未读到 → 状态未知。本行不请求权限、不扫描：动作只在说明弹层里。
class _ScalePermissionRow extends StatefulWidget {
  const _ScalePermissionRow({
    super.key,
    required this.sync,
    required this.onOpenSheet,
  });

  final ScaleSyncController sync;
  final VoidCallback onOpenSheet;

  @override
  State<_ScalePermissionRow> createState() => _ScalePermissionRowState();
}

class _ScalePermissionRowState extends State<_ScalePermissionRow> {
  /// null = 还没查到（显示「状态未知」，不显示假的「已授权」）。
  ScaleAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final availability = await widget.sync.availability();
    if (!mounted) return;
    setState(() => _availability = availability);
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    final (label, badge) = switch (availability) {
      ScaleAvailability.ready => ('已授权', LfBadge.mint('已授权')),
      ScaleAvailability.denied => ('未授权', LfBadge.honey('未授权')),
      ScaleAvailability.unsupported => ('设备不支持', LfBadge.neutral('设备不支持')),
      _ => ('状态未知', LfBadge.neutral('状态未知')),
    };
    return SettingRow(
      key: const Key('settings-scale-row'),
      icon: Icons.monitor_weight_outlined,
      title: '电子体重秤',
      trailing: Semantics(label: '体重秤同步：$label', child: badge),
      showChevron: true,
      onTap: widget.onOpenSheet,
    );
  }
}

/// 「电子体重秤」弹层主体（docs/31 S6 稿 ②③）：说明 → 扫描中（可取消）
/// → 结局交给 [_ScaleSheetBody.onOutcome]（在页面层呈现，弹层先关）。
class _ScaleSheetBody extends StatefulWidget {
  const _ScaleSheetBody({required this.sync, required this.onOutcome});

  final ScaleSyncController sync;
  final Future<void> Function(ScaleSyncOutcome outcome) onOutcome;

  @override
  State<_ScaleSheetBody> createState() => _ScaleSheetBodyState();
}

enum _ScaleSheetPhase { intro, scanning }

class _ScaleSheetBodyState extends State<_ScaleSheetBody> {
  _ScaleSheetPhase _phase = _ScaleSheetPhase.intro;

  Future<void> _startSync() async {
    setState(() => _phase = _ScaleSheetPhase.scanning);
    final outcome = await widget.sync.sync();
    // 用户点「取消同步」已经把弹层关了：结局没处呈现，也不该再弹任何东西。
    if (!mounted) return;
    Navigator.pop(context);
    await widget.onOutcome(outcome);
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _ScaleSheetPhase.scanning) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              key: Key('scale-sync-progress'),
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('请站上秤并保持稳定', style: LfText.body),
                SizedBox(height: 4),
                Text('最多等待 10 秒，期间可取消', style: LfText.bodySmall),
              ],
            ),
          ),
          LfTextButton(
            key: const Key('scale-sync-cancel'),
            label: '取消同步',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          key: Key('scale-permission-sheet-body'),
          '上秤后点同步；仅前台扫描约 10 秒，读数只存本机。',
          style: LfText.bodySmall,
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        LfConfirmButton(
          key: const Key('scale-action-sync'),
          label: '授权并开始同步',
          expand: true,
          onPressed: _startSync,
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        LfTextButton(
          key: const Key('scale-action-app-settings'),
          label: '去系统设置',
          onPressed: () async {
            // 先关弹层再跳：与步数行同一理由。
            Navigator.pop(context);
            await widget.sync.source.openAppSettings();
          },
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        Center(
          child: LfTextButton(
            label: '取消',
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}

/// 「添加食物数据」弹层里的大动作块（docs/31 S5 稿 ③）：图标 + 标题 +
/// 一句说明，整块可点。与「手动添加 / 导入 CSV」一一对应。
/// 页头（Round7 A `app.js:271`）：标题 + 一句副题，页内滚动、与身份卡同列。
class _SettingsPageHead extends StatelessWidget {
  const _SettingsPageHead();

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '我的',
          key: const Key('settings-page-title'),
          style: LfText.title.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: 2),
        Text(
          '关于你，也关于你的数据',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }
}

/// 页脚固定隐私徽章（docs/21 §5.6）。
class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('privacy-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: LfColors.mint(Theme.of(context).brightness).tone(50),
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 缺陷 ㉓：原来是 `Text('🛡')`——本仓无 emoji 字体（帧里空方框），
            // 且 A 的这一格是线稿 `shield` 图标。
            Icon(
              Icons.shield_outlined,
              size: 14,
              color: LfColors.mintText(Theme.of(context).brightness),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '所有数据仅保存在这台设备',
                style: LfText.label.copyWith(color: context.lf.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 帮助文档正文（docs/21 §5.6 📱；**需求 17d** 2026-10-25）。
///
/// 【为什么从 7 组硬编码问答改成随包 Markdown】用户原话是「优化帮助文档」。
/// 硬编码问答有三个问题：改一句要动 Dart（评审噪音大）、小标题/列表写不出来
/// （`Column` 里只有纯文本）、内容与行为的一致性没人保证。
///
/// 现在内容住在 `assets/help/*.md`（**随包、离线可读**），由**既有**的
/// `LfMarkdown` 渲染器渲染——不引新依赖，也复用对话气泡那套 Markdown 语言。
///
/// **诚实边界不变**：文档里不许出现与行为矛盾的隐私断言（「不会上传到任何
/// 服务器」之类），这条由 `settings_page_test` 的断言继续钉住。
class _HelpContent extends StatefulWidget {
  const _HelpContent({this.loader});

  /// 注入的正文加载器；null = 读随包资产（生产路径）。
  final Future<String> Function()? loader;

  /// 随包帮助文档（顺序即展示顺序）。
  static const List<String> assetPaths = [
    'assets/help/00-guide.md',
    'assets/help/01-data-and-privacy.md',
    'assets/help/02-ai-boundaries.md',
    'assets/help/03-recording.md',
    'assets/help/04-canteen-and-target.md',
    'assets/help/05-troubleshooting.md',
  ];

  @override
  State<_HelpContent> createState() => _HelpContentState();
}

class _HelpContentState extends State<_HelpContent> {
  /// 读一次即缓存：弹层反复开会重建，但资源内容不变。
  Future<String>? _content;

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  Future<String> _load() async {
    final injected = widget.loader;
    if (injected != null) return injected();
    final parts = <String>[];
    for (final path in _HelpContent.assetPaths) {
      try {
        parts.add((await rootBundle.loadString(path)).trim());
      } on Object {
        // 资产缺失如实说明（不静默少一段：帮助文档少一节用户看不出来）。
        parts.add('（这一节没能读出来：$path）');
      }
    }
    // 两节之间空一行（Markdown 段落分隔）。
    return parts.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    if (content == null) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: content,
      builder: (context, snapshot) {
        final text = snapshot.data;
        if (text == null) {
          // **不用转圈**：无限动画会让 `pumpAndSettle` 永远等不到静止
          // （实测：帮助弹层的用例因此超时）。读取只在本地资产上做，一瞬间
          // 的事，静态占位足够，也更好测。
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: LfDimens.spaceMedium),
            child: Text('正在读取帮助文档…'),
          );
        }
        return SizedBox(
          key: const Key('help-markdown'),
          width: double.infinity,
          child: LfMarkdown(text: text),
        );
      },
    );
  }
}

/// 反馈说明（docs/21 §5.6 📱；**需求 17e** 2026-10-25）。
///
/// 三件事各归其位：
/// 1. **没有内置上报通道**这句事实保留（原来就有，用户没让删——不许为了让
///    页面好看就把实话说没了）；
/// 2. 给一个**能点的链接**（GitHub issue 新建页）——它真的能打开浏览器；
/// 3. 给「复制环境信息」——不依赖任何外部服务，一键把报问题要的四件事复制好。
class _FeedbackContent extends StatelessWidget {
  const _FeedbackContent({required this.onOpenIssue, required this.onCopyEnv});

  final Future<void> Function() onOpenIssue;
  final Future<void> Function() onCopyEnv;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.lf;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 口径与原来逐字一致的那句事实说明（用户没要求删，就不删）。
        Text('没有内置上报通道', style: theme.textTheme.titleSmall),
        const SizedBox(height: LfDimens.spaceMedium),
        Text(
          '出错不会自动回传；只有你主动使用 AI 时才联网。',
          style: LfText.bodySmall.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        // 链接本身就是文案的一部分：用户能核对链接指向哪儿（不是藏在一个
        // 「点我」后面）。
        Text(
          SettingsPage.feedbackIssueUrl,
          key: const Key('feedback-issue-url'),
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        LfPrimaryButton(
          key: const Key('feedback-open-issue'),
          label: '去 GitHub 提 issue',
          icon: Icons.open_in_new,
          onPressed: () => unawaited(onOpenIssue()),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        LfTextButton(
          key: const Key('feedback-copy-env'),
          label: '复制环境信息',
          icon: Icons.copy_all_outlined,
          onPressed: () => unawaited(onCopyEnv()),
        ),
      ],
    );
  }
}

/// 顶部身份卡：薄荷 100→50 浅渐变 + 目标 emoji + 「减脂 · 每日 2,100 kcal」
/// + 三色目标 chips（docs/21 §5.6；渐变三处允许之一）。

/// 身份卡（docs/21 §5.6）：hero 渐变 + 16 全圆角 + 径向点纹理 + 头像/姓名/
/// 编辑药丸 + 三段统计（当前体重 / 总记录 / 连续天数）。
///
/// §6.1：姓名在 `Profiles` 无数据列 → 头像与姓名都用「Fit」兜底（与今日页
/// 问候头像同一口径），不编用户名；体重/目标缺一项就省那一段副标题。
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.overviewFuture,
    this.onEdit,
    this.onEditName,
    this.onPickAvatar,
    this.identityFuture,
    this.onOpenWeightHistory,
  });

  final Future<ProfileOverview?>? overviewFuture;

  /// 「编辑资料」药丸（docs/21 §5.6）：跳既有资料编辑页。
  final VoidCallback? onEdit;

  /// 点昵称/铅笔 → 昵称编辑弹层（docs/32 §3 D9）。null = 不可编辑（测试/未接线）。
  final VoidCallback? onEditName;

  /// 点头像 → 选图（docs/32 §3 D9）。null = 不可点。
  final VoidCallback? onPickAvatar;

  /// 「当前体重」格的点击（Round7 裁决 R5）。null = 不包裹点击层。
  final VoidCallback? onOpenWeightHistory;

  /// 身份事实（昵称/头像）。null 或未完成 → 回退「Fit」。
  final ValueNotifier<IdentityProfile?>? identityFuture;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      key: const Key('settings-identity-card'),
      child: FutureBuilder<ProfileOverview?>(
        future: overviewFuture,
        builder: (context, snapshot) {
          final overview = snapshot.data;
          // docs/32 §3 D9：昵称/头像**必须随身份事实的异步到达重建**——
          // `ValueNotifier` 的变化不会触发外层 `FutureBuilder`（它只跟
          // `overviewFuture` 的 ticket 走）。实测（无 `ListenableBuilder` 时）
          // 页面恒显「Fit」，即使仓库已返回昵称。
          final identityNotifier = identityFuture;
          return ListenableBuilder(
            listenable:
                identityNotifier ?? ValueNotifier<IdentityProfile?>(null),
            builder: (context, _) {
              final identity = identityNotifier?.value;
              final displayName = identity?.displayName;
              final avatarPath = identity?.avatarPath;
              final nameLabel =
                  (displayName == null || displayName.trim().isEmpty)
                  ? 'Fit'
                  : displayName;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头部一行：「我是谁」是这一行唯一的事——56dp 头像 + 姓名/副标题
                  // （可伸缩，长副标题省略号收尾，不挤压右侧动作）+「编辑资料」。
                  // 原来四行竖排（头像 / 姓名 / 副标题 / 药丸）占了卡高的一半空白。
                  // docs/32 §3 D9：头像与昵称块**垂直居中**、副标题整行删除、
                  // 头像与昵称各自可点（选图 / 改名）。
                  Row(
                    children: [
                      Semantics(
                        button: onPickAvatar != null,
                        label: onPickAvatar == null ? '用户头像' : '更换头像',
                        child: GestureDetector(
                          key: const Key('settings-avatar'),
                          onTap: onPickAvatar,
                          child: UserAvatar(
                            displayName: displayName,
                            avatarPath: avatarPath,
                            size: 56,
                            imageKey: const Key('settings-avatar-image'),
                            initialKey: const Key('settings-avatar-initial'),
                          ),
                        ),
                      ),
                      const SizedBox(width: LfDimens.spaceMedium),
                      Expanded(
                        child: GestureDetector(
                          key: const Key('settings-name'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onEditName,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  nameLabel,
                                  style: LfText.headline.copyWith(
                                    color: c.cardForeground,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (onEditName != null) ...[
                                const SizedBox(width: LfDimens.spaceTiny),
                                Icon(
                                  Icons.edit_outlined,
                                  size: LfDimens.iconSm,
                                  color: c.mutedForeground,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (onEdit != null) ...[
                        const SizedBox(width: LfDimens.spaceSmall),
                        LfTextButton(
                          key: const Key('cta-edit-profile'),
                          label: '编辑资料',
                          icon: Icons.edit_outlined,
                          onPressed: onEdit,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: LfDimens.spaceMediumPlus),
                  // 三段统计之间补 1px 分隔线：原来三列数字在底色之间漂，没有边界。
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _IdentityStat(
                          key: const Key('settings-stat-weight'),
                          value: _weightLabel(overview),
                          label: '当前体重',
                          onTap: onOpenWeightHistory,
                        ),
                        _IdentityDivider(color: c.border),
                        _IdentityStat(
                          key: const Key('settings-stat-records'),
                          value: overview == null
                              ? '—'
                              : _groupedNumber(overview.totalMealRecords),
                          label: '总记录',
                        ),
                        _IdentityDivider(color: c.border),
                        _IdentityStat(
                          key: const Key('settings-stat-streak'),
                          value: overview == null
                              ? '—'
                              : '${overview.streakDays} 天',
                          label: '连续天数',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _weightLabel(ProfileOverview? overview) {
    final weight = overview?.currentWeightKg;
    return weight == null ? '—' : '${weight.toStringAsFixed(1)} kg';
  }

  static String _groupedNumber(int value) {
    final text = value.toString();
    if (value < 0) return text;
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }
}

/// 三段统计之间的 1px 竖向分隔线（设计稿 `.statrow .d`：`width:1px`、
/// 上下留 2dp、左右 14dp）。**不能用 `Divider`**：那是横向的，要旋转。
class _IdentityDivider extends StatelessWidget {
  const _IdentityDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(
      horizontal: LfDimens.spaceMediumPlus,
      vertical: LfDimens.spaceMicro,
    ),
    color: color,
  );
}

/// 三段统计的一格（值 `headline` w800 墨色 + 标签 `micro` muted）。
///
/// 白卡化后不再需要「hero 上的双色」参数：文字色由卡的前景/次级色决定，
/// 与全 App 其余卡内文字同一规则（docs/21 §3.1）。
class _IdentityStat extends StatelessWidget {
  const _IdentityStat({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;

  /// 可点档（Round7 裁决 R5 的「当前体重」）：读屏标签说清点它会去哪，
  /// 视觉不变（身份卡三段统计本来就长得一样，不为它加一枚图标破坏等宽）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: LfText.headline.copyWith(
            color: c.cardForeground,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: LfDimens.spaceMicro),
        Text(label, style: LfText.micro.copyWith(color: c.mutedForeground)),
      ],
    );
    if (onTap == null) return Expanded(child: content);
    return Expanded(
      child: Semantics(
        button: true,
        label: '查看体重记录',
        child: GestureDetector(
          key: const Key('settings-stat-weight-open'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

/// 健康数据三张图形卡（docs/29 §P2 / 裁决 D10）：BMI 分档刻度尺、
/// 基础代谢率区间指示、水分摄入目标进度环——三种图形语言，不套同一根条。
///
/// 缺数据仍走诚实空态（「—」+ 空轨道，**不给档位文字**，不编演示值）；
/// BMR 带「kcal/天」单位（§6.2 裁决 8）。派生值一律来自
/// `LoadProfileOverview`，分档口径来自 `health_metric_bands.dart`。
class _HealthMetricsCard extends StatelessWidget {
  const _HealthMetricsCard({required this.overviewFuture});

  final Future<ProfileOverview?>? overviewFuture;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: LfDimens.spaceMicro,
            bottom: LfDimens.spaceSmall,
          ),
          // Round7 逐页对账批次 2：A `app.js:248` 的 `.section-title.with-link`
          // 两端形态——左「我的健康指标」、右 quiet-label「资料与今日记录」。
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '我的健康指标',
                  style: LfText.label.copyWith(color: c.mutedForeground),
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Text(
                '资料与今日记录',
                style: LfText.label.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
        ),
        FutureBuilder<ProfileOverview?>(
          future: overviewFuture,
          builder: (context, snapshot) {
            final overview = snapshot.data;
            final bmi = overview?.bmi;
            final tier = bmiTierOf(bmi);
            final bmr = overview?.bmrKcal;
            final position = bmrPositionOf(
              bmrKcal: bmr,
              calorieMinKcal: overview?.calorieMinKcal,
              calorieMaxKcal: overview?.calorieMaxKcal,
            );
            final calories = _calorieRangeLabel(overview);
            return Column(
              key: const Key('settings-health-metrics'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LfBandedScaleGauge(
                  key: const Key('settings-health-bmi'),
                  title: 'BMI',
                  valueLabel: bmi == null ? '—' : bmi.toStringAsFixed(1),
                  marker: bmi,
                  axisMin: 15,
                  axisMax: 35,
                  bands: const [
                    LfGaugeBand(
                      upperBound: 18.5,
                      label: '偏瘦',
                      tone: LfGaugeTone.neutral,
                    ),
                    LfGaugeBand(
                      upperBound: 24,
                      label: '正常',
                      tone: LfGaugeTone.success,
                    ),
                    LfGaugeBand(
                      upperBound: 28,
                      label: '超重',
                      tone: LfGaugeTone.warning,
                    ),
                    LfGaugeBand(
                      upperBound: null,
                      label: '肥胖',
                      tone: LfGaugeTone.danger,
                    ),
                  ],
                  badgeLabel: tier?.label,
                  badgeTone: switch (tier) {
                    null => LfGaugeTone.neutral,
                    BmiTier.thin => LfGaugeTone.neutral,
                    BmiTier.normal => LfGaugeTone.success,
                    BmiTier.over => LfGaugeTone.warning,
                    BmiTier.obese => LfGaugeTone.danger,
                  },
                ),
                const SizedBox(height: LfDimens.spaceSmall),
                // A `app.js:248` 的 BMI 边界说明（分档口径来自
                // `health_metric_bands.dart`，本句只是把它说明白）。
                Text(
                  '18.5 / 24 / 28 为分档边界，仅作健康参考',
                  key: const Key('settings-health-bmi-note'),
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(height: LfDimens.spaceSmall),
                LfBandTargetGauge(
                  key: const Key('settings-health-bmr'),
                  title: '基础代谢率',
                  valueLabel: bmr == null ? '—' : formatGroupedInt(bmr),
                  unit: bmr == null ? null : 'kcal/天',
                  marker: bmr?.toDouble(),
                  targetMin: overview?.calorieMinKcal,
                  targetMax: overview?.calorieMaxKcal,
                  targetLabel: calories,
                  badgeLabel: position?.label,
                  badgeTone: switch (position) {
                    null => LfGaugeTone.neutral,
                    BmrPosition.below => LfGaugeTone.neutral,
                    BmrPosition.within => LfGaugeTone.success,
                    BmrPosition.above => LfGaugeTone.warning,
                  },
                ),

                // 2026-10-16 用户：「去除水分摄入目标卡片」——健康区回到两格
                // （BMI + 基础代谢率）。饮水事实由今日页的饮水卡（已饮/目标 +
                // 达标 %）与加水弹层承载，这里不再重复一格。
              ],
            );
          },
        ),
      ],
    );
  }

  /// 目标热量区间的说明文字（「目标 1,900–2,100」）；缺区间返回 null。
  static String? _calorieRangeLabel(ProfileOverview? overview) {
    final min = overview?.calorieMinKcal;
    final max = overview?.calorieMaxKcal;
    if (min == null || max == null || max < min) return null;
    return '目标 ${formatGroupedInt(min.round())}–${formatGroupedInt(max.round())} kcal';
  }
}

/// 成就行卡（docs/29 §P3 需求 5）：铜/银/金三档 + 进度环 + 进度条 + `n/目标`。
///
/// 取代原来的「四格灰瓦片」：那四格既说不出进度（只分解锁/未解锁两态），
/// 又在 2.0× 字号下把名称挤成两行。现在每行自证三件事——等级（徽标 + 环色）、
/// 进度（环 + 条）、还差多少（`n/目标`）。
///
/// 等级与计数都由 `features/settings/domain/achievement_levels.dart` 派生
/// （**不落库、不改 schema**），这里只做「业务枚举 → 设计枚举」的映射。
class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({required this.overviewFuture});

  final Future<ProfileOverview?>? overviewFuture;

  static const _icons = <String, IconData>{
    'streak-7': Icons.local_fire_department_outlined,
    'nutrition-master': Icons.restaurant_menu,
    'workout-athlete': Icons.fitness_center,
    'healthy-diet': Icons.apple_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return FutureBuilder<ProfileOverview?>(
      future: overviewFuture,
      builder: (context, snapshot) {
        final achievements =
            snapshot.data?.achievements ?? _defaultAchievements;
        final unlocked = achievements.where((row) => row.unlocked).length;
        // Round7 逐页对账批次 2：标题与已解锁总数按 A `app.js:252`
        // （「每一份坚持，都算数」+「N / N 已解锁」）；行本身一字未动。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsGroup(
              key: const Key('settings-achievements'),
              title: '每一份坚持，都算数',
              trailingLabel: '$unlocked / ${achievements.length} 已解锁',
              trailingKey: const Key('settings-achievements-unlocked'),
              children: [
                for (var i = 0; i < achievements.length; i++)
                  LfAchievementRow(
                    key: Key('settings-achievement-${i + 1}'),
                    label: achievements[i].label,
                    tier: _medalTierOf(
                      achievementLevelOf(achievements[i].progress),
                    ),
                    progress: achievements[i].progress,
                    unlocked: achievements[i].unlocked,
                    count: achievementCountOf(
                      progress: achievements[i].progress,
                      target: achievements[i].target,
                    ),
                    target: achievements[i].target,
                    icon: _icons[achievements[i].key],
                  ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceXSmall),
            // A `app.js:252` 的口径说明。**不是抄一句好话**：`progress`
            // 在库里的语义就是历史最大值（`achievement_levels.dart:13-16`），
            // 所以「不因删记录而回退」是本仓已经成立的事实。
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LfDimens.spaceMicro,
              ),
              child: Text(
                '进度为历史最高值，不因删记录而回退。',
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 业务档位 → 设计层色板（枚举不同名是故意的：设计层不认业务术语）。
  static LfMedalTier _medalTierOf(AchievementLevel level) => switch (level) {
    AchievementLevel.bronze => LfMedalTier.bronze,
    AchievementLevel.silver => LfMedalTier.silver,
    AchievementLevel.gold => LfMedalTier.gold,
  };

  /// 加载中/未接线时的占位四行：与真实数据同构（§7.2 未解锁态）。
  /// 名称与目标值都取自 [AchievementSpec]——**不再抄一遍字面量**。
  static List<ProfileAchievement> get _defaultAchievements => [
    for (final spec in AchievementSpec.values)
      ProfileAchievement(
        key: spec.key,
        label: spec.label,
        unlocked: false,
        progress: 0,
        target: spec.target,
      ),
  ];
}

/// 页脚（设计稿）：清除警示（error 70%）+ 版本。
class _DangerFooter extends StatelessWidget {
  const _DangerFooter({required this.appVersion});

  /// 版本号（已解析）：组件不再自己判「有没有」，[resolveAppVersion] 保证非空。
  final String? appVersion;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final version = 'v${resolveAppVersion(injected: appVersion)}';
    // 【2026-11-02 用户：文字说明太多，只留标签】页脚只保留版本；清除后果
    // 已在确认弹层里完整说明，品牌句是装饰性文案，整段退场。
    return Text(
      'LocalFit AI $version',
      textAlign: TextAlign.center,
      style: LfText.caption.copyWith(color: c.mutedForeground),
    );
  }
}

/// 局域网更新地址弹层：controller 由本 State 持有并在 dispose 释放
/// （不能在 `showStateful` 返回后立刻 dispose——退场动画还在重建输入框）。
class _LanUpdateSheet extends StatefulWidget {
  const _LanUpdateSheet({required this.initialUrl, required this.onDone});

  final String initialUrl;
  final ValueChanged<String> onDone;

  @override
  State<_LanUpdateSheet> createState() => _LanUpdateSheetState();
}

class _LanUpdateSheetState extends State<_LanUpdateSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialUrl,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('lan-update-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '填电脑上跑下载服务的地址，例如 http://10.26.8.28:8080/。'
          '配置后「检查更新」会先走局域网，失败再回 GitHub。',
          style: LfText.caption.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        LfTextField(
          fieldKey: const Key('lan-update-url'),
          label: '地址',
          hintText: 'http://10.26.8.28:8080/',
          controller: _controller,
          onChanged: (_) {},
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(label: '取消', onPressed: () => Navigator.pop(context)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LfTextButton(
                  key: const Key('lan-update-clear'),
                  label: '清除',
                  onPressed: () => widget.onDone(''),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                LfPrimaryButton(
                  key: const Key('lan-update-save'),
                  label: '保存',
                  onPressed: () => widget.onDone(_controller.text.trim()),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
