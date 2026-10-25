import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/core/errors/diagnostic_text.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/application/ranking.dart';

/// 搜索调试 / 模拟面板（docs/39 G21）。
///
/// 解决两个问题：
/// 1. **可解释**：一次检索为什么是这几条？显示关键词/扩展词/槽位、每一路的
///    命中数、候选总数、前几条分数；
/// 2. **可对比**：同一查询切 `BALANCED / KEYWORD_FIRST / SEMANTIC_FIRST`
///    三种模式，并排看首条与命中数（docs/39 §6 的 scoreMode 思路）。
///
/// 本面板是**只读诊断**：不写库、不改设置、不调 AI。
class RetrievalDebugPage extends StatefulWidget {
  const RetrievalDebugPage({
    super.key,
    required this.dishes,
    this.canteenDishes = const [],
    this.status,
    this.semantic,
    this.onClose,
  });

  /// 菜品库（由调用方读好传入；面板不查库）。
  final List<DishRecord> dishes;

  /// 食堂菜（含 tags，供标签路）。
  final List<CanteenDish> canteenDishes;

  /// 索引与后台任务状态（nullable：未接线时不渲染该段，不假装 0 条）。
  final RetrievalIndexStatus? status;

  /// 语义运行时（docs/39 §4–§5）：null＝未接线，面板如实显示不可用。
  final SemanticRuntime? semantic;
  final VoidCallback? onClose;

  @override
  State<RetrievalDebugPage> createState() => _RetrievalDebugPageState();
}

class _RetrievalDebugPageState extends State<RetrievalDebugPage> {
  final _query = TextEditingController(text: '想吃点清淡的汤');
  static const _service = DishSearchService();
  String _queryText = '想吃点清淡的汤';

  /// 语义路状态（面板的「看得见」部分）。
  List<String>? _semanticRanking;
  bool _semanticEnabled = true;
  bool _semanticAvailable = false;
  int _indexedDishes = 0;
  int _indexingDone = 0;
  int _indexingTotal = 0;
  String? _semanticNote;

  @override
  void initState() {
    super.initState();
    _semanticEnabled = widget.semantic?.settings != null;
    unawaited(_bootstrapSemantic());
  }

