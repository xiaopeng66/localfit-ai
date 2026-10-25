import 'dart:convert';

import 'package:localfit_ai/core/time/local_date.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealSlot;

/// chat-edit v1（docs/23）的参数类型。
///
/// 只收「能机械验证」的类型：每个类型都有唯一的归一化规则与错误文案，
/// decoder 与 executor 共用，不让两处各写一套判断漂移掉。
enum ChatEditArgType {
  /// 非空短文本（名字/说明），trim 后 1–300 字符。
  string,

  /// 有限数（NaN/Infinity/布尔都拒绝），带可选 [ChatEditArgSpec.min]/[max]。
  number,

  /// 整数（JSON 里的 `3.0` 也接受，归一成 int）。
  integer,

  boolean,

  /// 非空字符串列表（规划约束的标签/过敏原）。
  stringList,

  /// 用料列表：元素必须是 `{"food": 文本, "grams": 数字}`（餐记录用）。
  foodItems,

  /// 训练计划的天列表（docs/32 §4 T6b / §3 D5）：
  /// 元素必须是 `{"weekday":1–7, "entries":[{"exercise":文本,"sets":正整数,
  /// "reps":正整数,"weightKg":可选非负}]}`；≤7 天、每天 1–20 条。
  planDays,

  /// 餐次：接受 `breakfast/lunch/dinner/snack` 或中文，归一成 storedValue。
  mealSlot,

  /// ISO 本地日 `yyyy-MM-dd`（唯一事实源 `isValidIsoLocalDate`）。
  localDate,

  /// 健康目标：`loseFat/maintain/gainMuscle` 或中文。
  goal,

  /// `HH:mm`（24 小时制）。
  time,
}

/// 一个参数的声明：类型 + 必填 + 区间。注册表用它校验，prompt 用它渲染。
final class ChatEditArgSpec {
  const ChatEditArgSpec({
    required this.name,
    required this.type,
    required this.required,
    this.min,
    this.max,
    this.hint,
    this.maxLength,
    this.jsonObjectAllowed = false,
  });

  final String name;
  final ChatEditArgType type;
  final bool required;
  final num? min;
  final num? max;

  /// `string` 型**是否同时收 JSON 对象/数组**（缺省 false）。
  ///
  /// 2026-10-15 真实 AI 测得：承载结构化载荷的参数（`menu.snapshot.publish`
  /// 的 `menuJson`），模型会**直接发对象**而不是转义后的字符串（实测 GLM-5.3
  /// 就这么发，被「要是文本」挡下）。开这一档 ⇒ 收到 Map/List 时
  /// `jsonEncode` 成文本再走同一套长度/非空校验；字符串形态照旧。
  final bool jsonObjectAllowed;

  /// `string` 型的长度上限（**缺省 300**，与历史口径一致）。
  /// 只有「承载结构化 JSON 的单个字符串参数」才需要放宽（批次 B 的
  /// `menu.snapshot.publish`：菜单草案本身就是一段 JSON 文本）。
  final int? maxLength;

  /// 渲染进 system prompt 的参数说明（中文，一句话）。
  final String? hint;
}

/// 命令的破坏力分级，编辑卡按它决定文案口吻（删除类加「不可恢复」提示）。
enum ChatEditDanger { create, update, delete }

/// 一条命令的静态声明（docs/23 §2 注册表的行）。
final class ChatEditCommandSpec {
  const ChatEditCommandSpec({
    required this.action,
    required this.title,
    required this.danger,
    required this.args,
    required this.summarize,
  });

  final String action;
  final String title;
  final ChatEditDanger danger;
  final List<ChatEditArgSpec> args;

  /// 把归一化后的参数压成一行中文摘要（编辑卡每行显示用）。
  final String Function(Map<String, Object> args) summarize;

  ChatEditArgSpec? specOf(String name) {
    for (final spec in args) {
      if (spec.name == name) return spec;
    }
    return null;
  }
}

/// 参数校验失败的异常；`message` 是给人看的中文（直接上编辑卡）。
final class ChatEditArgsException implements Exception {
  const ChatEditArgsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一条已通过校验的命令：参数已按 [ChatEditArgType] 归一化。
final class ChatEditCommand {
  const ChatEditCommand({required this.spec, required this.args});

  final ChatEditCommandSpec spec;
  final Map<String, Object> args;

  String get action => spec.action;

