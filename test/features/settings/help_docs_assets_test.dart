import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 需求 17d：帮助文档住在 `assets/help/*.md`（随包、离线可读）。
///
/// 这条是**纯 Dart** 用例（读文件，不碰 widget）：它保证「随包的那几节真的
/// 在仓库里、真的被 pubspec 声明、真的含有关键内容」。渲染与交互由
/// `settings_page_test` 的 17d 用例钉。
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('pubspec 声明了 assets/help/（不声明就随不了包）', () {
    expect(
      pubspec,
      contains('assets/help/'),
      reason: '随包资产必须在 pubspec 里声明，否则真机上读不到',
    );
  });

  test('帮助目录与五节正文都在，且每节非空', () {
    const paths = [
      'assets/help/00-guide.md',
      'assets/help/01-data-and-privacy.md',
      'assets/help/02-ai-boundaries.md',
      'assets/help/03-recording.md',
      'assets/help/04-canteen-and-target.md',
      'assets/help/05-troubleshooting.md',
    ];
    for (final path in paths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '缺少随包文档：$path');
      final text = file.readAsStringSync();
      expect(text.trim(), isNotEmpty, reason: '$path 是空的');
      expect(
        text,
        contains('## '),
        reason: '$path 至少要有二级标题（Markdown 渲染器按标题分段）',
      );
    }
  });

  test('文档含关键内容，且不夹与行为矛盾的隐私断言', () {
    final all = [
      for (final path in const [
        'assets/help/00-guide.md',
        'assets/help/01-data-and-privacy.md',
        'assets/help/02-ai-boundaries.md',
        'assets/help/03-recording.md',
        'assets/help/04-canteen-and-target.md',
        'assets/help/05-troubleshooting.md',
      ])
        File(path).readAsStringSync(),
    ].join('\n');
    for (final phrase in const [
      '数据存在哪里？',
      'AI 会直接改我的数据吗？',
      '怎么记一餐？',
      '热量目标是怎么算出来的？',
      '想反馈问题？',
    ]) {
      expect(all, contains(phrase), reason: '缺少这一节：$phrase');
    }
    // 与行为矛盾的断言不许出现（AI 功能确实会发请求）。
    expect(all, isNot(contains('不会上传到任何服务器')));
    expect(all, contains('不主动使用 AI 功能就不会有内容离开这台设备'));
  });
}
