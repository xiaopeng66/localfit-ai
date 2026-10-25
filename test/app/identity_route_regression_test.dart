import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/features/settings/presentation/profile_edit_page.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

final _now = DateTime(2026, 10, 13, 9);
const _pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late ProfileIdentityRepository identity;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    identity = ProfileIdentityRepository(database: database);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'identity-profile',
            activityLevel: 'moderate',
            displayName: const Value('李雷'),
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await database.close();
  });

  LocalFitApp app(String route) => LocalFitApp(
    initialLocation: route,
    profileIdentityRepository: identity,
    mealRepository: MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(_now.toUtc()),
    ),
    conversationService: _OfflineAi(),
    now: _now,
  );

  testWidgets('stored identity reaches Today and AI on first visit', (
    tester,
  ) async {
    const missingAvatar = 'E:/AI/Zcode/tmp/absent-identity-route-avatar.png';
    await identity.updateAvatarPath(missingAvatar);
    await _mount(tester, app(AppRoutes.dashboard));
    try {
      expect(find.text('早安，李雷'), findsOneWidget);
      _expectAvatar(
        tester,
        'dashboard-avatar-initial',
        name: '李雷',
        path: missingAvatar,
      );
      await _tap(tester, 'nav-ai-workbench');
      _expectAvatar(
        tester,
        'ai-chat-avatar-initial',
        name: '李雷',
        path: missingAvatar,
      );
      await _tap(tester, 'ai-chat-user-avatar');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('李雷'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _drain(tester);
    }
  });

  testWidgets(
    'identity updates keep mounted AI draft and update all three branches',
    (tester) async {
      await _mount(tester, app(AppRoutes.aiChat));
      try {
        final state = tester.state(find.byType(AiConversationPage));
        await tester.enterText(
          find.byKey(const Key('ai-chat-text-input')),
          '尚未发送的内容',
        );
        await _tap(tester, 'nav-dashboard');
        await _tap(tester, 'nav-settings');
        await identity.updateDisplayName('韩梅梅');
        await _frames(tester);
        expect((await identity.loadIdentity())?.displayName, '韩梅梅');
        expect(find.text('韩梅梅'), findsOneWidget);
        await _tap(tester, 'nav-dashboard');
        expect(find.text('早安，韩梅梅'), findsOneWidget);
        await _tap(tester, 'nav-ai-workbench');
        expect(tester.state(find.byType(AiConversationPage)), same(state));
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('ai-chat-text-input')))
              .controller!
              .text,
          '尚未发送的内容',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('ai-chat-avatar-initial')))
              .data,
          '韩',
        );

        await identity.clearDisplayName();
        await _frames(tester);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('ai-chat-avatar-initial')))
              .data,
          'Fit',
        );
        await _tap(tester, 'nav-settings');
        expect(find.text('韩梅梅'), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('settings-avatar-initial')))
              .data,
          'Fit',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _drain(tester);
      }
    },
  );

  testWidgets(
    'profile removal refreshes mounted identity without an overview loader',
    (tester) async {
      await _mount(tester, app(AppRoutes.settings));
      try {
        expect(find.text('李雷'), findsOneWidget);
        await database.delete(database.profiles).go();
        await _frames(tester);
        expect(find.text('李雷'), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('settings-avatar-initial')))
              .data,
          'Fit',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _drain(tester);
      }
    },
  );

  testWidgets('unconfigured avatar has no advertised change action', (
    tester,
  ) async {
    await _mount(
      tester,
      const LocalFitApp(initialLocation: AppRoutes.settings),
    );
    try {
      final avatar = tester.widget<GestureDetector>(
        find.byKey(const Key('settings-avatar')),
      );
      expect(avatar.onTap, isNull);
      final semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const Key('settings-avatar')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.button, isFalse);
      expect(semantics.properties.label, isNot('更换头像'));
    } finally {
      await _drain(tester);
    }
  });

  testWidgets(
    'real routed avatar selection copies bytes replaces old and cancellation keeps new',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'localfit-avatar-routing-',
      );
      final source = File(
        '${directory.path}${Platform.pathSeparator}gallery.png',
      );
      source.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      final privateDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}localfit_ai${Platform.pathSeparator}avatar',
      )..createSync(recursive: true);
      final oldFile = File(
        '${privateDirectory.path}${Platform.pathSeparator}old.png',
      );
      source.copySync(oldFile.path);
      await identity.updateAvatarPath(oldFile.path);
      var cancel = false;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return directory.path;
            }
            throw StateError('Unexpected path request: ${call.method}');
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pickerChannel, (call) async {
            calls.add(call);
            if (call.method != 'pickImage') {
              throw StateError('Unexpected picker request');
            }
            return cancel ? null : source.path;
          });
      await _mount(tester, app(AppRoutes.settings));
      try {
        // 2026-10-16（S6）：头像改在「编辑资料」页——从设置页身份卡进本页，
        // 再点本页的头像块（`profile-avatar`）。
        await _tap(tester, 'cta-edit-profile');
        await _tap(tester, 'profile-avatar');
        for (var index = 0; index < 100; index++) {
          if ((await identity.loadIdentity())?.avatarPath != oldFile.path &&
              !oldFile.existsSync()) {
            break;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await _frames(tester);
        expect(
          calls,
          hasLength(1),
          reason: 'The app route must invoke the installed image picker.',
        );
        expect(calls.single.arguments, containsPair('source', 1));
        expect(calls.single.arguments, containsPair('maxWidth', 512.0));
        expect(calls.single.arguments, containsPair('maxHeight', 512.0));
        expect(calls.single.arguments, containsPair('imageQuality', 90));
        final saved = (await identity.loadIdentity())!.avatarPath!;
        expect(saved, isNot(oldFile.path));
        expect(saved, isNot(source.path));
        expect(
          saved.startsWith('${privateDirectory.path}${Platform.pathSeparator}'),
          isTrue,
        );
        expect(File(saved).readAsBytesSync(), source.readAsBytesSync());
        expect(oldFile.existsSync(), isFalse);
        expect(source.existsSync(), isTrue);
        // 本页头像也要换成新图（等它读回库值再断言——写库与重建之间有
        // 一帧的窗口，`_frames` 不保证覆盖），再回设置页核对身份卡。
        for (var index = 0; index < 50; index++) {
          final image = tester.widget<Image>(
            find.byKey(const Key('profile-avatar-image')),
          );
          if ((image.image as FileImage).file.path == saved) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        _expectImagePath(tester, 'profile-avatar-image', saved);
        await _tap(tester, 'profile-edit-close');
        _expectImagePath(tester, 'settings-avatar-image', saved);
        await _tap(tester, 'nav-dashboard');
        _expectImagePath(tester, 'dashboard-avatar-image', saved);
        await _tap(tester, 'nav-ai-workbench');
        _expectImagePath(tester, 'ai-chat-avatar-image', saved);
        await _tap(tester, 'nav-settings');
        cancel = true;
        await _tap(tester, 'cta-edit-profile');
        await _tap(tester, 'profile-avatar');
        expect(calls, hasLength(2));
        expect((await identity.loadIdentity())!.avatarPath, saved);
        expect(File(saved).existsSync(), isTrue);
        expect(
          privateDirectory.listSync().whereType<File>().map(
            (file) => file.path,
          ),
          [saved],
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _drain(tester);
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        for (
          var attempt = 0;
          attempt < 50 && directory.existsSync();
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          try {
            directory.deleteSync(recursive: true);
          } on FileSystemException {
            if (attempt == 49) rethrow;
          }
        }
      }
    },
  );

  testWidgets(
    'nickname save owns its input through sheet exit and updates routed pages',
    (tester) async {
      await _mount(tester, app(AppRoutes.settings));
      try {
        // 2026-10-16（S6）：昵称改在「编辑资料」页，保存走页面自己的
        // 确认弹层（与其余资料字段同一条通路）。
        await _tap(tester, 'cta-edit-profile');
        await tester.enterText(
          find.byKey(const Key('profile-display-name')),
          '韩梅梅',
        );
        await tester.tap(find.text('保存'));
        await _frames(tester);
        await tester.tap(find.text('确认'));
        await _frames(tester);
        // 保存成功后页面自己关闭（`onClose` 的两条出口之一）。
        expect(find.byType(ProfileEditPage), findsNothing);
        expect(tester.takeException(), isNull);
        expect((await identity.loadIdentity())?.displayName, '韩梅梅');
        expect(find.text('韩梅梅'), findsOneWidget);
        await _tap(tester, 'nav-dashboard');
        expect(find.text('早安，韩梅梅'), findsOneWidget);
        await _tap(tester, 'nav-ai-workbench');
        expect(
          tester
              .widget<Text>(find.byKey(const Key('ai-chat-avatar-initial')))
              .data,
          '韩',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _drain(tester);
      }
    },
  );
}

Future<void> _mount(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(900, 1900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 24; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await _frames(tester);
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void _expectAvatar(
  WidgetTester tester,
  String initialKey, {
  required String name,
  required String path,
}) {
  final avatar = tester.widget<UserAvatar>(
    find.ancestor(
      of: find.byKey(Key(initialKey)),
      matching: find.byType(UserAvatar),
    ),
  );
  expect(avatar.displayName, name);
  expect(avatar.avatarPath, path);
  expect(
    tester.widget<Text>(find.byKey(Key(initialKey))).data,
    name.characters.first,
  );
}

void _expectImagePath(WidgetTester tester, String key, String path) {
  final image = tester.widget<Image>(find.byKey(Key(key)));
  expect((image.image as FileImage).file.path, path);
}

class _OfflineAi implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) => const Stream<String>.empty();
}
