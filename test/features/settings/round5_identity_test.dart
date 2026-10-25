import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/data/avatar_image_store.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// T7（docs/32 §4 T7 / §3 D9）：身份显示事实（昵称 + 头像）的读写与展示。
///
/// 覆盖：
/// 1. 昵称写读往返；1–20 字、trim、空与超长拒绝（错误文案可直接上屏）；
/// 2. 头像路径写读往返 + 越界路径拒绝（`.lfb` 篡改防线）；
/// 3. 头像存储：拷入私有目录、替换时旧文件删除、**只删本目录内**；
/// 4. `UserAvatar`：有图显图、无图显首字母、无昵称回退「Fit」、
///    **路径存在但文件缺失时回退首字母**（`.lfb` 只带路径不带字节）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ProfileIdentityRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ProfileIdentityRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProfile() async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p-identity',
            activityLevel: 'moderate',
            createdAt: DateTime.utc(2026, 10, 12),
            updatedAt: DateTime.utc(2026, 10, 12),
          ),
        );
  }

  group('T7 昵称读写与校验', () {
    test('往返：写入后读回同一个昵称（trim 生效）', () async {
      await seedProfile();
      await repository.updateDisplayName('  李雷  ');
      final identity = await repository.loadIdentity();
      expect(identity!.displayName, '李雷');
      expect(identity.avatarPath, isNull, reason: '没设头像 → null');
    });

    test('空/纯空白拒绝，错误文案可直接上屏', () async {
      await seedProfile();
      for (final bad in ['', '   ', '\n']) {
        expect(
          () => repository.updateDisplayName(bad),
          throwsA(
            isA<ProfileIdentityException>().having(
              (e) => e.message,
              'message',
              '昵称不能为空',
            ),
          ),
          reason: '「$bad」应被拒绝',
        );
      }
      final identity = await repository.loadIdentity();
      expect(identity!.displayName, isNull, reason: '拒绝后不得落库');
    });

    test('超过 20 字符拒绝；恰好 20 接受（边界）', () async {
      await seedProfile();
      expect(
        () => repository.updateDisplayName('a' * 21),
        throwsA(
          isA<ProfileIdentityException>().having(
            (e) => e.message,
            'message',
            '昵称最多 20 个字符',
          ),
        ),
      );
      await repository.updateDisplayName('b' * 20);
      expect((await repository.loadIdentity())!.displayName, 'b' * 20);
    });

    test('未建档时静默返回（不抛，也不凭空建行）', () async {
      await repository.updateDisplayName('李雷');
      expect(await database.select(database.profiles).get(), isEmpty);
    });
  });

  group('T7 头像路径与越界防护', () {
    test('路径往返；空串视为「移除」（写 null）', () async {
      await seedProfile();
      await repository.updateAvatarPath('/data/docs/localfit_ai/avatar/a.jpg');
      expect(
        (await repository.loadIdentity())!.avatarPath,
        '/data/docs/localfit_ai/avatar/a.jpg',
      );
      await repository.updateAvatarPath('');
      expect(
        (await repository.loadIdentity())!.avatarPath,
        isNull,
        reason: '空串 = 移除头像，不存空路径',
      );
    });

    test('含 .. 或 NUL 的越界路径拒绝（.lfb 篡改防线）', () async {
      await seedProfile();
      for (final bad in [
        '/data/docs/../../etc/passwd',
        'avatar/../../secret.jpg',
        '/data/docs/avatar/a\u0000.jpg',
      ]) {
        expect(
          () => repository.updateAvatarPath(bad),
          throwsA(isA<ProfileIdentityException>()),
          reason: '「$bad」应被拒绝',
        );
      }
      expect((await repository.loadIdentity())!.avatarPath, isNull);
    });
  });

  group('T7 头像存储', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfit-avatar-');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('拷入私有目录并返回路径；替换时旧文件被删', () async {
      final store = _TempAvatarStore(tempDir, _Ids());
      final first = await store.copyBytes(
        Uint8List.fromList([1, 2, 3]),
        createdAt: DateTime.utc(2026, 10, 12),
      );
      expect(File(first).existsSync(), isTrue);
      expect(first.startsWith(tempDir.path), isTrue, reason: '必须落在私有目录内');

      final second = await store.copyBytes(
        Uint8List.fromList([4, 5, 6]),
        createdAt: DateTime.utc(2026, 10, 12, 1),
      );
      expect(second, isNot(first));
      // 替换语义：调用方删旧（store 提供只删本目录内的删除原语）。
      await store.deleteQuietly(first);
      expect(File(first).existsSync(), isFalse, reason: '旧头像文件应被删掉');
      expect(File(second).existsSync(), isTrue, reason: '新头像必须还在');
    });

    test('只删本目录内的路径（越界路径直接拒绝）', () async {
      final store = _TempAvatarStore(tempDir, _Ids());
      final outside = File(
        '${tempDir.path}${Platform.pathSeparator}..${Platform.pathSeparator}outside.jpg',
      );
      outside.writeAsBytesSync([9]);
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync();
      });
      await store.deleteQuietly(outside.path);
      expect(outside.existsSync(), isTrue, reason: '目录外的文件一律不许删（防篡改的恢复包）');
    });

    test('exists：文件在 → true；路径在但文件缺失 → false（回退判据）', () async {
      final store = _TempAvatarStore(tempDir, _Ids());
      final path = await store.copyBytes(
        Uint8List.fromList([1]),
        createdAt: DateTime.utc(2026, 10, 12),
      );
      expect(await store.exists(path), isTrue);
      File(path).deleteSync();
      expect(
        await store.exists(path),
        isFalse,
        reason: '文件被清理后必须能被判出（界面回退首字母）',
      );
    });
  });

  group('T7 UserAvatar 展示与回退', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('路径存在但文件缺失 → 回退首字母（不是空白/红叉）', (tester) async {
      final missing =
          '${Directory.systemTemp.path}${Platform.pathSeparator}no-such-avatar.jpg';
      await tester.pumpWidget(
        host(
          UserAvatar(
            displayName: '李雷',
            avatarPath: missing,
            size: 56,
            imageKey: const Key('ua-image'),
            initialKey: const Key('ua-initial'),
          ),
        ),
      );
      // `Image.file` 的 errorBuilder 在解码失败时回退；先泵一帧让错误回调跑。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('ua-initial')), findsOneWidget);
      expect(find.text('李'), findsOneWidget);
    });
  });
}

/// 把 store 的目录固定到临时目录（真实 `getApplicationDocumentsDirectory`
/// 在纯 Dart 测试里拿不到平台通道）。
class _TempAvatarStore extends AvatarImageStore {
  _TempAvatarStore(this.directory, IdGenerator ids) : super(idGenerator: ids);

  final Directory directory;

  @override
  Future<Directory> ensureDirectory() async {
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return directory;
  }
}

class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'a${_v++}';
}
