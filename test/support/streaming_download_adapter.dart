import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 下载进度测试的假 `HttpClientAdapter`：把「多块字节流 + content-length」
/// 喂给**真实的** `dio.download`。
///
/// 为什么不用拦截器 `handler.resolve`：`download` 消费的是 `ResponseBody.stream`
/// 的分块流（`onReceiveProgress` 在**每块写完文件后**回调，`total` 从
/// `content-length` 头读出）；拦截器只能伪造一个 JSON 响应体，驱动不了那条流。
/// 换掉 `httpClientAdapter` 才能让进度回调走生产路径。
///
/// [closeStream] = false 时不发结束事件：模拟「连上了、收了一块、之后不动了」，
/// 正是取消操作要打断的状态（`CancelToken.cancel` 会取消订阅并删半截文件）。
final class StreamingDownloadAdapter implements HttpClientAdapter {
  StreamingDownloadAdapter({
    required this.chunks,
    this.contentLength,
    this.closeStream = true,
  });

  final List<List<int>> chunks;

  /// `null` = 不给 `content-length` 头（dio 的口径：`total` 回调为 -1）。
  final int? contentLength;
  final bool closeStream;

  final _opened = <StreamController<Uint8List>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final controller = StreamController<Uint8List>();
    _opened.add(controller);
    for (final chunk in chunks) {
      controller.add(Uint8List.fromList(chunk));
    }
    if (closeStream) unawaited(controller.close());
    return ResponseBody(
      controller.stream,
      200,
      headers: contentLength == null
          ? const <String, List<String>>{}
          : <String, List<String>>{
              Headers.contentLengthHeader: <String>['$contentLength'],
            },
    );
  }

  @override
  void close({bool force = false}) {
    for (final controller in _opened) {
      if (!controller.isClosed) unawaited(controller.close());
    }
  }
}
