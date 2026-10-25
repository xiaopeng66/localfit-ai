import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/application/menu_service_window.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart'
    show kCanteenSourceType;
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealSlot;

/// 把食堂目录里**已做营养分析**的菜品写进菜品库（docs/21 §5.3 写入路径 1）。
///
/// 菜单页的唯一主来源是 `DishLibrary`，而食堂三级结构（地点 → 窗口 → 菜品）
/// 只写 `MenuItems` + 营养证据表。没有这一步，「饮食·菜单」页永远是空的：
/// 用户辛苦录入并分析完菜品，回到菜单页却什么都看不到。
///
/// **份量口径（schema 28 还债）**：`DishLibrary` 的 kcal / 三宏量是「一份」
/// 语义，食堂证据是每 100g。旧实现把 per100g 直接写进「每份」列——那是
/// docs/40 §1 点名的「100g 假设」债。现在：
/// * 有 `menu_items.servingGrams` ⇒ 每份 = per100g × servingGrams / 100；
/// * 没有 ⇒ 每份 = per100g（等价 servingGrams=100）并标 `basisAssumed=1`，
///   UI 显示「按 100g 估算」，不假装知道份量。
/// 同时写 `sourceType='canteen'` + `sourceId=menuItemId`，同步提示才有锚点。
///
/// **缺的数据一律留空**：食堂证据没有微量营养素与点评，就写 null，
/// 让菜品卡按裁决 10 / 13 不渲染那两块（不编事实）。
final class AddCanteenDishesToLibrary {
  const AddCanteenDishesToLibrary({
    required this.dishLibrary,
    required this.canteen,
  });

  final DishLibraryRepository dishLibrary;
  final CanteenRepository canteen;

  /// **单条自动同步**（2026-10-24 用户：「加入菜品目录里不能自动加入菜品库吗…
  /// 我希望他们就是一个库，不要分开，不要自己加入」）。
  ///
  /// 装配层把它挂到 `CanteenRepository.onDishUpserted` 上：建菜/改名/换照片/
  /// 写营养之后自动调用一次。缺营养时是**空操作**（`written: 0`）——菜品库
  /// 的每行都必须有营养值，未分析的菜等分析完再进来，用户不需要点任何按钮。
  Future<AddDishesResult> syncDish(String dishId) async {
    final dish = await canteen.findDish(dishId);
    if (dish == null) return const AddDishesResult(written: 0, skipped: 0);
    return run(windowId: dish.windowId, dishes: [dish]);
  }

  /// 升级补齐（2026-10-24）：把库里**所有已分析**的食堂菜按来源键写进菜品库。
  ///
  /// 为什么需要它：老版本靠用户手动点「加入菜品库」，因此升级后必然有一批
  /// 「分析过、但没手动加过」的菜——它们在新版本里应当**立刻**出现在菜单页，
  /// 而不是等用户下一次碰那道菜。幂等（按来源 upsert），组合根用
  /// [kCanteenLibraryBackfillKey] 打标只跑一次。
  Future<AddDishesResult> backfillAll() async {
    var written = 0;
    var skipped = 0;
    for (final venue in await canteen.listVenues()) {
      for (final window in await canteen.listWindows(venue.id)) {
        final result = await run(windowId: window.id, dishes: window.dishes);
        written += result.written;
        skipped += result.skipped;
      }
    }
    return AddDishesResult(written: written, skipped: skipped);
  }

  /// **单条自动删除**：来源菜被删，菜品库里的同源行跟随删除。
  /// 一个库不能留幽灵（旧的「加入菜品库」是一次性拷贝，删来源不动副本）。
  Future<bool> removeDish(String dishId) => dishLibrary.deleteBySource(
    sourceType: kCanteenSourceType,
    sourceId: dishId,
  );

