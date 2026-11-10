import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
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

  Future<int> _loadPendingCount() async =>
      await widget.extractionQueue?.pendingCount() ?? 0;

  /// 「规则」弹层（R-8）：原顶部四行长说明挪到这里，行内只留一句话。
  Future<void> _showRules() => AppSheet.show<void>(
    context,
    title: '记忆规则',
    content: const Text(
      '记忆只保存在本机。对话时相关的几条会随提示词发给你配置的 AI 供应商'
      '（和对话内容走同一条路，不会发给别处）。\n\n'
      '过敏、目标、身体资料这类信息请用对话里的约束/目标命令，不要写在这里'
      '——那些有专门的校验与生效日期。',
    ),
    actions: Builder(
      builder: (sheetContext) => Align(
        alignment: Alignment.centerRight,
        child: LfTextButton(
          onPressed: () => Navigator.of(sheetContext).pop(),
          label: '知道了',
        ),
      ),
    ),
  );

  void _refreshPending() {
    if (!mounted) return;
    setState(() {
      _pendingCount = _loadPendingCount();
    });
  }

  @override
  Widget build(BuildContext context) {
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
          // 【v2（design/round8/memory-v2.html，2026-10-30 用户批准实施）】
          // 说明行与四行设置卡从首屏撤下，全部收进 ⚙️ 弹层；首屏只留
          // 「统计一行 + 搜索 + 记忆列表」。搜索框常驻，不再放 🔍 图标
          // （那会是一枚点了没有新动作的按钮）。
          LfIconButton(
            key: const Key('ai-memory-settings'),
            icon: Icons.settings_outlined,
            onPressed: _showSettings,
            semanticLabel: '记忆设置',
          ),
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
                      _statsRow(all.length, total: null),
                      _searchField(),
                      Expanded(child: _list(memories)),
                    ],
                  );
                }
                _maybeLoadPage(all);
                return Column(
                  children: [
                    _statsRow(all.length, total: _total),
                    _searchField(),
                    Expanded(child: _pagedList()),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: LfDimens.spaceSmall,
                runSpacing: LfDimens.spaceXSmall,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                  // 【v2】「清空记忆」从常驻底栏挪进 ⚙️ 设置弹层：
                  // 破坏性动作离开首屏、远离误触；行为与二次确认不变。
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索框（v2：胶囊形、常驻列表头）。
  Widget _searchField() {
    final c = context.lf;
    final radius = BorderRadius.circular(LfDimens.radiusFull);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: TextField(
        key: const Key('ai-memory-search'),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: '搜索记忆',
          isDense: true,
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: c.border),
          ),
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }

  /// ⚙️ 记忆设置弹层（v2）：两枚开关 + 待确认 + 整理建议 + 规则 + 复制 +
  /// 清空。行内不再带长副标题——开关语义自明，说明按需出现在各自的弹层。
  Future<void> _showSettings() async {
    await AppSheet.show<void>(
      context,
      title: '记忆设置',
      content: _MemorySettingsSheet(
        repository: widget.repository,
        extractionQueue: widget.extractionQueue,
        hygieneAvailable: widget.hygiene != null,
        loadPendingCount: _loadPendingCount,
        onRules: _showRules,
        onPending: _showPending,
        onHygiene: _showHygiene,
        onCopyAll: _copyAll,
        onClearAll: _clearAll,
      ),
    );
    _refreshPending();
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

  /// 列表头统计行（v2）：条目/额度；待确认单独一张整宽入口（0 条自动隐藏）。
  ///
  /// 【2026-11-02 用户：待确认入口和弹窗都很丑】原来它是一枚挤在
  /// `总条数 / 已用额度` 后面的小胶囊：3 个元素争一行，320×2.0 时要折行，
  /// 而且胶囊比列表卡轻得多，看不出「这里有一批东西等你决定」。现在拆成
  /// 统计行（纯数字）+ 整宽入口卡（图标 / 标题 / 一句后果 / chevron），
  /// 入口本身就是可点的卡，不再靠一枚小标签抢注意力。
  Widget _statsRow(int active, {required int? total}) {
    final theme = Theme.of(context);
    final over = active > kAiMemorySoftCap;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 【R-8 实帧修正（320×2.0）】两端文案加起来超宽会溢出 78px——
          // Wrap 折行（usage 挪到下一行），不裁不缩。
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: LfDimens.spaceSmall,
            runSpacing: LfDimens.spaceXSmall,
            children: [
              if (total != null)
                Text(
                  '共 $total 条',
                  key: const Key('ai-memory-total'),
                  style: muted,
                ),
              Text(
                '已用 $active / $kAiMemorySoftCap',
                key: const Key('ai-memory-usage'),
                style: muted,
              ),
            ],
          ),
          if (over)
            Text(
              '已超过软顶，建议整理。',
              key: const Key('ai-memory-softcap-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (widget.extractionQueue != null)
            FutureBuilder<int>(
              future: _pendingCount,
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                if (count <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
                  child: _pendingEntry(count),
                );
              },
            ),
        ],
      ),
    );
  }

  /// 待确认入口（整宽卡）：把「有几条 / 确认后才写入 / 点进去处理」一次讲清。
  Widget _pendingEntry(int count) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return DesignCard(
      key: const Key('ai-memory-pending'),
      onTap: _showPending,
      semanticLabel: '待确认 $count 条记忆',
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceMedium,
        vertical: LfDimens.spaceSmallPlus,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LfColors.mint(brightness).tone(100),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inbox_outlined,
              size: LfDimens.iconMd,
              color: LfColors.mintText(brightness),
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmallPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '待确认 $count 条',
                  style: LfText.bodyStrong.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '确认后才会写入记忆',
                  style: LfText.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _list(List<AiMemory> memories) {
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
    final rows = _query.isEmpty ? _groupedRows(memories) : _flatRows(memories);
    return ListView.builder(
      key: const Key('ai-memory-list'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  Widget _pagedList() {
    if (_page.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final showMore = _page.length < _total;
    final rows = <Widget>[
      ...(_query.isEmpty ? _groupedRows(_page) : _flatRows(_page)),
    ];
    if (showMore) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: LfTextButton(
              key: const Key('ai-memory-load-more'),
              label: _loadingMore ? '加载中…' : '加载更多',
              onPressed: _loadingMore ? null : _loadMore,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('ai-memory-list'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
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

  /// 平铺行（搜索态）：结果之间只留间距。
  List<Widget> _flatRows(List<AiMemory> memories) => [
    for (var i = 0; i < memories.length; i++) ...[
      if (i > 0) const SizedBox(height: LfDimens.spaceSmall),
      _row(memories[i]),
    ],
  ];

  /// 分组行（v2）：置顶组最上，其余按领域（enum 声明序）；组内保持流序
  /// （置顶优先、更新时间降序）。搜索时退化为 [_flatRows]。
  List<Widget> _groupedRows(List<AiMemory> memories) {
    final pinned = [
      for (final memory in memories)
        if (memory.pinned) memory,
    ];
    final groups = <AiMemoryDomain, List<AiMemory>>{};
    for (final memory in memories) {
      if (memory.pinned) continue;
      groups.putIfAbsent(memory.domain, () => []).add(memory);
    }
    final rows = <Widget>[];
    void addGroup(String label, List<AiMemory> items) {
      if (items.isEmpty) return;
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: LfDimens.spaceSmall));
      }
      rows.add(_MemoryGroupHeader(label: label, count: items.length));
      for (final memory in items) {
        rows.add(const SizedBox(height: 6));
        rows.add(_row(memory));
      }
    }

    addGroup('置顶', pinned);
    for (final domain in AiMemoryDomain.values) {
      addGroup(domain.label, groups[domain] ?? const []);
    }
    return rows;
  }

  /// 单条记忆卡（v2）：类型色标 + 置顶针 + ⋮ 菜单；正文 + 一行来源。
  /// 全部 key / 行为不变（编辑 / 置顶 / 转为忌口 / 删除都在 ⋮ 里）。
  Widget _row(AiMemory memory) {
    final c = context.lf;
    return DesignCard(
      key: Key('ai-memory-row-${memory.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MemoryKindTag(kind: memory.kind),
              if (memory.pinned) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.push_pin,
                  size: 12,
                  color: LfColors.mintText(Theme.of(context).brightness),
                ),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (action) => _onAction(action, memory),
                icon: Icon(Icons.more_vert, size: 18, color: c.mutedForeground),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(memory.pinned ? '取消置顶' : '置顶'),
                  ),
                  if (widget.constraintsRepository != null)
                    const PopupMenuItem(
                      value: 'promote',
                      child: Text('转为忌口/偏好'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _highlightedText(memory.text),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${memory.domain.label} · ${memory.sourceLabel} · '
              '${_date(memory.updatedAt)}'
              // 时间语义（G23）：只给已闭合的条目加一句——开放中的
              // 「某日起」是噪声，改口后的失效日期才是事实。
              '${memory.isClosed ? ' · 有效期 ${memory.validityLabel}' : ''}',
              style: LfText.micro.copyWith(color: c.mutedForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索命中高亮（v2）：命中片段垫一层 `brandSoft` 底色。
  Widget _highlightedText(String text) {
    final c = context.lf;
    final base = LfText.body.copyWith(color: c.foreground);
    if (_query.isEmpty || !text.contains(_query)) {
      return Text(text, style: base);
    }
    final spans = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      final index = text.indexOf(_query, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: _query,
          style: TextStyle(
            backgroundColor: LfColors.brandSoft(Theme.of(context).brightness),
          ),
        ),
      );
      start = index + _query.length;
    }
    return Text.rich(TextSpan(children: spans), style: base);
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
                ? _pendingEmptyState(sheetContext)
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < remaining.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i == remaining.length - 1
                                  ? 0
                                  : LfDimens.spaceSmall,
                            ),
                            child: _pendingRow(
                              sheetContext: sheetContext,
                              setSheetState: setSheetState,
                              queue: queue,
                              item: remaining[i],
                              index: i,
                              onRemoved: () {
                                setSheetState(() => remaining.removeAt(i));
                              },
                            ),
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

  /// 候选清空后的收尾态：不用一句裸露的「没有」，给一个完成符号。
  Widget _pendingEmptyState(BuildContext sheetContext) {
    final c = sheetContext.lf;
    final brightness = Theme.of(sheetContext).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceLarge),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LfColors.mint(brightness).tone(100),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.done_all, color: LfColors.mintText(brightness)),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            '没有待确认的记忆。',
            style: LfText.body.copyWith(color: c.cardForeground),
          ),
        ],
      ),
    );
  }

  /// 一条候选卡（v3）：标签 / 原文 / 就地错误 / 「忽略 · 保存」。
  ///
  /// 【2026-11-02 用户：弹窗布局很丑】旧版是裸文本 + 小字元信息 + 两个
  /// 左对齐文字按钮，条目之间没有边界；多条候选会糊成一段。现在一条候选
  /// 一张卡：类型/领域做徽标，原文是主体，操作固定在右下，错误留在卡内
  /// （弹层挡住页面时，SnackBar 在底部看不见）。
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
      builder: (rowContext, setRowState) {
        final c = rowContext.lf;
        return MutedBlock(
          key: Key('ai-memory-pending-card-$index'),
          padding: const EdgeInsets.all(LfDimens.spaceMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: LfDimens.spaceXSmall,
                runSpacing: LfDimens.spaceXSmall,
                children: [
                  LfBadge.mint(item.candidate.kind.label),
                  LfBadge.neutral(item.candidate.domain.label),
                ],
              ),
              const SizedBox(height: LfDimens.spaceSmall),
              Text(
                item.candidate.text,
                style: LfText.body.copyWith(color: c.cardForeground),
              ),
              if (error != null) ...[
                const SizedBox(height: LfDimens.spaceSmall),
                Text(
                  error!,
                  key: Key('ai-memory-pending-error-$index'),
                  style: LfText.bodySmall.copyWith(color: c.errorText),
                ),
              ],
              const SizedBox(height: LfDimens.spaceSmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LfTextButton(
                    key: Key('ai-memory-pending-ignore-$index'),
                    label: '忽略',
                    onPressed: () async {
                      await queue.ignore(item);
                      onRemoved();
                    },
                  ),
                  const SizedBox(width: LfDimens.spaceXSmall),
                  LfPillButton(
                    key: Key('ai-memory-pending-save-$index'),
                    label: '保存',
                    icon: Icons.check,
                    tone: LfPillTone.solid,
                    height: LfDimens.minTouchTarget,
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
                ],
              ),
            ],
          ),
        );
      },
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
                // 16a（2026-10-25 用户：记忆弹窗里这两件贴在一起）：类型与领域
                // 原来**零间距**直接相邻（`kind.bottom == domain.top`），两个
                // 描边方框连成一块，读起来像一个控件的两半。插一个
                // `spaceSmallPlus`(10) 让它们各自成立。
                const SizedBox(height: LfDimens.spaceSmallPlus),
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

