import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_hygiene.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_promotion.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';

/// 「我的 → AI 记忆」（docs/38 §4.6）。
///
/// 信任的三件套：**看得见**（列表 + 来源 + 时间）、**改得动**（编辑/置顶/删除）、
/// **关得掉**（对话时使用记忆的开关 + 一键清空 + 复制为文本导出）。
/// 页面不写任何「系统已按此安排」这类硬承诺——记忆是参考信息，不是事实源。
class AiMemoryPage extends StatefulWidget {
  const AiMemoryPage({
    super.key,
    required this.repository,
    this.onClose,
    this.constraintsRepository,
    this.pickAsOfDate,
    this.hygiene,
    this.extractionQueue,
    this.memoriesStream,
  });

  final AiMemoryRepository repository;
  final VoidCallback? onClose;

  /// 「转为忌口/偏好」晋升（docs/41 §5 G1）。null＝不渲染该动作
  /// （测试嵌入与旧调用点行为不变）。
  final PlanningConstraintsRepository? constraintsRepository;

  /// 「按日期回看」的日期选择（G23）。null＝系统日期选择器；
  /// 测试注入固定日期，避免依赖平台对话框。
  final Future<DateTime?> Function(BuildContext context)? pickAsOfDate;

  /// 整理建议（docs/43 B7）。null＝不渲染入口（未接线/无向量）。
  final MemoryHygiene? hygiene;

  /// 会话结束提炼的待确认队列（docs/43 B8）。null＝不渲染入口。
  final MemoryExtractionQueue? extractionQueue;

  /// 记忆流（测试注入用；null＝[AiMemoryRepository.watchActive]）。
  /// 存在的理由：错误态（RV-P1-12）要能构造一条会报错的流。
  final Stream<List<AiMemory>>? memoriesStream;

  @override
  State<AiMemoryPage> createState() => _AiMemoryPageState();
}

class _AiMemoryPageState extends State<AiMemoryPage> {
  static const int _pageSize = 50;

  String _query = '';
  late Future<bool> _injectionEnabled = widget.repository.injectionEnabled();

  /// 只在 init 时建一次。**不能在 build 里创建**：每次流发射都会触发重建，
  /// 重建又换一个新 stream ⇒ StreamBuilder 永远回到 waiting（转圈），
  /// 页面永不收敛（测试里表现为 pumpAndSettle 10 分钟超时）。
  late final Stream<List<AiMemory>> _memories =
      widget.memoriesStream ?? widget.repository.watchActive();

  // ── 分页（docs/43 B11）────────────────────────────────────────────────
  List<AiMemory> _page = const [];
  int _total = 0;
  String? _pageSignature;
  bool _loadingMore = false;

  // ── 待确认（docs/43 B8）──────────────────────────────────────────────
  late Future<int> _pendingCount = _loadPendingCount();

  /// 「结束会话自动提炼」开关（决策点 D2，2026-10-20 用户拍板「开」）：
  /// 开启后「结束本次会话」会发起真实 AI 调用。
  late Future<bool> _autoExtract =
      widget.extractionQueue?.enabled() ?? Future.value(false);

  Future<int> _loadPendingCount() async =>
      await widget.extractionQueue?.pendingCount() ?? 0;

