import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:localfit_ai/features/food_scan/data/meal_image_processor.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

void main() {
  test(
    're-encodes JPEG without EXIF and bounds its largest dimension',
    () async {
      final source = image_lib.Image(width: 2000, height: 1000);
      source.setPixelRgb(0, 0, 255, 0, 0);
      source.exif.imageIfd['Make'] = 'Sensitive Camera';
      source.exif.exifIfd['DateTimeOriginal'] = '2026:09:10 12:00:00';
      source.exif.gpsIfd['GPSLatitudeRef'] = 'N';
      final original = Uint8List.fromList(
        image_lib.encodeJpg(source, quality: 95),
      );
      final processor = const IsolateMealImageProcessor(maxDimension: 800);

      final result = await processor.process(
        SelectedMealImage(bytes: original, source: MealImageSource.gallery),
      );
      final decoded = image_lib.decodeJpg(result.bytes)!;

      expect(result.width, 800);
      expect(result.height, 400);
      expect(decoded.exif.isEmpty, isTrue);
      expect(result.bytes[0], 0xff);
      expect(result.bytes[1], 0xd8);
      expect(
        String.fromCharCodes(result.bytes).contains('Sensitive Camera'),
        isFalse,
      );
    },
  );

  test('rejects corrupt and oversized inputs', () async {
    const processor = IsolateMealImageProcessor(maxInputBytes: 4);
    await expectLater(
      processor.process(
        SelectedMealImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          source: MealImageSource.camera,
        ),
      ),
      throwsA(isA<MealImageFailure>()),
    );
    await expectLater(
      processor.process(
        SelectedMealImage(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          source: MealImageSource.camera,
        ),
      ),
      throwsA(isA<MealImageFailure>()),
    );
  });
}
