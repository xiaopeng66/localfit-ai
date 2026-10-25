import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';

/// S7（docs/31 需求 58 / 裁决 D8）：AI 接管能力**多条件**实测。
///
/// 用户原话：「用我给的供应商测试ai接管能力，检查有没有无法识别指令的情况
/// （多条件测试）」。
///
/// AI 架构不是 tool-calling，是 JSON 信封：`renderProtocol()` 把 34 条命令
/// 渲染进系统提示，模型输出 `{"reply":…,"edits":[…]}`，`parseChatEditTurn`
/// 解码。无法识别的指令有三种落法（docs/31 需求 58 勘察）：
/// ① 模型自己说做不到（纯文本）；② 输出未注册 action（行级
/// 「不支持的修改类型」）；③ 信封不合法（当纯文本闲聊）。
///
/// 本文件两个测试：
///
/// **测试 1（零外呼，常规门禁常跑）**——骨架自检：
/// 注册表 34 条、协议段渲染完整、用例矩阵覆盖其子集、种子 id 全部出现在
/// 快照里、三态分类器对 decoder 三条解码路径的契约成立。它同时是「应用侧
/// 前提」的守卫：这些前提不成立时，「模型侧没识别」的归因就不可信。
///
/// **测试 2（默认 skip，零外呼）**——真实供应商的多条件实测（D8 ①②③）：
/// - ① 28 个多条件用例：复合多意图（≥2 意图跨命令族）、单命令逐条覆盖
///   （含快照 id 引用、跨日期引用）、否定/克制、模糊指代、范围外（设计内
///   排除项）。
/// - ② 逐条记录三态：`parsed`（信封合法）/ `unknown_action`（模型编了
///   未注册动作）/ `plain_text`（模型只回话没出信封）；另记 `infra_error`
///   （传输/快照等应用侧管线故障——它必须为 0，否则覆盖表无效）。
/// - ③ 产出 **23 命令 × 多条件覆盖表** + 无法识别指令清单，区分
///   「模型不行」与「我们没实现」（docs/23 §2 的设计内排除单列，不算
///   模型失误；模型对排除项编造动作则算模型侧违规）。
///
/// 运行方式（key 只进环境变量，不落任何仓库文件；供应商与模型由用户指定）：
/// ```
/// LF_LIVE_KEY=... LF_LIVE_BASE=https://.../v1 LF_LIVE_MODEL=... \
///   flutter test test/live/ai_takeover_multi_intent_test.dart
/// ```
/// 可选：`LF_LIVE_LOG`（覆盖表 markdown 落盘路径，给
/// `docs/evidence/2026-10-10-ai-takeover-multi-intent.md` 用）。
///
/// 判定口径：硬断言只卡**管线级**（应用侧前提 + 零管线故障）；模型识别
/// 质量只记录不定罪——覆盖表与无法识别清单才是交付物（D8 ③）。
// 【工具盲点，2026-10-16 实测】`flutter test` **不认** `@Timeout` 注解
// （放 main 上也照样 30s 掐断），所以实时运行的超时由命令行给：
//   flutter test --timeout 240s test/ai_live/...
// 上游 `deepseek-ai/deepseek-v4.1-flash` 实测 TTFB ≈ 11s、整请求 40–46s，
// 默认 30s 会在「app 的传输上限」之前先把用例打断 ⇒ 结论被工具掩盖。
void main() {
  final liveKey = Platform.environment['LF_LIVE_KEY'] ?? '';
  final liveBase = Platform.environment['LF_LIVE_BASE'] ?? '';
  final liveModel = Platform.environment['LF_LIVE_MODEL'] ?? '';
  final skipReason = liveKey.isEmpty
      ? 'S7/D8 需显式授权才发真实请求：设置 LF_LIVE_KEY 等环境变量后运行'
      : null;

  /// 由 `test/ai_live/ai_live_control_matrix_test.dart`（真模型→App 解析→
  /// App 执行器→真库）逐条覆盖的命令（2026-10-15 docs/34 §7 补的 10 条）。
  const Set<String> controlMatrixCoverage = {
    'session.start',
    'set.log',
    'session.finish',
    'plan.entry.add',
    'plan.entry.remove',
    'plan.rename',
    'food.update',
    'food.delete',
    'profile.body.update',
    'targets.update',
    'menu.snapshot.publish',
    // S11（docs/38）：长期记忆两条由控制矩阵 ⑳ 真跑（记住 → 快照带上 → 忘掉）。
    'memory.remember',
    'memory.forget',
  };

  group('S7 AI 接管多条件实测（docs/31 需求 58 / 裁决 D8）', () {
    test('骨架自检：37 命令注册表 × 用例矩阵覆盖 × 快照 id × 三态分类'
        '（零外呼，常规门禁常跑）', () async {
      final registry = ChatEditCommandRegistry();
      final actions = registry.specs.map((spec) => spec.action).toList();
      expect(
        actions,
        hasLength(37),
        reason:
            '2026-10-17 docs/38 S11 补长期记忆 2 条（35 → 37）；'
            '命令数变了，_caseSpecs 必须跟着补用例',
      );
      final protocol = registry.renderProtocol();
      for (final action in actions) {
        expect(
          protocol,
          contains(action),
          reason: '协议段必须渲染出 $action，否则模型根本不知道这条命令存在',
        );
      }
      // 覆盖表不许有洞（D8 ③ 的前提）。**两个矩阵并起来**必须等于注册表：
      // 本文件的 `_caseSpecs`（多条件接管路径）+ `test/ai_live/
      // ai_live_control_matrix_test.dart` 的逐命令控制矩阵（2026-10-15
      // docs/34 补的 10 条在那里逐条真跑：开始/记组/结束、计划编排、自建
      // 食物改删、资料与目标）。归属显式列在这里，不做"看起来覆盖了"。
      final matrixActions = _caseSpecs.expand((spec) => spec.expected).toSet();
      expect(
        matrixActions.union(controlMatrixCoverage),
        equals(actions.toSet()),
        reason: '两个矩阵并起来必须覆盖全部命令；缺口 = 覆盖表的洞',
      );
      expect(
        _caseSpecs.map((spec) => spec.id).toSet(),
        hasLength(_caseSpecs.length),
        reason: '用例 id 必须唯一（报告与覆盖表按 id 对位）',
      );

      // 三态分类器 × decoder 三条解码路径的契约（docs/31 需求 58 ①②③）。
      final registryForClassify = ChatEditCommandRegistry();
      expect(
        _classify(
          parseChatEditTurn(
            '{"reply":"好","edits":'
            '[{"action":"weight.log","args":{"weightKg":72.5}}]}',
            registryForClassify,
          ),
        ),
        _D8State.parsed,
        reason: '合法信封 + 注册命令 → parsed',
      );
      expect(
        _classify(
          parseChatEditTurn(
            '{"reply":"嗯","edits":'
            '[{"action":"meal.move","args":{"mealId":"x"}}]}',
            registryForClassify,
          ),
        ),
        _D8State.unknownAction,
        reason:
            '未注册 action → unknown_action（decoder 的'
            '「不支持的修改类型」路径）',
      );
      expect(
        _classify(parseChatEditTurn('今天吃得不错，继续保持。', registryForClassify)),
        _D8State.plainText,
        reason: '纯文本 → plain_text',
      );
      expect(
        _classify(
          parseChatEditTurn(
            '{"reply":"改","edits":'
            '[{"action":"weight.log","args":{"weightKg":500}}]}',
            registryForClassify,
          ),
        ),
        _D8State.parsed,
        reason:
            '信封合法、命令认识、参数越界 → 仍按 D8 ② 记 parsed'
            '（unknown_action 只留给未注册动作），行级明细单独标注',
      );

      // 应用侧前提：种子行 id 必须全部出现在快照里（live 用例靠它们做
      // 快照 id 引用；快照缺行时「模型侧没识别」的归因不成立）。
      final harness = await _buildHarness();
      try {
        final cases = _materializeCases(harness.seed);
        for (final c in cases) {
          expect(
            c.prompt.contains('{'),
            isFalse,
            reason: '${c.id} 的提示词里还有未替换的占位符',
          );
        }
        final snapshot = await harness.coordinator.contextBuilder.build();
        for (final tagged in harness.seed.taggedSnapshotIds.entries) {
          expect(
            snapshot,
            contains(tagged.value),
            reason:
                '快照必须含 ${tagged.key} 的行 id（${tagged.value}），'
                '否则引用它的 live 用例前提不成立',
          );
        }
        expect(
          snapshot,
          contains('今天：${harness.seed.today}'),
          reason: '快照要标明「今天」，跨日期用例（B15/D1）依赖它',
        );
      } finally {
        await harness.dispose();
      }
    });

    test(
      '多条件实测：29 用例三态记录 + 23 命令覆盖表（默认 skip，零外呼）',
      () async {
        final harness = await _buildHarness();
        final cases = _materializeCases(harness.seed);
        final reports = <_CaseReport>[];
        final markdownLines = <String>[];
        void log(String line) {
          markdownLines.add(line);
          // ignore: avoid_print
          stdout.writeln(line);
        }

        final chat = OpenAiCompatibleConversationService(
          dio: Dio(),
          configurationReader: _FixedConfiguration(
            baseUrl: liveBase,
            model: liveModel,
          ),
          apiKeyStore: _apiKeyStoreWith(liveKey),
        );
        try {
          log('# S7 AI 接管多条件实测 ${DateTime.now().toUtc().toIso8601String()}');
          log('- base=$liveBase model=$liveModel 用例=${cases.length}');
          for (final c in cases) {
            reports.add(
              await _runCase(
                c,
                coordinator: harness.coordinator,
                chat: chat,
                log: log,
              ),
            );
          }
        } finally {
          await harness.dispose();
        }

        // 管线级硬断言（模型质量只记录不定罪，D8 ③ / P11 同一口径）。
        expect(reports, hasLength(cases.length), reason: '每个用例都必须有三态记录（D8 ②）');
        final infraErrors = reports
            .where((report) => report.state == _D8State.infraError)
            .toList();
        expect(
          infraErrors,
          isEmpty,
          reason:
              '管线级故障必须为 0（传输/快照失败时覆盖表无效，先修管线）：'
              '${[for (final r in infraErrors) '${r.c.id}:${r.errorText}'].join('；')}',
        );

        final markdown = _buildMarkdown(
          base: liveBase,
          model: liveModel,
          reports: reports,
          registryActions: harness.registry.specs
              .map((spec) => spec.action)
              .toList(),
        );
        for (final line in markdown.split('\n')) {
          log(line);
        }
        final logPath = Platform.environment['LF_LIVE_LOG'];
        if (logPath != null && logPath.isNotEmpty) {
          await File(logPath).writeAsString('${markdownLines.join("\n")}\n');
          log('[S7] 覆盖表已写入 $logPath');
        }
      },
      timeout: const Timeout(Duration(minutes: 40)),
      skip: skipReason,
    );
  });
}

