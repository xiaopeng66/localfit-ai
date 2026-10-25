import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/utils/food_name.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

/// 新建 / 编辑食物弹层（docs/28 §5.5）。
///
/// 【N7：保存失败不关窗】落库调用由调用方经 [show] 的 `onSubmit` 传入，
/// 弹层负责「提交中禁用 + 失败时把错误画在按钮行上方且不 pop」——用户输入
/// 原样保留，可以直接改完再存。此前是「先关窗、落库、在页面上弹 snackbar」，
/// 用户被关掉的输入就此丢失（弹层挂在根导航器上时页面提示还可能被遮住）。
///
/// 【N9：没有「默认份量」字段】用户 2026-10-04 原话：「输入弹窗也不需要填写
/// 份量」。四个营养项（每 100g 的 kcal/蛋白/碳水/脂肪）保留，份量从表单里
/// 撤掉；编辑已有条目时数据层的 `defaultServingGrams` 原样保留（不写 null）。
///
/// 【粘贴自动拆品牌】名称栏里粘进 `(Beretta) Prosciutto Cotto火腿片` 或
/// `7-ELEVEN 7-11御饭团` 时，按 §5.4 的同一套规则（[splitFoodName]）把品牌
/// 挪进品牌栏，并在名称栏下留一行可见说明——不是静默改用户输入。
///
/// 【种类是枚举下拉，docs/31 S5 需求 53】大库要求食物带种类，自建行由
/// **表单选择**落库（枚举 id，非自由文本）——自由文本会让按种类看库长出
/// 一堆孤儿档。默认「其他」，编辑回显旧值。
class NewFoodDialog {
  const NewFoodDialog._();

  static Future<NewFood?> show(
    BuildContext context, {
    required Future<String?> Function(NewFood food) onSubmit,
    FoodRecord? editing,
    String? prefillName,
    List<String> existingAliases = const [],
  }) {
    final formKey = GlobalKey<_NewFoodFormState>();
    NewFood? submitted;
    return AppSheet.showSubmitForm<NewFood>(
      context,
      title: editing == null ? '新建食物' : '编辑食物',
      submitKey: const Key('new-food-save'),
      errorKey: const Key('new-food-sheet-error'),
      // 预填名称（2026-10-16）：AI 对话的「创建食材「X」」按钮把名字带进来，
      // 用户只需要补营养值——名称栏是空的等于又让用户打一遍字。
      body: (_, _) => _NewFoodForm(
        key: formKey,
        editing: editing,
        prefillName: prefillName,
        existingAliases: existingAliases,
      ),
      onSubmit: () async {
        final form = formKey.currentState;
        if (form == null) return '表单没有准备好，请重试。';
        if (!form.validate()) return '请检查表单里的提示。';
        final food = form.buildFood();
        final failure = await onSubmit(food);
        // 只有成功那一份才记下来：调用点靠返回值区分「保存成功」与
        // 「用户取消」（两者都会关窗，都是 null 就分不清了）。
        if (failure == null) submitted = food;
        return failure;
      },
      resultBuilder: () => submitted,
    );
  }
}

class _NewFoodForm extends StatefulWidget {
  const _NewFoodForm({
    super.key,
    this.editing,
    this.prefillName,
    this.existingAliases = const [],
  });

  /// 编辑态的初值（null = 新建）。
  final FoodRecord? editing;

  /// 新建态的名称初值（编辑态以 [editing] 为准）。
  final String? prefillName;

  /// 编辑态的别名初值（ADR-037）：新建态为空。
  final List<String> existingAliases;

  @override
  State<_NewFoodForm> createState() => _NewFoodFormState();
}

