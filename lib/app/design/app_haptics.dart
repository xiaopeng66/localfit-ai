import 'package:flutter/services.dart';

/// 触觉反馈单源（docs/21 §2.9）：主按钮成功=medium impact、删除=warning、
/// 打卡/记一餐/拍照=light。全部走 Flutter 内置 HapticFeedback 通道，
/// 零新增依赖；「设置页可关」的开关接线在后续批次接入时统一改这里。
abstract final class AppHaptics {
  /// 轻震：拍照记餐、打卡、记一餐等常规记录动作。
  static void light() => HapticFeedback.selectionClick();

  /// 中等震动：主按钮成功（保存、写入计划）。
  static void success() => HapticFeedback.mediumImpact();

  /// 警告震动：删除、清空等危险动作。
  static void warning() => HapticFeedback.heavyImpact();
}
