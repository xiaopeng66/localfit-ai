/// 食物详情读模型（2.0-1j）：docs/07 §5.5 的三个实体——份量、营养修订、来源
/// 证据——导入之后要能被应用读回来。
///
/// 这里只做「如实转述」：缺数据就是空列表 / null，读路径不补默认份量、不替
/// 不完整修订填数字（那些会在界面上变成用户以为存在的事实）。
library;

/// 一条份量换算（个/碗/勺/袋…）。
final class FoodPortionOption {
  const FoodPortionOption({
    required this.id,
    required this.name,
    required this.grams,
    required this.locale,
    required this.source,
  });

  final String id;
  final String name;
  final double grams;
  final String locale;

  /// 份量的来源（目录数据 = 上游 sourceId；用户自建 = user）。
  final String source;
}

/// 一条营养修订。四项营养均可空：不完整修订照样读出来，但要能看出不完整。
final class FoodRevisionRecord {
  const FoodRevisionRecord({
    required this.id,
    required this.revisionNumber,
    required this.qualityStatus,
    this.createdAt,
    this.kcalPer100g,
    this.proteinGPer100g,
    this.carbsGPer100g,
    this.fatGPer100g,
    this.sourceEvidenceId,
    this.validFrom,
  });

  final String id;
  final int revisionNumber;
  final double? kcalPer100g;
  final double? proteinGPer100g;
  final double? carbsGPer100g;
  final double? fatGPer100g;

  /// 指向 [FoodEvidenceRecord.id] 的证据行；可为空（种子/用户自建没有证据行）。
  final String? sourceEvidenceId;

  /// ok | incomplete | …
  final String qualityStatus;
  final DateTime? validFrom;

  /// 入库时间。分片里的 revisions 只带 `valid_from`（ETL 不写 created_at），
  /// 所以从分片读出来的修订这里是 null——不拿「现在」冒充入库时间。
  final DateTime? createdAt;

  /// 四项齐全才算可用于严格营养计算（与 `foods.state` 的判据一致）。
  bool get isMacroComplete =>
      kcalPer100g != null &&
      proteinGPer100g != null &&
      carbsGPer100g != null &&
      fatGPer100g != null;
}

/// 一条目录级来源证据：许可证、采集时间、转换版本与原始记录哈希。
final class FoodEvidenceRecord {
  const FoodEvidenceRecord({
    required this.id,
    required this.sourceId,
    required this.license,
    required this.retrievedAt,
    required this.transformVersion,
    required this.qualityStatus,
    required this.recordHash,
    this.attribution,
  });

  final String id;
  final String sourceId;
  final String license;
  final String? attribution;
  final DateTime retrievedAt;
  final String transformVersion;
  final String qualityStatus;

  /// 原始记录（归一化前的 JSON）的 sha256 十六进制串。
  final String recordHash;

  /// 界面上只显示前 12 位：整串 64 位在窄屏会折行，用户要核对时用完整值。
  String get recordHashShort =>
      recordHash.length <= 12 ? recordHash : '${recordHash.substring(0, 12)}…';
}

/// 一个食物的详情：主表数值 + 三个实体。
final class FoodDetail {
  const FoodDetail({
    required this.foodId,
    required this.name,
    required this.state,
    required this.source,
    required this.licenseStatus,
    required this.isUserCreated,
    required this.canJoinPlan,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.brand,
    this.category,
    this.defaultServingGrams,
    this.portions = const [],
    this.latestRevision,
    this.evidence,
  });

  final String foodId;
  final String name;
  final String? brand;
  final String? category;

  /// verified | estimated | incomplete | user_created | stale。
  final String state;

  /// 上游/种子来源 id（如 openfoodfacts、user）。
  final String source;
  final String licenseStatus;
  final bool isUserCreated;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? defaultServingGrams;

  /// 按克数升序（同克数按名称），装载器已排好，界面照序渲染。
  final List<FoodPortionOption> portions;

  /// 编号最大的那条修订（同编号取最新创建的那条）。
  final FoodRevisionRecord? latestRevision;

  /// 最新修订指回的证据行。
  final FoodEvidenceRecord? evidence;

  bool get hasPortions => portions.isNotEmpty;
  bool get hasRevision => latestRevision != null;
  bool get hasEvidence => evidence != null;

  /// docs/07 §9.3：incomplete 行可搜索但不能加入确认计划。
  ///
  /// **2026-10-15（用户批准的裁决 ①）由 getter 改成显式字段**：原来的 getter
  /// 拿 `state` 当质量判据，而 `state` 里的 `user_created` 是**来源**值——
  /// 主库行（用户自建 / CSV 导入）落库即 `user_created`，于是「四值齐的自建
  /// 食物」在详情里被判成不可加入，与列表卡（`_fromMainRow` 对主库行恒 true）
  /// 两屏打架。现在规则**逐来源**给，与卡侧同源：
  ///  * 主库来源（`food_detail_repository.dart`）⇒ `true`（四值必填 = 完整）；
  ///  * 目录分片来源（`catalog_shard_detail_source.dart`）⇒ 上游质量档
  ///    （`verified | estimated`，与 `CatalogSearchRow.canJoinPlan` 同一规则）。
  final bool canJoinPlan;

  /// 与主表默认份量对得上的那行份量（记餐时用的就是 `defaultServingGrams`）。
  ///
  /// 容差 0.5g：份量是上游给的十进制数，主表可能经过换算，不该要求逐位相等。
  /// 对不上就返回 null——界面上不标「默认」，也不替用户挑一行。
  FoodPortionOption? get defaultPortion {
    final target = defaultServingGrams;
    if (target == null) return null;
    for (final portion in portions) {
      if ((portion.grams - target).abs() <= 0.5) return portion;
    }
    return null;
  }
}
