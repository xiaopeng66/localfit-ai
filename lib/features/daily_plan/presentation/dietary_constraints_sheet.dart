import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';

/// 设置里的「饮食约束」（C-2，docs/64）：素食标签 + 过敏原回避。
///
/// **同一张表**：读写 `profiles.dietaryPreferencesJson` /
/// `allergenAvoidancesJson`（`PlanningConstraintsRepository.load/save`），
/// AI 的 `constraints.set` 写的就是这两列——AI 写的约束这里打开就能看到，
/// 这里改的 AI 下一次对话也能看到。**不写进 AI 记忆**（记忆是「用户说过的话」，
/// 约束是「硬规则」），两处各管各的（docs/64 C-2 施工步骤 3）。
///
/// 上限由模型钉死（4 个标签 / 9 个过敏原，`validate()`）：超限**就地报错、
/// 不保存**，不静默截断。
///
/// **必须自带滚动**（2026-10-28 第二轮复核）：`AppSheet.showCustom` 的定制
/// 主体没有滚动层（只有屏高 90% 上限），9 个忌口胶囊 + 输入行 + 错误行在
/// 320dp × 2.0× 下实测溢出 **305px**。
Future<void> showDietaryConstraintsSheet(
  BuildContext context, {
  required PlanningConstraintsRepository repository,
}) {
  return AppSheet.showCustom<void>(
    context,
    builder: (_) => SingleChildScrollView(
      child: DietaryConstraintsSheet(repository: repository),
    ),
  );
}

