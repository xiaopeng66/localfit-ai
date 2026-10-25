import 'package:flutter/material.dart';
import 'package:localfit_ai/features/ai_workbench/presentation/ai_starter_gallery.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_starter.dart';

/// AI 创作画廊（docs/32 §4 T6a/T6c；原 docs/21 §3.5 的「宫格→详情」两层结构）。
///
/// 【T6c 后本页只剩画廊与描述框】旧详情层（`AiTaskCard` 的「卡内生成 →
/// 草案 → 本地校验 → 独立确认写入」）已随执行管线退役：生成改在 AI 对话里
/// 发生（D5），写库统一走 chat-edit 命令层（编辑卡「全部应用」）。
/// 卡片 Key（`ai-workbench-task-<id>`）与分组标题沿用。
///
/// `initialTaskId` 深链**直接打开该卡的描述框**
/// （入口不再白屏，用户少点一次）。
class AiWorkbenchPage extends StatefulWidget {
  const AiWorkbenchPage({
    super.key,
    this.initialTaskId,
    this.onGenerate,
    this.starters = aiStarters,
  });

  /// 画廊渲染的启动卡（docs/32 §4 T6c：默认即 `aiStarters` 六张卡；
  /// 测试可注入精简集合）。
  final List<AiStarter> starters;

  /// 「生成」按钮的回执（docs/32 §4 T6a / D5）：拿到拼好的启动提示词。
  /// T6b 把它接到「切对话分支 + 自动发送」；不接线时（如既有测试）
  /// 只走回执，不产生副作用。
  final ValueChanged<String>? onGenerate;

  /// 深链：直接打开某个任务的**描述框**（跳过宫格）。
  ///
  /// 两个真实入口用它：拍照识餐页「打开 AI 训练计划」（`?task=workout-plan`）、
  /// 食堂页「AI 分析这些菜品」（`?task=dish-nutrition`）。
  /// 该 id 不存在时回落到宫格（入口失效不该是白屏）。
  final String? initialTaskId;

  @override
  State<AiWorkbenchPage> createState() => _AiWorkbenchPageState();
}

class _AiWorkbenchPageState extends State<AiWorkbenchPage> {
  late String? _openTaskId = widget.initialTaskId;

  @override
  Widget build(BuildContext context) {
    final starters = widget.starters;
    // docs/32 §4 T6c：深链改为「打开该卡的描述框」——不再有详情分支。
    // 首帧后开（不能在 build 里 show 弹层）。
    final target = _openTaskId;
    if (target != null) {
      _openTaskId = null;
      final starter = starters.where((s) => s.id == target).firstOrNull;
      if (starter != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AiStarterSheet.show(
            context,
            starter: starter,
            onGenerate: widget.onGenerate,
          );
        });
      }
    }
    return AiStarterGallery(starters: starters, onGenerate: widget.onGenerate);
  }
}

/// 分组画廊（docs/32 §4 T6a / §3 D5）。
///
/// 两张分组卡列表（饮食 / 训练与搭配），每张卡：图标 + 标题 + 既有描述 +
/// 「描述需求」引导；点击 → [AiStarterSheet] 描述框；生成 → [onGenerate]
/// 回执拼好的启动提示词。
