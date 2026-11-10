/// 旧营养数据 → 统一每 100g 主库的**纯规则层**（docs/67 §7.2、§7.3）。
///
/// 这一层不碰数据库、不读时钟、不生成 id：输入"原始行 + 来源上下文"，
/// 输出"归一值 / 待补全原因 / 保全资料 / 冲突"。数据库升级与旧 `.lfb`
/// 恢复共用同一份规则，所以它必须是纯函数，才能被夹具单独测试、
/// 也才能在两个入口上得到完全相同的结果。
///
/// **不允许的行为**（写在类型上，不写在注释里就忘）：
/// * 把"每份"值改个字段名当"每100g"；
/// * 份量未知/假设时按 100g 换算；
/// * 缺营养填零、只取区间中点；
/// * 用户手改被来源覆盖。
library;

import 'package:localfit_ai/core/nutrition/nutrition_units.dart';

/// 归一规则版本。规则变了就升版本；同一旧键重跑会重新裁决，
/// 但**不会**给同一条旧记录造出第二条主食物。
abstract final class LegacyNutritionRules {
  static const String version = 'legacy-nutrition-v1';
}

/// 归一结果。
enum LegacyOutcome {
  /// 换算成功并建立了主食物（或复用了同源主食物）。
  converted('converted'),

  /// 有证据指向已存在的主食物，直接复用。
  reused('reused'),

  /// 不能安全换算：保留原值 + 可查看的待补全原因。
  needsCompletion('needs_completion'),

  /// 同一旧键出现互相矛盾的证据；保留全部版本，交给人裁决。
  conflict('conflict');

  const LegacyOutcome(this.storedValue);

  final String storedValue;

  static LegacyOutcome fromStored(String raw) {
    for (final outcome in LegacyOutcome.values) {
      if (outcome.storedValue == raw) return outcome;
    }
    return LegacyOutcome.needsCompletion;
  }
}

/// 待补全 / 冲突的原因码（稳定字符串，界面按码翻译）。
abstract final class LegacyReasonCode {
  static const String assumedServing = 'assumed_serving';
  static const String unknownServing = 'unknown_serving';
  static const String missingFields = 'missing_fields';
  static const String rangeOnly = 'range_only';
  static const String invalidValue = 'invalid_value';
  static const String duplicateSourceDivergent = 'duplicate_source_divergent';
  static const String duplicateConfirmedMatch = 'duplicate_confirmed_match';
  static const String danglingSource = 'dangling_source';
  static const String sourceChanged = 'source_changed';
  static const String unanalyzed = 'unanalyzed';
  static const String userEditedPreserved = 'user_edited_preserved';
  static const String explicitPer100g = 'explicit_per100g';
  static const String convertedFromServing = 'converted_from_serving';
  static const String fromCanteenEvidence = 'from_canteen_evidence';

  /// 给用户看的默认说明（界面可覆盖成更具体的文案）。
  static String describe(String? code) => switch (code) {
    assumedServing => '旧记录只有"一份"营养，份量是历史假设的 100g，不能据此换算每 100g。',
    unknownServing => '旧记录缺少每份克数，无法把"一份"营养换算成每 100g。',
    missingFields => '旧记录营养四项不齐，不能进入可计算主库。',
    rangeOnly => '旧记录只有热量区间、没有代表值，不取中点冒充完整营养。',
    invalidValue => '旧记录营养数值不是有限的非负数。',
    duplicateSourceDivergent => '同一来源有多条互相矛盾的旧副本，保留全部版本待确认。',
    duplicateConfirmedMatch => '同一个供应有多条已确认的食物匹配，不能猜用哪一条。',
    danglingSource => '旧记录指向的来源已不存在；数值可安全换算，按独立条目保留。',
    sourceChanged => '旧记录在上次归一之后又被改过，需要重新确认。',
    unanalyzed => '这条供应还没有营养分析，先保存为待分析。',
    userEditedPreserved => '用户手改过的营养被原样保留，未被来源同步覆盖。',
    _ => '旧记录需要补全后才能参与营养计算。',
  };
}

/// 旧菜品库行（`dish_library`）——只取规则需要的列。
final class LegacyDishRow {
  const LegacyDishRow({
    required this.id,
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.nutritionBasis,
    required this.basisAssumed,
    required this.userEdited,
    required this.source,
    this.mealSlot = 'lunch',
    this.servingGrams,
    this.fiberG,
    this.sodiumMg,
    this.vitaminDMcg,
    this.sourceType,
    this.sourceId,
    this.comment,
    this.imagePath,
    this.servingWindow,
    this.sourceUpdatedAt,
  });

