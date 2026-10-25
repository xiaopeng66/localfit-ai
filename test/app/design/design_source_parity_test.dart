import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 设计源 ↔ Dart token 的**机械对账**（阶段 J 验收基建）。
///
/// 为什么需要它：`docs/21` §1 定的是「视觉唯一依据 = `ui设计/pages/*.html`」，
/// 但此前的 token 测试把设计稿的数值**手抄**成 Dart 字面量再断言——抄错、或者
/// 设计源改了而代码没跟，两种漂移都测不出来（测试比的是代码自己）。这里改成
/// 直接读 HTML 的 `theme-vars` 块解析期望值，于是「设计源 → 代码」这条链每跑
/// 一次门禁就对账一次。
///
/// 覆盖「阶段 J 验收 6 维度」里可机械化的五项：背景色/描边（语义表面 token）、
/// 卡片圆角（radius 六档）、色块比例之外的取色（ramp/数据色）、阴影公式、
/// 暗色模式（`html.dark` 整块）。剩下「色块位置与比例、字号层级、间距」由各页
/// 的几何探针（`docs/evidence/2026-10-01-stage-j-*.md`）与页面测试覆盖——那些
/// 不是 token 层的事，读 HTML 也对不出来。
void main() {
  // 解析在设计源上的 `expect` 只能在测试体内跑（收集阶段用 expect 会抛
  // OutsideTestException），所以放到 setUpAll。
  late final List<_DesignSource> sources;
  late final _Round7Source round7;
  setUpAll(() {
    sources = _loadSources();
    round7 = _loadRound7();
  });

  group('设计源自洽：8 页的 theme-vars 只有 radius 块存在两版', () {
    test('8 个页面各有一份 theme-vars', () {
      expect(
        sources.map((s) => s.name).toList(),
        unorderedEquals([
          'AI 工作.html',
          '今日.html',
          '初始引导.html',
          '我的.html',
          '拍照识餐.html',
          '训练.html',
          '饮食 · 记录.html',
          '饮食 · 菜单.html',
        ]),
      );
    });

    test('除 radius 外，8 页每一对同名变量的取值完全一致（改一处不会漏改其余）', () {
      final names = <String>{};
      for (final s in sources) {
        names.addAll(s.light.keys.where((k) => !k.startsWith('--lf-radius-')));
      }
      expect(names, isNotEmpty);

      final drifted = <String>[];
      for (final name in names) {
        final values = <String>{};
        for (final s in sources) {
          final v = s.light[name];
          if (v == null) {
            drifted.add('$name 在 ${s.name} 缺失');
          } else {
            values.add(v);
          }
        }
        if (values.length > 1) {
          drifted.add('$name 有 ${values.length} 种取值：${values.join(' / ')}');
        }
      }
      expect(
        drifted,
        isEmpty,
        reason:
            '设计源内部漂移会让「唯一依据」失效。除 --lf-radius-*（docs/21 §2.3 已裁决过'
            '的两版）外，8 页变量必须逐值一致',
      );
    });

    test('radius 六档恰好只有两版，且与 docs/21 §2.3 记录的两张表一致', () {
      const restrained = {
        '--lf-radius-xs': '4px',
        '--lf-radius-sm': '8px',
        '--lf-radius-md': '12px',
        '--lf-radius-lg': '16px',
        '--lf-radius-xl': '16px',
        '--lf-radius-2xl': '16px',
      };
      const large = {
        '--lf-radius-xs': '8px',
        '--lf-radius-sm': '12px',
        '--lf-radius-md': '16px',
        '--lf-radius-lg': '20px',
        '--lf-radius-xl': '24px',
        '--lf-radius-2xl': '32px',
      };

      final copies = <String, List<String>>{};
      for (final s in sources) {
        final key = restrained.keys.map((k) => s.light[k]).join(',');
        copies.putIfAbsent(key, () => []).add(s.name);
      }
      expect(copies.keys.toSet(), {
        restrained.values.join(','),
        large.values.join(','),
      }, reason: '出现第三个 radius 版本说明设计源又漂了一次，必须重新裁决');

      // 采用哪一版：`今日.html` 是样板页（docs/22 阶段 B「定调」），Dart 跟它。
      final sample = sources.firstWhere((s) => s.name == '今日.html');
      expect({for (final k in restrained.keys) k: sample.light[k]}, restrained);
      expect(LfDimens.radiusXs, 4);
      expect(LfDimens.radiusSm, 8);
      expect(LfDimens.radiusMd, 12);
      expect(LfDimens.radiusLg, 16);
      expect(LfDimens.radiusXl, 16);
      expect(LfDimens.radius2xl, 16);
    });
  });

  group('亮色 theme-vars ↔ Dart token（逐值）', () {
    late _DesignSource t;
    setUp(() => t = sources.firstWhere((s) => s.name == '今日.html'));

    test('mint / neutral 两条 ramp 十档', () {
      for (final tone in _rampTones) {
        expect(
          LfColors.mintLight.tone(tone),
          t.color('--lf-mint-$tone'),
          reason: 'mint-$tone',
        );
        expect(
          LfColors.neutralLight.tone(tone),
          t.color('--lf-neutral-$tone'),
          reason: 'neutral-$tone',
        );
      }
    });

    test('分类数据色五组（编码不可变）', () {
      expect(LfColors.proteinLight, t.color('--lf-protein'));
      expect(LfColors.protein100Light, t.color('--lf-protein-100'));
      expect(LfColors.carbsLight, t.color('--lf-carbs'));
      expect(LfColors.carbs100Light, t.color('--lf-carbs-100'));
      expect(LfColors.fatLight, t.color('--lf-fat'));
      expect(LfColors.fat100Light, t.color('--lf-fat-100'));
      expect(LfColors.waterLight, t.color('--lf-water'));
      expect(LfColors.weightLight, t.color('--lf-weight'));
    });

    test('语义表面 token（背景色 / 描边就是这一组）', () {
      final c = LfSemanticColors.light;
      expect(c.background, t.color('--lf-background'));
      expect(c.foreground, t.color('--lf-foreground'));
      expect(c.card, t.color('--lf-card'));
      expect(c.cardForeground, t.color('--lf-card-foreground'));
      expect(c.popover, t.color('--lf-popover'));
      expect(c.popoverForeground, t.color('--lf-popover-foreground'));
      expect(c.muted, t.color('--lf-muted'));
      // 次文色与主按钮前景已由用户选定的 Round7 A 主稿接管（docs/33 §4.2）：
      // 旧八页仍是 ramp / 状态 / 证据与未变语义的输入，这两个角色改读
      // `design/round7` 的有效层叠（styles → refinement → polish），逐值对账
      // 见下方「Round7 A」组。
      expect(c.mutedForeground, round7.light['--muted']);
      expect(c.border, t.color('--lf-border'));
      expect(c.input, t.color('--lf-input'));
      expect(c.ring, t.color('--lf-ring'));
      expect(c.primary, t.color('--lf-primary'));
      expect(c.primaryForeground, round7.color('.btn.primary', 'color'));
    });

    test('状态色与证据分级色', () {
      final c = LfSemanticColors.light;
      expect(c.success, t.color('--lf-state-success'));
      expect(c.successForeground, t.color('--lf-state-success-foreground'));
      expect(c.warning, t.color('--lf-state-warning'));
      expect(c.warningForeground, t.color('--lf-state-warning-foreground'));
      expect(c.error, t.color('--lf-state-error'));
      expect(c.errorForeground, t.color('--lf-state-error-foreground'));
      expect(c.info, t.color('--lf-state-info'));
      expect(c.infoForeground, t.color('--lf-state-info-foreground'));
      expect(c.evidenceA, t.color('--lf-evidence-a'));
      expect(c.evidenceB, t.color('--lf-evidence-b'));
      expect(c.evidenceC, t.color('--lf-evidence-c'));
    });

    test('hero 渐变三停靠位的取色', () {
      expect(
        LfComponentColors.light.heroGradient,
        t.gradientColors('--lf-hero-gradient'),
      );
      expect(
        LfComponentColors.light.heroStops,
        t.gradientStops('--lf-hero-gradient'),
      );
    });

    test('三条阴影公式逐层逐值（含 spread——CSS 的第 4 个长度参数）', () {
      expect(_canon(LfShadows.surface(true)), t.shadows('--lf-shadow-1'));
      expect(_canon(LfShadows.float(true)), t.shadows('--lf-shadow-float'));
      expect(
        _canon(LfShadows.floatLg(true)),
        t.shadows('--lf-shadow-float-lg'),
      );
    });
  });

  group('暗色 theme-vars ↔ Dart token（逐值）', () {
    late _DesignSource t;
    setUp(() => t = sources.firstWhere((s) => s.name == '今日.html'));

    test('两条 ramp 十档（暗色方向相反，不许照抄亮色）', () {
      for (final tone in _rampTones) {
        expect(
          LfColors.mintDark.tone(tone),
          t.darkColor('--lf-mint-$tone'),
          reason: 'mint-$tone',
        );
        expect(
          LfColors.neutralDark.tone(tone),
          t.darkColor('--lf-neutral-$tone'),
          reason: 'neutral-$tone',
        );
      }
    });

    test('分类数据色暗色档', () {
      expect(LfColors.proteinDark, t.darkColor('--lf-protein'));
      expect(LfColors.protein100Dark, t.darkColor('--lf-protein-100'));
      expect(LfColors.carbsDark, t.darkColor('--lf-carbs'));
      expect(LfColors.carbs100Dark, t.darkColor('--lf-carbs-100'));
      expect(LfColors.fatDark, t.darkColor('--lf-fat'));
      expect(LfColors.fat100Dark, t.darkColor('--lf-fat-100'));
      expect(LfColors.waterDark, t.darkColor('--lf-water'));
      expect(LfColors.weightDark, t.darkColor('--lf-weight'));
    });

    test('语义表面 / 状态 / 证据 token 暗色档', () {
      final c = LfSemanticColors.dark;
      expect(c.background, t.darkColor('--lf-background'));
      expect(c.foreground, t.darkColor('--lf-foreground'));
      expect(c.card, t.darkColor('--lf-card'));
      expect(c.muted, t.darkColor('--lf-muted'));
      expect(c.mutedForeground, t.darkColor('--lf-muted-foreground'));
      expect(c.border, t.darkColor('--lf-border'));
      expect(c.input, t.darkColor('--lf-input'));
      expect(c.ring, t.darkColor('--lf-ring'));
      expect(c.primary, t.darkColor('--lf-primary'));
      // 同浅色组：主按钮前景 = A `.btn.primary` 的 `#10271D`（两主题同值，
      // `refinement.css:2`；不是主题自定义属性，因此两主题读同一条规则）。
      expect(c.primaryForeground, round7.color('.btn.primary', 'color'));
      expect(c.success, t.darkColor('--lf-state-success'));
      expect(c.warning, t.darkColor('--lf-state-warning'));
      expect(c.error, t.darkColor('--lf-state-error'));
      expect(c.info, t.darkColor('--lf-state-info'));
      expect(c.evidenceA, t.darkColor('--lf-evidence-a'));
      expect(c.evidenceB, t.darkColor('--lf-evidence-b'));
      expect(c.evidenceC, t.darkColor('--lf-evidence-c'));
    });

    test('hero 渐变换成暗色三停靠位', () {
      expect(
        LfComponentColors.dark.heroGradient,
        t.darkGradientColors('--lf-hero-gradient'),
      );
      expect(
        LfComponentColors.dark.heroStops,
        t.darkGradientStops('--lf-hero-gradient'),
      );
    });

    test('暗色阴影（shadow-1 是 1px 白色描边——spread 必须真的画出来）', () {
      expect(_canon(LfShadows.surface(false)), t.darkShadows('--lf-shadow-1'));
      expect(
        _canon(LfShadows.float(false)),
        t.darkShadows('--lf-shadow-float'),
      );
      expect(
        _canon(LfShadows.floatLg(false)),
        t.darkShadows('--lf-shadow-float-lg'),
      );
    });
  });
  group('Round7 A 有效层叠 ↔ Dart token（本次新增的有界对账）', () {
    test('层叠顺序与深色特异性：后出的 :root 不得覆盖深色角色', () {
      expect(round7.light['--muted'], _cssColor('#5C7067'));
      expect(round7.light['--fg'], _cssColor('#1A201D'));
      // --brand-strong：styles #187653 → refinement #1B8A62 → polish #187653，
      // 取最后（polish）那份，同时证明三层顺序真的按文档执行。
      expect(round7.light['--brand-strong'], _cssColor('#187653'));
      // 深色 --muted 由 refinement 的 html[data-theme="dark"] 给出；polish 的
      // `:root{--muted:#5C7067}` 出现在它后面，但特异性更低，不得覆盖。
      expect(round7.dark['--muted'], _cssColor('#8FA09A'));
      expect(round7.dark['--fg'], _cssColor('#DDE5E1'));
      expect(round7.dark['--brand-strong'], _cssColor('#4ED9A6'));
    });

    test('语义角色逐值对齐 A（浅色 / 深色）', () {
      const light = LfSemanticColors.light;
      const dark = LfSemanticColors.dark;
      expect(light.background, round7.light['--bg']);
      expect(light.card, round7.light['--card']);
      expect(light.foreground, round7.light['--fg']);
      expect(light.mutedForeground, round7.light['--muted']);
      expect(light.primary, round7.light['--brand']);
      expect(light.border, round7.light['--border']);
      expect(light.muted, round7.light['--track']);
      expect(
        LfColors.mintText(Brightness.light),
        round7.light['--brand-strong'],
      );
      expect(
        LfColors.brandSoft(Brightness.light),
        round7.light['--brand-soft'],
      );
      expect(LfComponentColors.light.ringTrack, round7.light['--track']);
      expect(dark.background, round7.dark['--bg']);
      expect(dark.card, round7.dark['--card']);
      expect(dark.foreground, round7.dark['--fg']);
      expect(dark.mutedForeground, round7.dark['--muted']);
      expect(dark.primary, round7.dark['--brand']);
      expect(dark.border, round7.dark['--border']);
      expect(LfColors.mintText(Brightness.dark), round7.dark['--brand-strong']);
      expect(LfColors.brandSoft(Brightness.dark), round7.dark['--brand-soft']);
      expect(LfComponentColors.dark.ringTrack, round7.dark['--track']);
    });

    test('几何角色取自 A 的字面规则（按钮 / 卡片 / 弹层 / 把手）', () {
      expect(LfDimens.buttonRadius, round7.length('.btn', 'border-radius'));
      expect(LfDimens.radiusLg, round7.length('.card', 'border-radius'));
      expect(
        LfDimens.sheetRadius,
        round7.length('.app-sheet', 'border-radius').abs(),
      );
      final handle = AppTheme.light().bottomSheetTheme.dragHandleSize!;
      expect(handle.width, round7.length('.sheet-handle::after', 'width'));
      expect(handle.height, round7.length('.sheet-handle::after', 'height'));
    });
  });
}

