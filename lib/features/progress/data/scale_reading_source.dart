import 'package:localfit_ai/features/progress/data/scale_channel.dart';

/// 电子秤「读数来源」抽象（docs/32 §3 D16，需求 78）——本轮**只预留接口**，
/// 不实现任何私有协议解析（无真表无法诚实验收）。
///
/// 三条接缝就是本轮的全部交付：
/// ① 编排（`ScaleSyncController`）只认 [ScaleReadingSource]，不碰平台通道；
/// ② 协议分派挂点 = [ScaleParserRegistry]：按**广播服务 UUID / 设备名**认领
///    解析器，将来小米这类私有协议在这里注册条目；
/// ③ 私有协议适配 = 实现 [ScaleProtocolParser] + `registry.register(...)`，
///    编排层一行不改（`scale_reading_source_test.dart` 用假 parser 证明）。
///
/// **为什么操作面是「一次前台读取」而不是 `scan` + `readings` 两段**：原生通道
/// 只有合成原语 `scanOnce`（扫描 → 连接 → 订阅 → SFLOAT 解析在一次调用里完成、
/// 一次答复，`MainActivity.kt:280-470`），拆两段要么让一次调用冒充两段（撒谎）、
/// 要么改原生（本轮无法进 `flutter test` 门禁验证）。细则见 docs/32 §3 D16 的
/// 「范围修订」。将来适配私有协议时，原生侧还需补「发现（去掉 0x181D 过滤）+
/// 原始字节透传」那一半——那是后期适配备件（具体型号 + 真表在场）。

/// 一台被发现的秤（或它的协议描述）。
final class ScaleDevice {
  const ScaleDevice({
    required this.id,
    required this.name,
    this.serviceUuids = const [],
  });

  /// 设备标识：真实设备用平台侧地址；协议描述用 `standard:0x181d` 这类**明确
  /// 非硬件地址**的字符串（不冒充 MAC）。
  final String id;

  /// 广播名（广播里没带就是空串——不编名字）。
  final String name;

  /// 广播服务 UUID（可能大小写混杂，比较一律走 [advertises]）。
  final List<String> serviceUuids;

  /// 广播里是否带该服务（大小写不敏感）。
  bool advertises(String serviceUuid) {
    final needle = serviceUuid.toLowerCase();
    return serviceUuids.any((service) => service.toLowerCase() == needle);
  }
}

/// 协议解析器：认领设备 → 读一次读数（克、公制）。
///
/// **这是扩展点**：新增私有协议（小米等）= 实现本接口并注册进来源的
/// [ScaleParserRegistry]；编排与落地规则零改动（D16 验收 ③）。
abstract interface class ScaleProtocolParser {
  /// 注册名（诊断用；界面不显示）。
  String get id;

  /// 是否认领这台设备（按广播名/服务 UUID 判断，不猜）。
  bool matches(ScaleDevice device);

  /// 从这台设备读一次（含连接与订阅；标准实现在原生侧完成）。
  ///
  /// [window] 是读取窗口；对**标准协议无效**——原生窗口固定 10 秒
  /// （`MainActivity.kt` `SCALE_TIMEOUT_MS`），参数留给将来能自定义窗口的
  /// 来源/解析器，本轮不假装能控制它。
  Future<ScaleReading> readOnce(ScaleDevice device, {required Duration window});
}

/// 协议分派表：按注册顺序取**第一个认领**的解析器（先注册先命中）。
final class ScaleParserRegistry {
  ScaleParserRegistry([Iterable<ScaleProtocolParser> parsers = const []])
    : _parsers = List.of(parsers);

  final List<ScaleProtocolParser> _parsers;

  List<ScaleProtocolParser> get parsers => List.unmodifiable(_parsers);

  /// 追加一个解析器。重复 id = 接线错误：直接抛，不静默覆盖。
  void register(ScaleProtocolParser parser) {
    if (_parsers.any((it) => it.id == parser.id)) {
      throw ArgumentError.value(
        parser.id,
        'parser.id',
        '解析器 id 已注册过（重复注册 = 接线错误）',
      );
    }
    _parsers.add(parser);
  }

  /// 认领 [device] 的第一个解析器；没人认领就是 `null`（如实「不认」，
  /// 不硬塞一个去试）。
  ScaleProtocolParser? forDevice(ScaleDevice device) {
    for (final parser in _parsers) {
      if (parser.matches(device)) return parser;
    }
    return null;
  }

  /// 分派读一次：没人认领时如实报 `timeout`/`no_parser`，**不猜数值**。
  Future<ScaleReading> readOnce(
    ScaleDevice device, {
    Duration window = ScaleReadingSource.defaultWindow,
  }) {
    final parser = forDevice(device);
    if (parser == null) {
      return Future.value(
        const ScaleReading(
          status: ScaleReadStatus.timeout,
          reason: 'no_parser',
        ),
      );
    }
    return parser.readOnce(device, window: window);
  }
}

/// 「读数来源」：把**扫描 + 订阅 + 解析**从通道实现里解耦的接缝
/// （D16）。标准协议实现见 `standard_scale_reading_source.dart`；将来每种
/// 私有协议 = 一份新的来源实现 + 注册它的 parser。
abstract interface class ScaleReadingSource {
  /// 读取窗口默认值 = 原生的扫描窗口（`SCALE_TIMEOUT_MS` 10 秒）。
  static const Duration defaultWindow = Duration(seconds: 10);

  /// 协议分派表（D16 型号/厂商挂点）：`register` 一个 parser 即接入一种协议。
  ScaleParserRegistry get parsers;

  /// 能力查询（界面行徽章与编排入口判断用）。
  Future<ScaleAvailability> check();

  /// 请求蓝牙运行时权限（API 31+）。返回是否已授权。
  Future<bool> requestPermission();

  /// 打开本应用的系统设置页（权限被拒后的出口）。
  Future<void> openAppSettings();

  /// 前台读一次：扫描 → 按 [parsers] 分派 → 订阅一次 → 断开。
  ///
  /// [window] 默认 = [defaultWindow]（原生标准路径的固定 10 秒窗口）。
  Future<ScaleReading> readOnce({Duration window = defaultWindow});
}
