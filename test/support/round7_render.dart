import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const round7Boundary = Key('round7-native-render');

Future<void> loadRound7Fonts() async {
  // `FlutterTest` 是 flutter_test 的**默认字体家族**。前三个名字是阶段 1 组件
  // 样板显式指定的家族；整页捕获跑的是 `LocalFitApp` 自己建的 theme
  // （`AppTheme` 不指定 fontFamily），文字因此落到默认家族上——不把本机 CJK
  // 字体也注册到这个名字下，整页渲染出来就是豆腐块，审图无从谈起。
  for (final family in ['Round7LocalCjk', 'Roboto', 'Ahem', 'FlutterTest']) {
    final loader = FontLoader(family);
    loader.addFont(
      File('C:/Windows/Fonts/msyh.ttc')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)),
    );
    loader.addFont(
      File('C:/Windows/Fonts/msyhbd.ttc')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)),
    );
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// 捕获用的主题：把本机 CJK 族注入**所有**会被渲染的文本样式。
///
/// 【为什么不止 `textTheme`】（Round7 阶段 6 · 缺陷 ㉔，渲染审看抓到）：
/// `AppTheme` 按 `docs/21 §2.6.1` **不内置字体族**（真机落到平台默认 CJK），
/// 但它把若干样式**冻结**在主题里（`listTileTheme.titleTextStyle/subtitleTextStyle`、
/// 历史上还有 `appBarTheme.titleTextStyle`）。这些冻结样式**在构建 ThemeData 时
/// 就定型**，`copyWith(textTheme: …)` 追不进去；而 `ListTile` / `AppBar` 又是
/// **替换**（不是合并）环境 `DefaultTextStyle` 的 ⇒ 测试引擎里没有平台兜底，
/// 标题渲染成 `.notdef` 空方框（资料编辑页的「减脂/维持/增肌」、`AppBar` 标题都出过）。
/// 真机不受影响 ⇒ 这是**帧保真**修正：由捕获件补族，**生产代码不动**。
ThemeData round7CaptureTheme(ThemeData source) => source.copyWith(
  textTheme: source.textTheme.apply(fontFamily: 'Round7LocalCjk'),
  primaryTextTheme: source.primaryTextTheme.apply(fontFamily: 'Round7LocalCjk'),
  listTileTheme: source.listTileTheme.copyWith(
    titleTextStyle: source.listTileTheme.titleTextStyle?.copyWith(
      fontFamily: 'Round7LocalCjk',
    ),
    subtitleTextStyle: source.listTileTheme.subtitleTextStyle?.copyWith(
      fontFamily: 'Round7LocalCjk',
    ),
  ),
  appBarTheme: source.appBarTheme.copyWith(
    titleTextStyle: source.appBarTheme.titleTextStyle?.copyWith(
      fontFamily: 'Round7LocalCjk',
    ),
  ),
);

Future<void> captureRound7(WidgetTester tester, String name) async {
  final output = Platform.environment['LF_ROUND7_CAPTURE_DIR'];
  if (output == null) return;
  final normalized = output.replaceAll('\\', '/');
  if (!normalized.startsWith('E:/AI/Zcode/tmp/') || normalized.contains('..')) {
    throw ArgumentError('Capture output must be within workspace tmp');
  }
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(round7Boundary),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$normalized/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
