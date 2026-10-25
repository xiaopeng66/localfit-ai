import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_source_license.dart';

/// 菜单来源与许可证的展示标签（阶段 I-2c：旧 `MenuFreshnessBar` 的诚实性
/// 断言在此重新落点）。
///
/// 旧件（2.0-6b 的快照新鲜度条）按 docs/21 §5.3 被“地点→窗口→菜品”三级
/// 自建结构取代，整件删除。它的四条断言去向：
///
/// - 「无快照给出可操作提示」：新菜单 tab 的空态由 `AppEmptyState` 承担
///   （`menu_tab_view_test` 覆盖）；
/// - 「有效快照显示更新于/有效至」：快照概念（导入时间/过期）在新结构中
///   不再面向用户，随件删除；
/// - 「过期写『快照已过期』」：过期语义仍在域层（`next_meal_decision_controller`
///   「快照已过期或已被新版本取代」），有 `next_meal_decision_card_test` 覆盖；
/// - **「未知来源/许可证照实写『未记录』，不猜」——这条是诚实规则
///   （docs/21 §6.1）的组成部分，必须保留**：落点从渲染层移到纯函数
///   `labelOf`，并补齐旧测试没覆盖的「已知 token 给中文标签」一档。
void main() {
  test('来源类型：已知 token 给中文标签，空值写「未记录」不猜', () {
    expect(MenuSourceType.labelOf(MenuSourceType.pastedText), '粘贴文本');
    expect(MenuSourceType.labelOf(MenuSourceType.fileTxtCsvJson), '文件导入');
    expect(MenuSourceType.labelOf(null), '来源未记录');
    expect(MenuSourceType.labelOf(''), '来源未记录');
    // 未知 token 原样返回，便于发现新来源没补标签（不吞成「未记录」）。
    expect(MenuSourceType.labelOf('future_type'), 'future_type');
  });

  test('许可证：已知 token 给中文标签，空值写「未记录」不猜', () {
    expect(
      MenuSourceLicense.labelOf(MenuSourceLicense.userProvided),
      '用户提供（无第三方许可）',
    );
    expect(
      MenuSourceLicense.labelOf(MenuSourceLicense.userFile),
      '用户提供文件（无第三方许可）',
    );
    expect(MenuSourceLicense.labelOf(null), '许可证未记录');
    expect(MenuSourceLicense.labelOf(''), '许可证未记录');
    // SPDX 之类的已记录标识原样显示。
    expect(MenuSourceLicense.labelOf('CC-BY-4.0'), 'CC-BY-4.0');
  });

  test('存储 token 是稳定字面量（备份往返与查询都按它断言）', () {
    expect(MenuSourceType.pastedText, 'pasted_text');
    expect(MenuSourceType.fileTxtCsvJson, 'file_txt_csv_json');
    expect(MenuSourceLicense.userProvided, 'user-provided');
    expect(MenuSourceLicense.userFile, 'user-file');
  });
}
