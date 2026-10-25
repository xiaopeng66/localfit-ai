import 'dart:io';

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 用户头像（docs/32 §3 D9）：**有图显示图、无图显示首字母、无昵称回退「Fit」**。
///
/// 三处共用同一件：我的页身份卡（56dp 圆）、今日页顶栏（44dp 圆角方块）、
/// 对话页顶栏（36dp 圆）——**尺寸与形状由调用方给**（[size] 与 [circle]），
/// 本件只管「取什么内容显示」与「文件缺失时的回退」。
///
/// **文件缺失必须回退**（D9 如实记的限制）：`.lfb` 只带 `avatarPath` 字符串、
/// 不带图片字节；换机恢复后那个路径可能指不到文件 ⇒ 回退首字母，
/// 而不是留一块空白或红叉。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.displayName,
    required this.size,
    this.avatarPath,
    this.circle = true,
    this.imageKey,
    this.initialKey,
    this.background,
    this.foreground,
    this.borderColor,
  });

  /// 昵称。null/空 → 首字母回退「Fit」（与 `DashboardGreetingHeader.avatarInitial`
  /// 既有口径一致）。
  final String? displayName;

  /// 头像文件路径。null → 直接走首字母，不做文件探测。
  final String? avatarPath;

  final double size;

  /// true = 圆形（身份卡/对话顶栏）；false = 圆角 16 方块（今日页顶栏，既有形态）。
  final bool circle;

  /// 落在图片本体的 Key（测试用它断言「显示的是图」）。
  final Key? imageKey;

  /// 落在首字母文字的 Key（测试用它断言回退）。
  final Key? initialKey;

  /// 底色覆盖。null = 品牌浅档 `mint-100`（既有三处共用形态）。
  ///
  /// 有覆盖需求的是 Round7 A 的 `.avatar{background:var(--brand-soft)}`
  /// （今日页顶栏 44dp 圆）——A 的浅档是 `--brand-soft`，与 ramp 的 `mint-100`
  /// 不是同一个值，所以由调用方显式给。
  final Color? background;

  /// 首字母/前景色覆盖。null = `LfColors.mintText`。
  final Color? foreground;

  /// 描边覆盖。null = 语义 `border`（A 顶栏头像描的是 `--card`）。
  final Color? borderColor;

  /// 首字：昵称第一个字；无昵称回退「Fit」。
  static String initialOf(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'Fit';
    return trimmed.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    final radius = circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(LfDimens.radiusLg);
    final filePath = avatarPath;
    // **同步探测文件存在性**（而不是只靠 `Image.file` 的 errorBuilder）：
    // ① errorBuilder 是异步解码失败路径，widget 测试里不泵够帧就不触发
    //    （实测：路径不存在时首字母不出现）；
    // ② 换机恢复（`.lfb` 只带路径不带字节）与用户清理都会命中这里，
    //    需要**立刻**回退而不是先闪一下空框。
    final hasFile =
        filePath != null && filePath.isNotEmpty && File(filePath).existsSync();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background ?? mint.tone(100),
        borderRadius: radius,
        border: Border.all(color: borderColor ?? c.border),
      ),
      alignment: Alignment.center,
      child: hasFile ? _image(filePath, brightness) : _initial(brightness),
    );
  }

  Widget _initial(Brightness brightness) => Text(
    initialOf(displayName),
    key: initialKey,
    // 小尺寸（≤40dp）用 caption 档：56dp 上的 titleLarge 在 36dp 圆里会顶边。
    style: LfText.titleLarge.copyWith(
      color: foreground ?? LfColors.mintText(brightness),
      fontSize: size <= 40 ? LfText.caption.fontSize : null,
    ),
  );

  Widget _image(String filePath, Brightness brightness) => Image.file(
    File(filePath),
    key: imageKey,
    width: size,
    height: size,
    fit: BoxFit.cover,
    // 「路径在库里但文件不在/不可读」：换机恢复（`.lfb` 不带图片字节）
    // 与用户手动清理都会走到这里 —— 回退首字母，不留空白。
    errorBuilder: (context, error, stackTrace) => _initial(brightness),
  );
}