// ── 解析器 ────────────────────────────────────────────────────────────────

/// design CSS 的 ramp 档位（没有 150/250 这类中间档）。
const _rampTones = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900];

/// 一条阴影的规范字符串：`x y blur spread #AARRGGBB`，层间用 ` | ` 连接。
///
/// 刻意把 **spread 写进规范形**：CSS 的第 4 个长度参数（`0 0 0 1px`）与
/// Flutter 的 `spreadRadius` 等价，漏抄它就会画不出那 1px 环——而只看
/// offset/blur/color 的断言抓不到这种漏抄。
String _canon(List<BoxShadow> shadows) => shadows
    .map(
      (s) =>
          '${_num(s.offset.dx)} ${_num(s.offset.dy)} ${_num(s.blurRadius)} '
          '${_num(s.spreadRadius)} #'
          '${s.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
    )
    .join(' | ');

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

class _DesignSource {
  _DesignSource(this.name, this.light, this.dark);

  final String name;
  final Map<String, String> light;
  final Map<String, String> dark;

  String _get(String key) {
    final v = light[key] ?? dark[key];
    expect(v, isNotNull, reason: '$name 缺变量 $key（设计源改了？）');
    return v!;
  }

  Color color(String key) => _cssColor(_get(key));
  Color darkColor(String key) {
    final v = dark[key];
    expect(v, isNotNull, reason: '$name 的 html.dark 缺变量 $key');
    return _cssColor(v!);
  }

