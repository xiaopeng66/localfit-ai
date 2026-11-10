import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_data_flows.dart';
import 'package:localfit_ai/features/nutrition/presentation/custom_meal_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_target_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/dish_meal_editor_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';

/// 饮食页的动作层（2.0-6i-3b，docs/07 §9.3「页面只负责布局和用户事件」）：
/// 打开各类编辑/确认对话框、落库、回显结果——页面不再自己写这些流程。
///
/// 只依赖注入进来的仓库与回调；不查库、不发网络请求。
///
/// 2026-10-04（docs/28 §6.3）：原先这里还有 `openRecipePlan` /
/// `addRecipeToMeal` / `editRecipe` 三个方法，随「食谱 / 计划」整族下线一并
/// 删除（相关弹层与用例类也不存在了）。方案原话是「整个文件删」，实测该文件
/// 同时承载记录页的 editMeal / deleteMeal / deleteMeals / reuseMeal /
/// createFood，删掉会把记录页的动作层一起带走 ⇒ **以实测为准，只摘掉那三个
/// 方法**。
final class NutritionActions {
  const NutritionActions({
    required this.context,
    required this.selectedDate,
    required this.onDateSelected,
    this.dishLibraryRepository,
    this.onAddDishToMeal,
    this.canteenRepository,
    this.onAnalyzeDishes,
    this.supplyCatalog,
  });

  final BuildContext context;

  /// 当前选中日期（页面持有状态，所以按需取而不是复制一份）。
  final DateTime Function() selectedDate;

  /// 记录/复用后页面的选中日期可能被推进（例如记录到别的日子）。
  final ValueChanged<DateTime> onDateSelected;

  /// 「按菜品记录」需要读菜品库（docs/41 §7 写入路径矩阵第二条）。
  /// 未接线时那个入口不渲染（宁可少一个入口，也不给点了没反应的按钮）。
  final DishLibraryRepository? dishLibraryRepository;

  /// 菜品 → 餐记录的唯一写入路径（docs/40 §3：所有路径最终都落到同一个
  /// `MealRepository.create`；这里复用的是菜单页「加入」那一份用例）。
  /// 未接线时「按菜品记录」不可用。
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
  onAddDishToMeal;

  /// 食堂目录仓储（2026-10-25 D-1）：只**读**未分析的菜，让「按菜品记录」
  /// 能搜到它们。未接线时该分组不出现。
  final CanteenRepository? canteenRepository;

  /// 食堂供应的统一读取口（docs/67 §6.4）：记餐编辑器用它把"某窗口的一份"
  /// 作为可记录候选，明确窗口与份量，而不是当成无来源的重复行。
  final SupplyCatalogRepository? supplyCatalog;

  /// 去给选中的菜做 AI 分析（与食堂目录页同一个回调，不新造写路径）。
  /// 未接线时只如实说明「还没有营养数据」，不给点了没反应的按钮。
  final Future<void> Function(List<CanteenDish> dishes)? onAnalyzeDishes;

  /// 记录餐入口：先问「按食材 / 按菜品」，再进对应弹层。
  ///
  /// 两个入口的存在本身是需求（docs/40 §2.4）：混在一个框里时食物库在
  /// 日常路径上等于不存在。两条路都走既有落库路径，不新增写逻辑。
  Future<void> chooseRecordEntry(
    FoodRepository foods,
    MealRepository meals, {
    MealSlot? initialSlot,
  }) async {
    final entry = await MealRecordEntryChooser.show(context);
    if (entry == null || !context.mounted) return;
    switch (entry) {
      case MealRecordEntry.byFood:
        await editMeal(foods, meals, initialSlot: initialSlot);
      case MealRecordEntry.byDish:
        await recordByDish(initialSlot: initialSlot);
      case MealRecordEntry.byCustom:
        await recordCustomMeal(meals, initialSlot: initialSlot);
    }
  }

  /// 手动指定每日营养目标（2026-10-26 用户：「营养摄入自己不能改」）。
  ///
  /// 从**今天**起生效；保存后卡上的「依据」写「手动设定」，「恢复按身体数据
  /// 计算」清掉手动值、回到公式那套（`DailyTargets` 行一个字都没动）。
  Future<void> editNutritionTarget(MealRepository meals) async {
    final localDate = formatLocalDate(selectedDate());
    final current = await meals.readManualTargetForDate(localDate);
    final formula = await meals.watchNutritionForDate(localDate).first;
    if (!context.mounted) return;
    await NutritionTargetSheet.show(
      context,
      effectiveDate: localDate,
      // 预填：手动值优先；没有手动值就用当前生效的（公式）目标。
      current: current?.toTarget() ?? formula.target,
      onSave: (value) async {
        try {
          await meals.saveManualTarget(value);
          _showMessage('营养目标已按你填的区间生效。', icon: AppSnackBar.successIcon);
          return null;
        } on FormatException catch (error) {
          return error.message;
        } catch (_) {
          return '保存失败，请重试。';
        }
      },
      onRestore: () {
        unawaited(meals.clearManualTarget());
        _showMessage('已恢复按身体数据计算。', icon: AppSnackBar.successIcon);
      },
    );
  }

