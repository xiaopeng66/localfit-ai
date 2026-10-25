import 'package:flutter/material.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_form_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_form_validation.dart';

/// 食堂 tab 的四张表单弹层：添加地点 / 添加窗口 / 添加菜品 / 编辑菜品。
///
/// 从页面抽出来的只是编排（开弹层 → 表现层预校验 → 落库 → 报错选址），
/// 与布局无关，所以放在页面之外不违反 docs/07 §9.3 的「页面只做编排」——
/// 反而让页面回到只负责布局与用户事件。表单字段仍由 [CanteenFormSheet]
/// 持有控制器（弹层关闭时统一释放）；校验规则见
/// `canteen_form_validation.dart`（与 `CanteenRepository` 的字面口径逐字
/// 一致，同一个严格 `HH:MM` 正则，避免两处判定漂移）。
///
/// 【N7】校验与落库都放在弹层的提交路径里：任一步失败都返回一句文案而不
/// 关窗，用户可以直接改。旧做法是「先关窗、再写库、失败只闪一条 snackbar」
/// ——弹层挂在根导航器上盖住整页，那条提示在物理上看不见，用户的输入也
/// 已经丢了。
class MenuFormPrompts {
  const MenuFormPrompts({
    required this.repository,
    required this.reload,
    this.pickDishImage,
    this.onDishCreated,
  });

  final CanteenRepository repository;

  /// 每次成功落库后刷新页面数据（由页面提供，保证弹层与列表同源）。
  final Future<void> Function() reload;

  /// 菜品照片取图（docs/29 §P7 需求 16）：source 为 true＝拍照、false＝
  /// 从相册选，返回私有目录里的新路径；null＝用户取消。null（未接线）＝
  /// 表单不渲染照片字段（纯测试嵌入场景）。真实实现见 `main.dart`
  ///（ImagePicker → [DishImageStore.copyBytes]）。
  final Future<String?> Function(bool fromCamera)? pickDishImage;

  /// 建菜/改名成功后的「参考食物库」匹配回调（docs/40 §3.1，2026-10-18）。
  /// 参数是 (dishId, 菜名)。null＝不跑匹配（旧调用点行为逐字不变）。
  final Future<void> Function(String dishId, String dishName)? onDishCreated;

  /// 把一次落库交给弹层的提交路径：返回 `null` = 成功（弹层关闭），
  /// 返回文案 = 留在弹层内显示。
  Future<String?> _writeViaSheet(Future<void> Function() action) async {
    try {
      await action();
      await reload();
      return null;
    } on CanteenWriteException catch (error) {
      return error.userMessage;
    } catch (_) {
      return '操作失败：请稍后重试。';
    }
  }

  Future<void> promptAddVenue(
    BuildContext context, {
    String? prefillName,
  }) async {
    await CanteenFormSheet.show(
      context,
      title: '添加食堂地点',
      fields: [
        CanteenField(
          key: 'canteen-venue-name',
          label: '地点名称',
          hint: '例：东区食堂',
          autofocus: true,
          // 2026-10-16：AI 对话的「新建地点「X」」把名字带进来（同一套口径，
          // 校区仍由用户填——App 不替用户编数据）。
          initialValue: prefillName ?? '',
        ),
        const CanteenField(
          key: 'canteen-venue-campus',
          label: '学校/园区（可留空）',
          hint: '例：示范大学',
        ),
      ],
      onSubmit: (values) async {
        final error = validateVenueForm(values);
        if (error != null) return error;
        return _writeViaSheet(
          () => repository.createVenue(
            name: values['canteen-venue-name']!,
            campusName: values['canteen-venue-campus']!,
          ),
        );
      },
    );
  }