  List<Color> gradientColors(String key) =>
      _cssGradient(_require(light, key)).map((s) => s.color).toList();
  List<double> gradientStops(String key) =>
      _cssGradient(_require(light, key)).map((s) => s.stop).toList();
  List<Color> darkGradientColors(String key) =>
      _cssGradient(_require(dark, key)).map((s) => s.color).toList();
  List<double> darkGradientStops(String key) =>
      _cssGradient(_require(dark, key)).map((s) => s.stop).toList();

  String _require(Map<String, String> vars, String key) {
    final v = vars[key];
    expect(v, isNotNull, reason: '$name 缺变量 $key（设计源改了？）');
    return v!;
  }

  String shadows(String key) => _cssShadows(_require(light, key));
  String darkShadows(String key) => _cssShadows(_require(dark, key));
}

List<_DesignSource> _loadSources() {
  final dir = Directory('ui设计/pages');
  expect(
    dir.existsSync(),
    isTrue,
    reason: '找不到设计源 ${dir.absolute.path}——测试的工作目录必须是包根',
  );
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.html'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return [for (final f in files) _parse(f)];
}

_DesignSource _parse(File file) {
  final text = file.readAsStringSync();
  final block = RegExp(r'<style id="theme-vars">([\s\S]*?)</style>')
      .firstMatch(text)
      ?.group(1);
  expect(block, isNotNull, reason: '${file.path} 没有 theme-vars 块');

  final darkAt = block!.indexOf('html.dark');
  expect(
    darkAt,
    greaterThan(0),
    reason: '${file.path} 的 theme-vars 没有 html.dark 段',
  );

  return _DesignSource(
    file.uri.pathSegments.last,
    _declare(block.substring(0, darkAt)),
    _declare(block.substring(darkAt)),
  );
}