  /// 「自定义一顿」：不依赖食物库，直接填这一顿的热量与三宏量。
  ///
  /// 为什么需要（2026-10-26 用户：「营养摄入自己不能改」）：外卖、家里做的、
  /// 聚餐这些食物库里没有的东西，原来只能先建一个食物、或拍照让 AI 估。
  /// 落库仍走 `MealRepository.create`（`foodId = null` + `sourceType =
  /// 'manual'`），不新增写路径。
  Future<void> recordCustomMeal(
    MealRepository meals, {
    MealSlot? initialSlot,
  }) async {
    await CustomMealSheet.show(
      context,
      localDate: formatLocalDate(selectedDate()),
      initialSlot: initialSlot,
      onSubmit: (draft) async {
        try {
          await meals.create(draft);
          _showMessage('已记下这一顿（自定义热量）。', icon: AppSnackBar.successIcon);
          return null;
        } on FormatException catch (error) {
          return error.message;
        } catch (_) {
          return '餐食保存失败，请重试。';
        }
      },
    );
  }

  /// 「按菜品记录」：**表单弹层**（2026-10-28 用户：「按菜品记录为什么弹窗
  /// 还是这样，我要的是按食材记录这样，自定义一顿也是一样」）——与按食材
  /// 同构：餐次胶囊 + 搜索加菜 + 已添加 + 合计 + 保存；保存逐条走
  /// [onAddDishToMeal]（`AddDishToMeal.run`），不新增写路径。
  ///
  /// 未分析的食堂菜**不进表单**（没有营养，加进来就是 0 kcal）：那 条
  /// 「搜得到但不能记、点了给『去分析』」的支路留在 `DishMealPickerDialog`
  /// （`_offerUnanalyzedEntry`），只在菜品库为空且食堂有未分析菜时作为
  /// **补位入口**出现（弹层空态不能只是一句「还是空的」）。
  ///
  /// [initialSlot] 是页面给的预选餐次（今日页「记录晚餐」）：它优先于菜品
  /// 库里记的餐次——用户刚说的是哪一餐，比菜库里存档的餐次更可信。
  Future<void> recordByDish({MealSlot? initialSlot}) async {
    final library = dishLibraryRepository;
    final addDish = onAddDishToMeal;
    if (library == null || addDish == null) return;
    try {
      final dishes = await library.watchAll().first;
      if (!context.mounted) return;
      final result = await DishMealEditorSheet.show(
        context,
        dishes: dishes,
        localDate: formatLocalDate(selectedDate()),
        onAddDish: addDish,
        initialSlot: initialSlot,
      );
      if (result == null || result.saved <= 0 || !context.mounted) return;
      _showMessage(
        result.saved == 1
            ? '已记一份菜到${result.slot.label}（记为已吃）'
            : '已记 ${result.saved} 份菜到${result.slot.label}（记为已吃）',
        icon: AppSnackBar.successIcon,
      );
      // 表单关闭后，若菜品库为空且食堂有未分析菜，补一条「去分析」出路
      // （原 D-1 支路收窄版：空菜库不能只是一句「还是空的」）。
      if (dishes.isEmpty) unawaited(_offerFirstUnanalyzed());
    } on FormatException catch (error) {
      _showMessage(error.message, icon: AppSnackBar.errorIcon);
    } catch (_) {
      _showMessage('记录失败，请重试。', icon: AppSnackBar.errorIcon);
    }
  }

  Future<void> _offerFirstUnanalyzed() async {
    final unanalyzed = await _unanalyzedCanteenDishes();
    if (unanalyzed.isEmpty) return;
    if (!context.mounted) return;
    _offerAnalyzeUnanalyzed(unanalyzed.first);
  }

