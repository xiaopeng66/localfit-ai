import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// `RV4-P1-05`（`docs/57` §3 / `docs/56` R3）：**匹配是对的，被排序和上限藏了**。
///
/// 实测（随包 CSV 复算）：「鸡蛋」命中 **154 条**，`鸡蛋（熟）` 按现有排序
/// （`isUserCreated → 精确 → instr → length`）落在第 **32** 位，而结果区只取
/// **10** 条 ⇒ 用户永远看不到它。品牌完全不参与检索（`page()` 只 `like(name)`）。
///
/// 本文件钉两件事：
/// 1. **括号前主名优先**：搜「鸡蛋」时 `鸡蛋（熟）` 必须进前 3；
/// 2. **品牌参与检索**：搜「千丰香米」能命中品牌为千丰香米的「米饭」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
    );
  });
  tearDown(() => database.close());

  Future<void> add(String name, {String? brand, double kcal = 100}) =>
      repository.create(
        NewFood(
          name: name,
          brand: brand,
          kcalPer100g: kcal,
          proteinPer100g: 5,
          carbsPer100g: 10,
          fatPer100g: 3,
        ),
      );

  group('括号前主名优先（搜「鸡蛋」要能看到「鸡蛋（熟）」）', () {
    test('括号变体进前 3（现为第 4 之外）', () async {
      // 真实库的形状：命中 154 条，其中大量是「鸡蛋X」这种**更短**的名字。
      // 现排序（instr → length）下 `鸡蛋（熟）`（5 字）排在它们**后面**，
      // 所以「匹配到了但看不到」。
      for (final suffix in ['干', '仔', '清', '黄', '白', '皮', '壳', '丝']) {
        await add('鸡蛋$suffix');
      }
      await add('鸡蛋清（代表值；生）');
      await add('鸡蛋（熟）', kcal: 139);
      for (var i = 0; i < 12; i++) {
        await add('鸡蛋制品${i.toString().padLeft(2, '0')}');
      }

      final results = await repository.search('鸡蛋', limit: 10);
      final names = results.map((food) => food.name).toList();
      final index = names.indexOf('鸡蛋（熟）');
      expect(
        index,
        greaterThanOrEqualTo(0),
        reason: '「鸡蛋（熟）」必须在前 10 里（现在被 154 条命中的长尾淹掉）',
      );
      expect(index, lessThan(3), reason: '括号前主名 == 查询词时应排在前面。实际位次：$names');
    });

    test('精确同名仍优先于括号变体', () async {
      await add('鸡蛋（熟）');
      await add('鸡蛋干');
      await add('鸡蛋'); // 精确同名
      final results = await repository.search('鸡蛋', limit: 10);
      expect(results.first.name, '鸡蛋');
    });

    test('无括号的名称排序不变（括号逻辑不误伤普通词）', () async {
      await add('鸡胸肉');
      await add('鸡腿');
      final results = await repository.search('鸡', limit: 10);
      expect(results, isNotEmpty);
      // 「鸡腿」比「鸡胸肉」短 → 现排序里先出；括号规则不该改变这一点。
      expect(results.first.name, '鸡腿');
    });
  });

  group('品牌参与检索（搜「千丰香米」要命中「米饭」）', () {
    test('搜品牌命中该行', () async {
      await add('米饭', brand: '千丰香米', kcal: 338);
      await add('米饭', brand: '叮咚', kcal: 156);
      await add('米饭', kcal: 116);

      final results = await repository.search('千丰香米');
      expect(
        results.map((food) => food.name),
        contains('米饭'),
        reason: '品牌必须参与检索（原来 page() 只 like(name)）',
      );
      expect(results.first.brand, '千丰香米', reason: '品牌命中的那条要排在最前');
    });

    test('名称命中优先于品牌命中（排序档位）', () async {
      // 名称里就有「香米」的 vs 只有品牌是「香米」的。
      await add('香米');
      await add('米饭', brand: '香米');
      final results = await repository.search('香米');
      expect(results, isNotEmpty);
      expect(results.first.name, '香米', reason: '名称命中应排在品牌命中之前（品牌是补充信息）');
    });

    test('品牌检索不受大小写/空格影响（沿用 trim 语义）', () async {
      await add('米饭', brand: '千丰香米');
      final results = await repository.search('  千丰香米  ');
      expect(results, isNotEmpty);
    });
  });

  group('回归：既有排序事实不变', () {
    test('limit 生效且 id ASC 收尾（分页稳定）', () async {
      for (var i = 0; i < 30; i++) {
        await add('同名食物');
      }
      final first = await repository.page(query: '同名食物', offset: 0, limit: 10);
      final second = await repository.page(
        query: '同名食物',
        offset: 10,
        limit: 10,
      );
      expect(first, hasLength(10));
      expect(second, hasLength(10));
      // 两页不许有交集（`id ASC` 收尾保证稳定）。
      final firstIds = first.map((food) => food.id).toSet();
      expect(
        second.map((food) => food.id).where(firstIds.contains),
        isEmpty,
        reason: '分页在值相等的行之间必须稳定（id ASC 收尾）',
      );
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${(_value++).toString().padLeft(4, '0')}';
}