  final String id;
  final String name;
  final String mealSlot;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double? fiberG;
  final double? sodiumMg;
  final double? vitaminDMcg;
  final double? servingGrams;
  final String nutritionBasis;
  final bool basisAssumed;
  final String source;
  final String? sourceType;
  final String? sourceId;
  final String? comment;
  final String? imagePath;
  final String? servingWindow;
  final DateTime? sourceUpdatedAt;
  final bool userEdited;
}

/// 食堂供应的营养证据（`menu_item_nutrition_evidence`，已是每 100g）。
final class LegacyCanteenEvidence {
  const LegacyCanteenEvidence({
    required this.origin,
    required this.grade,
    this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.kcalMin,
    this.kcalMax,
    this.sourceText,
  });

  final String origin;
  final String grade;
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? kcalMin;
  final double? kcalMax;
  final String? sourceText;

  bool get isComplete => isCompleteNutrition(
    kcalPer100g: kcalPer100g,
    proteinPer100g: proteinPer100g,
    carbsPer100g: carbsPer100g,
    fatPer100g: fatPer100g,
  );

  /// 只有区间、没有代表值。
  bool get hasRangeOnly => !isComplete && (kcalMin != null || kcalMax != null);
}

/// 归一后的主食物草稿（每 100g）。
final class LegacyMasterDraft {
  const LegacyMasterDraft({
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.origin,
    required this.isEstimated,
    required this.nutritionBasis,
    required this.basisServingGrams,
    required this.basisAssumed,
    required this.rawValuesJson,
    this.fiberPer100g,
    this.sodiumMgPer100g,
    this.vitaminDMcgPer100g,
    this.cookingNote,
    this.brand,
  });

  final String name;
  final String? brand;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? fiberPer100g;
  final double? sodiumMgPer100g;
  final double? vitaminDMcgPer100g;

  /// 来源：`legacy_dish_library` / `legacy_canteen_evidence`。
  final String origin;
  final bool isEstimated;
  final String nutritionBasis;
  final double? basisServingGrams;
  final bool basisAssumed;
  final String rawValuesJson;
  final String? cookingNote;
}

/// 一条旧记录的完整裁决。
final class LegacyNutritionDecision {
  const LegacyNutritionDecision({
    required this.outcome,
    required this.fingerprint,
    required this.preservedJson,
    required this.originalBasis,
    this.reasonCode,
    this.reasonText,
    this.master,
    this.requiresVariant = false,
    this.note,
  });

  final LegacyOutcome outcome;

  /// 归一化前的稳定内容指纹；旧行被改过就必须重新裁决。
  final String fingerprint;

  /// 原始资料保全（JSON 字符串）：原值、原口径、点评、图片路径、来源。
  final String preservedJson;

  final String originalBasis;
  final String? reasonCode;
  final String? reasonText;
  final LegacyMasterDraft? master;

  /// 用户手改过的值：可以换算，但应成为变体而不是污染共享条目。
  final bool requiresVariant;

  /// 给对账看的补充说明（不影响结果）。
  final String? note;

  bool get producesMaster => master != null;
}

