import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// chat-edit v1 命令注册表（docs/23 §2）。
///
/// **单一事实源**：decoder 按它校验、executor 按它分发、system prompt 的
/// 命令清单由 [renderProtocol] 渲染。新增可编辑面 = 在这里注册一条 spec，
/// executor 加一个同名分支，两边测试各补一条。
///
/// 明确**不注册**（docs/23 §2 排除项）：设置/凭据类（安全边界）、训练计划的
/// 创建与条目编辑（已有带确认草稿的专属 AI 流程）、种子/目录食物的改删
/// （应用 UI 本来就不可改，事实纪律）。
final class ChatEditCommandRegistry {
  ChatEditCommandRegistry({List<ChatEditCommandSpec>? specs})
    : _specs = List.unmodifiable(specs ?? defaultSpecs) {
    for (final spec in _specs) {
      _byAction[spec.action] = spec;
    }
  }

  static const int maxEditsPerReply = 10;

  /// 一次回复最多几条「推荐按钮」（2026-10-16 新增的 `suggestions` 通道）。
  /// 3 条＝一行放得下，再多就是替用户做决定。
  static const int maxSuggestionsPerReply = 3;

  final List<ChatEditCommandSpec> _specs;
  final Map<String, ChatEditCommandSpec> _byAction = {};

  /// 查 spec；未注册的 action 返回 null（decoder 据此报「不支持的修改类型」）。
  ChatEditCommandSpec? specOf(String action) => _byAction[action];

  List<ChatEditCommandSpec> get specs => _specs;