/// 分组小标题（v2）：类型色点 + 领域名 + 条数。
class _MemoryGroupHeader extends StatelessWidget {
  const _MemoryGroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: LfColors.mint(brightness).tone(500),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: LfText.caption.copyWith(
              color: c.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $count',
            style: LfText.micro.copyWith(color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// 记忆类型色标（v2）：偏好 mint / 习惯 蓝 / 事实 灰 / 近况 琥珀。
///
/// 取色全部来自既有 token（brandSoft/mintText、info、muted/mutedForeground、
/// carbs100/warningText），不新增色值。
class _MemoryKindTag extends StatelessWidget {
  const _MemoryKindTag({required this.kind});

  final AiMemoryKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final (bg, fg) = switch (kind) {
      AiMemoryKind.preference => (
        LfColors.brandSoft(brightness),
        LfColors.mintText(brightness),
      ),
      AiMemoryKind.habit => (c.info.withValues(alpha: 0.14), c.cardForeground),
      AiMemoryKind.fact => (c.muted, c.mutedForeground),
      AiMemoryKind.context => (c.carbs100, c.warningText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kind.label,
        style: LfText.micro.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// ⚙️ 记忆设置弹层体（v2）：开关 + 待确认 + 整理建议 + 规则 + 复制 + 清空。
///
/// 开关在弹层内自己持有 Future 状态（页面只负责在弹层关闭后刷新待确认数）；
/// 其余行先关弹层再执行动作（各自的弹层从页面 context 弹出，避免叠两层弹层）。
class _MemorySettingsSheet extends StatefulWidget {
  const _MemorySettingsSheet({
    required this.repository,
    required this.extractionQueue,
    required this.hygieneAvailable,
    required this.loadPendingCount,
    required this.onRules,
    required this.onPending,
    required this.onHygiene,
    required this.onCopyAll,
    required this.onClearAll,
  });

  final AiMemoryRepository repository;
  final MemoryExtractionQueue? extractionQueue;
  final bool hygieneAvailable;
  final Future<int> Function() loadPendingCount;
  final VoidCallback onRules;
  final VoidCallback onPending;
  final VoidCallback onHygiene;
  final VoidCallback onCopyAll;
  final VoidCallback onClearAll;

  @override
  State<_MemorySettingsSheet> createState() => _MemorySettingsSheetState();
}

class _MemorySettingsSheetState extends State<_MemorySettingsSheet> {
  late Future<bool> _injection = widget.repository.injectionEnabled();
  late Future<bool> _autoExtract =
      widget.extractionQueue?.enabled() ?? Future.value(false);
  late final Future<int> _pending = widget.loadPendingCount();

  Future<void> _toggleInjection(bool value) async {
    await widget.repository.setInjectionEnabled(value);
    if (!mounted) return;
    setState(() {
      _injection = Future.value(value);
    });
  }

  /// 「结束会话自动提炼」（决策点 D2）：开启前说明一次，不静默改行为。
  Future<void> _toggleAutoExtract(bool value) async {
    final queue = widget.extractionQueue;
    if (queue == null) return;
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
    setState(() {
      _autoExtract = Future.value(value);
    });
  }

  /// 先关本弹层，下一帧再执行动作（动作自己的弹层不会叠在设置弹层上）。
  void _runAfterClose(VoidCallback action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return SizedBox(
      key: const Key('ai-memory-settings-sheet'),
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder<bool>(
            future: _injection,
            builder: (context, snapshot) => SwitchListTile(
              key: const Key('ai-memory-injection-toggle'),
              contentPadding: EdgeInsets.zero,
              value: snapshot.data ?? true,
              title: const Text('对话时使用记忆'),
              onChanged: snapshot.hasData ? _toggleInjection : null,
            ),
          ),
          if (widget.extractionQueue != null) ...[
            FutureBuilder<bool>(
              future: _autoExtract,
              builder: (context, snapshot) => SwitchListTile(
                key: const Key('ai-memory-auto-extract-toggle'),
                contentPadding: EdgeInsets.zero,
                value: snapshot.data ?? false,
                title: const Text('结束会话时自动提炼'),
                onChanged: snapshot.hasData ? _toggleAutoExtract : null,
              ),
            ),
            FutureBuilder<int>(
              future: _pending,
              builder: (context, snapshot) => ListTile(
                key: const Key('ai-memory-pending-row'),
                contentPadding: EdgeInsets.zero,
                title: const Text('待确认候选'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${snapshot.data ?? 0}',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
                onTap: () => _runAfterClose(widget.onPending),
              ),
            ),
          ],
          if (widget.hygieneAvailable)
            ListTile(
              key: const Key('ai-memory-hygiene'),
              contentPadding: EdgeInsets.zero,
              title: const Text('整理建议'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _runAfterClose(widget.onHygiene),
            ),
          ListTile(
            key: const Key('ai-memory-rules'),
            contentPadding: EdgeInsets.zero,
            title: const Text('查看规则'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _runAfterClose(widget.onRules),
          ),
          ListTile(
            key: const Key('ai-memory-copy-all-sheet'),
            contentPadding: EdgeInsets.zero,
            title: const Text('复制全部文本'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _runAfterClose(widget.onCopyAll),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: LfDangerButton(
              key: const Key('ai-memory-clear-all'),
              label: '清空全部记忆',
              icon: Icons.delete_sweep_outlined,
              onPressed: () => _runAfterClose(widget.onClearAll),
            ),
          ),
        ],
      ),
    );
  }
}
