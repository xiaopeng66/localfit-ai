import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/text/search_text.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_name_format.dart';
import 'package:localfit_ai/features/nutrition/data/food_revision_writer.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_write_failure.dart';

final class FoodRepository implements LocalFoodSearch {
  const FoodRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  Stream<void> watchChanges() => database
      .tableUpdates(TableUpdateQuery.onTable(database.foods))
      .map((_) {});

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) =>
      page(query: query, offset: 0, limit: limit);

  /// 主库**条数**（docs/28 §8.2）：滑条长度与顶部「全部 N 条」都读它，
  /// 所以它是 `COUNT(*)` 的真实值，不是「已加载条数」。
  ///
  /// [category] 非空时只数该分类（Round7 阶段 3 的食物库分类行）：判据是
  /// **落库的枚举 id**，不是按名字猜。没落库分类的行（旧数据、目录分片原串）
  /// 不属于任何分类——它们只在「全部」里出现。
  Future<int> count({FoodCategory? category}) async {
    final total = database.foods.id.count();
    final query = database.selectOnly(database.foods)..addColumns([total]);
    if (category != null) {
      query.where(database.foods.category.equals(category.id));
    }
    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// 取第 [offset] 条起的 [limit] 条（docs/28 §8.2）。分页用 `LIMIT/OFFSET`
  /// 而不是 keyset：滑条要能拖到任意位置，keyset 跳不了随机页。
  ///
  /// 排序**每一档都以 `id ASC` 收尾**。名称可重复（食物库数万条里同名的
  /// 不少），没有唯一键时 `LIMIT/OFFSET` 在值相等的行之间顺序不保证稳定 ⇒
  /// 翻页会漏行或同一行出现两次（§1.12 的陷阱）。
  ///
  /// [category] 是**可选**的追加条件（分类与查询词同时生效），默认 `null`
  /// 时这条 SQL 与加它之前一字不差。`foods.category` 上没有索引（加索引 =
  /// 改库结构，不在本片范围）——分类页是「过滤 + 排序 + LIMIT/OFFSET」，
  /// 20k 量级的实测护栏在 `test/features/nutrition/query_benchmark_test.dart`。
  Future<List<FoodRecord>> page({
    String query = '',
    required int offset,
    required int limit,
    FoodCategory? category,
  }) async {
    final normalized = query.trim();
    final statement = database.select(database.foods);
    if (category != null) {
      statement.where((row) => row.category.equals(category.id));
    }
    if (normalized.isNotEmpty) {
      final pattern = _likePattern(normalized);
      // `RV4-P1-05`：品牌也参与检索（原来只 `like(name)`，搜「千丰香米」
      // 搜不到「米饭」）。`OR` 会让本来已无索引的全表扫再宽一层——实测护栏在
      // `test/features/nutrition/query_benchmark_test.dart`（p95 劣化 >10%
      // 就改两段式查询）。
      statement.where(
        (row) =>
            row.name.like(pattern, escapeChar: r'\') |
            row.brand.like(pattern, escapeChar: r'\'),
      );
      // 相关性排序（`RV4-P1-05`）：
      //   自建 > 精确同名 > **括号前主名命中** > 名称命中位置 > 长度 > 名称 > id
      //
      // 第三档是本轮新增的关键一层：真实库里「鸡蛋」命中 154 条，`鸡蛋（熟）`
      // 按旧的 `instr → length` 落在第 32 位（结果只取 10 条 ⇒ 永远看不到）。
      // 主名 = `substr(name, 1, instr(name,'（')-1)`，无括号时即整名；主名
      // **等于**查询词时优先。这样 `鸡蛋（熟）`/`鸡蛋（生）` 这类「同一食物的
      // 状态变体」会聚到前面，而不会被 `鸡蛋干`/`鸡蛋仔` 这些短名挤走。
      final mainName = FunctionCallExpression<String>('substr', [
        database.foods.name,
        const Constant(1),
        _mainNameEndExpression(),
      ]);
      statement.orderBy([
        (row) => OrderingTerm.desc(row.isUserCreated),
        (row) => OrderingTerm.desc(row.name.equals(normalized)),
        (row) => OrderingTerm.desc(mainName.equals(normalized)),
        // 名称命中优先于**仅品牌**命中（品牌是补充信息）。
        (row) => OrderingTerm.desc(row.name.like(pattern, escapeChar: r'\')),
        (row) => OrderingTerm.asc(
          FunctionCallExpression<int>('instr', [
            row.name,
            Constant(normalized),
          ]),
        ),
        (row) =>
            OrderingTerm.asc(FunctionCallExpression<int>('length', [row.name])),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
    } else {
      statement.orderBy([
        (row) => OrderingTerm.desc(row.isUserCreated),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
    }
    statement.limit(limit, offset: offset);
    return (await statement.get()).map(_map).toList(growable: false);
  }

  /// 「括号前主名」的右边界表达式：`instr(name, '（')` 为 0（无括号）时取
  /// 名称全长，否则取到括号前一位。
  ///
  /// SQLite 没有 `CASE` 之外的短路，用 `CASE WHEN instr(...) = 0 THEN length(name)
  /// ELSE instr(...) - 1 END` 表达；只依赖 `substr/instr/length/CASE`，不需要
  /// 新列、新索引、新依赖。
  Expression<int> _mainNameEndExpression() {
    final name = database.foods.name.name;
    return CustomExpression<int>(
      "CASE WHEN instr($name, '（') = 0 "
      'THEN length($name) '
      "ELSE instr($name, '（') - 1 END",
    );
  }

  /// 「名称包含」的 LIKE 模式（显式 ESCAPE）。SQLite 的 LIKE 没有默认转义符，
  /// 不声明的话名称里含 `%` 或 `_` 的食物（如「100%果汁」）永远搜不到。
  String _likePattern(String normalized) {
    final escaped = normalized
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  /// 按 id 取一条食物；不存在返回 null（AI 对话编辑的定向解析用）。
  Future<FoodRecord?> getById(String id) async {
    final row = await (database.select(
      database.foods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  /// 精确同名（trim 后全等）查找：0 或多于 1 条都原样返回，
  /// 调用方据此区分「找不到」与「有歧义」（docs/23 §4 不猜名字）。
  ///
  /// **写入会归一化名称**（`（外卖，…）` → `（外卖；…）`，见 [_row]），所以
  /// 查询必须用同一套归一化试一次；否则「刚建过、下一轮拿原话再引用」会
  /// 0 命中（2026-11-05 审计实测）。先原样、再归一化，兼容历史未归一化行。
  Future<List<FoodRecord>> searchExact(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return const [];
    final formatted = normalizeFoodNameFormat(normalized);
    final candidates = formatted == normalized
        ? [normalized]
        : [normalized, formatted];
    final rows = await (database.select(
      database.foods,
    )..where((row) => row.name.isIn(candidates))).get();
    return rows.map(_map).toList(growable: false);
  }

  Future<FoodRecord> create(NewFood food) async {
    _validate(food);
    final id = idGenerator.next();
    final now = clock.nowUtc();
    final row = _row(food, id: id, now: now);
    await database.transaction(() async {
      await database.into(database.foods).insert(row);
      await _replaceAliases(
        foodId: id,
        foodName: food.name,
        rawAliases: food.aliases,
        now: now,
        source: 'user',
      );
      // docs/67 §3.1：任何新建的可计算食物都必须有一条**生效修订**，
      // 主表四项是它的投影。放在仓储里而不是每个调用方，才不会有人忘。
      await FoodRevisionWriter(
        database: database,
        idGenerator: idGenerator,
        clock: clock,
      ).appendBaseline(foodId: id, food: food, origin: 'user_input', now: now);
    });
    return _map(row);
  }

  /// 批量新建（导入路径专用：docs/32 §4 T11 验收 2 / §3 D14 ③）。
  ///
  /// 与 [create] **同一套校验**——行的构造都走 [_row]，区别有两处：
  /// ① 写入方式：一批一个 drift `Batch`（一次往返而不是 N 次）；
  /// ② **身份**：导入行是**内置**（`isUserCreated=false`），不是自建。
  /// 2026-10-23 用户：「导入的食物都属内置（以后导入也是），只有 App 内
  /// 新建才是自建」。这决定了它们不可编辑/删除、且「清除所有数据」不清它们。
  ///
  /// **事务由调用方给**：批与批必须共用一个事务，逐批各成事务就退回了
  /// 「几万次提交」——这正是要拆掉的那个量级，所以这里刻意不开事务。
  ///
  /// 校验不过的行只数不抛（[FoodBatchCreateResult.rejected]）：预览期已经
  /// 做过同一套判据，真走到这里的坏行是意外，为它丢掉整批（以及同事务里
  /// 已经写好的几万行）代价太大。DB 级错误相反——**直接抛出**让调用方
  /// 回滚，吞掉它会把「全都没进去」报成「全进去了」。
  /// 【2026-10-30（用户实机：2w+ 导入食物全部显示「自建」）】一次性数据回填。
  ///
  /// 根因：T11（2026-10-23）之前，CSV 导入走**逐行 [create]** ——而 [create]
  /// 的身份口径是「App 内新建 = 自建」，于是早期导入的整批目录行被标成
  /// `is_user_created = 1`。T11 之后写入路径已改对（[createMany] → 内置），
  /// 但**存量行没有迁移**，老库的目录行就一直顶着「自建」。
  ///
  /// 修复判据（批量信号）：`is_user_created = 1` 且 `source = 'user'` 的行里，
  /// **同一分钟内创建 ≥ 30 行**的桶 = 一次批量导入 → 翻成内置
  /// （`is_user_created=0, source='import', state='verified'`）。
  /// 手动新建是零星操作，一分钟内不会出现几十行——孤立行保持自建不动。
  /// KV 门槛保证只跑一次；本方法幂等（再跑无行可翻，返回 0）。
  ///
  /// 【为什么不用 migration 版本号】schema 30 不动（版本号 = 表结构版本），
  /// 这是**数据**修复，挂 KV 门槛即可；调用点在 main.dart 启动链。
  ///
  /// 【为什么是**一条**集合式 UPDATE（2026-10-30 实机时序）】第一版按行
  /// `batch.update`（2.4 万条 = 2.4 万条语句），模拟器实测首启卡骨架
  /// **3.5 分钟**（04:25:36 启动 → 04:29:06 回填完成）。SQLCipher 下每行
  /// 都要重加密，逐行语句的固定开销把一次性迁移拖成了事故。改成单条
  /// `UPDATE ... WHERE id IN (按分钟分桶 HAVING COUNT>=30)`：分桶在 SQL 里
  /// 做（`created_at / 60` 整除 = 同一分钟；drift 的 dateTime 存 INTEGER
  /// 秒），语句数从 2.4 万降到 1。
  Future<int> backfillImportedFoodIdentity() async {
    final settings = AppSettingsRepository(database: database);
    if (await settings.getBool(kFoodImportIdentityBackfillKey)) return 0;

    final flipped = await database.customUpdate(
      '''
      UPDATE foods
         SET is_user_created = 0, source = 'import', state = 'verified'
       WHERE is_user_created = 1
         AND source = 'user'
         AND id IN (
           SELECT f.id
             FROM foods f
             JOIN (
               SELECT created_at / 60 AS bucket
                 FROM foods
                WHERE is_user_created = 1 AND source = 'user'
                GROUP BY bucket
               HAVING COUNT(*) >= ?
             ) bulk ON f.created_at / 60 = bulk.bucket
            WHERE f.is_user_created = 1 AND f.source = 'user'
         )
      ''',
      variables: [Variable.withInt(bulkBucketMinRows)],
      updates: {database.foods},
    );
    await settings.setBool(kFoodImportIdentityBackfillKey, value: true);
    return flipped;
  }

  /// 上面的回填 KV 门槛（app_settings 键）。
  static const String kFoodImportIdentityBackfillKey =
      'food_import_identity_backfill_v1';

  /// 同一分钟桶至少多少行才算「一次批量导入」。
  static const int bulkBucketMinRows = 30;

  Future<FoodBatchCreateResult> createMany(List<NewFood> foods) async {
    if (foods.isEmpty) {
      return const FoodBatchCreateResult(created: 0, rejected: 0);
    }
    final now = clock.nowUtc();
    final rows = <Insertable<Food>>[];
    final aliasRows = <FoodAliase>[];
    final revisionRows = <FoodNutritionRevisionsCompanion>[];
    var rejected = 0;
    for (final food in foods) {
      try {
        _validate(food);
      } on FormatException {
        rejected += 1;
        continue;
      }
      final id = idGenerator.next();
      final revisionId = '$id-rev-1';
      // 批量导入同样必须带生效修订（docs/67 §3.1）。修订行拼进同一个
      // batch：几万行导入不能因为"补修订"退回逐条往返。
      revisionRows.add(
        FoodRevisionWriter.baselineCompanion(
          revisionId: revisionId,
          foodId: id,
          food: food,
          origin: 'import',
          now: now,
        ),
      );
      rows.add(
        _row(
          food,
          id: id,
          now: now,
          isUserCreated: false,
        ).toCompanion(false).copyWith(currentRevisionId: Value(revisionId)),
      );
      // 别名与食物同一批、同一事务落库（ADR-037）：几万行导入时不能每条
      // 再开一次「查旧别名 + 插入」的往返。
      aliasRows.addAll(
        _aliasRowsFor(
          foodId: id,
          foodName: food.name,
          rawAliases: food.aliases,
          now: now,
          source: 'import',
        ),
      );
    }
    if (rows.isNotEmpty) {
      await database.batch((batch) {
        for (final row in rows) {
          batch.insert(database.foods, row);
        }
        for (final alias in aliasRows) {
          batch.insert(database.foodAliases, alias);
        }
        for (final revision in revisionRows) {
          batch.insert(database.foodNutritionRevisions, revision);
        }
      });
    }
    return FoodBatchCreateResult(created: rows.length, rejected: rejected);
  }

  /// 读一条食物的别名（归一化形态，按创建序）。
  Future<List<String>> aliasesFor(String foodId) async {
    final rows =
        await (database.select(database.foodAliases)
              ..where((row) => row.foodId.equals(foodId))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    return rows.map((row) => row.normalizedText).toList(growable: false);
  }

  /// 全库别名 → `{foodId: [normalizedText...]}`（导出用；一次查询，不 N+1）。
  Future<Map<String, List<String>>> aliasesByFood() async {
    final rows = await (database.select(
      database.foodAliases,
    )..orderBy([(row) => OrderingTerm.asc(row.createdAt)])).get();
    final grouped = <String, List<String>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.foodId, () => <String>[]).add(row.normalizedText);
    }
    return grouped;
  }

  /// 用这批别名替换某个食物的全部别名（[rawAliases] 为 null = 不动）。
  ///
  /// 归一化口径与检索侧同一函数（[normalizeSearchText]）：去空白、全角折半角、
  /// 小写。空串、与名称相同的、重复的都会被丢掉——这些别名永远不会被命中，
  /// 留着只会把导出文件写脏。
  Future<void> _replaceAliases({
    required String foodId,
    required String foodName,
    required List<String>? rawAliases,
    required DateTime now,
    required String source,
  }) async {
    if (rawAliases == null) return;
    await (database.delete(
      database.foodAliases,
    )..where((row) => row.foodId.equals(foodId))).go();
    final rows = _aliasRowsFor(
      foodId: foodId,
      foodName: foodName,
      rawAliases: rawAliases,
      now: now,
      source: source,
    );
    if (rows.isEmpty) return;
    await database.batch((batch) {
      for (final row in rows) {
        batch.insert(database.foodAliases, row);
      }
    });
  }

  /// 别名行的共同构造（[createMany] 批量与 [_replaceAliases] 单条共用）。
  List<FoodAliase> _aliasRowsFor({
    required String foodId,
    required String foodName,
    required List<String>? rawAliases,
    required DateTime now,
    required String source,
  }) {
    if (rawAliases == null || rawAliases.isEmpty) return const [];
    final seen = <String>{normalizeSearchText(foodName)};
    final rows = <FoodAliase>[];
    for (final raw in rawAliases) {
      final text = normalizeSearchText(raw);
      // 空串、重复、以及**与名称相同**的别名都不写：它们要么永远命中不了，
      // 要么只是把名称抄了一遍（名称本身已经参与匹配）。
      if (text.isEmpty || !seen.add(text)) continue;
      rows.add(
        FoodAliase(
          id: idGenerator.next(),
          foodId: foodId,
          normalizedText: text,
          language: 'zh-CN',
          // 用户/导入给的别名走 manual（菜单匹配的最高优先级档）；
          // 随包规则派生的走 nickname（普通精确命中档）。
          aliasType: source == 'normalized' ? 'nickname' : 'manual',
          source: source,
          confidence: 1,
          createdAt: now,
        ),
      );
    }
    return rows;
  }

  /// 改一条**自建**食物（docs/28 §5.3 D1）：内置条目抛 [FoodWriteFailure]。
  ///
  /// 只写表单拥有的列。`defaultServingGrams` **不在**其中——2026-10-04 起
  /// 新建/编辑弹层不再收集「默认份量」（N9），编辑时保留旧值：把它写 null
  /// 等于替用户静默抹掉一条他再也看不到、也改不回来的数据。
  Future<FoodRecord> update(
    String id,
    NewFood food, {

    /// 显式给了才写（AI 的 `food.update` 会带；编辑弹层不带 ⇒ 保留旧值）。
    double? defaultServingGrams,

    /// 读-改-写冲突检测：调用方把"打开表单时那一版的 updatedAt"带回来。
    /// 库里已被改过（不同秒）就抛 [FoodWriteFailure]，不静默覆盖
    /// （docs/67 §3.2 第 7 条）。null = 不做检查（AI/导入等无表单场景）。
    DateTime? expectedUpdatedAt,
  }) async {
    _validate(food);
    await _requireUserCreated(id);
    if (expectedUpdatedAt != null) {
      final current =
          await (database.select(database.foods)
                ..where((row) => row.id.equals(id))
                ..limit(1))
              .getSingleOrNull();
      if (current == null) {
        throw const FoodWriteFailure('这条食物已不在本地数据里。');
      }
      final sameSecond =
          current.updatedAt.millisecondsSinceEpoch ~/ 1000 ==
          expectedUpdatedAt.millisecondsSinceEpoch ~/ 1000;
      if (!sameSecond) {
        throw const FoodWriteFailure('这条食物刚在别处被改过，请重新打开再改。');
      }
    }
    final now = clock.nowUtc();
    await database.transaction(() async {
      await (database.update(
        database.foods,
      )..where((row) => row.id.equals(id))).write(
        FoodsCompanion(
          name: Value(normalizeFoodNameFormat(food.name.trim())),
          brand: Value(
            food.brand?.trim().isEmpty ?? true ? null : food.brand!.trim(),
          ),
          kcalPer100g: Value(food.kcalPer100g),
          proteinPer100g: Value(food.proteinPer100g),
          carbsPer100g: Value(food.carbsPer100g),
          fatPer100g: Value(food.fatPer100g),
          // 表单一带上种类就一起写（新建弹层的下拉总是给值）；null 同样如实
          // 写空——update 的语义是「把表单拥有的列写成表单里的样子」。
          category: Value(food.category?.id),
          defaultServingGrams: defaultServingGrams == null
              ? const Value.absent()
              : Value(defaultServingGrams),
          updatedAt: Value(now),
        ),
      );
      // 别名：null = 不动（AI 改营养时不会误删）；[] = 清空；非空 = 替换。
      await _replaceAliases(
        foodId: id,
        foodName: food.name,
        rawAliases: food.aliases,
        now: now,
        source: 'user',
      );
      // 营养修改 = 追加修订 + 切指针（同一事务）：主表四项永远能解释
      // "按哪一版算的"，旧修订也保留下来供历史餐追溯。
      final number = await _nextRevisionNumber(id) + 1;
      final revisionId = '$id-rev-$number';
      await database
          .into(database.foodNutritionRevisions)
          .insert(
            FoodNutritionRevisionsCompanion.insert(
              id: revisionId,
              foodId: id,
              revisionNumber: number,
              kcalPer100g: Value(food.kcalPer100g),
              proteinGPer100g: Value(food.proteinPer100g),
              carbsGPer100g: Value(food.carbsPer100g),
              fatGPer100g: Value(food.fatPer100g),
              createdAt: now,
              nutritionBasis: Value(NutritionBasis.per100g.storedValue),
              basisAssumed: const Value(false),
              origin: const Value('user_input'),
              conversionVersion: const Value('food-write-v1'),
            ),
          );
      await (database.update(database.foods)..where((row) => row.id.equals(id)))
          .write(FoodsCompanion(currentRevisionId: Value(revisionId)));
    });
    final updated = await getById(id);
    if (updated == null) {
      throw const FoodWriteFailure('这条食物已不在本地数据里。');
    }
    return updated;
  }

  /// 删一条**自建**食物（docs/28 §5.3 D1）。内置条目抛 [FoodWriteFailure]。
  ///
  /// 引用处理（**不静默改别人的数据，但也不留悬空链接**）：
  ///  * `meal_items.food_id` → 置 NULL：餐次条目自带名称/营养**快照**，用户
  ///    看到的数字与名称一个都不变，只是不再指向那条已经删掉的食物；
  ///  * `menu_item_food_matches` → 连同删掉：匹配是「菜单项 ↔ 食物」的链接，
  ///    指向一条不存在的食物没有意义（菜单页会重新给建议）；
  ///  * 份量/修订/别名 → 由外键 `ON DELETE CASCADE` 一并清掉（这些是那条
  ///    食物自己的派生数据）。
  ///
  /// 2026-10-04（docs/28 §6.7）：原先这里还有一条 `recipe_items` 的守卫
  ///（「这条食物还在食谱里用着」）——该表随食谱整族删除，守卫与文案一并移除。
  /// 库存/价格两张表也在同批删除，所以也没了它们的级联清理。
  Future<void> delete(String id) async {
    await _requireUserCreated(id);
    // docs/67 D10：仍被食堂供应引用时**不能硬删**——`menu_items.food_id` 是
    // 真外键（NO ACTION），硬删会撞约束；更重要的是"删一条食物顺手让某个
    // 窗口的菜失去营养"不是用户表达的意图。归档才是默认动作。
    final referencing =
        await (database.select(database.menuItems)
              ..where((row) => row.foodId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (referencing != null) {
      throw const FoodWriteFailure('这条食物还被食堂窗口引用，不能删除；可以先归档（不再进新挂窗与推荐）。');
    }
    await database.transaction(() async {
      await (database.update(database.mealItems)
            ..where((row) => row.foodId.equals(id)))
          .write(const MealItemsCompanion(foodId: Value(null)));
      await (database.delete(
        database.menuItemFoodMatches,
      )..where((row) => row.foodId.equals(id))).go();
      // 台账保留（这是"这条旧记录被移到哪"的历史），只断开主食物指针：
      // 连台账一起删会让下次归一给同一旧键再造一条主食物。
      await (database.update(database.legacyEntityMappings)
            ..where((row) => row.foodId.equals(id)))
          .write(const LegacyEntityMappingsCompanion(foodId: Value(null)));
      await (database.delete(
        database.foods,
      )..where((row) => row.id.equals(id))).go();
    });
  }

  /// 编辑/删除的共同前置：条目在、且是自建（D1 只给自建条目入口）。
  Future<FoodRecord> _requireUserCreated(String id) async {
    final existing = await getById(id);
    if (existing == null) {
      throw const FoodWriteFailure('这条食物已不在本地数据里。');
    }
    if (!existing.isUserCreated) {
      throw const FoodWriteFailure('内置食物不能修改或删除。');
    }
    return existing;
  }

  /// 新建行的共同构造：[create] 与 [createMany] 都经由这里。
  ///
  /// **2026-10-23 用户**：「导入的食物都属内置（以后导入也是），只有 App 内
  /// 新建才是自建」。因此身份由**写入路径**决定，而不是由调用方传值：
  /// [create]（App 内新建 / AI 建食物）→ `isUserCreated=true`；
  /// [createMany]（CSV 导入 / 随包食物库）→ `isUserCreated=false`。
  /// 导入行因此不可在食物库里编辑/删除（`_requireUserCreated`），
  /// 「清空内置食物」会连它们一起清；「清除所有数据」不再清它们。
  Food _row(
    NewFood food, {
    required String id,
    required DateTime now,
    bool isUserCreated = true,
  }) => Food(
    id: id,
    // 名称固定格式（ADR-037）：`主名（备注）`。写入口统一归一化——手动新建、
    // 编辑、CSV 导入、AI 建食物都走这里，格式不靠每个调用点自觉。
    name: normalizeFoodNameFormat(food.name.trim()),
    brand: food.brand?.trim().isEmpty ?? true ? null : food.brand!.trim(),
    defaultServingGrams: food.defaultServingGrams,
    kcalPer100g: food.kcalPer100g,
    proteinPer100g: food.proteinPer100g,
    carbsPer100g: food.carbsPer100g,
    fatPer100g: food.fatPer100g,
    // 种类落枚举 id 文本（docs/31 S5 需求 53）。
    //
    // 【2026-10-31 用户：「自定义食材自动加入食物库时也自动分类，不提示用户；
    // AI 生成的食物也要自动分类」】调用方没给种类时**不再留空**，按名称走
    // [FoodCategory.classify] 的确定性关键词表归类（同一名字必得同一类，
    // 不联网、不弹提示）。调用方给了就尊重调用方（AI 带 `rawCategory` 的路径
    // 仍按它自己的分类列翻译）。
    //
    // 【为什么这不违反「不猜分类」】旧注释防的是把**不知道的**一律塞成「其他」
    // ——那等于用默认值冒充答案可乐库/搜索全靠「全部」过滤，空分类只会让
    // 新食物在分类页里彻底消失。[FoodCategory.classify] 与 CSV 导入是**同一
    // 张表**（导入行早就这么归类），所以手动建 / AI 建和导入行看到的是同一类；
    // 名字里一个关键词都不中的才落 `other`，与导入行同口径，不是新编的答案。
    category: (food.category ?? FoodCategory.classify(name: food.name)).id,
    // Round 5 T11（需求 75）新结构 15 列：导入才带值，手动新建 / AI 草稿
    // 都是 null（`_text` 把空串也收成 null——库里「未填」是 null）。
    source: isUserCreated ? 'user' : 'import',
    isUserCreated: isUserCreated,
    state: isUserCreated ? 'user_created' : 'verified',
    licenseStatus: 'unknown',
    createdAt: now,
    updatedAt: now,
  );

  Future<int> _nextRevisionNumber(String foodId) async {
    final row = await database
        .customSelect(
          'SELECT COALESCE(MAX(revision_number), 0) AS n '
          'FROM food_nutrition_revisions WHERE food_id = ?',
          variables: [Variable.withString(foodId)],
        )
        .getSingle();
    return (row.data['n'] as int? ?? 0);
  }

  void _validate(NewFood food) {
    validatedEntityName(food.name, label: '食物名称');
    final values = [
      food.kcalPer100g,
      food.proteinPer100g,
      food.carbsPer100g,
      food.fatPer100g,
      ?food.defaultServingGrams,
    ];
    if (values.any((value) => !value.isFinite || value < 0)) {
      throw const FormatException('营养和份量必须是非负数。');
    }
    if (food.kcalPer100g > 1000 ||
        food.proteinPer100g > 100 ||
        food.carbsPer100g > 100 ||
        food.fatPer100g > 100) {
      throw const FormatException('每 100 克营养数值超出合理范围。');
    }
  }

  FoodRecord _map(Food row) => FoodRecord(
    id: row.id,
    name: row.name,
    brand: row.brand,
    defaultServingGrams: row.defaultServingGrams,
    kcalPer100g: row.kcalPer100g,
    proteinPer100g: row.proteinPer100g,
    carbsPer100g: row.carbsPer100g,
    fatPer100g: row.fatPer100g,
    isUserCreated: row.isUserCreated,
    category: FoodCategory.tryFromId(row.category),
  );
}

/// [FoodRepository.createMany] 的结果。导入路径只需要数字：把几万个
/// `FoodRecord` 再物化一遍没有意义。`rejected` = 校验没过的行数，
/// 正常为 0（预览期已经做过同一套判据）。
final class FoodBatchCreateResult {
  const FoodBatchCreateResult({required this.created, required this.rejected});

  final int created;
  final int rejected;
}
