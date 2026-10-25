import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_file_importer.dart';
import 'package:localfit_ai/features/campus_menus/data/file_menu_raw_content_store.dart';

void main() {
  late AppDatabase database;
  late Directory tempDir;
  late Directory rawDir;
  late String venueId;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('localfit-fileimport-');
    rawDir = Directory('${tempDir.path}${Platform.pathSeparator}raw')
      ..createSync();
    final now = DateTime.now().toUtc();
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: 'source-1',
            venueId: 'venue-1',
            sourceType: 'file_txt_csv_json',
            createdAt: now,
            updatedAt: now,
          ),
        );
    venueId = 'venue-1';
  });
  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });
  group('导入文件大小上限（docs/25 §5 L5）', () {
    test('超过上限的文件在读入内存之前就被拒绝', () async {
      // 真实的 8 MiB 上限：不注入小阈值，测的就是生产判据本身。
      final file = File('${tempDir.path}${Platform.pathSeparator}huge.csv');
      final handle = file.openSync(mode: FileMode.write);
      // truncate 直接把文件拉长（不写 8 MiB 的零字节约到内存里）。
      handle.truncateSync(menuImportMaxBytes + 1);
      handle.closeSync();
      expect(file.lengthSync(), menuImportMaxBytes + 1);

      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );

      await expectLater(
        importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
        ),
        throwsA(
          isA<MenuFileImportException>()
              .having(
                (error) => error.kind,
                'kind',
                MenuImportFailureKind.fileTooLarge,
              )
              .having(
                (error) => error.userMessage,
                'userMessage',
                contains('文件过大'),
              )
              .having(
                (error) => error.message,
                'message',
                // 开发者文本带真实体积，上屏文案不带（docs/11 §3-B）。
                contains('file too large'),
              ),
        ),
      );
      // 没有落任何快照/失败 job：文件在解析之前就被挡住了。
      expect(await database.select(database.menuSnapshots).get(), isEmpty);
      expect(await database.select(database.menuImportJobs).get(), isEmpty);
    });

    test('恰好等于上限的文件放行（判据是「大于」不是「大于等于」）', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}at-limit.csv');
      final handle = file.openSync(mode: FileMode.write);
      handle.truncateSync(menuImportMaxBytes);
      handle.closeSync();

      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );

      await expectLater(
        importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
        ),
        // 8 MiB 的 NUL 不是合法 CSV 内容 ⇒ 走内容解析失败，而不是大小判据。
        throwsA(
          isA<MenuFileImportException>().having(
            (error) => error.kind,
            'kind',
            isNot(MenuImportFailureKind.fileTooLarge),
          ),
        ),
      );
    });
  });

  group('menu file importer', () {
    test(
      'parses the structured JSON template into a draft and publishes',
      () async {
        final file = File('${tempDir.path}${Platform.pathSeparator}menu.json')
          ..writeAsStringSync('''
{"source_date":"2026-09-15","venue_name":"东区食堂",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","price_minor":800}]}]}
''');
        final store = FileMenuRawContentStore(rawDir.path);
        final importer = MenuFileImporter(
          database: database,
          rawContentStore: store,
        );
        final result = await importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
        );
        expect(result.snapshotId, isNotNull);
        // 原文已保存且 hash 落库；入库的是相对路径（docs/07 §6.1），
        // 绝对路径会随设备/沙箱目录漂移。
        final snapshot =
            (await database.select(database.menuSnapshots).get()).single;
        expect(snapshot.rawContentPath, 'menu_raw/${snapshot.id}.raw');
        expect(snapshot.rawContentHash, hasLength(64));
        expect(
          File(store.resolve(snapshot.rawContentPath!)).readAsStringSync(),
          contains('鸡蛋炒饭'),
        );
      },
    );
    test('keeps no raw text when the source disallows saving it', () async {
      // docs/07 §6.1 末句：用户可以选择「不保存原文，只保存已确认的结构化菜单」。
      await (database.update(database.menuSources)
            ..where((row) => row.id.equals('source-1')))
          .write(const MenuSourcesCompanion(allowRawContent: Value(false)));
      final file = File('${tempDir.path}${Platform.pathSeparator}no-raw.json')
        ..writeAsStringSync('''
{"source_date":"2026-09-15","venue_name":"东区食堂",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","price_minor":800}]}]}
''');
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );

      final result = await importer.importFile(
        venueId: venueId,
        sourceId: 'source-1',
        filePath: file.path,
      );

      // 结构化菜单照常发布，只是不留原文。
      expect(result.snapshotId, isNotNull);
      final snapshot =
          (await database.select(database.menuSnapshots).get()).single;
      expect(snapshot.rawContentPath, isNull);
      expect(snapshot.rawContentHash, isNull);
      final rawDirectory = Directory(
        '${rawDir.path}${Platform.pathSeparator}'
        '${FileMenuRawContentStore.directoryName}',
      );
      expect(rawDirectory.existsSync(), isFalse);
    });
    test('parses a simple CSV (service,open,close,item) file', () async {
      // 2026-10-16 用户删掉菜品价格：CSV 表头从「窗口,开始,结束,菜名,价格分」
      // 收成 4 列（`价格分` 列与解析同批退役；legacy 5 列表头按新事实拒绝，
      // 判据见下方「legacy 价格列表头被拒且不留快照」）。
      final file = File('${tempDir.path}${Platform.pathSeparator}menu.csv')
        ..writeAsStringSync('''
窗口,开始,结束,菜名
一楼窗口,10:30,13:30,鸡蛋炒饭
一楼窗口,10:30,13:30,清炒时蔬
''');
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );
      final result = await importer.importFile(
        venueId: venueId,
        sourceId: 'source-1',
        filePath: file.path,
      );
      expect(result.snapshotId, isNotNull);
      final items = await database.select(database.menuItems).get();
      expect(items, hasLength(2));
      expect(items.map((i) => i.displayName), containsAll(['鸡蛋炒饭', '清炒时蔬']));
      final services = await database.select(database.menuServices).get();
      expect(services, hasLength(1));
      expect(services.single.openTime, '10:30');
    });
    test('legacy 价格列表头被拒且不留快照（价格退役后的格式边界）', () async {
      // 2026-10-16 用户删掉菜品价格：CSV 只认 4 列。旧文件（带 `价格分`）
      // 要么按新格式重导，要么如实报「文件内容不符合导入格式」——不能被
      // 悄悄接受后把价格丢弃，因为「哪几列」是用户能看见的契约。
      final file = File('${tempDir.path}${Platform.pathSeparator}legacy.csv')
        ..writeAsStringSync('''
窗口,开始,结束,菜名,价格分
一楼窗口,10:30,13:30,鸡蛋炒饭,800
''');
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );
      await expectLater(
        importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
        ),
        throwsA(
          isA<MenuFileImportException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('文件内容不符合导入格式'),
          ),
        ),
      );
      expect(await database.select(database.menuItems).get(), isEmpty);
      expect(
        (await database.select(database.menuSnapshots).get()).where(
          (row) => row.status == 'active',
        ),
        isEmpty,
      );
    });
    test('parses a plain TXT with service and item lines', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}menu.txt')
        ..writeAsStringSync('''
# 一楼窗口 10:30-13:30
鸡蛋炒饭 800
清炒时蔬 600
''');
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );
      final result = await importer.importFile(
        venueId: venueId,
        sourceId: 'source-1',
        filePath: file.path,
      );
      expect(result.snapshotId, isNotNull);
      expect(await database.select(database.menuItems).get(), hasLength(2));
    });
    test(
      'the injected clock decides the business date, not the wall clock',
      () async {
        // 2.0-1j 缺陷回归：这里给一个 2020 年的时刻，快照就必须落在
        // 2020-01-02。之前业务日期取自真实时钟，跨日之后「刚导入的菜单」在
        // load(now:) 里查不到（菜单 tab 整个文件在第二天全红）。
        final file = File('${tempDir.path}${Platform.pathSeparator}clock.txt')
          ..writeAsStringSync('''
# 一楼窗口 10:30-13:30
鸡蛋炒饭 800
''');
        final importer = MenuFileImporter(
          database: database,
          rawContentStore: FileMenuRawContentStore(rawDir.path),
        );
        final result = await importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
          now: DateTime.utc(2020, 1, 2, 8),
        );

        expect(result.snapshotId, isNotNull);
        final snapshot =
            (await database.select(database.menuSnapshots).get()).single;
        expect(snapshot.businessDate, '2020-01-02');
        expect(snapshot.importedAt.toUtc(), DateTime.utc(2020, 1, 2, 8));
      },
    );
    test(
      'a JSON draft keeps its own source_date as the business date',
      () async {
        // 模板声明的是这份菜单的日期（decoder 校验成 ISO 日期），导入时刻
        // 与它无关：快照要落在文件声明的日期上，否则「某天的菜单」永远查不到。
        final file = File('${tempDir.path}${Platform.pathSeparator}dated.json')
          ..writeAsStringSync('''
{"source_date":"2026-09-15","venue_name":"东区食堂",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","price_minor":800}]}]}
''');
        final importer = MenuFileImporter(
          database: database,
          rawContentStore: FileMenuRawContentStore(rawDir.path),
        );
        await importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
          now: DateTime.utc(2020, 1, 2, 8),
        );

        final snapshot =
            (await database.select(database.menuSnapshots).get()).single;
        expect(snapshot.businessDate, '2026-09-15');
      },
    );
    test('rejects unsupported extension and keeps no snapshot', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}menu.pdf')
        ..writeAsStringSync('fake');
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );
      await expectLater(
        importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
        ),
        throwsA(isA<MenuFileImportException>()),
      );
      expect(await database.select(database.menuSnapshots).get(), isEmpty);
    });
    test(
      'records a failed job for an unparseable csv and keeps old snapshot',
      () async {
        // 先发布一份有效快照。
        final good = File('${tempDir.path}${Platform.pathSeparator}good.csv')
          ..writeAsStringSync('窗口,开始,结束,菜名\n一楼,10:30,13:30,饭\n');
        final importer = MenuFileImporter(
          database: database,
          rawContentStore: FileMenuRawContentStore(rawDir.path),
        );
        await importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: good.path,
        );
        // 再导入坏文件（时间格式非法）。
        final bad = File('${tempDir.path}${Platform.pathSeparator}bad.csv')
          ..writeAsStringSync('窗口,开始,结束,菜名\n一楼,8am,13:30,饭\n');
        await expectLater(
          importer.importFile(
            venueId: venueId,
            sourceId: 'source-1',
            filePath: bad.path,
          ),
          throwsA(isA<MenuFileImportException>()),
        );
        final jobs = await database.select(database.menuImportJobs).get();
        expect(jobs.last.status, 'failed');
        expect(jobs.last.parseErrorCount, greaterThanOrEqualTo(1));
        final snapshots = await database.select(database.menuSnapshots).get();
        expect(snapshots, hasLength(1));
        expect(snapshots.single.status, 'active');
      },
    );
    test('missing file is rejected before a job is created', () async {
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );
      await expectLater(
        importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: '${tempDir.path}${Platform.pathSeparator}nope.csv',
        ),
        throwsA(isA<MenuFileImportException>()),
      );
      expect(await database.select(database.menuImportJobs).get(), isEmpty);
    });

    test('非 UTF-8 文件按内容格式失败并留痕，不裸抛解码异常', () async {
      // docs/11 §3-F：`readAsStringSync()` 默认按 UTF-8 解码，而 Excel 导出的
      // 中文 CSV 通常是 GBK。解码失败原本直接抛原始 FileSystemException——
      // 既不进按类别固定的上屏文案，也不记 failed job（与「解析失败也要留痕」
      // 的约定不一致）。
      final file = File('${tempDir.path}${Platform.pathSeparator}gbk.csv')
        ..writeAsBytesSync(<int>[
          0xB4, 0xB0, 0xBF, 0xDA, 0x2C, // 窗口,
          0xBF, 0xAA, 0xCA, 0xBC, 0x2C, // 开始,
          0xBD, 0xE1, 0xCA, 0xF8, 0x2C, // 结束,
          0xB2, 0xCB, 0xC3, 0xFB, 0x0A, // 菜名（4 列表头，价格列已退役）
        ]);
      final importer = MenuFileImporter(
        database: database,
        rawContentStore: FileMenuRawContentStore(rawDir.path),
      );

      await expectLater(
        importer.importFile(
          venueId: venueId,
          sourceId: 'source-1',
          filePath: file.path,
        ),
        throwsA(
          isA<MenuFileImportException>().having(
            (error) => error.userMessage,
            'userMessage',
            '导入失败：文件内容不符合导入格式，请检查后重试。',
          ),
        ),
      );

      // 留痕与解析失败同待遇：一条 failed job，旧快照不受影响。
      final jobs = await database.select(database.menuImportJobs).get();
      expect(jobs, hasLength(1));
      expect(jobs.single.status, 'failed');
      expect(jobs.single.parseErrorCount, greaterThanOrEqualTo(1));
      expect(await database.select(database.menuSnapshots).get(), isEmpty);
    });

    test('failure kinds map to fixed user copy (raw text never shown)', () {
      // docs/11 §3-B：上屏文案按类别固定，原始 message 只进 job 记录。
      expect(
        const MenuFileImportException(
          'file not found: /data/user/0/app/menu.csv',
          kind: MenuImportFailureKind.fileUnreadable,
        ).userMessage,
        '导入失败：找不到或无法读取该文件。',
      );
      expect(
        const MenuFileImportException(
          'unsupported file extension: .pdf',
          kind: MenuImportFailureKind.unsupportedFormat,
        ).userMessage,
        '导入失败：只支持 TXT/CSV/JSON 文件。',
      );
      expect(
        const MenuFileImportException(
          'csv row 3 must have 5 cells: 一楼,10:30,13:30',
        ).userMessage,
        '导入失败：文件内容不符合导入格式，请检查后重试。',
      );
      expect(
        const MenuFileImportException(
          'venue not found: venue-9',
          kind: MenuImportFailureKind.sourceMissing,
        ).userMessage,
        '导入失败：本地食堂记录缺失，请重新选择食堂。',
      );
    });
  });
}