  String summarize() => spec.summarize(args);
}

/// 校验并归一化一条命令的参数。
///
/// 规则（docs/23 §1）：未知参数报错（抓模型幻觉）；可选参数缺省即跳过；
/// 单条失败抛 [ChatEditArgsException]，由调用方变成该行的失败原因。
Map<String, Object> validateChatEditArgs(
  ChatEditCommandSpec spec,
  Map<Object?, Object?> rawArgs,
) {
  final normalized = <String, Object>{};
  for (final entry in rawArgs.entries) {
    final key = entry.key;
    if (key is! String || spec.specOf(key) == null) {
      throw ChatEditArgsException('参数「$key」不是「${spec.action}」认识的参数。');
    }
  }
  for (final argSpec in spec.args) {
    final raw = rawArgs[argSpec.name];
    if (raw == null) {
      if (argSpec.required) {
        throw ChatEditArgsException('缺少必填参数「${argSpec.name}」。');
      }
      continue;
    }
    normalized[argSpec.name] = _normalizeValue(argSpec, raw);
  }
  return normalized;
}

/// 归一化一条用料 `{"food": 文本, "grams": 数字}`；多余键忽略（模型常带
/// `unit` 之类说明，无伤大雅），缺键/类型不对报错。
Map<String, Object> _normalizeFoodItem(String argName, Object raw) {
  if (raw is! Map) {
    throw ChatEditArgsException('参数「$argName」的每条用料要是 {"food":…,"grams":…}。');
  }
  final food = raw['food'];
  final grams = raw['grams'];
  if (food is! String || food.trim().isEmpty) {
    throw ChatEditArgsException('参数「$argName」里有用料缺食物名。');
  }
  if (grams is! num || !grams.isFinite || grams < 0.1 || grams > 5000) {
    throw ChatEditArgsException('参数「$argName」里的克数要在 0.1–5000 之间。');
  }
  return {'food': food.trim(), 'grams': grams.toDouble()};
}

/// 归一化训练计划的一天（docs/32 §4 T6b）。
///
/// 机械校验（不依赖动作库存在性——那是 executor 的第二次把关）：
/// `weekday` 整数 1–7；`entries` 1–20 条；每条 `exercise` 非空文本、
/// `sets`/`reps` 正整数、`weightKg` 可选且非负。
Map<String, Object> _normalizePlanDay(String argName, Object raw) {
  if (raw is! Map) {
    throw ChatEditArgsException(
      '参数「$argName」的每一天要是 {"weekday":1–7,"entries":[…]}。',
    );
  }
  final weekday = raw['weekday'];
  if (weekday is! num ||
      !weekday.isFinite ||
      weekday != weekday.roundToDouble() ||
      weekday < 1 ||
      weekday > 7) {
    throw ChatEditArgsException('参数「$argName」里的 weekday 要是 1–7 的整数。');
  }
  final entries = raw['entries'];
  if (entries is! List || entries.isEmpty) {
    throw ChatEditArgsException('参数「$argName」里每天至少要有一条动作。');
  }
  if (entries.length > 20) {
    throw ChatEditArgsException('参数「$argName」里每天最多 20 条动作。');
  }
  return {
    'weekday': weekday.toInt(),
    'entries': [
      for (final entry in entries) _normalizePlanEntry(argName, entry),
    ],
  };
}

Map<String, Object> _normalizePlanEntry(String argName, Object raw) {
  if (raw is! Map) {
    throw ChatEditArgsException(
      '参数「$argName」里的每条动作要是 {"exercise":文本,"sets":…,"reps":…}。',
    );
  }
  final exercise = raw['exercise'];
  if (exercise is! String || exercise.trim().isEmpty) {
    throw ChatEditArgsException('参数「$argName」里有动作缺名称。');
  }
  final sets = raw['sets'];
  if (sets is! num ||
      !sets.isFinite ||
      sets != sets.roundToDouble() ||
      sets < 1 ||
      sets > 99) {
    throw ChatEditArgsException('参数「$argName」里每条动作的 sets 要是 1–99 的整数。');
  }
  final reps = raw['reps'];
  if (reps is! num ||
      !reps.isFinite ||
      reps != reps.roundToDouble() ||
      reps < 1 ||
      reps > 999) {
    throw ChatEditArgsException('参数「$argName」里每条动作的 reps 要是 1–999 的整数。');
  }
  final out = <String, Object>{
    'exercise': exercise.trim(),
    'sets': sets.toInt(),
    'reps': reps.toInt(),
  };
  if (raw.containsKey('weightKg')) {
    final weight = raw['weightKg'];
    if (weight is! num || !weight.isFinite || weight < 0 || weight > 500) {
      throw ChatEditArgsException('参数「$argName」里每条动作的 weightKg 要在 0–500 之间。');
    }
    out['weightKg'] = weight.toDouble();
  }
  return out;
}

Object _normalizeValue(ChatEditArgSpec spec, Object raw) {
  switch (spec.type) {
    case ChatEditArgType.string:
      final Object? rawText = switch (raw) {
        String _ => raw,
        Map _ || List _ when spec.jsonObjectAllowed => jsonEncode(raw),
        _ => null,
      };
      if (rawText is! String) {
        throw ChatEditArgsException('参数「${spec.name}」要是文本。');
      }
      final text = rawText.trim();
      if (text.isEmpty) {
        throw ChatEditArgsException('参数「${spec.name}」不能为空。');
      }
      final limit = spec.maxLength ?? 300;
      if (text.length > limit) {
        throw ChatEditArgsException('参数「${spec.name}」太长（最多 $limit 字）。');
      }
      return text;
    case ChatEditArgType.number:
      if (raw is! num) {
        throw ChatEditArgsException('参数「${spec.name}」要是数字。');
      }
      final value = raw.toDouble();
      if (!value.isFinite) {
        throw ChatEditArgsException('参数「${spec.name}」不是有限数字。');
      }
      return _checkRange(spec, value);
    case ChatEditArgType.integer:
      if (raw is! num || !raw.isFinite) {
        throw ChatEditArgsException('参数「${spec.name}」要是有限数字。');
      }
      if (raw != raw.roundToDouble()) {
        throw ChatEditArgsException('参数「${spec.name}」要是整数。');
      }
      return _checkRange(spec, raw.toInt());
    case ChatEditArgType.boolean:
      if (raw is! bool) {
        throw ChatEditArgsException('参数「${spec.name}」要是 true/false。');
      }
      return raw;
    case ChatEditArgType.stringList:
      if (raw is! List) {
        throw ChatEditArgsException('参数「${spec.name}」要是列表。');
      }
      if (raw.length > 20) {
        throw ChatEditArgsException('参数「${spec.name}」最多 20 项。');
      }
      return [
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    case ChatEditArgType.foodItems:
      if (raw is! List) {
        throw ChatEditArgsException('参数「${spec.name}」要是列表。');
      }
      if (raw.isEmpty) {
        throw ChatEditArgsException('参数「${spec.name}」不能为空。');
      }
      if (raw.length > 20) {
        throw ChatEditArgsException('参数「${spec.name}」最多 20 条用料。');
      }
      return [for (final item in raw) _normalizeFoodItem(spec.name, item)];
    case ChatEditArgType.planDays:
      if (raw is! List) {
        throw ChatEditArgsException('参数「${spec.name}」要是列表。');
      }
      if (raw.isEmpty) {
        throw ChatEditArgsException('参数「${spec.name}」不能为空。');
      }
      if (raw.length > 7) {
        throw ChatEditArgsException('参数「${spec.name}」最多 7 天。');
      }
      return [for (final day in raw) _normalizePlanDay(spec.name, day)];
    case ChatEditArgType.mealSlot:
      final slot = parseChatEditMealSlot(raw, spec.name);
      return slot.storedValue;
    case ChatEditArgType.localDate:
      if (raw is! String || !isValidIsoLocalDate(raw)) {
        throw ChatEditArgsException('参数「${spec.name}」要是 yyyy-MM-dd 格式的日期。');
      }
      return raw;
    case ChatEditArgType.goal:
      return parseChatEditGoal(raw, spec.name);
    case ChatEditArgType.time:
      if (raw is! String || !RegExp(r'^\d{2}:\d{2}$').hasMatch(raw.trim())) {
        throw ChatEditArgsException('参数「${spec.name}」要是 HH:mm 格式的时间。');
      }
      final parts = raw.trim().split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour > 23 || minute > 59) {
        throw ChatEditArgsException('参数「${spec.name}」不是合法的 24 小时制时间。');
      }
      return raw.trim();
  }
}

num _checkRange(ChatEditArgSpec spec, num value) {
  final min = spec.min;
  final max = spec.max;
  if (min != null && value < min) {
    throw ChatEditArgsException('参数「${spec.name}」不能小于 $min。');
  }
  if (max != null && value > max) {
    throw ChatEditArgsException('参数「${spec.name}」不能大于 $max。');
  }
  return value;
}

/// 餐次宽容解析：英文 storedValue 与中文都认，其余报错（不猜）。
MealSlot parseChatEditMealSlot(Object raw, String argName) {
  final text = raw is String ? raw.trim() : '';
  for (final slot in MealSlot.values) {
    if (text == slot.storedValue || text == slot.label) return slot;
  }
  if (text == '早饭') return MealSlot.breakfast;
  if (text == '午饭') return MealSlot.lunch;
  if (text == '晚饭' || text == '宵夜') {
    return text == '晚饭' ? MealSlot.dinner : MealSlot.snack;
  }
  throw ChatEditArgsException('参数「$argName」要是早餐/午餐/晚餐/加餐。');
}

/// 健康目标宽容解析（`ProfileIdentityRepository.updateGoal` 的枚举名）。
String parseChatEditGoal(Object raw, String argName) {
  final text = raw is String ? raw.trim() : '';
  const english = {'loseFat', 'maintain', 'gainMuscle'};
  if (english.contains(text)) return text;
  const chinese = {'减脂': 'loseFat', '维持': 'maintain', '增肌': 'gainMuscle'};
  final mapped = chinese[text];
  if (mapped != null) return mapped;
  throw ChatEditArgsException('参数「$argName」要是 减脂/维持/增肌。');
}
