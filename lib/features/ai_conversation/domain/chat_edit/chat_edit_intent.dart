/// 「用户这句话是在要求我改数据吗」的**本地**判定（2026-10-16）。
///
/// 由来（用户原话）：「我对话只要是涉及到让你修改，你就必须正确识别指令，
/// 而不是空回文字」。模型偶尔会把「帮我加一个鸡蛋」当闲聊回一段文字——
/// 这时**不能就此收场**：App 要能认出「这是修改请求」，再要求模型给出
/// 可应用的信封（见 `ConversationController` 的信封重试）。
///
/// 【为什么是保守口径】判定为真会**多发一次 AI 请求**（带「必须输出信封」
/// 提示重跑）。误判的代价是白花一次请求、还可能在气泡里换掉一段本来没问题的
/// 回复；漏判的代价只是退化成旧行为（用户看到文字，可以点「让 AI 给出可应用
/// 的修改」）。所以：**问句优先判假**，宁漏不误。
///
/// 这是纯本地启发式（不调模型、不猜实体），只回答「要不要催一次信封」。
library;

/// 修改动词（词根）：只要出现就认为「可能要求改」。
///
/// 覆盖日常说法：加/记/改/删/建/设/换/命名/更新/调整。刻意收窄到
/// 「动作性」强的词，避免「吃」「喝」「有」这类描述性动词误判。
const _modificationVerbs = <String>[
  '添加',
  '加入',
  '加进',
  '加到',
  '加一个',
  '加上',
  '加个',
  '再加',
  '帮我加',
  '放进',
  '录入',
  '新增',
  '存进',
  '保存到',
  '补记',
  '补录',
  '记录',
  '记一笔',
  '记一下',
  '帮我记',
  '记到',
  '删掉',
  '删除',
  '移除',
  '去掉',
  '改成',
  '改为',
  '换成',
  '换为',
  '修改',
  '更新',
  '调整',
  '重命名',
  '改名',
  '命名为',
  '设为',
  '设置为',
  '建一个',
  '新建',
  '创建',
  '编辑',
  // 【2026-11-02 用户实机：AI 一直重复「要不要生成」】计划类请求此前完全
  // 不在动词表里：「帮我生成今天的饮食计划」「安排三餐」「制定减脂计划」
  // 全判 false ⇒ 不催信封 ⇒ 模型一句「要不要我帮你生成？」就能无限循环。
  '生成',
  '制定',
  '制订',
  '安排',
  '规划',
  '计划一下',
  '配一套',
  '配一餐',
  '排一下',
  '排一套',
  '做一个',
  '做个',
  '拟一个',
  '拟个',
  '定个计划',
  '定一个计划',
  // 「我把这件事做了」的口语陈述＝记录意图（协议规则 5 的同一批说法）。
  '吃了',
  '喝了',
  '我喝了',
  '我吃了',
  '我称了',
  '我量了',
  '我跑了',
  '我练了',
  '我刚吃了',
  '我刚喝了',
];

/// 动词后紧跟这些字时**不算请求**：`记录很正常` / `记录不就是…` 是在谈论
/// 「记录」这件事，不是在要求记一笔。
const _verbFollowersToSkip = ['很', '不', '就', '是', '的', '也', '还', '过'];

/// 明确的「我要改」意图词：单独出现（后面不必跟动词）也算。
const _intentPhrases = <String>['我要', '我想', '帮我改', '改一下'];

/// 问句标记：出现这些就按「提问」处理（先答问题，不要硬塞信封）。
const _questionMarkers = <String>[
  '？',
  '?',
  '吗',
  '呢',
  '能不能',
  '可不可以',
  '要不要',
  '在哪儿',
  '在哪',
  '怎么',
];

/// **陈述式约束**的说法（2026-10-16 真实模型实测补的洞）。
///
/// 这类句子没有「加/删/改」动词，但它明确要求**把一条约束落库**
/// （`constraints.set`）：过敏、忌口、素食、不吃某物。
/// 不认它 ⇒ 不催信封 ⇒ 模型那段「我来把这些写进你的饮食约束里」的散文
/// 后面即使贴着信封也会解析失败，**什么都没写**，而用户看到的是「已记下」。
///
/// 口径仍然保守：要求「我」作主语且关键词紧随其后（避免「我朋友对花生过敏」），
/// 或者是个明确的祈使句（「别给我推荐…」）。纯提问由问句规则先拦掉。
/// 第三方主语：说的是别人（「我朋友对花生过敏」）时**不**按自己的约束处理。
const _thirdPartyMarkers = <String>[
  '我朋友',
  '我妈',
  '我爸',
  '我同事',
  '我家人',
  '我媳妇',
  '我老公',
  '我老婆',
  '我孩子',
  '我儿子',
  '我女儿',
  '我室友',
  '我同学',
  '我对象',
];

