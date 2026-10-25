import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_form_sheet.dart';
import 'package:localfit_ai/features/hydration/presentation/water_entry_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';
import 'package:localfit_ai/features/progress/presentation/weight_entry_dialog.dart';

/// **N7：保存失败不关窗**（docs/28 §3.5/§3.6）。
///
/// 逐表单参数化：落库抛异常 / 业务层返回错误文案时，弹层仍在屏上、错误画在
/// 弹层**内**、用户已经填的内容一个字都不丢、按钮还能再点（不是被永久禁用）。
///
/// 针对的是用户点名的旧行为：先 `pop` 弹层、再写库、失败只在页面上闪一条
/// snackbar。弹层挂在根导航器上盖住整页，那条提示物理上看不见，而用户的输入
/// 已经随着弹层一起没了。
///
/// 各弹层把异常翻成哪句人话不完全相同（食物/食堂/通用壳走壳的兜底文案，
/// 体重与饮水在各自弹层里翻），所以期望文案逐个写清，不用一条通用断言糊过去。
void main() {
  final cases = <String, _SheetCase>{
    'AppSheet.showSubmitForm（通用提交型弹层）': _SheetCase(
      open: (tester, submit) async {
        await tester.pumpWidget(
          _host(
            (context) => AppSheet.showSubmitForm<void>(
              context,
              title: '通用表单',
              submitKey: const Key('probe-submit'),
              errorKey: const Key('probe-error'),
              body: (_, _) => TextField(
                key: const Key('probe-input'),
                controller: _probeController,
                decoration: const InputDecoration(hintText: '写点什么'),
              ),
              onSubmit: submit,
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      },
      fill: (tester) async {
        _probeController.text = '通用输入';
        await tester.pump();
      },
      submitKey: const Key('probe-submit'),
      throwMessage: '保存失败，请重试。',
      stillVisible: (tester) => expect(find.text('通用表单'), findsOneWidget),
      inputText: (tester) => _probeController.text,
      expectedInput: '通用输入',
    ),
    'CanteenFormSheet（添加窗口）': _SheetCase(
      open: (tester, submit) async {
        await tester.pumpWidget(
          _host(
            (context) => CanteenFormSheet.show(
              context,
              title: '添加窗口',
              fields: const [
                CanteenField(
                  key: 'canteen-window-name',
                  label: '窗口名称',
                  hint: '例：一楼快餐',
                ),
              ],
              onSubmit: (_) => submit(),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      },
      fill: (tester) => tester.enterText(
        find.byKey(const Key('canteen-window-name')),
        '一楼快餐',
      ),
      submitKey: const Key('canteen-form-submit'),
      throwMessage: '保存失败，请重试。',
      stillVisible: (tester) => expect(find.text('添加窗口'), findsOneWidget),
      inputText: (tester) => tester
          .widget<TextFormField>(find.byKey(const Key('canteen-window-name')))
          .controller!
          .text,
      expectedInput: '一楼快餐',
    ),
    'NewFoodDialog（新建食物）': _SheetCase(
      open: (tester, submit) async {
        await tester.pumpWidget(
          _host(
            (context) => NewFoodDialog.show(context, onSubmit: (_) => submit()),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      },
      fill: (tester) async {
        await tester.enterText(find.byKey(const Key('new-food-name')), '番茄');
        await tester.enterText(find.byKey(const Key('new-food-brand')), '示范牌');
        await tester.enterText(
          find.byKey(const Key('new-food-每 100g 热量')),
          '18',
        );
        await tester.enterText(
          find.byKey(const Key('new-food-每 100g 蛋白质')),
          '0.9',
        );
        await tester.enterText(
          find.byKey(const Key('new-food-每 100g 碳水')),
          '3.9',
        );
        await tester.enterText(
          find.byKey(const Key('new-food-每 100g 脂肪')),
          '0.2',
        );
      },
      submitKey: const Key('new-food-save'),
      throwMessage: '保存失败，请重试。',
      stillVisible: (tester) => expect(find.text('新建食物'), findsOneWidget),
      inputText: (tester) => tester
          .widget<TextFormField>(find.byKey(const Key('new-food-brand')))
          .controller!
          .text,
      expectedInput: '示范牌',
    ),
    'WeightEntryDialog（记录体重）': _SheetCase(
      open: (tester, submit) async {
        await tester.pumpWidget(
          _host(
            (context) => AppSheet.showCustom<void>(
              context,
              builder: (_) => WeightEntryDialog(onSubmit: (_) => submit()),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      },
      fill: (tester) async {
        await tester.enterText(find.byKey(const Key('weight-input')), '68.5');
        await tester.enterText(find.byKey(const Key('weight-notes')), '早上空腹');
      },
      submitKey: const Key('weight-save'),
      throwMessage: '体重保存失败，请重试。',
      stillVisible: (tester) => expect(find.text('记录体重'), findsOneWidget),
      inputText: (tester) => tester
          .widget<TextFormField>(find.byKey(const Key('weight-notes')))
          .controller!
          .text,
      expectedInput: '早上空腹',
    ),
    'WaterEntryDialog（记录饮水）': _SheetCase(
      open: (tester, submit) async {
        await tester.pumpWidget(
          _host(
            (context) => AppSheet.showCustom<void>(
              context,
              builder: (_) => WaterEntryDialog(onSubmit: (_) => submit()),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      },
      fill: (tester) =>
          tester.enterText(find.byKey(const Key('water-amount-input')), '333'),
      submitKey: const Key('water-amount-submit'),
      throwMessage: '饮水记录失败，请重试。',
      stillVisible: (tester) => expect(find.text('记录饮水'), findsOneWidget),
      inputText: (tester) => tester
          .widget<TextFormField>(find.byKey(const Key('water-amount-input')))
          .controller!
          .text,
      expectedInput: '333',
    ),
  };

  cases.forEach((name, testCase) {
    group(name, () {
      testWidgets('落库抛异常：弹层仍在 + 错误在内 + 输入不丢 + 还能再提交', (tester) async {
        var attempts = 0;
        await testCase.open(tester, () async {
          attempts++;
          throw StateError('写入失败（测试注入）');
        });
        await testCase.fill(tester);
        await tester.tap(find.byKey(testCase.submitKey));
        await tester.pumpAndSettle();

        expect(attempts, 1, reason: '提交确实走到了落库这一步');
        expect(find.byType(BottomSheet), findsOneWidget, reason: '弹层不能关');
        testCase.stillVisible(tester);
        expect(
          find.text(testCase.throwMessage),
          findsOneWidget,
          reason: '异常必须被翻成弹层内的一条人话',
        );
        expect(
          testCase.inputText(tester),
          testCase.expectedInput,
          reason: '输入不丢',
        );

        // 按钮没有被永久禁用：再点一次仍会走到落库。
        await tester.tap(find.byKey(testCase.submitKey));
        await tester.pumpAndSettle();
        expect(attempts, 2, reason: '失败后按钮仍可再次提交');
        expect(find.byType(BottomSheet), findsOneWidget);
      });

      testWidgets('返回错误文案：留在弹层内显示这条文案，输入不丢', (tester) async {
        await testCase.open(tester, () async => '这个名字重复了。');
        await testCase.fill(tester);
        await tester.tap(find.byKey(testCase.submitKey));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
        testCase.stillVisible(tester);
        expect(find.text('这个名字重复了。'), findsOneWidget);
        expect(testCase.inputText(tester), testCase.expectedInput);
      });

      testWidgets('返回 null = 成功：弹层照常关闭（成功路径没被挡住）', (tester) async {
        await testCase.open(tester, () async => null);
        await testCase.fill(tester);
        await tester.tap(find.byKey(testCase.submitKey));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
      });
    });
  });
}

final _probeController = TextEditingController();

/// 打开方式 / 填表 / 断言的最小描述。
class _SheetCase {
  const _SheetCase({
    required this.open,
    required this.fill,
    required this.submitKey,
    required this.throwMessage,
    required this.stillVisible,
    required this.inputText,
    required this.expectedInput,
  });

  final Future<void> Function(
    WidgetTester tester,
    Future<String?> Function() submit,
  )
  open;
  final Future<void> Function(WidgetTester tester) fill;
  final Key submitKey;

  /// 落库抛异常时该弹层给出的兜底文案。
  final String throwMessage;
  final void Function(WidgetTester tester) stillVisible;
  final String Function(WidgetTester tester) inputText;
  final String expectedInput;
}

Widget _host(Future<void> Function(BuildContext context) open) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => open(context),
          child: const Text('打开'),
        ),
      ),
    ),
  ),
);
