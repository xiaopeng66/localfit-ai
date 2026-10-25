/// 食物名称中文规范化。
///
/// 用于 [FoodLibraryView] 和 [FoodSearchTab] 的食物名称渲染，把原始数据
/// 里的下划线/横杠统一转空格、去掉多余空白，并把英文单词首字母大写。
///
/// 规则（按优先级）：
///  1. 去除首尾空白。
///  2. 将 `_` 和 `-` 替换为空格（连续多个 collapse 为单个空格）。
///  3. 每个空格分隔的词按形态分类处理（**只补大小写，不丢信息**）：
///     * 含汉字的混合词原样保留——`AB100健能`、`KITTY猫`、
///       `100%WHOLEWHEATBREAD100%全麦面包` 的内部大写是品牌/型号的一部分；
///     * 全大写数字字母串（`OREO`/`AGF`/`250ML`/`V8`）原样保留；
///     * 其余（纯拉丁词）只保证首字母大写；词内已有大写时保留其余大小写
///       （`ACfarm`/`HokkaidoCream` 不该被压成 `Acfarm`/`hokkaidocream`）。
///  4. 保留中文、数字、括号、标点，不做强行替换。
///
/// 2026-10-04 修复（docs/28 §5.4）：旧实现一律 `first.toUpperCase() +
/// rest.toLowerCase()`，把含中文的混合词内部大写也压平了
/// （`dplus 天然酵母面包HokkaidoCream` → `…hokkaidocream`），而那正是品牌在
/// 名称里的**唯一**大小写线索——名称清洗（`splitFoodName`）之后卡上要靠它
/// 认出品牌，压平就再也认不出来了。
library;

final RegExp _han = RegExp(r'[\u4e00-\u9fff]');
final RegExp _digitsAndCapsOnly = RegExp(r'^[A-Z0-9]+$');
final RegExp _hasUpper = RegExp(r'[A-Z]');

String normalizeFoodName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final normalized = trimmed
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  final words = <String>[];
  for (final word in normalized.split(' ')) {
    if (word.isEmpty) continue;
    words.add(_restoreCase(word));
  }
  return words.join(' ');
}

String _restoreCase(String word) {
  if (_han.hasMatch(word)) return word;
  if (_digitsAndCapsOnly.hasMatch(word)) return word;
  if (word.length == 1) return word.toUpperCase();
  final rest = word.substring(1);
  final body = _hasUpper.hasMatch(rest) ? rest : rest.toLowerCase();
  return word[0].toUpperCase() + body;
}
