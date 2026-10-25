import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/menu_tab_view.dart';

/// 食堂目录二级页（docs/22 裁决 ②：设计稿未画的功能收进二级入口）。
///
/// 承载原「菜单」tab 的三级自建结构（地点 → 窗口 → 菜品）与「今日推荐」。
/// 从饮食·菜单页 hero 右上角推入，返回即回菜单页。
class CanteenDirectoryPage extends StatelessWidget {
  const CanteenDirectoryPage({
    super.key,
    required this.repository,
    required this.now,
    this.onAnalyzeDishes,
    this.pickDishImage,
    this.foodReferenceService,
  });

  final CanteenRepository repository;

  /// 页面时钟：喂给「今日推荐」卡（本餐预算的「现在几点」+ 调整到达时间）。
  final DateTime now;
  final Future<void> Function(List<CanteenDish> dishes)? onAnalyzeDishes;

  /// 菜品照片取图（docs/29 §P7 需求 16）；null＝菜品表单不渲染照片字段。
  final Future<String?> Function(bool fromCamera)? pickDishImage;

  /// 建食堂菜的「参考食物库」匹配服务（docs/40 §3.1）；null＝流程关闭。
  final FoodReferenceService? foodReferenceService;

  @override
  Widget build(BuildContext context) {
    // 2026-10-22 用户：「食堂目录里的今日推荐删掉，这个界面就记录食堂菜品」；
    // 2026-10-24（`RV4-P3-01` + `R4`）两个死形参 `decisionController` /
    // `mealRepository` 随「下一餐」整族退役一并删除（调用点已改）。
    return Scaffold(
      appBar: const LfTopBar(title: '食堂目录'),
      body: MenuTabView(
        repository: repository,
        foodReferenceService: foodReferenceService,
        onAnalyzeDishes: onAnalyzeDishes,
        pickDishImage: pickDishImage,
      ),
    );
  }
}
