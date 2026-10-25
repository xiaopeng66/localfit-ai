import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/app_motion.dart';

/// docs/21 §2.9：「其余交互动效沿用现有 `AppMotion`（fast 150 / base 250 /
/// 标准 spring）」——弹簧三档与隐式动画时长是**仍在服役**的 token，不属于
/// 阶段 I-3 删除的 `App*` 旧 token 组。原断言从 `app_tokens_test.dart`
/// 原样迁到这里，避免随旧套件一起被删掉。
void main() {
  group('弹簧动效 token（docs/21 §2.9）', () {
    test('三档弹簧参数固定', () {
      expect(AppMotion.springQuick.stiffness, 500);
      expect(AppMotion.springQuick.damping, 30);
      expect(AppMotion.springQuick.mass, 1);
      expect(AppMotion.springStandard.stiffness, 380);
      expect(AppMotion.springStandard.damping, 26);
      expect(AppMotion.springSlow.stiffness, 260);
      expect(AppMotion.springSlow.damping, 24);
    });

    test('隐式动画时长伴随档位（quick≈240 / standard≈380 / slow≈550）', () {
      expect(AppMotion.springQuickDuration, const Duration(milliseconds: 240));
      expect(
        AppMotion.springStandardDuration,
        const Duration(milliseconds: 380),
      );
      expect(AppMotion.springSlowDuration, const Duration(milliseconds: 550));
    });
  });
}
