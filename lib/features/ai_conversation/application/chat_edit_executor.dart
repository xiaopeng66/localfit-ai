import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/application/publish_menu_normalize_draft.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_write_failure.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart'
    show FoodRecord, NewFood;
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart'
    show HealthGoal;
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 执行器依赖束；main.dart 里所有仓储都是现成的，这里只做聚合。
final class ChatEditServices {
  const ChatEditServices({
    required this.database,
    required this.clock,
    required this.idGenerator,
    required this.foodRepository,
    required this.mealRepository,
    required this.dishLibraryRepository,
    required this.waterRepository,
    required this.measurementRepository,
    required this.planningConstraintsRepository,
    required this.canteenRepository,
    required this.workoutPlanRepository,
    required this.workoutSessionRepository,
    required this.exerciseRepository,
    required this.profileIdentityRepository,
    required this.updateWaterTargetMl,
    required this.stepsRepository,
    required this.aiMemoryRepository,
    this.foodReferenceService,
  });

  final AppDatabase database;
  final AppClock clock;

  /// 发布菜单快照（批次 B）等「需要新行 id」的通路用；与各仓储同一个生成器。
  final IdGenerator idGenerator;
  final FoodRepository foodRepository;
  final MealRepository mealRepository;
  final DishLibraryRepository dishLibraryRepository;
  final WaterRepository waterRepository;
  final MeasurementRepository measurementRepository;
  final PlanningConstraintsRepository planningConstraintsRepository;
  final CanteenRepository canteenRepository;
  final WorkoutPlanRepository workoutPlanRepository;

  /// 训练会话（批次 A：`session.start`/`set.log`/`session.finish` 的落点）。
  final WorkoutSessionRepository workoutSessionRepository;

  final ExerciseRepository exerciseRepository;
  final ProfileIdentityRepository profileIdentityRepository;

  /// 水分目标（批次 C：`targets.update` 的落点，与 `profile_edit_page` 同一用例）。
  final UpdateWaterTargetMl updateWaterTargetMl;

  /// 步数目标（批次 C：`targets.update` 的落点，与资料编辑同一仓储）。
  final StepsRepository stepsRepository;

  /// `nutritionFrom: 'food'` 分支的本地匹配（docs/40 §3.1 / docs/43 B10）。
  /// null = 未接线：显式指定 `food` 时如实失败（不静默改走 AI）。
  final FoodReferenceService? foodReferenceService;

  /// 长期记忆（S11：`memory.remember`/`memory.forget` 的落点）。
  final AiMemoryRepository aiMemoryRepository;
}

/// 把注册表里的 23 条命令落到真实仓储（docs/23 §2/§4）。
///
/// 两条贯穿性规则：
/// * **不猜目标**——id 直查优先；按名字只接受「精确同名且唯一」，零/多命中都失败。
/// * **不信 AI 的数值**——decoder 校验过一遍，这里再靠仓储自身校验兜一层，
///   任何异常都翻成可行动的人话，绝不静默吞掉。
///
/// 2026-10-04（docs/28 §6.4/§6.7）：原先 33 条。随「食谱 / 计划」整族下线
/// 退役 10 条（`recipe.create/update/delete`、`plan.create/update/delete`、
/// `pantry.set/clear`、`price.set`、`planning.preferences.set` 的存储类已被
/// 删除）。`constraints.set` **保留**：它写的 `profiles.allergenAvoidancesJson`
/// 仍被 `DailyPlanEngine` 读取，是活跃功能。
final class RepositoryChatEditExecutor implements ChatEditExecutor {
  RepositoryChatEditExecutor(this.services);

