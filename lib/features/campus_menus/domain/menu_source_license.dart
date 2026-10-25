/// 菜单来源的类型与许可证（docs/07 §6.1：`menu_sources` 记录来源类型、
/// 用户输入 URL/文件引用、许可证、是否允许保存原文；docs/07 §6.3：所有菜单显示
/// 「来源、导入时间、业务日期、过期状态」）。
///
/// 这里的取值是入库的稳定 token（测试与备份往返都按它断言），中文只出现在
/// [labelOf] 的展示标签里。**拿不准就写未记录**：空值一律显示「未记录」，
/// 不假设「用户自己导入的就没有条款问题」——这正是许可证字段存在的意义。
library;

/// 来源类型 token（与 `menu_sources.sourceType` 的注释枚举一致）。
abstract final class MenuSourceType {
  /// 用户粘贴的菜单文本（走 AI 解析或本地 JSON 解析）。
  static const String pastedText = 'pasted_text';

  /// 用户导入的本地 TXT/CSV/JSON 文件。
  static const String fileTxtCsvJson = 'file_txt_csv_json';

  /// 展示用标签；未知 token 原样返回，便于发现新来源没补标签。
  static String labelOf(String? sourceType) => switch (sourceType) {
    pastedText => '粘贴文本',
    fileTxtCsvJson => '文件导入',
    null || '' => '来源未记录',
    _ => sourceType,
  };
}

/// 许可证/使用条款 token。
abstract final class MenuSourceLicense {
  /// 用户自己粘贴的内容：没有第三方许可，条款由用户与原始来源之间决定。
  static const String userProvided = 'user-provided';

  /// 用户自己导入的本地文件：同上。
  static const String userFile = 'user-file';

  /// 展示用标签；已记录的 SPDX 之类标识原样显示，未记录就说未记录。
  static String labelOf(String? license) => switch (license) {
    userProvided => '用户提供（无第三方许可）',
    userFile => '用户提供文件（无第三方许可）',
    null || '' => '许可证未记录',
    _ => license,
  };
}
