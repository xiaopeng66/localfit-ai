import 'package:localfit_ai/features/progress/data/scale_channel.dart';
import 'package:localfit_ai/features/progress/data/scale_reading_source.dart';

/// Bluetooth SIG 标准体重秤服务（0x181D）的规范 UUID（小写 128 位形式）。
const standardWeightScaleServiceUuid = '0000181d-0000-1000-8000-00805f9b34fb';

/// 标准协议设备的描述（`ScaleReadingSource.parsers` 的认领依据）。
///
/// 名字是空串：原生按服务过滤、不回传广播名——**不编一个「设备名」出来**；
/// [ScaleDevice.advertises] 才是标准 parser 的认领条件。
const standardWeightScaleDevice = ScaleDevice(
  id: 'standard:0x181d',
  name: '',
  serviceUuids: [standardWeightScaleServiceUuid],
);

/// 标准体重测量协议（0x181D 服务 + 0x2A9D Weight Measurement 特征）——
/// 「第一个实现」，行为与第四轮 S6 逐字一致：扫描 / 连接 / 订阅 / IEEE-11073
/// SFLOAT 解析都在原生侧完成（`MainActivity.kt:280-470`），这里只把原生的
/// 一次 `scanOnce` 翻译出来，不重复实现协议。
final class StandardWeightMeasurementParser implements ScaleProtocolParser {
  StandardWeightMeasurementParser({ScaleChannel? channel})
    : _channel = channel ?? ScaleChannel();

  final ScaleChannel _channel;

  @override
  String get id => 'standard_weight_measurement';

  @override
  bool matches(ScaleDevice device) =>
      device.advertises(standardWeightScaleServiceUuid);

  /// [window] 对标准协议**不生效**（原生窗口固定 10 秒，`SCALE_TIMEOUT_MS`）：
  /// 文档如实写明，不假装能控制它。
  @override
  Future<ScaleReading> readOnce(
    ScaleDevice device, {
    required Duration window,
  }) => _channel.scanOnce();
}

/// 标准协议的「读数来源」：能力 / 授权 / 去系统设置直通通道；读取过一次
/// [ScaleParserRegistry] 分派（生产路径也真的过 registry——换掉认领者，
/// 来源的输出就换人）。
final class StandardScaleReadingSource implements ScaleReadingSource {
  factory StandardScaleReadingSource({
    ScaleChannel? channel,
    ScaleParserRegistry? parsers,
  }) {
    final resolved = channel ?? ScaleChannel();
    return StandardScaleReadingSource._(
      resolved,
      parsers ??
          ScaleParserRegistry([
            StandardWeightMeasurementParser(channel: resolved),
          ]),
    );
  }

  StandardScaleReadingSource._(this._channel, this._parsers);

  final ScaleChannel _channel;
  final ScaleParserRegistry _parsers;

  @override
  ScaleParserRegistry get parsers => _parsers;

  @override
  Future<ScaleAvailability> check() => _channel.check();

  @override
  Future<bool> requestPermission() => _channel.requestPermission();

  @override
  Future<void> openAppSettings() => _channel.openAppSettings();

  @override
  Future<ScaleReading> readOnce({
    Duration window = ScaleReadingSource.defaultWindow,
  }) => _parsers.readOnce(standardWeightScaleDevice, window: window);
}