/// 旧菜品库行的裁决。
///
/// [duplicateSourceCopies]：同 `(sourceType, sourceId)` 的旧行数（>1 时才有
/// 合并/冲突问题）。[copiesAgree] 由调用方按数值是否一致给出。
/// [canteenEvidence]：`sourceType == 'canteen'` 时该供应的最新营养证据。
LegacyNutritionDecision decideDishLibraryLegacy({
  required LegacyDishRow row,
  LegacyCanteenEvidence? canteenEvidence,
  int duplicateSourceCopies = 1,
  bool copiesAgree = true,
  bool confirmedMatchAmbiguous = false,
  bool sourceExists = true,
}) {
  final preserved = _dishPreservedJson(row, canteenEvidence);
  final fingerprint = stableContentFingerprint(preserved);
  final basisAssumed = row.basisAssumed;

  LegacyNutritionDecision fail(
    LegacyOutcome outcome,
    String reasonCode, {
    String? note,
  }) => LegacyNutritionDecision(
    outcome: outcome,
    fingerprint: fingerprint,
    preservedJson: preserved,
    originalBasis: row.nutritionBasis,
    reasonCode: reasonCode,
    reasonText: LegacyReasonCode.describe(reasonCode),
    note: note,
  );

  // ── I 类：非法值（四项必须有限且非负）────────────────────────────────
  if (!isCompleteNutrition(
    kcalPer100g: row.kcal,
    proteinPer100g: row.proteinG,
    carbsPer100g: row.carbsG,
    fatPer100g: row.fatG,
  )) {
    return fail(LegacyOutcome.needsCompletion, LegacyReasonCode.invalidValue);
  }

  // ── G 类：同来源多副本 ────────────────────────────────────────────────
  if (duplicateSourceCopies > 1 && !copiesAgree) {
    return fail(
      LegacyOutcome.conflict,
      LegacyReasonCode.duplicateSourceDivergent,
      note: '同来源 $duplicateSourceCopies 条副本数值不一致',
    );
  }

  // ── H 类：多重确认匹配 ────────────────────────────────────────────────
  if (confirmedMatchAmbiguous) {
    return fail(
      LegacyOutcome.conflict,
      LegacyReasonCode.duplicateConfirmedMatch,
    );
  }

  final explicitPer100g =
      NutritionBasis.tryParse(row.nutritionBasis) == NutritionBasis.per100g;

  // ── D 类：食堂来源 + 可靠的每 100g 证据 ───────────────────────────────
  if (row.sourceType == 'canteen' && (canteenEvidence?.isComplete ?? false)) {
    final evidence = canteenEvidence!;
    return LegacyNutritionDecision(
      outcome: sourceExists ? LegacyOutcome.reused : LegacyOutcome.converted,
      fingerprint: fingerprint,
      preservedJson: preserved,
      originalBasis: row.nutritionBasis,
      reasonCode: sourceExists
          ? LegacyReasonCode.fromCanteenEvidence
          : LegacyReasonCode.danglingSource,
      reasonText: sourceExists
          ? null
          : LegacyReasonCode.describe(LegacyReasonCode.danglingSource),
      requiresVariant: row.userEdited,
      master: _masterFromCanteen(row, evidence),
      note: row.userEdited ? LegacyReasonCode.userEditedPreserved : null,
    );
  }

  // ── B 类：明确原每 100g，且不是假设口径 ───────────────────────────────
  if (explicitPer100g && !basisAssumed) {
    return LegacyNutritionDecision(
      outcome: LegacyOutcome.converted,
      fingerprint: fingerprint,
      preservedJson: preserved,
      originalBasis: row.nutritionBasis,
      reasonCode: LegacyReasonCode.explicitPer100g,
      requiresVariant: row.userEdited,
      master: _masterFromPer100g(row),
    );
  }

  // ── E/F 类：每份营养，只有可信份量才能换算 ─────────────────────────────
  final servingGrams = row.servingGrams;
  final hasTrustedServing =
      !basisAssumed &&
      servingGrams != null &&
      servingGrams.isFinite &&
      servingGrams > 0 &&
      servingGrams <= NutritionLimits.maxServingGrams;

  if (!hasTrustedServing) {
    return fail(
      LegacyOutcome.needsCompletion,
      basisAssumed || servingGrams != null
          ? LegacyReasonCode.assumedServing
          : LegacyReasonCode.unknownServing,
      note: basisAssumed ? 'basisAssumed=true' : null,
    );
  }

  // ── C 类：可信每份克数 → 按公式换算四项 + 单位明确的微量 ──────────────
  final kcal = per100gFromPerServing(
    perServing: row.kcal,
    servingGrams: servingGrams,
  );
  final protein = per100gFromPerServing(
    perServing: row.proteinG,
    servingGrams: servingGrams,
  );
  final carbs = per100gFromPerServing(
    perServing: row.carbsG,
    servingGrams: servingGrams,
  );
  final fat = per100gFromPerServing(
    perServing: row.fatG,
    servingGrams: servingGrams,
  );
  if (kcal == null || protein == null || carbs == null || fat == null) {
    return fail(LegacyOutcome.needsCompletion, LegacyReasonCode.invalidValue);
  }

  return LegacyNutritionDecision(
    outcome: LegacyOutcome.converted,
    fingerprint: fingerprint,
    preservedJson: preserved,
    originalBasis: row.nutritionBasis,
    reasonCode: LegacyReasonCode.convertedFromServing,
    requiresVariant: row.userEdited,
    master: LegacyMasterDraft(
      name: row.name,
      kcalPer100g: kcal,
      proteinPer100g: protein,
      carbsPer100g: carbs,
      fatPer100g: fat,
      fiberPer100g: per100gFromPerServing(
        perServing: row.fiberG ?? 0,
        servingGrams: row.fiberG == null ? null : servingGrams,
      ),
      sodiumMgPer100g: per100gFromPerServing(
        perServing: row.sodiumMg ?? 0,
        servingGrams: row.sodiumMg == null ? null : servingGrams,
      ),
      vitaminDMcgPer100g: per100gFromPerServing(
        perServing: row.vitaminDMcg ?? 0,
        servingGrams: row.vitaminDMcg == null ? null : servingGrams,
      ),
      origin: 'legacy_dish_library',
      isEstimated: row.source == 'ai_estimate',
      nutritionBasis: row.nutritionBasis,
      basisServingGrams: servingGrams,
      basisAssumed: false,
      rawValuesJson: preserved,
    ),
    note: row.userEdited ? LegacyReasonCode.userEditedPreserved : null,
  );
}

