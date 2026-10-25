/// CSV 表格公式守卫（CWE-1236）与它的**逆运算**——两半必须成对使用。
///
/// 问题：Excel / Numbers / Sheets 会把以 `=`、`+`、`-`、`@` 或前导 Tab/CR 开头的
/// 单元格当**公式**执行。用户在食物名里写 `=HYPERLINK("http://…")` 就是命令式
/// payload，导出文件被别人用表格软件打开时会跟着跑。
///
/// 解法：导出时给这类单元格加前导单引号（表格软件共同的「强制文本」记号），
/// **值本身一字不改**；导入时把这一枚记号拆掉，值就回到原样。
///
/// 2026-10-21 设备实测（食物库导出 → 原样导入）：只有加、没有拆 ⇒ 名称被写成
/// `'+电商山楂饼`，与库内 (名称, 品牌) 身份对不上，自己导出的文件重新导入会
/// 冒出「2 条新条目」。所以两半放在**同一处**，谁也别想只改一半。
///
/// 关于 `'` 自己：它也在守卫集里，否则变换不可逆——名字本来就以 `'` 开头时
/// （`'+abc`），导出不加记号、导入却会拆掉一枚 ⇒ 名字被吃掉一个字符。
/// 现在 `'+abc` 导出成 `''+abc`、导入拆回 `'+abc`，**严格互逆**。
library;

/// 会触发表格公式语义的前导字符（`'` 见上文：为了可逆而纳入）。
const Set<String> kCsvFormulaTriggers = {'=', '+', '-', '@', '\t', '\r', "'"};

/// 导出侧：该加前导单引号就加。纯数字（如 `-5`、`+5`）**不处理**——加了引号
/// 反而让导入侧把数值列当文本，破坏数字。
String neutralizeFormulaCell(String cell) {
  if (cell.isEmpty) return cell;
  if (!kCsvFormulaTriggers.contains(cell[0])) return cell;
  if (double.tryParse(cell) != null) return cell;
  return "'$cell";
}

/// 导入侧：拆掉 [neutralizeFormulaCell] 加的那一枚前导单引号。
///
/// 只在「首字符是 `'` 且第二字符仍在守卫集里」时拆——**普通文本里的单引号
/// （`'引号开头` 里的那枚，后面跟着的是普通字）一动不动**，手写文件的引号
/// 也被原样保留。
String restoreFormulaGuard(String cell) {
  if (cell.length < 2) return cell;
  if (cell[0] != "'") return cell;
  if (!kCsvFormulaTriggers.contains(cell[1])) return cell;
  return cell.substring(1);
}