Map<String, String> _declare(String segment) {
  final out = <String, String>{};
  for (final m in RegExp(
    r'--(lf-[a-z0-9-]+)\s*:\s*([^;]+);',
  ).allMatches(segment)) {
    out['--${m.group(1)}'] = m.group(2)!.trim();
  }
  return out;
}

Color _cssColor(String value) {
  final hex = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(value);
  if (hex != null) {
    return Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
  }
  final rgba = RegExp(
    r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$',
  ).firstMatch(value);
  expect(rgba, isNotNull, reason: '认不出的颜色字面量：$value');
  final alpha = rgba!.group(4) == null ? 1.0 : double.parse(rgba.group(4)!);
  // 设计稿用 0..1 的 alpha，Flutter 用 8bit——量化到最近的整数档，与
  // `Color(0x0A0F241C)` 这类字面量的换算方式一致。
  return Color.fromARGB(
    (alpha * 255).round(),
    int.parse(rgba.group(1)!),
    int.parse(rgba.group(2)!),
    int.parse(rgba.group(3)!),
  );
}

List<({Color color, double stop})> _cssGradient(String value) {
  final inner = RegExp(r'linear-gradient\(([\s\S]*)\)$')
      .firstMatch(value)
      ?.group(1);
  expect(inner, isNotNull, reason: '认不出的渐变：$value');
  final parts = _splitTopLevel(inner!);
  expect(parts.first.trim(), matches(RegExp(r'^\d+deg$')), reason: '渐变角度段缺失');
  return [
    for (final part in parts.skip(1))
      () {
        final bits = part.trim().split(RegExp(r'\s+'));
        expect(bits, hasLength(2), reason: '色彩停靠位语法：$part');
        return (
          color: _cssColor(bits[0]),
          stop: double.parse(bits[1].replaceAll('%', '')) / 100,
        );
      }(),
  ];
}