/// 旧食堂供应的裁决：只从**每 100g 证据**建主食物，不从"每份"猜。
LegacyNutritionDecision decideSupplyLegacy({
  required String menuItemId,
  required String displayName,
  LegacyCanteenEvidence? evidence,
  required bool itemHasConfirmedMatch,
}) {
  final preserved = _supplyPreservedJson(
    menuItemId: menuItemId,
    displayName: displayName,
    evidence: evidence,
    itemHasConfirmedMatch: itemHasConfirmedMatch,
  );
  final fingerprint = stableContentFingerprint(preserved);

  LegacyNutritionDecision fail(
    LegacyOutcome outcome,
    String reasonCode,
    String originalBasis,
  ) => LegacyNutritionDecision(
    outcome: outcome,
    fingerprint: fingerprint,
    preservedJson: preserved,
    originalBasis: originalBasis,
    reasonCode: reasonCode,
    reasonText: LegacyReasonCode.describe(reasonCode),
  );

  if (evidence == null) {
    return fail(
      LegacyOutcome.needsCompletion,
      LegacyReasonCode.unanalyzed,
      'unknown',
    );
  }
  if (!evidence.isComplete) {
    return fail(
      LegacyOutcome.needsCompletion,
      evidence.hasRangeOnly
          ? LegacyReasonCode.rangeOnly
          : LegacyReasonCode.missingFields,
      'per100g',
    );
  }

  return LegacyNutritionDecision(
    outcome: LegacyOutcome.converted,
    fingerprint: fingerprint,
    preservedJson: preserved,
    originalBasis: 'per100g',
    reasonCode: LegacyReasonCode.fromCanteenEvidence,
    master: LegacyMasterDraft(
      name: displayName,
      kcalPer100g: evidence.kcalPer100g!,
      proteinPer100g: evidence.proteinPer100g!,
      carbsPer100g: evidence.carbsPer100g!,
      fatPer100g: evidence.fatPer100g!,
      origin: 'legacy_canteen_evidence',
      isEstimated: evidence.origin == 'ai_estimate',
      nutritionBasis: 'per100g',
      basisServingGrams: null,
      basisAssumed: false,
      rawValuesJson: preserved,
    ),
  );
}

LegacyMasterDraft _masterFromCanteen(
  LegacyDishRow row,
  LegacyCanteenEvidence evidence,
) => LegacyMasterDraft(
  name: row.name,
  kcalPer100g: evidence.kcalPer100g!,
  proteinPer100g: evidence.proteinPer100g!,
  carbsPer100g: evidence.carbsPer100g!,
  fatPer100g: evidence.fatPer100g!,
  origin: 'legacy_canteen_evidence',
  isEstimated: evidence.origin == 'ai_estimate',
  nutritionBasis: 'per100g',
  basisServingGrams: null,
  basisAssumed: false,
  rawValuesJson: _dishPreservedJson(row, evidence),
);

LegacyMasterDraft _masterFromPer100g(LegacyDishRow row) => LegacyMasterDraft(
  name: row.name,
  kcalPer100g: row.kcal,
  proteinPer100g: row.proteinG,
  carbsPer100g: row.carbsG,
  fatPer100g: row.fatG,
  fiberPer100g: row.fiberG,
  sodiumMgPer100g: row.sodiumMg,
  vitaminDMcgPer100g: row.vitaminDMcg,
  origin: 'legacy_dish_library',
  isEstimated: row.source == 'ai_estimate',
  nutritionBasis: row.nutritionBasis,
  basisServingGrams: row.servingGrams,
  basisAssumed: row.basisAssumed,
  rawValuesJson: _dishPreservedJson(row, null),
);

