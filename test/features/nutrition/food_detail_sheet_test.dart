import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/app/design/widgets/macro_bar.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_detail_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

/// 食物详情弹层的**新契约**（docs/28 §5.2 N9/N10；docs/29 §P8a 需求 28）。
///
/// 用户 2026-10-04 原话：「这里边不需要有份量（输入弹窗也不需要填写份量），
/// 营养修订也不需要，来源证据也不需要」+「这里需要的是食物名称，以及营养的
/// 图表，要可视化的图形风格界面」；2026-10-05 又点了这一屏：「详情抽屉与卡片
/// 一致；圆环小一点（三个营养同行）；单位注意；只要克数不要百分比；0g 也要写」。
/// 所以这一组测试分两半：
///
/// 1. **删掉的三节真的不渲染**——不是「Key 换了」，而是把带份量/修订/证据的
///    完整 [FoodDetail] 喂进去，屏上也不能出现它们（数据仍在域层，只是不再
///    上这一屏）；
/// 2. **留下的图形化营养**——56dp 环（0–1000 刻度）+ **三行**宏量块（每行
///    彩点 + 名称 + 克数；缺值与 0 都写 `0g`，百分比行已整行删除）。
///
/// 2026-10-08（docs/30 §2 D2 需求 1）把第 2 条从「三格同行」改成「三行竖排 +
/// **三行块中心 = 环心**」：用户原话「点击后的卡片才显示详细的三营养数据，三行
/// 数据的所在行需要与圆环的圆心上下对齐」。所以几何断言也换了对象——量的是
/// `MacroDotRows` 的中心与**中间那一行**（碳水）的中心，而不是「三格在环右边
/// 且纵向重叠」。`kcal/100g` 口径标签也从环列移到了整块下方：它原先住在环列
/// 里，`center` 居中的是**整列**（环 + 2 + 标签 = 72dp）⇒ 环心被推偏 8dp，
/// 「环心 = 三行块中心」这条对齐根本不可能成立。
void main() {
  const builtIn = FoodLibraryItem(
    id: 'off:1001',
    name: '蒸米饭',
    source: 'catalog',
    state: 'verified',
    canJoinPlan: true,
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
  );

  const userCreated = FoodLibraryItem(
    id: 'user:1',
    name: '自制鸡肉沙拉',
    source: 'main',
    state: 'user_created',
    canJoinPlan: true,
    isUserCreated: true,
    kcalPer100g: 120,
    proteinPer100g: 12,
    carbsPer100g: 6,
    fatPer100g: 5,
  );

  FoodDetail detail({
    String state = 'verified',
    bool isUserCreated = false,
    // 裁决 ①（2026-10-15）后 canJoinPlan 是显式字段（规则逐来源给）：
    // 夹具默认 true；只有断言「不完整」那条才显式 false。
    bool canJoinPlan = true,
    double kcal = 116,
    double protein = 2.6,
    double carbs = 25.9,
    double fat = 0.3,
    // 三节已删的内容仍然塞进读模型：证明的是「界面上不再渲染」，
    // 而不是「构造器里碰巧没有这些东西」。
    List<FoodPortionOption> portions = const [],
    FoodRevisionRecord? revision,
    FoodEvidenceRecord? evidence,
    double? defaultServingGrams,
  }) => FoodDetail(
    foodId: 'off:1001',
    name: '蒸米饭',
    state: state,
    source: 'openfoodfacts',
    licenseStatus: 'allowed',
    isUserCreated: isUserCreated,
    canJoinPlan: canJoinPlan,
    kcalPer100g: kcal,
    proteinPer100g: protein,
    carbsPer100g: carbs,
    fatPer100g: fat,
    defaultServingGrams: defaultServingGrams,
    portions: portions,
    latestRevision: revision,
    evidence: evidence,
  );

  const fullDetailWithDeletedSections = FoodPortionOption(
    id: 'off:1001:portion:1',
    name: '一碗',
    grams: 150,
    locale: 'zh-CN',
    source: 'openfoodfacts',
  );

  Future<void> pumpSheet(
    WidgetTester tester,
    Future<FoodDetail?> Function() load, {
    FoodLibraryItem item = builtIn,
    Future<void> Function()? onEdit,
    Future<void> Function()? onDelete,
    Size size = const Size(900, 1600),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodDetailSheet(
            item: item,
            load: load,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('三行宏量块的中心与环心同高（docs/30 §2 D2 需求 1 的对齐）', (tester) async {
    await pumpSheet(tester, () async => detail(), size: const Size(360, 800));

    final ring = tester.getRect(find.byType(LfFoodKcalRing));
    final rows = tester.getRect(find.byType(MacroDotRows));
    expect(rows.left, greaterThan(ring.right), reason: '三行块在环右边');
    // 对齐的对象是**块中心**，不是「两者纵向重叠」：块 67dp 比环 56dp 高，
    // 重叠在旧版（三格一行）与新版（三行竖排）里都成立，量不出对齐。
    expect(
      rows.center.dy,
      closeTo(ring.center.dy, 0.5),
      reason: '三行块中心必须落在环心上（旧版三格一行时这里差 8dp）',
    );
    // 三行块的中心行 = 中间那一行（碳水）；用户说的是「三行数据的所在行」
    // 与环心对齐，所以这一行的中心也必须落在环心上，而不是「块大致居中」。
    final carbsRow = tester.getRect(
      find.ancestor(of: find.text('碳水'), matching: find.byType(Row)).first,
    );
    expect(
      carbsRow.center.dy,
      closeTo(ring.center.dy, 0.5),
      reason: '中间那一行（碳水）的中心就是环心',
    );
    // 三行块的 1.0× 口径高（行高 17 × 3 + 行距 8 × 2 = 67dp）：对齐算式依赖
    // 它，改行高/行距时这条会先红，不会悄悄把环心推偏。
    expect(rows.height, closeTo(MacroDotRows.blockHeight, 0.5));
    // 环仍是 56dp 大档（原 88dp）。
    expect(ring.width, LfDimens.foodKcalRingLargeSize);
  });

  testWidgets('2.0× 大字号：三行仍与环心对齐，且不溢出、不折行、不被裁掉', (tester) async {
    // 行高从定高 `SizedBox(height: 17)` 改成 `minHeight: 17` 就是为了这一条：
    // 定高在 2.0× 下把 33.6dp 的文字塞进 17dp（拦腰截断），而 `center` 对齐
    // 按实际高度算 —— 块变高，环跟着下推，环心仍在块中心。
    await pumpSheet(tester, () async => detail(), textScale: 2);

    final ring = tester.getRect(find.byType(LfFoodKcalRing));
    final rows = tester.getRect(find.byType(MacroDotRows));
    expect(rows.left, greaterThan(ring.right), reason: '2.0× 也必须同行');
    expect(
      rows.center.dy,
      closeTo(ring.center.dy, 0.5),
      reason: '2.0× 下块更高（3 × 33.6 + 16 = 116.8dp），环心仍须在块中心',
    );
    // 文字真的画得下：每行的高度至少容得下 2.0× 的 caption 行高
    // （12px × 2 × 1.4 = 33.6dp）。被裁掉时 `getRect` 报的是**布局**高度，
    // 所以这里比的是「行高 ≥ 文字需要的行高」，而不是「有没有报 overflow」。
    final carbsRow = tester.getRect(
      find.ancestor(of: find.text('碳水'), matching: find.byType(Row)).first,
    );
    expect(
      carbsRow.height,
      greaterThanOrEqualTo(LfText.caption.fontSize! * 2 * 1.4 - 0.5),
      reason: '2.0× 下碳水那一行的高度必须容得下整行文字（定高会在这里红）',
    );
  });

  testWidgets('留下的四件：名称、品牌/徽标、56dp 环、三行宏量（只有克数，没有百分比）', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(
        defaultServingGrams: 150,
        portions: const [fullDetailWithDeletedSections],
        revision: FoodRevisionRecord(
          id: 'off:1001:rev:2',
          revisionNumber: 2,
          qualityStatus: 'ok',
          kcalPer100g: 118,
          proteinGPer100g: 2.7,
          carbsGPer100g: 26,
          fatGPer100g: 0.3,
          validFrom: DateTime.utc(2026, 9, 16, 1),
        ),
        evidence: FoodEvidenceRecord(
          id: 'off:1001:ev',
          sourceId: 'openfoodfacts',
          license: 'odbl-1.0',
          attribution: 'Open Food Facts, ODbL',
          retrievedAt: DateTime.utc(2026, 9, 15, 20, 45, 7),
          transformVersion: '2.0-1j',
          qualityStatus: 'ok',
          recordHash: '0123456789abcdef${'0' * 48}',
        ),
      ),
    );

    expect(find.text('蒸米饭'), findsOneWidget);
    // 内置条目（随包种子/导入目录）在详情里也是「内置」。
    expect(find.text('内置'), findsOneWidget);
    expect(find.text('自建'), findsNothing);

    // 图形化热量：大环档（56dp + 6dp），刻度 0–1000 ⇒ 116/1000 = 12%。
    expect(find.byKey(const Key('food-detail-ring-kcal')), findsOneWidget);
    final ring = tester.widget<LfFoodKcalRing>(find.byType(LfFoodKcalRing));
    expect(ring.size, LfDimens.foodKcalRingLargeSize);
    expect(ring.stroke, LfDimens.foodKcalRingLargeStroke);
    expect(ring.kcalPer100g, 116);
    // 环的口径独立成行（移出了环那一列，否则 `center` 居中的是整列、环心被推偏）：
    // 有热量时讲满刻度，与列表头同一句话、同一个常量（改刻度时两处一起变）。
    final label = find.byKey(const Key('food-detail-ring-label'));
    expect(label, findsOneWidget);
    expect(
      find.descendant(of: label, matching: find.textContaining('kcal/100g')),
      findsOneWidget,
      reason: '单位要写全（需求 22/28）',
    );
    expect(find.text('每 100g'), findsNothing);
    expect(
      tester.getRect(label).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(MacroDotRows)).bottom),
      reason: '口径行在环 + 三行整块的下方（旧版住在环列里，就是把环心推偏 8dp 的那一件）',
    );
    expect(
      tester.getSemantics(find.byType(LfFoodKcalRing)).label,
      '每 100 克 116 千卡，约为能量密度满刻度的 12%',
      reason: '刻度是能量密度 0–1000（常量单源），不是「相对每日目标」',
    );

    // 只有克数，没有百分比（需求 28 整行删除的那三格）；三行各占一行。
    expect(find.byType(MacroDotRows), findsOneWidget);
    expect(find.text('蛋白质'), findsOneWidget);
    expect(find.text('碳水'), findsOneWidget);
    expect(find.text('脂肪'), findsOneWidget);
    expect(find.text('2.6g'), findsOneWidget);
    expect(find.text('25.9g'), findsOneWidget);
    expect(find.text('0.3g'), findsOneWidget);
    // 三行竖排（不是三格一行）：名称文字自带行，克数贴右端。
    final protein = tester.getRect(find.text('蛋白质'));
    final carbs = tester.getRect(find.text('碳水'));
    final fat = tester.getRect(find.text('脂肪'));
    expect(protein.center.dy, lessThan(carbs.center.dy), reason: '蛋白质在碳水上面');
    expect(carbs.center.dy, lessThan(fat.center.dy), reason: '碳水在脂肪上面');
    for (final percent in const ['蛋白质 9%', '碳水 89%', '脂肪 2%']) {
      expect(find.text(percent), findsNothing, reason: '$percent 是已删的占比行');
    }
    expect(find.byType(MacroRatioRow), findsNothing);
  });

  testWidgets('删掉的三节一个都不再渲染（份量 / 营养修订 / 来源证据）', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(
        defaultServingGrams: 150,
        portions: const [fullDetailWithDeletedSections],
        revision: const FoodRevisionRecord(
          id: 'off:1001:rev:2',
          revisionNumber: 2,
          qualityStatus: 'ok',
        ),
        evidence: FoodEvidenceRecord(
          id: 'off:1001:ev',
          sourceId: 'openfoodfacts',
          license: 'odbl-1.0',
          retrievedAt: DateTime.utc(2026, 9, 15, 20, 45, 7),
          transformVersion: '2.0-1j',
          qualityStatus: 'ok',
          recordHash: '0123456789abcdef${'0' * 48}',
        ),
      ),
    );

    // 旧的三节在弹层里连标题都不在（数据在，但这一屏不再展示）。
    expect(find.textContaining('份量'), findsNothing);
    expect(find.textContaining('修订'), findsNothing);
    expect(find.textContaining('来源证据'), findsNothing);
    expect(find.textContaining('odbl-1.0'), findsNothing);
    expect(find.textContaining('记录哈希'), findsNothing);
    expect(find.textContaining('一碗'), findsNothing);
  });

  testWidgets('名称按 §5.4 清洗：品牌前缀挪到品牌行', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(),
      item: const FoodLibraryItem(
        id: 'seed:1',
        name: '7-ELEVEN 7-11御饭团',
        source: 'main',
        state: 'verified',
        canJoinPlan: true,
        kcalPer100g: 200,
        proteinPer100g: 5,
        carbsPer100g: 38,
        fatPer100g: 3,
      ),
    );

    // 前缀不再出现在标题里（连字符按既有规则折叠成空格），品牌单独一行。
    expect(find.text('7 11御饭团'), findsOneWidget);
    expect(find.byKey(const Key('food-detail-brand')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('food-detail-brand'))).data,
      '7-ELEVEN',
    );
  });

  testWidgets('数据层的品牌列优先于名称里的前缀', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(),
      item: const FoodLibraryItem(
        id: 'seed:2',
        name: '(Beretta) Prosciutto Cotto火腿片',
        source: 'main',
        state: 'verified',
        canJoinPlan: true,
        brand: 'Beretta 官方',
        kcalPer100g: 250,
        proteinPer100g: 20,
        carbsPer100g: 1,
        fatPer100g: 18,
      ),
    );

    expect(find.text('Prosciutto Cotto火腿片'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('food-detail-brand'))).data,
      'Beretta 官方',
    );
  });

  testWidgets('热量缺失（主表 0）按缺失处理：环里 —、口径写「无热量数据」', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(kcal: 0, protein: 0, carbs: 0, fat: 0),
    );

    expect(
      tester.widget<LfFoodKcalRing>(find.byType(LfFoodKcalRing)).kcalPer100g,
      isNull,
    );
    expect(find.text('—'), findsOneWidget);
    // 口径行两档二选一：没有热量时不讲满刻度（环里那个 `—` 需要一句解释），
    // 如实写「无热量数据」；有热量时才讲 0–1000 刻度。
    expect(find.text('无热量数据'), findsOneWidget);
    expect(find.text('kcal/100g'), findsNothing);
    expect(find.text('每 100g'), findsNothing);
    // 需求 28（D14）：三行宏量照画，缺值与 0 都写 `0g`——「三行永不缺位」是
    // 显示约定；「这一条没有宏量数据」由下面那句「营养不完整」说，不靠少画行。
    expect(find.byType(MacroDotRows), findsOneWidget);
    expect(find.text('蛋白质'), findsOneWidget);
    expect(find.text('0g'), findsNWidgets(3), reason: '三行都写 0g');
    expect(
      tester.getSemantics(find.byType(LfFoodKcalRing)).label,
      '每 100 克热量未知',
    );
  });

  testWidgets('缺项与 0 都写 0g：三行恒占位，不跳过缺失项', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(kcal: 100, protein: 10, carbs: 10, fat: 0),
    );

    expect(find.text('10g'), findsNWidgets(2));
    expect(find.text('0g'), findsOneWidget, reason: '0 也要上屏，不跳过');
    // 三行都在（缺项不跳过 ⇒ 行数恒定，三行的 y 坐标才会与环心对齐）。
    expect(find.text('蛋白质'), findsOneWidget);
    expect(find.text('碳水'), findsOneWidget);
    expect(find.text('脂肪'), findsOneWidget);
    // 百分比行已整行删除（需求 28）。
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('不可加入确认计划：理由写在明面上', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(state: 'incomplete', canJoinPlan: false),
    );

    expect(find.text('营养不完整，暂不可加入确认计划'), findsOneWidget);
  });

  testWidgets('自建食物（user_created + 四值齐）：不显示「营养不完整」', (tester) async {
    // 2026-10-15 用户批准的裁决 ①：canJoinPlan 由**数据完整性**决定，不由
    // **来源**决定——主库行（用户自建 / CSV 导入）四个数值是必填的
    // （21 列契约 + 表单校验），所以「主库 = 完整」成立；详情与列表卡从此
    // 同一来源（卡侧 `_fromMainRow` 对主库行恒 true），不再两屏打架。
    await pumpSheet(
      tester,
      () async => detail(isUserCreated: true, state: 'user_created'),
      item: userCreated,
    );

    expect(
      find.text('营养不完整，暂不可加入确认计划'),
      findsNothing,
      reason: '来源不是质量：自建 + 四值齐必须可加入确认计划（卡侧同一规则）',
    );
  });

  testWidgets('自建条目给编辑/删除，内置条目一个写入口都没有', (tester) async {
    var edited = 0;
    var deleted = 0;
    await pumpSheet(
      tester,
      () async => detail(isUserCreated: true, state: 'user_created'),
      item: userCreated,
      onEdit: () async => edited++,
      onDelete: () async => deleted++,
    );

    expect(find.text('自建'), findsOneWidget);
    expect(find.byKey(const Key('food-detail-edit')), findsOneWidget);
    expect(find.byKey(const Key('food-detail-delete')), findsOneWidget);

    // 内置条目：就算调用点误传了回调，也不渲染任何写入口。
    await pumpSheet(
      tester,
      () async => detail(),
      onEdit: () async => edited++,
      onDelete: () async => deleted++,
    );
    expect(find.byKey(const Key('food-detail-edit')), findsNothing);
    expect(find.byKey(const Key('food-detail-delete')), findsNothing);
    // 没点按钮，回调一次都不该被调用。
    expect(edited, 0);
    expect(deleted, 0);
  });

  testWidgets('自建条目没给回调时也不画按钮（点了没反应更糟）', (tester) async {
    await pumpSheet(
      tester,
      () async => detail(isUserCreated: true, state: 'user_created'),
      item: userCreated,
    );

    expect(find.byKey(const Key('food-detail-edit')), findsNothing);
    expect(find.byKey(const Key('food-detail-delete')), findsNothing);
  });

  testWidgets('点编辑/删除先关掉详情弹层，再把控制权交给调用点', (tester) async {
    var edited = false;
    var deleted = false;
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => FoodDetailSheet.show(
                context,
                item: userCreated,
                load: () async =>
                    detail(isUserCreated: true, state: 'user_created'),
                onEdit: () async => edited = true,
                onDelete: () async => deleted = true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-detail-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('food-detail-edit')));
    await tester.pumpAndSettle();
    // 弹层自己关了（编辑会改掉它正显示的那份数据，留在原地就是给旧值），
    // 底下的页面没有被误关。
    expect(find.byKey(const Key('food-detail-sheet')), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(edited, isTrue);
    expect(deleted, isFalse);

    // 删除同理。
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('food-detail-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-detail-sheet')), findsNothing);
    expect(deleted, isTrue);
  });

  testWidgets('loader failure shows a retry message, not an empty card', (
    tester,
  ) async {
    await pumpSheet(tester, () async => throw StateError('shard gone'));

    expect(find.byKey(const Key('food-detail-error')), findsOneWidget);
    expect(find.text('食物详情加载失败，请重试。'), findsOneWidget);
  });

  testWidgets('a vanished food says so', (tester) async {
    await pumpSheet(tester, () async => null);

    expect(find.byKey(const Key('food-detail-missing')), findsOneWidget);
    expect(find.text('这条食物已不在本地数据里。'), findsOneWidget);
  });

  testWidgets('shows a loading state until the detail arrives', (tester) async {
    final completer = Completer<FoodDetail?>();
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodDetailSheet(item: builtIn, load: () => completer.future),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('food-detail-loading')), findsOneWidget);

    completer.complete(detail());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-detail-loading')), findsNothing);
    expect(find.byKey(const Key('food-detail-ring-kcal')), findsOneWidget);
  });
}
