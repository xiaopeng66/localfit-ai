/// 降级矩阵（docs/41 §10 G10）：**每格都有判据、所有降级如实标注**。
///
/// 四列功能 × 五行状态；本文件是**单一事实源**——矩阵里每一格的
/// 行为说明与界面文案都从这里取，页面不许各写一份（写两份就会漂，
/// 「如实标注」最怕的就是文案先漂）。
///
/// P1 阶段的实际可判据范围：端上模型与向量索引在 P3 才落地，那两行的
/// 「搜索/推荐」格在 P1 恒为「关键词路径 + 如实提示」（见 [degradationNote]
/// 对 `_onDeviceModelUnavailable` / `_indexBuilding` 的返回）；测试把这些
/// 格钉成常量，P3 落地时改这里一处即可。
enum DegradationRow {
  /// AI 未配置（供应商/Key/模型三缺一）。
  aiNotConfigured('AI 未配置'),

  /// 无网（探针/请求层连接失败）。
  offline('无网络'),

  /// 对话模型不可用（配置了但请求失败）。
  chatModelUnavailable('对话模型不可用'),

  /// 端上嵌入模型不可用/未装（P3 起才有语义路径）。
  onDeviceModelUnavailable('端上模型不可用'),

  /// 语义索引未建/重建中（P3 起才有索引）。
  indexBuilding('索引重建中');

  const DegradationRow(this.label);
  final String label;
}

enum DegradationColumn {
  memoryInjection('记忆注入'),
  dishRecommendation('菜品推荐/短名单'),
  search('搜索'),
  mealLogging('记餐');

  const DegradationColumn(this.label);
  final String label;
}

/// 一格降级矩阵：行为 + 给用户看的一句话。
final class DegradationCell {
  const DegradationCell({required this.behavior, required this.notice});

  /// 这格在降级状态下的实际行为（判据写进测试）。
  final String behavior;

  /// 界面上如实显示的提示；空串 = 不需要额外提示（该格本就是全功能）。
  final String notice;

  /// 判据常量：语义路径可用的格子（P3 起才出现）。
  static const semanticAvailableNotice = '';
}

/// 记忆注入列：任何降级状态下都是「置顶 + 关键词排序」的本地路径，
/// 区别只在提示（AI 未配置时对话本身不可用，提示由对话页给）。
const _memoryLocal = DegradationCell(
  behavior: '置顶优先 + 关键词/标签排序（本地），语义路径不可用',
  notice: '（记忆按置顶与关键词匹配注入，本次不使用语义排序）',
);

/// 菜品推荐列：本地标签 + 规则（无 AI 文案/解释）。
const _dishLocal = DegradationCell(
  behavior: '本地标签 + 规则（无 AI 文案/解释）',
  notice: '（推荐来自本地标签与规则，AI 解释暂不可用）',
);

/// 搜索列：关键词 + 标签兜底。
const _searchKeyword = DegradationCell(
  behavior: '关键词 + 标签（本地索引可用时含语义；见行覆盖）',
  notice: '',
);

/// 记忆注入列（断网）：语义打分在端上，断网不影响；只是 AI 对话本身不可用。
const _memoryLocalOnline = DegradationCell(
  behavior: '置顶优先 + 关键词/标签；端上语义可用时照常参与（不需要网络）',
  notice: '',
);

/// 搜索列（断网）：本地索引与端上向量都不依赖网络 ⇒ 全功能，不标注降级。
const _searchLocalSemantic = DegradationCell(
  behavior: '关键词 + 标签 + 端上语义（全部本地，不需要网络）',
  notice: '',
);

/// 记餐列：**任何状态下都正常**（D10 手动营养兜底后记餐永不降级）。
const _mealNormal = DegradationCell(
  // 2026-10-21 RV-P2-09：`origin=user_input` 是**食堂营养证据表**的列，
  // `meal_items` 没有 origin 列；原句把两件事混成一件。
  behavior: '正常（D10 手动营养兜底；手填值记在食堂营养证据，origin=user_input）',
  notice: '',
);

/// 矩阵本体（docs/41 §10 逐格誊写；改一行必须同步 docs/41）。
const Map<DegradationRow, Map<DegradationColumn, DegradationCell>>
kDegradationMatrix = {
  DegradationRow.aiNotConfigured: {
    DegradationColumn.memoryInjection: _memoryLocal,
    DegradationColumn.dishRecommendation: _dishLocal,
    DegradationColumn.search: _searchKeyword,
    DegradationColumn.mealLogging: _mealNormal,
  },
  DegradationRow.offline: {
    // 2026-10-21 裁决 D-2：本地语义不需要网络，断网时搜索**不降级**。
    DegradationColumn.memoryInjection: _memoryLocalOnline,
    DegradationColumn.dishRecommendation: _dishLocal,
    DegradationColumn.search: _searchLocalSemantic,
    DegradationColumn.mealLogging: _mealNormal,
  },
  DegradationRow.chatModelUnavailable: {
    DegradationColumn.memoryInjection: _memoryLocal,
    DegradationColumn.dishRecommendation: _dishLocal,
    DegradationColumn.search: _searchKeyword,
    DegradationColumn.mealLogging: _mealNormal,
  },
  DegradationRow.onDeviceModelUnavailable: {
    DegradationColumn.memoryInjection: _memoryLocal,
    DegradationColumn.dishRecommendation: _dishLocal,
    DegradationColumn.search: DegradationCell(
      behavior: '关键词 + 标签，如实提示「语义检索不可用」',
      notice: '（语义检索不可用，正在用关键词 + 标签搜索）',
    ),
    DegradationColumn.mealLogging: _mealNormal,
  },
  DegradationRow.indexBuilding: {
    DegradationColumn.memoryInjection: _memoryLocal,
    DegradationColumn.dishRecommendation: _dishLocal,
    DegradationColumn.search: DegradationCell(
      behavior: '关键词 + 标签，显示重建进度',
      notice: '（语义索引重建中，先按关键词 + 标签搜索）',
    ),
    DegradationColumn.mealLogging: _mealNormal,
  },
};

/// 语义路「引擎可用但候选都不过相关度阈值」时的提示（RV-P1-06 的子情形）。
///
/// 与 `onDeviceModelUnavailable` 分开：引擎没坏，只是没有足够相关的菜——
/// 说成「不可用」会误导排查方向。
const String kSemanticBelowThresholdNotice = '（语义候选相关度不足，本次按关键词 + 标签显示）';

/// 一格的界面提示（页面直接用；不要自己再 switch 一遍）。
String degradationNotice(DegradationRow row, DegradationColumn column) =>
    kDegradationMatrix[row]![column]!.notice;

/// 从 AI 配置状态与**最近一次连接失败证据**推出当前所处的行。
///
/// 2026-10-21 裁决 D-2（选项 A）：不新增 connectivity 依赖，用
/// `AiConnectivityMonitor` 的真实失败证据判「无网」。顺序：
/// 1. 没配置 AI ⇒ `aiNotConfigured`（用户要做的动作是去配置，不是查网络）；
/// 2. 有连接失败证据（窗口内）⇒ `offline`；
/// 3. 其余 ⇒ `chatModelUnavailable`（配置了但这一轮请求失败）。
DegradationRow degradationRowFor({
  required bool aiConfigured,
  bool offline = false,
}) {
  if (!aiConfigured) return DegradationRow.aiNotConfigured;
  return offline ? DegradationRow.offline : DegradationRow.chatModelUnavailable;
}