/// 稳定 JSON：键序固定、浮点用 `toString`、时间用 epoch 毫秒。
String _canonicalJson(Map<String, Object?> values) {
  final keys = values.keys.toList()..sort();
  final buffer = StringBuffer('{');
  var first = true;
  for (final key in keys) {
    if (!first) buffer.write(',');
    first = false;
    buffer
      ..write('"')
      ..write(key)
      ..write('":')
      ..write(_canonicalValue(values[key]));
  }
  buffer.write('}');
  return buffer.toString();
}

String _canonicalValue(Object? value) {
  if (value == null) return 'null';
  if (value is num) {
    if (!value.isFinite) return '"${value.toString()}"';
    return value.toString();
  }
  if (value is bool) return value.toString();
  if (value is DateTime) return value.millisecondsSinceEpoch.toString();
  if (value is Map) {
    return _canonicalJson(value.map((key, v) => MapEntry('$key', v)));
  }
  if (value is Iterable) {
    return '[${value.map(_canonicalValue).join(',')}]';
  }
  return '"${value.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

String _dishPreservedJson(LegacyDishRow row, LegacyCanteenEvidence? evidence) =>
    _canonicalJson({
      'legacyKind': 'dish_library',
      'id': row.id,
      'name': row.name,
      'mealSlot': row.mealSlot,
      // 原值按"原口径"保存——这是"每份 400 千卡"能自证的关键。
      'basis': row.nutritionBasis,
      'servingGrams': row.servingGrams,
      'basisAssumed': row.basisAssumed,
      'kcal': row.kcal,
      'proteinG': row.proteinG,
      'carbsG': row.carbsG,
      'fatG': row.fatG,
      'fiberG': row.fiberG,
      'sodiumMg': row.sodiumMg,
      'vitaminDMcg': row.vitaminDMcg,
      'source': row.source,
      'sourceType': row.sourceType,
      'sourceId': row.sourceId,
      'sourceUpdatedAt': row.sourceUpdatedAt,
      'userEdited': row.userEdited,
      'comment': row.comment,
      'imagePath': row.imagePath,
      'servingWindow': row.servingWindow,
      if (evidence != null)
        'canteenEvidence': {
          'origin': evidence.origin,
          'grade': evidence.grade,
          'kcalPer100g': evidence.kcalPer100g,
          'proteinPer100g': evidence.proteinPer100g,
          'carbsPer100g': evidence.carbsPer100g,
          'fatPer100g': evidence.fatPer100g,
          'sourceText': evidence.sourceText,
        },
    });

String _supplyPreservedJson({
  required String menuItemId,
  required String displayName,
  required LegacyCanteenEvidence? evidence,
  required bool itemHasConfirmedMatch,
}) => _canonicalJson({
  'legacyKind': 'menu_item',
  'id': menuItemId,
  'displayName': displayName,
  'hasConfirmedMatch': itemHasConfirmedMatch,
  if (evidence != null)
    'evidence': {
      'origin': evidence.origin,
      'grade': evidence.grade,
      'kcalPer100g': evidence.kcalPer100g,
      'proteinPer100g': evidence.proteinPer100g,
      'carbsPer100g': evidence.carbsPer100g,
      'fatPer100g': evidence.fatPer100g,
      'kcalMin': evidence.kcalMin,
      'kcalMax': evidence.kcalMax,
      'sourceText': evidence.sourceText,
    },
});

/// 稳定内容指纹：FNV-1a 64 位十六进制。
///
/// 用途只有"这行旧数据有没有被改过"，不需要密码学强度；选它是因为同步、
/// 无依赖、跨平台结果一致，能在纯规则层里直接算。
String stableContentFingerprint(String canonical) {
  // 两路 32 位 FNV-1a 拼接：Dart 的 int 是有符号 64 位，用 64 位掩码会溢出成
  // 负数（`0xFFFFFFFFFFFFFFFF` 在 Dart 里等于 -1）。32 位掩码是安全的，
  // 拼起来仍有 64 位空间，跨平台结果一致。
  var first = 0x811c9dc5;
  var second = 0x01000193;
  for (final unit in canonical.codeUnits) {
    first = ((first ^ unit) * 0x01000193) & 0xFFFFFFFF;
    second = ((second ^ (unit + 0x9e37)) * 0x85ebca6b) & 0xFFFFFFFF;
  }
  return first.toRadixString(16).padLeft(8, '0') +
      second.toRadixString(16).padLeft(8, '0');
}
