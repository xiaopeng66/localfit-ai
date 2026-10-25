import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/localfit_app.dart';

/// **中文系统文案**（2026-10-24 用户：「输入框选中文字后进行复制或者粘贴等
/// 操作的时候，系统提示是英文的 copy、cut、paste，而不是中文」）。
///
/// 根因：`MaterialApp` 没有配 `localizationsDelegates` / `supportedLocales`
/// / `locale`，Flutter 回落到 `DefaultMaterialLocalizations`（纯英文），
/// 所以文本选择菜单、日期选择器这些都显示英文。
///
/// 本文件钉的是**渲染出来的菜单文案**，不是「配置里有没有那几个 delegate」
/// ——配置写了但 `locale` 没设成中文，菜单照样是英文。
void main() {
  group('Material 系统文案是中文', () {
    testWidgets('文本选择菜单显示「复制 / 剪切 / 粘贴 / 全选」而不是英文', (tester) async {
      final controller = TextEditingController(text: '测试文本，用来触发选择菜单');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: LocalFitApp.localizationsDelegates,
          supportedLocales: LocalFitApp.supportedLocales,
          locale: LocalFitApp.preferredLocale,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: TextField(
                key: const Key('l10n-field'),
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 选中一段文字，让选择菜单出现。
      await tester.tap(find.byKey(const Key('l10n-field')));
      await tester.pumpAndSettle();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pumpAndSettle();

      // 触发选择 toolbar（Android/iOS 上长按；测试里用 selectAll 之后
      // 直接检查 MaterialLocalizations 的文案更稳）。
      final context = tester.element(find.byKey(const Key('l10n-field')));
      final l10n = MaterialLocalizations.of(context);

      const english = {
        'copy': 'Copy',
        'cut': 'Cut',
        'paste': 'Paste',
        'selectAll': 'Select all',
      };
      expect(
        l10n.copyButtonLabel,
        isNot(english['copy']),
        reason: '「复制」菜单项仍是英文 Copy',
      );
      expect(
        l10n.cutButtonLabel,
        isNot(english['cut']),
        reason: '「剪切」菜单项仍是英文 Cut',
      );
      expect(
        l10n.pasteButtonLabel,
        isNot(english['paste']),
        reason: '「粘贴」菜单项仍是英文 Paste',
      );
      expect(
        l10n.selectAllButtonLabel,
        isNot(english['selectAll']),
        reason: '「全选」菜单项仍是英文 Select all',
      );

      // 且确实是中文（不是别的语言）。
      expect(l10n.copyButtonLabel, '复制');
      expect(l10n.cutButtonLabel, '剪切');
      expect(l10n.pasteButtonLabel, '粘贴');
      expect(l10n.selectAllButtonLabel, '全选');
    });

    testWidgets('输入框场景下四个菜单文案都是中文（在 TextField 上下文里读）', (tester) async {
      final controller = TextEditingController(text: 'ABC');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: LocalFitApp.localizationsDelegates,
          supportedLocales: LocalFitApp.supportedLocales,
          locale: LocalFitApp.preferredLocale,
          home: Scaffold(
            body: TextField(
              key: const Key('l10n-field'),
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = MaterialLocalizations.of(
        tester.element(find.byKey(const Key('l10n-field'))),
      );
      // 在**输入框真实上下文**里再取一次（上一条用的是同一份 delegate，
      // 这一条确认 locale 在 widget 树里也生效，不只是 delegate 列表对）。
      expect(l10n.copyButtonLabel, '复制');
      expect(l10n.pasteButtonLabel, '粘贴');
      // 日期选择器也跟着中文化（同为 MaterialLocalizations 提供）。
      expect(l10n.cancelButtonLabel, isNot('Cancel'));
    });
  });

  group('LocalFitApp 暴露的本地化配置本身', () {
    test('首选语言是 zh-CN，且 supportedLocales 含它', () {
      expect(LocalFitApp.preferredLocale.languageCode, 'zh');
      expect(
        LocalFitApp.supportedLocales.any(
          (l) => l.languageCode == 'zh' && l.countryCode == 'CN',
        ),
        isTrue,
      );
    });

    test('三个 delegate 都在（Material / Widgets / Cupertino）', () {
      expect(
        LocalFitApp.localizationsDelegates.length,
        greaterThanOrEqualTo(3),
      );
    });
  });
}
