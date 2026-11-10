import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/app/app_version.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_source.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

import '../../support/update_download_fixture.dart';

void main() {
  /// 新版「我的」页比旧版高（身份卡 + 健康数据 + 成就 + 4 个分组）：
  /// 默认 800×600 下懒列表只构建前几节，下半屏的分组点了也断言不到。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('validates local HTTPS setup and never renders saved API Key', (
    tester,
  ) async {
    useTallViewport(tester);
    final store = _FakeAiProviderSettingsStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    // Base URL 与模型名在「AI 模型」行打开的配置弹层里（docs/21 §5.6 AI 组）。
    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pump();
    expect(find.text('请输入有效的 HTTPS Base URL'), findsOneWidget);
    expect(find.text('请填写模型名称'), findsOneWidget);
    expect(find.text('请填写 API Key'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai-base-url')),
      'http://api.example.com/v1',
    );
    await tester.enterText(find.byKey(const Key('ai-model')), 'vision-model');
    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pump();
    expect(find.text('请输入有效的 HTTPS Base URL'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai-base-url')),
      'https://api.example.com/v1',
    );
    // 首次保存必须填 Key：Key 框就在弹层里（docs/29 §P4 配置统一），
    // 字段校验直接画在弹层内，填上即保存成功。
    await tester.enterText(find.byKey(const Key('ai-api-key')), 'secret-key');
    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-config-sheet-save')), findsNothing);
    expect(store.saved, hasLength(1));
    expect(store.saved.single.baseUrl, 'https://api.example.com/v1');
    expect(store.saved.single.apiKey, 'secret-key');
    expect(find.text('secret-key'), findsNothing);
    expect(find.text('AI 配置已仅保存到本机。'), findsOneWidget);
  });

  testWidgets('弹层保存失败必须画在弹层里，且协议选择真的落库', (tester) async {
    // 真实缺陷回归（2026-10-02 模拟器走查抓到）：弹层挂在根导航器上盖住
    // 整页，页面级反馈用户看不见（「点了没反应」）。docs/29 §P4 起 Key 收进
    // 弹层，首次保存没有 Key 由**弹层内的字段校验**拦截——断言必须锁
    // 「校验错误可见于弹层内」这个语义：只查 find.text 会同时命中藏在
    // 弹层后面的任何同文案控件，所以要限定 BottomSheet 后代。
    useTallViewport(tester);
    final store = _FakeAiProviderSettingsStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-base-url')),
      'https://api.example.com/v1',
    );
    await tester.enterText(find.byKey(const Key('ai-model')), 'gpt-test-model');
    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pumpAndSettle();

    // 首次保存没有 Key：字段校验拦截，弹层不关、配置不落库。
    expect(store.saved, isEmpty);
    final errorFinder = find.text('请填写 API Key');
    expect(errorFinder, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('请填写 API Key'),
      ),
      findsOneWidget,
    );
    // 错误必须是可见的（同屏、有实际绘制尺寸），不是被盖住/收起的状态。
    expect(tester.getSize(errorFinder).height, greaterThan(0));

    // 首次填 Key 的主路径：Key 就在弹层里，填上直接保存成功关闭。
    await tester.enterText(find.byKey(const Key('ai-api-key')), 'secret-key');
    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pumpAndSettle();
    expect(store.saved, hasLength(1));

    // 有了 Key 之后弹层保存应当成功关闭，并且**协议选择随配置落库**
    // （docs/24 §7；模拟器走查时曾因保存被拒而无法证明这条）。
    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-protocol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Responses（OpenAI /v1/responses）').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-config-sheet-save')), findsNothing);
    expect(store.saved, hasLength(2));
    expect(store.saved.last.protocol, AiProviderProtocol.responses);
    // 推理档默认「关闭推理」随配置一起落库（docs/29 §P4）。
    expect(store.saved.last.reasoning, AiReasoningMode.disabled);
  });

  testWidgets('clears only API Key after explicit confirmation', (
    tester,
  ) async {
    useTallViewport(tester);
    final store = _FakeAiProviderSettingsStore(
      settings: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'vision-model',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    // 清除 Key 收进 AI 配置弹层（docs/29 §P4）。
    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-key-clear')));
    await tester.pumpAndSettle();
    expect(find.text('清除 API Key？'), findsOneWidget);

    // 确认弹层叠在配置弹层之上：取最上面的那个「取消」。
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(store.clearCalls, 0);

    await tester.tap(find.byKey(const Key('ai-key-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();

    expect(store.clearCalls, 1);
    // 清除后弹层里的「清除 Key」按钮即时消失（不弹 snackbar：弹层盖住页面，
    // 页面级提示用户看不见——docs/29 §P4 前这曾是真缺陷）。
    expect(find.byKey(const Key('ai-key-clear')), findsNothing);
  });

  testWidgets('按钮档位：弹层保存 = B2（full 圆角主行动）、清除 Key = B7（error 文字）', (
    tester,
  ) async {
    // 设计稿出处：弹层底部主行动 = B2（`拍照识餐.html:513` 的 full 圆角确认
    // 档）；`我的.html:524-532`「清除所有数据」是 error 字色的一行——设计稿
    // 里没有实心 error 按钮，所以清除凭据这类破坏性动作必须是文字型 B7。
    // （docs/29 §P4 起「保存」与「清除 Key」都住在 AI 配置弹层里。）
    useTallViewport(tester);
    final store = _FakeAiProviderSettingsStore(
      settings: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'vision-model',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.byKey(const Key('ai-config-sheet-save')),
    );
    // Round7 A：A 的按钮**只有** 12 圆角一档（`refinement.css:3`
    // `.btn{border-radius:12px}`，`.btn.confirm` 只改高度不改圆角）——旧稿
    // 「B2 = full 圆角胶囊」是 docs/21 §3.8 的形态，已被 A 覆盖。
    expect(
      (save.style!.shape!.resolve(
        const {},
      ) as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(LfDimens.buttonRadius),
      reason: 'B2 与其余按钮同取 A 的 12 圆角（不是胶囊）',
    );

    final clear = tester.widget<TextButton>(
      find.byKey(const Key('ai-key-clear')),
    );
    expect(
      clear.style?.foregroundColor?.resolve(<WidgetState>{}),
      // 2026-11-09：B7 字色改为文字档 errorText——填充档 error 当 14px
      // 正文在白卡上只有 3.68:1（压 muted 3.29:1），低于 AA 4.5:1。
      LfSemanticColors.light.errorText,
      reason: '破坏性动作用 errorText 字色的文字按钮（B7）',
    );
  });

  testWidgets('renders themed profile page sections and privacy badge', (
    tester,
  ) async {
    useTallViewport(tester);
    final store = _FakeAiProviderSettingsStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('AI 配置'), findsOneWidget);
    // 说明文案随 Base URL/模型一起收进了「AI 模型」行的配置弹层。
    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();
    // 说明文案是多行（隐私 + 协议路径说明），按包含式断言。
    expect(find.textContaining('配置仅保存在本机；端点格式见'), findsOneWidget);
    // 协议选择器在弹层里（docs/24 §2）：默认 Chat Completions＝旧行为。
    expect(find.byKey(const Key('ai-protocol')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // 无备份能力时隐私徽章仍然可见（页脚固定，需要滚到底）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('privacy-badge')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-badge')), findsOneWidget);
    expect(find.text('所有数据仅保存在这台设备'), findsOneWidget);
    // 危险区仅在具备备份能力时出现，此时不在页面上。
    expect(find.text('清除全部本地数据'), findsNothing);
  });

  testWidgets('Round7 裁决 R5：身份卡「当前体重」→ 只读「体重记录」弹层', (tester) async {
    useTallViewport(tester);
    final now = DateTime.utc(2026, 9, 12, 9);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            activityLevel: 'lightlyActive',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final measurements = MeasurementRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    await measurements.saveManualWeight(
      localDate: '2026-09-10',
      weightKg: 65.0,
    );
    await measurements.saveManualWeight(
      localDate: '2026-09-12',
      weightKg: 64.4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          measurementRepository: measurements,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-stat-weight-open')));
    await tester.pumpAndSettle();

    // 只读弹层：最新一条大字 + 全部记录行（日期 + kg + 来源）。
    expect(find.byKey(const Key('weight-history-sheet')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('weight-history-latest'))).data,
      '64.4 kg',
    );
    expect(
      find.byKey(const Key('weight-history-row-2026-09-12')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('weight-history-row-2026-09-10')),
      findsOneWidget,
    );
    expect(find.text('手输'), findsNWidgets(2));
    // **不搬** A 的「记录今天的体重」写入按钮：本弹层只读（写入通路在今日页
    // 体重卡），这条 findsNothing 是它的哨兵。
    expect(find.text('记录今天的体重'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Round7 逐页对账批次 2：健康与成就卡按 A（app.js:248,252）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_app(_FakeAiProviderSettingsStore()));
    await tester.pumpAndSettle();

    // 健康卡两端标签（A `.section-title.with-link`：左标题、右 quiet-label）。
    expect(find.text('我的健康指标'), findsOneWidget);
    expect(find.text('资料与今日记录'), findsOneWidget);
    // A 的 BMI 分档边界说明（口径来自 health_metric_bands.dart，未改一行）。
    expect(find.text('18.5 / 24 / 28 为分档边界，仅作健康参考'), findsOneWidget);
    // 成就卡：A 的标题 + 已解锁总数（四行全未解锁 ⇒ 0 / 4）。
    await tester.scrollUntilVisible(
      find.text('每一份坚持，都算数'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('0 / 4 已解锁'), findsOneWidget);
    // 不回退说明：口径已由 `achievement_levels.dart:13-16`（progress 是历史
    // 最大值）证实，不是抄 A 的一句好话。
    expect(find.text('进度为历史最高值，不因删记录而回退。'), findsOneWidget);
  });

  testWidgets('Round7 逐页对账：页头与页尾按 A（app.js:271）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_app(_FakeAiProviderSettingsStore()));
    await tester.pumpAndSettle();

    // A 的「我的」页头：标题 + 副题（徽章见下条）。
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('关于你，也关于你的数据'), findsOneWidget);
    // **不搬 A 的「本地优先」徽章**：docs/33 §3.8 明令「不再用『本地优先』
    // 概括所有流向」——外发（AI 调用/导出）是用户触发的事实，徽章会把
    // 它说没。本页已有的「所有数据仅保存在这台设备」+ 数据来源清单才是
    // 本仓的诚实说法。这条 findsNothing 是它的哨兵。
    expect(find.text('本地优先'), findsNothing);
    // 2026-11-02：页脚只留版本；品牌句与重复警告撤下。
    await tester.scrollUntilVisible(
      find.textContaining('LocalFit AI v'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('LocalFit AI v'), findsOneWidget);
    expect(find.text('让每一次记录，回到你自己。'), findsNothing);
  });

  // 【测试退役，2026-10-24 用户裁决】原「lists third-party food data sources
  // with their licences」整条退役：用户明确要求删除「数据来源与许可证」入口。
  //
  // 退役理由与替代保障（不是「删了省事」）：
  // * 用户先要求删界面入口，随后追加「**数据层也删**」——所以三层（公共值类型 +
  //   食物清单 + 动作清单）已全部删除，`lib/` 里不再有这类符号；
  // * **仍然守着的**：`privacy_statement_audit_test` 里那些真正的隐私/供应链
  //   审计（出网面、密钥、权限、manifest 许可证白名单、剥离来源脚本）一条未动；
  //   其中「ETL 许可证必须在白名单里」改成了直接对 manifest 断言（不再借 App 清单
  //   当白名单）；
  // * 开源组件许可（`showLicensePage`）随入口一起移除——它只在那个弹层里被
  //   调用，没有其它入口。
  testWidgets('「数据来源与许可证」入口已按用户要求删除', (tester) async {
    useTallViewport(tester);
    final store = _FakeAiProviderSettingsStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('数据来源与许可证'), findsNothing);
    expect(find.byKey(const Key('data-attribution')), findsNothing);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('反馈'),
      400,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-attribution')),
      findsNothing,
      reason: '滚到底也不该出现（整项已删，不是被折叠）',
    );
  });

  testWidgets('导入扩展食物目录：只在失败/分片缺失时渲染（T8 · D10），状态写副标题', (tester) async {
    useTallViewport(tester);
    // docs/28 §5.6（N12）+ docs/32 §3 D10：独立的「食物目录」分组删掉，导入入口
    // 收进食材库组；T8 起**正常态零入口**（首启已自动导入，常驻一行「可选导入」
    // 等于请用户重复做一遍），只有失败/分片缺失时才作为**恢复入口**出现。
    final tempDir = Directory.systemTemp.createTempSync('settings-catalog-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final bootstrap = CatalogBootstrap(
      source: CatalogShardSource(
        supportDir: tempDir.path,
        assetLoader: (key) async => null,
      ),
      importer: CatalogShardImporter(database: database),
    );

    await tester.pumpWidget(_app(_FakeAiProviderSettingsStore(), bootstrap));
    await tester.pumpAndSettle();

    expect(find.text('食物目录'), findsNothing);
    // ① 还在检查（lastResult == null）＝还没结论：**不渲染入口**（正常态零入口，
    //    检查中的每一帧都常驻一行「可选导入」同样是在请用户重复动作）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-group-catalog')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-catalog-import')), findsNothing);
    expect(find.textContaining('本次构建没有随包目录数据'), findsNothing);

    // ② 没有随包分片且没失败（正常构建的常态）＝成功态，同样零入口。
    bootstrap.lastResult.value = const CatalogBootstrapResult.noCatalog();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-catalog-import')), findsNothing);
    expect(find.text('没有可导入的分片。'), findsNothing);

    // ③ 分片缺失（只导了一部分）＝恢复入口出现，两个数字都如实显示。
    bootstrap.lastResult.value = const CatalogBootstrapResult(
      catalogVersion: '2026.09',
      importedRows: 20000,
      importedShards: 1,
      totalShards: 5,
      missingShards: ['foods-core-001.sqlite', 'foods-core-002.sqlite'],
      skippedEntirely: false,
      failure: null,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-catalog-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('导入扩展食物目录（可选）'), findsOneWidget);
    expect(find.textContaining('上次导入 20,000 条（1/5 个分片）'), findsOneWidget);
    expect(
      find.textContaining('未导入的分片：foods-core-001.sqlite、foods-core-002.sqlite'),
      findsOneWidget,
    );

    // ④ 点这一行 = 重新扫描本地分片；这里随包没有目录，结果回到「没有可导入
    //    的分片」（无失败）→ 恢复入口自己收掉，旧数字不留在屏上。
    await tester.tap(find.byKey(const Key('settings-catalog-import')));
    await tester.pumpAndSettle();
    expect(find.textContaining('上次导入 20,000 条'), findsNothing);
    expect(
      find.byKey(const Key('settings-catalog-import')),
      findsNothing,
      reason: '恢复正常后入口必须收掉（正常态零入口）',
    );

    // ⑤ 失败态：入口出现，且副标题说失败原因，不说成「没有可导入的分片」。
    // O-1（2026-09-19 裁定）：文案里不再插异常类型名（如 StateError）。
    bootstrap.lastResult.value = const CatalogBootstrapResult.noCatalog(
      failure: '随包目录准备失败，本次跳过；可在「我的 → 食材库 → 导入扩展食物目录」重新扫描。',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-catalog-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final prepareFailed = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('settings-catalog-import')),
            matching: find.textContaining('上次导入未完成：'),
          ),
        )
        .data!;
    expect(prepareFailed, contains('随包目录准备失败'));
    expect(prepareFailed, contains('我的 → 食材库'));
    expect(prepareFailed, isNot(contains('StateError')));

    // 空间不足时副标题说的是「剩余空间不足」，不是类型名——2026-09-19 设备走查
    // （BUG-17/BUG-18）里用户实际读到的是「意外错误（DriftRemoteException）」
    // 和「准备失败（FileSystemException）」，两条都不可行动。这里把上屏文案
    // 钉在组件层，与 bootstrap/importer 的回归测试形成端到端闭环。
    bootstrap.lastResult.value = const CatalogBootstrapResult(
      catalogVersion: '2026.09',
      importedRows: 0,
      importedShards: 0,
      totalShards: 5,
      missingShards: [],
      skippedEntirely: false,
      failure: '设备剩余空间不足，目录导入已暂停。清理空间后可在「我的 → 食材库 → 导入扩展食物目录」重试。',
    );
    await tester.pumpAndSettle();
    final insufficient = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('settings-catalog-import')),
            matching: find.textContaining('上次导入未完成：'),
          ),
        )
        .data!;
    expect(insufficient, contains('设备剩余空间不足'));
    expect(insufficient, isNot(contains('Exception')));
    expect(insufficient, isNot(contains('DriftRemoteException')));

    // ⑥ 「已在库中，无需重复导入」= 成功态，入口收掉。
    bootstrap.lastResult.value = const CatalogBootstrapResult(
      catalogVersion: '2026.09',
      importedRows: 0,
      importedShards: 0,
      totalShards: 5,
      missingShards: [],
      skippedEntirely: true,
      failure: null,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-catalog-import')), findsNothing);
    expect(find.textContaining('已在库中，无需重复导入'), findsNothing);
  });

  /// 把「我的」页滚到底：ListView 是懒构建的，屏幕外的分组根本没被
  /// build 出来，直接 find 会报「0 widgets」——不是没实现，是没渲染。
  Future<void> scrollToKey(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// 关于分组（docs/21 §5.6 📱）：版本号按注入值如实显示。
  /// 「帮助文档 / 反馈」两个入口必须真能打开弹层——只渲染一个点了没反应的
  /// 按钮，就是这条规范最常见的假完成形态。
  ///
  /// 【2026-10-25 断言语义变更（17c，强度不降）】原断言是「未注入时显示
  /// 『版本未知』」。用户实测看到那句「版本未知」，追根因是我构建 APK 时漏传
  /// `--dart-define=APP_VERSION=`。改法不是把话写好看，而是让「没有版本」这个
  /// 状态**不再存在**：版本回落到随包常量（`lib/app/app_version.dart`，它与
  /// pubspec 的 `+构建号` 由 `test/release/app_version_test.dart` 钉住）。
  /// 于是原来那条「不得编造版本字符串」的断言被**替换**为更强的两条：不许出现
  /// 「版本未知」+ 必须有一个真实 v 号上屏。
  testWidgets('关于分组：版本号永远有值（未注入时用随包版本），帮助与反馈可打开', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: _FakeAiProviderSettingsStore()),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-version-row'));

    expect(find.text('关于'), findsOneWidget);
    expect(
      find.text('版本未知'),
      findsNothing,
      reason: '17c：这句是「构建漏传 define」的产物，不该再出现在界面上',
    );
    expect(
      find.text('v$kAppVersionFallback'),
      findsOneWidget,
      reason: '未注入时回落到随包版本号——真实构建号，不是编的',
    );

    await tester.ensureVisible(find.byKey(const Key('about-help')));
    await tester.tap(find.byKey(const Key('about-help')));
    await tester.pumpAndSettle();
    // 弹层里出现真实问答内容，而不是空壳。
    expect(find.text('数据存在哪里？'), findsOneWidget);
    // 2026-10-08：帮助文档不许出现与行为矛盾的隐私断言——AI 功能确实会把
    // 照片/餐记录/体重发给你自己配置的供应商，「不会上传到任何服务器」
    // 是错的（BUG-D）。
    expect(find.textContaining('不会把照片、体重或饮食记录上传到任何服务器'), findsNothing);
    expect(find.textContaining('不主动使用 AI 功能就不会有内容离开这台设备'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('about-feedback')));
    await tester.tap(find.byKey(const Key('about-feedback')));
    await tester.pumpAndSettle();
    // 同样不许说「不联网 / 数据不会流出设备」：配置了供应商之后会真的发请求。
    expect(find.text('没有内置上报通道'), findsOneWidget);
    expect(find.text('当前版本不联网'), findsNothing);
  });

  // 需求 17b（docs/60 §12.2）：检查更新**真做事**（原来是假按钮，只弹一句
  // 「不会联网检查更新」）。这里用注入的服务 + 打桩 HTTP 驱动整条链：
  // 查最新版 → 有新版就弹一层说明 + 「下载并安装」。
  testWidgets('17b：有新版时检查更新弹「发现新版本」并给下载按钮', (tester) async {
    useTallViewport(tester);
    const channel = MethodChannel('localfit/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'deviceInfo') {
            return <Object?, Object?>{
              'model': 'Test Device',
              'androidVersion': '15',
              'sdkInt': 35,
              'versionCode': 6073,
              'abi': 'x86_64',
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'tag_name': 'v6074',
              'assets': [
                {
                  'name': 'LocalFitAI-vc6074-x86_64-emulator.apk',
                  'browser_download_url': 'https://example.com/a.apk',
                  'size': 41000000,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          appUpdateService: AppUpdateService(dio: dio),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-check-update')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-check-update')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update-available-sheet')), findsOneWidget);
    expect(find.textContaining('v6074'), findsWidgets);
    expect(
      find.byKey(const Key('update-download-install')),
      findsOneWidget,
      reason: '要有真的会下载的按钮（不是一句说明就完）',
    );
  });

  testWidgets('快速连点检查更新只发一次请求、只开一层更新确认', (tester) async {
    useTallViewport(tester);
    final download = UpdateDownloadFixture();
    addTearDown(download.dispose);
    final waiting = <(RequestOptions, RequestInterceptorHandler)>[];
    download.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => waiting.add((options, handler)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          appUpdateService: download.service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final check = find.byKey(const Key('settings-check-update'));
    await tester.scrollUntilVisible(
      check,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(check);
    await tester.tap(check);
    await tester.pump();
    await pumpDownloadUntil(tester, () => waiting.isNotEmpty);
    final requestCount = waiting.length;
    for (final (options, handler) in waiting) {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'tag_name': 'v4074',
            'assets': [
              {
                'name': UpdateDownloadFixture.asset.name,
                'browser_download_url': UpdateDownloadFixture.asset.downloadUrl,
                'size': 4 * 1024 * 1024,
              },
            ],
          },
        ),
      );
    }
    await tester.pumpAndSettle();
    expect(requestCount, 1, reason: '检查期间连点不能叠下载流程、争写同一个 APK');
    expect(
      find.byKey(const Key('update-available-sheet'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-available-sheet')), findsNothing);
  });

  for (final outcome in ['cancelled', 'started', 'needPermission', 'failed']) {
    testWidgets('检查更新完整入口：进度可见并如实呈现 $outcome', (tester) async {
      useTallViewport(tester);
      final download = UpdateDownloadFixture()..installOutcome = outcome;
      addTearDown(download.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      });
      download.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.toString() != AppUpdateService.releasesLatestUrl) {
              handler.next(options);
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'tag_name': 'v4074',
                  'assets': [
                    {
                      'name': UpdateDownloadFixture.asset.name,
                      'browser_download_url':
                          UpdateDownloadFixture.asset.downloadUrl,
                      'size': 4 * 1024 * 1024,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            settingsStore: _FakeAiProviderSettingsStore(),
            appUpdateService: download.service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-check-update')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('settings-check-update')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('update-download-install')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      download.sendBytes(1024 * 1024);
      await pumpDownloadUntil(
        tester,
        () => find.text('25%').evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('update-download-progress')), findsOneWidget);
      expect(find.text('已下载 1.0 MB / 共 4.0 MB'), findsOneWidget);

      if (outcome == 'cancelled') {
        await tester.tap(find.byKey(const Key('update-download-cancel')));
        await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
        expect(download.installedPaths, isEmpty);
      } else {
        download.sendBytes(3 * 1024 * 1024);
        download.finish();
        await pumpDownloadUntil(
          tester,
          () => download.installedPaths.isNotEmpty,
        );
      }
      await pumpDownloadUntil(
        tester,
        () => find.byKey(const Key('update-download-sheet')).evaluate().isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final message = switch (outcome) {
        'cancelled' => '已取消下载',
        'started' => '下载完成，已交给系统安装',
        'needPermission' => '允许本应用安装',
        _ => '系统没能打开安装界面',
      };
      expect(find.textContaining(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 需求 17d（docs/60 §12.3）：帮助文档改成**随包 Markdown**（离线可读、
  // 复用既有 `LfMarkdown` 渲染器）。
  testWidgets('17d：帮助文档来自随包 Markdown（不是硬编码问答）', (tester) async {
    useTallViewport(tester);
    // 注入正文加载器：`rootBundle` 是 CachingAssetBundle（跨用例互相污染），
    // 本仓既有做法是注入闭包（见 `bundled_user_food_importer_test.dart`）。
    // 真实资产的内容由下面那条 `读完随包资产` 的纯 Dart 用例保证。
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          helpContentLoader: () async => _fakeHelpMarkdown,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-version-row'));
    await tester.ensureVisible(find.byKey(const Key('about-help')));
    await tester.tap(find.byKey(const Key('about-help')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('help-markdown')),
      findsOneWidget,
      reason: '帮助正文由 Markdown 渲染器渲染（复用既有 LfMarkdown）',
    );
    // 内容确实上屏了（几节标题都在）。
    for (final heading in const [
      '数据存在哪里？',
      'AI 会直接改我的数据吗？',
      '怎么记一餐？',
      '热量目标是怎么算出来的？',
      '想反馈问题？',
    ]) {
      expect(
        find.textContaining(heading),
        findsWidgets,
        reason: '帮助正文里应包含这一节：$heading',
      );
    }
    // 诚实口径仍在（不许为了换渲染器把与行为矛盾的隐私断言放回来）。
    expect(find.textContaining('不会把照片、体重或饮食记录上传到任何服务器'), findsNothing);
    expect(find.textContaining('不主动使用 AI 功能就不会有内容离开这台设备'), findsOneWidget);
  });

  // 需求 17e（docs/60 §12.3，用户「按你的建议来」）：反馈弹层要有**真能用的
  // 通道**——GitHub issue 直达链接 + 一键复制环境信息；同时保留「没有内置
  // 上报通道」这句事实说明（不许为了好看把实话说没了）。
  testWidgets('17e：反馈弹层有 issue 链接 + 复制环境信息，且保留事实说明', (tester) async {
    useTallViewport(tester);
    // 平台通道打桩：开链接成功、设备信息可读（不碰真机）。
    const channel = MethodChannel('localfit/platform');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'openUrl') return true;
          if (call.method == 'deviceInfo') {
            return <Object?, Object?>{
              'model': 'Test Device',
              'androidVersion': '15',
              'sdkInt': 35,
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    // 剪贴板打桩（读回复制了什么）。
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          appVersion: '4074',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-version-row'));
    await tester.ensureVisible(find.byKey(const Key('about-feedback')));
    await tester.tap(find.byKey(const Key('about-feedback')));
    await tester.pumpAndSettle();

    // 事实说明还在（用户没让删）。
    expect(find.text('没有内置上报通道'), findsOneWidget);
    // 可达渠道：链接文本与可点按钮都在。
    expect(
      find.textContaining('github.com/xiaopeng66/localfit-ai/issues/new'),
      findsWidgets,
      reason: '要给可核对的链接，不是藏在「点我」后面',
    );
    await tester.tap(find.byKey(const Key('feedback-open-issue')));
    await tester.pumpAndSettle();
    expect(calls, contains('openUrl'), reason: '点链接必须真的调平台开浏览器（零新依赖，自建通道）');

    // 复制环境信息：版本 / 机型 / Android / 页面四件。
    await tester.tap(find.byKey(const Key('feedback-copy-env')));
    await tester.pumpAndSettle();
    expect(clipboard, hasLength(1));
    final text = (clipboard.single.arguments as Map)['text'] as String;
    expect(text, contains('v4074'));
    expect(text, contains('Test Device'));
    expect(text, contains('Android 15'));
    expect(text, contains('反馈'));
  });

  testWidgets('17e：打不开浏览器时如实说明并把链接复制好（点了必须有反应）', (tester) async {
    useTallViewport(tester);
    const channel = MethodChannel('localfit/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // 平台说「开不了」。
          if (call.method == 'openUrl') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: _FakeAiProviderSettingsStore()),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-version-row'));
    await tester.ensureVisible(find.byKey(const Key('about-feedback')));
    await tester.tap(find.byKey(const Key('about-feedback')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback-open-issue')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('链接已复制'),
      findsOneWidget,
      reason: '开不了浏览器时要如实说明并给退路（不许点了没反应）',
    );
    expect(clipboard, hasLength(1));
    expect(
      (clipboard.single.arguments as Map)['text'],
      contains('github.com/xiaopeng66/localfit-ai/issues/new'),
    );
  });

  testWidgets('关于弹层：本地运行声明不夹英文词、不越界承诺', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          appVersion: '4074',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-version-row'));
    await tester.tap(find.byKey(const Key('settings-version-row')));
    await tester.pumpAndSettle();

    // 2026-11-02：长隐私说明收进帮助文档，弹层只留一句事实标签；
    // 仍然不许夹英文词（原 BUG-E）。
    expect(find.text('数据仅保存在本机；AI 只在你主动调用时联网。'), findsOneWidget);
    expect(find.textContaining('you'), findsNothing);
  });

  /// 注入值是**构建脚本算出的 versionCode**（17c / 17b 口径：在线更新比 versionCode，
  /// 不比语义版本）。所以这条断言用 4074 这种真实形状，而不是 `0.1.0+1`。
  testWidgets('关于分组：注入版本号时显示注入值（原样透传，不改写）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          appVersion: '4074',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-version-row'));
    expect(find.text('v4074'), findsOneWidget);
    expect(find.text('LocalFit AI v4074'), findsOneWidget);
    expect(find.text('版本未知'), findsNothing);
  });

  testWidgets('菜单来源管理：仅在接线时出现，点击回调真的被调用', (tester) async {
    useTallViewport(tester);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          onOpenMenuSources: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToKey(tester, const Key('settings-menu-sources'));
    // scrollUntilVisible 可能刚好把分组标题顶出屏幕，往回带一点。
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.text('维护地点 / 窗口 / 菜品'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('settings-menu-sources')));
    await tester.tap(find.byKey(const Key('settings-menu-sources')));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('菜单来源管理：未接线时不渲染该入口', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: _FakeAiProviderSettingsStore()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('维护地点 / 窗口 / 菜品'), findsNothing);
  });

  // ───────── §5.6 规格测试（新增断言，全部配隔离变异红证） ─────────

  testWidgets('健康数据两格按真实派生：BMI / BMR(kcal/天)（水分卡已下线）', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 9, 12, 10);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'hm-profile',
            birthYear: const Value(1995),
            biologicalSex: const Value('female'),
            heightCm: const Value(165.0),
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.measurements)
        .insert(
          MeasurementsCompanion.insert(
            id: 'hm-weight',
            profileId: 'hm-profile',
            localDate: '2026-09-12',
            weightKg: 62,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'hm-goal',
            profileId: 'hm-profile',
            type: 'loseFat',
            calorieMinKcal: 1400,
            calorieMaxKcal: 1600,
            effectiveFrom: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'hm-target',
            goalId: 'hm-goal',
            effectiveDate: '2026-09-12',
            calorieMinKcal: 1400,
            calorieMaxKcal: 1600,
            proteinMinGrams: 60,
            proteinMaxGrams: 120,
            carbsMinGrams: 150,
            carbsMaxGrams: 220,
            fatMinGrams: 40,
            fatMaxGrams: 60,
            waterTargetMl: const Value(2000),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // BMI = 62 / 1.65² = 22.8；BMR（Mifflin-St Jeor）= 1,335 kcal/天
    // （§6.2 裁决 8：必须带单位）。2026-10-16 用户要求删掉水分环卡，故这里
    // 不再断言 2.0 L —— 饮水的达成本来由今日页饮水卡表达。
    expect(find.text('22.8'), findsOneWidget);
    expect(find.text('1,335'), findsOneWidget);
    expect(find.text('kcal/天'), findsOneWidget);
    expect(find.text('2.0'), findsNothing);
    expect(
      find.byKey(const Key('settings-health-water')),
      findsNothing,
      reason: '水分摄入目标卡已按用户要求下线',
    );
  });

  testWidgets('健康数据空库：两格显示「—」，不搬设计稿演示值（§6.1）', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 无档案/无测量 ⇒ BMI 与 BMR 都无从派生。
    // 两格都必须走诚实空态，而不是 22.8 / 1,335 这类设计稿演示数字。
    final scoped = find.descendant(
      of: find.byKey(const Key('settings-health-metrics')),
      matching: find.text('—'),
    );
    expect(scoped, findsNWidgets(2));
    expect(find.text('22.8'), findsNothing);
    expect(find.textContaining('kcal/天'), findsNothing);
    expect(find.text('2.0'), findsNothing);
  });

  testWidgets('成就四格：未解锁给锁图标，解锁行如实点亮', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 9, 12, 10);
    await database
        .into(database.achievements)
        .insert(
          AchievementsCompanion.insert(
            id: 'a-healthy-diet',
            key: 'healthy-diet',
            unlockedAt: Value(now),
            progress: const Value(1.0),
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 1; i <= 4; i++) {
      expect(find.byKey(Key('settings-achievement-$i')), findsOneWidget);
    }
    // 4 格中 3 格未解锁（锁图标）；已解锁那格不再给锁。
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
  });

  /// docs/21 §5.6 逐条点名了「我的」页的锚点 Key（分组标题、API Key 行、
  /// 成就四格、食材库计数行）。规范里的 Key 是**可测试性契约**：只写进文档
  /// 而页面上没有，视觉断言就无处落地。这里整页扫一遍，把缺失项一次性列全
  /// （逐个 `expect` 只会报到第一个就停）。
  testWidgets('docs/21 §5.6 Key 覆盖：分组标题与关键行都真实存在', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_app(_FakeAiProviderSettingsStore()));
    await tester.pumpAndSettle();

    // 整页 ListView 懒构建：滚动到位之前，下半屏的 key 根本没被 build。
    final scrollable = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;
    Future<bool> reveal(String key) async {
      for (var i = 0; i < 14; i++) {
        if (find.byKey(Key(key)).evaluate().isNotEmpty) return true;
        await tester.drag(scrollable, const Offset(0, -320));
        await tester.pump();
      }
      return find.byKey(Key(key)).evaluate().isNotEmpty;
    }

    const docKeys = <String>[
      'settings-achievements', // 成就四格
      'settings-group-ai', // AI 配置分组
      'settings-ai-model-row', // AI 配置入口行（docs/29 §P4：Key 收进弹层）
      'settings-group-catalog', // 食材库分组
      'settings-food-db-row', // 食材数据库计数行
      'settings-group-about', // 关于分组
    ];
    final missing = <String>[];
    for (final key in docKeys) {
      if (!await reveal(key)) missing.add(key);
    }
    expect(
      missing,
      isEmpty,
      reason: '我的页缺少 docs/21 §5.6 的 Key：${missing.join('、')}',
    );

    // 不止「控件在」：分组标题与计数行要显示的是文档里那份文案。
    expect(find.text('AI 配置'), findsOneWidget);
    expect(find.text('食材库'), findsOneWidget);
    expect(find.text('食材数据库'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('食材数据库计数带千位分隔符，并说清其中自建多少（§5.6）', (tester) async {
    useTallViewport(tester);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 9, 12, 10);
    await database.batch(
      (batch) => batch.insertAll(database.foods, [
        for (var i = 0; i < 1234; i++)
          FoodsCompanion.insert(
            id: 'seed-fc-$i',
            name: '食物$i',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 2,
            fatPer100g: 3,
            source: 'seed-v4',
            createdAt: now,
            updatedAt: now,
          ),
        // 一条自建：两个数字都要是真的算出来的（不是写死 49,464 / 0）。
        FoodsCompanion.insert(
          id: 'user-1',
          name: '我的鸡肉卷',
          kcalPer100g: 180,
          proteinPer100g: 15,
          carbsPer100g: 20,
          fatPer100g: 5,
          source: 'user',
          isUserCreated: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;
    for (var i = 0; i < 16; i++) {
      if (find.byKey(const Key('settings-food-db-row')).evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(scrollable, const Offset(0, -320));
      await tester.pump();
    }
    expect(find.text('1,235 条（自建 1 条）'), findsOneWidget);
    expect(find.text('1235 条（自建 1 条）'), findsNothing);
    expect(find.textContaining('49,464'), findsNothing);
  });

  testWidgets('自动本地备份开关真的写入本地设置（裁决 ⑦）', (tester) async {
    useTallViewport(tester);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final settingsRepo = AppSettingsRepository(database: database);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(appSettingsRepository: settingsRepo)),
    );
    await tester.pumpAndSettle();
    // 开关在数据管理分组下半屏：懒列表默认没构建它，先拖进视口。
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-auto-backup-toggle')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      await settingsRepo.getBool(AppSettingsRepository.autoBackupEnabledKey),
      isFalse,
    );
    await tester.tap(find.byKey(const Key('settings-auto-backup-toggle')));
    await tester.pumpAndSettle();
    expect(
      await settingsRepo.getBool(AppSettingsRepository.autoBackupEnabledKey),
      isTrue,
    );
    // 再关回去：开关是真实的偏好存取，不是摆设。
    await tester.tap(find.byKey(const Key('settings-auto-backup-toggle')));
    await tester.pumpAndSettle();
    expect(
      await settingsRepo.getBool(AppSettingsRepository.autoBackupEnabledKey),
      isFalse,
    );
  });

  testWidgets('局域网更新地址可保存与清除（2114）', (tester) async {
    useTallViewport(tester);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final settingsRepo = AppSettingsRepository(database: database);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(appSettingsRepository: settingsRepo)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-lan-update')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-lan-update')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lan-update-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('lan-update-url')),
      'http://10.26.8.28:8080/',
    );
    await tester.tap(find.byKey(const Key('lan-update-save')));
    await tester.pumpAndSettle();
    expect(
      await settingsRepo.getString(AppSettingsRepository.lanUpdateBaseUrlKey),
      'http://10.26.8.28:8080/',
    );

    await tester.tap(find.byKey(const Key('settings-lan-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lan-update-clear')));
    await tester.pumpAndSettle();
    expect(
      await settingsRepo.getString(AppSettingsRepository.lanUpdateBaseUrlKey),
      isNull,
    );
  });

  /// 【2026-10-25 断言语义反转（需求 17b，强度不降）】原断言是「点检查更新
  /// 只说一句『本应用完全本地运行，**不会联网检查更新**』」——那是**当时的
  /// 实情**（那条路确实没接），但用户要的是「点击检查更新并安装」。现在真去
  /// 查 GitHub Releases，所以那句「不会联网检查更新」**成了假话**，必须删掉。
  ///
  /// 判据改写为：查不动时**如实说连不上**（而不是继续声称「不联网」）。
  testWidgets('检查更新：真的去查；查不动时如实说，不再声称「不联网」', (tester) async {
    const channel = MethodChannel('localfit/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'deviceInfo') {
            return <Object?, Object?>{
              'model': 'Test Device',
              'androidVersion': '15',
              'sdkInt': 35,
              'versionCode': 6076,
              'abi': 'x86_64',
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    // 注入一个「连不上」的更新服务（不在 widget 测试里发真网络请求）。
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'no network in test',
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          appUpdateService: AppUpdateService(dio: dio),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-check-update')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-check-update')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('连不上更新服务器'),
      findsOneWidget,
      reason: '查不动就如实说连不上（不许继续声称「不会联网检查更新」）',
    );
    expect(
      find.textContaining('不会联网检查更新'),
      findsNothing,
      reason: '那句话现在是假的：这条路真的会联网',
    );
  });

  testWidgets('320dp 窄屏：我的页整页不溢出（几何探针）', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_FakeAiProviderSettingsStore()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.3× 与 2.0× 字号：身份卡与健康数据不溢出（几何探针）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in const <double>[1.3, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SettingsPage(settingsStore: _FakeAiProviderSettingsStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale× 字号下溢出');
    }
  });

  testWidgets('AI 记忆入口：接线才渲染，点按真的触发回调', (tester) async {
    useTallViewport(tester);
    var opened = 0;

    await tester.pumpWidget(
      _app(_FakeAiProviderSettingsStore(), null, () => opened++),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-ai-memory-row')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-ai-memory-row')));
    await tester.pumpAndSettle();
    expect(opened, 1);

    // 未接线（回调为 null）时不渲染入口。
    await tester.pumpWidget(_app(_FakeAiProviderSettingsStore()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-ai-memory-row')), findsNothing);
  });

  testWidgets('搜索调试入口：接线才渲染，点按真的触发回调', (tester) async {
    useTallViewport(tester);
    var opened = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: _FakeAiProviderSettingsStore(),
          onOpenRetrievalDebug: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-retrieval-debug-row')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('settings-retrieval-debug-row')));
    await tester.pumpAndSettle();
    expect(opened, 1);

    // 未接线时不渲染入口。
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: _FakeAiProviderSettingsStore()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-retrieval-debug-row')), findsNothing);
  });
}

Widget _app(
  AiProviderSettingsStore store, [
  CatalogBootstrap? bootstrap,
  VoidCallback? onOpenAiMemory,
]) => MaterialApp(
  home: SettingsPage(
    settingsStore: store,
    catalogBootstrap: bootstrap,
    onOpenAiMemory: onOpenAiMemory,
  ),
);

/// 帮助正文的测试替身（与随包资产的**结构**一致：几个二级标题 + 段落）。
///
/// 内容真实性由 `17d（资产）` 那两条纯 Dart 用例保证——这里只钉「渲染器接上了」。
const String _fakeHelpMarkdown = '''
## 数据存在哪里？

全部条目存在这台设备的加密数据库里。不主动使用 AI 功能就不会有内容离开这台设备。

## AI 会直接改我的数据吗？

不会。AI 只生成草稿，确认过才写入本地事实。

## 怎么记一餐？

在「饮食」页点右下加号，先选按食材或按菜品。

## 热量目标是怎么算出来的？

Mifflin–St Jeor 公式算基础代谢，再按目标调整，给出区间。

## 想反馈问题？

「我的 → 关于 → 反馈」里有仓库链接与复制环境信息。
''';

final class _FakeAiProviderSettingsStore implements AiProviderSettingsStore {
  _FakeAiProviderSettingsStore({AiProviderSettings? settings})
    : _settings =
          settings ??
          const AiProviderSettings(configuration: null, hasApiKey: false);

  AiProviderSettings _settings;
  final saved = <AiProviderSettingsInput>[];
  int clearCalls = 0;

  @override
  Future<void> clearApiKey() async {
    clearCalls++;
    _settings = AiProviderSettings(
      configuration: _settings.configuration,
      hasApiKey: false,
    );
  }

  @override
  Future<AiProviderSettings> load() async => _settings;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      _settings.configuration;

  @override
  Future<void> save(AiProviderSettingsInput input) async {
    // 与真实 store（local_ai_provider_settings_store.dart）同口径：首次保存时
    // 既没有已存 Key、本次也没带 Key，必须拒绝。旧的假 store 从不抛错，
    // 于是「弹层保存失败零反馈」的真实缺陷在 widget 测试里全绿——这条守卫
    // 本身就是回归防线，删掉它等于把缺陷放回盲区。
    final hasNewApiKey = input.apiKey?.trim().isNotEmpty ?? false;
    if (!hasNewApiKey && !_settings.hasApiKey) {
      throw const ValidationFailure('首次保存时必须填写 API Key。');
    }
    saved.add(input);
    _settings = AiProviderSettings(
      configuration: AiProviderConfiguration(
        baseUrl: input.baseUrl.trim(),
        model: input.model.trim(),
        protocol: input.protocol,
      ),
      hasApiKey: _settings.hasApiKey || hasNewApiKey,
    );
  }
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'r5-${_value++}';
}