/// ───────────────────────── 用例矩阵（D8 ①） ─────────────────────────

/// 用例类型；决定「无法识别清单」的归因口径与结论判定。
enum _CaseKind {
  /// 一条消息 ≥2 个意图、跨命令族。
  composite,

  /// 单命令逐条覆盖（含快照 id 引用、跨日期引用）。
  command,

  /// 否定/克制：期望不出信封或不出被否定的那条 edit。
  negation,

  /// 模糊指代：有快照可消解 / 完全无指代对象。
  vague,

  /// 范围外：docs/23 §2 设计内排除项——「我们没实现」，不算模型失误。
  outOfScope,
}

final class _CaseSpec {
  const _CaseSpec(
    this.id,
    this.kind,
    this.template,
    this.expected, {
    this.note,
  });

  final String id;
  final _CaseKind kind;

  /// 提示词模板；`{xxxId}` 占位符在 [_materializeCases] 里用种子 id 替换。
  final String template;

  /// 期望模型输出的 action 集合；空 = 期望不产出任何 edit。
  final List<String> expected;
  final String? note;
}

/// B10 故意排在 B9 前：B10 往窗口里加菜，B9 把窗口删掉（顺序有意为之）。
const List<_CaseSpec> _caseSpecs = [
  // ── A 复合多意图（≥2 意图，跨命令族）──
  _CaseSpec('A1', _CaseKind.composite, '帮我记两笔：今早体重 71.8 公斤；然后刚才喝了 300 毫升水。', [
    'weight.log',
    'water.add',
  ]),
  _CaseSpec(
    'A2',
    _CaseKind.composite,
    '新建一个自定义食材：无糖酸奶，每 100 克 62 千卡、蛋白质 3.4、碳水 5.2、脂肪 1.8；'
        '然后把 150 克无糖酸奶记到今天午餐。',
    ['food.create', 'meal.create'],
    note: '同信封链式依赖：meal.create 引用的食物由同信封里的 food.create 先建',
  ),
  _CaseSpec(
    'A3',
    _CaseKind.composite,
    '我们学校主校区新开了「东区二食堂」，里面有个「麻辣烫」窗口，10:30 到 14:00 营业，'
        '都帮我录进食堂目录。',
    ['canteen.venue.create', 'canteen.window.create'],
    note: 'window.create 的 venue 参数引用同信封里刚建的地点（按精确唯一名）',
  ),
  _CaseSpec(
    'A4',
    _CaseKind.composite,
    '把健康目标改成减脂，目标体重 68 公斤；另外记一笔今天的体重 68.5 公斤。',
    ['weight.log', 'profile.goal.update'],
  ),
  _CaseSpec(
    'A5',
    _CaseKind.composite,
    '把 [meal:{todayLunchMealId}] 这餐的备注改成「食堂加餐」，再记一杯 200 毫升水。',
    ['meal.update', 'water.add'],
    note: '快照 id 引用 + 跨命令族',
  ),
  // ── B 单命令逐条覆盖（补齐 23 命令矩阵；含快照 id / 跨日期引用）──
  _CaseSpec(
    'B1',
    _CaseKind.command,
    '[water:{waterId}] 那条饮水记错了，删掉，重新记 250 毫升。',
    ['water.delete', 'water.add'],
    note: '同族两意图：先删后加',
  ),
  _CaseSpec(
    'B2',
    _CaseKind.command,
    '[item:{eggItemId}] 的鸡蛋实际吃了 80 克，帮我改成 80 克。',
    ['meal.item.update'],
  ),
  _CaseSpec(
    'B3',
    _CaseKind.command,
    '[item:{cucumberItemId}] 那条黄瓜不要了，从这餐里去掉。',
    ['meal.item.delete'],
  ),
  _CaseSpec('B4', _CaseKind.command, '[meal:{dupSnackMealId}] 这餐记重复了，整餐删掉。', [
    'meal.delete',
  ]),
  _CaseSpec(
    'B5',
    _CaseKind.command,
    '收录一道家常菜：清蒸鲈鱼，适合晚餐，每份 180 千卡、蛋白质 22、碳水 0、脂肪 8。',
    ['dish.upsert'],
  ),
  _CaseSpec('B6', _CaseKind.command, '[dish:{dishId}] 红烧排骨不吃了，从菜品库删掉。', [
    'dish.delete',
  ]),
  _CaseSpec('B7', _CaseKind.command, '把 [venue:{venueMainId}] 改名为「东区教工食堂」。', [
    'canteen.venue.rename',
  ]),
  _CaseSpec('B8', _CaseKind.command, '[venue:{venueOldId}] 这个地点撤了，删掉。', [
    'canteen.venue.delete',
  ]),
  _CaseSpec(
    'B10',
    _CaseKind.command,
    // 2026-10-16 S8-b：价格整条退役——`canteen.dish.create` 只收 window+name，
    // 提示词里再写金额会把模型引到一个已不存在的参数上。
    '在 [window:{windowId}] 窗口加个菜：手撕包菜。',
    ['canteen.dish.create'],
  ),
  _CaseSpec('B9', _CaseKind.command, '[window:{windowId}] 这个窗口不营业了，删掉。', [
    'canteen.window.delete',
  ]),
  _CaseSpec(
    'B11',
    _CaseKind.command,
    // S8-b 之后 `canteen.dish.update` 只剩改名（改价随价格列退役）。
    '[canteen-dish:{canteenDishKeepId}] 名字改成「手撕圆白菜」。',
    ['canteen.dish.update'],
  ),
  _CaseSpec(
    'B12',
    _CaseKind.command,
    '[canteen-dish:{canteenDishDropId}] 从窗口菜单里删掉。',
    ['canteen.dish.delete'],
  ),
  _CaseSpec('B13', _CaseKind.command, '我对花生和芝麻过敏，之后别再给我推荐这两样。', [
    'constraints.set',
  ]),
  _CaseSpec('B14', _CaseKind.command, '[wplan:{planId}] 这份训练计划不练了，删掉。', [
    'workout.plan.delete',
  ]),
  _CaseSpec(
    'B17',
    _CaseKind.command,
    // N3（2026-10-16 用户：「食堂菜品 AI 分析以后并没有在食堂目录里显示已分析
    // 和结果」）：分析结果要经这条命令落库，覆盖表必须跟着补。
    '把 [canteen-dish:{canteenDishDropId}] 的营养估一下：每 100 克 120 千卡、'
        '蛋白质 6 克、碳水 12 克、脂肪 5 克，证据等级按 C。',
    ['canteen.dish.nutrition'],
  ),
  _CaseSpec('B15', _CaseKind.command, '补记一下：9 月 1 日那天我体重 70.0 公斤。', [
    'weight.log',
  ], note: '跨日期引用：快照的「今天」是 2026-10-07，模型要推出 localDate=2026-09-01'),
  // T6b（docs/32 §4 T6b）：新增的创建命令也要在矩阵里。
  _CaseSpec(
    'B16',
    _CaseKind.command,
    '按这个给我建个计划并保存：周一深蹲 4 组 8 次 60 公斤，周三卧推 4 组 10 次。',
    ['workout.plan.create'],
    note: '对话创建训练计划（source=ai）；动作名须与本地动作库精确同名',
  ),
  // ── C 否定 / 克制 ──
  _CaseSpec(
    'C1',
    _CaseKind.negation,
    '今天早上体重 72.5 公斤……算了，先别记，晚上再量。',
    [],
    note: '全否定：期望纯文本（或至少不出 weight.log）',
  ),
  _CaseSpec('C2', _CaseKind.negation, '记 300 毫升水，但体重先不要动。', [
    'water.add',
  ], note: '部分否定：water.add 该出、weight.log 不该出'),
  _CaseSpec(
    'C3',
    _CaseKind.negation,
    '先帮我把目标改成增肌——哦等等，还是算了，别改了。',
    [],
    note: '改口取消：期望纯文本',
  ),
  // ── D 模糊指代 ──
  _CaseSpec('D1', _CaseKind.vague, '把昨天那顿午饭改到晚饭。', [
    'meal.update',
  ], note: '可从快照消解的模糊（快照里有昨天午餐行）；看模型选没选对 mealId'),
  _CaseSpec('D2', _CaseKind.vague, '把那个改一下。', [], note: '完全模糊：期望模型反问（纯文本）'),
  // ── E 范围外（docs/23 §2 设计内排除——「我们没实现」）──
  _CaseSpec(
    'E1',
    _CaseKind.outOfScope,
    '帮我把 API key 换成 sk-live-test-000。',
    [],
    note: '凭据/设置类不注册（安全边界）',
  ),
  _CaseSpec(
    'E2',
    _CaseKind.outOfScope,
    // 2026-10-16 真实模型实测后**改写**：原来这条写的是「帮我生成一份新的练背
    // 训练计划。」并断言「chat-edit 不注册计划创建」——但 `workout.plan.create`
    // 早在 T6b 就注册了（B16 就在跑它），这条的**前提已经过期**，于是真模型
    // 老老实实给出信封反被判成「越权改动」。真正的范围外请求应该是仓库里
    // 根本不存在的动作：同步/上传到云端。
    '把我今天的饮食和体重同步到云端账号里。',
    [],
    note: '云端同步不存在（App 是纯本地，无账号体系）⇒ 期望纯文本，不许编造动作',
  ),
  _CaseSpec(
    'E3',
    _CaseKind.outOfScope,
    '把食物库里的鸡蛋删掉。',
    [],
    note: '食物库没有删除命令（种子/目录食物的改删排除）',
  ),
];

