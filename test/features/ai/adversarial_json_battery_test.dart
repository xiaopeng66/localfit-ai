import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/data/meal_estimate_json_decoder.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';
import 'package:localfit_ai/features/training/data/workout_plan_json_decoder.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// docs/11 §3-C 对抗 JSON 电池：**仍在生产链路里的**合同 decoder 面对
/// 「越界数值 / 错误枚举 / 多余字段 / 嵌套注入 / 超长字符串 / 原型污染形状」
/// 时的行为。
///
/// 判据只有两条：**要么整单拒绝**（抛异常，不落库），**要么安全截断**
/// （数量截到上限、文本截到上限、不可识别枚举归 null/缺省）。绝不允许
/// 「越界值被放行成事实」——AI 返回值不能直接变成本地营养/训练事实。
///
/// 2026-10-22（RV2-P2-01 退役）：`dish-guidance.v1` / `meal-pairing.v1` /
/// `daily-menu-plan.v1` / `dish-nutrition` 四份契约的解码器已随对应的
/// 「AI 创作卡」改为对话启动而退役（生产零调用，见 `docs/03` 三节的
/// as-built 横幅）。本电池只保留仍有生产调用点的三份合同：
/// `meal-estimate`（拍照识餐）、`menu-normalize`（菜单发布）、
/// `workout-plan`（训练计划）。退役那四份的原判据不再有意义——它们守的
/// 代码路径已不存在；对应的输入约束改由 chat-edit 命令层（参数规格 +
/// 快照 id allow-list）承担。
void main() {
  group('超长字符串：截断到上限或整单拒绝，绝不原样放行', () {
    test('meal-estimate：超过 maxJsonLength 的正文在解析前就被挡下', () {
      final json = '{"schema_version":1,"items":[],"pad":"${'a' * 70000}"}';
      expect(
        () => const MealEstimateJsonDecoder().decode(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('menu-normalize：超长 venue_name 整单拒绝（带违规明细）', () {
      final json =
          '{"schema_version":1,"source_date":"2026-10-22",'
          '"venue_name":"${'x' * 300}","services":[],"warnings":[]}';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(isA<MenuNormalizeFormatException>()),
      );
    });
  });

  group('越界数值：负数 / NaN / 无穷 / 超上限', () {
    test('meal-estimate：克数越界（0 / 负数 / 超上限 / NaN）全部拒绝', () {
      for (final grams in ['0', '-10', '99999', 'NaN']) {
        final json =
            '{"schema_version":1,"items":[{"name":"米饭",'
            '"estimated_grams":$grams}],"warnings":[]}';
        expect(
          () => const MealEstimateJsonDecoder().decode(json),
          throwsA(isA<FormatException>()),
          reason: 'estimated_grams=$grams 必须被拒绝',
        );
      }
    });

    test('workout-plan：负数/超限 sets 与 reps 拒绝', () {
      final request = AiWorkoutPlanRequest(
        daysPerWeek: 1,
        goalText: '增肌',
        exercises: const [ExerciseOption(id: 'ex-squat', name: '深蹲')],
      );
      for (final sets in ['-1', '0', '99']) {
        final json =
            '{"schema_version":1,"name":"计划","days":[{"weekday":1,'
            '"entries":[{"exercise_id":"ex-squat","target_sets":$sets,'
            '"target_reps":8}]}],"warnings":[]}';
        expect(
          () => const WorkoutPlanJsonDecoder().decode(json, request),
          throwsA(isA<FormatException>()),
          reason: 'target_sets=$sets 必须被拒绝',
        );
      }
    });
  });

  group('错误枚举：不可识别的值归 null/缺省，不放行成事实', () {
    test('menu-normalize：不可识别的营业时间整单拒绝，不猜成某个时刻', () {
      // 判据：`morning` 这类值**拒绝**，不许被当成 00:00 或任何具体时间落库
      // ——「显示开着、算成关着」比直接报错更坏。
      const json =
          '{"schema_version":1,"source_date":"2026-10-22",'
          '"venue_name":"一食堂","services":['
          '{"service_name":"一楼","open_time":"morning","close_time":"20:00",'
          '"items":[]}],"warnings":[]}';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(
          isA<MenuNormalizeFormatException>().having(
            (error) => error.errors.join(';'),
            'errors',
            contains('open_time'),
          ),
        ),
      );
    });
  });

  group('多余字段与嵌套注入：不认识的键不许变成事实', () {
    test('workout-plan：引用本地动作库之外的动作整单拒绝', () {
      final request = AiWorkoutPlanRequest(
        daysPerWeek: 1,
        goalText: '增肌',
        exercises: const [ExerciseOption(id: 'ex-squat', name: '深蹲')],
      );
      final json =
          '{"schema_version":1,"name":"计划","days":[{"weekday":1,'
          '"entries":[{"exercise_id":"ex-invented","target_sets":3,'
          '"target_reps":8}]}],"warnings":[]}';
      expect(
        () => const WorkoutPlanJsonDecoder().decode(json, request),
        throwsA(isA<FormatException>()),
      );
    });

    test('menu-normalize：多余字段（含 price_yuan）被忽略，不进草案', () {
      const json =
          '{"schema_version":1,"source_date":"2026-10-22",'
          '"venue_name":"一食堂","services":[{"service_name":"一楼",'
          '"open_time":"08:00","close_time":"20:00","items":['
          '{"display_name":"番茄炒蛋","price_yuan":12,'
          '"reported_nutrition":{"kcal":100}}]}],'
          '"warnings":[],"__proto__":{"polluted":true}}';
      final draft = const MenuNormalizeJsonDecoder().decode(json);
      expect(draft.venueName, '一食堂');
      expect(draft.services.single.items.single.displayName, '番茄炒蛋');
      // 价格已从契约里删除：草案类型上没有价格字段（容忍旧信封、丢字段）。
      expect(draft.services.single.items.single.reportedNutrition?.kcal, 100);
    });
  });

  group('形状攻击：非对象 / 数组当对象 / 深度嵌套 / 截断 JSON', () {
    test('三份 decoder 对「不是单个 JSON 对象」的正文都不放行', () {
      const badInputs = [
        '[]',
        '"just a string"',
        '123',
        '{"a":1}{"b":2}',
        '{"unclosed": ',
        '',
        'null',
      ];
      final request = AiWorkoutPlanRequest(
        daysPerWeek: 1,
        goalText: '增肌',
        exercises: const [ExerciseOption(id: 'ex-squat', name: '深蹲')],
      );
      for (final bad in badInputs) {
        final reason = '正文=${bad.isEmpty ? '(空)' : bad}';
        expect(
          () => const MealEstimateJsonDecoder().decode(bad),
          throwsA(isA<Object>()),
          reason: 'meal-estimate $reason',
        );
        expect(
          () => const MenuNormalizeJsonDecoder().decode(bad),
          throwsA(isA<Object>()),
          reason: 'menu-normalize $reason',
        );
        expect(
          () => const WorkoutPlanJsonDecoder().decode(bad, request),
          throwsA(isA<Object>()),
          reason: 'workout-plan $reason',
        );
      }
    });

    test('数量上限：数组超限一律截断或拒绝，不放行超量事实', () {
      // meal-estimate：21 个条目 > 上限 20 → 拒绝。
      final items = List.generate(
        21,
        (i) => '{"name":"食物$i","estimated_grams":100}',
      ).join(',');
      expect(
        () => const MealEstimateJsonDecoder().decode(
          '{"schema_version":1,"items":[$items],"warnings":[]}',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
