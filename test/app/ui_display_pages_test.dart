import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_workbench/presentation/ai_workbench_page.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_card.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

void _viewport(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  double keyboard = 0,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void _readable(WidgetTester tester, Finder finder, {int? maxLines}) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: paragraph.text.toPlainText(),
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  expect(boxes, isNotEmpty);
  if (maxLines != null) {
    expect(
      boxes.map((box) => box.top).toSet().length,
      lessThanOrEqualTo(maxLines),
      reason: paragraph.text.toPlainText(),
    );
  }
}

Future<void> _openEditor(WidgetTester tester, Widget editor) async {
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                AppSheet.showCustom<void>(context, builder: (_) => editor),
            child: const Text('打开编辑'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑'));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase database;
  late FoodRepository foods;
  final now = DateTime.utc(2026, 9, 12, 10);
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
  });
  tearDown(() => database.close());

  testWidgets(
    'populated profile health tiles do not break a four-digit BMR into stacked digits',
    (tester) async {
      _viewport(tester, const Size(390, 1000), scale: 2);
      await database
          .into(database.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'profile',
              birthYear: const Value(1995),
              biologicalSex: const Value('female'),
              heightCm: const Value(165),
              activityLevel: 'moderate',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.measurements)
          .insert(
            MeasurementsCompanion.insert(
              id: 'weight',
              profileId: 'profile',
              localDate: '2026-09-12',
              weightKg: 62,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await tester.pumpWidget(
        _app(
          SettingsPage(
            profileOverviewLoader: LoadProfileOverview(
              database: database,
              clock: FixedAppClock(now),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-health-metrics')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // docs/27 R1 规格回归设计稿：值是纯数字（大字），单位是独立小字。
      _readable(tester, find.text('1,335'), maxLines: 1);
      _readable(tester, find.text('kcal/天'), maxLines: 1);
      _readable(tester, find.text('基础代谢率'), maxLines: 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'AI protocol options fit a 320dp form at $scale without horizontal overflow',
      (tester) async {
        _viewport(tester, const Size(320, 1100), scale: scale);
        await tester.pumpWidget(
          _app(SettingsPage(settingsStore: _SettingsStore())),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('settings-ai-model-row')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-ai-model-row')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('ai-protocol')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final responses = find.text('Responses（OpenAI /v1/responses）').last;
        await tester.ensureVisible(responses);
        await tester.tap(responses);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('ai-config-sheet-save')).hitTestable(),
          findsOneWidget,
        );
      },
    );
  }

  // 食谱编辑器用例随食谱整族下线删除（docs/28 §6.1）。
  testWidgets(
    'meal editor scrolls all fields above a keyboard on a short screen',
    (tester) async {
      _viewport(tester, const Size(390, 568), keyboard: 240);
      await _openEditor(
        tester,
        MealEditorDialog(foodRepository: foods, localDate: '2026-09-12'),
      );
      expect(tester.takeException(), isNull);
      final save = find.byKey(const Key('meal-save'));
      final rect = tester.getRect(save);
      expect(rect.bottom, lessThanOrEqualTo(328));
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pump();
      expect(find.textContaining('请至少添加一种食物'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 食谱编辑器用例随食谱整族下线删除（docs/28 §6.1）。
  testWidgets(
    'meal-x populated editor can scroll to a grams field and save the change on a short keyboard screen',
    (tester) async {
      _viewport(tester, const Size(390, 568), keyboard: 240);
      final food = FoodRecord(
        id: 'food-1',
        name: '鸡胸肉',
        kcalPer100g: 165,
        proteinPer100g: 31,
        carbsPer100g: 0,
        fatPer100g: 3.6,
        isUserCreated: false,
      );
      final item = MealItemRecord(
        id: 'item-1',
        foodId: food.id,
        foodName: food.name,
        grams: 100,
        nutrition: NutritionValues(
          kcal: 165,
          proteinGrams: 31,
          carbsGrams: 0,
          fatGrams: 3.6,
        ),
        createdAt: now,
        updatedAt: now,
      );
      MealDraft? savedMeal;
      final editor = MealEditorDialog(
        foodRepository: foods,
        localDate: '2026-09-12',
        initialMeal: MealRecord(
          id: 'meal-1',
          localDate: '2026-09-12',
          slot: MealSlot.lunch,
          eatenAt: now,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
          items: [item],
        ),
      );
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await AppSheet.showCustom<Object?>(
                    context,
                    builder: (_) => editor,
                  );
                  savedMeal = result as MealDraft?;
                },
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('meal-grams-item-1')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const Key('meal-grams-item-1')), '150');
      final save = find.byKey(const Key('meal-save'));
      await tester.ensureVisible(save);
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(savedMeal?.items.single.grams, 150);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('dish nutrients and add action fit narrow cards at $scale', (
      tester,
    ) async {
      _viewport(tester, const Size(320, 1000), scale: scale);
      var calls = 0;
      final dish = DishRecord(
        id: 'dish',
        name: '鸡胸肉蔬菜午餐',
        mealSlot: 'lunch',
        kcal: 650,
        proteinG: 35,
        carbsG: 65,
        fatG: 28,
        source: 'ai_estimate',
        createdAt: now,
        updatedAt: now,
        servingWindow: '11:30-13:30',
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DishCard(
                  dish: dish,
                  index: 1,
                  onAddToMeal: (_) async => calls++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('cta-add-meal-1')));
      await tester.pumpAndSettle();
      _readable(tester, find.text('加入午餐'), maxLines: 1);
      await tester.tap(find.byKey(const Key('cta-add-meal-1')));
      expect(calls, 1);
    });
  }

  testWidgets(
    'achievement tiles keep their full names at large font instead of ellipsizing',
    (tester) async {
      _viewport(tester, const Size(360, 900), scale: 2);
      await tester.pumpWidget(
        _app(SettingsPage(settingsStore: _SettingsStore())),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-achievements')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      for (final label in const ['7天连续打卡', '营养达人', '运动健将', '健康饮食']) {
        _readable(tester, find.text(label));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large-font AI task hub displays complete task names instead of ellipses',
    (tester) async {
      _viewport(tester, const Size(320, 1000), scale: 2);
      // docs/32 §4 T6c：画廊改渲染 `aiStarters` 的六张卡（不再注入 tasks）。
      const titles = ['解析学校菜单', '生成今日吃法', '分析菜品营养'];
      await tester.pumpWidget(_app(AiWorkbenchPage()));
      await tester.pumpAndSettle();
      for (final title in titles) {
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        _readable(tester, find.text(title));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chat edit proposal actions stay readable and clickable in a narrow bubble',
    (tester) async {
      _viewport(tester, const Size(320, 800), scale: 2);
      final turn = parseChatEditTurn(
        jsonEncode({
          'reply': '准备记录',
          'edits': [
            {
              'action': 'water.add',
              'args': {'amountMl': 300},
            },
          ],
        }),
        ChatEditCommandRegistry(),
      )!;
      var apply = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 250,
                child: ChatEditCard(
                  index: 0,
                  message: ConversationMessage(
                    id: 'edit',
                    role: ConversationRole.assistant,
                    text: '准备记录',
                    createdAt: now,
                    kind: ConversationMessageKind.editProposal,
                    editTurn: turn,
                  ),
                  onApply: () => apply++,
                  onApplyRows: (_) {},
                  onDismiss: () {},
                  onApplySuggestion: (_) {},
                  onRepair: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      _readable(tester, find.text('全部应用'), maxLines: 1);
      await tester.tap(find.byKey(const Key('chat-edit-apply-0')));
      expect(apply, 1);
    },
  );
}

final class _SettingsStore implements AiProviderSettingsStore {
  @override
  Future<void> clearApiKey() async {}
  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;
  @override
  Future<AiProviderSettings> load() async =>
      const AiProviderSettings(configuration: null, hasApiKey: false);
  @override
  Future<void> save(AiProviderSettingsInput input) async {}
}