  final ChatEditServices services;

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    try {
      return await _dispatch(command);
    } on _ChatEditFailure catch (error) {
      return ChatEditApplyResult.failure(error.message, repair: error.repair);
    } on FormatException catch (error) {
      return ChatEditApplyResult.failure(error.message);
    } on FoodWriteFailure catch (error) {
      // 批次 C（2026-10-15）：自建食物守卫抛的就是它——原来没在捕获名单里，
      // 一次 `food.update` 打在**内置**食物上会直接逃逸出 apply（用户看不到
      // 人话，界面还可能红屏）。这里与其余失败同一口径：如实翻成人话。
      return ChatEditApplyResult.failure(error.message);
    } on ValidationFailure catch (error) {
      return ChatEditApplyResult.failure(error.message);
    } on StateError catch (error) {
      return ChatEditApplyResult.failure(error.message);
    } on ArgumentError catch (error) {
      return ChatEditApplyResult.failure('$error');
    } on CanteenWriteException catch (error) {
      return ChatEditApplyResult.failure(error.userMessage);
    } on AiMemoryException catch (error) {
      // S11：记忆写入被拒（重复/超限/敏感）——消息本来就是人话。
      return ChatEditApplyResult.failure(error.message);
    } on AiMemoryMergeSuggested catch (error) {
      // 2026-10-20 全应用审查 RV-P1-02：0.88–0.96 的近重复抛的是这个
      // 类型（**不是** AiMemoryException 子类）。漏在这里会让整批编辑卡
      // 卡在「应用中」——单条失败必须只让该行失败。
      return ChatEditApplyResult.failure(error.message);
    } on WaterTargetException catch (error) {
      // 同上：没有每日目标行时仓储抛它（也不是 AiMemoryException）。
      return ChatEditApplyResult.failure(error.message);
    }
  }

  Future<ChatEditApplyResult> _dispatch(ChatEditCommand command) async {
    switch (command.action) {
      case 'weight.log':
        return _weightLog(command);
      case 'water.add':
        return _waterAdd(command);
      case 'water.delete':
        return _waterDelete(command);
      case 'meal.create':
        return _mealCreate(command);
      case 'meal.update':
        return _mealUpdate(command);
      case 'meal.item.update':
        return _mealItemUpdate(command);
      case 'meal.item.delete':
        return _mealItemDelete(command);
      case 'meal.delete':
        return _mealDelete(command);
      case 'food.create':
        return _foodCreate(command);
      case 'dish.upsert':
        return _dishUpsert(command);
      case 'dish.delete':
        return _dishDelete(command);
      case 'canteen.venue.create':
        return _venueCreate(command);
      case 'canteen.venue.rename':
        return _venueRename(command);
      case 'canteen.venue.delete':
        return _venueDelete(command);
      case 'canteen.window.create':
        return _windowCreate(command);
      case 'canteen.window.delete':
        return _windowDelete(command);
      case 'canteen.dish.create':
        return _canteenDishCreate(command);
      case 'canteen.dish.update':
        return _canteenDishUpdate(command);
      case 'canteen.dish.delete':
        return _canteenDishDelete(command);
      case 'canteen.dish.nutrition':
        return _canteenDishNutrition(command);
      case 'profile.goal.update':
        return _profileGoalUpdate(command);
      case 'constraints.set':
        return _constraintsSet(command);
      case 'workout.plan.create':
        return _workoutPlanCreate(command);
      case 'workout.plan.delete':
        return _workoutPlanDelete(command);

      // ── 批次 A（2026-10-15）：训练域 ────────────────────────────────
      case 'session.start':
        return _sessionStart(command);
      case 'set.log':
        return _setLog(command);
      case 'session.finish':
        return _sessionFinish(command);
      case 'plan.entry.add':
        return _planEntryAdd(command);
      case 'plan.entry.remove':
        return _planEntryRemove(command);
      case 'plan.rename':
        return _planRename(command);

      // ── 批次 C（2026-10-15）：自建食物与资料/目标 ──────────────────
      case 'food.update':
        return _foodUpdate(command);
      case 'food.delete':
        return _foodDelete(command);
      case 'profile.body.update':
        return _profileBodyUpdate(command);
      case 'targets.update':
        return _targetsUpdate(command);

      // ── 批次 B（2026-10-15）：菜单快照发布 ──────────────────────────
      case 'menu.snapshot.publish':
        return _menuSnapshotPublish(command);

      // ── S11（2026-10-17，docs/38）：长期记忆 ────────────────────────
      case 'memory.remember':
        return _memoryRemember(command);
      case 'memory.forget':
        return _memoryForget(command);
    }
    // 注册表与 switch 必须同步；走到这里说明注册了命令没写分支（测试钉住）。
    return ChatEditApplyResult.failure('不支持的修改类型「${command.action}」。');
  }

  // ---------- 体重 / 饮水 ----------

  Future<ChatEditApplyResult> _weightLog(ChatEditCommand command) async {
    await services.measurementRepository.saveManualWeight(
      localDate: _localDate(command),
      weightKg: command.args['weightKg'] as double,
      notes: command.args['notes'] as String?,
    );
    return ChatEditApplyResult.ok('体重已记录。');
  }

  Future<ChatEditApplyResult> _waterAdd(ChatEditCommand command) async {
    await services.waterRepository.add(
      localDate: _localDate(command),
      amountMl: command.args['amountMl'] as double,
    );
    return ChatEditApplyResult.ok('饮水已记录。');
  }

  Future<ChatEditApplyResult> _waterDelete(ChatEditCommand command) async {
    final id = _idArg(command, 'waterId');
    final removed = await services.waterRepository.delete(id);
    if (removed == null) return _missing('饮水记录', id);
    return ChatEditApplyResult.ok('已删除 ${removed.amountMl}ml 的饮水记录。');
  }

  // ---------- 餐记录 ----------

  Future<ChatEditApplyResult> _mealCreate(ChatEditCommand command) async {
    final items = await _resolveMealItems(command);
    final localDate = _localDate(command);
    final slot = _slot(command);
    // 2026-10-23 用户：「AI 不查重（加午餐后再加晚餐会重复午餐计入两份）」。
    // 同一日期同一餐次已有记录时**并入**那一餐，并跳过同名食物——模型把
    // 上一餐的条目又带进这一餐的提议里时，不会在账上算两遍。
    final sameDay = await services.mealRepository.watchForDate(localDate).first;
    MealRecord? existing;
    for (final meal in sameDay) {
      if (meal.slot == slot) {
        existing = meal;
        break;
      }
    }
    if (existing != null) {
      final recordedNames = {
        for (final item in existing.items) item.foodName.trim(),
      };
      final fresh = [
        for (final item in items)
          if (!recordedNames.contains(item.food.name.trim())) item,
      ];
      if (fresh.isEmpty) {
        return ChatEditApplyResult.ok('${slot.label}已经记过这些食物，没有重复写入。');
      }
      final skipped = items.length - fresh.length;
      await services.mealRepository.update(
        existing.id,
        MealDraft(
          localDate: existing.localDate,
          slot: existing.slot,
          notes: existing.notes,
          items: [
            for (final item in existing.items) item.scaledTo(item.grams),
            for (final item in fresh)
              MealItemDraft.fromFood(item.food, item.grams),
          ],
        ),
      );
      return ChatEditApplyResult.ok(
        skipped == 0
            ? '已并入今天的${slot.label}。'
            : '已并入今天的${slot.label}（跳过 $skipped 条已记录的食物）。',
      );
    }
    // 新餐次：再按**全天**去重一次。用户实测的场景是「加午餐后再加晚餐，
    // 模型把午餐的条目又带进晚餐」——同名食物在今天的别的餐次已经记过，
    // 就不再算第二份；用户真要一天吃两次，可以手动再记。
    final recordedToday = {
      for (final meal in sameDay)
        for (final item in meal.items) item.foodName.trim(),
    };
    final fresh = [
      for (final item in items)
        if (!recordedToday.contains(item.food.name.trim())) item,
    ];
    if (fresh.isEmpty) {
      return ChatEditApplyResult.ok('今天的其他餐次已经记过这些食物，没有重复写入。');
    }
    final skipped = items.length - fresh.length;
    await services.mealRepository.saveManualMeal(
      ManualMealDraft(localDate: localDate, slot: slot, items: fresh),
    );
    return ChatEditApplyResult.ok(
      skipped == 0 ? '已记录这一餐。' : '已记录这一餐（跳过 $skipped 条今天已记录过的食物）。',
    );
  }

  Future<ChatEditApplyResult> _mealUpdate(ChatEditCommand command) async {
    final record = await _requireMeal(_idArg(command, 'mealId'));
    final newSlot = _slotOrNull(command);
    final hasNotes = command.args.containsKey('notes');
    await services.mealRepository.update(
      record.id,
      MealDraft(
        localDate: record.localDate,
        slot: newSlot ?? record.slot,
        notes: hasNotes ? (command.args['notes'] as String?) : record.notes,
        items: [for (final item in record.items) item.scaledTo(item.grams)],
      ),
    );
    return ChatEditApplyResult.ok('这一餐已更新。');
  }

  Future<ChatEditApplyResult> _mealItemUpdate(ChatEditCommand command) async {
    return _rewriteMealItems(command, removeItemId: null);
  }

  Future<ChatEditApplyResult> _mealItemDelete(ChatEditCommand command) async {
    return _rewriteMealItems(command, removeItemId: _idArg(command, 'itemId'));
  }

  /// 条目级编辑 = 找到所属餐 → 整草稿重建 → 走 [MealRepository.update]。
  /// 餐记录仓储没有单条目 API，这是它的既有写路径，不绕过。
  Future<ChatEditApplyResult> _rewriteMealItems(
    ChatEditCommand command, {
    required String? removeItemId,
  }) async {
    final itemId = removeItemId ?? _idArg(command, 'itemId');
    final meal = await _findMealContainingItem(itemId);
    final drafts = <MealItemDraft>[];
    var hit = false;
    for (final item in meal.items) {
      if (item.id == itemId) {
        hit = true;
        if (removeItemId == null) {
          drafts.add(item.scaledTo(command.args['grams'] as double));
        }
        continue;
      }
      drafts.add(item.scaledTo(item.grams));
    }
    if (!hit) return _missing('餐条目', itemId);
    if (drafts.isEmpty) {
      return const ChatEditApplyResult.failure('这餐只有这一条食物；要删整餐请说「删掉这餐」。');
    }
    await services.mealRepository.update(
      meal.id,
      MealDraft(
        localDate: meal.localDate,
        slot: meal.slot,
        notes: meal.notes,
        items: drafts,
      ),
    );
    return ChatEditApplyResult.ok(
      removeItemId == null ? '克数已改为 ${command.args['grams']}g。' : '条目已删除。',
    );
  }

  Future<ChatEditApplyResult> _mealDelete(ChatEditCommand command) async {
    final id = _idArg(command, 'mealId');
    final removed = await services.mealRepository.delete(id);
    if (removed == null) return _missing('餐记录', id);
    return ChatEditApplyResult.ok(
      '已删除 ${removed.localDate} ${removed.slot.label} 的记录。',
    );
  }

  // ---------- 食材 ----------

  Future<ChatEditApplyResult> _foodCreate(ChatEditCommand command) async {
    final name = command.args['name'] as String;
    final duplicates = await services.foodRepository.searchExact(name);
    // 2026-10-23 用户：「不主动检索食物库已有食物（先推卡片再说已有/失败）」。
    // 应用前先查库：已有同名食物就**直接引用**（不新建、不报错），让「新建」
    // 这条提议落到用户真正想要的结果上；同名多条才需要用户指定。
    if (duplicates.length == 1) {
      return ChatEditApplyResult.ok(
        '食材库里已有「${duplicates.single.name}」，已直接引用（未新建）。',
      );
    }
    if (duplicates.length > 1) {
      return ChatEditApplyResult.failure(
        '食材库里已有 ${duplicates.length} 条「$name」，请用快照里的 id 指定要用哪一条。',
      );
    }
    final created = await services.foodRepository.create(
      NewFood(
        name: name,
        kcalPer100g: command.args['kcalPer100g'] as double,
        proteinPer100g: command.args['proteinPer100g'] as double,
        carbsPer100g: command.args['carbsPer100g'] as double,
        fatPer100g: command.args['fatPer100g'] as double,
        defaultServingGrams: command.args['servingGrams'] as double?,
        brand: command.args['brand'] as String?,
      ),
    );
    return ChatEditApplyResult.ok('已创建食材「${created.name}」。');
  }

  // ---------- 约束 ----------

  Future<ChatEditApplyResult> _constraintsSet(ChatEditCommand command) async {
    final labels = command.args['dietaryLabels'] as List<Object>?;
    final allergens = command.args['allergenAvoidances'] as List<Object>?;
    if (labels == null && allergens == null) {
      return const ChatEditApplyResult.failure('要说清要改哪一项：饮食约束还是回避过敏原。');
    }
    await services.planningConstraintsRepository.save(
      PlanningConstraints(
        dietaryLabels: [
          for (final value in labels ?? const <Object>[])
            _parseDietaryLabel(value as String),
        ],
        allergenAvoidances: [
          for (final value in allergens ?? const <Object>[])
            if ((value as String).trim().isNotEmpty) value.trim(),
        ],
      ),
    );
    return ChatEditApplyResult.ok('饮食约束已更新。');
  }

  // ---------- 菜品库 ----------

  Future<ChatEditApplyResult> _dishUpsert(ChatEditCommand command) async {
    final record = await services.dishLibraryRepository.upsertByName(
      DishDraft(
        name: command.args['name'] as String,
        mealSlot: command.args['slot'] as String,
        kcal: command.args['kcal'] as double,
        proteinG: command.args['protein'] as double,
        carbsG: command.args['carbs'] as double,
        fatG: command.args['fat'] as double,
        source: 'ai_chat',
        comment: command.args['comment'] as String?,
      ),
    );
    return ChatEditApplyResult.ok('菜品「${record.name}」已写入菜品库。');
  }

  Future<ChatEditApplyResult> _dishDelete(ChatEditCommand command) async {
    final id = _idArg(command, 'dishId');
    final removed = await services.dishLibraryRepository.delete(id);
    if (removed == null) return _missing('菜品', id);
    return ChatEditApplyResult.ok('已删除菜品「${removed.name}」。');
  }

  // ---------- 食堂 ----------

  Future<ChatEditApplyResult> _venueCreate(ChatEditCommand command) async {
    final id = await services.canteenRepository.createVenue(
      name: command.args['name'] as String,
      campusName: command.args['campus'] as String,
    );
    return ChatEditApplyResult.ok('已新建地点（$id）。');
  }

  Future<ChatEditApplyResult> _venueRename(ChatEditCommand command) async {
    final venue = await _requireVenue(_idArg(command, 'venueId'));
    await services.canteenRepository.renameVenue(
      venue.id,
      command.args['name'] as String,
    );
    return ChatEditApplyResult.ok('地点已改名。');
  }

  Future<ChatEditApplyResult> _venueDelete(ChatEditCommand command) async {
    final id = _idArg(command, 'venueId');
    final venue = await _requireVenue(id);
    await services.canteenRepository.deleteVenue(id);
    return ChatEditApplyResult.ok('已删除地点「${venue.name}」及其全部窗口与菜品。');
  }

  Future<ChatEditApplyResult> _windowCreate(ChatEditCommand command) async {
    final venue = await _resolveVenueRef(command.args['venue'] as String);
    final id = await services.canteenRepository.createWindow(
      venueId: venue.id,
      name: command.args['name'] as String,
      openTime: command.args['openTime'] as String,
      closeTime: command.args['closeTime'] as String,
    );
    return ChatEditApplyResult.ok('已新建窗口（$id）。');
  }

  Future<ChatEditApplyResult> _windowDelete(ChatEditCommand command) async {
    final id = _idArg(command, 'windowId');
    await _requireWindow(id);
    await services.canteenRepository.deleteWindow(id);
    return ChatEditApplyResult.ok('窗口及其菜品已删除。');
  }

  Future<ChatEditApplyResult> _canteenDishCreate(
    ChatEditCommand command,
  ) async {
    // `nutritionFrom`（docs/43 B10）：缺省 none = 旧行为逐字节不变。
    final from = _nutritionFrom(command);
    final window = await _resolveWindowRef(command.args['window'] as String);
    final id = await services.canteenRepository.createDish(
      windowId: window.id,
      name: command.args['name'] as String,
    );
    final applied = from == 'food'
        ? await _applyFoodNutrition(
            dishId: id,
            dishName: command.args['name'] as String,
          )
        : null;
    if (applied != null && !applied.ok) {
      // 2026-10-20 审查 RV-P1-04：菜**已经落库**。回报「失败」会让用户
      // 重试 → 同名重复菜（createDish 无去重）。如实报「部分成功」。
      return ChatEditApplyResult.ok('已新增菜品（$id），但营养未填写：${applied.message}');
    }
    return ChatEditApplyResult.ok('已新增菜品（$id）${applied?.message ?? ''}');
  }

  /// 读取并校验 `nutritionFrom`（`food|ai|none`）。
  ///
  /// 两条命令的缺省不同，与旧行为一致：
  /// * `canteen.dish.create` 缺省 `none`（建菜不填营养）；
  /// * `canteen.dish.nutrition` 缺省 `ai`（这条命令本身就是写 AI 估算值）。
  String _nutritionFrom(ChatEditCommand command, {String fallback = 'none'}) {
    final raw = command.args['nutritionFrom'];
    if (raw == null) return fallback;
    final value = raw is String ? raw.trim().toLowerCase() : '';
    if (!const {'food', 'ai', 'none'}.contains(value)) {
      _fail('营养来源「$raw」不认识，只能是 food / ai / none。');
    }
    return value;
  }

  /// `nutritionFrom='food'`：本地食物库精确/别名匹配 → 写证据（origin=
  /// `food_library`、grade 沿用、链接 confirmed）。
  ///
  /// **未命中给可行动文案，不静默改走 AI**（docs/40 §3.1）。
  Future<ChatEditApplyResult?> _applyFoodNutrition({
    required String dishId,
    required String dishName,
  }) async {
    final service = services.foodReferenceService;
    if (service == null) {
      return ChatEditApplyResult.failure(
        '食物库匹配未接线，不能按「食物库」填「$dishName」的营养；'
        '请改用 AI 分析或手动填写。',
      );
    }
    final List<FoodReferenceCandidate> candidates;
    try {
      candidates = await service.suggestForDish(dishId, limit: 1);
    } on Object {
      return ChatEditApplyResult.failure(
        '食物库匹配置信度不足，无法为「$dishName」引用营养；'
        '请改用 AI 分析或手动填写。',
      );
    }
    if (candidates.isEmpty) {
      return ChatEditApplyResult.failure('食物库没有「$dishName」，请改用 AI 分析或手动填写。');
    }
    final candidate = candidates.first;
    // 精确同名才算「引用」；包含匹配（「米饭」→「米饭饼」）不是同一件东西。
    if (candidate.confidence < _foodExactConfidence) {
      return ChatEditApplyResult.failure(
        '食物库只有相近条目「${candidate.foodName}」，不是同一个菜；'
        '请改用 AI 分析或手动填写。',
      );
    }
    try {
      // 2026-10-21 RV-P2-07：证据写入与链接确认必须同事务——否则链接失败时
      // 证据已落库、界面却报失败，用户重试会再写一条证据。
      await services.database.transaction(() async {
        await services.canteenRepository.recordNutrition(
          dishId: dishId,
          kcalPer100g: candidate.kcalPer100g,
          proteinPer100g: candidate.proteinPer100g,
          carbsPer100g: candidate.carbsPer100g,
          fatPer100g: candidate.fatPer100g,
          // 证据等级沿用食物条目状态（verified→A / 自建→B / 其他→C）。
          grade: switch (candidate.state) {
            'verified' => 'A',
            'user_created' => 'B',
            _ => 'C',
          },
          confidence: candidate.confidence,
          origin: 'food_library',
          sourceText: '引用食物库「${candidate.foodName}」',
        );
        await service.confirmAdoption(dishId, candidate.foodId);
      });
    } on CanteenWriteException catch (error) {
      return ChatEditApplyResult.failure(error.userMessage);
    } on Object {
      return ChatEditApplyResult.failure('引用食物库营养失败，请稍后重试。');
    }
    return ChatEditApplyResult.ok('，营养引用自食物库「${candidate.foodName}」（每 100g）。');
  }

  /// 精确同名阈值（与 `MenuItemMatcher.confidenceContains` 之上留出余量）。
  static const double _foodExactConfidence = 0.9;

  /// `canteen.dish.nutrition`（2026-10-16）：把 AI 估的营养写进**证据表**。
  ///
  /// 落点与菜品库那条不同：这里写的是 `menu_item_nutrition_evidence`
  /// （等级 + 置信度 + 逐项营养）+ 回写 `menu_items` 的状态/等级标签，读侧
  /// `listDishes` 取最新一条证据 ⇒ 食堂目录里那一行立刻从「未分析营养」
  /// 变成「等级徽标 + 每 100g 热量 + 三大宏量点」，地点统计的「已分析 N」
  /// 也跟着变（这正是用户报的缺陷：分析完目录里什么都没变）。
  Future<ChatEditApplyResult> _canteenDishNutrition(
    ChatEditCommand command,
  ) async {
    final dishId = _idArg(command, 'dishId');
    final row =
        await (services.database.select(services.database.menuItems)
              ..where((item) => item.id.equals(dishId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      _fail('菜品「$dishId」不存在（可能已被删除）。');
    }
    // `nutritionFrom`（docs/43 B10）：缺省 ai = 旧行为逐字节不变。
    final from = _nutritionFrom(command, fallback: 'ai');
    if (from == 'food') {
      // 显式要食物库：本地匹配命中就写（忽略命令里自带的数值），
      // 未命中如实失败——**不静默改走 AI**。
      final applied = await _applyFoodNutrition(
        dishId: dishId,
        dishName: row.displayName,
      );
      return applied ??
          ChatEditApplyResult.failure(
            '食物库匹配未接线，不能按「食物库」填「${row.displayName}」的营养。',
          );
    }
    if (from == 'none') {
      return ChatEditApplyResult.ok(
        '按 nutritionFrom=none 跳过写入（「${row.displayName}」营养未变）。',
      );
    }
    // 等级缺省按**最保守**的 D（粗估）——不替模型把证据等级说高。非法值
    // 直接拒绝（登记表只认 A/B/C/D）。
    final rawGrade = command.args['grade'];
    final grade = rawGrade is String ? rawGrade.trim().toUpperCase() : 'D';
    if (!const {'A', 'B', 'C', 'D'}.contains(grade)) {
      _fail('证据等级「$rawGrade」不认识，只能是 A/B/C/D。');
    }
    final confidence = command.args['confidence'] as double? ?? 0.5;
    await services.canteenRepository.recordNutrition(
      dishId: dishId,
      kcalPer100g: command.args['kcalPer100g'] as double,
      proteinPer100g: command.args['proteinPer100g'] as double,
      carbsPer100g: command.args['carbsPer100g'] as double,
      fatPer100g: command.args['fatPer100g'] as double,
      grade: grade,
      confidence: confidence,
    );
    return ChatEditApplyResult.ok(
      '已记录「${row.displayName}」的营养：'
      '${_trimNumber(command.args['kcalPer100g'] as double)} kcal/100g'
      '（等级 $grade）。',
    );
  }

  Future<ChatEditApplyResult> _canteenDishUpdate(
    ChatEditCommand command,
  ) async {
    final dishId = _idArg(command, 'dishId');
    // 仓储的 updateDish 是整行写（name 必填非空）：只改价格时必须带上
    // 现名，否则「名称不能为空」会把纯价格更新打回去。
    final current = await (services.database.select(
      services.database.menuItems,
    )..where((row) => row.id.equals(dishId))).getSingleOrNull();
    if (current == null) return _missing('菜品', dishId);
    await services.canteenRepository.updateDish(
      dishId: dishId,
      name: (command.args['name'] as String?) ?? current.displayName,
    );
    return ChatEditApplyResult.ok('菜品已更新。');
  }

  Future<ChatEditApplyResult> _canteenDishDelete(
    ChatEditCommand command,
  ) async {
    final id = _idArg(command, 'dishId');
    await _requireCanteenDish(id);
    await services.canteenRepository.deleteDish(id);
    return ChatEditApplyResult.ok('菜品已删除。');
  }

  // ---------- 档案 / 训练计划 ----------

  // ── 批次 A：训练会话与计划编排（2026-10-15，docs/34 §5）──────────────

  /// 解析「进行中的会话」：显式给的 id 优先，否则取当前活跃会话。
  Future<WorkoutSessionRecord> _requireActiveSession(String? rawId) async {
    final explicit = rawId == null ? null : normalizeTargetId(rawId);
    if (explicit != null) {
      final record = await services.workoutSessionRepository.getById(explicit);
      if (record == null) _fail('训练会话「$explicit」不存在。');
      if (record.status != 'active') {
        _fail('这次训练已经结束了（${record.completedSetCount} 组已保存）。');
      }
      return record;
    }
    final active = await services.workoutSessionRepository.getActive();
    if (active == null) {
      _fail('现在没有进行中的训练；先说「开始训练」再记组。');
    }
    return active;
  }

  Future<ChatEditApplyResult> _sessionStart(ChatEditCommand command) async {
    final existing = await services.workoutSessionRepository.getActive();
    if (existing != null) {
      return ChatEditApplyResult.failure(
        '已经有一次进行中的训练（已记录 ${existing.completedSetCount} 组）；'
        '先在训练页结束它，或直接把组记在这次里。',
      );
    }
    final rawPlanId = command.args['planId'] as String?;
    String? planId;
    if (rawPlanId != null) {
      planId = normalizeTargetId(rawPlanId);
      final plan = await services.workoutPlanRepository.getById(planId);
      if (plan == null) {
        return ChatEditApplyResult.failure('训练计划「$planId」不存在，无法开始。');
      }
    }
    final sessionId = await services.workoutSessionRepository.start(
      localDate: _localDate(command),
      planId: planId,
    );
    assert(sessionId.isNotEmpty);
    return ChatEditApplyResult.ok(
      planId == null ? '开始了一次自由训练。' : '已按这份计划开始训练。',
    );
  }

  Future<ChatEditApplyResult> _setLog(ChatEditCommand command) async {
    final session = await _requireActiveSession(
      command.args['sessionId'] as String?,
    );
    final exercise = await _resolveExerciseByName(
      command.args['exercise'] as String,
    );
    final rpe = command.args['rpe'] as double?;
    await services.workoutSessionRepository.logSet(
      session.id,
      WorkoutSetDraft(
        exerciseId: exercise.id,
        weightKg: command.args['weightKg'] as double,
        reps: command.args['reps'] as int,
        rpe: rpe,
      ),
    );
    final updated = await services.workoutSessionRepository.getById(session.id);
    final total = updated?.completedSetCount ?? session.completedSetCount + 1;
    return ChatEditApplyResult.ok(
      '已记录 ${exercise.name} '
      '${_trimNumber(command.args['weightKg'] as double)}kg × '
      '${command.args['reps']} 次（这次训练共 $total 组）。',
    );
  }

  Future<ChatEditApplyResult> _sessionFinish(ChatEditCommand command) async {
    final session = await _requireActiveSession(
      command.args['sessionId'] as String?,
    );
    final sets = session.completedSetCount;
    await services.workoutSessionRepository.finish(session.id);
    return ChatEditApplyResult.ok('训练已结束，共保存 $sets 组。');
  }

  Future<ChatEditApplyResult> _planEntryAdd(ChatEditCommand command) async {
    final planId = _idArg(command, 'planId');
    final plan = await services.workoutPlanRepository.getById(planId);
    if (plan == null) {
      return ChatEditApplyResult.failure('训练计划「$planId」不存在。');
    }
    final exercise = await _resolveExerciseByName(
      command.args['exercise'] as String,
    );
    final weekday = command.args['weekday'] as int;
    await services.workoutPlanRepository.addEntry(
      planId,
      weekday,
      PlannedExerciseDraft(
        exerciseId: exercise.id,
        targetSets: command.args['sets'] as int,
        targetReps: command.args['reps'] as int,
        targetWeightKg: command.args['weightKg'] as double?,
      ),
    );
    return ChatEditApplyResult.ok(
      '已给「${plan.name}」星期${workoutWeekdayLabel(weekday)}加上 '
      '${exercise.name}（${command.args['sets']} 组 × '
      '${command.args['reps']} 次）。',
    );
  }

  Future<ChatEditApplyResult> _planEntryRemove(ChatEditCommand command) async {
    final entryId = _idArg(command, 'entryId');
    final removed = await services.workoutPlanRepository.removeEntry(entryId);
    if (!removed) {
      return ChatEditApplyResult.failure('动作条目「$entryId」不存在（可能已被移除）。');
    }
    return ChatEditApplyResult.ok('已从计划里移除这个动作。');
  }

  Future<ChatEditApplyResult> _planRename(ChatEditCommand command) async {
    final planId = _idArg(command, 'planId');
    final name = command.args['name'] as String;
    final renamed = await services.workoutPlanRepository.renamePlan(
      planId,
      name,
    );
    if (!renamed) {
      return ChatEditApplyResult.failure('训练计划「$planId」不存在。');
    }
    return ChatEditApplyResult.ok('计划已改名为「${name.trim()}」。');
  }

  // ── 批次 C：自建食物与资料/目标（2026-10-15，docs/34 §5）────────────

  Future<ChatEditApplyResult> _foodUpdate(ChatEditCommand command) async {
    final id = _idArg(command, 'foodId');
    final current = await services.foodRepository.getById(id);
    if (current == null) return _missing('自建食物', id);
    // 仓储自己还有一道 `_requireUserCreated` 守卫（抛 FoodWriteFailure）；
    // 这里先看一眼是为了把「内置不能改」这句话说得更早、更具体。
    if (!current.isUserCreated) {
      return ChatEditApplyResult.failure('「${current.name}」是内置食物，不能修改。');
    }
    final updated = await services.foodRepository.update(
      id,
      NewFood(
        name: command.args['name'] as String,
        kcalPer100g: command.args['kcalPer100g'] as double,
        proteinPer100g: command.args['proteinPer100g'] as double,
        carbsPer100g: command.args['carbsPer100g'] as double,
        fatPer100g: command.args['fatPer100g'] as double,
        defaultServingGrams: command.args['servingGrams'] as double?,
        brand: command.args['brand'] as String?,
        // **保留原分类**：`update` 的语义是「把表单拥有的列写成表单里的
        // 样子」，而 AI 命令没有「种类」这个参数——传 null 会静默清掉
        // 用户自己选的分类。
        category: current.category,
      ),
      // 2026-10-21 RV-P2-02：参数给了就写；没给保留旧值（不再静默丢弃）。
      defaultServingGrams: command.args['servingGrams'] as double?,
    );
    return ChatEditApplyResult.ok('已更新自建食物「${updated.name}」。');
  }

  Future<ChatEditApplyResult> _foodDelete(ChatEditCommand command) async {
    final id = _idArg(command, 'foodId');
    final current = await services.foodRepository.getById(id);
    if (current == null) return _missing('自建食物', id);
    if (!current.isUserCreated) {
      return ChatEditApplyResult.failure('「${current.name}」是内置食物，不能删除。');
    }
    // 删前把影响面说清楚（只读计数）：仓储会把餐记录里这一项的 foodId
    // 置空、保留当次营养快照——用户有权先知道有几条餐记录被牵动。
    final referenced = await (services.database.select(
      services.database.mealItems,
    )..where((row) => row.foodId.equals(id))).get().then((rows) => rows.length);
    await services.foodRepository.delete(id);
    return ChatEditApplyResult.ok(
      referenced == 0
          ? '已删除自建食物「${current.name}」。'
          : '已删除自建食物「${current.name}」；'
                '$referenced 条餐记录里保留着当次名称与营养，不受影响。',
    );
  }

  Future<ChatEditApplyResult> _profileBodyUpdate(
    ChatEditCommand command,
  ) async {
    final current = await services.profileIdentityRepository.loadBodyProfile();
    if (current == null) {
      return const ChatEditApplyResult.failure('还没有本地档案，请先完成建档。');
    }
    final heightCm = command.args['heightCm'] as double? ?? current.heightCm;
    final birthYear = command.args['birthYear'] as int? ?? current.birthYear;
    final rawSex = command.args['sex'] as String?;
    if (rawSex != null && rawSex != 'female' && rawSex != 'male') {
      // 只认仓内枚举（`BiologicalSex{female, male}`）：它进热量公式，
      // 收下第三个值就等于让一个不认识的值参与计算。
      return ChatEditApplyResult.failure('生理性别只接受 female 或 male。');
    }
    final biologicalSex = rawSex ?? current.biologicalSex;
    await services.profileIdentityRepository.updateBodyProfile(
      heightCm: heightCm,
      birthYear: birthYear,
      biologicalSex: biologicalSex,
    );
    final parts = <String>[
      if (command.args.containsKey('heightCm'))
        '身高 ${_trimNumber(heightCm!)}cm',
      if (command.args.containsKey('birthYear')) '出生年 $birthYear',
      if (rawSex != null) '生理性别 ${rawSex == 'female' ? '女' : '男'}',
    ];
    return ChatEditApplyResult.ok('已更新：${parts.join('、')}。');
  }

  Future<ChatEditApplyResult> _targetsUpdate(ChatEditCommand command) async {
    final waterMl = command.args['waterMl'] as double?;
    final steps = command.args['steps'] as int?;
    if (waterMl == null && steps == null) {
      return const ChatEditApplyResult.failure(
        '要说清改哪个目标：饮水（waterMl）或步数（steps）。',
      );
    }
    final parts = <String>[];
    if (waterMl != null) {
      await services.updateWaterTargetMl.run(
        targetMl: waterMl,
        today: _localDate(command),
      );
      parts.add('每日饮水目标 ${(waterMl / 1000).toStringAsFixed(1)}L');
    }
    if (steps != null) {
      await services.stepsRepository.updateDailyGoal(steps);
      parts.add('每日步数目标 $steps 步');
    }
    return ChatEditApplyResult.ok('已更新：${parts.join('、')}。');
  }

  // ── 批次 B：菜单快照发布（2026-10-15，docs/34 §7）────────────────────

  Future<ChatEditApplyResult> _menuSnapshotPublish(
    ChatEditCommand command,
  ) async {
    final rawJson = command.args['menuJson'] as String;
    final MenuNormalizeDraft draft;
    try {
      draft = const MenuNormalizeJsonDecoder().decode(rawJson);
    } on MenuNormalizeFormatException catch (error) {
      // 解码器的报错是逐条英文技术口径（给开发者看）；这里翻成人话并把
      // **条数**说清楚，具体条目让用户回菜单文件/文本里核对。
      final count = error.violations.length;
      return ChatEditApplyResult.failure(
        '菜单草案不合格（$count 处问题），没有发布。'
        '请核对：schema_version=1、source_date、venue_name、'
        '每个窗口的 service_name 与 HH:mm 时间、每道菜的 display_name。',
      );
    }
    try {
      final result = await PublishMenuNormalizeDraft(
        database: services.database,
        idGenerator: services.idGenerator,
        clock: services.clock,
      ).call(draft);
      if (result.duplicateOf != null) {
        return ChatEditApplyResult.ok(
          '这份菜单与既有快照内容一致，已跳过重复发布（快照 ${result.duplicateOf}）。',
        );
      }
      final items = draft.services.fold<int>(
        0,
        (sum, service) => sum + service.items.length,
      );
      return ChatEditApplyResult.ok(
        '菜单快照已发布：${draft.venueName} · '
        '${draft.services.length} 个窗口 · $items 道菜。',
      );
    } on MenuPublishException catch (error) {
      // `userMessage` 为 null 时**不得回显 errors**（docs/11 §3-B 白名单化）
      // ⇒ 用固定兜底文案。
      return ChatEditApplyResult.failure(
        error.userMessage ?? '菜单快照发布失败，已回滚，未写入任何数据。',
      );
    }
  }

  /// 数值去掉多余的小数点（`0.0` → `0`、`62.50` → `62.5`）。
  String _trimNumber(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  Future<ChatEditApplyResult> _profileGoalUpdate(
    ChatEditCommand command,
  ) async {
    final hasGoal = await (services.database.select(
      services.database.goals,
    )..limit(1)).getSingleOrNull();
    if (hasGoal == null) {
      return const ChatEditApplyResult.failure('还没有历史目标记录，请先在「我的」完成建档再改目标。');
    }
    await services.profileIdentityRepository.updateGoal(
      goal: HealthGoal.values.byName(command.args['goal'] as String),
      targetWeightKg: command.args['targetWeightKg'] as double?,
    );
    return ChatEditApplyResult.ok('健康目标已更新。');
  }

  /// 创建训练计划（docs/32 §4 T6b / §3 D5）。
  ///
  /// 安全属性（原任务管线退役后**重钉到这里**）：
  /// * 动作名 → 库内 **精确同名且唯一** 解析；未知或歧义**整条拒绝**
  ///   （错误文案进编辑卡，不静默改名、不猜最近似）；
  /// * 参数已由 `planDays` 机械校验过一遍，这里靠 `WorkoutPlanRepository.create`
  ///   的 `_validateDraft`/`_requireExercise` 二次把关；
  /// * 落库 source 记 `ai`（与训练页「AI 生成计划」同一口径）。
  Future<ChatEditApplyResult> _workoutPlanCreate(
    ChatEditCommand command,
  ) async {
    final name = command.args['name'] as String;
    final rawDays = command.args['days'] as List;
    final days = <WorkoutPlanDayDraft>[];
    for (final rawDay in rawDays) {
      final day = rawDay as Map;
      final weekday = day['weekday'] as int;
      final entries = <PlannedExerciseDraft>[];
      for (final rawEntry in day['entries'] as List) {
        final entry = rawEntry as Map;
        final exerciseName = entry['exercise'] as String;
        final exercise = await _resolveExerciseByName(exerciseName);
        entries.add(
          PlannedExerciseDraft(
            exerciseId: exercise.id,
            targetSets: entry['sets'] as int,
            targetReps: entry['reps'] as int,
            targetWeightKg: entry['weightKg'] as double?,
          ),
        );
      }
      days.add(WorkoutPlanDayDraft(weekday: weekday, entries: entries));
    }
    final planId = await services.workoutPlanRepository.create(
      WorkoutPlanDraft(name: name, days: days),
      source: 'ai',
    );
    final total = days.fold<int>(0, (sum, day) => sum + day.entries.length);
    // planId 落库即可；应用结果只带一句人话（与其余命令一致）。
    assert(planId.isNotEmpty);
    return ChatEditApplyResult.ok(
      '训练计划「$name」已创建（${days.length} 个训练日、$total 条动作）。',
    );
  }

  /// 动作名 → 库内条目：**精确同名且唯一**才接受（docs/23 §4「不猜目标」）。
  Future<ExerciseRecord> _resolveExerciseByName(String name) async {
    final matches = await services.exerciseRepository.findByExactName(name);
    if (matches.isEmpty) {
      // 2026-10-16（用户要求把兜底扩到更多缺实体）：给出**可点的新建入口**
      // ——点开预填名称的「新建动作」弹层，而不是让用户自己去动作库摸路。
      throw _ChatEditFailure(
        '动作库里没有「$name」，先在训练页的动作库添加它。',
        repair: ChatEditRepair.createExercise(name: name),
      );
    }
    if (matches.length > 1) {
      _fail('动作库里「$name」有多条同名记录，请先在动作库改名区分。');
    }
    return matches.single;
  }

  Future<ChatEditApplyResult> _workoutPlanDelete(
    ChatEditCommand command,
  ) async {
    final id = _idArg(command, 'planId');
    final removed = await services.workoutPlanRepository.removePlan(id);
    if (!removed) return _missing('训练计划', id);
    return ChatEditApplyResult.ok('训练计划已删除。');
  }

  // ---------- 解析与工具 ----------

  Never _fail(String message) => throw _ChatEditFailure(message);

  Future<CanteenWindow> _requireWindow(String id) async {
    for (final venue in await services.canteenRepository.listVenues()) {
      for (final window in await services.canteenRepository.listWindows(
        venue.id,
      )) {
        if (window.id == id) return window;
      }
    }
    _fail('窗口「$id」不存在（可能已被删除）。');
  }

  Future<void> _requireCanteenDish(String id) async {
    final row = await (services.database.select(
      services.database.menuItems,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) _fail('菜品「$id」不存在（可能已被删除）。');
  }

  DietaryLabel _parseDietaryLabel(String value) {
    for (final label in DietaryLabel.values) {
      if (value == label.name || value == label.label) return label;
    }
    _fail('「$value」不是可用的饮食约束（素食/纯素/无乳制品/无麸质）。');
  }

  /// 快照里的**展示别名**前缀（`[water:mx-1]` / `[meal:mx-2]` /
  /// `[canteen-dish:mx-3]`…）。真实模型会把方括号里的整串当 id 回填
  /// （2026-10-15 实测：deepseek-v4.1-flash 与 GLM-5.3-Flash 都出现过），
  /// 所以凡「`<别名>:<真 id>`」形状的值先剥一层；**剥完查不到仍如实报
  /// 不存在**，绝不按模糊匹配猜目标。
  /// 别名表 = `DriftChatEditContextLoader` 实际会印出的**全部**前缀
  /// （`grep "'\[" chat_edit_context_loader.dart` 一次性对齐）：
  /// `[water:]`/`[meal:]`/`[item:]`/`[dish:]`/`[venue:]`/`[window:]`/
  /// `[canteen-dish:]`/`[wplan:]`/`[pentry:]`。多留几个近义写法（plan/goal/weight…）
  /// 只是容忍，剥完仍查不到就按不存在报，不猜。
  static const _snapshotIdAliases = {
    'water',
    'meal',
    'item',
    'dish',
    'food',
    'venue',
    'window',
    'canteen-dish',
    'wplan',
    'pentry',
    'plan',
    'goal',
    'weight',
    'measurement',
  };

  static String normalizeTargetId(String raw) {
    final value = raw.trim();
    final index = value.indexOf(':');
    if (index <= 0) return value;
    final prefix = value.substring(0, index).toLowerCase();
    return _snapshotIdAliases.contains(prefix)
        ? value.substring(index + 1).trim()
        : value;
  }

  /// 读一个 id 形参（顺手归一化快照别名）。
  String _idArg(ChatEditCommand command, String name) =>
      normalizeTargetId(command.args[name] as String);

  ChatEditApplyResult _missing(String kind, String id) =>
      ChatEditApplyResult.failure('$kind「$id」不存在（可能已被删除），请刷新后重试。');

  String _localDate(ChatEditCommand command) {
    final explicit = command.args['localDate'] as String?;
    if (explicit == null) return formatLocalDate(services.clock.nowUtc());
    // 2026-10-21 RV-P2-08：记录语义不允许未来日期（UI 的日期选择器本来
    // 就 lastDate=today；AI 路径此前可写 2099 年，快照还会被未来餐挤掉）。
    final today = formatLocalDate(services.clock.nowUtc());
    if (explicit.compareTo(today) > 0) {
      _fail('不能记录未来日期（$explicit）；请改成今天（$today）或更早。');
    }
    return explicit;
  }

  MealSlot _slot(ChatEditCommand command) =>
      MealSlot.fromStoredValue(command.args['slot'] as String);

  MealSlot? _slotOrNull(ChatEditCommand command) =>
      command.args.containsKey('slot')
      ? MealSlot.fromStoredValue(command.args['slot'] as String)
      : null;

  Future<MealRecord> _requireMeal(String id) async {
    final record = await services.mealRepository.getById(id);
    if (record == null) _fail('餐记录「$id」不存在（可能已被删除）。');
    return record;
  }

  Future<MealRecord> _findMealContainingItem(String itemId) async {
    final meals = await services.mealRepository.listRecent(limit: 100);
    for (final meal in meals) {
      if (meal.items.any((item) => item.id == itemId)) return meal;
    }
    _fail('餐条目「$itemId」不存在（只支持最近 100 条餐记录里的条目）。');
  }

  Future<CanteenVenue> _requireVenue(String id) async {
    for (final venue in await services.canteenRepository.listVenues()) {
      if (venue.id == id) return venue;
    }
    _fail('食堂地点「$id」不存在（可能已被删除）。');
  }

  /// `food` 参数：先试 id，再试「精确同名唯一」。
  Future<FoodRecord> _resolveFoodRef(String reference) async {
    final byId = await services.foodRepository.getById(reference);
    if (byId != null) return byId;
    final matches = await services.foodRepository.searchExact(reference);
    if (matches.isEmpty) {
      // 2026-10-16（用户：缺食材要弹「创建鸡蛋食材」按钮）：失败不只是人话，
      // 还带一个**可行动作**——编辑卡据此渲染「创建食材「X」」按钮。
      throw _ChatEditFailure(
        '找不到食材「$reference」。没有的食材要先用 food.create 创建。',
        repair: ChatEditRepair.createFood(name: reference),
      );
    }
    if (matches.length > 1) {
      _fail('「$reference」命中 ${matches.length} 条同名食材，请用快照里的 id 指定。');
    }
    return matches.single;
  }

  Future<CanteenVenue> _resolveVenueRef(String reference) async {
    final venues = await services.canteenRepository.listVenues();
    for (final venue in venues) {
      if (venue.id == reference) return venue;
    }
    final byName = venues.where((venue) => venue.name == reference).toList();
    if (byName.isEmpty) {
      throw _ChatEditFailure(
        '找不到食堂地点「$reference」。',
        repair: ChatEditRepair.createVenue(name: reference),
      );
    }
    if (byName.length > 1) {
      _fail('「$reference」命中 ${byName.length} 个同名地点，请用 id 指定。');
    }
    return byName.single;
  }

  Future<CanteenWindow> _resolveWindowRef(String reference) async {
    for (final venue in await services.canteenRepository.listVenues()) {
      for (final window in await services.canteenRepository.listWindows(
        venue.id,
      )) {
        if (window.id == reference) return window;
      }
    }
    final matches = <CanteenWindow>[];
    for (final venue in await services.canteenRepository.listVenues()) {
      for (final window in await services.canteenRepository.listWindows(
        venue.id,
      )) {
        if (window.name == reference) matches.add(window);
      }
    }
    if (matches.isEmpty) {
      // 窗口修复必须知道它属于哪个地点：引用是「地点内精确同名」，所以
      // 从那次搜索里把地点带出来。
      String? venueId;
      for (final venue in await services.canteenRepository.listVenues()) {
        for (final window in await services.canteenRepository.listWindows(
          venue.id,
        )) {
          if (window.name == reference) venueId = venue.id;
        }
      }
      // 库里一个窗口都没有时也可能是「先建地点」的场景：退化到第一个地点
      // （表单里仍由用户确认）。**一个地点都没有时不给修复按钮**——窗口表单
      // 必须落在某个地点下，凭空给个按钮反而会开出一个填不了的窗。
      final owner = venueId ?? await _firstVenueIdOrNull();
      if (owner == null) _fail('找不到窗口「$reference」。');
      throw _ChatEditFailure(
        '找不到窗口「$reference」。',
        repair: ChatEditRepair.createWindow(name: reference, venueId: owner),
      );
    }
    if (matches.length > 1) {
      _fail('「$reference」命中 ${matches.length} 个同名窗口，请用 id 指定。');
    }
    return matches.single;
  }

  /// 库里第一个地点的 id（窗口修复的兜底归属）；一个地点都没有时 null。
  Future<String?> _firstVenueIdOrNull() async {
    final venues = await services.canteenRepository.listVenues();
    return venues.isEmpty ? null : venues.first.id;
  }

  // ---------- 长期记忆（S11，docs/38） ----------

  Future<ChatEditApplyResult> _memoryRemember(ChatEditCommand command) async {
    final memory = await services.aiMemoryRepository.remember(
      text: command.args['text'] as String,
      kind:
          AiMemoryKind.tryParse(command.args['kind']) ??
          AiMemoryKind.preference,
      domain:
          AiMemoryDomain.tryParse(command.args['domain']) ??
          AiMemoryDomain.general,
      tags: [
        for (final tag in (command.args['tags'] as List<Object>?) ?? const [])
          tag as String,
      ],
    );
    return ChatEditApplyResult.ok('已记住：${memory.text}');
  }

  /// 「忘掉」的三种结局都必须如实：0 条（没找到）、多条（列出候选让用户说具体）、
  /// 1 条（真删）。绝不假装删成功。
  Future<ChatEditApplyResult> _memoryForget(ChatEditCommand command) async {
    final matches = await services.aiMemoryRepository.findMatches(
      command.args['text'] as String,
    );
    if (matches.isEmpty) {
      return const ChatEditApplyResult.failure(
        '没有找到匹配的记忆；可以在「我的 → AI 记忆」里看看当前记了什么。',
      );
    }
    if (matches.length > 1) {
      final labels = matches
          .take(3)
          .map((memory) => '「${memory.text}」')
          .join('、');
      return ChatEditApplyResult.failure(
        '找到 ${matches.length} 条相关记忆，请说得更具体：$labels。',
      );
    }
    await services.aiMemoryRepository.delete(matches.single.id);
    return ChatEditApplyResult.ok('已忘掉：${matches.single.text}');
  }

  Future<List<ManualMealItemDraft>> _resolveMealItems(
    ChatEditCommand command,
  ) async {
    final items = command.args['items'] as List<Object>;
    final resolved = <ManualMealItemDraft>[];
    for (final entry in items) {
      final map = entry as Map<String, Object>;
      final food = await _resolveFoodRef(map['food'] as String);
      resolved.add(
        ManualMealItemDraft(food: food, grams: map['grams'] as double),
      );
    }
    return resolved;
  }
}

/// executor 内部的定位失败；与仓储抛出的 FormatException/StateError 一样
/// 会被 [RepositoryChatEditExecutor.apply] 翻译成失败结果。
final class _ChatEditFailure implements Exception {
  const _ChatEditFailure(this.message, {this.repair});

  final String message;

  /// 失败时可点修复动作（2026-10-16：缺食材 → 「创建食材 X」按钮）。
  final ChatEditRepair? repair;
}
