import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';

/// 添加/编辑食物弹层的新契约（docs/28 §5.5，N6 / N7 / N9）。
void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    FoodRecord? editing,
    List<String> existingAliases = const [],
    required Future<String?> Function(NewFood food) onSubmit,
  }) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => NewFoodDialog.show(
                context,
                editing: editing,
                existingAliases: existingAliases,
                onSubmit: onSubmit,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, Key key) =>
      tester.widget<TextFormField>(find.byKey(key)).controller!.text;

  testWidgets('不再有「默认份量」字段，四个营养项保留（N9）', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    expect(find.text('新建食物'), findsOneWidget);
    expect(find.textContaining('默认份量'), findsNothing);
    expect(find.byKey(const Key('new-food-name')), findsOneWidget);
    expect(find.byKey(const Key('new-food-brand')), findsOneWidget);
    for (final label in const ['热量', '蛋白质', '碳水', '脂肪']) {
      expect(find.byKey(Key('new-food-每 100g $label')), findsOneWidget);
    }

    await tester.enterText(find.byKey(const Key('new-food-name')), '我的豆腐');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '116');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 蛋白质')), '12');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 碳水')), '3');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 脂肪')), '6');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    // 提交出去的表单里也不带份量（默认份量由数据层决定，弹层不再插一手）。
    expect(submitted?.name, '我的豆腐');
    expect(submitted?.kcalPer100g, 116);
    expect(submitted?.defaultServingGrams, isNull);
  });

  testWidgets('别名：可选字段存在；逗号/顿号分隔、去重后随表单提交（ADR-037）', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    // 新建态：别名栏在、为空、标注可选。
    expect(find.byKey(const Key('new-food-aliases')), findsOneWidget);
    expect(fieldText(tester, const Key('new-food-aliases')), '');

    await tester.enterText(find.byKey(const Key('new-food-name')), '西红柿');
    await tester.enterText(
      find.byKey(const Key('new-food-aliases')),
      '番茄、洋柿子,番茄',
    );
    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '20');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 蛋白质')), '1');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 碳水')), '4');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 脂肪')), '0.2');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    expect(submitted?.aliases, ['番茄', '洋柿子'], reason: '分隔符都认、重复丢掉');
  });

  testWidgets('编辑态：别名栏回显现有别名（保存即替换）', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      editing: const FoodRecord(
        id: 'f-1',
        name: '土豆',
        brand: '某牌',
        kcalPer100g: 81,
        proteinPer100g: 2,
        carbsPer100g: 18,
        fatPer100g: 0.2,
        isUserCreated: true,
        category: FoodCategory.staple,
      ),
      existingAliases: const ['马铃薯', '洋芋'],
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    expect(fieldText(tester, const Key('new-food-aliases')), '马铃薯、洋芋');
    await tester.enterText(find.byKey(const Key('new-food-aliases')), '洋芋');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();
    expect(submitted?.aliases, ['洋芋']);
  });

  testWidgets('粘贴「(品牌) 名称」自动拆进品牌栏，并留一行可见说明', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    await tester.enterText(
      find.byKey(const Key('new-food-name')),
      '(Beretta) Prosciutto Cotto火腿片',
    );
    await tester.pumpAndSettle();

    expect(
      fieldText(tester, const Key('new-food-name')),
      'Prosciutto Cotto火腿片',
    );
    expect(fieldText(tester, const Key('new-food-brand')), 'Beretta');
    final hint = tester.widget<Text>(
      find.byKey(const Key('new-food-brand-hint')),
    );
    expect(hint.data, contains('Beretta'));

    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '250');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 蛋白质')), '20');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 碳水')), '1');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 脂肪')), '18');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    expect(submitted?.name, 'Prosciutto Cotto火腿片');
    expect(submitted?.brand, 'Beretta');
  });

  testWidgets('粘贴「品牌 名称」（§5.4 词表命中）同样拆开', (tester) async {
    await openDialog(tester, onSubmit: (_) async => null);

    await tester.enterText(
      find.byKey(const Key('new-food-name')),
      '7-ELEVEN 7-11御饭团',
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester, const Key('new-food-name')), '7-11御饭团');
    expect(fieldText(tester, const Key('new-food-brand')), '7-ELEVEN');
  });

  testWidgets('逐字输入不会被当成粘贴（不擅自改用户正在打的字）', (tester) async {
    await openDialog(tester, onSubmit: (_) async => null);

    // 一个字符一个字符地打：每一步只多一个字符 ⇒ 不是粘贴，一个字都不动。
    const full = '7-ELEVEN 7-11御饭团';
    for (var i = 1; i <= full.length; i++) {
      await tester.enterText(
        find.byKey(const Key('new-food-name')),
        full.substring(0, i),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(fieldText(tester, const Key('new-food-name')), full);
    expect(fieldText(tester, const Key('new-food-brand')), isEmpty);
    expect(find.byKey(const Key('new-food-brand-hint')), findsNothing);
  });

  testWidgets('改过品牌栏之后，自动拆分的说明就撤掉', (tester) async {
    await openDialog(tester, onSubmit: (_) async => null);

    await tester.enterText(
      find.byKey(const Key('new-food-name')),
      '(Beretta) Prosciutto火腿片',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-food-brand-hint')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('new-food-brand')),
      'Beretta 官方',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-food-brand-hint')), findsNothing);
    expect(fieldText(tester, const Key('new-food-brand')), 'Beretta 官方');
  });

  testWidgets('编辑态：初值来自既有条目，标题与提交结果都是改后的那份', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      editing: const FoodRecord(
        id: 'user-1',
        name: '(Beretta) Prosciutto Cotto火腿片',
        brand: 'Beretta',
        kcalPer100g: 250,
        proteinPer100g: 20,
        carbsPer100g: 1,
        fatPer100g: 18,
        isUserCreated: true,
      ),
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    expect(find.text('编辑食物'), findsOneWidget);
    expect(
      fieldText(tester, const Key('new-food-name')),
      '(Beretta) Prosciutto Cotto火腿片',
    );
    expect(fieldText(tester, const Key('new-food-brand')), 'Beretta');
    // 整数不拖小数点。
    expect(fieldText(tester, const Key('new-food-每 100g 热量')), '250');
    expect(fieldText(tester, const Key('new-food-每 100g 脂肪')), '18');

    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '260');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    expect(submitted?.kcalPer100g, 260);
    // 品牌与名称原样带出（弹层不替调用点决定存哪一条：身份在调用点的 id 上）。
    expect(submitted?.name, '(Beretta) Prosciutto Cotto火腿片');
    expect(submitted?.brand, 'Beretta');
  });

  testWidgets('没有「过敏原与饮食标签」整块（需求 50）', (tester) async {
    await openDialog(tester, onSubmit: (_) async => null);

    // 两组标签的小标题与整块的标题一个都不许在。
    expect(find.textContaining('过敏原'), findsNothing);
    expect(find.textContaining('饮食标签'), findsNothing);
    expect(find.text('适用饮食标签'), findsNothing);
    expect(find.text('包含过敏原'), findsNothing);
    // 「我已确认本地事实」那个开关也不在。
    expect(find.text('我已确认本地事实'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    // 反面：六个字段与保存钮仍在（删的是那一块，不是整个表单）。
    expect(find.byKey(const Key('new-food-name')), findsOneWidget);
    expect(find.byKey(const Key('new-food-brand')), findsOneWidget);
    for (final label in const ['热量', '蛋白质', '碳水', '脂肪']) {
      expect(find.byKey(Key('new-food-每 100g $label')), findsOneWidget);
    }
    expect(find.byKey(const Key('new-food-save')), findsOneWidget);
  });

  testWidgets('保存失败不关窗：错误画在弹层里，输入原样保留（N7）', (tester) async {
    var attempts = 0;
    await openDialog(
      tester,
      onSubmit: (food) async {
        attempts++;
        return attempts == 1 ? '内置食物不能修改或删除。' : null;
      },
    );

    await tester.enterText(find.byKey(const Key('new-food-name')), '我的豆腐');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '116');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 蛋白质')), '12');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 碳水')), '3');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 脂肪')), '6');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    // 弹层没关、错误在弹层里、用户填的东西一个字没丢。
    expect(find.text('新建食物'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('new-food-sheet-error'))).data,
      '内置食物不能修改或删除。',
    );
    expect(fieldText(tester, const Key('new-food-name')), '我的豆腐');
    expect(fieldText(tester, const Key('new-food-每 100g 热量')), '116');

    // 再点一次成功 ⇒ 关窗。
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();
    expect(find.text('新建食物'), findsNothing);
    expect(attempts, 2);
  });

  testWidgets('校验失败留在弹层里（不 pop、不丢输入）', (tester) async {
    var attempts = 0;
    await openDialog(
      tester,
      onSubmit: (_) async {
        attempts++;
        return null;
      },
    );

    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();
    expect(find.text('请填写食物名称'), findsOneWidget);
    expect(attempts, 0);
  });

  testWidgets('种类是枚举下拉：默认「其他」，选「乳制品」随表单提交（docs/31 S5 需求 53）', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    expect(find.byKey(const Key('new-food-category')), findsOneWidget);
    // 默认档是「其他食物」（枚举 other 的中文标签），不是自由文本框。
    expect(find.text('其他食物'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-food-name')), '我的酸奶');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '62');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 蛋白质')), '3.2');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 碳水')), '4.8');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 脂肪')), '3.1');
    await tester.tap(find.byKey(const Key('new-food-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乳制品').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    expect(submitted?.name, '我的酸奶');
    expect(submitted?.category, FoodCategory.dairy);
  });

  testWidgets('编辑态回显旧种类（没种类的旧数据落「其他」）', (tester) async {
    NewFood? submitted;
    await openDialog(
      tester,
      editing: const FoodRecord(
        id: 'user-1',
        name: '我的酸奶',
        kcalPer100g: 62,
        proteinPer100g: 3.2,
        carbsPer100g: 4.8,
        fatPer100g: 3.1,
        isUserCreated: true,
        category: FoodCategory.snack,
      ),
      onSubmit: (food) async {
        submitted = food;
        return null;
      },
    );

    expect(find.text('零食甜点'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();
    expect(submitted?.category, FoodCategory.snack);
  });
}
