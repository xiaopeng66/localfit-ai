import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';

/// T6b（docs/32 §4 T6b / §3 D5）：`workout.plan.create` 命令规格与 `planDays` 组合类型。
///
/// 覆盖：① 命令已注册且 danger=create、days 用新组合类型；
/// ② `planDays` 机械校验（weekday 越界 / 空 entries / 超 7 天 / 非列表 /
/// sets·reps 非正整数 / weightKg 负值 / 缺动作名 全部拒绝）；
/// ③ `weightKg` 可省略（自重动作）；
/// ④ 注册表命令数 = 34（T6b 24 → T8 23 → 2026-10-15 docs/34 补 10 条到 33，再加 menu.snapshot.publish 到 34）。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommandSpec specOf(String action) {
    final spec = registry.specOf(action);
    expect(spec, isNotNull, reason: '$action 必须已注册');
    return spec!;
  }

  /// 与 decoder 同路径校验一组参数。
  Map<String, Object> validate(String action, Map<Object?, Object?> raw) =>
      validateChatEditArgs(specOf(action), raw);

  group('T6b workout.plan.create 规格', () {
    test('已注册，name 与 days 必填，danger=create，days 用 planDays', () {
      final s = specOf('workout.plan.create');
      expect(s.title, '创建训练计划');
      expect(s.danger, ChatEditDanger.create);
      expect(s.args.map((a) => a.name), containsAll(['name', 'days']));
      expect(s.specOf('name')!.required, isTrue);
      expect(
        s.specOf('days')!.type,
        ChatEditArgType.planDays,
        reason: 'days 必须是新的组合类型 planDays（仿 foodItems 先例）',
      );
      expect(s.specOf('days')!.required, isTrue);
    });

    test('summarize 报天数与动作总数（编辑卡上看得见规模）', () {
      final s = specOf('workout.plan.create');
      final summary = s.summarize({
        'name': '四天增肌',
        'days': [
          {
            'weekday': 1,
            'entries': [
              {'exercise': '杠铃深蹲', 'sets': 4, 'reps': 8},
            ],
          },
          {
            'weekday': 3,
            'entries': [
              {'exercise': '卧推', 'sets': 4, 'reps': 10},
              {'exercise': '划船', 'sets': 3, 'reps': 12},
            ],
          },
        ],
      });
      expect(summary, contains('四天增肌'));
      expect(summary, contains('2 个训练日'));
      expect(summary, contains('3 条动作'));
    });
  });

  group('T6b planDays 机械校验', () {
    test('合法输入通过并归一化（weekday/sets/reps 成 int，weightKg 成 double）', () {
      final args = validate('workout.plan.create', {
        'name': '计划',
        'days': [
          {
            'weekday': 1,
            'entries': [
              {'exercise': '深蹲', 'sets': 4, 'reps': 8, 'weightKg': 60},
            ],
          },
        ],
      });
      final days = args['days'] as List;
      final day = days.single as Map;
      expect(day['weekday'], 1);
      final entry = (day['entries'] as List).single as Map;
      expect(entry['exercise'], '深蹲');
      expect(entry['sets'], isA<int>());
      expect(entry['reps'], isA<int>());
      expect(entry['weightKg'], 60.0);
    });

    test('weekday 越界（0 / 8 / 小数）拒绝', () {
      for (final bad in <Object>[0, 8, 1.5]) {
        expect(
          () => validate('workout.plan.create', {
            'name': '计划',
            'days': [
              {
                'weekday': bad,
                'entries': [
                  {'exercise': '深蹲', 'sets': 4, 'reps': 8},
                ],
              },
            ],
          }),
          throwsA(isA<ChatEditArgsException>()),
          reason: 'weekday=$bad 应被拒绝',
        );
      }
    });

    test('空 entries / 超过 7 天 / days 非列表 / days 为空 拒绝', () {
      expect(
        () => validate('workout.plan.create', {
          'name': '计划',
          'days': [
            {'weekday': 1, 'entries': <Object?>[]},
          ],
        }),
        throwsA(isA<ChatEditArgsException>()),
      );
      expect(
        () => validate('workout.plan.create', {
          'name': '计划',
          'days': [
            for (var i = 0; i < 8; i++)
              {
                'weekday': (i % 7) + 1,
                'entries': [
                  {'exercise': '深蹲', 'sets': 4, 'reps': 8},
                ],
              },
          ],
        }),
        throwsA(isA<ChatEditArgsException>()),
      );
      expect(
        () => validate('workout.plan.create', {'name': '计划', 'days': '不是列表'}),
        throwsA(isA<ChatEditArgsException>()),
      );
      expect(
        () => validate('workout.plan.create', {
          'name': '计划',
          'days': <Object?>[],
        }),
        throwsA(isA<ChatEditArgsException>()),
      );
    });

    test('sets/reps 非正整数、weightKg 负值、动作名空 拒绝', () {
      final bad = <Map<String, Object?>>[
        {'exercise': '深蹲', 'sets': 0, 'reps': 8},
        {'exercise': '深蹲', 'sets': 4, 'reps': 0},
        {'exercise': '深蹲', 'sets': 2.5, 'reps': 8},
        {'exercise': '深蹲', 'sets': 4, 'reps': 8, 'weightKg': -5},
        {'exercise': '  ', 'sets': 4, 'reps': 8},
      ];
      for (final entry in bad) {
        expect(
          () => validate('workout.plan.create', {
            'name': '计划',
            'days': [
              {
                'weekday': 1,
                'entries': [entry],
              },
            ],
          }),
          throwsA(isA<ChatEditArgsException>()),
          reason: '$entry 应被拒绝',
        );
      }
    });

    test('weightKg 可省略（自重动作）', () {
      final args = validate('workout.plan.create', {
        'name': '计划',
        'days': [
          {
            'weekday': 2,
            'entries': [
              {'exercise': '俯卧撑', 'sets': 3, 'reps': 15},
            ],
          },
        ],
      });
      final days = args['days'] as List;
      final entry = ((days.single as Map)['entries'] as List).single as Map;
      expect(entry.containsKey('weightKg'), isFalse);
    });
  });

  test('注册表命令数 37（T6b 24 → T8 23 → docs/34 补 11 → S11 补 2）', () {
    expect(registry.specs, hasLength(37));
    final actions = registry.specs.map((s) => s.action).toList();
    expect(actions.toSet(), hasLength(actions.length), reason: 'action 唯一');
    expect(actions, contains('workout.plan.create'));
    // S11（docs/38）：长期记忆两条。
    expect(actions, contains('memory.remember'));
    expect(actions, contains('memory.forget'));
  });
}