final _constraintPatterns = <RegExp>[
  RegExp(r'我[^。？！\n]{0,10}(过敏|忌口|忌食|不吃|吃素|素食|乳糖不耐)'),
  RegExp(r'(忌口|忌食)[^。？！\n]{0,10}'),
  RegExp(r'(别|不要|以后别)[^。？！\n]{0,6}(推荐|给我推)'),
];

/// 模型散文回复里**声称已经改了数据**的模式（2026-10-27，信封升级梯子的
/// 回复侧触发器，docs/24 记录过的真实失败模式：「已在你的忌口清单里加入芒果」
/// ——其实什么都没写）。
///
/// 只认第一人称完成态（已/帮你 + 落库动词），不认「建议你记录」「可以记录」
/// 这类**建议/说明**——误伤的代价是多花一次请求，但漏放的代价是用户以为
/// 记上了。两条都故意收紧。
final _replyClaimPatterns = <RegExp>[
  RegExp(r'已(经)?(记录|记下|添加|加入|删除|删掉|更新|改成|写入|保存)'),
  RegExp(r'已把[^。？！\n]{0,10}(加入|记入|存入|删除|删掉|更新|改成)'),
  RegExp(r'帮你(记录|记下|添加|加入|删除|删掉|更新|改)'),
];

/// 这条模型回复是否在**声称已经改了数据**。真值为「模型承诺过改动却没带
/// 信封」的失败信号（信封升级梯子的回复侧触发器）。
bool replyClaimsChanges(String reply) {
  final flat = reply.trim();
  if (flat.isEmpty) return false;
  for (final pattern in _replyClaimPatterns) {
    if (pattern.hasMatch(flat)) return true;
  }
  return false;
}

/// 模型回复里**引用「应用」卡片**的说法（「点『应用』后才会保存」「应用后
/// 自动记到今天的摄入」）。
///
/// 【2026-11-02 用户实机：AI 说有一条待应用记录，屏幕上却没有卡片】
/// 模型把「有一条卡等你点应用」当成事实写进回复，但这一轮根本没给信封。
/// 这比「声称已保存」更隐蔽：用户会去找那张不存在的卡，然后发现对话里
/// 只有文字。命中它时按失败处理（重催信封 + 兜底卡），而不是当普通闲聊。
///
/// 只在**整段对话没有任何编辑卡**时才算失败信号（见 controller）：用户
/// 对着上一张真实卡片追问「应用后会记到今天的摄入吗」是正常对话，不能误催。
final _applyCardReferencePatterns = <RegExp>[
  RegExp('点[击了]?[「"\u2018]?应用'),
  RegExp('应用[」"\u2019]?(之)?后'),
  RegExp(r'应用卡片'),
];

/// 这条回复是否在讲「点应用」这件事（配合「会话里有没有真卡片」一起判断）。
bool replyMentionsApplyCard(String reply) {
  final flat = reply.trim();
  if (flat.isEmpty) return false;
  for (final pattern in _applyCardReferencePatterns) {
    if (pattern.hasMatch(flat)) return true;
  }
  return false;
}

/// 模型回复是否在**反问「要不要我生成 / 帮你安排」**。
///
/// 【2026-11-02 用户实机】用户说「帮我生成今天的饮食计划」，模型连着几轮只回
/// 「要不要我帮你生成一份？」，一张卡都不弹。协议规则 0/4 明确要求「拿不准也
/// 要出信封，不要只回提问」，但模型反复违反。命中它时按失败处理（催信封），
/// 而不是把「要不要生成」当正常对话。
final _askingToProceedPatterns = <RegExp>[
  RegExp(r'(要不要|需不需要|是否要|可以帮你|需要我|要我)[^。？！\n]{0,20}(生成|安排|制定|规划|配|排|做)'),
  RegExp(r'(生成|安排|制定|规划|配|排)[^。？！\n]{0,12}(吗|呢|？|\?)'),
];

/// 这条回复是否在反问「要不要生成/安排」（而不是直接给信封）。
bool replyAsksToProceed(String reply) {
  final flat = reply.trim();
  if (flat.isEmpty) return false;
  for (final pattern in _askingToProceedPatterns) {
    if (pattern.hasMatch(flat)) return true;
  }
  return false;
}

