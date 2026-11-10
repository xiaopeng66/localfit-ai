@Tags(['interaction-gate'])
library;

import 'package:drift/native.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart'
    as chat;
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// E-2（docs/64 阶段 3）：**12 页 320dp × 2.0× 全页扫描**——任何一处溢出即红，
/// 报出页面名 + 溢出像素；每页再断言首屏关键 Key 可见（挂载失败 ≠ 通过）。
///
/// 与 `narrow_layout_audit_test.dart` 同一套 harness（LocalFitApp 全接线 +
/// 真实建档），差别只有两条：视口 320dp、字号 2.0。docs/64 附录 B：
/// 扫描耗时，挂 `interaction-gate` 标签，本地/发布前各跑一次。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 骨架屏/脉冲是无限动画，pumpAndSettle 等不完（docs/64 附录 E）。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  late _InMemoryBackupFileStore fileStore;
  late CreateEncryptedBackup createBackup;
  late RestoreEncryptedBackup restoreBackup;
  late AiMemoryRepository aiMemoryRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    await CompleteOnboarding(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    )(
      const OnboardingInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 75,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
        targetWeightKg: 68,
      ),
    );
    const ids = UuidV7Generator();
    const clock = SystemAppClock();
    foodRepository = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    fileStore = _InMemoryBackupFileStore();
    createBackup = CreateEncryptedBackup(
      database: database,
      fileStore: fileStore,
      codec: const LfbBackupCodec(iterations: 2000, derivesInIsolate: false),
    );
    restoreBackup = RestoreEncryptedBackup(
      database: database,
      fileStore: fileStore,
      codec: const LfbBackupCodec(iterations: 2000, derivesInIsolate: false),
    );
    aiMemoryRepository = AiMemoryRepository(
      database: database,
      clock: clock,
      idGenerator: const UuidV7Generator(),
    );
  });

  tearDown(() => database.close());

  List<String> overflows = <String>[];
  void Function(FlutterErrorDetails)? originalHandler;

  void startAudit() {
    overflows = <String>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        overflows.add(message.split('\n').first);
        return;
      }
      previousHandler?.call(details);
    };
    originalHandler = previousHandler;
  }

  void endAudit(String page) {
    for (var i = 0; i < overflows.length; i++) {
      overflows[i] = '[$page] ${overflows[i]}';
    }
    final collected = overflows.toList();
    FlutterError.onError = originalHandler;
    expect(
      collected,
      isEmpty,
      reason: '$page 在 320dp × 2.0× 下溢出：\n${collected.join('\n')}',
    );
  }

  Widget app(String location) => LocalFitApp(
    initialLocation: location,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    measurementRepository: MeasurementRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    waterRepository: WaterRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    exerciseRepository: ExerciseRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutPlanRepository: WorkoutPlanRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutSessionRepository: WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    profileIdentityRepository: ProfileIdentityRepository(database: database),
    // AI 助手 / 记忆两页需要仓储才挂得出真实页面（未接线时路由是兜底文案）。
    conversationService: _NoopConversationService(),
    aiMemoryRepository: aiMemoryRepository,
    dataSelfCheck: DataSelfCheck(
      database: database,
      clock: const SystemAppClock(),
    ),
    // 备份四件全接线（数据管理组可见，「备份」页的弹层才挂得出来）；
    // fileStore 用内存实现，扫描不会碰真实文件系统。
    createEncryptedBackup: createBackup,
    restoreEncryptedBackup: restoreBackup,
    clearAllLocalData: ClearAllLocalData(database),
    exportCsvFiles: ExportCsvFiles(database: database, fileStore: fileStore),
    now: DateTime(2026, 9, 13),
  );

  void useExtremeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  }

  /// 饮食页 tab 是横向 chips；拖到可见后点击。
  Future<void> openNutritionChip(WidgetTester tester, String label) async {
    final chip = find.text(label);
    if (!tester.any(chip)) {
      fail('未找到 tab chip：$label');
    }
    final rect = tester.getRect(chip);
    if (rect.right > 320 || rect.left < 0) {
      final view = find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          )
          .first;
      await tester.dragUntilVisible(chip, view, const Offset(-60, 0));
      await settle(tester);
    }
    await tester.tap(chip);
    await settle(tester);
  }

  /// 统一页面巡检：挂载 → settle → 页内动作（含滚动）→ 断言溢出 →
  /// 断言首屏关键件 → 卸树放行（drift 流取消的 0ms 定时器要 flush）。
  Future<void> auditPage(
    WidgetTester tester,
    String page,
    String location,
    Future<void> Function(WidgetTester tester) body,
    Key sentinel,
  ) async {
    useExtremeViewport(tester);
    startAudit();
    await tester.pumpWidget(app(location));
    await settle(tester);
    await body(tester);
    endAudit(page);
    expect(find.byKey(sentinel), findsOneWidget, reason: '$page：首屏关键件');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 从当前页把纵向滚动体往下拖一段（把页底的 Key 拉进视口）。
  Future<void> scrollDown(WidgetTester tester, Key target) async {
    await tester.scrollUntilVisible(
      find.byKey(target),
      260,
      scrollable: find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.vertical,
          )
          .first,
    );
    await settle(tester);
  }

  testWidgets('E-2 · 今日（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '今日',
      AppRoutes.dashboard,
      (_) async {},
      const Key('dashboard-greeting'),
    );
  });

  testWidgets('E-2 · 记录（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '记录',
      AppRoutes.nutrition,
      (_) async {},
      const Key('nutrition-record-energy'),
    );
  });

  testWidgets('E-2 · 菜单（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '菜单',
      AppRoutes.nutrition,
      (tester) => openNutritionChip(tester, '菜单'),
      const Key('nutrition-menu-hero'),
    );
  });

  testWidgets('E-2 · 食物库（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '食物库',
      AppRoutes.nutrition,
      (tester) => openNutritionChip(tester, '食物库'),
      // 库为空（audit 不跑内置食物导入）⇒ 空态的滚动宿主是稳定首屏件。
      const Key('food-empty-scroll'),
    );
  });

  testWidgets('E-2 · 训练（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '训练',
      AppRoutes.training,
      (_) async {},
      const Key('training-segment-plan'),
    );
  });

  testWidgets('E-2 · 训练计划创建（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '训练计划创建',
      AppRoutes.workoutPlanManual,
      (_) async {},
      const Key('manual-plan-name'),
    );
  });

  testWidgets('E-2 · 动作库（320dp × 2.0×）', (tester) async {
    await auditPage(tester, '动作库', AppRoutes.training, (tester) async {
      // 动作库收在训练页右下的「上拉三角」里：展开 → 点动作库。
      await tester.tap(find.byKey(const Key('training-actions-toggle')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('training-exercise-library')));
      await settle(tester);
    }, const Key('training-exercise-add'));
  });

  testWidgets('E-2 · 我的（设置，320dp × 2.0×）', (tester) async {
    await auditPage(tester, '我的', AppRoutes.settings, (tester) async {
      // 版本行在页面底部：滚到底（把整页也扫一遍）。
      await scrollDown(tester, const Key('settings-version-row'));
    }, const Key('settings-version-row'));
  });

  testWidgets('E-2 · 资料编辑（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '资料编辑',
      AppRoutes.profileEdit,
      (_) async {},
      const Key('profile-edit-close'),
    );
  });

  testWidgets('E-2 · AI 助手（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      'AI 助手',
      AppRoutes.aiChat,
      (_) async {},
      const Key('ai-chat-title'),
    );
  });

  testWidgets('E-2 · 记忆（320dp × 2.0×）', (tester) async {
    await auditPage(
      tester,
      '记忆',
      AppRoutes.aiMemory,
      (_) async {},
      const Key('ai-memory-add'),
    );
  });

  testWidgets('E-2 · 备份弹层（320dp × 2.0×）', (tester) async {
    await auditPage(tester, '备份', AppRoutes.settings, (tester) async {
      await scrollDown(tester, const Key('settings-backup-hub'));
      await tester.tap(find.byKey(const Key('settings-backup-hub')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('cta-backup')));
      await settle(tester);
      // 哨兵必须在**弹层自己的内容**里（2026-10-27 复核修正：原来断言的是
      // 设置页的行，弹层没挂出来也会绿）。
      expect(find.text('导出加密备份'), findsOneWidget, reason: '备份弹层必须真的挂出来');
      expect(find.byKey(const Key('backup-export-password')), findsOneWidget);
    }, const Key('data-self-check-entry'));
  });
}

final class _InMemoryBackupFileStore implements BackupFileStore {
  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async => '/memory/$defaultFileName';

  @override
  Future<Uint8List?> pickRestoreFile() async => null;
}

/// 只回一句、不联网的最小对话服务（E-2 只扫版式，不扫 AI 行为）。
final class _NoopConversationService implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<chat.ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    yield '（扫描占位回复）';
  }
}
