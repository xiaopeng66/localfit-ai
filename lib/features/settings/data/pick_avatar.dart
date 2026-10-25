import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:localfit_ai/features/settings/data/avatar_image_store.dart';

/// 选头像（docs/32 §3 D9）：相册选图 → 压到 `maxWidth/maxHeight 512`、
/// `imageQuality 90` → 复制进 [AvatarImageStore] 的私有目录 → 返回新路径。
///
/// 选图与存储分开：本类只负责「取一张图并落盘」，写库由调用方在同一处
/// 完成（与 `PickDishImage` 同一分层）。用户取消返回 null（不报错）。
final class PickAvatar {
  PickAvatar({ImagePicker? picker, required this.store})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final AvatarImageStore store;

  /// D9 的字面值：512×512 上限、质量 90（一次性压到位，省二次解码）。
  static const double maxDimension = 512;
  static const int quality = 90;

  Future<String?> pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: quality,
    );
    if (file == null) return null;
    final bytes = await File(file.path).readAsBytes();
    return store.copyBytes(
      bytes,
      createdAt: DateTime.now().toUtc(),
      extension: _extensionOf(file.path),
    );
  }

  static String _extensionOf(String filePath) {
    final dot = filePath.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = filePath.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]+$').hasMatch(extension) ? extension : '.jpg';
  }
}