/// 判断这句话是否**很可能**是修改请求（比对：`looksLikeModificationRequest`）。
bool looksLikeModificationRequest(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  // 问句优先：问「要不要 / 能不能 / 在哪儿 / 怎么」时不催信封——
  // 那正是模型该用纯文本回答的场景。
  for (final marker in _questionMarkers) {
    if (trimmed.contains(marker)) return false;
  }
  for (final verb in _modificationVerbs) {
    final at = trimmed.indexOf(verb);
    if (at < 0) continue;
    final next = at + verb.length;
    if (next < trimmed.length && _verbFollowersToSkip.contains(trimmed[next])) {
      continue; // 这一处不是请求，继续看别的动词
    }
    return true;
  }
  // 「我要减脂」「我想增肌」这类：意图词 + 后面还有实词（不是「我要」两个字）。
  for (final phrase in _intentPhrases) {
    final at = trimmed.indexOf(phrase);
    if (at >= 0 && trimmed.length > at + phrase.length) return true;
  }
  // 陈述式约束（过敏/忌口/素食/不吃）——没有动词但必须落库，见
  // `_constraintPatterns` 的注释。
  final thirdParty = _thirdPartyMarkers.any(trimmed.contains);
  if (!thirdParty) {
    for (final pattern in _constraintPatterns) {
      if (pattern.hasMatch(trimmed)) return true;
    }
  }
  return false;
}

/// 「让 AI 把回复整理成可应用修改」的提示句（App 在重试时追加到 system 段）。
///
/// 说得具体是为了让模型**只做一件事**：把刚才那段话变成信封；不发明新实体
/// （缺信息时用 `suggestions` 给可点选项）。
/// **手动点「让 AI 给出可应用的修改」时的加强版提示**（2026-10-16 设备实测补）。
///
/// 由来：设备上用户说「我对芒果过敏，别给我推荐含芒果的菜」，模型连着两次都只回
/// 文字（还声称「已在你的过敏/忌口清单里加入芒果」——其实什么都没写），标准提示
/// 催不动它。加强版把**模型自己上一条回复原文**引进去，要求它把其中承诺的改动
/// 逐条转成命令：对着自己的话，模型更难再用一段散文收尾。
String chatEditEnvelopeNudgeQuoting(String previousReply) {
  final flat = previousReply
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('"', '「')
      .trim();
  final quoted = flat.length <= 200 ? flat : '${flat.substring(0, 200)}…';
  return '【App 提示】用户点了「让 AI 给出可应用的修改」。你上一条回复是：'
      '「$quoted」。'
      '请把这条回复里**承诺或描述过的改动逐条**转成 chat-edit 命令信封：'
      '整段回复只放这一个 JSON 对象（不要解释、不要代码围栏）；'
      '每条 edit 都要有 action 与 args；缺信息时用 suggestions 给 1–3 个可点候选。'
      '如果那条回复其实没有任何改动要做，就回一个 edits 为空、只带 suggestions 的信封。';
}

const chatEditEnvelopeNudge =
    '【App 提示】用户这一条是**修改数据的请求**。你必须按 chat-edit 协议输出 '
    'JSON 信封（整段回复只放这一个 JSON 对象，不要写任何解释或代码围栏）。'
    '缺少必要信息时不要只回文字：用 suggestions 给 1–3 个可点选项，'
    '或在 reply 里说清楚还差什么、并用 suggestions 给出候选。';

/// 模型反问「要不要生成 / 要不要帮你安排」时的专门催促。
///
/// 【2026-11-02 用户实机】用户已经明确说「帮我生成今天的饮食计划」，模型却
/// 连续几轮只回「要不要我帮你生成一份？」，一张卡都不弹。协议规则 0/4 早就
/// 禁止「只回提问」，但这条对部分模型不够硬。这个提示把「不要问、直接做」
/// 单独说一遍，并给出可执行的最小信封形状。
String chatEditEnvelopeNudgeNoAsking(String previousReply) {
  final flat = previousReply
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('"', '「')
      .trim();
  final quoted = flat.length <= 200 ? flat : '${flat.substring(0, 200)}…';
  return '【App 提示】你上一条回复在**反问用户要不要生成**：「$quoted」。'
      '用户已经明确提出了这个请求，**不要再问一遍**——直接输出 chat-edit 信封，'
      '把要做的事写成 edits（例如 `workout.plan.create` / `meal.create`）。'
      '信息不全时按常见值估算并在 reply 里说明，绝不许用一句「要不要我帮你生成」'
      '代替信封。整段回复只放这一个 JSON 对象。';
}