/// 已选忌口项的小胶囊（设计系统内的形态：muted 底 + 正文 + 44dp 命中盒的
/// 删除钮）。不用 Material `InputChip`——它的 label 是平台默认字体样式，
/// 不在设计令牌链上。
class _AllergenChip extends StatelessWidget {
  const _AllergenChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Container(
      padding: const EdgeInsets.only(
        left: LfDimens.spaceMedium,
        right: LfDimens.spaceXSmall,
        top: LfDimens.spaceMicro,
        bottom: LfDimens.spaceMicro,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: LfText.body.copyWith(color: c.foreground)),
          const SizedBox(width: LfDimens.spaceMicro),
          LfIconButton(
            icon: Icons.close,
            iconSize: 16,
            semanticLabel: '删除忌口项 $label',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class DietaryConstraintsSheet extends StatefulWidget {
  const DietaryConstraintsSheet({super.key, required this.repository});

  final PlanningConstraintsRepository repository;

  @override
  State<DietaryConstraintsSheet> createState() =>
      _DietaryConstraintsSheetState();
}

class _DietaryConstraintsSheetState extends State<DietaryConstraintsSheet> {
  final _allergenInput = TextEditingController();
  var _labels = <DietaryLabel>[];
  var _allergens = <String>[];
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _allergenInput.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final constraints = await widget.repository.load();
    if (!mounted) return;
    setState(() {
      _labels = [...constraints.dietaryLabels];
      _allergens = [...constraints.allergenAvoidances];
      _loading = false;
    });
  }

  void _toggleLabel(DietaryLabel label) {
    setState(() {
      _error = null;
      if (_labels.contains(label)) {
        _labels = _labels.where((item) => item != label).toList();
        return;
      }
      if (_labels.length >= PlanningConstraints.maxDietaryLabels) {
        _error = '最多 ${PlanningConstraints.maxDietaryLabels} 个饮食标签。';
        return;
      }
      _labels = [..._labels, label];
    });
  }

  void _toggleAllergen(String allergen) {
    setState(() {
      _error = null;
      if (_allergens.contains(allergen)) {
        _allergens = _allergens.where((item) => item != allergen).toList();
        return;
      }
      if (_allergens.length >= PlanningConstraints.maxAllergenAvoidances) {
        _error = '最多 ${PlanningConstraints.maxAllergenAvoidances} 个忌口项。';
        return;
      }
      _allergens = [..._allergens, allergen];
    });
  }

  void _addAllergen() {
    final text = _allergenInput.text.trim();
    if (text.isEmpty) return;
    if (_allergens.contains(text)) {
      setState(() => _error = '「$text」已经在忌口清单里。');
      return;
    }
    if (_allergens.length >= PlanningConstraints.maxAllergenAvoidances) {
      setState(
        () => _error = '最多 ${PlanningConstraints.maxAllergenAvoidances} 个忌口项。',
      );
      return;
    }
    setState(() {
      _error = null;
      _allergens = [..._allergens, text];
      _allergenInput.clear();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final constraints = PlanningConstraints(
      dietaryLabels: _labels,
      allergenAvoidances: _allergens,
    );
    try {
      constraints.validate();
      await widget.repository.save(constraints);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
      return;
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    AppSnackBar.showOn(
      messenger,
      '饮食约束已保存，AI 也会照这份执行。',
      icon: AppSnackBar.successIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final customAllergens = [
      for (final item in _allergens)
        if (!FoodAllergen.values.any((allergen) => allergen.label == item))
          item,
    ];
    // 1.0× 下 9 个忌口按 3×3 排；放大字号后用 2 列，避免每个块过窄。
    final allergenColumns = MediaQuery.textScalerOf(context).scale(12) > 16
        ? 2
        : 3;
    return Column(
      key: const Key('dietary-constraints-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('饮食约束', style: LfText.headline),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(
          'AI 对话与「换一套」会按这份硬过滤；本地菜单按菜名保守避开。'
          '写进 AI 记忆的话不算约束。',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(LfDimens.spaceLarge),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else ...[
          _ConstraintSectionHeader(
            title: '饮食标签',
            count: '${_labels.length}/${PlanningConstraints.maxDietaryLabels}',
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          _ConstraintGrid(
            children: [
              for (final label in DietaryLabel.values)
                DietaryConstraintChoice(
                  key: Key('dietary-label-${label.name}'),
                  label: label.label,
                  selected: _labels.contains(label),
                  onTap: () => _toggleLabel(label),
                ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          _ConstraintSectionHeader(
            title: '忌口 / 过敏原',
            count:
                '${_allergens.length}/${PlanningConstraints.maxAllergenAvoidances}',
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          // 预设项**永远占固定位置**：选中只改底色/勾选，不从原位置消失，
          // 解决用户看到的「点一下标签就跳到最后边」。
          _ConstraintGrid(
            columns: allergenColumns,
            children: [
              for (final allergen in FoodAllergen.values)
                DietaryConstraintChoice(
                  key: Key('dietary-allergen-${allergen.name}'),
                  label: allergen.label,
                  selected: _allergens.contains(allergen.label),
                  onTap: () => _toggleAllergen(allergen.label),
                ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LfTextField(
                  fieldKey: const Key('dietary-allergen-input'),
                  controller: _allergenInput,
                  label: '其它忌口',
                  hintText: '如：芒果',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _addAllergen(),
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Padding(
                padding: const EdgeInsets.only(bottom: LfDimens.spaceMicro),
                child: LfIconButton(
                  key: const Key('dietary-allergen-add'),
                  icon: Icons.add,
                  semanticLabel: '添加忌口项',
                  onPressed: _addAllergen,
                ),
              ),
            ],
          ),
          if (customAllergens.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Wrap(
              spacing: LfDimens.spaceSmall,
              runSpacing: LfDimens.spaceSmall,
              children: [
                for (final allergen in customAllergens)
                  _AllergenChip(
                    label: allergen,
                    onRemove: () => _toggleAllergen(allergen),
                  ),
              ],
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            _error!,
            key: const Key('dietary-constraints-error'),
            style: LfText.body.copyWith(color: c.errorText),
          ),
        ],
        const SizedBox(height: LfDimens.spaceMedium),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
            LfPrimaryButton(
              key: const Key('dietary-constraints-save'),
              label: '保存',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
      ],
    );
  }
}

/// 约束小节标题：左标题 + 右「已选 / 上限」。
final class _ConstraintSectionHeader extends StatelessWidget {
  const _ConstraintSectionHeader({required this.title, required this.count});

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: LfText.bodyStrong.copyWith(color: c.cardForeground),
          ),
        ),
        Text(count, style: LfText.caption.copyWith(color: c.mutedForeground)),
      ],
    );
  }
}

/// 固定列数的选择网格：同一组里每个选项等宽，选中/取消都不会改变位置。
final class _ConstraintGrid extends StatelessWidget {
  const _ConstraintGrid({required this.children, this.columns = 2});

  final List<Widget> children;
  final int columns;

  static const double _gap = LfDimens.spaceSmall;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// 紧凑选择块（44dp 高、12 圆角）。
///
/// 旧实现直接复用页面级筛选胶囊：44dp 高 + 胶囊形 + 选中时把已选项追加到
/// Wrap 末尾，视觉上又大又跳。这里改成固定两列的方角块：选中 = 浅品牌底 +
/// 1px 品牌边 + 右侧勾，未选中 = muted 底 + 透明边；容器尺寸完全不变。
final class DietaryConstraintChoice extends StatelessWidget {
  const DietaryConstraintChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    final foreground = selected
        ? LfColors.mintText(brightness)
        : c.cardForeground;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? LfColors.brandSoft(brightness) : c.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LfDimens.radiusMd),
            side: BorderSide(
              color: selected ? mint.tone(300) : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('dietary-choice-$label'),
            onTap: onTap,
            child: SizedBox(
              height: LfDimens.minTouchTarget,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LfDimens.spaceSmall,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: LfText.body.copyWith(
                            color: foreground,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceMicro),
                    Icon(
                      Icons.check,
                      size: LfDimens.iconSm,
                      color: selected ? foreground : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