final class _Case {
  _Case(this.spec, this.prompt);

  final _CaseSpec spec;
  final String prompt;

  String get id => spec.id;
  _CaseKind get kind => spec.kind;
  List<String> get expected => spec.expected;

  String get kindLabel => switch (kind) {
    _CaseKind.composite => '复合',
    _CaseKind.command => '单命令',
    _CaseKind.negation => '否定',
    _CaseKind.vague => '模糊',
    _CaseKind.outOfScope => '范围外',
  };
}

/// 把模板里的 `{xxxId}` 占位符换成种子行 id。
List<_Case> _materializeCases(_Seed seed) => [
  for (final spec in _caseSpecs)
    _Case(
      spec,
      spec.template
          .replaceAll('{todayLunchMealId}', seed.todayLunchMealId)
          .replaceAll('{dupSnackMealId}', seed.dupSnackMealId)
          .replaceAll('{eggItemId}', seed.eggItemId)
          .replaceAll('{cucumberItemId}', seed.cucumberItemId)
          .replaceAll('{waterId}', seed.waterId)
          .replaceAll('{dishId}', seed.dishId)
          .replaceAll('{venueMainId}', seed.venueMainId)
          .replaceAll('{venueOldId}', seed.venueOldId)
          .replaceAll('{windowId}', seed.windowId)
          .replaceAll('{canteenDishKeepId}', seed.canteenDishKeepId)
          .replaceAll('{canteenDishDropId}', seed.canteenDishDropId)
          .replaceAll('{planId}', seed.planId),
    ),
];

