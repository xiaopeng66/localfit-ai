import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_form_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_window_card.dart';

/// docs/29 §P7 需求 16/17：菜品行行头（序号圆 / 缩略图 / 档口副行）与
/// 菜品表单的照片字段（可选、可删、失败留窗）。
///
/// 用真实仓库（内存库）+ 注入的假 picker：断言的是**仓库里真的写了
/// imagePath**，不是弹层内部状态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late CanteenRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CanteenRepository(
      database: database,
      idGenerator: _Ids(),
      clock: _FixedClock(DateTime.utc(2026, 10, 6, 12)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('菜品行（CanteenDishRow）', () {
    Future<void> pumpRow(
      WidgetTester tester, {
      required CanteenDish dish,
      required int index,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [LfSemanticColors.light]),
          home: Scaffold(
            body: CanteenDishRow(dish: dish, index: index),
          ),
        ),
      );
    }

    testWidgets('无照片：行头是序号圆（不是缩略图），档口做副行', (tester) async {
      final venueId = await repository.createVenue(
        name: '东区食堂',
        campusName: '',
      );
      final windowId = await repository.createWindow(
        venueId: venueId,
        name: '一楼快餐',
        openTime: '08:00',
        closeTime: '13:30',
      );
      await repository.createDish(
        windowId: windowId,
        name: '红烧排骨',
        stationName: '川湘窗口',
      );
      final dish = (await repository.listDishes(windowId)).single;

      await pumpRow(tester, dish: dish, index: 2);

      // 序号圆在场、显示窗口内序号（1 起）。
      final indexCircle = find.byKey(Key('canteen-dish-index-${dish.id}'));
      expect(indexCircle, findsOneWidget);
      expect(
        find.descendant(of: indexCircle, matching: find.text('2')),
        findsOneWidget,
      );
      // 无照片不画缩略图（诚实空态，不伪造占位图）。
      expect(
        find.byKey(Key('canteen-dish-photo-thumb-${dish.id}')),
        findsNothing,
      );
      // 档口副行（列本来就在，此前读取侧整列丢弃）。
      expect(
        find.byKey(Key('canteen-dish-station-${dish.id}')),
        findsOneWidget,
      );
      expect(find.text('川湘窗口'), findsOneWidget);
      // 右列：未分析 ⇒ 什么都不画（2026-10-16 删掉价格后，这里不再有
      // 「15.00 元」那一行——用户要求把价格从所有地方删掉）。
      expect(find.textContaining('元'), findsNothing);
    });

    testWidgets('有照片：行头换成缩略图，序号圆不渲染', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('localfit-dish-row-');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final photo = File('${tempDir.path}${Platform.pathSeparator}dish.jpg')
        ..writeAsBytesSync(_tinyJpeg);

      const dish = CanteenDish(
        id: 'dish-1',
        windowId: 'window-1',
        name: '番茄炒蛋',
        evidenceGrade: 'C',
        itemStatus: 'unresolved',
        evidence: null,
        imagePath: null,
      );
      final withPhoto = CanteenDish(
        id: dish.id,
        windowId: dish.windowId,
        name: dish.name,
        evidenceGrade: dish.evidenceGrade,
        itemStatus: dish.itemStatus,
        evidence: null,
        imagePath: photo.path,
      );

      await pumpRow(tester, dish: withPhoto, index: 1);

      expect(
        find.byKey(Key('canteen-dish-photo-thumb-${dish.id}')),
        findsOneWidget,
      );
      expect(find.byKey(Key('canteen-dish-index-${dish.id}')), findsNothing);
      // 缩略图 44dp 圆角（设计稿值）。
      final image = tester.widget<Image>(
        find.byKey(Key('canteen-dish-photo-thumb-${dish.id}')),
      );
      expect(image.width, 44);
      expect(image.height, 44);
    });
  });

  group('菜品表单照片字段（CanteenFormSheet）', () {
    testWidgets('无图初态：虚线空态 + 两个动作；移除后快照里的路径也清空', (tester) async {
      // 先测「有图可删」：初值带路径。**捕获提交快照**——只断言 UI 回
      // 空态会漏掉「UI 清了但快照仍带旧路径」的缺陷（保存时旧照片又被
      // 写回库）。
      Map<String, String>? snapshot;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [LfSemanticColors.light]),
          home: Scaffold(
            body: CanteenFormSheet(
              title: '编辑菜品',
              fields: [
                CanteenField(
                  key: 'canteen-dish-photo',
                  label: '菜品照片（可选）',
                  initialValue: '/tmp/old.jpg',
                  photo: true,
                  onPickPhoto: (_) async => null,
                ),
              ],
              onSubmit: (values) => snapshot = values,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('canteen-dish-photo-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('canteen-dish-photo-remove')),
        findsOneWidget,
      );
      // 两个取图动作都在（拍照 / 从相册选）。
      expect(find.byKey(const Key('canteen-dish-photo-shoot')), findsOneWidget);
      expect(
        find.byKey(const Key('canteen-dish-photo-gallery')),
        findsOneWidget,
      );

      expect(snapshot?['canteen-dish-photo'], '/tmp/old.jpg', reason: '初值入快照');

      // 移除照片 → 回虚线空态，且**快照里的值也变空串**。
      await tester.tap(find.byKey(const Key('canteen-dish-photo-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('canteen-dish-photo-empty')), findsOneWidget);
      expect(find.byKey(const Key('canteen-dish-photo-preview')), findsNothing);
      expect(
        snapshot?['canteen-dish-photo'],
        '',
        reason: '移除后保存必须写空路径（否则旧照片被写回库）',
      );
    });

    testWidgets('新增菜品：快照带照片路径', (tester) async {
      Map<String, String>? snapshot;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [LfSemanticColors.light]),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    snapshot = await CanteenFormSheet.show(
                      context,
                      title: '添加菜品',
                      fields: [
                        const CanteenField(
                          key: 'canteen-dish-name',
                          label: '菜品名称',
                        ),
                        const CanteenField(
                          key: 'canteen-dish-photo',
                          label: '菜品照片（可选）',
                          photo: true,
                        ),
                      ],
                      onSubmit: (values) async => null,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 无 onPickPhoto 时不渲染取图动作，但字段值仍在快照里（空串）。
      expect(find.byKey(const Key('canteen-dish-photo-shoot')), findsNothing);
      await tester.tap(find.byKey(const Key('canteen-form-submit')));
      await tester.pumpAndSettle();
      expect(snapshot?['canteen-dish-photo'], '');
    });
  });
}

/// 极小 JPEG 头（不需要可解码：Image.file 的 errorBuilder 会接住）。
final List<int> _tinyJpeg = [
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0xFF,
  0xD9,
];

final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String next() {
    _next++;
    return 'id-${_next.toString().padLeft(4, '0')}';
  }
}

final class _FixedClock implements AppClock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime nowUtc() => _now;
}
