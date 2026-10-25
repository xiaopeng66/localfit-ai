/// 检索用的文本归一化（**唯一实现**）。
///
/// 用途：`food_aliases.normalized_text` 的落库形态、菜单项匹配、AI 预览检索的
/// 比较口径——三处必须同一套规则，否则「存进去的别名」和「查询词」对不上。
///
/// 规则（与 `normalizeMenuText` 历史上的实现逐字节一致）：
///  * 去掉所有空白：半角空格、全角空格（U+3000）、Tab/CR/LF；
///  * 全角 ASCII（U+FF01–U+FF5E）折成半角；
///  * 转小写。
///
/// 不做的事：不做简繁转换、不去标点、不做拼音——那些是**别名数据**该承担的
/// （用户/规则把「西红柿」写成一条别名），不是归一化该猜的。
String normalizeSearchText(String input) {
  final buffer = StringBuffer();
  for (final code in input.runes) {
    if (code == 0x3000 || (code >= 0x09 && code <= 0x0d) || code == 0x20) {
      continue;
    }
    var c = code;
    if (c >= 0xff01 && c <= 0xff5e) c -= 0xfee0;
    buffer.writeCharCode(c);
  }
  return buffer.toString().toLowerCase();
}
