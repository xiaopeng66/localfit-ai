/// Prompt Catalog（docs/07 §4.1）。
///
/// 每个任务一个版本化 prompt 模板 + 任务卡披露事实（发送什么、不发送
/// 什么、目的地）。渲染时 `{key}` 占位符被替换；未注册的任务/版本拒绝。
library;

/// 任务卡披露事实。
class PromptDisclosure {
  const PromptDisclosure({
    required this.taskId,
    required this.promptVersion,
    required this.sendsWhat,
    required this.neverSends,
    required this.destinationHint,
  });

  final String taskId;
  final String promptVersion;
  final String sendsWhat;
  final String neverSends;
  final String destinationHint;
}

/// 版本化 prompt 模板。
class PromptTemplate {
  const PromptTemplate({
    required this.taskId,
    required this.promptVersion,
    required this.template,
    this.sendsWhat = '任务输入字段（见任务卡）',
    this.neverSends = '完整食物目录、健康档案明细、真实图片',
    this.destinationHint = '设置中的 BYOK AI 供应商主机',
  });

  final String taskId;
  final String promptVersion;
  final String template;
  final String sendsWhat;
  final String neverSends;
  final String destinationHint;
}

class PromptCatalogException implements Exception {
  const PromptCatalogException(this.message);

  final String message;

  @override
  String toString() => 'PromptCatalogException: $message';
}

final class PromptCatalog {
  final Map<String, PromptTemplate> _templates = {};

  void register(PromptTemplate template) {
    final key = '${template.taskId}#${template.promptVersion}';
    _templates[key] = template;
  }

  /// 渲染 prompt；`{key}` 替换为 values，未知占位符保留原样以便发现
  /// 模板笔误（测试覆盖）。
  ///
  /// 单趟扫描替换：值文本里再出现「{已知占位符}」不会被二次展开——
  /// 原先逐个 `replaceAll` 时，后替换的值若含前面占位符的字面量会被
  /// 意外展开（用户输入可控，属于值注入边角）。
  String render({
    required String taskId,
    required String promptVersion,
    required Map<String, String> values,
  }) {
    final template = _templates['$taskId#$promptVersion'];
    if (template == null) {
      throw PromptCatalogException(
        'no prompt template for $taskId#$promptVersion',
      );
    }
    // task_id / prompt_version 是模板内置事实，自动注入。
    final resolved = {
      'task_id': template.taskId,
      'prompt_version': template.promptVersion,
      ...values,
    };
    return template.template.replaceAllMapped(
      RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
      (match) => resolved[match.group(1)] ?? match.group(0)!,
    );
  }

  PromptDisclosure disclosureFor(String taskId) {
    // 同任务取最新注册的版本（Map 保序，后注册覆盖）。
    PromptTemplate? latest;
    for (final template in _templates.values) {
      if (template.taskId == taskId) latest = template;
    }
    if (latest == null) {
      throw PromptCatalogException('no prompt template for task $taskId');
    }
    return PromptDisclosure(
      taskId: latest.taskId,
      promptVersion: latest.promptVersion,
      sendsWhat: latest.sendsWhat,
      neverSends: latest.neverSends,
      destinationHint: latest.destinationHint,
    );
  }
}
