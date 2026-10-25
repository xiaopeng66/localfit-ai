import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class IsolateMealImageProcessor implements MealImageProcessor {
  const IsolateMealImageProcessor({
    this.maxDimension = 1600,
    this.jpegQuality = 82,
    this.maxInputBytes = 25 * 1024 * 1024,
  });

  final int maxDimension;
  final int jpegQuality;
  final int maxInputBytes;

  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async {
    if (selected.bytes.isEmpty || selected.bytes.length > maxInputBytes) {
      throw const MealImageFailure('图片为空或超过 25 MB，请选择较小的图片。');
    }
    try {
      final result = await Isolate.run(
        () => _sanitize(
          _ProcessInput(
            bytes: selected.bytes,
            maxDimension: maxDimension,
            quality: jpegQuality,
          ),
        ),
      );
      return ProcessedMealImage(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
      );
    } on MealImageFailure {
      rethrow;
    } catch (_) {
      throw const MealImageFailure('图片格式不受支持或文件已损坏。');
    }
  }
}

final class _ProcessInput {
  const _ProcessInput({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
  });

  final Uint8List bytes;
  final int maxDimension;
  final int quality;
}

final class _ProcessResult {
  const _ProcessResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

_ProcessResult _sanitize(_ProcessInput input) {
  var decoded = image_lib.decodeImage(input.bytes);
  if (decoded == null) throw const MealImageFailure('图片格式不受支持或文件已损坏。');
  decoded = image_lib.bakeOrientation(decoded);
  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  if (longest > input.maxDimension) {
    decoded = image_lib.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? input.maxDimension : null,
      height: decoded.height > decoded.width ? input.maxDimension : null,
      interpolation: image_lib.Interpolation.average,
    );
  }
  decoded.exif.clear();
  final bytes = Uint8List.fromList(
    image_lib.encodeJpg(decoded, quality: input.quality),
  );
  return _ProcessResult(
    bytes: bytes,
    width: decoded.width,
    height: decoded.height,
  );
}