  /// 打开面板即补齐索引（有进度），再按当前查询算一次语义名次。
  ///
  /// **失败不报错**：模型缺失/加载失败时 `_semanticNote` 记原因、面板显示
  /// 「不可用」，检索照常走关键词 + 标签（docs/39 §4.3 的降级）。
  Future<void> _bootstrapSemantic() async {
    final runtime = widget.semantic;
    if (runtime == null) {
      if (mounted) setState(() => _semanticNote = '未接线');
      return;
    }
    final enabled = await runtime.enabled();
    if (mounted) setState(() => _semanticEnabled = enabled);
    try {
      final report = await runtime.indexDishes(
        widget.dishes,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _indexingDone = done;
              _indexingTotal = total;
            });
          }
        },
      );
      final indexed = await runtime.indexedCount();
      if (!mounted) return;
      setState(() {
        _indexedDishes = indexed;
        _semanticAvailable = true;
        _semanticNote =
            '索引 ${report.indexed} 新写 / ${report.skipped} 复用'
            '${report.removed == 0 ? '' : ' / ${report.removed} 清理'}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _semanticAvailable = false;
        _semanticNote = '$error';
      });
    }
    await _refreshSemantic();
  }

  Future<void> _refreshSemantic() async {
    final runtime = widget.semantic;
    if (runtime == null || !_semanticAvailable) return;
    final ranking = await runtime.rankDishes(_queryText, widget.dishes);
    if (!mounted) return;
    setState(() => _semanticRanking = ranking);
  }

  Future<void> _toggleSemantic(bool value) async {
    final runtime = widget.semantic;
    if (runtime == null) return;
    await runtime.setEnabled(value);
    if (!mounted) return;
    setState(() => _semanticEnabled = value);
    await _refreshSemantic();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _run(String value) {
    setState(() {
      _queryText = value;
      _semanticRanking = null;
    });
    unawaited(_refreshSemantic());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final balanced = _service.search(
      query: _queryText,
      dishes: widget.dishes,
      canteenDishes: widget.canteenDishes,
      semanticRanking: _semanticRanking,
      mode: RetrievalMode.balanced,
    );
    final keywordFirst = _service.search(
      query: _queryText,
      dishes: widget.dishes,
      canteenDishes: widget.canteenDishes,
      semanticRanking: _semanticRanking,
      mode: RetrievalMode.keywordFirst,
    );
    final semanticFirst = _service.search(
      query: _queryText,
      dishes: widget.dishes,
      canteenDishes: widget.canteenDishes,
      semanticRanking: _semanticRanking,
      mode: RetrievalMode.semanticFirst,
    );
    final debug = balanced.debug;
    return Scaffold(
      appBar: AppBar(
        title: Text('搜索调试', key: const Key('retrieval-debug-title')),
        leading: widget.onClose == null
            ? null
            : LfIconButton(
                key: const Key('retrieval-debug-close'),
                icon: Icons.close,
                semanticLabel: '关闭',
                onPressed: widget.onClose!,
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(LfDimens.pagePadding),
        children: [
          TextField(
            key: const Key('retrieval-debug-query'),
            controller: _query,
            decoration: const InputDecoration(
              labelText: '查询',
              hintText: '例：想吃点清淡的汤',
              border: OutlineInputBorder(),
            ),
            onChanged: _run,
            onSubmitted: _run,
          ),
          if (widget.semantic != null)
            DesignCard(
              key: const Key('retrieval-debug-semantic'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('语义检索', style: LfText.bodyStrong),
                      const Spacer(),
                      Switch(
                        key: const Key('retrieval-debug-semantic-toggle'),
                        value: _semanticEnabled,
                        onChanged: _toggleSemantic,
                      ),
                    ],
                  ),
                  Text(
                    _semanticAvailable
                        ? '可用 · 已索引 $_indexedDishes 条'
                              '${_indexingTotal == 0 ? '' : '（本次 $_indexingDone/$_indexingTotal）'}'
                        : '不可用（${_semanticNote ?? '加载中…'}）',
                    key: const Key('retrieval-debug-semantic-status'),
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                  if (_semanticNote != null && _semanticAvailable)
                    Text(
                      '本次索引：${_semanticNote!}',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  Text(
                    _semanticRanking == null
                        ? '本轮语义名次：未参与'
                        : '本轮语义名次：${_semanticRanking!.length} 条'
                              '${_semanticRanking!.isEmpty ? '' : '，首条 '
                                        '${_semanticRanking!.first}'}',
                    key: const Key('retrieval-debug-semantic-ranking'),
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                  // 降级原因（docs/43 A1「原因在调试面板可见」）。
                  if (_rankFailureReason() case final reason?)
                    Text(
                      '未参与原因：$reason',
                      key: const Key('retrieval-debug-semantic-reason'),
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                ],
              ),
            ),
          if (widget.status case final status?) ...[
            const SizedBox(height: LfDimens.spaceMedium),
            _section(
              c,
              '索引与后台任务',
              status.rows,
              key: const Key('retrieval-debug-index'),
            ),
          ],
          const SizedBox(height: LfDimens.spaceMedium),
          _section(c, '查询理解', [
            ('关键词', debug.keywords.join(' / ')),
            ('扩展词', debug.expanded.join('、')),
            ('槽位', debug.slots.join('、')),
            ('否定（只软惩罚）', debug.negations.join('、')),
            ('语义路', debug.semanticEnabled ? '开' : '关（索引未填充；32 档两门槛已过，待接线）'),
          ]),
          const SizedBox(height: LfDimens.spaceMedium),
          _section(c, '各路命中（BALANCED）', [
            ('关键词路', '${debug.routeHits['keyword']} 条'),
            ('标签路', '${debug.routeHits['tags']} 条'),
            ('语义路', '${debug.routeHits['semantic']} 条'),
            ('候选总数', '${debug.candidateCount}'),
          ]),
          const SizedBox(height: LfDimens.spaceMedium),
          DesignCard(
            key: const Key('retrieval-debug-modes'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('模式对比', style: LfText.bodyStrong),
                const SizedBox(height: LfDimens.spaceSmall),
                _modeRow(
                  c,
                  const Key('retrieval-debug-mode-balanced'),
                  'BALANCED',
                  _summary(balanced),
                ),
                _modeRow(
                  c,
                  const Key('retrieval-debug-mode-keyword'),
                  'KEYWORD_FIRST',
                  _summary(keywordFirst),
                ),
                _modeRow(
                  c,
                  const Key('retrieval-debug-mode-semantic'),
                  'SEMANTIC_FIRST',
                  _summary(semanticFirst),
                ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          DesignCard(
            key: const Key('retrieval-debug-results'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('前 5 条', style: LfText.bodyStrong),
                const SizedBox(height: LfDimens.spaceSmall),
                if (balanced.hits.isEmpty)
                  Text('（无命中：查询与现有菜名/标签都不匹配）')
                else
                  for (final hit in balanced.hits.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${hit.name} · ${hit.score.toStringAsFixed(4)}'
                        '${hit.reasons.isEmpty ? '' : '（${hit.reasons.join('+')}）'}',
                        key: Key('retrieval-debug-hit-${hit.id}'),
                        style: LfText.body.copyWith(color: c.cardForeground),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          LfTextButton(
            key: const Key('retrieval-debug-rerun'),
            label: '重新运行',
            icon: Icons.refresh,
            onPressed: () => _run(_query.text),
          ),
        ],
      ),
    );
  }

  /// 语义名次未参与时的原因（docs/43 A1：原因在调试面板可见）。
  String? _rankFailureReason() {
    if (_semanticRanking != null) return null;
    return widget.semantic?.lastRankError ?? _semanticNote;
  }

  String _summary(RetrievalResult result) {
    final first = result.hits.isEmpty ? '—' : result.hits.first.name;
    return '${result.hits.length} 条 · 首条 $first';
  }

  Widget _modeRow(LfSemanticColors c, Key key, String label, String summary) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '$label：$summary',
          key: key,
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
      );

  Widget _section(
    LfSemanticColors c,
    String title,
    List<(String, String)> rows, {
    Key? key,
  }) => DesignCard(
    key: key,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: LfText.bodyStrong),
        const SizedBox(height: LfDimens.spaceSmall),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$label：${value.isEmpty ? '—' : value}',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ),
      ],
    ),
  );
}

/// 索引与后台任务的一张快照（调试面板只读展示）。
final class RetrievalIndexStatus {
  const RetrievalIndexStatus({
    required this.indexedCount,
    required this.jobs,
    this.powerNote,
  });

  /// 派生索引表在**打开面板那一刻**的行数（不带 modelId 过滤的粗数）；
  /// 语义检索的实时条数见「语义检索」卡（索引写完后才准确）。
  final int indexedCount;
  final List<RetrievalJobLine> jobs;

  /// 调度条件的如实标注（docs/43 A3：实现 B「未接充电判定」）。
  final String? powerNote;

  /// 只报**后台任务**：向量条数由「语义检索」卡显示（那是索引写完之后读的
  /// 实时数字）。两处各说一次会打架——2026-10-19 设备实测：这一段是打开面板
  /// 那一刻的快照（0 条），而语义卡随后已写进 2 条。
  List<(String, String)> get rows => [
    if (powerNote case final note?) ('调度', note),
    if (jobs.isEmpty)
      ('后台任务', '无')
    else ...[
      for (final job in jobs)
        (
          '${job.type} · ${job.state}',
          job.lastError != null
              ? '失败：${sanitizeDiagnosticText(job.lastError!)}'
              : (job.progress == null ? '进度 —' : '进度 ${job.progress}%'),
        ),
    ],
  ];
}

/// 一行后台任务（`background_jobs` 的投影；不引用 drift 数据类）。
final class RetrievalJobLine {
  const RetrievalJobLine({
    required this.type,
    required this.state,
    this.progress,
    this.lastError,
  });

  final String type;
  final String state;
  final int? progress;
  final String? lastError;
}