/// ───────────────────────── 三态记录（D8 ②） ─────────────────────────

enum _D8State {
  /// 信封合法。含「命令认识但参数不合法」的行——unknown_action 只留给
  /// 未注册动作；参数问题在行级明细里单独标注。
  parsed,

  /// 信封合法，但模型编了注册表外的 action。
  unknownAction,

  /// 模型只回话，没出（合法）信封——含坏 JSON / 缺键 / 空 edits。
  plainText,

  /// 应用侧管线故障（传输 / 快照构建 / 解码异常）。它必须为 0，
  /// 否则覆盖表无效。
  infraError,
}

String _d8Label(_D8State state) => switch (state) {
  _D8State.parsed => 'parsed',
  _D8State.unknownAction => 'unknown_action',
  _D8State.plainText => 'plain_text',
  _D8State.infraError => 'infra_error',
};

_D8State _classify(ChatEditTurn? turn) {
  if (turn == null) return _D8State.plainText;
  final rows = turn.rows;
  if (rows.any((row) => row.command != null)) return _D8State.parsed;
  final hasUnknownAction = rows.any(
    (row) => (row.decodeError ?? '').contains('不支持的修改类型'),
  );
  if (hasUnknownAction) return _D8State.unknownAction;
  // 全部行都是「参数不合法」的失败：信封与命令名都成立 → parsed 家族。
  return _D8State.parsed;
}

final class _CaseReport {
  const _CaseReport({
    required this.c,
    required this.state,
    required this.matched,
    required this.missing,
    required this.unexpected,
    required this.rowLines,
    required this.applyLines,
    required this.latencyMs,
    required this.replyPreview,
    this.errorText,
  });

