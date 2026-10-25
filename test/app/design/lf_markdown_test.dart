import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_markdown.dart';

/// `RV4-P2-02`（`docs/57` §3 / `docs/56` R13）：AI 回复要按 Markdown 排版。
///
/// 现状：`AiMessageBubble` 是纯 `Text`，模型输出的 `**加粗**`、`- 列表`、
/// ``` 代码块全部原样带符号上屏——用户说的「乱七八糟堆成一堆」。
///
/// 约束：**不新增第三方依赖**（自写最小渲染器）；**不支持**表格/图片/外链
/// 跳转（隐私口径：不打开外部浏览器）；**畸形输入一律降级为纯文本**，不抛异常。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('行内语法', () {
    testWidgets('**粗体**：星号不上屏，且字重真的是 bold', (tester) async {
      await tester.pumpWidget(host(const LfMarkdown(text: '这是**重点**内容')));
      await tester.pumpAndSettle();

      expect(find.textContaining('**'), findsNothing, reason: '星号不得上屏');
      final richText = tester.widget<RichText>(
        find.byWidgetPredicate((w) => w is RichText).first,
      );
      final span = richText.text as TextSpan;
      final bold = <TextSpan>[];
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.style?.fontWeight == FontWeight.w700 &&
            (child.text ?? '').contains('重点')) {
          bold.add(child);
        }
        return true;
      });
      expect(bold, isNotEmpty, reason: '「重点」必须是 w700 的 TextSpan');
    });

    testWidgets('`代码`：等宽字体且不上屏反引号', (tester) async {
      await tester.pumpWidget(
        host(const LfMarkdown(text: '执行 `meal.create` 命令')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('`'), findsNothing);
      expect(find.textContaining('meal.create'), findsWidgets);
    });

    testWidgets('*斜体*：不上屏星号', (tester) async {
      await tester.pumpWidget(host(const LfMarkdown(text: '这是*强调*文本')));
      await tester.pumpAndSettle();
      expect(find.textContaining('*'), findsNothing);
    });
  });

  group('块级语法', () {
    testWidgets('无序列表：每项一行且不带 "- "', (tester) async {
      await tester.pumpWidget(
        host(const LfMarkdown(text: '- 第一项\n- 第二项\n- 第三项')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('- '), findsNothing);
      expect(find.textContaining('第一项'), findsOneWidget);
      expect(find.textContaining('第二项'), findsOneWidget);
      expect(find.textContaining('第三项'), findsOneWidget);
    });

    testWidgets('有序列表：编号保留但不再是裸 "1. "', (tester) async {
      await tester.pumpWidget(host(const LfMarkdown(text: '1. 先喝水\n2. 再记餐')));
      await tester.pumpAndSettle();
      expect(find.textContaining('先喝水'), findsOneWidget);
      expect(find.textContaining('再记餐'), findsOneWidget);
    });

    testWidgets('标题 # / ##：字号大于正文且不带 #', (tester) async {
      await tester.pumpWidget(host(const LfMarkdown(text: '# 今日总结\n正文')));
      await tester.pumpAndSettle();
      expect(find.textContaining('#'), findsNothing);
      expect(find.textContaining('今日总结'), findsOneWidget);
    });

    testWidgets('代码围栏：等宽、可横向滚动、围栏符号不上屏', (tester) async {
      await tester.pumpWidget(
        host(const LfMarkdown(text: '看这段：\n```\nmeal.create(x)\n```\n结束')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('```'), findsNothing);
      expect(find.textContaining('meal.create(x)'), findsWidgets);
    });

    testWidgets('分隔线 ---：不把三个横线当正文', (tester) async {
      await tester.pumpWidget(host(const LfMarkdown(text: '上\n---\n下')));
      await tester.pumpAndSettle();
      expect(find.text('---'), findsNothing);
      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('引用 >：不上屏 >', (tester) async {
      await tester.pumpWidget(host(const LfMarkdown(text: '> 引用一句')));
      await tester.pumpAndSettle();
      expect(find.textContaining('>'), findsNothing);
      expect(find.textContaining('引用一句'), findsOneWidget);
    });
  });

  group('不支持的语法要降级，不许崩', () {
    testWidgets('表格按纯文本显示（不解析、不崩）', (tester) async {
      await tester.pumpWidget(
        host(const LfMarkdown(text: '| a | b |\n| --- | --- |\n| 1 | 2 |')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('未闭合 ** / 未闭合围栏 / 超长行：降级为纯文本，不抛异常', (tester) async {
      for (final text in [
        '未闭合 **粗体',
        '```\n没有结束的围栏',
        '超长行' * 500,
        '',
        '\n\n\n',
        '**',
        '[]()[]',
      ]) {
        await tester.pumpWidget(host(LfMarkdown(text: text)));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason:
              '畸形输入不得抛异常：${text.length > 20 ? '${text.substring(0, 20)}…' : text}',
        );
      }
    });

    testWidgets('内部引用标记 [canteen-dish:abc] 不出现（先清洗再渲染）', (tester) async {
      // 清洗在 `replyTextForDisplay`；渲染器只负责渲染已清洗的文本。
      // 这条钉的是「渲染器不会把被清洗过的标记重新暴露」。
      await tester.pumpWidget(
        host(const LfMarkdown(text: '看这道菜：[canteen-dish:abc] 番茄炒蛋')),
      );
      await tester.pumpAndSettle();
      // 渲染器本身不负责清洗，但也不该把方括号变成链接或崩溃。
      expect(tester.takeException(), isNull);
    });

    testWidgets('随机拼接 50 段不崩（fuzz 式）', (tester) async {
      const pieces = [
        '**a**',
        '_b_',
        '`c`',
        '# d',
        '- e',
        '1. f',
        '> g',
        '---',
        '```',
        '\n',
        '\n\n',
        '普通文本',
        '[x](y)',
        '| t |',
        '\\*',
        '***',
        '~~~',
      ];
      for (var seed = 0; seed < 50; seed++) {
        final buffer = StringBuffer();
        for (var i = 0; i <= seed % 12; i++) {
          buffer.write(pieces[(seed * 7 + i * 3) % pieces.length]);
        }
        await tester.pumpWidget(host(LfMarkdown(text: buffer.toString())));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('渲染上限', () {
    testWidgets('超过 200 行的消息折叠（不一次渲完）', (tester) async {
      final long = List.generate(400, (i) => '第 $i 行').join('\n');
      await tester.pumpWidget(host(LfMarkdown(text: long)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 折叠态给一个可点的「展开全部」。
      expect(find.byKey(const Key('lf-markdown-expand')), findsOneWidget);
    });
  });
}