  /// 把全部命令渲染成 system prompt 里的协议段（名字 + 参数 + 说明）。
  String renderProtocol() {
    final buffer = StringBuffer()
      ..writeln('你可以提议对 App 数据做修改。规则：')
      // 2026-10-24（`ai-live` 实测 + 提示词预算）：**把最关键的三条前置**。
      //
      // 实测（`deepseek-v4.1-flash`，27 条自然语言）：第一趟出信封 22/27 =
      // 81.5%；4 条失败**不是听不懂**，而是退回散文（「没有午餐可删」
      // 「看不出你指哪一条」「这是原则还是具体一餐」）。它们全部违反原先
      // 写在 63% 处的「修改请求禁止只回一句文字」——小参模型对长指令**中段**
      // 的依从性差（lost in the middle），而规则 1（格式）在最前、规则 12
      // 在最后都被遵守。
      //
      // 修法：**规则 1 之前先讲「什么时候必须给信封」**（含缺信息兜底），
      // 并把它压缩成三句能记住的话；原规则 5 的正文保留在后面（语义不删）。
      ..writeln(
        '0. **只要用户这句话是在「让你改点什么」——记录/添加/删除/修改/'
        '设定目标——就必须给出信封，不能只回一段文字。**'
        '这是本协议最重要的一条：',
      )
      ..writeln('   · 信息够 → 直接给 edits（不要反问确认）。')
      ..writeln(
        '   · 信息不全 / 指代不明 → **仍然要给信封**：edits 为空，reply 里说清'
        '还差哪一项信息；**只有在快照里确实存在多个可选择项时**才用 suggestions '
        '列出它们（例如「删掉那条记录」而快照里有 3 条 ⇒ 3 个候选按钮）。'
        '**别把无关操作混进来**。',
      )
      ..writeln(
        '   · **食量/克数/营养值没说 ⇒ 按常见份量估算，不许反问**：这类最常被'
        '误当成「信息不全」，其实**都该估**。「我中午吃了米饭和鸡胸肉」「早上'
        '两个包子」「加一个叫麻辣烫的食材」——按常见份量估算（一碗米饭约 150g、'
        '一个肉包约 100g、麻辣烫每 100g 约 90 kcal）并给**完整 edits**，reply 里'
        '写「按 … 估算」。**不要反问**「各吃了多少克」「营养值是多少」「要我按'
        '这组估算值建吗」——那等于把不用用户回答的事推回去。估算值直接上卡片，'
        '**点「应用 / 不应用」就是确认**，不必再征求同意。'
        '**「说了一半」也算修改请求**（「午餐 600 大卡左右」「刚吃了点东西」）：'
        '只有**估不出来**的项（指代哪一条记录、哪一餐）才问，食量类一律自己估，'
        '**绝不许只回一段问句**。',
      )
      ..writeln(
        '   · **动作执行不了也要给信封，但不许偷换成别的命令**：快照里找不到要'
        '删/要改的目标（「把今天的午餐删了」而今天没记录）、缺少可写入口、数据'
        '本来就是空的 —— 这些不是「没听懂」，是「听懂了但做不了」。此时仍要给'
        '信封：**edits 为空数组**，reply 里一句话说清为什么做不了。'
        '**suggestions 也要留空**——除非用户那句话里**明确还有另一件可以做'
        '的事**才给对应命令。**严禁**把用户没要求的事塞成按钮（用户说「删午餐」'
        '而库里没有，就不许推荐「记午餐」；用户说练了深蹲，就不许推荐换动作）。'
        '只给正确的：要么精确命中用户要的命令，要么什么都不给、只说明原因。',
      )
      ..writeln(
        '   · **一条回复只做用户这句话要求的事，不许顺手附送**：用户说「我中午'
        '吃了米饭和鸡胸肉」就只 `meal.create`；**不要**再补一条 '
        '`meal.item.update` 去改克数、不要补 `targets.update` 去改目标、不要补 '
        '`memory.remember` 去记一句。多给的那条会被一起画成待应用行，用户得'
        '逐条拒绝——这就是「推荐了用户没要的东西」。'
        '**每次只提议用户这句话里明确提到的那件事**。',
      )
      ..writeln(
        '   · **每条 edits 的参数必须完整、能直接执行**：写不全的这条不要发'
        '（记一餐的 `items` **至少要有一条食物**，不能是空数组）——执行器会'
        '直接判失败。参数确实不全 ⇒ 走上面那条：edits 留空，reply 说清缺什么。',
      )
      ..writeln(
        '   · **你只是提议，还没有生效**：reply 里**不许写「已记录 / 已添加 / '
        '已删除 / 已改好」**这类完成态说法（用户还没点「应用」）。用「我准备'
        '记为…」「要我这样记吗」这类提议口吻。谎报完成比不弹卡片更糟。',
      )
      ..writeln('   · 只有用户**完全没提改动**（纯提问 / 闲聊）才用纯文本。')
      ..writeln(
        '1. 信封格式：'
        '{"reply":"给用户看的中文说明","edits":[{"action":"命令名","args":{...}}]}。'
        '**整段回复只放这一个 JSON 对象**——不要加解释、寒暄或'
        'markdown 代码围栏（App 逐字解析：多一个字，这次提议就作废）。'
        '`edits` 可为空数组，但**只在**规则 0 的两种情况：信息不全（reply 说明'
        '缺什么）或执行不了（reply 说明为什么）——正常能改时必须至少一条。',
      )
      ..writeln('2. 每次回复最多 $maxEditsPerReply 条 edits。')
      ..writeln(
        '3. 改/删目标优先用【当前可编辑数据快照】里方括号给的 id；'
        '按名字定位必须是快照/常识里的精确全名，禁止编造 id。'
        '列表里没有的命令不要声称不存在——先按上面的清单核对。',
      )
      ..writeln(
        '4. 用户已明确要求的修改直接输出信封，不要再追问确认（应用前本来就有'
        '「应用」确认步）。拿不准时**仍要出信封**（edits 空 + suggestions，'
        '见规则 0），不要只回一句提问。你提议的修改要等用户点「应用」才生效。'
        '可用命令：',
      );
    for (final spec in _specs) {
      final params = [
        for (final arg in spec.args)
          '${arg.name}${arg.required ? '' : '(可选)'}'
              '${arg.hint == null ? '' : '：${arg.hint}'}',
      ].join('；');
      buffer.writeln('- ${spec.action}（${spec.title}）：$params');
    }
    buffer
      ..writeln('')
      ..writeln(
        '5. **修改请求禁止只回一句文字**：话里含增/删/改的意思就必须给信封'
        '（规则 0）。真缺信息时 edits 可以空，在 reply 里说明还差什么。'
        '**用户这条是修改请求**却没有信封，App 会认为你没答完并再催你一次。',
      )
      ..writeln(
        '6. **口语就是命令**：听到「加/记录/我吃了/喝了/删掉/改成」这类说法，'
        '直接翻成对应命令出信封——不要因为用户没说命令名就只回文字，也不要'
        '反问「要不要用某个命令」。例：「添加鸡肉食材」库里没有 ⇒ food.create；'
        '「早餐一个鸡蛋」⇒ meal.create（slot=breakfast，items=[{"food":"鸡蛋",'
        '"grams":50}]）。',
      )
      ..writeln(
        '7. 用户要加的食物/菜品/动作/地点/窗口不在快照里时，**不要只回「库里'
        '没有」**：在 reply 里说明并用 food.create 提议建成自建食材（营养按常见'
        '值估算，不要留空）；一次回复可以同时 food.create + meal.create。'
        'App 侧也会在引用不存在的实体时给出「新建」按钮。',
      )
      ..writeln(
        '8. 可选字段 `suggestions`：有 1–$maxSuggestionsPerReply 个「下一步大概率'
        '想做的事」时加"suggestions":[{"label":"短文案","action":"命令名",'
        '"args":{…}}]，App 渲染成按钮。只给按钮不写库时 edits 可为空。',
      )
      // 2026-10-16 口语弹药库 C19 实测：用户说「今天走了一万步」（**当天
      // 事实**），模型把它当成「把步数目标改成一万」并写了 `targets.update`
      // ⇒ 用户的**目标**被静默改掉。计步数据来自系统传感器，对话里没有
      // 记录当天步数的命令——必须如实说明，不许改目标顶替。
      ..writeln(
        '9. **步数是系统读的**：`targets.update` 的 `steps` 是「每日**目标**」。'
        '用户说「今天走了一万步」这类**当天事实**时没有对应命令，用纯文本'
        '如实说明，**绝不要**用 `targets.update` 顶替；只有明确说改目标才用。',
      )
      // 2026-10-17（docs/38 S11）：快照新增「饮食偏好与忌口」段。段在快照里
      // 只是数据，行为规则必须写在协议里：遵守 + 改口时以当前说法为准并落库。
      ..writeln(
        '10. **饮食偏好与忌口是硬约束**：【饮食偏好与忌口】段里的标签与忌口/'
        '过敏食材名必须遵守：给餐食、食材、菜品或外食建议时一律避开。'
        '用户当前说法不一致时（「我其实能吃 X 了」）**以用户当前说法为准**，'
        '用 `constraints.set` 更新并在 reply 里说明改了什么。',
      )
      // 2026-10-17（docs/38 S11）：长期记忆的用法。核心是分工——结构化字段
      // 能表达的一律不进记忆，否则同一事实两处不一致。
      ..writeln(
        '11. **长期记忆只收「软信息」**：「记住…」用 `memory.remember`，'
        '「忘掉…」用 `memory.forget`；【长期记忆】段只是参考，与当前说法冲突'
        '以当前为准。**能落到结构化字段的一律用对应命令**：过敏/忌口/标签用 '
        '`constraints.set`，目标 `profile.goal.update`，身高/出生年/性别 '
        '`profile.body.update`，饮水/步数目标 `targets.update`，训练计划 '
        '`workout.plan.*`——不要写进记忆。记忆只收口味偏好、作息习惯、器械/'
        '厨房条件、常去窗口、近况；一条 ≤140 字，不存证件/银行类信息。'
        '**「常去/爱吃 X」是偏好不是新建**：「我常去二食堂川菜窗口」是记住'
        '这个习惯，**不要**发 `canteen.venue.create`/`canteen.window.create`。'
        '`memory.forget` 匹配多条时**用 suggestions 给出每条候选项**让用户点选。',
      )
      // 2026-10-19（docs/40 §5 / docs/43 B10）：食物来源优先级。只加提示词，
      // 不改命令与 wire 形状；四条按「有供应事实 > 份量模板 > 营养事实 >
      // 新建」排序，避免用食物库顶替食堂菜。
      ..writeln(
        '12. **食物来源优先级**：1) 该窗口今天有同名菜（`[canteen-dish:…]`）'
        '→ 食堂菜；2) 菜品库（`[dish:…]`）→ 每份；3) 食物库同名（精确/别名）'
        '→ 每 100g × 克数；4) 都没有 → 提议 `food.create`。'
        '「食堂今天有什么」→ **只查菜单**。指食堂菜问热量 → 用食堂证据并标'
        '「AI 估算」。`nutritionFrom`：只有明确说「用食物库的」才用 `food`，'
        '**不要替用户决定**；`food` 未命中如实失败，不静默改走 AI。',
      )
      // 2026-10-23 用户：「AI 不查重（加午餐后再加晚餐会重复午餐计入两份）」
      // 「不主动检索食物库已有食物（先推卡片再说已有/失败）」。
      // App 侧已加合并/复用兜底；提示词先让模型别提出重复的提议。
      ..writeln(
        '13. **不要重复记同一餐 / 先查食物库**：今天已有的餐次不要再发 '
        '`meal.create`；「再吃点 X」只补那一餐还没有的（App 也会按餐次合并、'
        '跳过同名）。新建食材前先看【食物库参考】：已有同名直接引用，'
        '不要先 `food.create` 再报「已存在」。',
      )
      ..writeln(
        '14. **餐次按用户说的 / items 不许同名重复 / 一样都不许漏**：'
        '① 用户说了哪一餐（「晚饭」「午餐」「早上」）就**必须**用那个 `slot`，'
        '**绝不许自己换一餐**；用户没说才由你按上下文判断。'
        '② 同一条 `meal.create` 的 `items` 里**同名食物只能出现一次**——用户'
        '自己说重复（「米饭和米饭」）或你算份量列了两次，都**合并成一条**。'
        '③ 用户一句话点了好几样（「米饭、鸡胸肉、牛奶，还有一个苹果」）时'
        '**每一样都要进 items**，一样都不许漏。',
      );
    return buffer.toString();
  }