  final _Case c;
  final _D8State state;
  final List<String> matched;
  final List<String> missing;
  final List<String> unexpected;
  final List<String> rowLines;
  final List<String> applyLines;
  final int latencyMs;
  final String replyPreview;
  final String? errorText;
}

Future<_CaseReport> _runCase(
  _Case c, {
  required ChatEditCoordinator coordinator,
  required OpenAiCompatibleConversationService chat,
  required void Function(String line) log,
}) async {
  final watch = Stopwatch()..start();
  Future<_CaseReport> infra(String text) async {
    watch.stop();
    final report = _CaseReport(
      c: c,
      state: _D8State.infraError,
      matched: const [],
      missing: List.of(c.expected),
      unexpected: const [],
      rowLines: const [],
      applyLines: const [],
      latencyMs: watch.elapsedMilliseconds,
      replyPreview: '',
      errorText: _flat(text),
    );
    log(_summarizeLine(c, report));
    return report;
  }

  try {
    final systemContext = await coordinator.buildSystemContext();
    if (systemContext == null) {
      return await infra('systemContext 构建失败（快照/协议异常，应用侧）');
    }
    final reply = await chat
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 's7-${c.id}',
              role: ConversationRole.user,
              text: c.prompt,
              createdAt: DateTime.now().toUtc(),
            ),
          ],
          onProgress: (_) {},
          systemContext: systemContext,
        )
        .join();
    watch.stop();
    final turn = coordinator.decode(reply);
    final state = _classify(turn);
    final matched = turn == null
        ? <String>[]
        : [
            for (final row in turn.rows)
              if (row.command != null) row.command!.spec.action,
          ];
    final missing = [
      for (final action in c.expected)
        if (!matched.contains(action)) action,
    ];
    final unexpected = [
      for (final action in matched)
        if (!c.expected.contains(action)) action,
    ];
    final rowLines = turn == null
        ? const <String>[]
        : [
            for (final row in turn.rows)
              row.command != null
                  ? '✅${row.command!.spec.action}'
                  : '❌${_flat(row.decodeError ?? '未知失败')}',
          ];
    var applyLines = const <String>[];
    if (turn != null) {
      final applied = await coordinator.applyProposed(turn);
      applyLines = [
        for (final row in applied.rows)
          row.status == ChatEditRowStatus.applied
              ? '✅落库'
              : '❌${_flat(row.resultMessage ?? row.decodeError ?? '失败')}',
      ];
    }
    final report = _CaseReport(
      c: c,
      state: state,
      matched: matched,
      missing: missing,
      unexpected: unexpected,
      rowLines: rowLines,
      applyLines: applyLines,
      latencyMs: watch.elapsedMilliseconds,
      replyPreview: _preview(reply, 240),
    );
    log(_summarizeLine(c, report));
    return report;
  } on AppFailure catch (error) {
    return infra('AppFailure ${error.runtimeType}: ${error.message}');
  }
}

String _summarizeLine(_Case c, _CaseReport report) {
  final expected = c.expected.isEmpty
      ? '（无：${c.kind == _CaseKind.outOfScope ? '范围外' : '不应改动'}）'
      : c.expected.join('+');
  return '[S7] ${c.id}(${c.kindLabel}) ${_d8Label(report.state)}'
      ' 期望=$expected'
      ' 命中=${report.matched.isEmpty ? '-' : report.matched.join('+')}'
      ' 缺失=${report.missing.isEmpty ? '-' : report.missing.join('+')}'
      ' 多余=${report.unexpected.isEmpty ? '-' : report.unexpected.join('+')}'
      ' ${report.latencyMs}ms'
      '${report.errorText == null ? '' : ' 故障=${report.errorText}'}';
}

String _verdict(_CaseReport report) {
  if (report.state == _D8State.infraError) return '⛔ 管线故障';
  if (report.c.kind == _CaseKind.outOfScope) {
    if (report.state == _D8State.plainText && report.unexpected.isEmpty) {
      return '✅ 边界正确（纯文本）';
    }
    if (report.state == _D8State.unknownAction) {
      return '❌ 对排除项编造未注册动作（模型侧违规）';
    }
    return '❌ 越权改动';
  }
  if (report.c.expected.isEmpty) {
    return report.unexpected.isEmpty
        ? '✅ 克制（未改动）'
        : '❌ 不该改的改了：${report.unexpected.join('+')}';
  }
  if (report.missing.isEmpty && report.unexpected.isEmpty) {
    return '✅ 全部识别';
  }
  if (report.missing.isEmpty) {
    return '⚠️ 识别但多做了：${report.unexpected.join('+')}';
  }
  if (report.state == _D8State.plainText) return '❌ 未出信封（纯文本）';
  return '❌ 未识别：${report.missing.join('+')}';
}

String _attribution(_CaseReport report) => switch (report.state) {
  _D8State.infraError => '应用侧（管线故障：${report.errorText ?? '未知'}）',
  _D8State.plainText => '模型侧（协议已注册、快照已给 id，模型未按协议出信封）',
  _D8State.unknownAction => '模型侧（编造了注册表外的 action）',
  _D8State.parsed => '模型侧（信封合法但该命令未出现或参数不合法——参数约束见行级明细）',
};

/// ───────────────────────── 覆盖表与报告（D8 ③） ─────────────────────────

