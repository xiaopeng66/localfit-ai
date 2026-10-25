import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// RV-P1-13：告警/错误色当**正文/图标**时必须达到 WCAG AA。
///
/// 2026-10-20 审查实测：`warning`(#FF9800) 当文字只有 2.16:1，
/// 异常日原先用白字画在橙底上（2.16），`error` 当正文 3.68。
/// 新增的 `warningText` / `errorText` 是「当文字」专用档。
void main() {
  double channel(int v) {
    final c = v / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  }

  double ratio(int fg, int bg) {
    final a = luminance(fg) + 0.05;
    final b = luminance(bg) + 0.05;
    return a > b ? a / b : b / a;
  }

  int argbOf(Object color) => (color as dynamic).toARGB32() as int;

  for (final (name, colors) in [
    ('light', LfSemanticColors.light),
    ('dark', LfSemanticColors.dark),
  ]) {
    test('$name：warningText 作正文 ≥4.5:1', () {
      for (final bg in [
        argbOf(colors.card),
        argbOf(colors.background),
        argbOf(colors.muted),
      ]) {
        final r = ratio(argbOf(colors.warningText), bg);
        // ignore: avoid_print
        print(
          '$name warningText/${bg.toRadixString(16)} = ${r.toStringAsFixed(2)}',
        );
        expect(
          r,
          greaterThanOrEqualTo(4.5),
          reason:
              '$name warningText 对底 ${bg.toRadixString(16)} = '
              '${r.toStringAsFixed(2)}',
        );
      }
    });

    test('$name：warningText 画在 warning@12% tint 上 ≥4.5:1', () {
      final base = argbOf(colors.card);
      final warn = argbOf(colors.warning);
      int mix(int a, int b, double t) {
        int ch(int shift) {
          final av = (a >> shift) & 0xFF;
          final bv = (b >> shift) & 0xFF;
          return ((av * t) + (bv * (1 - t))).round() & 0xFF;
        }

        return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
      }

      final r = ratio(argbOf(colors.warningText), mix(warn, base, 0.12));
      expect(
        r,
        greaterThanOrEqualTo(4.5),
        reason: '实测 ${r.toStringAsFixed(2)}',
      );
    });

    test('$name：errorText 作正文 ≥4.5:1', () {
      final r = ratio(argbOf(colors.errorText), argbOf(colors.card));
      expect(
        r,
        greaterThanOrEqualTo(4.5),
        reason: '实测 ${r.toStringAsFixed(2)}',
      );
    });
  }
}