  /// 收集「食堂目录里还没分析」的菜（跨全部地点/窗口）。
  ///
  /// 只读、失败返回空（读不到食堂目录不该挡住「按菜品记录」这条主路）。
  Future<List<CanteenDish>> _unanalyzedCanteenDishes() async {
    final canteen = canteenRepository;
    if (canteen == null) return const [];
    try {
      final out = <CanteenDish>[];
      for (final venue in await canteen.listVenues()) {
        for (final window in await canteen.listWindows(venue.id)) {
          for (final dish in await canteen.listDishes(window.id)) {
            if (!dish.hasNutrition) out.add(dish);
          }
        }
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// 选中未分析的食堂菜时：如实说明 + 给「去分析」入口。
  ///
  /// **不替用户决定**：默认什么都不做，用户点「去分析」才走既有的 AI 分析
  /// 链路（与食堂目录页那个入口同一个回调，不新造写路径）。
  Future<void> _offerAnalyzeUnanalyzed(CanteenDish dish) async {
    final analyze = onAnalyzeDishes;
    if (analyze == null) {
      _showMessage(
        '「${dish.name}」还没有营养数据，先在菜单页给它做 AI 分析再记。',
        icon: AppSnackBar.errorIcon,
      );
      return;
    }
    // 用带 action 的提示条（与「换一整套」同一形态），不引新的弹层件。
    AppSnackBar.show(
      context,
      '「${dish.name}」还没有营养数据，记不准这一餐的热量。要先让 AI 分析吗？',
      actionLabel: '去分析',
      onAction: () => unawaited(analyze([dish])),
      icon: AppSnackBar.errorIcon,
    );
  }

  /// 打开餐食编辑弹层。
  ///
  /// [initialSlot] 是「点哪一餐就记哪一餐」的预选槽位（Round7 阶段 2 决策
  /// D9）：今日页「记录晚餐」、记录页槽位卡头「+」用它；编辑既有餐食时
  /// [initial] 的槽位优先。不传 = 既有默认（午餐），旧调用点行为不变。
  /// 返回弹层产出的草稿（null = 用户取消）。【2026-10-31】从 void 改为
  /// 返回草稿：合并编辑（[editSlotMeals]）要靠它分辨「保存成功」与「取消」
  /// ——取消时绝不能删掉被合并的其余记录。
  Future<MealDraft?> editMeal(
    FoodRepository foods,
    MealRepository meals, {
    MealRecord? initial,
    MealSlot? initialSlot,
  }) async {
    return AppSheet.showCustom<MealDraft>(
      context,
      builder: (context) => MealEditorDialog(
        foodRepository: foods,
        // 【N-2（2026-10-29 用户：三个添加入口合并成一个界面）】统一弹层
        // 直连菜品库：一个搜索框同时搜食物库与菜品库、支持手动添加食材
        // （可存入食物库）——三入口 chooser 退役。
        dishRepository: dishLibraryRepository,
        supplyCatalog: supplyCatalog,
        localDate: formatLocalDate(selectedDate()),
        initialMeal: initial,
        initialSlot: initialSlot,
        // 落库在弹层的提交路径里（N7）：写失败时弹层不关、错误画在弹层内，
        // 已经加好的食物与克数都不丢。
        onSubmit: (draft) async {
          try {
            if (initial == null) {
              await meals.create(draft);
            } else {
              await meals.update(initial.id, draft);
            }
            _showMessage(
              initial == null ? '餐食已保存到本机。' : '餐食已更新。',
              icon: AppSnackBar.successIcon,
            );
            return null;
          } on FormatException catch (error) {
            return error.message;
          } catch (_) {
            return '餐食保存失败，请重试。';
          }
        },
      ),
    );
  }

  /// 【2026-10-31 用户：「整卡点击后显示所有已添加的食物，然后可以编辑」】
  /// 合并编辑：打开的弹层列出该槽位**全部记录**的食物（多条记录合成一个
  /// 视图），保存 = 更新第一条记录为整份草稿、**删除其余记录**（同槽位
  /// 同餐次，用户的意图就是「这一餐吃的是这堆」），不引入新表。
  Future<void> editSlotMeals(
    FoodRepository foods,
    MealRepository meals, {
    required List<MealRecord> records,
  }) async {
    if (records.isEmpty) return;
    final first = records.first;
    final latest = records.reduce(
      (a, b) => a.eatenAt.isAfter(b.eatenAt) ? a : b,
    );
    final mergedNotes = [
      for (final meal in records)
        if ((meal.notes ?? '').trim().isNotEmpty) meal.notes!.trim(),
    ].join(' · ');
    final merged = MealRecord(
      id: first.id,
      localDate: first.localDate,
      slot: first.slot,
      eatenAt: latest.eatenAt,
      source: first.source,
      createdAt: first.createdAt,
      updatedAt: latest.updatedAt,
      items: [for (final meal in records) ...meal.items],
      notes: mergedNotes.isEmpty ? null : mergedNotes,
    );
    final draft = await editMeal(foods, meals, initial: merged);
    // 【取消护栏】弹层返回 null = 用户取消——此时**绝不能**删掉被合并的
    // 其余记录，否则用户什么都没改反而丢了数据。
    if (draft == null) return;
    // 保存成功：第一条记录已更新为整份草稿，其余记录的内容已并入它，
    // 原样留着会双份 —— 删除（同槽位同餐次）。
    for (var i = 1; i < records.length; i++) {
      await meals.delete(records[i].id);
    }
  }

  Future<void> deleteMeal(MealRecord meal, MealRepository repository) async {
    final confirmed = await AppSheet.show<bool>(
      context,
      title: '删除餐食？',
      content: Text('将删除${meal.slot.label}及其中 ${meal.items.length} 项食物。'),
      // 弹层走根导航器（docs/21 §3.6），动作闭包须用弹层内 context 弹出；
      // 页面 context 属于 shell 分支导航器，用它会把本页弹掉。
      actions: Builder(
        builder: (sheetContext) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
            // 破坏性确认 = §3.8 B7（设计稿没有实心 error 按钮）：本弹层本身就是
            // 「二次确认」，所以确认键用字型 error 而不是实心 error。
            LfDangerButton(
              key: const Key('meal-delete-confirm'),
              label: '删除',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final deleted = await repository.delete(meal.id);
      if (deleted == null) {
        _showMessage('餐食不存在或已被删除。', icon: AppSnackBar.errorIcon);
        return;
      }
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      AppSnackBar.showOn(
        messenger,
        '餐食已删除。',
        icon: AppSnackBar.deleteIcon,
        actionLabel: '撤销',
        // 删除族显式 6 秒（RV4-P1-01）：撤销是破坏性操作的唯一恢复通道，
        // 默认 4 秒对「看清 → 决定 → 点中」偏紧。
        duration: AppSnackBar.undoDuration,
        onAction: () async {
          try {
            await repository.restore(deleted);
          } catch (_) {
            if (context.mounted) {
              _showMessage('撤销失败，请重试。', icon: AppSnackBar.errorIcon);
            }
          }
        },
      );
    } catch (_) {
      _showMessage('删除失败，请重试。', icon: AppSnackBar.errorIcon);
    }
  }

  /// docs/21 §3 批量删除的撤销通道（RecordTab 长按多选后由页面动作层
  /// 收起 snackbar）。列表层的 RecordTab 已处理落库；这里只对已成功
  /// 删除的 [deleted] 提供一次性撤销。
  Future<void> deleteMeals(
    List<MealRecord> deleted,
    MealRepository repository,
  ) async {
    if (deleted.isEmpty || !context.mounted) return;
    final deletedRecords = List<MealRecord>.of(deleted);
    final messenger = ScaffoldMessenger.of(context);
    AppSnackBar.showOn(
      messenger,
      '已删除所选食物。',
      icon: AppSnackBar.deleteIcon,
      actionLabel: '撤销',
      duration: AppSnackBar.undoDuration,
      onAction: () async {
        try {
          for (final record in deletedRecords) {
            await repository.restore(record);
          }
        } catch (_) {
          if (context.mounted) {
            _showMessage('撤销失败，请重试。', icon: AppSnackBar.errorIcon);
          }
        }
      },
    );
  }

  Future<void> createFood(FoodRepository repository) async {
    // 落库放在弹层的提交路径里：失败时弹层不关、错误画在弹层内（N7）。
    await NewFoodDialog.show(
      context,
      onSubmit: (food) async {
        try {
          await repository.create(food);
          return null;
        } on FormatException catch (error) {
          return error.message;
        } catch (_) {
          return '食物创建失败，请重试。';
        }
      },
    );
  }

  /// 页尾左链「导入食物数据」（Round7 阶段 3 · 3-2c；A `app.js:201` 的
  /// `import-info`）：走**同一条** CSV 通路（挑文件 → 预览 → 落库），
  /// 契约与设置页那条一字不差（ADR-036 官方 9 列 + 整批一个事务）。
  ///
  /// 不在这里刷新列表：`NutritionPage` 监听食物表变更，提交后自己会跟上
  /// （自建食物那条通路也是同一机制）。
  Future<void> importFoods(FoodRepository repository) =>
      runFoodCsvImportFlow(context, repository);

  /// 页尾右链「食物管理」（A `app.js:201` 的 `food-management`）：共享的
  /// 「食物数据」弹层（设置页的「添加食物数据」是同一个组件），标题按 A
  /// 的字面用「食物库管理」。手动添加走既有 [createFood]（同一份弹层、
  /// 同一条落库路径）。
  Future<void> manageFoods(FoodRepository repository) => showFoodDataSheet(
    context,
    title: '食物库管理',
    onAddCustomFood: () => createFood(repository),
    onImportFoodCsv: () => runFoodCsvImportFlow(context, repository),
  );

  void _showMessage(String message, {IconData? icon}) {
    if (!context.mounted) return;
    AppSnackBar.show(context, message, icon: icon);
  }
}
