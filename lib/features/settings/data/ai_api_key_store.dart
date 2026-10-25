import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart'
    show AiApiKeyStoreRef;

/// 本机 Key **读不出来**时的统一文案（单一事实源）。
///
/// 与「没配 Key」（'AI 服务尚未配置…'）刻意不同：这里条目是在的，只是读失败
/// （系统凭据被重置/迁移等），用户能救回来的动作是**重新填写并保存**。
const String kAiApiKeyUnreadableMessage =
    '本机保存的 API Key 读取失败（系统凭据可能已重置），'
    '请在「AI 配置」里重新填写并保存。';

final class AiApiKeyStore implements AiApiKeyStoreRef {
  AiApiKeyStore({required this.store});

  static const storageKey = 'localfit.ai.api_key.v1';

  final SecureKeyValueStore store;

  Future<bool> hasKey() async => (await read()) != null;

  /// 拒绝含控制字符（误粘贴的换行/回车会让请求头构造失败并被错误归类为
  /// 网络故障）与超长输入的 Key。
  void _validate(String value) {
    if (value.trim().isEmpty) {
      throw const ValidationFailure('API Key 不能为空。');
    }
    if (value.trim().length > 4096) {
      throw const ValidationFailure('API Key 过长，请检查是否粘贴了多余内容。');
    }
    if (value.trim().codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw const ValidationFailure('API Key 包含换行等无效字符，请重新粘贴。');
    }
  }

  /// 读取本机保存的 Key。
  ///
  /// **读失败与「没存过」是两件不同的事**，文案必须分开（2026-10-16 设备实测）：
  /// 应用升级后系统凭据可能被重置，此时条目还在、但读出来会抛 —— 用户需要的是
  /// 「重新填写并保存」，而不是「网络连接不可用」这类误导。
  Future<String?> read() async {
    try {
      return await store.read(storageKey);
    } catch (error) {
      throw StorageFailure(kAiApiKeyUnreadableMessage, cause: error);
    }
  }

  Future<void> save(String value) async {
    _validate(value);
    try {
      await store.write(storageKey, value.trim());
    } catch (error) {
      throw StorageFailure('无法保存 AI API Key。', cause: error);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await store.delete(storageKey);
    } catch (error) {
      throw StorageFailure('无法清除 AI API Key。', cause: error);
    }
  }
}
