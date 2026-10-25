import 'package:image_picker/image_picker.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';

/// 菜品照片取图（docs/29 §P7 需求 16）：相机/相册选一张 → 复制进应用
/// 文档目录 → 返回可入库的路径。
///
/// 与聊天图片（`PickChatImage`）同一原则：绝不引用相册原始 URI（那个路径
/// 会随系统整理失效，而菜品照片是目录数据的一部分）。与聊天图片的差异是
/// **不走图片处理管线**：菜品缩略图只有 44dp，1280 宽一档已足够，直接在
/// `pickImage` 里用 `imageQuality`/`maxWidth` 压一次，省掉一次 isolate 解码。
final class PickDishImage {
  PickDishImage({ImagePicker? picker, required this.store, required this.clock})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final DishImageStore store;
  final AppClock clock;

  /// 返回 null 表示用户取消选择（不是错误）；失败抛
  /// [DishImageStoreException]（表单内联显示）。
  Future<String?> pick(bool fromCamera) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        requestFullMetadata: false,
      );
    } catch (_) {
      throw const DishImageStoreException('无法选择照片，请检查相机或相册权限后重试。');
    }
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const DishImageStoreException('所选照片为空，请换一张。');
    }
    return store.copyBytes(
      bytes,
      createdAt: clock.nowUtc(),
      extension: _extensionOf(file.name),
    );
  }

  /// 相册里的文件名后缀（`.png`/`.heic`…）；无法识别时回落到 `.jpg`
  /// （[DishImageStore.copyBytes] 自身也有白名单校验，这里只是尽量保真）。
  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '.jpg';
    final extension = fileName.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]+$').hasMatch(extension) ? extension : '.jpg';
  }
}
