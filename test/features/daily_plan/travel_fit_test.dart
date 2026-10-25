import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/daily_plan/application/travel_fit.dart';

/// T8（docs/32 §4 T8 / §3 D10）：`travelFit` 的输入源（手动分钟数 + 单次路线
/// 查询）已随整条纵切下线，取值**恒为中性**。映射函数连同它的档位断言一并
/// 退役——留着一个没人调用的映射只会诱使后来者重新接线。端到端的中性值由
/// `next_meal_decision_controller_test.dart` 的引擎断言钉住。
void main() {
  test('neutral is the mid value: neither rewards nor punishes', () {
    expect(TravelFit.neutral, 0.5);
    expect(TravelFit.neutral, greaterThan(0.0));
    expect(TravelFit.neutral, lessThan(1.0));
  });
}
