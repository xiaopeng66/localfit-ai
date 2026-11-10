/// 整数千位分组渲染（界面计数用）。
///
/// 食物库从 2,464 条扩到 4.9 万条之后，「食材数据库 49464 条」这样的裸数字
/// 与同一页「随包 4.9 万条中文食物」的说法不一致，所以计数一律走这里。
///
/// 规则：只按每三位插逗号，不做本地化（项目没有 intl 依赖，且测试需要确定性
/// 输出）；负数保留符号；0 返回 `0`。
String formatGroupedInt(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// 字节数 → `41.0 MB` 这样的一句话（更新包大小、下载进度用）。
///
/// 以 1024 为进；不到 1 MB 用 KB，负数归零。
/// MB 与小于 10 KB 的数保留一位小数，其余 KB 显示整数。
String formatMegabytes(int bytes) {
  final safe = bytes < 0 ? 0 : bytes;
  const unit = 1024 * 1024;
  if (safe < unit) {
    final kb = safe / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  return '${(safe / unit).toStringAsFixed(1)} MB';
}