class _NewFoodFormState extends State<_NewFoodForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;

  /// 别名（ADR-037）：一格多个、逗号/顿号分隔；保存时替换该食物的全部别名。
  late final TextEditingController _aliases;

  /// 种类（docs/31 S5 需求 53）：编辑回显旧值；没有旧值（新建 / 旧数据
  /// 没回填）落「其他」，不猜更细的档。字段初始化器够不到 `widget`，
  /// 旧值在 [initState] 里落。
  FoodCategory _category = FoodCategory.other;

  /// 上一次见到的名称文本：用来判断这一次是「粘贴」还是「逐字输入」。
  String _lastName = '';

  /// 自动拆出去的品牌（显示一行可见说明；用户改品牌栏后清掉）。
  String? _autoSplitBrand;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _name = TextEditingController(
      text: editing?.name ?? widget.prefillName ?? '',
    );
    _brand = TextEditingController(text: editing?.brand ?? '');
    _kcal = TextEditingController(text: _number(editing?.kcalPer100g));
    _protein = TextEditingController(text: _number(editing?.proteinPer100g));
    _carbs = TextEditingController(text: _number(editing?.carbsPer100g));
    _fat = TextEditingController(text: _number(editing?.fatPer100g));
    _aliases = TextEditingController(text: widget.existingAliases.join('、'));
    _category = editing?.category ?? FoodCategory.other;
    _lastName = _name.text;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _aliases.dispose();
    super.dispose();
  }

  /// 表单校验（供 [NewFoodDialog.show] 的提交路径调用）。
  bool validate() => _formKey.currentState?.validate() ?? false;

  /// 当前输入构建的 [NewFood]。
  NewFood buildFood() {
    double value(TextEditingController controller) =>
        double.parse(controller.text.trim());
    return NewFood(
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      kcalPer100g: value(_kcal),
      proteinPer100g: value(_protein),
      carbsPer100g: value(_carbs),
      fatPer100g: value(_fat),
      category: _category,
      aliases: _parseAliases(_aliases.text),
    );
  }

  /// 名称栏变化：粘贴（一次多出 >= 2 个字符）且品牌栏还空着时，按 §5.4 的
  /// 规则把品牌挪过去，并留一行可见说明。
  void _onNameChanged(String value) {
    final pasted = value.length - _lastName.length >= 2;
    _lastName = value;
    if (!pasted || _brand.text.trim().isNotEmpty) return;
    if (!value.contains(' ') && !value.startsWith('(')) return;
    final split = splitFoodName(value);
    final brand = split.brand;
    if (brand == null || split.name.trim().isEmpty) return;
    _name.text = split.name;
    _name.selection = TextSelection.collapsed(offset: split.name.length);
    _brand.text = brand;
    _lastName = split.name;
    setState(() => _autoSplitBrand = brand);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LfTextField(
            fieldKey: const Key('new-food-name'),
            label: '食物名称',
            controller: _name,
            validator: _requiredText,
            onChanged: _onNameChanged,
            // RV-P2-16：与仓储 kMaxEntityNameLength 同口径。
            maxLength: kMaxEntityNameLength,
          ),
          if (_autoSplitBrand case final brand?) ...[
            const SizedBox(height: LfDimens.spaceXSmall),
            Text(
              // 说明「谁动的、动到哪去了」：用户粘贴的是品牌在前的写法，
              // 卡上品牌要挪到底行（N11），这里替他把两栏分好。
              '已把品牌「$brand」移进品牌栏（卡上品牌显示在名称下方）。',
              key: const Key('new-food-brand-hint'),
              style: LfText.micro.copyWith(color: c.mutedForeground),
            ),
          ],
          const SizedBox(height: LfDimens.spaceMedium),
          LfTextField(
            fieldKey: const Key('new-food-brand'),
            label: '品牌',
            optional: true,
            controller: _brand,
            onChanged: (_) {
              if (_autoSplitBrand != null) {
                setState(() => _autoSplitBrand = null);
              }
            },
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          LfTextField(
            fieldKey: const Key('new-food-aliases'),
            label: '别名',
            optional: true,
            controller: _aliases,
            hintText: '多个用逗号分隔，如：西红柿、洋柿子',
            maxLength: kMaxEntityNameLength * 2,
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // docs/32 §3 D7（需求 66）：统一下拉（长列表 10 类，弹层可滚）。
          LfSelectField<FoodCategory>(
            fieldKey: const Key('new-food-category'),
            label: '种类',
            value: _category,
            options: FoodCategory.values,
            optionLabel: (category) => category.label,
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // 四个数字字段落 A `.form-grid`（2×2、gap 12，`styles.css:423`）。
          // 字段名与 Key **不动**：`new-food-每 100g …` 已自带每 100 g 口径，
          // 且被既有测试按 Key 直取——改标签就是改键，零收益。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numberField(_kcal, '每 100g 热量', 'kcal')),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(child: _numberField(_protein, '每 100g 蛋白质', 'g')),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numberField(_carbs, '每 100g 碳水', 'g')),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(child: _numberField(_fat, '每 100g 脂肪', 'g')),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // 表单注（D51）：A `foodEditForm` 的注只搬**成立的三段**——
          // 「以上均为每 100g」字段名已自带；「留空表示未知」与本仓四个数字
          // 必填的校验矛盾（搬即假话）；「热量为 0 按无数据展示」是
          // `kcalOrMissing` 的事实；「修改不会回写已记录的餐食」是 `meal_items`
          // 存当次快照的事实（删除确认里同一句话）。
          Text(
            '以上均为每 100g。热量为 0 按无数据展示；改动不会回写已经记过的餐次。',
            key: const Key('new-food-note'),
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  AppNumberField _numberField(
    TextEditingController controller,
    String label,
    String unit,
  ) {
    return AppNumberField(
      fieldKey: Key('new-food-$label'),
      label: label,
      unit: unit,
      controller: controller,
      validator: (value) => _numberError(value),
    );
  }

  /// 别名输入解析：逗号/顿号/分号/竖线都算分隔符，去空去重。
  static List<String> _parseAliases(String raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final part in raw.split(RegExp(r'[、,，;；|｜]'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }

  String? _requiredText(String? value) {
    return value == null || value.trim().isEmpty ? '请填写食物名称' : null;
  }

  String? _numberError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '请填写数值';
    final number = double.tryParse(text);
    if (number == null || !number.isFinite || number < 0) {
      return '请输入非负数';
    }
    return null;
  }

  /// 编辑态初值：整数不拖小数点（与页面既有数字格式一致），空/null 留空。
  static String _number(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }
}