  Future<void> promptAddWindow(
    BuildContext context,
    String venueId, {
    String? prefillName,
  }) async {
    await CanteenFormSheet.show(
      context,
      title: '添加窗口',
      fields: [
        CanteenField(
          key: 'canteen-window-name',
          label: '窗口名称',
          hint: '例：一楼快餐',
          autofocus: true,
          initialValue: prefillName ?? '',
        ),
        const CanteenField(
          key: 'canteen-window-open',
          label: '开始时间（HH:MM）',
          initialValue: '08:00',
        ),
        const CanteenField(
          key: 'canteen-window-close',
          label: '结束时间（HH:MM）',
          initialValue: '20:00',
        ),
      ],
      onSubmit: (values) async {
        final error = validateWindowForm(values);
        if (error != null) return error;
        return _writeViaSheet(
          () => repository.createWindow(
            venueId: venueId,
            name: values['canteen-window-name']!,
            openTime: values['canteen-window-open']!,
            closeTime: values['canteen-window-close']!,
          ),
        );
      },
    );
  }

  Future<void> promptAddDish(BuildContext context, String windowId) =>
      _promptDishForm(
        context,
        title: '添加菜品',
        write: (name, imagePath, _) async {
          final id = await repository.createDish(
            windowId: windowId,
            name: name,
            // 新增：快照里的路径就是最终态（空串＝没加照片，写 null）。
            imagePath: imagePath.isEmpty ? null : imagePath,
          );
          // 建菜成功后本地跑一次食物库匹配（docs/40 §3.1）：命中给三选一，
          // 不静默填。回调未接线/无命中时什么都不发生（旧行为）。
          await onDishCreated?.call(id, name);
        },
      );

  Future<void> promptEditDish(BuildContext context, CanteenDish dish) =>
      _promptDishForm(
        context,
        title: '编辑菜品',
        initialName: dish.name,
        initialImagePath: dish.imagePath ?? '',
        // 第四参 setImagePath：用户没碰照片字段时保持 false，仓库不写列、
        // 也不删旧文件（测试锚点：'编辑菜品：未碰照片不动列'）。
        write: (name, imagePath, setImagePath) async {
          await repository.updateDish(
            dishId: dish.id,
            name: name,
            imagePath: imagePath.isEmpty ? null : imagePath,
            setImagePath: setImagePath,
          );
          // 改名同样给一次匹配建议（docs/40 §3.1「建菜/改名成功后」）。
          await onDishCreated?.call(dish.id, name);
        },
      );

  /// 菜名（+ 可选照片）表单；落库失败留在弹层内给文案（N7）。
  /// 照片字段只在 [pickDishImage] 已接线时渲染。
  ///
  /// 2026-10-16 用户要求删掉价格：字段与校验整条撤掉（列已随 v26 迁移退役）。
  ///
  /// [write] 的第二参是照片路径快照（空串＝无照片），第三参是本表单里
  /// 照片是否被改动过：新增表单恒为 true（首次写入即最终态），编辑表单
  /// 与初值相同则为 false（仓库不碰照片列）。
  Future<void> _promptDishForm(
    BuildContext context, {
    required String title,
    required Future<void> Function(
      String name,
      String imagePath,
      bool setImagePath,
    )
    write,
    String initialName = '',
    String initialImagePath = '',
  }) async {
    final pick = pickDishImage;
    await CanteenFormSheet.show(
      context,
      title: title,
      fields: [
        CanteenField(
          key: 'canteen-dish-name',
          label: '菜品名称',
          hint: '例：番茄炒蛋',
          initialValue: initialName,
          autofocus: true,
        ),
        // 照片可选可删（需求 16）：没有的事不画，移除后回虚线空态。
        if (pick != null)
          CanteenField(
            key: 'canteen-dish-photo',
            label: '菜品照片（可选）',
            initialValue: initialImagePath,
            photo: true,
            onPickPhoto: pick,
          ),
      ],
      onSubmit: (values) async {
        final error = validateDishForm(values);
        if (error != null) return error;
        final imagePath = values['canteen-dish-photo'] ?? initialImagePath;
        return _writeViaSheet(
          () => write(
            values['canteen-dish-name']!,
            imagePath,
            imagePath != initialImagePath,
          ),
        );
      },
    );
  }
}