  /// v1 全量命令（docs/23 §2 表格的实现）。
  static final List<ChatEditCommandSpec> defaultSpecs = _buildSpecs();
}

List<ChatEditCommandSpec> _buildSpecs() {
  final localDateArg = ChatEditArgSpec(
    name: 'localDate',
    type: ChatEditArgType.localDate,
    required: false,
    hint: 'yyyy-MM-dd，缺省今天',
  );

  String itemsSummary(Map<String, Object> args) {
    final items = args['items'] as List<Object>;
    return items
        .map((item) {
          final map = item as Map<String, Object>;
          return '${map['food']} ${map['grams']}g';
        })
        .join(' + ');
  }

  return [
    ChatEditCommandSpec(
      action: 'weight.log',
      title: '记录体重',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'weightKg',
          type: ChatEditArgType.number,
          required: true,
          min: 35,
          max: 300,
          hint: '体重 kg',
        ),
        localDateArg,
        // schema 22（docs/31 S2，需求 45/46）删掉 bodyFatPercent /
        // muscleMassKg 两个可选参数：字段与数据一起没了，AI 再收到这两个
        // 参数就是往一个不存在的列上写。
        const ChatEditArgSpec(
          name: 'notes',
          type: ChatEditArgType.string,
          required: false,
          hint: '备注',
        ),
      ],
      summarize: (args) =>
          '体重 ${args['weightKg']}kg'
          '${args.containsKey('localDate') ? '（${args['localDate']}）' : '（今天）'}',
    ),
    ChatEditCommandSpec(
      action: 'water.add',
      title: '记一笔饮水',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'amountMl',
          type: ChatEditArgType.number,
          required: true,
          min: 1,
          max: 5000,
          hint: '毫升（与仓储上限一致）',
        ),
        localDateArg,
      ],
      summarize: (args) =>
          '饮水 ${args['amountMl']}ml'
          '${args.containsKey('localDate') ? '（${args['localDate']}）' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'water.delete',
      title: '删除饮水记录',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'waterId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的饮水记录 id',
        ),
      ],
      summarize: (args) => '删除饮水记录 ${args['waterId']}',
    ),
    ChatEditCommandSpec(
      action: 'meal.create',
      title: '记一餐',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'slot',
          type: ChatEditArgType.mealSlot,
          required: true,
          hint: '餐次',
        ),
        const ChatEditArgSpec(
          name: 'items',
          type: ChatEditArgType.foodItems,
          required: true,
          hint:
              '条目列表，形如 {"food":"鸡蛋","grams":50}；'
              '食物必须已存在，没有就先 food.create',
        ),
        localDateArg,
        const ChatEditArgSpec(
          name: 'notes',
          type: ChatEditArgType.string,
          required: false,
          hint: '备注',
        ),
      ],
      summarize: (args) =>
          '${_slotLabel(args['slot'])}：${itemsSummary(args)}'
          '${args.containsKey('localDate') ? '（${args['localDate']}）' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'meal.update',
      title: '修改一餐',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'mealId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的餐记录 id',
        ),
        const ChatEditArgSpec(
          name: 'slot',
          type: ChatEditArgType.mealSlot,
          required: false,
          hint: '改成哪个餐次',
        ),
        const ChatEditArgSpec(
          name: 'notes',
          type: ChatEditArgType.string,
          required: false,
          hint: '备注（覆盖）',
        ),
      ],
      summarize: (args) =>
          '修改餐 ${args['mealId']}'
          '${args.containsKey('slot') ? ' → ${_slotLabel(args['slot'])}' : ''}'
          '${args.containsKey('notes') ? '，备注「${args['notes']}」' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'meal.item.update',
      title: '改餐里某条的克数',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'itemId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的餐条目 id',
        ),
        const ChatEditArgSpec(
          name: 'grams',
          type: ChatEditArgType.number,
          required: true,
          min: 0.1,
          max: 5000,
          hint: '新克数',
        ),
      ],
      summarize: (args) => '${args['itemId']} 改为 ${args['grams']}g',
    ),
    ChatEditCommandSpec(
      action: 'meal.item.delete',
      title: '删掉餐里某条',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'itemId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的餐条目 id',
        ),
      ],
      summarize: (args) => '删除条目 ${args['itemId']}',
    ),
    ChatEditCommandSpec(
      action: 'meal.delete',
      title: '删除一餐',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'mealId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的餐记录 id',
        ),
      ],
      summarize: (args) => '删除餐 ${args['mealId']}',
    ),
    ChatEditCommandSpec(
      action: 'food.create',
      title: '新建食材',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '食材名（含品牌更好）',
        ),
        const ChatEditArgSpec(
          name: 'kcalPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 1000,
          hint: '每 100g 热量',
        ),
        const ChatEditArgSpec(
          name: 'proteinPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 蛋白质 g',
        ),
        const ChatEditArgSpec(
          name: 'carbsPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 碳水 g',
        ),
        const ChatEditArgSpec(
          name: 'fatPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 脂肪 g',
        ),
        const ChatEditArgSpec(
          name: 'servingGrams',
          type: ChatEditArgType.number,
          required: false,
          min: 0.1,
          max: 2000,
          hint: '默认一份的克数',
        ),
        const ChatEditArgSpec(
          name: 'brand',
          type: ChatEditArgType.string,
          required: false,
          hint: '品牌',
        ),
      ],
      summarize: (args) =>
          '新建食材「${args['name']}」：${args['kcalPer100g']} kcal/100g'
          '（P${args['proteinPer100g']}/C${args['carbsPer100g']}/F${args['fatPer100g']}）',
    ),
    ChatEditCommandSpec(
      action: 'dish.upsert',
      title: '收录/更新菜品',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '菜品名（同名=同一道菜，会更新）',
        ),
        const ChatEditArgSpec(
          name: 'slot',
          type: ChatEditArgType.mealSlot,
          required: true,
          hint: '适合的餐次',
        ),
        const ChatEditArgSpec(
          name: 'kcal',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 1000,
          hint: '每份热量',
        ),
        const ChatEditArgSpec(
          name: 'protein',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 300,
        ),
        const ChatEditArgSpec(
          name: 'carbs',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 500,
        ),
        const ChatEditArgSpec(
          name: 'fat',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 300,
        ),
        const ChatEditArgSpec(
          name: 'comment',
          type: ChatEditArgType.string,
          required: false,
          hint: '一句话点评',
        ),
      ],
      summarize: (args) =>
          '菜品「${args['name']}」${args['kcal']} kcal'
          '（P${args['protein']}/C${args['carbs']}/F${args['fat']}）',
    ),
    ChatEditCommandSpec(
      action: 'dish.delete',
      title: '删除菜品',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'dishId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的菜品 id',
        ),
      ],
      summarize: (args) => '删除菜品 ${args['dishId']}',
    ),
    ChatEditCommandSpec(
      action: 'canteen.venue.create',
      title: '新建食堂地点',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '地点名',
        ),
        const ChatEditArgSpec(
          name: 'campus',
          type: ChatEditArgType.string,
          required: true,
          hint: '校区名',
        ),
      ],
      summarize: (args) => '新建地点「${args['name']}」（${args['campus']}）',
    ),
    ChatEditCommandSpec(
      action: 'canteen.venue.rename',
      title: '重命名食堂地点',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'venueId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的地点 id',
        ),
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
        ),
      ],
      summarize: (args) => '地点改名「${args['name']}」',
    ),
    ChatEditCommandSpec(
      action: 'canteen.venue.delete',
      title: '删除食堂地点',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'venueId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的地点 id',
        ),
      ],
      summarize: (args) => '删除地点 ${args['venueId']}（含其窗口与菜品）',
    ),
    ChatEditCommandSpec(
      action: 'canteen.window.create',
      title: '新建窗口',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'venue',
          type: ChatEditArgType.string,
          required: true,
          hint: '地点 id 或精确唯一名',
        ),
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '窗口名',
        ),
        const ChatEditArgSpec(
          name: 'openTime',
          type: ChatEditArgType.time,
          required: true,
          hint: 'HH:mm',
        ),
        const ChatEditArgSpec(
          name: 'closeTime',
          type: ChatEditArgType.time,
          required: true,
          hint: 'HH:mm，须晚于开始',
        ),
      ],
      summarize: (args) =>
          '窗口「${args['name']}」${args['openTime']}–${args['closeTime']}'
          '（${args['venue']}）',
    ),
    ChatEditCommandSpec(
      action: 'canteen.window.delete',
      title: '删除窗口',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'windowId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的窗口 id',
        ),
      ],
      summarize: (args) => '删除窗口 ${args['windowId']}（含其菜品）',
    ),
    ChatEditCommandSpec(
      action: 'canteen.dish.create',
      title: '新增食堂菜品',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'window',
          type: ChatEditArgType.string,
          required: true,
          hint: '窗口 id 或精确唯一名',
        ),
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '菜品名',
        ),
        const ChatEditArgSpec(
          name: 'nutritionFrom',
          type: ChatEditArgType.string,
          required: false,
          hint:
              '营养来源：food（引用食物库）| ai（AI 分析）| none（不填）；'
              '缺省 none，与旧行为一致',
        ),
      ],
      summarize: (args) =>
          '菜品「${args['name']}」加到 ${args['window']}'
          '${args['nutritionFrom'] == 'food' ? '（营养引用食物库）' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'canteen.dish.update',
      title: '修改食堂菜品',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'dishId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的菜品 id',
        ),
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: false,
        ),
      ],
      summarize: (args) =>
          '修改菜品 ${args['dishId']}'
          '${args.containsKey('name') ? '，改名「${args['name']}」' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'canteen.dish.delete',
      title: '删除食堂菜品',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'dishId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的菜品 id',
        ),
      ],
      summarize: (args) => '删除菜品 ${args['dishId']}',
    ),
    ChatEditCommandSpec(
      action: 'profile.goal.update',
      title: '改健康目标',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'goal',
          type: ChatEditArgType.goal,
          required: true,
          hint: '减脂/维持/增肌',
        ),
        const ChatEditArgSpec(
          name: 'targetWeightKg',
          type: ChatEditArgType.number,
          required: false,
          min: 35,
          max: 300,
          hint: '目标体重 kg',
        ),
      ],
      summarize: (args) =>
          '目标改为${_goalLabel(args['goal'])}'
          '${args.containsKey('targetWeightKg') ? '，目标体重 ${args['targetWeightKg']}kg' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'constraints.set',
      title: '设置饮食约束',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'dietaryLabels',
          type: ChatEditArgType.stringList,
          required: false,
          hint: '素食/纯素/无乳制品/无麸质（空列表=清空）',
        ),
        const ChatEditArgSpec(
          name: 'allergenAvoidances',
          type: ChatEditArgType.stringList,
          required: false,
          // 2026-10-16 真实模型实测：用户说「我对芒果过敏」时，模型把过敏原
          // 漏成空列表（只写了素食标签）⇒ 约束没真正落库。hint 里点名
          // 「过敏原放这里」并给常见例子，减少这类漏填。
          hint:
              '用户过敏/忌口的食材放这里：蛋类/乳制品/大豆/麸质/花生/树坚果/'
              '鱼类/甲壳类/芝麻，也接受其他食材名（如芒果、菠萝蜜）',
        ),
      ],
      summarize: (Map<String, Object> args) {
        final labels = args['dietaryLabels'] as List<Object>?;
        final allergens = args['allergenAvoidances'] as List<Object>?;
        final labelText = (labels == null || labels.isEmpty)
            ? '（不变）'
            : labels.join('、');
        final allergenText = (allergens == null || allergens.isEmpty)
            ? '（不变）'
            : allergens.join('、');
        return '饮食约束：$labelText；回避过敏原：$allergenText';
      },
    ),
    ChatEditCommandSpec(
      action: 'workout.plan.create',
      title: '创建训练计划',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '计划名，如「四天增肌」',
        ),
        const ChatEditArgSpec(
          name: 'days',
          type: ChatEditArgType.planDays,
          required: true,
          hint: '每天 {"weekday":1–7,"entries":[{"exercise":动作名,"sets":组数,"reps":次数,"weightKg":可选}]}',
        ),
      ],
      summarize: (args) {
        final days = args['days'] as List;
        final total = days.fold<int>(
          0,
          (sum, day) => sum + ((day as Map)['entries'] as List).length,
        );
        return '创建计划「${args['name']}」：${days.length} 个训练日、共 $total 条动作';
      },
    ),
    ChatEditCommandSpec(
      action: 'workout.plan.delete',
      title: '删除训练计划',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'planId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的训练计划 id',
        ),
      ],
      summarize: (args) => '删除训练计划 ${args['planId']}',
    ),

    // ── 批次 B（2026-10-15）：菜单快照发布（docs/34 §7 第 2 条）────────
    // 承载形态＝**结构化载荷**：参数里直接放 `menu-normalize v1` 的 JSON 文本，
    // 由 `MenuNormalizeJsonDecoder` 逐字段校验后交 `PublishMenuNormalizeDraft`
    // 发布——不新造管线，也不用会丢 schema 版本/warnings 的降级折衷。
    // 2026-10-16（用户：食堂菜品 AI 分析后目录里没有显示结果）：新增一条
    // **食堂菜品营养**写入命令。原先 `CanteenRepository.recordNutrition`
    // （写证据表 + 等级 + 状态）一个调用方都没有——分析结果从来没落库，
    // 于是目录永远显示「未分析营养」。
    ChatEditCommandSpec(
      action: 'canteen.dish.nutrition',
      title: '记录菜品营养',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'dishId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的菜品 id（[canteen-dish:…]）',
        ),
        const ChatEditArgSpec(
          name: 'kcalPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 900,
          hint: '每 100g 热量',
        ),
        const ChatEditArgSpec(
          name: 'proteinPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 蛋白质 g',
        ),
        const ChatEditArgSpec(
          name: 'carbsPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 碳水 g',
        ),
        const ChatEditArgSpec(
          name: 'fatPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 脂肪 g',
        ),
        const ChatEditArgSpec(
          name: 'grade',
          type: ChatEditArgType.string,
          required: false,
          hint: '证据等级 A|B|C|D，缺省按最保守的 D（粗估）',
        ),
        const ChatEditArgSpec(
          name: 'confidence',
          type: ChatEditArgType.number,
          required: false,
          min: 0,
          max: 1,
          hint: '模型自评置信度 0–1（缺省 0.5）',
        ),
        const ChatEditArgSpec(
          name: 'nutritionFrom',
          type: ChatEditArgType.string,
          required: false,
          hint:
              '营养来源：ai（本命令的数值，缺省）| food（引用食物库）| '
              'none（跳过写入）',
        ),
      ],
      // 【2026-10-25 缺陷修复】原来把 `dishId` 直接拼进文案，于是编辑卡上
      // 显示「[canteen-dish:mx-3] 每 100g：45 kcal…」——那是给模型看的快照
      // 坐标，不是人话（用户实测：「还是会输出一堆食材 ID」）。
      // `dishId` 仍然**必须传**（执行器靠它定位），只是不再上屏。
      summarize: (args) =>
          '每 100g：${args['kcalPer100g']} kcal · 蛋白 ${args['proteinPer100g']}g · '
          '碳水 ${args['carbsPer100g']}g · 脂肪 ${args['fatPer100g']}g'
          '${args.containsKey('grade') ? '（等级 ${args['grade']}）' : ''}'
          '${args['nutritionFrom'] == 'food' ? '（改引食物库）' : ''}',
    ),
    ChatEditCommandSpec(
      action: 'menu.snapshot.publish',
      title: '发布菜单快照',
      danger: ChatEditDanger.create,
      args: [
        ChatEditArgSpec(
          name: 'menuJson',
          type: ChatEditArgType.string,
          required: true,
          maxLength: 20000,
          // 真模型会把结构化载荷发成**对象**（2026-10-15 实测 GLM-5.3 如此）
          // ⇒ 对象/数组形态也收（解码器 jsonEncode 成文本再走同一套校验）。
          jsonObjectAllowed: true,
          hint:
              'menu-normalize v1 草案 JSON（字段：schema_version=1、'
              'source_date yyyy-MM-dd、venue_name、services[{service_name、'
              'open_time/close_time HH:mm、items[{display_name、'
              'station_name、reported_nutrition、ingredient_hints、'
              'allergen_hints、needs_confirmation、questions}]}]、warnings[]）',
        ),
      ],
      summarize: (args) =>
          '发布菜单快照（草案 ${(args['menuJson'] as String).length} 字）',
    ),

    // ── 批次 A（2026-10-15）：训练域六个命令（docs/34 §5）───────────────
    // 口径：与 UI 同源校验（仓储自己再兜一层）；会话是**进行中状态机**，
    // `session.start` 遇到已有活跃会话时如实拒绝，绝不覆盖。
    ChatEditCommandSpec(
      action: 'session.start',
      title: '开始一次训练',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'planId',
          type: ChatEditArgType.string,
          required: false,
          hint: '快照里的训练计划 id（可选；不给就是自由训练）',
        ),
        localDateArg,
      ],
      summarize: (args) => args.containsKey('planId')
          ? '开始训练（计划 ${args['planId']}）'
          : '开始一次自由训练',
    ),
    ChatEditCommandSpec(
      action: 'set.log',
      title: '记一组训练',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'exercise',
          type: ChatEditArgType.string,
          required: true,
          hint: '动作名（与动作库精确同名，如「杠铃深蹲」）',
        ),
        const ChatEditArgSpec(
          name: 'weightKg',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 500,
          hint: '重量 kg（自重动作填 0）',
        ),
        const ChatEditArgSpec(
          name: 'reps',
          type: ChatEditArgType.integer,
          required: true,
          min: 1,
          max: 100,
          hint: '次数',
        ),
        const ChatEditArgSpec(
          name: 'rpe',
          type: ChatEditArgType.number,
          required: false,
          min: 6,
          max: 10,
          hint: '自觉用力程度 6–10（可选）',
        ),
        const ChatEditArgSpec(
          name: 'sessionId',
          type: ChatEditArgType.string,
          required: false,
          hint: '进行中会话 id（缺省＝当前进行中的那个）',
        ),
      ],
      summarize: (args) =>
          '记一组：${args['exercise']} ${args['weightKg']}kg × ${args['reps']} 次',
    ),
    ChatEditCommandSpec(
      action: 'session.finish',
      title: '结束这次训练',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'sessionId',
          type: ChatEditArgType.string,
          required: false,
          hint: '进行中会话 id（缺省＝当前进行中的那个）',
        ),
      ],
      summarize: (args) => '结束这次训练',
    ),
    ChatEditCommandSpec(
      action: 'plan.entry.add',
      title: '给计划加一个动作',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'planId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的训练计划 id',
        ),
        const ChatEditArgSpec(
          name: 'weekday',
          type: ChatEditArgType.integer,
          required: true,
          min: 1,
          max: 7,
          hint: '星期（1=周一 … 7=周日）',
        ),
        const ChatEditArgSpec(
          name: 'exercise',
          type: ChatEditArgType.string,
          required: true,
          hint: '动作名（与动作库精确同名）',
        ),
        const ChatEditArgSpec(
          name: 'sets',
          type: ChatEditArgType.integer,
          required: true,
          min: 1,
          max: 20,
          hint: '目标组数',
        ),
        const ChatEditArgSpec(
          name: 'reps',
          type: ChatEditArgType.integer,
          required: true,
          min: 1,
          max: 100,
          hint: '目标次数',
        ),
        const ChatEditArgSpec(
          name: 'weightKg',
          type: ChatEditArgType.number,
          required: false,
          min: 0,
          max: 500,
          hint: '目标重量 kg（可选）',
        ),
      ],
      summarize: (args) =>
          '计划 ${args['planId']} 星期${args['weekday']}加：'
          '${args['exercise']} ${args['sets']}×${args['reps']}',
    ),
    ChatEditCommandSpec(
      action: 'plan.entry.remove',
      title: '从计划里移除一个动作',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'entryId',
          type: ChatEditArgType.string,
          required: true,
          hint:
              '快照「训练计划」段里的 [pentry:…] 条目 id（2026-10-16 起该段'
              '同时印出每个训练日的条目 id 与动作名）',
        ),
      ],
      summarize: (args) => '移除动作条目 ${args['entryId']}',
    ),
    ChatEditCommandSpec(
      action: 'plan.rename',
      title: '改训练计划名',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'planId',
          type: ChatEditArgType.string,
          required: true,
          hint: '快照里的训练计划 id',
        ),
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '新名字（≤60 字）',
        ),
      ],
      summarize: (args) => '计划 ${args['planId']} 改名为「${args['name']}」',
    ),

    // ── 批次 C（2026-10-15）：自建食物与资料/目标（docs/34 §5）─────────
    ChatEditCommandSpec(
      action: 'food.update',
      title: '改自建食物',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'foodId',
          type: ChatEditArgType.string,
          required: true,
          hint: '自建食物的 id（食物库详情里可查；内置食物不可改）',
        ),
        const ChatEditArgSpec(
          name: 'name',
          type: ChatEditArgType.string,
          required: true,
          hint: '名称',
        ),
        const ChatEditArgSpec(
          name: 'kcalPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 1000,
          hint: '每 100g 热量 kcal',
        ),
        const ChatEditArgSpec(
          name: 'proteinPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 蛋白质 g',
        ),
        const ChatEditArgSpec(
          name: 'carbsPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 碳水 g',
        ),
        const ChatEditArgSpec(
          name: 'fatPer100g',
          type: ChatEditArgType.number,
          required: true,
          min: 0,
          max: 100,
          hint: '每 100g 脂肪 g',
        ),
        const ChatEditArgSpec(
          name: 'servingGrams',
          type: ChatEditArgType.number,
          required: false,
          min: 1,
          max: 5000,
          hint: '默认一份克数（可选）',
        ),
        const ChatEditArgSpec(
          name: 'brand',
          type: ChatEditArgType.string,
          required: false,
          hint: '品牌（可选）',
        ),
      ],
      summarize: (args) =>
          '改自建食物 ${args['foodId']}：'
          '${args['name']} ${args['kcalPer100g']}kcal/100g',
    ),
    ChatEditCommandSpec(
      action: 'food.delete',
      title: '删自建食物',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'foodId',
          type: ChatEditArgType.string,
          required: true,
          hint: '自建食物的 id（内置食物不可删）',
        ),
      ],
      summarize: (args) => '删除自建食物 ${args['foodId']}',
    ),
    ChatEditCommandSpec(
      action: 'profile.body.update',
      title: '改身体资料',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'heightCm',
          type: ChatEditArgType.number,
          required: false,
          min: 100,
          max: 250,
          hint: '身高 cm（可选）',
        ),
        const ChatEditArgSpec(
          name: 'birthYear',
          type: ChatEditArgType.integer,
          required: false,
          min: 1900,
          max: 2020,
          hint: '出生年份（用户说年龄时用「今天」换算）',
        ),
        const ChatEditArgSpec(
          name: 'sex',
          type: ChatEditArgType.string,
          required: false,
          hint: "生理性别（female / male；只影响热量公式）",
        ),
      ],
      summarize: (args) {
        final parts = <String>[
          if (args.containsKey('heightCm')) '身高 ${args['heightCm']}cm',
          if (args.containsKey('birthYear')) '出生年 ${args['birthYear']}',
          if (args.containsKey('sex')) '性别 ${args['sex']}',
        ];
        return '改身体资料：${parts.join('、')}';
      },
    ),
    ChatEditCommandSpec(
      action: 'targets.update',
      title: '改每日目标',
      danger: ChatEditDanger.update,
      args: [
        const ChatEditArgSpec(
          name: 'waterMl',
          type: ChatEditArgType.number,
          required: false,
          min: 500,
          max: 6000,
          hint: '每日饮水目标 ml（可选）',
        ),
        const ChatEditArgSpec(
          name: 'steps',
          type: ChatEditArgType.integer,
          required: false,
          min: 1000,
          max: 50000,
          hint: '每日步数**目标**（可选；不是「今天走了多少步」——当天步数由系统计步读取，对话不写）',
        ),
      ],
      summarize: (args) {
        final parts = <String>[
          if (args.containsKey('waterMl')) '饮水 ${args['waterMl']}ml',
          if (args.containsKey('steps')) '步数 ${args['steps']}',
        ];
        return '改每日目标：${parts.join('、')}';
      },
    ),
    // ── S11（2026-10-17，docs/38）：长期记忆 ──────────────────────────
    ChatEditCommandSpec(
      action: 'memory.remember',
      title: '记住一条偏好/习惯',
      danger: ChatEditDanger.create,
      args: [
        const ChatEditArgSpec(
          name: 'text',
          type: ChatEditArgType.string,
          required: true,
          maxLength: kAiMemoryMaxTextLength,
          hint: '一句话（≤140 字），例如「周三晚上练腿」',
        ),
        const ChatEditArgSpec(
          name: 'kind',
          type: ChatEditArgType.string,
          required: false,
          maxLength: 12,
          hint: '偏好/习惯/事实/近况（缺省=偏好）',
        ),
        const ChatEditArgSpec(
          name: 'domain',
          type: ChatEditArgType.string,
          required: false,
          maxLength: 12,
          hint: '饮食/训练/作息/食堂/其他（缺省=其他）',
        ),
        const ChatEditArgSpec(
          name: 'tags',
          type: ChatEditArgType.stringList,
          required: false,
          hint: '关键词（可选，≤6 个，每个 ≤12 字）',
        ),
      ],
      summarize: (args) => '记住「${args['text']}」',
    ),
    ChatEditCommandSpec(
      action: 'memory.forget',
      title: '忘掉一条记忆',
      danger: ChatEditDanger.delete,
      args: [
        const ChatEditArgSpec(
          name: 'text',
          type: ChatEditArgType.string,
          required: true,
          maxLength: kAiMemoryMaxTextLength,
          hint: '要忘掉的那条记忆的关键词（匹配不到会如实说没找到）',
        ),
      ],
      summarize: (args) => '忘掉「${args['text']}」',
    ),
  ];
}

String _slotLabel(Object? value) => switch (value) {
  'breakfast' => '早餐',
  'lunch' => '午餐',
  'dinner' => '晚餐',
  'snack' => '加餐',
  _ => '$value',
};

String _goalLabel(Object? value) => switch (value) {
  'loseFat' => '减脂',
  'maintain' => '维持',
  'gainMuscle' => '增肌',
  _ => '$value',
};