String _cssShadows(String value) => _splitTopLevel(value)
    .map((layer) {
      // 长度单位可省（CSS 里 `0` 不写 `px`）。
      final m = RegExp(
        r'^(-?[\d.]+)(?:px)?\s+(-?[\d.]+)(?:px)?\s+(-?[\d.]+)(?:px)?'
        r'(?:\s+(-?[\d.]+)(?:px)?)?\s+([a-z]+\(.+\))$',
      ).firstMatch(layer.trim());
      expect(m, isNotNull, reason: '认不出的阴影层：${layer.trim()}');
      final spread = m!.group(4) ?? '0';
      final color = _cssColor(m.group(5)!.trim());
      final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
      return '${_num(double.parse(m.group(1)!))} ${_num(double.parse(m.group(2)!))} '
          '${_num(double.parse(m.group(3)!))} ${_num(double.parse(spread))} #$hex';
    })
    .join(' | ');

/// 按顶层逗号切分（跳过括号内的逗号——`rgba(15, 36, 28, .04)` 不能被切开）。
List<String> _splitTopLevel(String value) {
  final out = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (ch == ',' && depth == 0) {
      out.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

// ── Round7 A 有效层叠（有界读取） ──────────────────────────────────────────

/// `design/round7` 的**有效**层叠（`index.html:9–11` 的顺序：
/// `styles.css` → `refinement.css` → `polish.css`）。
///
/// 只取两类事实：
///  * `:root` / `html[data-theme="dark"]` 两个自定义属性块 → 语义角色；
///  * 少量字面规则（`.btn`、`.btn.primary`、`.card`、`.app-sheet`、
///    `.sheet-handle::after`）→ 几何角色。
///
/// 不读取 `html[data-variant="b"|"c"]`、`data-large`、`data-embed` —— 那些是
/// B/C 版式比较与原型预览开关，不是 A 的角色来源。特异性按 CSS 建模：
/// 后出现的 `:root` **不能**覆盖已由 `html[data-theme="dark"]` 声明的深色值。
class _Round7Source {
  _Round7Source({
    required Map<String, String> lightVars,
    required Map<String, String> darkVars,
    required this._rules,
  }) : light = _round7Colors(lightVars),
       dark = _round7Colors(darkVars);

  /// 只留颜色类自定义属性（`--shadow` / `--ease` 这类非颜色值不进 map，
  /// 否则 `_cssColor` 会当场抛）。
  final Map<String, Color> light;
  final Map<String, Color> dark;
  final List<({String selector, String property, String value})> _rules;

  String rule(String selector, String property) {
    for (final rule in _rules.reversed) {
      if (rule.selector == selector && rule.property == property) {
        return rule.value;
      }
    }
    fail('Round7 设计源缺规则 $selector { $property }（设计源改了？）');
  }

  Color color(String selector, String property) =>
      _cssColor(rule(selector, property));

  /// 长度属性（`12px` / `24px 24px 0 0` → 首个数值）。
  double length(String selector, String property) => double.parse(
    RegExp(r'-?[\d.]+').firstMatch(rule(selector, property))!.group(0)!,
  );
}

Map<String, Color> _round7Colors(Map<String, String> vars) {
  final out = <String, Color>{};
  for (final entry in vars.entries) {
    final value = entry.value;
    if (value.startsWith('#') ||
        value.startsWith('rgb') ||
        value.startsWith('hsl')) {
      out[entry.key] = _cssColor(value);
    }
  }
  return out;
}

_Round7Source _loadRound7() {
  final dir = Directory('design/round7');
  expect(
    dir.existsSync(),
    isTrue,
    reason: '找不到 Round7 设计源 ${dir.absolute.path}——测试的工作目录必须是包根',
  );
  final light = <String, String>{};
  final darkOverrides = <String, String>{};
  final rules = <({String selector, String property, String value})>[];
  for (final name in ['styles.css', 'refinement.css', 'polish.css']) {
    final css = File('${dir.path}/$name')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    _round7Walk(css, (selector, body) {
      final declarations = _round7Declarations(body);
      final custom = {
        for (final entry in declarations.entries)
          if (entry.key.startsWith('--')) entry.key: entry.value,
      };
      if (selector == ':root') {
        // 后出的文件覆盖先出的（层叠顺序即文件顺序）。
        light.addAll(custom);
      } else if (selector == 'html[data-theme="dark"]') {
        // 深色只覆盖显式声明过的键——`:root` 的深色**基线**在下面合并，
        // 于是 polish 里那个更晚但特异性更低的 `:root{--muted:...}` 不会
        // 把 refinement 的深色值冲掉（这正是本组的测试 1 要钉的事实）。
        darkOverrides.addAll(custom);
      }
      for (final entry in declarations.entries) {
        rules.add((
          selector: selector,
          property: entry.key,
          value: entry.value,
        ));
      }
    });
  }
  return _Round7Source(
    lightVars: light,
    darkVars: {...light, ...darkOverrides},
    rules: rules,
  );
}

/// 极简规则遍历：跟踪花括号深度；`@media` 之类的条件块内的真规则递归收下。
void _round7Walk(String css, void Function(String, String) emit) {
  var index = 0;
  while (index < css.length) {
    final open = css.indexOf('{', index);
    if (open < 0) break;
    var depth = 1;
    var cursor = open + 1;
    while (cursor < css.length && depth > 0) {
      final ch = css.codeUnitAt(cursor);
      if (ch == 0x7B) depth++;
      if (ch == 0x7D) depth--;
      cursor++;
    }
    final selector = css.substring(index, open).trim();
    final body = css.substring(open + 1, cursor - 1);
    if (selector.startsWith('@')) {
      _round7Walk(body, emit);
    } else {
      emit(selector, body);
    }
    index = cursor;
  }
}

Map<String, String> _round7Declarations(String body) {
  final out = <String, String>{};
  for (final part in body.split(';')) {
    final at = part.indexOf(':');
    if (at <= 0) continue;
    final key = part.substring(0, at).trim();
    final value = part.substring(at + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;
    out[key] = value;
  }
  return out;
}
