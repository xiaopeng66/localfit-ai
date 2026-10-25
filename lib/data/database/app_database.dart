import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:localfit_ai/data/database/tables.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    AiProviderConfigs,
    Profiles,
    Goals,
    DailyTargets,
    Measurements,
    Foods,
    FoodAliases,
    FoodNutritionRevisions,
    FoodPortions,
    FoodEvidence,
    FoodImportJobs,
    CampusProfiles,
    Venues,
    MenuSources,
    MenuSnapshots,
    MenuServices,
    MenuItems,
    MenuItemFoodMatches,
    MenuItemNutritionEvidence,
    MenuImportJobs,
    AvailabilityWindows,
    DailyPlans,
    DailyPlanSlots,
    DailyPlanCandidates,
    Meals,
    MealItems,
    Exercises,
    WorkoutPlans,
    WorkoutDays,
    PlannedExercises,
    WorkoutSessions,
    WorkoutSets,
    // schema 17 新增域（docs/21 §7.2）。
    WaterIntakes,
    Achievements,
    DishLibrary,
    CardioPrescriptions,
    RecognitionResults,
    ConversationMessages,
    AppSettings,
    // schema 21 预置（docs/29 §P7）：每日本机步数，P9 接功能。
    StepsDaily,
    // schema 27（docs/38）：AI 长期记忆。
    AiMemories,
    // schema 28（docs/41 §11）：派生向量索引 + 通用后台任务队列。
    EmbeddingIndex,
    BackgroundJobs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open({required Uint8List key}) async {
    final directory = await getApplicationSupportDirectory();
    return openFile(
      file: File(path.join(directory.path, 'localfit.sqlite')),
      key: key,
    );
  }

  static AppDatabase openFile({required File file, required Uint8List key}) {
    final keyHex = _hex(key);

    return AppDatabase(
      NativeDatabase.createInBackground(
        file,
        isolateSetup: configureSqlCipherLibrary,
        setup: (database) {
          final cipherVersion = database.select('PRAGMA cipher_version');
          if (cipherVersion.isEmpty) {
            throw StateError('SQLCipher library is unavailable.');
          }
          database.execute("PRAGMA key = \"x'$keyHex'\"");
          database.execute('PRAGMA foreign_keys = ON');
          database.execute('PRAGMA cipher_memory_security = ON');
        },
      ),
    );
  }

  @override
  int get schemaVersion => 30;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(aiProviderConfigs);
      }
      if (from < 5) {
        // schema 22（docs/31 S2）删掉了这里原本给 `foods` 加的三列
        // （constraintKnowledge / dietaryLabelsJson / allergensJson，schema 5
        // 加入、schema 22 删除）。**保留本分支的其余动作**：
        // `profiles.allergenAvoidancesJson` 还在用（docs/31 §2 D5）。
        //
        // 为什么不改成裸 SQL「先照样加、再由 v22 删」：终点 schema 完全一样，
        // 但对 v4 老库会白白触发**三次 foods 表重建**（49,444 行种子），
        // 换来一个谁也不观察的中间态。删除是等价的（v22 分支按列存在性判断，
        // 列不在就跳过），成本却只有零。
        await migrator.addColumn(profiles, profiles.allergenAvoidancesJson);
      }
      if (from < 6) {
        await migrator.addColumn(profiles, profiles.planningBudgetMinorUnits);
        await migrator.addColumn(profiles, profiles.planningBudgetCurrency);
        await migrator.addColumn(
          profiles,
          profiles.maximumDraftDeclaredMinutes,
        );
        await migrator.addColumn(profiles, profiles.pantryCoverageEnabled);
      }
      if (from < 7) {
        await migrator.createTable(exercises);
      }
      if (from < 8) {
        await migrator.createTable(workoutPlans);
        await migrator.createTable(workoutDays);
        await migrator.createTable(plannedExercises);
      }
      if (from < 9) {
        await migrator.createTable(workoutSessions);
        await migrator.createTable(workoutSets);
      }
      if (from < 10) {
        // Phase 6 性能切片：为既有库补建高频查询列索引。
        // 2026-10-21 RV-P2-11：drift 的 `createIndex` 生成裸 `CREATE INDEX`，
        // 迁移失败重试会撞「already exists」⇒ 这里改显式 IF NOT EXISTS。
        for (final sql in const [
          'CREATE INDEX IF NOT EXISTS idx_meals_local_date '
              'ON meals (local_date)',
          'CREATE INDEX IF NOT EXISTS idx_meal_items_meal_id '
              'ON meal_items (meal_id)',
          'CREATE INDEX IF NOT EXISTS idx_measurements_local_date '
              'ON measurements (local_date)',
          'CREATE INDEX IF NOT EXISTS idx_workout_sessions_status_local_date '
              'ON workout_sessions (status, local_date)',
          'CREATE INDEX IF NOT EXISTS idx_workout_sets_session_id '
              'ON workout_sets (session_id)',
        ]) {
          await customStatement(sql);
        }
      }
      if (from < 11) {
        // 2.0-1 食物目录分层：canonical 增量列 + alias/revision/portion/
        // evidence/import job 实体。旧行回填 state：用户自建 → user_created，
        // 既有种子（完整四项宏量）→ verified。
        await migrator.addColumn(foods, foods.state);
        await migrator.addColumn(foods, foods.locale);
        await migrator.addColumn(foods, foods.category);
        await migrator.addColumn(foods, foods.sourceVersion);
        await migrator.addColumn(foods, foods.licenseStatus);
        await customStatement(
          "UPDATE foods SET state = 'user_created' WHERE is_user_created = 1",
        );
        await migrator.createTable(foodAliases);
        await migrator.createTable(foodNutritionRevisions);
        await migrator.createTable(foodPortions);
        await migrator.createTable(foodEvidence);
        await migrator.createTable(foodImportJobs);
      }
      if (from < 12) {
        // 2.0-3 Menu v1：校园菜单分层（规范第 6/8 节）。快照是来源内容，
        // 不直接成为 foods/meals；原文存私有目录，库里只有路径与 hash。
        await migrator.createTable(campusProfiles);
        await migrator.createTable(venues);
        await migrator.createTable(menuSources);
        await migrator.createTable(menuSnapshots);
        await migrator.createTable(menuServices);
        await migrator.createTable(menuItems);
        await migrator.createTable(menuItemFoodMatches);
        await migrator.createTable(menuItemNutritionEvidence);
        await migrator.createTable(menuImportJobs);
      }
      if (from < 13) {
        // 2.0-4 Planning v1：availability windows 与 daily plans（docs/07 §6/8）。
        // 推荐层，不进营养统计；确认才写 confirmed。
        await migrator.createTable(availabilityWindows);
        await migrator.createTable(dailyPlans);
        await migrator.createTable(dailyPlanSlots);
        await migrator.createTable(dailyPlanCandidates);
      }
      if (from < 14) {
        // 2.0-6i-2 手动通勤列 `manual_commute_minutes`（docs/07 §7.5 第一级）：
        // 本地事实，无定位、无副作用。该特性已在 Round 5 T8 下线、列由下面
        // 的 `from < 24` 分支删除（docs/32 §3 D10）——**迁移历史不改写**：
        // 这一步仍按当年的形状补列（表类里已无该列，故用原生 SQL），否则
        // 升到 v14 中途的库会缺列、后续分支的列存在性判断会失真。
        // 旧行保持 null = 未填写（中性值）。
        await customStatement(
          'ALTER TABLE profiles ADD COLUMN manual_commute_minutes INTEGER',
        );
      }
      if (from >= 12 && from < 15) {
        // 3.0 食堂目录：营养证据补每 100g 代表值四列（区间列一直在，但推荐
        // 与展示需要单一代表值）。旧行保持 null：那些行只有区间、没有可靠
        // 中心值，读取侧按「无营养」处理，绝不拿区间中点冒充事实。
        //
        // 下界 `from >= 12` 是必需的：更早的库由上面 `from < 12` 分支
        // `createTable` 建表，而 createTable 用的是**当前**表定义（已含这
        // 四列），再 addColumn 会 duplicate column。
        await migrator.addColumn(
          menuItemNutritionEvidence,
          menuItemNutritionEvidence.kcalPer100g,
        );
        await migrator.addColumn(
          menuItemNutritionEvidence,
          menuItemNutritionEvidence.proteinPer100g,
        );
        await migrator.addColumn(
          menuItemNutritionEvidence,
          menuItemNutritionEvidence.carbsPer100g,
        );
        await migrator.addColumn(
          menuItemNutritionEvidence,
          menuItemNutritionEvidence.fatPer100g,
        );
      }
      if (from >= 7 && from < 16) {
        // docs/21 §5.5：动作库补「难度 / 常用度」两列。下界 `from >= 7`
        // 与上面 `from >= 12` 同理——v6 及更早的库由 `from < 7` 分支
        // `createTable` 建表，用的是已含这两列的当前定义，再 addColumn 会
        // duplicate column。
        //
        // 旧行保持 null＝未标注：难度不能默认成「初级」、常用度不能默认成
        // 0，那会把「不知道」伪装成事实。种子 v2 随后按 id 覆盖有标注的行。
        //
        // 「表在不在」必须先查：迁移测试的 v11/v12/v13 fixture 是**最小
        // 复现**——只建自己断言要用到的表（见 app_database_v12_migration_test
        // 的 _createV11Database）。真实 v11+ 库一定有 exercises（v7 就建了），
        // 所以这里对生产路径是恒真分支；但不守卫的话，任何裁剪过的库
        // （含历史 fixture）会在 addColumn 上炸「no such table」。
        final hasExercises = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'exercises'",
        ).getSingleOrNull();
        if (hasExercises != null) {
          await migrator.addColumn(exercises, exercises.difficulty);
          await migrator.addColumn(exercises, exercises.popularity);
        }
      }
      if (from < 17) {
        // docs/21 §7.2 新增域：7 张表 + Measurements 扩 muscleMassKg 列
        // （体成分不单独建表——同一测量时刻的多指标同行，§7.2 裁决）。
        // 只增不改不删：37 张既有表的结构与数据不动。
        //
        // schema 22（docs/31 S2）撤销了 muscleMassKg 那一半：改列已从表定义
        // 删除，这里不再 addColumn（它必然编译失败，且加了也会被 v22 立刻
        // drop —— 终点一样，中间态没人观察）。**7 张表的创建原样保留**。
        await migrator.createTable(waterIntakes);
        await migrator.createTable(achievements);
        await migrator.createTable(dishLibrary);
        await migrator.createTable(cardioPrescriptions);
        await migrator.createTable(recognitionResults);
        await migrator.createTable(conversationMessages);
        await migrator.createTable(appSettings);
      }
      if (from >= 2 && from < 18) {
        // docs/24 §2：AI 供应商协议可选（Chat Completions / Responses /
        // Anthropic Messages）。旧行保持 null＝从未选过协议，读取侧回落到
        // Chat Completions（旧行为逐字节不变，见 AiProviderProtocol）。
        //
        // **两条守卫都必需**：
        // * 下界 `from >= 2`：v1 及更早的库由上面 `from < 2` 分支
        //   `createTable(aiProviderConfigs)` 建表，而 createTable 用的是**当前**
        //   表定义（已含 protocol 列），再 addColumn 会 duplicate column
        //   （与 v15/v16 两处同类守卫同理）。
        // * 存在性：迁移测试的 v12/v13 fixture 是最小复现，根本没建这张表
        //   （与 exercises 的守卫同理）；生产路径（v2+ 真实库）恒有该表。
        final hasAiProviderConfigs = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_provider_configs'",
        ).getSingleOrNull();
        if (hasAiProviderConfigs != null) {
          await migrator.addColumn(
            aiProviderConfigs,
            aiProviderConfigs.protocol,
          );
        }
      }
      if (from < 19) {
        // docs/28 §6.5 / §6.7：食谱 / 周计划 / 食物价格 / 库存四族整族下线。
        //
        // **三条纪律（每条都有具体失败模式，见 docs/28 §6.5）**：
        // * 必须 `IF EXISTS`：v1/v2 老库从没建过 recipes 族（它们由已删除的
        //   `from < 3` / `from < 4` 建），v1..v5 也从没建过价格/库存
        //   （由已删除的 `from < 6` 那两行建）；裸 `DROP TABLE` 会抛
        //   `no such table`，把所有老库的升级一次打死。
        // * 子表在前：`recipe_items.recipeId`（CASCADE）与
        //   `meal_plan_entries.recipeId` 都引用 `recipes(id)`；
        //   价格/库存只引用 `foods(id)`，位置不敏感。
        // * 放在迁移链最末：将来若有人恢复建表逻辑，也不会出现
        //   「刚建完又被后面的分支留下」的错序。
        //
        // **不可逆**：这是 D9 的明确后果，库里的食谱与计划数据永久消失。
        await customStatement('DROP TABLE IF EXISTS recipe_items');
        await customStatement('DROP TABLE IF EXISTS meal_plan_entries');
        await customStatement('DROP TABLE IF EXISTS recipes');
        await customStatement('DROP TABLE IF EXISTS pantry_stocks');
        await customStatement('DROP TABLE IF EXISTS food_price_facts');
      }
      if (from >= 2 && from < 20) {
        // docs/29 §P4：AI 推理开关（19→20 一次迁移）。旧行 reasoning 为
        // null＝从未选过 → 读取侧按 `AiReasoningMode.fromStorage` 回落
        // 「关闭推理」（产品默认档）。
        //
        // **两条守卫都必需**（与 from<18 的 protocol 列同理）：
        // * 下界 `from >= 2`：v1 及更早的库由 `from < 2` 分支
        //   `createTable(aiProviderConfigs)` 建表，用的是**当前**表定义
        //   （已含 reasoning 列），再 addColumn 会 duplicate column。
        // * 存在性：迁移测试的 fixture 是最小复现，可能根本没建这张表；
        //   生产路径（v2+ 真实库）恒有该表。
        final hasAiProviderConfigs = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_provider_configs'",
        ).getSingleOrNull();
        if (hasAiProviderConfigs != null) {
          await migrator.addColumn(
            aiProviderConfigs,
            aiProviderConfigs.reasoning,
          );
        }
      }
      if (from < 21) {
        // docs/29 §P7：菜品照片列 + 每日步数表。**v20 已被 P4 的 reasoning
        // 列发给线上设备，菜品图片不能挤进同一版**（那条分支在已升到 v20
        // 的库上不会再跑，加了列也补不上）⇒ 顺延为 20→21 新开一步。
        //
        // * StepsDaily 是新表，`createTable` 恒安全（建出即带全列）。
        // * menu_items.imagePath 加列改成**按实际列存在性**判断，而不是
        //   按版本区间猜：本包开发期曾按 docs/29 原稿把该列放进 `from < 20`
        //   分支（与 P4 同版），中途构建过的库 user_version=20 但列已在
        //   ——设备走查第一轮就崩在 `duplicate column name: image_path`
        //   （增量迁移的教训：版本号只说明「跑没跑过链」，说明不了
        //   「列在不在」）。pragma_table_info 一条查询同时覆盖三种情形：
        //   列已有（跳过）、真 v20 库（补列）、`from < 12` 刚用当前表定义
        //   建出（列已带，跳过）。
        await migrator.createTable(stepsDaily);
        // 两条守卫都要：表不存在（fixture 是最小复现）时
        // `pragma_table_info` 静默返回空，会被误读成「列缺失」再去
        // ALTER 一张不存在的表。
        final hasMenuItems = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'menu_items'",
        ).getSingleOrNull();
        if (hasMenuItems != null) {
          final hasImagePath = await customSelect(
            "SELECT 1 FROM pragma_table_info('menu_items') "
            "WHERE name = 'image_path'",
          ).getSingleOrNull();
          if (hasImagePath == null) {
            await migrator.addColumn(menuItems, menuItems.imagePath);
          }
        }
      }
      if (from < 23) {
        // docs/32 §3 D9（需求 69）：身份列 —— 昵称 + 头像路径。
        //
        // **范围修订（2026-10-12）**：D9 原写「与删 `manualCommuteMinutes`
        // 合并为同一次迁移」；但该列有 67 个文件引用（含 drift 生成代码），
        // 而 T7 排在 T8 之前 —— 先删列会让全仓编译失败、违反「每包独立过
        // 门禁 EXIT=0」。故本包**只加列**；删列已由 T8 的 `from < 24`
        // 分支完成（终点 schema 与 D9 原文一致）。
        //
        // 纪律与 v22 的减法迁移同源：**按列存在性判断**，不按版本区间
        // （`ADD COLUMN` 第二次会 duplicate column；开发期就有「版本号没升
        // 但列已改」的库形态）。两列都可空 ⇒ 老行自然为 null（未填 ≠ 空串）。
        // **先查表在不在**（v22 分支注释里的同一条纪律）：迁移测试的 fixture
        // 是最小复现/裁剪库，不一定建了 `profiles`；对不存在的表查
        // `pragma_table_info` 会静默返回空、被误读成「列缺失」再去 ALTER
        // 一张不存在的表（实测：v21/v20 fixture 直接抛 `no such table`）。
        final hasProfiles = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'profiles'",
        ).getSingleOrNull();
        if (hasProfiles != null) {
          for (final column in const ['display_name', 'avatar_path']) {
            final exists = await customSelect(
              "SELECT 1 FROM pragma_table_info('profiles') WHERE name = ?",
              variables: [Variable<String>(column)],
            ).getSingleOrNull();
            if (exists == null) {
              await customStatement(
                'ALTER TABLE profiles ADD COLUMN $column TEXT',
              );
            }
          }
        }
      }
      if (from < 26) {
        // Round9 S8-b（2026-10-16 用户：食堂菜品价格「所有地方，只要涉及到的
        // 都删」）：退役列 `price_minor`（点名一次，供退役特性 grep 门禁区分
        // 「历史列名」与「活引用」）。纪律与 v24 的减法迁移同源：
        //  * 按**列存在性**判断（`DROP COLUMN` 没有 IF EXISTS）；
        //  * 先查表在不在（裁剪 fixture 不一定建了 `menu_items`）。
        final hasMenuItems = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'menu_items'",
        ).getSingleOrNull();
        if (hasMenuItems != null) {
          final hasPrice = await customSelect(
            "SELECT 1 FROM pragma_table_info('menu_items') "
            "WHERE name = 'price_minor'",
          ).getSingleOrNull();
          if (hasPrice != null) {
            await customStatement(
              'ALTER TABLE menu_items DROP COLUMN price_minor',
            );
          }
        }
      }
      if (from < 24) {
        // Round 5 T8（docs/32 §3 D10 / 需求 70/71）：退役列
        // `manual_commute_minutes`（点名一次，供退役特性 grep 门禁区分
        // 「历史列名」与「活引用」）随整条纵切下线。**减法迁移三条纪律**
        // （与 v22 同源，见下）：
        // * 按**列存在性**判断，不按版本区间：`DROP COLUMN` 没有 `IF EXISTS`，
        //   重复升级会抛 `no such column`；
        // * **先查表在不在**：裁剪 fixture 不一定建了 `profiles`；
        // * `from < 14` 的库由 v14 分支补列、更早的库由建表定义给出，
        //   两条路径最终都到这里，列存在性判断覆盖两者。
        final hasProfiles = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'profiles'",
        ).getSingleOrNull();
        if (hasProfiles != null) {
          final hasColumn = await customSelect(
            "SELECT 1 FROM pragma_table_info('profiles') "
            "WHERE name = 'manual_commute_minutes'",
          ).getSingleOrNull();
          if (hasColumn != null) {
            await customStatement(
              'ALTER TABLE profiles DROP COLUMN manual_commute_minutes',
            );
          }
        }
      }
      if (from < 25) {
        // Round 5 T11（docs/32 §4 T11 / §6 第 7 条「除 T11 按新结构统一外」）：
        // 食物库新结构 15 列（用户流水线 21 列契约里表上没有的那些，全可空）。
        //
        // 加法迁移沿用 v23 的三条纪律（比裸 addColumn 稳）：
        // * **先查表在不在**——裁剪 fixture 不一定建了 `foods`；
        // * **按列存在性判断**，不按版本区间：`ADD COLUMN` 第二次会 duplicate
        //   column，而开发期就有「版本号没升但列已改」的库形态；
        // * 全部 TEXT 且可空 ⇒ 老行自然为 null，不需要回填。
        // **迁移 DDL 与 drift 生成代码是两处列名事实**（§11 m2 的教训），
        // 这里写的是 SQL 名（snake_case）。
        final hasFoods = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'foods'",
        ).getSingleOrNull();
        if (hasFoods != null) {
          for (final column in const [
            'library_code',
            'category_group',
            'category_sub',
            'cuisine',
            'food_kind',
            'data_basis',
            'food_state',
            'source_code',
            'source_food_code',
            'original_name',
            'original_category',
            'source_note',
            'source_url',
            'recipe_summary',
            'source_nature',
          ]) {
            final exists = await customSelect(
              "SELECT 1 FROM pragma_table_info('foods') WHERE name = ?",
              variables: [Variable<String>(column)],
            ).getSingleOrNull();
            if (exists == null) {
              await customStatement(
                'ALTER TABLE foods ADD COLUMN $column TEXT',
              );
            }
          }
        }
      }
      if (from < 22) {
        // docs/31 S2（需求 45/46/50）：**本仓第一次减列迁移**。
        // 删 `measurements` 的体脂率/肌肉量两列 + `foods` 的三个
        // 过敏原/饮食标签列。用户原话「添加的弹窗卡片去掉体脂率和肌肉量」、
        // 「其他所有地方有关于这两个数据的都删掉」、「过敏原与饮食标签这个删掉」。
        //
        // **三条纪律（减法的失败模式比加法多）**：
        // * **按列存在性判断，不按版本区间**：`ALTER TABLE ... DROP COLUMN`
        //   没有 `IF EXISTS`，第二次会抛 `no such column`；而本包开发期就有
        //   「版本号没升但列已改」的 DB 形态（v21 的 image_path 踩过同一坑）。
        // * **先查表在不在**：迁移测试的 fixture 是最小复现，不一定建了
        //   `measurements`/`foods`；对不存在的表查 `pragma_table_info` 会
        //   静默返回空、被误读成「列缺失」再去 ALTER 一张不存在的表。
        // * **`from >= 5` / `from >= 17` 的下界**：更早的库由上面的分支用
        //   **当前**表定义建表（已无这些列），`DROP COLUMN` 必然 `no such
        //   column`——不过列存在性判断已经覆盖这一点，下界只是省一次查询。
        //   这里**不**写下界：判据只有一条（列在不在），少一个能写错的开关。
        //
        // **不可逆**：体脂率/肌肉量/食物侧过敏原的**历史数据永久消失**。
        // 旧 `.lfb` 包里的对应键在恢复时被静默忽略（见 schema 22 的两列注释）。
        // **副作用**：`daily_solver` 的 `allergen_conflict` 从此没有食物侧
        // 输入源（profiles 侧声明仍在，但不再过滤推荐）——见 docs/31 §2 D5。
        final hasMeasurements = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'measurements'",
        ).getSingleOrNull();
        if (hasMeasurements != null) {
          for (final column in const ['body_fat_percent', 'muscle_mass_kg']) {
            final exists = await customSelect(
              "SELECT 1 FROM pragma_table_info('measurements') "
              "WHERE name = ?",
              variables: [Variable<String>(column)],
            ).getSingleOrNull();
            if (exists != null) {
              await migrator.dropColumn(measurements, column);
            }
          }
        }
        final hasFoods = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'foods'",
        ).getSingleOrNull();
        if (hasFoods != null) {
          for (final column in const [
            'constraint_knowledge',
            'dietary_labels_json',
            'allergens_json',
          ]) {
            final exists = await customSelect(
              "SELECT 1 FROM pragma_table_info('foods') WHERE name = ?",
              variables: [Variable<String>(column)],
            ).getSingleOrNull();
            if (exists != null) {
              await migrator.dropColumn(foods, column);
            }
          }
        }
      }
      if (from < 27) {
        // docs/38 S11（2026-10-17）：AI 长期记忆。纯加法；按「表在不在」
        // 判断而不是按版本区间猜——开发期手工建过表的库也能升上来
        // （与 steps_daily 那次踩坑同一教训）。
        final hasMemories = await customSelect(
          "SELECT 1 FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_memories'",
        ).getSingleOrNull();
        if (hasMemories == null) {
          await migrator.createTable(aiMemories);
        }
      }
      if (from < 28) {
        // docs/41 §11（2026-10-18，schema 28）：**纯加法**——记忆治理列、
        // 菜品/食堂菜/餐记录三张表的来源与份量列、派生索引表、任务队列表。
        // 全部按列/表存在性守卫（开发期手工加过列的库也能升上来）。
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.importance);
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.lastUsedAt);
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.useCount);
        await _addColumnIfMissing(
          migrator,
          aiMemories,
          aiMemories.supersededById,
        );
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.expiresAt);
        await _addColumnIfMissing(
          migrator,
          aiMemories,
          aiMemories.sourceMessageId,
        );
        await _addColumnIfMissing(
          migrator,
          aiMemories,
          aiMemories.linkedEntityType,
        );
        await _addColumnIfMissing(
          migrator,
          aiMemories,
          aiMemories.linkedEntityId,
        );
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.relatedIds);

        await _addColumnIfMissing(
          migrator,
          dishLibrary,
          dishLibrary.servingGrams,
        );
        await _addColumnIfMissing(
          migrator,
          dishLibrary,
          dishLibrary.nutritionBasis,
        );
        await _addColumnIfMissing(
          migrator,
          dishLibrary,
          dishLibrary.basisAssumed,
        );
        await _addColumnIfMissing(
          migrator,
          dishLibrary,
          dishLibrary.sourceType,
        );
        await _addColumnIfMissing(migrator, dishLibrary, dishLibrary.sourceId);
        await _addColumnIfMissing(
          migrator,
          dishLibrary,
          dishLibrary.sourceUpdatedAt,
        );
        await _addColumnIfMissing(
          migrator,
          dishLibrary,
          dishLibrary.userEdited,
        );

        await _addColumnIfMissing(migrator, menuItems, menuItems.servingGrams);
        await _addColumnIfMissing(migrator, menuItems, menuItems.tagsJson);
        await _addColumnIfMissing(
          migrator,
          menuItems,
          menuItems.ingredientsJson,
        );

        await _addColumnIfMissing(migrator, mealItems, mealItems.sourceType);
        await _addColumnIfMissing(migrator, mealItems, mealItems.sourceId);

        final hasDishLibrary = await _tableExists('dish_library');
        final hasMealItems = await _tableExists('meal_items');
        // 回填（docs/40 §8）：
        // * 菜品库历史行：口径 perServing、份量 100 且**标为假设**；
        // * 餐记录：有 foodId → sourceType=food，否则 manual（sourceId 同步
        //   回填 foodId，来源追溯才有得看）。
        if (hasDishLibrary) {
          await customStatement(
            "UPDATE dish_library SET nutrition_basis = 'perServing' "
            "WHERE nutrition_basis IS NULL OR nutrition_basis = ''",
          );
          // 2026-10-21 RV-P2-10：先标「份量未知」的行，再统一写 100。
          // 原顺序会把**本来就有真实 100g** 的历史行也标成假设值。
          await customStatement(
            'UPDATE dish_library SET basis_assumed = 1 '
            'WHERE serving_grams IS NULL',
          );
          await customStatement(
            'UPDATE dish_library SET serving_grams = 100 '
            'WHERE serving_grams IS NULL',
          );
          await customStatement(
            "UPDATE dish_library SET source_type = 'canteen' "
            "WHERE source_type IS NULL AND source = 'ai_estimate' "
            'AND serving_window IS NOT NULL',
          );
          await customStatement(
            "UPDATE dish_library SET source_type = 'manual' "
            'WHERE source_type IS NULL',
          );
        }
        if (hasMealItems) {
          await customStatement(
            "UPDATE meal_items SET source_type = 'food', source_id = food_id "
            'WHERE food_id IS NOT NULL',
          );
          await customStatement(
            "UPDATE meal_items SET source_type = 'manual' "
            "WHERE source_type IS NULL OR source_type = ''",
          );
        }

        // 新表：按表存在性守卫（createTable 是幂等的语义由守卫提供）。
        for (final entry in <String, TableInfo<Table, dynamic>>{
          'embedding_index': embeddingIndex,
          'background_jobs': backgroundJobs,
        }.entries) {
          final exists = await customSelect(
            "SELECT 1 FROM sqlite_master "
            "WHERE type = 'table' AND name = '${entry.key}'",
          ).getSingleOrNull();
          if (exists == null) {
            await migrator.createTable(entry.value);
          }
        }
      }
      if (from < 29) {
        // S14（2026-10-19 用户授权）：记忆时间语义。纯加法；历史行把
        // `valid_from` 回填成 `created_at`（不能凭空造「现在」），
        // `valid_to` 留空 = 当时仍然有效。
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.validFrom);
        await _addColumnIfMissing(migrator, aiMemories, aiMemories.validTo);
        if (await _tableExists('ai_memories')) {
          await customStatement(
            'UPDATE ai_memories SET valid_from = created_at '
            'WHERE valid_from IS NULL',
          );
        }
      }
      if (from < 30) {
        // 2026-10-21 ADR-036（用户「存储格式定死」）：DROP 17 列——
        // 21 列契约的 15 列（只写不读）+ categoryGroup/categorySub（导入期
        // 中间量；分类是唯一指标，category 10 枚举在导入时已翻译落库）。
        // 纪律与 v26 的减法迁移同源：先查表/列在不在（无 IF EXISTS），
        // SQLite ≥3.35 才支持 DROP COLUMN（bundled sqlite3 3.45 满足）。
        final hasFoods = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'foods'",
        ).getSingleOrNull();
        if (hasFoods != null) {
          for (final column in const [
            'library_code',
            'category_group',
            'category_sub',
            'cuisine',
            'food_kind',
            'data_basis',
            'food_state',
            'source_code',
            'source_food_code',
            'original_name',
            'original_category',
            'source_note',
            'source_url',
            'recipe_summary',
            'source_nature',
          ]) {
            final hasColumn = await customSelect(
              "SELECT 1 FROM pragma_table_info('foods') WHERE name = ?",
              variables: [Variable.withString(column)],
            ).getSingleOrNull();
            if (hasColumn != null) {
              await customStatement('ALTER TABLE foods DROP COLUMN $column');
            }
          }
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<bool> hasProfile() async {
    final row = await (select(profiles)..limit(1)).getSingleOrNull();
    return row != null;
  }

  Future<void> saveConfirmedMeal({
    required MealsCompanion meal,
    required List<MealItemsCompanion> items,
  }) {
    return transaction(() async {
      await into(meals).insert(meal);
      await batch((batch) => batch.insertAll(mealItems, items));
    });
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  /// schema 28 的逐列守卫：列已存在就跳过（开发期手工加过列的库、以及
  /// 从中间版本升上来的库都靠这条保命）。
  Future<void> _addColumnIfMissing(
    Migrator migrator,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    // 迁移测试的裁剪 fixture 只包含部分表：表不在就整体跳过。
    if (!await _tableExists(table.actualTableName)) return;
    final columns = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).get();
    final exists = columns.any((row) => row.data['name'] == column.name);
    if (!exists) {
      await migrator.addColumn(table, column);
    }
  }

  Future<bool> _tableExists(String name) async {
    final row = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(name)],
    ).getSingleOrNull();
    return row != null;
  }
}

/// 让 `package:sqlite3` 在本进程里加载随包的 `libsqlcipher.so`。
///
/// **每个会调用 `sqlite3.open` 的 isolate 都要先调一次**，幂等。默认解析在
/// Android 上是 `DynamicLibrary.open('libsqlite3.so')`——系统里没有这个库，
/// 于是 `sqlite3.open` 直接抛 `ArgumentError`（不是 `SqliteException`）。
/// 主库自己走后台 isolate（`NativeDatabase.createInBackground` 的
/// `isolateSetup`），但**主 isolate 里也有裸 sqlite3 调用**：目录分片的 FTS
/// 搜索（`CatalogSearchService`）与分片导入（`CatalogShardImporter`）。只给后台
/// isolate 装上覆盖时，真机上这两条路都会失败（2026-09-16 实测：设置页显示
/// 「目录导入遇到意外错误（ArgumentError）」，搜索同样打不开分片）。
void configureSqlCipherLibrary() {
  sqlite_open.open.overrideFor(
    sqlite_open.OperatingSystem.android,
    openCipherOnAndroid,
  );
}
