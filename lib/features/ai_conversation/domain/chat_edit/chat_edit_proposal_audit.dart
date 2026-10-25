import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 提案审查发现的问题类型。
enum ChatEditAuditKind {
  /// 用户明确说了餐次，但提议的餐次不是它（「我要晚餐，给我午餐」）。
  slotMismatch,

  /// 同一餐次里同一个食物出现多次（含跨多条命令）。
  duplicateFood,

  /// 用户点名的食物在提议里找不到（漏了）。
  missingFood,

  /// 份量离谱（2026-10-24 补上轮局限）：一条食物的克数远超常识范围
  /// （如「米饭 5000g」）。**绝不自动改**——可能是用户真有特殊需求，
  /// 但必须让用户在应用前看见。
  implausiblePortion,

  /// 非常规餐次说法（2026-10-24 补上轮局限）：用户说了「睡前那顿」
  /// 「下午那顿」这类词表外的餐次，我们认不出对应哪一餐——此时**不报**
  /// 餐次不符（那是瞎猜），但应当提示「没说清哪一餐」。
  vagueSlot,
}

/// 单条食物的「离谱份量」门槛（2026-10-24）。
///
/// 1000g 一顿吃一样东西不是不可能（大份沙拉、汤），但**超过它就值得
/// 让人看一眼**。执行器本身允许到 5000g（那是参数校验上限，不是常识
/// 上限），所以这里只警告、不拦。
const double kImplausiblePortionGrams = 1000;

/// 一次审查发现的问题。
final class ChatEditAuditWarning {
  const ChatEditAuditWarning({required this.kind, required this.message});

  final ChatEditAuditKind kind;

  /// 给人看的一句话（直接上编辑卡）。**必须具体**：说清「你说的」与
  /// 「提议的」，否则用户不知道该怎么改。
  final String message;
}

/// 提案审查的**接口**（控制器只认它，不碰任何仓储）。
///
/// 实现是 [ChatEditProposalAudit]；null 实现 = 未接线，卡片不显示审查警告。
abstract interface class ChatEditAuditor {
  Future<List<ChatEditAuditWarning>> audit({
    required String userText,
    required List<ChatEditCommand> commands,
  });
}

/// **提案审查器**（2026-10-24 用户：「要有自己的去重和检测遗漏的机制」）。
///
/// 用户原话：「确保 ai 能正确合理的调用所有功能，而且不会出错，比如我要晚餐，
/// 给我午餐，漏掉食物或者重复食物等」。
///
/// ## 设计原则：**只标注，绝不改数据**
///
/// 模型给的东西可以错，但 App **不能替用户悄悄改**：
/// * 静默改餐次 = 用户以为记的是晚餐、实际记的是别的；
/// * 静默补食物 = App 凭空写一条用户没说的记录；
/// * 静默丢重复 = 用户不知道模型重复了（克数可能取错）。
///
/// 所以这里只产出**警告**，由页面显示在卡片上，让用户在点「应用」前看见。
///
/// ## 三类检查
///
/// 1. **餐次不符**：用户句话里明确说了餐次（晚饭/午餐/早饭…），提议的 `slot`
///    与它不一致 ⇒ 警告。用户没提餐次时**不猜**（那会误报）。
/// 2. **重复食物**：同一餐次里同名食物出现多次（同一批提议内部）⇒ 警告。
///    跨餐次的同名**不算**重复——用户可能午饭晚饭都吃米饭。
/// 3. **疑似遗漏**：用户这句话里点名的食物（在食物库里能查到的），在提议的
///    `items` 里找不到 ⇒ 警告。同批提议里 `food.create` 了的新食物不算遗漏。
///
/// 全部检查都是**保守的**：宁可漏报，不可误报——误报会让用户不再相信警告。
final class ChatEditProposalAudit implements ChatEditAuditor {
  const ChatEditProposalAudit({
    required this.userText,
    required this.commands,
    required this.foodRepository,
    required this.mealRepository,
    required this.clock,
  });

  /// 用户这一轮说的话（用来判断「说了晚餐」「说了鸡蛋」）。
  final String userText;

  /// 这一批提议里的命令（已通过参数校验）。
  final List<ChatEditCommand> commands;

  final FoodRepository foodRepository;
  final MealRepository mealRepository;
  final AppClock clock;

  /// 接口实现：控制器用它（不关心内部三类检查怎么写）。
  @override
  Future<List<ChatEditAuditWarning>> audit({
    required String userText,
    required List<ChatEditCommand> commands,
  }) => ChatEditProposalAudit(
    userText: userText,
    commands: commands,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    clock: clock,
  ).run();

