import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RV-P1-10 / RV-P1-11：弹层约定护栏（docs/21 附录 D8）。
///
/// 裸 `showModalBottomSheet` 必须：
/// * `useRootNavigator: true` —— 否则挂进 shell 分支导航器，被贴底栏盖住；
/// * `enableDrag: false` —— 拖拽只认把手；
/// * 至少一处 `sheetBottomInset(` 或 `AppSheet` —— 键盘 + 安全区 + 最小留白。
///
/// 2026-10-19 修过一次手动营养弹层，2026-10-20 审查又发现 3 处新弹层没照约定。
/// 这条静态护栏让「下一次忘写」在门禁里就红。
void main() {
  test('lib/ 里所有裸 showModalBottomSheet 都遵守 D8 三件套', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      final calls = RegExp(r'showModalBottomSheet(<[^>]*>)?\(')
          .allMatches(source);
      for (final call in calls) {
        // 取调用点后 900 字符作为「这一块」：足够覆盖参数列表。
        final block = source.substring(
          call.start,
          (call.start + 900).clamp(0, source.length),
        );
        final name = file.path.replaceAll(r'\', '/');
        // AppSheet 是共享壳：三件套由它自己实现，不需要再套一层。
        if (name.endsWith('lib/app/design/widgets/app_sheet.dart')) continue;
        if (!block.contains('useRootNavigator: true')) {
          offenders.add('$name: 缺 useRootNavigator: true');
        }
        if (!block.contains('enableDrag: false')) {
          offenders.add('$name: 缺 enableDrag: false');
        }
        if (!block.contains('sheetBottomInset(') &&
            !block.contains('AppSheet')) {
          offenders.add('$name: 缺 sheetBottomInset(');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'D8 约定（docs/21 附录 D8）:\n${offenders.join('\n')}\n'
          '（AppSheet 内部的调用已由 AppSheet 统一实现，这里只查裸调用）',
    );
  });
}
