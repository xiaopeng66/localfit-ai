import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 手动填写每 100g 营养（docs/41 D10）：**无 AI 也能用**的食堂菜营养来源。
///
/// `origin='user_input'`（用户输入是权威来源，AI 之后不再覆盖）；证据等级
/// 落 'D'（不是实测，诚实标注），徽标显示「用户输入 · 已确认」——来源与
/// 证据两维分开（`LfSourceBadgePair.forCanteenOrigin`）。
///
/// 表单是 2×2 数字网格（与菜品库表单同一套键风格）；四个字段都必填，
/// 交给 `validateDishNutrition` 的同一套校验（不写第二套规则）。
class ManualNutritionSheet extends StatefulWidget {
  const ManualNutritionSheet({
    super.key,
    required this.dish,
    required this.onSubmit,
  });

  final CanteenDish dish;

  /// 落库由调用方给（MenuTabView 的既有 `_run` 外壳）。返回文案 = 留在
  /// 弹层内显示（N7 失败不关窗）；null = 成功关窗。
  final Future<String?> Function(
    double kcal,
    double protein,
    double carbs,
    double fat,
  )
  onSubmit;

  static Future<void> show(
    BuildContext context, {
    required CanteenDish dish,
    required Future<String?> Function(
      double kcal,
      double protein,
      double carbs,
      double fat,
    )
    onSubmit,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    // 与 `AppSheet` 同一约定：走**根导航器**浮在贴底栏之上。
    // 默认（false）会把弹层挂进分支导航器，而 shell 是
    // `extendBody: true`——正文延伸到栏下，弹层最后一行（这里是「保存」）
    // 就被底栏盖住：2026-10-19 在 1080×2340 设备上实测，点击落进了
    // 导航中间槽（跳到 AI 页），营养没写进库。
    useRootNavigator: true,
    // 拖拽只认把手：层内滚动/收键盘时下拉不该关窗（同 AppSheet）。
    enableDrag: false,
    builder: (sheetContext) => Padding(
      // 键盘高 + 安全区 + 最小留白（同 `AppSheet`）：两者都为 0 时主行动
      // 会贴到屏幕物理底边。
      padding: EdgeInsets.only(bottom: sheetBottomInset(sheetContext)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ManualNutritionSheet(dish: dish, onSubmit: onSubmit),
      ),
    ),
  );

  @override
  State<ManualNutritionSheet> createState() => _ManualNutritionSheetState();
}

class _ManualNutritionSheetState extends State<ManualNutritionSheet> {
  late final TextEditingController _kcal = TextEditingController(
    text: dish.kcalPer100g?.toStringAsFixed(0) ?? '',
  );
  late final TextEditingController _protein = TextEditingController(
    text: dish.proteinPer100g?.toStringAsFixed(1) ?? '',
  );
  late final TextEditingController _carbs = TextEditingController(
    text: dish.carbsPer100g?.toStringAsFixed(1) ?? '',
  );
  late final TextEditingController _fat = TextEditingController(
    text: dish.fatPer100g?.toStringAsFixed(1) ?? '',
  );
  String? _error;
  bool _saving = false;

  CanteenDish get dish => widget.dish;

  @override
  void dispose() {
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final kcal = double.tryParse(_kcal.text.trim());
    final protein = double.tryParse(_protein.text.trim());
    final carbs = double.tryParse(_carbs.text.trim());
    final fat = double.tryParse(_fat.text.trim());
    if (kcal == null || protein == null || carbs == null || fat == null) {
      setState(() => _error = '四项都要填数字（每 100g 的值）。');
      return;
    }
    try {
      validateDishNutrition(
        name: dish.name,
        kcal: kcal,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final message = await widget.onSubmit(kcal, protein, carbs, fat);
    if (!mounted) return;
    if (message != null) {
      setState(() {
        _saving = false;
        _error = message;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('manual-nutrition-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '手动填写营养（每 100g）',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '「${dish.name}」· 按包装或营养成分表填写「每 100 克」的值；'
          '四项都必填，保存后标为「用户输入」，AI 分析不会覆盖。',
          key: const Key('manual-nutrition-hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('manual-nutrition-kcal'),
                controller: _kcal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '热量 kcal',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('manual-nutrition-protein'),
                controller: _protein,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '蛋白质 g',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('manual-nutrition-carbs'),
                controller: _carbs,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '碳水 g',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('manual-nutrition-fat'),
                controller: _fat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '脂肪 g',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('manual-nutrition-error'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        LfPrimaryButton(
          key: const Key('manual-nutrition-save'),
          label: _saving ? '保存中…' : '保存（标为用户输入）',
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