  Future<void> _toggleAutoExtract(bool value) async {
    final queue = widget.extractionQueue;
    if (queue == null) return;
    // 开启前说明一次（docs/43 B8：开启前弹说明，不是静默改行为）。
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启会话结束自动提炼？'),
          content: const Text(
            '开启后，点对话页顶栏的「结束本次会话」会把这段对话发给你配置的 '
            'AI 模型做提炼（和聊天走同一条路、只发对话文本）。'
            '候选只进「待确认」，你确认后才会写进记忆。'
            'AI 未配置时会如实失败。',
          ),
          actions: [
            LfTextButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: '取消',
            ),
            LfTextButton(
              key: const Key('ai-memory-auto-extract-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              label: '开启',
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }
    await queue.setEnabled(value);
    if (!mounted) return;
    final next = Future.value(value);
    setState(() {
      _autoExtract = next;
    });
  }

  void _refreshPending() {
    if (!mounted) return;
    setState(() => _pendingCount = _loadPendingCount());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 记忆'),
        leading: widget.onClose == null
            ? null
            : LfIconButton(
                key: const Key('ai-memory-close'),
                icon: Icons.close,
                onPressed: widget.onClose,
                semanticLabel: '关闭',
              ),
        actions: [
          LfIconButton(
            key: const Key('ai-memory-add'),
            icon: Icons.add,
            onPressed: () => _showEditor(),
            semanticLabel: '添加记忆',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '记忆只保存在本机。对话时相关的几条会随提示词发给你配置的 AI 供应商'
              '（和对话内容走同一条路，不会发给别处）。过敏、目标、身体资料这类'
              '信息请用对话里的约束/目标命令，不要写在这里。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FutureBuilder<bool>(
            future: _injectionEnabled,
            builder: (context, snapshot) => SwitchListTile(
              key: const Key('ai-memory-injection-toggle'),
              value: snapshot.data ?? true,
              title: const Text('对话时使用记忆'),
              subtitle: const Text('关掉后记忆仍保留，只是不再随对话发送'),
              onChanged: snapshot.hasData
                  ? (value) async {
                      await widget.repository.setInjectionEnabled(value);
                      if (!mounted) return;
                      setState(() {
                        _injectionEnabled = Future.value(value);
                      });
                    }
                  : null,
            ),
          ),
          if (widget.extractionQueue != null) ...[
            // 「结束会话自动提炼」（决策点 D2）：默认关；开启前弹说明。
            FutureBuilder<bool>(
              future: _autoExtract,
              builder: (context, snapshot) => SwitchListTile(
                key: const Key('ai-memory-auto-extract-toggle'),
                value: snapshot.data ?? false,
                title: const Text('结束会话时自动提炼'),
                subtitle: const Text('开启后「结束本次会话」会调用 AI 提炼候选；确认才写入'),
                onChanged: snapshot.hasData
                    ? (value) => _toggleAutoExtract(value)
                    : null,
              ),
            ),
            FutureBuilder<int>(
              future: _pendingCount,
              builder: (context, snapshot) => ListTile(
                key: const Key('ai-memory-pending'),
                leading: const Icon(Icons.pending_actions_outlined),
                title: Text('待确认 ${snapshot.data ?? 0} 条'),
                subtitle: const Text('会话结束提炼的候选；保存才写入'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showPending,
              ),
            ),
          ],
          if (widget.hygiene != null)
            ListTile(
              key: const Key('ai-memory-hygiene'),
              leading: const Icon(Icons.auto_fix_high_outlined),
              title: const Text('整理建议'),
              subtitle: const Text('近义重复与长期未用；只建议，不自动改'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showHygiene,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('ai-memory-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索记忆',
                isDense: true,
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AiMemory>>(
              stream: _memories,
              builder: (context, snapshot) {
                // RV-P1-12：流报错时不能永久 spinner。
                if (snapshot.hasError) {
                  return const Center(child: AppErrorText('记忆加载失败，请重试。'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final usePaged = _query.isNotEmpty || all.length > _pageSize;
                if (!usePaged) {
                  final memories = _filter(all);
                  return Column(
                    children: [
                      _usageLine(all.length),
                      Expanded(child: _list(memories, all.length)),
                    ],
                  );
                }
                _maybeLoadPage(all);
                return Column(
                  children: [
                    _usageLine(all.length),
                    _totalLine(),
                    Expanded(child: _pagedList(all.length)),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  LfTextButton(
                    key: const Key('ai-memory-asof'),
                    onPressed: _showAsOf,
                    icon: Icons.history,
                    label: '按日期回看',
                  ),
                  LfTextButton(
                    key: const Key('ai-memory-copy-all'),
                    onPressed: _copyAll,
                    icon: Icons.copy_all,
                    label: '复制全部',
                  ),
                  const Spacer(),
                  LfDangerButton(
                    key: const Key('ai-memory-clear-all'),
                    onPressed: _clearAll,
                    icon: Icons.delete_sweep_outlined,
                    label: '清空记忆',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _page = const [];
      _total = 0;
      _pageSignature = null;
    });
  }

  List<AiMemory> _filter(List<AiMemory> all) => _query.isEmpty
      ? all
      : [
          for (final memory in all)
            if (memory.text.contains(_query) ||
                memory.tags.any((tag) => tag.contains(_query)))
              memory,
        ];

  /// 「已用 N / 2000（软顶）」+ 超软顶提示（docs/43 B5）。
  Widget _usageLine(int active) {
    final theme = Theme.of(context);
    final over = active > kAiMemorySoftCap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已用 $active / $kAiMemorySoftCap（软顶）',
            key: const Key('ai-memory-usage'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (over)
            Text(
              '已超过软顶，建议整理。',
              key: const Key('ai-memory-softcap-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalLine() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '共 $_total 条',
        key: const Key('ai-memory-total'),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );

  Widget _list(List<AiMemory> memories, int active) {
    if (memories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _query.isEmpty
                ? '还没有记忆。\n在对话里说「记住…」，或点右上角 + 添加。'
                : '没有匹配「$_query」的记忆。',
            key: const Key('ai-memory-empty'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      key: const Key('ai-memory-list'),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: memories.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _row(memories[index]),
    );
  }

  Widget _pagedList(int active) {
    if (_page.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final showMore = _page.length < _total;
    return ListView.separated(
      key: const Key('ai-memory-list'),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _page.length + (showMore ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= _page.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: LfTextButton(
                key: const Key('ai-memory-load-more'),
                label: _loadingMore ? '加载中…' : '加载更多',
                onPressed: _loadingMore ? null : _loadMore,
              ),
            ),
          );
        }
        return _row(_page[index]);
      },
    );
  }

  /// 分页数据只在「查询/数据版本」变化时重载（build 里不能直接 await）。
  void _maybeLoadPage(List<AiMemory> all) {
    final stamp = all.isEmpty
        ? ''
        : '${all.first.updatedAt.microsecondsSinceEpoch}:'
              '${all.last.updatedAt.microsecondsSinceEpoch}';
    final signature = '$_query|${all.length}|$stamp';
    if (signature == _pageSignature) return;
    _pageSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final page = await widget.repository.searchPage(
        query: _query,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted || _pageSignature != signature) return;
      setState(() {
        _page = page.items;
        _total = page.total;
      });
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final page = await widget.repository.searchPage(
      query: _query,
      offset: _page.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _page = [..._page, ...page.items];
      _total = page.total;
      _loadingMore = false;
    });
  }

  Widget _row(AiMemory memory) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('ai-memory-row-${memory.id}'),
      leading: Icon(
        memory.pinned ? Icons.push_pin : Icons.memory,
        color: memory.pinned
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(memory.text),
      subtitle: Text(
        '${memory.kind.label} · ${memory.domain.label} · '
        '${memory.sourceLabel} · ${_date(memory.updatedAt)}'
        // 时间语义（G23）：只给已闭合的条目加一句——开放中的
        // 「某日起」是噪声，改口后的失效日期才是事实。
        '${memory.isClosed ? ' · 有效期 ${memory.validityLabel}' : ''}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => _onAction(action, memory),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(
            value: 'pin',
            child: Text(memory.pinned ? '取消置顶' : '置顶'),
          ),
          if (widget.constraintsRepository != null)
            const PopupMenuItem(value: 'promote', child: Text('转为忌口/偏好')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _onAction(String action, AiMemory memory) async {
    switch (action) {
      case 'edit':
        await _showEditor(memory: memory);
      case 'promote':
        await _promoteToConstraint(memory);
      case 'pin':
        await widget.repository.setPinned(memory.id, !memory.pinned);
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除这条记忆？'),
            content: Text(memory.text),
            actions: [
              LfTextButton(
                onPressed: () => Navigator.of(context).pop(false),
                label: '取消',
              ),
              LfDangerButton(
                key: const Key('ai-memory-delete-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                label: '删除',
              ),
            ],
          ),
        );
        if (confirmed ?? false) {
          await widget.repository.delete(memory.id);
        }
    }
  }

  /// 「转为忌口/偏好」（G1）：把记忆晋升为硬约束（走 constraints.set 的
  /// 同一条写路径），成功后问一句「顺便删掉这条记忆？」——**不自动删**。
  Future<void> _promoteToConstraint(AiMemory memory) async {
    final repository = widget.constraintsRepository;
    if (repository == null) return;
    final MemoryPromotionResult result;
    try {
      final current = await repository.load();
      result = await promoteMemoryToConstraint(
        memory: memory,
        current: current.allergenAvoidances,
        persist: (next) => repository.save(
          PlanningConstraints(
            dietaryLabels: current.dietaryLabels,
            allergenAvoidances: next,
          ),
        ),
      );
    } on FormatException catch (error) {
      _snack(error.message);
      return;
    } on Object {
      _snack('晋升失败，请稍后重试。');
      return;
    }
    if (!mounted) return;
    _snack(result.message);
    if (result != MemoryPromotionResult.added) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('顺便删掉这条记忆？'),
        content: const Text(
          '它已经写进饮食约束（硬约束），记忆里再留一份是重复信息。'
          '不删也不影响约束生效。',
        ),
        actions: [
          LfTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            label: '保留',
          ),
          LfDangerButton(
            key: const Key('ai-memory-promote-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            label: '删掉',
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.repository.delete(memory.id);
    }
  }

  /// 「当时是什么」（G23）：选一天，列出那天成立的记忆。
  ///
  /// 用**当天 23:59:59（本地）**作为查询时刻：用户问的是「那一天」，
  /// 不是「那天零点的瞬间」——当天新建的记忆必须算进去。
  Future<void> _showAsOf() async {
    final picked =
        await (widget.pickAsOfDate?.call(context) ??
            showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              helpText: '回看哪一天？',
            ));
    if (picked == null || !mounted) return;
    final endOfDay = DateTime(
      picked.year,
      picked.month,
      picked.day,
      23,
      59,
      59,
    ).toUtc();
    final items = await widget.repository.listAsOf(endOfDay);
    if (!mounted) return;
    await AppSheet.show<void>(
      context,
      title:
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')} 那天记住的',
      content: SizedBox(
        key: const Key('ai-memory-asof-sheet'),
        width: double.infinity,
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('那天还没有任何记忆。'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final memory in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${memory.text}（${memory.kind.label} · '
                        '${memory.domain.label}'
                        '${memory.validityLabel == null ? '' : ' · ${memory.validityLabel}'}）',
                        key: Key('ai-memory-asof-row-${memory.id}'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// 整理建议（docs/43 B7）：只读扫描 → 弹层建议；用户点「合并/归档」才动。
  ///
  /// 合并走 B6 的既有语义：保留一条、把重复条 `supersede`（`validTo` 闭合、
  /// 历史仍可回看），不重写正文；归档 = `status='archived'`（不删除）。
  Future<void> _showHygiene() async {
    final service = widget.hygiene;
    if (service == null) return;
    final report = await service.scan();
    if (!mounted) return;
    final dismissed = <String>{};
    await AppSheet.show<void>(
      context,
      title: '整理建议',
      content: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final clusters = [
            for (final cluster in report.clusters)
              if (cluster.memories.any((m) => !dismissed.contains(m.id)))
                cluster,
          ];
          final stale = [
            for (final memory in report.stale)
              if (!dismissed.contains(memory.id)) memory,
          ];
          return SizedBox(
            key: const Key('ai-memory-hygiene-sheet'),
            width: double.infinity,
            child: clusters.isEmpty && stale.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('暂时没有整理建议。'),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (clusters.isNotEmpty) ...[
                          Text(
                            '可能重复（${clusters.length} 簇）',
                            style: Theme.of(sheetContext).textTheme.titleSmall,
                          ),
                          for (final cluster in clusters) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                '${cluster.domain.label} · 相似度 '
                                '${(cluster.maxSimilarity * 100).round()}%',
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .bodySmall,
                              ),
                            ),
                            for (var i = 0; i < cluster.memories.length; i++)
                              if (!dismissed.contains(cluster.memories[i].id))
                                _hygieneRow(
                                  sheetContext: sheetContext,
                                  setSheetState: setSheetState,
                                  dismissed: dismissed,
                                  memory: cluster.memories[i],
                                  mergeInto: i == 0
                                      ? null
                                      : cluster.memories.first,
                                ),
                          ],
                        ],
                        if (stale.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            '长期未用（${stale.length} 条）',
                            style: Theme.of(sheetContext).textTheme.titleSmall,
                          ),
                          for (final memory in stale)
                            _hygieneRow(
                              sheetContext: sheetContext,
                              setSheetState: setSheetState,
                              dismissed: dismissed,
                              memory: memory,
                            ),
                        ],
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _hygieneRow({
    required BuildContext sheetContext,
    required StateSetter setSheetState,
    required Set<String> dismissed,
    required AiMemory memory,
    AiMemory? mergeInto,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(memory.text),
          Wrap(
            spacing: 4,
            children: [
              if (mergeInto != null)
                LfTextButton(
                  key: Key('ai-memory-hygiene-merge-${memory.id}'),
                  label: '合并到「${mergeInto.text}」',
                  onPressed: () async {
                    await widget.repository.supersede(
                      oldId: memory.id,
                      newId: mergeInto.id,
                    );
                    setSheetState(() => dismissed.add(memory.id));
                  },
                ),
              LfTextButton(
                key: Key('ai-memory-hygiene-archive-${memory.id}'),
                label: '归档',
                onPressed: () async {
                  await widget.repository.archive(memory.id);
                  setSheetState(() => dismissed.add(memory.id));
                },
              ),
              LfTextButton(
                key: Key('ai-memory-hygiene-skip-${memory.id}'),
                label: '先不管',
                onPressed: () => setSheetState(() => dismissed.add(memory.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 待确认（docs/43 B8）：保存才写库（`source='extracted'`），忽略只移出 payload。
  Future<void> _showPending() async {
    final queue = widget.extractionQueue;
    if (queue == null) return;
    var remaining = await queue.pendingCandidates();
    if (!mounted) return;
    await AppSheet.show<void>(
      context,
      title: '待确认的记忆',
      content: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SizedBox(
            key: const Key('ai-memory-pending-sheet'),
            width: double.infinity,
            child: remaining.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('没有待确认的记忆。'),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < remaining.length; i++)
                          _pendingRow(
                            sheetContext: sheetContext,
                            setSheetState: setSheetState,
                            queue: queue,
                            item: remaining[i],
                            index: i,
                            onRemoved: () {
                              setSheetState(() => remaining.removeAt(i));
                            },
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
    _refreshPending();
  }

  Widget _pendingRow({
    required BuildContext sheetContext,
    required StateSetter setSheetState,
    required MemoryExtractionQueue queue,
    required PendingMemoryCandidate item,
    required int index,
    required VoidCallback onRemoved,
  }) {
    String? error;
    return StatefulBuilder(
      builder: (rowContext, setRowState) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.candidate.text),
            Text(
              '${item.candidate.kind.label} · ${item.candidate.domain.label}',
              style: Theme.of(rowContext).textTheme.bodySmall,
            ),
            if (error != null)
              Text(
                error!,
                key: Key('ai-memory-pending-error-$index'),
                style: TextStyle(color: Theme.of(rowContext).colorScheme.error),
              ),
            Row(
              children: [
                LfTextButton(
                  key: Key('ai-memory-pending-save-$index'),
                  label: '保存',
                  onPressed: () async {
                    try {
                      await queue.confirm(item);
                      onRemoved();
                    } on AiMemoryException catch (exception) {
                      setRowState(() => error = exception.message);
                    } on AiMemoryMergeSuggested catch (exception) {
                      setRowState(() => error = exception.message);
                    }
                  },
                ),
                LfTextButton(
                  key: Key('ai-memory-pending-ignore-$index'),
                  label: '忽略',
                  onPressed: () async {
                    await queue.ignore(item);
                    onRemoved();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAll() async {
    final memories = await widget.repository.listActive();
    if (memories.isEmpty) {
      _snack('还没有记忆可复制。');
      return;
    }
    final text = memories
        .map(
          (memory) =>
              '- [${memory.kind.label}/${memory.domain.label}] ${memory.text}',
        )
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _snack('已复制 ${memories.length} 条记忆为文本。');
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部记忆？'),
        content: const Text('这会删除本机保存的所有长期记忆，无法恢复。'),
        actions: [
          LfTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            label: '取消',
          ),
          LfDangerButton(
            key: const Key('ai-memory-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            label: '清空',
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await widget.repository.deleteAll();
  }

  Future<void> _showEditor({AiMemory? memory}) async {
    final textController = TextEditingController(text: memory?.text ?? '');
    var kind = memory?.kind ?? AiMemoryKind.preference;
    var domain = memory?.domain ?? AiMemoryDomain.general;
    var pinned = memory?.pinned ?? false;
    // 错误就地画在弹层里（而不是 SnackBar）：弹层挡住页面时，页面底部的
    // SnackBar 用户根本看不见；测试里也少一个 4s 计时器要等。
    String? errorText;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(memory == null ? '添加记忆' : '编辑记忆'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('ai-memory-editor-text'),
                  controller: textController,
                  autofocus: true,
                  maxLength: kAiMemoryMaxTextLength,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    hintText: '一句话，例如「周三晚上练腿」',
                  ),
                ),
                DropdownButtonFormField<AiMemoryKind>(
                  key: const Key('ai-memory-editor-kind'),
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: [
                    for (final value in AiMemoryKind.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => kind = value ?? kind),
                ),
                DropdownButtonFormField<AiMemoryDomain>(
                  key: const Key('ai-memory-editor-domain'),
                  initialValue: domain,
                  decoration: const InputDecoration(labelText: '领域'),
                  items: [
                    for (final value in AiMemoryDomain.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => domain = value ?? domain),
                ),
                SwitchListTile(
                  key: const Key('ai-memory-editor-pinned'),
                  contentPadding: EdgeInsets.zero,
                  value: pinned,
                  title: const Text('置顶'),
                  subtitle: const Text('置顶的记忆优先随对话发送'),
                  onChanged: (value) => setDialogState(() => pinned = value),
                ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorText!,
                      key: const Key('ai-memory-editor-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            LfTextButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: '取消',
            ),
            LfTextButton(
              key: const Key('ai-memory-editor-save'),
              onPressed: () async {
                try {
                  if (memory == null) {
                    await widget.repository.remember(
                      text: textController.text,
                      kind: kind,
                      domain: domain,
                      pinned: pinned,
                      source: 'manual',
                    );
                  } else {
                    await widget.repository.update(
                      memory.id,
                      text: textController.text,
                      kind: kind,
                      domain: domain,
                      pinned: pinned,
                    );
                  }
                  if (context.mounted) Navigator.of(context).pop(true);
                } on AiMemoryException catch (error) {
                  setDialogState(() => errorText = error.message);
                }
              },
              label: '保存',
            ),
          ],
        ),
      ),
    );
    // 不在 pop 之后立刻 dispose：对话框退场动画还在读这个控制器
    // （真实缺陷：测试里抛「A TextEditingController was used after being
    // disposed」，页面也跟着报错）。交给 GC，一个弹层一个控制器可接受。
    if (!(saved ?? false)) return;
    // 列表本身会随 Drift 变更流刷新，成功不再额外弹 SnackBar。
  }

  void _snack(String message) {
    if (!mounted) return;
    // RV4-P3-05：这是全仓唯一绕开统一出口的裸 `SnackBar`（不走主题、不带图标、
    // 不参与「替换式合并」）。改走 `AppSnackBar` 后底色/圆角/时长与其它提示一致。
    AppSnackBar.show(context, message, icon: AppSnackBar.infoIcon);
  }
}