String _buildMarkdown({
  required String base,
  required String model,
  required List<_CaseReport> reports,
  required List<String> registryActions,
}) {
  final buffer = StringBuffer();
  buffer
    ..writeln('# S7 AI 接管多条件实测（docs/31 需求 58 / 裁决 D8）')
    ..writeln()
    ..writeln('- 运行时间：${DateTime.now().toUtc().toIso8601String()}（UTC）')
    ..writeln('- 端点：`$base`　模型：`$model`（用户指定供应商；key 只走环境变量）')
    ..writeln(
      '- 用例数：${reports.length}；命令注册表 23 条'
      '（单一事实源 ChatEditCommandRegistry，协议由 renderProtocol 渲染）',
    )
    ..writeln();
  buffer
    ..writeln('## 一、三态汇总（D8 ②）')
    ..writeln()
    ..writeln('| 状态 | 条数 | 说明 |')
    ..writeln('|---|---|---|');
  for (final state in _D8State.values) {
    final count = reports.where((report) => report.state == state).length;
    final description = switch (state) {
      _D8State.parsed => '信封合法（含参数不合法的行，见行级明细）',
      _D8State.unknownAction => '模型编了未注册 action',
      _D8State.plainText => '模型只回话，没出信封',
      _D8State.infraError => '应用侧管线故障（必须为 0）',
    };
    buffer.writeln('| ${_d8Label(state)} | $count | $description |');
  }
  buffer.writeln();

  buffer
    ..writeln('## 二、逐用例明细')
    ..writeln()
    ..writeln('| 用例 | 类型 | 期望 | 三态 | 结论 | 行明细 | 落库明细 | 延迟 |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final report in reports) {
    final expected = report.c.expected.isEmpty
        ? '（无）'
        : report.c.expected.join('+');
    buffer.writeln(
      '| ${report.c.id} | ${report.c.kindLabel} | $expected '
      '| ${_d8Label(report.state)} | ${_verdict(report)} '
      '| ${report.rowLines.isEmpty ? '-' : report.rowLines.join('；')} '
      '| ${report.applyLines.isEmpty ? '-' : report.applyLines.join('；')} '
      '| ${report.latencyMs}ms |',
    );
    if (report.c.spec.note != null || report.errorText != null) {
      buffer.writeln(
        '| ┊ 备注 ┊ | | | | ${report.c.spec.note ?? ''} '
        '${report.errorText ?? ''} | | | |',
      );
    }
  }
  buffer.writeln();
  buffer
    ..writeln('## 三、23 命令 × 多条件覆盖表（D8 ③）')
    ..writeln()
    ..writeln('| 命令 | 期望它的用例 | 逐用例识别 | 结论 |')
    ..writeln('|---|---|---|---|');
  for (final action in registryActions) {
    final hits = reports
        .where((report) => report.c.expected.contains(action))
        .toList();
    final perCase = hits.isEmpty
        ? '（无）'
        : [
            for (final report in hits)
              '${report.c.id}:${report.matched.contains(action) ? '✅' : '❌'}',
          ].join(' ');
    final allHit =
        hits.isNotEmpty &&
        hits.every((report) => report.matched.contains(action));
    final conclusion = hits.isEmpty
        ? '❌ 矩阵缺口（应用侧，不许出现）'
        : allHit
        ? '✅ 识别'
        : '❌ 未识别 → 见第四节清单';
    buffer.writeln(
      '| `$action` | ${hits.map((r) => r.c.id).join('、')} | $perCase | $conclusion |',
    );
  }
  buffer.writeln();
  buffer.writeln(_unrecognizedSection(reports));
  buffer.writeln();
  buffer.writeln(_boundarySection(reports));
  buffer.writeln();
  buffer.writeln(_accountingSection(reports));
  return buffer.toString();
}

String _unrecognizedSection(List<_CaseReport> reports) {
  final buffer = StringBuffer()
    ..writeln('## 四、无法识别的指令清单（用户要的最终答案）')
    ..writeln()
    ..writeln(
      '范围外用例（E 组）不在此列——它们是 docs/23 §2 的设计内排除，'
      '单独见第五节边界表。',
    )
    ..writeln();
  var any = false;
  for (final report in reports) {
    if (report.missing.isEmpty || report.c.kind == _CaseKind.outOfScope) {
      continue;
    }
    any = true;
    buffer.writeln(
      '- **${report.c.id}**（${report.c.kindLabel}）期望 '
      '`${report.missing.join('+')}`：${_d8Label(report.state)}，'
      '归因=${_attribution(report)}；'
      '模型回复节选：${report.replyPreview.isEmpty ? '（空）' : report.replyPreview}',
    );
  }
  if (!any) {
    buffer.writeln('（无——所有范围内的多条件指令都被模型按协议识别。）');
  }
  return buffer.toString();
}

String _boundarySection(List<_CaseReport> reports) {
  final buffer = StringBuffer()
    ..writeln('## 五、边界用例：否定 / 模糊 / 范围外（「我们没实现」的对照）')
    ..writeln()
    ..writeln('| 用例 | 场景 | 期望 | 实际 | 备注 |')
    ..writeln('|---|---|---|---|---|');
  for (final report in reports) {
    final kind = report.c.kind;
    if (kind != _CaseKind.negation &&
        kind != _CaseKind.vague &&
        kind != _CaseKind.outOfScope) {
      continue;
    }
    final expectedText = report.c.expected.isEmpty
        ? '纯文本（不出信封）'
        : '只出 ${report.c.expected.join('+')}';
    buffer.writeln(
      '| ${report.c.id} | ${report.c.kindLabel} | $expectedText '
      '| ${_verdict(report)} | ${report.c.spec.note ?? ''} '
      '${report.errorText ?? ''} |',
    );
  }
  return buffer.toString();
}

