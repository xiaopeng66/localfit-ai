/// 食堂三级结构（地点/窗口/菜品）的表单预校验（docs/28 §3.5）。
///
/// [CanteenFormSheet] 收集到的字段值先在这里过一遍：仓库层仍会再验一次，
/// 这里只是把「弹层先关、错误只在页面上闪一下、用户输入全丢」提前拦住——
/// 错误画在弹层内，用户可以直接改。规则与 `CanteenRepository` 的字面口径
/// 逐字一致（同一个严格 `HH:MM` 正则），避免两处判定漂移。
library;

String? validateVenueForm(Map<String, String> values) {
  if ((values['canteen-venue-name'] ?? '').trim().isEmpty) {
    return '请填写地点名称。';
  }
  return null;
}

String? validateWindowForm(Map<String, String> values) {
  if ((values['canteen-window-name'] ?? '').trim().isEmpty) {
    return '请填写窗口名称。';
  }
  final open = _hhmmMinutes((values['canteen-window-open'] ?? '').trim());
  if (open == null) return '开始时间要写成 08:30 这样的格式。';
  final close = _hhmmMinutes((values['canteen-window-close'] ?? '').trim());
  if (close == null) return '结束时间要写成 08:30 这样的格式。';
  if (close <= open) return '结束时间要晚于开始时间。';
  return null;
}

/// 菜品表单校验：**只剩名称**（2026-10-16 用户删掉价格，字段与规则同批撤）。
String? validateDishForm(Map<String, String> values) {
  if ((values['canteen-dish-name'] ?? '').trim().isEmpty) {
    return '请填写菜品名称。';
  }
  return null;
}

/// 严格 `HH:MM`（与 `CanteenRepository._requireHhmm` 同一正则）；
/// 不合法返回 null。
int? _hhmmMinutes(String raw) {
  if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(raw)) return null;
  final parts = raw.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
