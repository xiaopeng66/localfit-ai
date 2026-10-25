/// 食物名称的显示层清洗（docs/28 §5.4，N11）。
///
/// 种子库把品牌印在名称头部（`7-ELEVEN 7-11御饭团(酱烧鳗口味)`、
/// `Nichirei日冷 抹茶…`），而卡片要把品牌挪到底行、名称只留产品名。清洗
/// **只在显示层做**：种子行数据不重生成、`name` 列不改（搜索仍按原始
/// `name` 匹配 —— 搜「Beretta」照样找得到，只是卡上不再显示前缀）。
library;

import 'package:localfit_ai/utils/food_brands.g.dart';
import 'package:localfit_ai/utils/food_brands_reviewed.g.dart';

/// 运行时品牌词表 = 自动表 ∪ 人工表（docs/29 §P8b-2、D13）。
///
/// 两张表**分开存放**：自动表按规则从种子重算得出，人工表是全量审核
/// 里人一眼判下来的结论（含自动规则按设计排除的纯汉字品牌，如「明治」）。分开
/// 才保住「自动表可从种子重算」这条性质；显示层在这里取并集使用。
final Set<String> kFoodBrandTokensAll = <String>{
  ...kFoodBrandTokens,
  ...kFoodBrandTokensReviewed,
};

/// 括号式品牌：`(Beretta) Prosciutto Cotto火腿片` → 品牌在括号里。
///
/// 括号内容只允许拉丁字母/数字与 `& ' - .` 和空格：`(韩国)蜂蜜柚子茶` 的
/// 括号是产地说明、`(Fe+VC)无糖泡腾片` 的括号是营养标注（`+` 不在允许集
/// 里），两者都不算品牌——计划里点名的反例就是这两类。
final RegExp _parenthesizedLatinBrand = RegExp(
  r"^\(([A-Za-z0-9][A-Za-z0-9&'\-.]*(?: [A-Za-z0-9&'\-.]*)*)\)[ \t]*(.+)$",
);

/// 把「品牌 + 产品名」拆成两段（docs/28 §5.4 的三条规则，按序）：
///
///  1. `(拉丁词) 其余` → `brand = 括号内`、`name = 其余`；
///  2. `首 token 其余` 且 token ∈ [kFoodBrandTokensAll]（自动表 ∪ 人工表）→
///     `brand = token`、`name = 其余`；
///  3. 其余原样返回（`name = raw`、`brand = null`）。
///
/// 只按**空白边界**切分：`Nichirei日冷`（品牌与译名粘在一个 token 里）整体
/// 当作品牌，不再往 token 内部切——token 内部没有「这里是品牌、这里是产品」
/// 的标记，往里切就是凭空造边界。
///
/// 不变量（`test/utils/food_name_test.dart` 在全部种子条目上枚举）：
/// `normalizeFoodName(brand + ' ' + name) == normalizeFoodName(raw)` ——
/// 拆分绝不丢字。唯一例外是规则 1 的括号式名字：括号本身是「这是品牌」的
/// 标记，按计划不在品牌里保留（字面损失只有那一对括号，测试对这 5 条断言
/// 「去掉括号后相等」）。
///
/// [brands] 只为测试注入（真实调用点用生成的 [kFoodBrandTokensAll]，
/// 即自动表 ∪ 人工表）：换掉词表是「拆分依据被拔掉」，相关断言必须变红。
({String name, String? brand}) splitFoodName(
  String raw, {
  Set<String>? brands,
}) {
  final tokens = brands ?? kFoodBrandTokensAll;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return (name: trimmed, brand: null);

  final parenthesized = _parenthesizedLatinBrand.firstMatch(trimmed);
  if (parenthesized != null) {
    final brand = parenthesized.group(1)!.trim();
    final name = parenthesized.group(2)!.trim();
    if (brand.isNotEmpty && name.isNotEmpty) return (name: name, brand: brand);
  }

  final cut = trimmed.indexOf(' ');
  if (cut > 0) {
    final head = trimmed.substring(0, cut);
    final rest = trimmed.substring(cut + 1).trim();
    if (rest.isNotEmpty && tokens.contains(head)) {
      return (name: rest, brand: head);
    }
  }
  return (name: trimmed, brand: null);
}