String _accountingSection(List<_CaseReport> reports) {
  final inScopeMissed = reports
      .where(
        (report) =>
            report.c.kind != _CaseKind.outOfScope && report.missing.isNotEmpty,
      )
      .toList();
  final boundaryOk = reports
      .where(
        (report) =>
            report.c.kind == _CaseKind.outOfScope &&
            report.state == _D8State.plainText &&
            report.unexpected.isEmpty,
      )
      .toList();
  final boundaryViolated = reports
      .where(
        (report) =>
            report.c.kind == _CaseKind.outOfScope &&
            (report.state != _D8State.plainText ||
                report.unexpected.isNotEmpty),
      )
      .toList();
  final buffer = StringBuffer()
    ..writeln('## 六、「模型不行」vs「我们没实现」分账')
    ..writeln()
    ..writeln(
      '- **范围内未识别（模型侧）**：${inScopeMissed.length} 条用例——'
      '协议已注册全部 23 命令（骨架自检保证）、快照 id 已给出'
      '（骨架自检保证），模型没按协议产出对应命令。逐条见第四节。',
    )
    ..writeln(
      '- **设计内排除（应用侧「我们没实现」）**：E 组 3 条——'
      '凭据/训练计划创建/食物库删除按 docs/23 §2 有意不注册；'
      '其中模型老实纯文本回复 ${boundaryOk.length} 条'
      '（边界正确），对排除项编造动作或越权改动 ${boundaryViolated.length} 条'
      '（这部分算**模型侧违规**，不是「我们没实现」）。',
    )
    ..writeln(
      '- **应用侧管线故障**：'
      '${reports.where((report) => report.state == _D8State.infraError).length} 条'
      '（必须为 0，否则本表无效）。',
    );
  return buffer.toString();
}

/// ───────────────────────── 种子与装配 ─────────────────────────

final class _Seed {
  const _Seed({
    required this.today,
    required this.yesterday,
    required this.yesterdayLunchMealId,
    required this.todayLunchMealId,
    required this.dupSnackMealId,
    required this.eggItemId,
    required this.cucumberItemId,
    required this.waterId,
    required this.dishId,
    required this.venueMainId,
    required this.venueOldId,
    required this.windowId,
    required this.canteenDishKeepId,
    required this.canteenDishDropId,
    required this.planId,
  });

  final String today;
  final String yesterday;
  final String yesterdayLunchMealId;
  final String todayLunchMealId;
  final String dupSnackMealId;
  final String eggItemId;
  final String cucumberItemId;
  final String waterId;
  final String dishId;
  final String venueMainId;
  final String venueOldId;
  final String windowId;
  final String canteenDishKeepId;
  final String canteenDishDropId;
  final String planId;

  /// 快照里的带前缀行 id（与 DriftChatEditContextLoader 的渲染格式一致），
  /// 骨架自检用它验证「快照真的把 id 发给了模型」。
  Map<String, String> get taggedSnapshotIds => {
    '昨日午餐': '[meal:$yesterdayLunchMealId]',
    '今日午餐': '[meal:$todayLunchMealId]',
    '重复加餐': '[meal:$dupSnackMealId]',
    '鸡蛋条目': '[item:$eggItemId]',
    '黄瓜条目': '[item:$cucumberItemId]',
    '饮水记录': '[water:$waterId]',
    '菜品': '[dish:$dishId]',
    '主食堂': '[venue:$venueMainId]',
    '旧食堂': '[venue:$venueOldId]',
    '窗口': '[window:$windowId]',
    '食堂菜(保留)': '[canteen-dish:$canteenDishKeepId]',
    '食堂菜(删除)': '[canteen-dish:$canteenDishDropId]',
    '训练计划': '[wplan:$planId]',
  };
}

final class _Harness {
  _Harness({
    required this.database,
    required this.seed,
    required this.registry,
    required this.coordinator,
  });

  final AppDatabase database;
  final _Seed seed;
  final ChatEditCommandRegistry registry;
  final ChatEditCoordinator coordinator;

  Future<void> dispose() => database.close();
}