  /// 写入一批菜品，返回实际写入/更新的条数。
  ///
  /// 只处理 `hasNutrition` 的菜品：没有营养值的菜品写进菜品库只会得到一张
  /// 全是「—」的卡，还会污染「每日目标进度」的分母。未分析的菜品由调用方
  /// 在结果文案里如实报数。
  Future<AddDishesResult> run({
    required String windowId,
    required List<CanteenDish> dishes,
  }) async {
    final window = await _windowOrNull(windowId);
    final mealSlot = _mealSlotForWindow(window);
    final servingWindow = window == null
        ? null
        : '${window.openTime}-${window.closeTime}';

    var written = 0;
    var skipped = 0;
    for (final dish in dishes) {
      final kcal = dish.kcalPer100g;
      final protein = dish.proteinPer100g;
      final carbs = dish.carbsPer100g;
      final fat = dish.fatPer100g;
      if (kcal == null || protein == null || carbs == null || fat == null) {
        skipped++;
        continue;
      }
      final servingGrams = dish.servingGrams;
      final factor = (servingGrams ?? 100) / 100;
      await dishLibrary.upsertBySource(
        sourceType: kCanteenSourceType,
        sourceId: dish.id,
        draft: DishDraft(
          name: dish.name,
          mealSlot: mealSlot.storedValue,
          // 每份 = per100g × servingGrams / 100（唯一事实源仍是 per100g）。
          kcal: kcal * factor,
          proteinG: protein * factor,
          carbsG: carbs * factor,
          fatG: fat * factor,
          // `RV4-P1-03`：照片必须跟着进菜品库。旧实现漏了这一行 ⇒ 菜品库行的
          // `imagePath` 恒为 null，`DishCard` 那套 4:3 封面 + `Image.file`
          // 写得再完整也永远走渐变占位（变异 M2 证明：补上后 12 条测试全绿不变
          // = 零覆盖）。改名/换照片/删照片都经 `syncDish` 回到这里，
          // 所以一处修好三条路径一起通。
          imagePath: dish.imagePath,
          // 来源跟随营养证据（2026-10-20 审查 RV-P1-07）：手填是用户输入，
          // 不能标成 AI 估算；引用食物库也不是估算。旧实现硬编码
          // `ai_estimate`，设备上把用户自己填的数标成「AI 估算」。
          source: switch (dish.evidence?.origin) {
            'user_input' => 'manual',
            'food_library' => 'food_library',
            _ => 'ai_estimate',
          },
          servingWindow: servingWindow,
          servingGrams: servingGrams,
          sourceType: kCanteenSourceType,
          sourceId: dish.id,
          sourceUpdatedAt: dish.evidence?.updatedAt,
        ),
      );
      written++;
    }
    return AddDishesResult(written: written, skipped: skipped);
  }

  Future<CanteenWindow?> _windowOrNull(String windowId) async {
    // 窗口信息（营业时段 → 餐次 + 供应时段）只能从所属地点取回：
    // 仓储没有「按 id 取窗口」的入口，列出各地点再找是现有能力内最省的
    // 做法，且窗口数量是个位数。
    for (final venue in await canteen.listVenues()) {
      for (final window in await canteen.listWindows(venue.id)) {
        if (window.id == windowId) return window;
      }
    }
    return null;
  }

  /// 窗口营业时段 → 餐次。
  ///
  /// 用**结束时间**判定（06:30–09:30 → 早餐、11:00–13:30 → 午餐），
  /// 阈值与 `NextMealDecisionController._slotFor` 的当天分界同源：
  /// 早餐截止 09:30、午餐 14:00、晚餐 20:30。取不到窗口（已被删除）时
  /// 落 [MealSlot.lunch]——这是现有代码里「不知道就按午餐」的既有兜底
  /// （`resolveMealScanCandidates` 同款），不是新猜的规则。
  static MealSlot _mealSlotForWindow(CanteenWindow? window) {
    if (window == null) return MealSlot.lunch;
    final close = parseHhmmToMinute(window.closeTime);
    if (close <= 9 * 60 + 30) return MealSlot.breakfast;
    if (close <= 14 * 60) return MealSlot.lunch;
    if (close <= 20 * 60 + 30) return MealSlot.dinner;
    return MealSlot.snack;
  }
}

/// 写入结果：`skipped` = 因缺营养值而未写入的条数。
///
/// 分开报数而不是只给一个总数：静默少写等于告诉用户「都加进去了」。
final class AddDishesResult {
  const AddDishesResult({required this.written, required this.skipped});

  final int written;
  final int skipped;

  bool get isEmpty => written == 0;
}

/// 升级补齐只跑一次的 KV 标记（`app_settings`）。
const String kCanteenLibraryBackfillKey = 'canteen_library_backfill_v1';
