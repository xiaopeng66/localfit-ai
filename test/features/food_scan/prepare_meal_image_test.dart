import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

void main() {
  late _Picker picker;
  late _Processor processor;
  late _Store store;
  late PrepareMealImage prepare;

  setUp(() {
    picker = _Picker();
    processor = _Processor();
    store = _Store();
    prepare = PrepareMealImage(
      picker: picker,
      processor: processor,
      store: store,
    );
  });

  test('cancellation keeps the current image and creates no file', () async {
    const current = PreparedMealImage(
      path: 'current.jpg',
      width: 10,
      height: 10,
      byteLength: 10,
    );
    picker.next = null;

    expect(
      await prepare.select(MealImageSource.gallery, current: current),
      isNull,
    );
    expect(store.saved, isEmpty);
    expect(store.deleted, isEmpty);
  });

  test(
    'successful replacement saves new image before deleting current',
    () async {
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        source: MealImageSource.camera,
      );
      const current = PreparedMealImage(
        path: 'current.jpg',
        width: 10,
        height: 10,
        byteLength: 10,
      );

      final result = await prepare.select(
        MealImageSource.camera,
        current: current,
      );

      expect(result!.path, 'prepared-0.jpg');
      expect(store.events, ['save', 'delete:current.jpg']);
    },
  );

  test(
    'processing failure keeps current and does not save or delete',
    () async {
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.gallery,
      );
      processor.failure = const MealImageFailure('bad image');

      await expectLater(
        prepare.select(
          MealImageSource.gallery,
          current: const PreparedMealImage(
            path: 'current.jpg',
            width: 1,
            height: 1,
            byteLength: 1,
          ),
        ),
        throwsA(isA<MealImageFailure>()),
      );
      expect(store.saved, isEmpty);
      expect(store.deleted, isEmpty);
    },
  );

  test('initialize clears stale artifacts and discard is nullable', () async {
    await prepare.initialize();
    await prepare.discard(null);
    expect(store.cleared, isTrue);
    expect(store.deleted, isEmpty);
  });
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async => next;

  @override
  Future<SelectedMealImage?> recoverLost() async => null;
}

final class _Processor implements MealImageProcessor {
  MealImageFailure? failure;

  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async {
    if (failure case final error?) throw error;
    return ProcessedMealImage(bytes: selected.bytes, width: 20, height: 10);
  }
}

final class _Store implements TemporaryMealImageStore {
  final saved = <ProcessedMealImage>[];
  final deleted = <PreparedMealImage>[];
  final events = <String>[];
  bool cleared = false;

  @override
  Future<void> clearStale() async => cleared = true;

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {
    deleted.add(image);
    events.add('delete:${image.path}');
  }

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async {
    saved.add(image);
    events.add('save');
    return PreparedMealImage(
      path: 'prepared-${saved.length - 1}.jpg',
      width: image.width,
      height: image.height,
      byteLength: image.bytes.length,
    );
  }
}