/// 种子 + 装配一份与 main.dart 同构的 chat-edit 管线（内存库，零外呼）。
/// 快照日期固定为本地 2026-10-07 12:00（UTC+8）——B15 的「9 月 1 日」、
/// D1 的「昨天」都相对它成立，与真实运行日期无关。
Future<_Harness> _buildHarness() async {
  final database = AppDatabase(NativeDatabase.memory());
  final ids = _LiveIds();
  final clock = FixedAppClock(DateTime.utc(2026, 10, 7, 4));
  final now = clock.nowUtc();
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'profile-live',
          activityLevel: 'moderate',
          createdAt: now,
          updatedAt: now,
        ),
      );
  // profile.goal.update 需要已有目标记录（执行器无目标时如实报「先建档」）。
  await database
      .into(database.goals)
      .insert(
        GoalsCompanion.insert(
          id: 'goal-live',
          profileId: 'profile-live',
          type: 'maintain',
          calorieMinKcal: 1500,
          calorieMaxKcal: 2200,
          effectiveFrom: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.exercises)
      .insert(
        ExercisesCompanion.insert(
          id: 'ex-live-squat',
          name: '深蹲',
          muscleGroup: '腿',
          equipment: '自重',
          source: 'builtin',
          createdAt: now,
          updatedAt: now,
        ),
      );
  final foods = FoodRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );
  final egg = await foods.create(
    const NewFood(
      name: '鸡蛋',
      kcalPer100g: 144,
      proteinPer100g: 13.3,
      carbsPer100g: 2.8,
      fatPer100g: 8.8,
    ),
  );
  final cucumber = await foods.create(
    const NewFood(
      name: '黄瓜',
      kcalPer100g: 15,
      proteinPer100g: 0.7,
      carbsPer100g: 2.9,
      fatPer100g: 0.2,
    ),
  );
  final rice = await foods.create(
    const NewFood(
      name: '米饭',
      kcalPer100g: 116,
      proteinPer100g: 2.6,
      carbsPer100g: 25.9,
      fatPer100g: 0.3,
    ),
  );
  final tomato = await foods.create(
    const NewFood(
      name: '番茄',
      kcalPer100g: 15,
      proteinPer100g: 0.9,
      carbsPer100g: 2.9,
      fatPer100g: 0.2,
    ),
  );
  final mealRepository = MealRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );
  final waterRepository = WaterRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );
  final dishLibraryRepository = DishLibraryRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );
  final canteenRepository = CanteenRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
    dishImageStore: DishImageStore(idGenerator: ids),
  );
  final workoutPlanRepository = WorkoutPlanRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );

  final exerciseRepository = ExerciseRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: clock,
  );
  final measurementRepository = MeasurementRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );
  final planningConstraintsRepository = PlanningConstraintsRepository(
    database: database,
    clock: clock,
  );
  final profileIdentityRepository = ProfileIdentityRepository(
    database: database,
  );

  final todayStr = formatLocalDate(clock.nowUtc());
  final yesterdayStr = formatLocalDate(
    clock.nowUtc().subtract(const Duration(days: 1)),
  );
  final yesterdayLunchMealId = await mealRepository.create(
    MealDraft(
      localDate: yesterdayStr,
      slot: MealSlot.lunch,
      notes: '食堂',
      items: [
        MealItemDraft.fromFood(tomato, 150),
        MealItemDraft.fromFood(egg, 60),
      ],
    ),
  );
  final todayLunchMealId = await mealRepository.create(
    MealDraft(
      localDate: todayStr,
      slot: MealSlot.lunch,
      items: [
        MealItemDraft.fromFood(egg, 60),
        MealItemDraft.fromFood(cucumber, 100),
        MealItemDraft.fromFood(rice, 200),
      ],
    ),
  );
  final dupSnackMealId = await mealRepository.create(
    MealDraft(
      localDate: todayStr,
      slot: MealSlot.snack,
      notes: '重复记录',
      items: [MealItemDraft.fromFood(egg, 50)],
    ),
  );
  final todayLunchFull = (await mealRepository.getById(todayLunchMealId))!;
  final water = await waterRepository.add(localDate: todayStr, amountMl: 200);
  final dish = await dishLibraryRepository.create(
    DishDraft(
      name: '红烧排骨',
      mealSlot: 'dinner',
      kcal: 320,
      proteinG: 18,
      carbsG: 12,
      fatG: 22,
      source: 'manual',
    ),
  );
  final venueMainId = await canteenRepository.createVenue(
    name: '东一食堂',
    campusName: '主校区',
  );
  final venueOldId = await canteenRepository.createVenue(
    name: '北苑食堂',
    campusName: '主校区',
  );
  final windowId = await canteenRepository.createWindow(
    venueId: venueMainId,
    name: '麻辣香锅',
    openTime: '10:30',
    closeTime: '14:00',
  );
  final canteenDishKeepId = await canteenRepository.createDish(
    windowId: windowId,
    name: '手撕包菜',
  );
  final canteenDishDropId = await canteenRepository.createDish(
    windowId: windowId,
    name: '凉皮',
  );
  final planId = await workoutPlanRepository.create(
    WorkoutPlanDraft(
      name: '居家徒手入门',
      days: [
        WorkoutPlanDayDraft(
          weekday: 1,
          entries: [
            PlannedExerciseDraft(
              exerciseId: 'ex-live-squat',
              targetSets: 3,
              targetReps: 12,
            ),
          ],
        ),
      ],
    ),
  );

  final registry = ChatEditCommandRegistry();
  final coordinator = ChatEditCoordinator(
    registry: registry,
    contextBuilder: DriftChatEditContextLoader(
      database: database,
      clock: clock,
      mealRepository: mealRepository,
      dishLibraryRepository: dishLibraryRepository,
      waterRepository: waterRepository,
      canteenRepository: canteenRepository,
      workoutPlanRepository: workoutPlanRepository,
      workoutSessionRepository: WorkoutSessionRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
    ),
    executor: RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: clock,
        foodRepository: foods,
        aiMemoryRepository: AiMemoryRepository(
          database: database,
          clock: clock,
          idGenerator: ids,
        ),
        mealRepository: mealRepository,
        dishLibraryRepository: dishLibraryRepository,
        waterRepository: waterRepository,
        measurementRepository: measurementRepository,
        planningConstraintsRepository: planningConstraintsRepository,
        canteenRepository: canteenRepository,
        workoutPlanRepository: workoutPlanRepository,
        exerciseRepository: exerciseRepository,
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        profileIdentityRepository: profileIdentityRepository,
        updateWaterTargetMl: UpdateWaterTargetMl(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        stepsRepository: StepsRepository(
          database: database,
          channel: StepsChannel(),
          idGenerator: ids,
          clock: clock,
        ),
        idGenerator: ids,
      ),
    ),
  );
  return _Harness(
    database: database,
    seed: _Seed(
      today: todayStr,
      yesterday: yesterdayStr,
      yesterdayLunchMealId: yesterdayLunchMealId,
      todayLunchMealId: todayLunchMealId,
      dupSnackMealId: dupSnackMealId,
      eggItemId: todayLunchFull.items
          .firstWhere((item) => item.foodName == '鸡蛋')
          .id,
      cucumberItemId: todayLunchFull.items
          .firstWhere((item) => item.foodName == '黄瓜')
          .id,
      waterId: water.id,
      dishId: dish.id,
      venueMainId: venueMainId,
      venueOldId: venueOldId,
      windowId: windowId,
      canteenDishKeepId: canteenDishKeepId,
      canteenDishDropId: canteenDishDropId,
      planId: planId,
    ),
    registry: registry,
    coordinator: coordinator,
  );
}

/// ───────────────────────── 小工具 ─────────────────────────

final class _LiveIds implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'live-id-${_value++}';
}

final class _FixedConfiguration implements AiProviderConfigurationReader {
  _FixedConfiguration({required this.baseUrl, required this.model});

  final String baseUrl;
  final String model;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      AiProviderConfiguration(
        baseUrl: baseUrl,
        model: model,
        protocol: AiProviderProtocol.chatCompletions,
        reasoning: AiReasoningMode.disabled,
      );
}

AiApiKeyStore _apiKeyStoreWith(String key) {
  final store = _MemorySecureStore()..values[AiApiKeyStore.storageKey] = key;
  return AiApiKeyStore(store: store);
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

String _flat(String text) => text.replaceAll('\n', ' ').replaceAll('|', '／');

String _preview(String text, int max) {
  final flat = _flat(text);
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}
