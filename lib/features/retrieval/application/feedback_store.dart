/// 推荐反馈闭环（docs/41 P4 / G9）：**不做静默学习**。
///
/// 用户在推荐卡上点「不错 / 换一个」就是一次显式反馈：
/// * 存**菜名级**的计数（`app_settings` KV，JSON；不新增表——`docs/41` §11
///   没有登记反馈表，硬约束要求任何结构变更单列）；
/// * 只影响**软排序**（boost/penalty），绝不硬过滤；
/// * 冷启动门槛：同一道菜至少 [kFeedbackMinSamples] 次同向反馈才生效，
///   避免一次误点就把一道菜压到看不见。
library;

import 'dart:convert';

/// 一次反馈的方向。
enum FeedbackVote {
  like('不错'),
  dislike('换一个');

  const FeedbackVote(this.label);
  final String label;
}

/// 一道菜的反馈累计。
final class DishFeedback {
  const DishFeedback({this.likes = 0, this.dislikes = 0});

  final int likes;
  final int dislikes;

  int get total => likes + dislikes;

  /// −1..1 的净偏好（样本不足时按 0 处理，不放大噪声）。
  double get score {
    if (total < kFeedbackMinSamples) return 0;
    return (likes - dislikes) / total;
  }

  Map<String, Object?> toJson() => {'l': likes, 'd': dislikes};
}

/// 生效门槛：同向反馈至少 2 次（一次点击可能只是手滑）。
const int kFeedbackMinSamples = 2;

/// `app_settings` 里的键。
const String kFeedbackStoreKey = 'recommendation_feedback';

/// 反馈存储：纯 KV + JSON，读写都在内存对象里完成，调用方负责落库。
final class FeedbackStore {
  FeedbackStore([Map<String, DishFeedback>? initial]) : _byName = {...?initial};

  final Map<String, DishFeedback> _byName;

  Map<String, DishFeedback> get entries => Map.unmodifiable(_byName);

  /// 记一次反馈（按归一化菜名累计）。
  void record(String dishName, FeedbackVote vote) {
    final key = normalizeFeedbackName(dishName);
    if (key.isEmpty) return;
    final current = _byName[key] ?? const DishFeedback();
    _byName[key] = switch (vote) {
      FeedbackVote.like => DishFeedback(
        likes: current.likes + 1,
        dislikes: current.dislikes,
      ),
      FeedbackVote.dislike => DishFeedback(
        likes: current.likes,
        dislikes: current.dislikes + 1,
      ),
    };
  }

  /// 某道菜的净偏好（−1..1；样本不足 = 0）。
  double scoreOf(String dishName) =>
      _byName[normalizeFeedbackName(dishName)]?.score ?? 0;

  /// 检索 boost：偏好 +5%、不喜欢 ×0.85（与 `applyBoosts` 的量级一致）。
  double multiplierFor(String dishName) {
    final score = scoreOf(dishName);
    if (score >= 0.5) return 1.05;
    if (score <= -0.5) return 0.85;
    return 1;
  }

  String encode() => jsonEncode({
    for (final entry in _byName.entries) entry.key: entry.value.toJson(),
  });

  static FeedbackStore decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return FeedbackStore();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return FeedbackStore();
      final out = <String, DishFeedback>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final likes = (value['l'] as num?)?.toInt() ?? 0;
        final dislikes = (value['d'] as num?)?.toInt() ?? 0;
        if (likes < 0 || dislikes < 0) return;
        out[key] = DishFeedback(likes: likes, dislikes: dislikes);
      });
      return FeedbackStore(out);
    } on FormatException {
      return FeedbackStore();
    }
  }
}

/// 与检索/口味画像同一套归一化（全半角、空白、大小写）。
String normalizeFeedbackName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u3000]+'), '')
    .replaceAll(RegExp(r'''[，。！？、；：,.!?;:（）()「」“”"'`]'''), '');
