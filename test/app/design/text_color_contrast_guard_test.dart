import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 2026-11-09 全量审查：**「什么颜色能当文字」的守卫**。
///
/// 既有 `token_contrast_test` 只钉了 `warningText` / `errorText` 自身达标，
/// 但没有任何东西阻止调用点继续用 `primary`(#2FBE8F) / `error`(#F44336)
/// 当正文——实测浅色主题下这三处组合全部低于 AA：
///
/// | 组合 | 比值 |
/// | --- | --- |
/// | primary 压 card | 2.36 |
/// | primary 压 mint-50 | 2.22 |
/// | primary 压 muted | 2.11 |
/// | error 压 muted | 3.29 |
/// | error 压 card | 3.68 |
///
/// 本测试把「文字档」的底线固定住，并明确记录哪几档**不许**当正文，
/// 避免以后有人「看着挺绿挺红」又改回去。
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

  for (final (name, colors, brightness) in [
    ('light', LfSemanticColors.light, Brightness.light),
    ('dark', LfSemanticColors.dark, Brightness.dark),
  ]) {
    group(name, () {
      test('文字档 mintText 在 card / background / muted / mint-50 上都 ≥4.5:1', () {
        final mint = LfColors.mint(brightness);
        final backgrounds = <String, int>{
          'card': argbOf(colors.card),
          'background': argbOf(colors.background),
          'muted': argbOf(colors.muted),
          'mint-50': argbOf(mint.tone(50)),
        };
        for (final entry in backgrounds.entries) {
          final r = ratio(argbOf(LfColors.mintText(brightness)), entry.value);
          expect(
            r,
            greaterThanOrEqualTo(4.5),
            reason: '$name mintText/${entry.key} = ${r.toStringAsFixed(2)}',
          );
        }
      });

      test('文字档 errorText 在 card / muted 上 ≥4.5:1', () {
        for (final entry in {
          'card': argbOf(colors.card),
          'muted': argbOf(colors.muted),
        }.entries) {
          final r = ratio(argbOf(colors.errorText), entry.value);
          expect(
            r,
            greaterThanOrEqualTo(4.5),
            reason: '$name errorText/${entry.key} = ${r.toStringAsFixed(2)}',
          );
        }
      });

      test('颜色填充档 primary / error **不许**当浅色文字（记录实测）', () {
        // 不是断言「必须失败」，而是钉住已知数值：若哪天 token 改了导致
        // 这两档真的达标，这条会红，提醒同步更新「文字档」的规则说明。
        final lightMint = LfColors.mintLight.tone(500);
        final lightPrimaryRatio = ratio(
          argbOf(lightMint),
          argbOf(LfSemanticColors.light.card),
        );
        expect(
          lightPrimaryRatio,
          lessThan(4.5),
          reason:
              'primary 作为浅色主题正文色实测 ${lightPrimaryRatio.toStringAsFixed(2)}:1：'
              '若已改到达标，请把本注释/规则一起更新，并允许调用点使用它',
        );
      });
    });
  }
}
