/// 诊断文本脱敏（2026-10-21 审查 RV-P2-13）。
///
/// 调试面板会把异常/任务失败原因上屏；drift 的 `SqliteException` 可能带
/// SQL 片段与数据库绝对路径，任务失败原因也可能是同样的字符串。这里只做
/// 两件事：**抹掉绝对路径**、**截断超长**——保留可诊断性，不泄漏本机布局。
String sanitizeDiagnosticText(String raw, {int maxLength = 160}) {
  // Windows 盘符路径（E:\a\b 或 E:/a/b）。反斜杠用普通字符串双写。
  var text = raw.replaceAll(RegExp('[A-Za-z]:[\\\\/][^\\s"<>]+'), '<path>');
  // POSIX 路径只抹常见的应用数据目录，避免误伤普通斜杠文本。
  text = text.replaceAll(
    RegExp('/(?:data|storage|Users)/[^\\s"<>]+'),
    '<path>',
  );
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}…';
}
