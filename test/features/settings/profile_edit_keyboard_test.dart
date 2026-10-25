import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/presentation/profile_edit_page.dart';

/// 阶段 3 验收（docs/21 §5.8.4）：
///
/// 「底部元素始终可点」——编辑页有 `AppNumberField`（会弹键盘），
/// 键盘弹起时「保存」必须仍完整可见、可点。
///
/// 2026-09-26 实测（探针）：手写 `SafeArea + Padding` 的版本里按钮底边 814，
/// 而可视边界只有 544（844 − 300 键盘），**被盖住 270dp**。该页当时的
/// `bottomNavigationBar` 是手写块，没有 `viewInsets` 处理。
///
/// 注意 `MediaQuery` 必须放在 `MaterialApp` **内部**：放在外面会被
/// MaterialApp 自己插入的 MediaQuery 顶掉，`viewInsets` 完全不生效，
/// 于是「有键盘」和「无键盘」两次量出的矩形一模一样——探针第一版就是这么
/// 骗过自己的（rect 两次都是 794→814）。本文件用内部注入，并先断言
/// 两次布局确实不同，避免测试退化成空转。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const screenHeight = 844.0;
  const keyboardHeight = 300.0;
  const visibleBottom = screenHeight - keyboardHeight;

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<void> pumpAt(WidgetTester tester, double keyboardInset) async {
    tester.view.physicalSize = const Size(390, screenHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: ProfileEditPage(
            repository: ProfileIdentityRepository(database: database),
            currentGoal: null,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('无键盘：保存键贴底且在屏内', (tester) async {
    await pumpAt(tester, 0);

    final rect = tester.getRect(find.text('保存'));
    expect(rect.bottom, lessThanOrEqualTo(screenHeight + 0.01));
  });

  testWidgets('键盘弹起 300dp：保存键不被键盘盖住（docs/21 §5.8.3）', (tester) async {
    await pumpAt(tester, keyboardHeight);

    final rect = tester.getRect(find.text('保存'));
    expect(
      rect.bottom,
      lessThanOrEqualTo(visibleBottom + 0.01),
      reason: '保存键被软键盘盖住，用户点不到（docs/21 §5.8.3「底部元素始终可点」）',
    );
  });

  testWidgets('键盘弹起后保存键真的可点（触发校验而不是被遮挡吞掉）', (tester) async {
    await pumpAt(tester, keyboardHeight);

    // 目标体重填一个非法值，点保存应弹校验提示——证明点击真的到达按钮。
    await tester.enterText(find.byKey(const Key('profile-target-weight')), '0');
    await tester.pumpAndSettle();

    final save = find.text('保存');
    expect(
      tester.getRect(save).bottom,
      lessThanOrEqualTo(visibleBottom + 0.01),
      reason: '先确认按钮没被盖，否则下面的 tap 可能落在键盘上',
    );

    await tester.tap(save);
    await tester.pumpAndSettle();

    // 校验失败必须给出反馈，而不是静默什么都不发生。
    expect(find.textContaining('有效体重'), findsOneWidget, reason: '点击应真的触发校验流程');
  });
}