  /// 实际执行三类检查。
  Future<List<ChatEditAuditWarning>> run() async {
    final warnings = <ChatEditAuditWarning>[];
    final mealCreates = [
      for (final command in commands)
        if (command.action == 'meal.create') command,
    ];
    if (mealCreates.isEmpty) return warnings;

    final expectedSlot = _slotMentionedIn(userText);
    final createdFoods = {
      for (final command in commands)
        if (command.action == 'food.create')
          (command.args['name'] as String? ?? '').trim(),
    };

    // ① 餐次不符
    if (expectedSlot != null) {
      for (final command in mealCreates) {
        final slot = _asSlot(command.args['slot']);
        if (slot == null || slot == expectedSlot) continue;
        warnings.add(
          ChatEditAuditWarning(
            kind: ChatEditAuditKind.slotMismatch,
            message:
                '你说的是${_slotLabel(expectedSlot)}，但这条提议记到'
                '${_slotLabel(slot)}——应用前请确认要改餐次还是就这样记。',
          ),
        );
        break; // 同一类问题只说一次，不刷屏
      }
    }

    // ② 重复食物（**按餐次分组**：跨餐次同名不算重复）
    final seenBySlot = <String, Set<String>>{};
    final duplicated = <String>{};
    for (final command in mealCreates) {
      final slotLabel = _asSlot(command.args['slot'])?.label ?? '这一餐';
      final names = seenBySlot.putIfAbsent(slotLabel, () => <String>{});
      for (final item in _itemsOf(command)) {
        final name = _normalizeName(item.food);
        if (name.isEmpty) continue;
        if (!names.add(name)) duplicated.add(item.food);
      }
    }
    if (duplicated.isNotEmpty) {
      warnings.add(
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.duplicateFood,
          message:
              '同一餐里重复提到了${duplicated.map((n) => '「$n」').join('、')}'
              '——应用时会按一条记，克数以先出现的为准。',
        ),
      );
    }

