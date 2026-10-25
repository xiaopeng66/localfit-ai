import 'package:localfit_ai/features/settings/data/pick_avatar.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// 选头像的结果：改了 / 用户取消 / 失败（[message] 是给用户看的人话）。
enum AvatarUpdateStatus { updated, cancelled, failed }

final class AvatarUpdateResult {
  const AvatarUpdateResult._(this.status, [this.message]);

  const AvatarUpdateResult.updated() : this._(AvatarUpdateStatus.updated);
  const AvatarUpdateResult.cancelled() : this._(AvatarUpdateStatus.cancelled);
  const AvatarUpdateResult.failed(String message)
    : this._(AvatarUpdateStatus.failed, message);

  final AvatarUpdateStatus status;
  final String? message;
}

/// 「选一张头像并落库」的**单一实现**（docs/32 §3 D9 的语义）：
/// 相册 → 512/0.9 压一次 → 落私有目录 → 写库 → **删旧文件**（替换语义）。
///
/// 2026-10-16：入口从设置页身份卡迁到「编辑资料」页（用户要求头像与昵称统一
/// 在那里改），所以这段流程从设置页的 State 里搬出来，两处（将来若再增入口）
/// 共用一份——不在两个页面各写一遍删旧文件/清孤儿文件的细节。
///
/// 失败语义：写库失败时把**刚落的文件删掉**再报错（不留半套状态）。
Future<AvatarUpdateResult> pickAndStoreAvatar({
  required ProfileIdentityRepository repository,
  required PickAvatar picker,
  required String? oldPath,
}) async {
  final String? newPath;
  try {
    newPath = await picker.pickFromGallery();
  } catch (error) {
    return AvatarUpdateResult.failed('$error');
  }
  if (newPath == null) return const AvatarUpdateResult.cancelled();
  try {
    await repository.updateAvatarPath(newPath);
  } catch (error) {
    await picker.store.deleteQuietly(newPath);
    return AvatarUpdateResult.failed('$error');
  }
  if (oldPath != null && oldPath != newPath) {
    await picker.store.deleteQuietly(oldPath);
  }
  return const AvatarUpdateResult.updated();
}