    // ③ 疑似遗漏
    final proposedNames = {
      for (final command in mealCreates)
        for (final item in _itemsOf(command)) _normalizeName(item.food),
    };
    final mentioned = await _foodsMentionedIn(userText);
    final missing = [
      for (final food in mentioned)
        if (!proposedNames.contains(_normalizeName(food.name)) &&
            !_anyMentions(createdFoods, food.name))
          food,
    ];
    if (missing.isNotEmpty) {
      warnings.add(
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.missingFood,
          message:
              '你提到了${missing.map((f) => '「${f.name}」').join('、')}，'
              '但这条提议里没有——确认是漏了，还是这次只记别的。',
        ),
      );
    }

    // ④ 份量离谱（2026-10-24 补上轮局限）
    final outliers = <({String food, double grams})>[];
    for (final command in mealCreates) {
      for (final item in _itemsOf(command)) {
        if (item.grams > kImplausiblePortionGrams) outliers.add(item);
      }
    }
    if (outliers.isNotEmpty) {
      warnings.add(
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.implausiblePortion,
          message:
              '份量看起来偏大：'
              '${outliers.map((o) => '「${o.food}」${o.grams.round()}g').join('、')}'
              '（单条食物通常不超过 ${kImplausiblePortionGrams.round()}g）。'
              '应用后可以再改克数。',
        ),
      );
    }

    // ⑤ 非常规餐次说法（2026-10-24 补上轮局限）
    //
    // 词表外的说法（「睡前那顿」「下午那顿」）认不出是哪一餐。**不报餐次
    // 不符**（那是瞎猜），但值得提醒一句「我按 X 记的，不对就改」，
    // 免得用户以为 App 知道「睡前那顿」指哪一餐。
    if (expectedSlot == null && _hasVagueSlotWord(userText)) {
      final proposed = _asSlot(mealCreates.first.args['slot']);
      if (proposed != null) {
        warnings.add(
          ChatEditAuditWarning(
            kind: ChatEditAuditKind.vagueSlot,
            message:
                '你把这一顿叫「${_vagueSlotWordIn(userText)}」，'
                '我不确定是哪一餐，按${_slotLabel(proposed)}记的——'
                '不对的话应用前改一下。',
          ),
        );
      }
    }

    return warnings;
  }

  /// 这是不是一句「说不出具体哪一餐」的话。
  static bool _hasVagueSlotWord(String text) =>
      _vagueSlotWordIn(text).isNotEmpty;

  /// 取出那句模糊说法（用于提示文案）；没有返回空串。
  static String _vagueSlotWordIn(String text) {
    for (final word in _vagueSlotWords) {
      if (text.contains(word)) return word;
    }
    return '';
  }

  /// 「说了，但不是标准餐次词」的说法。
  ///
  /// 刻意只收**明确指一顿饭**的说法；「饿了」「想吃」这种不算（那可能
  /// 只是随口一说，提醒反而烦）。
  static const List<String> _vagueSlotWords = [
    '睡前那顿',
    '睡前',
    '下午那顿',
    '下午',
    '宵夜',
    '半夜',
    '刚那顿',
    '这一顿',
    '随便一顿',
    '中间那顿',
  ];

  /// 用户句话里明确说的餐次；没提 → null（**不猜**）。
  MealSlot? _slotMentionedIn(String text) {
    // 顺序有意义：「早饭/早上」这类先判，「晚餐/晚饭/晚上」…；同一句里
    // 出现多个（「午饭和晚饭」）时**不判定**——那是两餐，单条 meal.create
    // 本来就该被拆开，报餐次不符只会制造噪音。
    final hits = <MealSlot>[];
    for (final entry in _slotKeywords.entries) {
      if (text.contains(entry.key)) hits.add(entry.value);
    }
    final unique = hits.toSet();
    if (unique.length != 1) return null;
    return unique.single;
  }

  /// 中文/英文餐次词 → [MealSlot]。识别不了返回 null。
  ///
  /// 命令参数在校验阶段已归一成 `storedValue`（见 `ChatEditArgType.mealSlot`），
  /// 所以这里只需要认 storedValue；认不出就不判（**不猜**）。
  MealSlot? _asSlot(Object? raw) {
    if (raw is! String) return null;
    for (final slot in MealSlot.values) {
      if (raw.trim() == slot.storedValue || raw.trim() == slot.label) {
        return slot;
      }
    }
    return null;
  }

  /// 从这句话里找出「食物库里真实存在的食物名」。
  ///
  /// 做法：把句子按常见连接词/标点切开，逐段去食物库精确查（含别名）。
  /// **只在库里有精确同名时才认为用户点的是那个食物**——否则「随便吃点」
  /// 这类会一路误报。
  Future<List<FoodRecord>> _foodsMentionedIn(String text) async {
    final out = <FoodRecord>[];
    final seen = <String>{};
    for (final token in _tokenize(text)) {
      if (token.length < 2) continue;
      final hits = await foodRepository.searchExact(token);
      for (final food in hits) {
        final name = _normalizeName(food.name);
        if (name.isEmpty || !seen.add(name)) continue;
        // 别名命中也算：用户说「鸡蛋」库里叫「鸡蛋（熟）」时，searchExact
        // 会通过别名命中——那条就该被认为「用户提到了」。
        out.add(food);
      }
    }
    return out;
  }

  /// 把一句话切成候选食物名：按标点/连接词/量词切，保留 2–8 字的中文片段。
  ///
  /// 这是**保守的启发式**，不是 NLP：宁可切不出来（少报），也不乱切（误报）。
  List<String> _tokenize(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[，,。.、；;：:！!？?（）()【】\[\]"“”]'), ' ')
        .replaceAll(RegExp(r'(还有|另外|以及|再加|加上|然后|和|跟|与)'), ' ')
        .replaceAll(
          RegExp(r'[0-9]+(\.[0-9]+)?\s*(g|G|克|毫升|ml|ML|个|只|碗|杯|份|片|根|块)'),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'(吃了|喝了|吃|喝|了|我|今天|昨天|早上|中午|晚上|早饭|午饭|晚饭|早餐|午餐|晚餐|加餐|夜宵|的|点|一|两|三|四|五|半)',
          ),
          ' ',
        );
    return [
      for (final part in cleaned.split(RegExp(r'\s+')))
        if (part.trim().length >= 2 && part.trim().length <= 8) part.trim(),
    ];
  }

  static bool _anyMentions(Set<String> created, String name) {
    final target = _normalizeName(name);
    for (final item in created) {
      if (_normalizeName(item) == target) return true;
    }
    return false;
  }

  /// 食物名归一（去空格、去括号说明、统一大小写）——「米饭（熟）」与
  /// 「米饭」在判重时视为同一个。**只用于比较**，不写回任何数据。
  static String _normalizeName(String raw) {
    var name = raw.trim();
    final paren = name.indexOf(RegExp(r'[（(]'));
    if (paren > 0) name = name.substring(0, paren);
    return name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  static String _slotLabel(MealSlot slot) => slot.label;

  static List<({String food, double grams})> _itemsOf(ChatEditCommand command) {
    final raw = command.args['items'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          (
            food: (item['food'] as String? ?? '').trim(),
            grams: (item['grams'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  /// 餐次关键词 → [MealSlot]。同一句里命中多个不同餐次时视为「没提」。
  static const Map<String, MealSlot> _slotKeywords = {
    '早餐': MealSlot.breakfast,
    '早饭': MealSlot.breakfast,
    '早上': MealSlot.breakfast,
    '午餐': MealSlot.lunch,
    '午饭': MealSlot.lunch,
    '中午': MealSlot.lunch,
    '晚餐': MealSlot.dinner,
    '晚饭': MealSlot.dinner,
    '晚上': MealSlot.dinner,
    '加餐': MealSlot.snack,
    '夜宵': MealSlot.snack,
    '零食': MealSlot.snack,
  };
}
