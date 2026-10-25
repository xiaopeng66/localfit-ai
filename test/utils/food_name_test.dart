import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/utils/food_brands.g.dart';
import 'package:localfit_ai/utils/food_brands_reviewed.g.dart';
import 'package:localfit_ai/utils/food_name.dart';
import 'package:localfit_ai/utils/text_utils.dart';

/// 食物名称 / 品牌拆分（docs/28 §5.4，N11）。
///
/// 四层证据：
///  1. fixture：规则 1/2/3 各自的形态与反例（含计划点名的 5 条括号式名字与
///     12 个描述词停用表）；
///  2. 不变量：在**真实种子（v5）的全部条目**上枚举
///     `normalizeFoodName(brand + ' ' + name) == normalizeFoodName(raw)`。
///     2026-10-13 起（docs/32 §4 T13）种子已移出仓库，这一组只在**本机有归档**
///     时注册（见 `archivedSeedPath`）；没有归档就不跑，而不是删断言——覆盖
///     损失如实记在 T13 证据里；
///  3. 自动词表新鲜度：用 Dart 按生成脚本的同一条规则把词表**重算一遍**，与
///     `kFoodBrandTokens` 逐字比较，并校验它记录的是当前种子的 sha256。
///     改了种子不重生成词表（`tool/food_seed/build_brand_gazetteer.py`）→ 红。
///  4. 人工词表对账：`kFoodBrandTokensReviewed` 只含账本 `review_ledger.jsonl`
///     里出现过的 `brand_token`；手加一个（账本里没有）→ 红。
void main() {
  // 2026-10-13（docs/32 §4 T13）：食物种子整族退役、已移出仓库，归档在仓库外的
  // `../archive/food-seed-2026-10-13/`（见那里的 README）。需要真实种子的断言
  // 因此改成「有归档才注册」，而不是断言一个仓库里不存在的文件。
  // 相对路径按包根解析（`flutter test` 的工作目录就是包根）。
  const archivedSeedPath = '../archive/food-seed-2026-10-13/foods.v5.json';
  const scriptPath = 'tool/food_seed/build_brand_gazetteer.py';
  const ledgerPath = 'reports/review_ledger.jsonl';

  /// docs/28 §5.4 的 12 个描述词停用表（生成脚本里的同一份，测试端独立写出：
  /// 脚本把停用表丢掉时这里仍会红）。
  const stopwords = <String>[
    'Golden',
    'Value',
    'Classic',
    'organic',
    'super',
    'Pure',
    'FINE',
    'raw',
    'MULTI',
    'Fresh',
    'premium',
    'Extra',
  ];

  final seedFile = File(archivedSeedPath);
  final seed = seedFile.existsSync()
      ? jsonDecode(seedFile.readAsStringSync()) as Map<String, Object?>
      : null;
  final names = seed == null
      ? const <String>[]
      : [
          for (final item
              in (seed['foods']! as List).cast<Map<String, Object?>>())
            item['name']! as String,
        ];

  group('splitFoodName 规则', () {
    test('规则 1：括号内的拉丁词是品牌，括号不留在名字里', () {
      expect(splitFoodName('(Beretta) Prosciutto Cotto火腿片'), (
        name: 'Prosciutto Cotto火腿片',
        brand: 'Beretta',
      ));
      expect(
        splitFoodName('(BellaMare) Kieler Sprotten 油浸鲱鱼罐头').brand,
        'BellaMare',
      );
    });

    test('规则 1 反例：括号里是产地或营养标注时不动', () {
      for (final raw in const [
        '(韩国)蜂蜜柚子茶',
        '(Fe+VC)无糖泡腾片',
        '面条(生)',
        '饺子(猪肉韭菜馅)',
      ]) {
        expect(splitFoodName(raw), (name: raw, brand: null), reason: raw);
      }
    });

    test('规则 2：首 token 在词表里才拆', () {
      expect(splitFoodName('7-ELEVEN 7-11御饭团'), (
        name: '7-11御饭团',
        brand: '7-ELEVEN',
      ));
      // 品牌与译名粘在一个 token 里（种子 20.4% 的拉丁残留多数是这种）：
      // 整体当品牌，不往 token 内部切。
      expect(splitFoodName('Nichirei日冷 抹茶冰淇淋'), (
        name: '抹茶冰淇淋',
        brand: 'Nichirei日冷',
      ));
    });

    test('规则 3：没有证据就原样返回', () {
      for (final raw in const [
        '米饭',
        '面条(生)',
        '迷你 小饼干', // 纯中文描述词：自动规则不收，人工审核也没把它并进词表
        'kale 羽衣甘蓝',
      ]) {
        expect(splitFoodName(raw), (name: raw, brand: null), reason: raw);
      }
    });

    test('规则 2 也认人工词表：`明治 酸奶` 拆（自动规则排除了纯汉字）', () {
      // 纯汉字品牌自动规则按设计不收；2026-10-06 全量人工审核把它并入
      // `food_brands_reviewed.g.dart`，运行时词表取并集后必须能拆。
      expect(
        kFoodBrandTokens.contains('明治'),
        isFalse,
        reason: '自动规则只收拉丁/数字词，明治不该在自动表里',
      );
      expect(kFoodBrandTokensReviewed.contains('明治'), isTrue);
      expect(splitFoodName('明治 酸奶'), (name: '酸奶', brand: '明治'));
    });

    test('12 个描述词不进**自动**词表：`Golden 小饼干` 不拆', () {
      // 停用表约束的是**自动**词表（按频率/形态机械收词，会把描述词误收）。
      // 人工表另说：全量审核里人可以为某个确实同形的品牌单独裁决（例如
      // `FINE Japan` 是日本保健品牌、全库仅 1 条），那条裁决带着 source 证据
      // 落在账本里，不是自动规则的产物。所以这里只对自动表断言。
      for (final word in stopwords) {
        expect(
          kFoodBrandTokens.contains(word),
          isFalse,
          reason: '$word 是描述词，自动表收它会把描述词当品牌搬到卡底',
        );
      }
      // 人工表里若出现停用词形的 token，必须能在账本里找到带证据的 brand_token
      // 裁决（下面「人工词表只含账本裁决过的 token」那条已经保证这一点）。
      for (final word in [
        'Golden',
        'Value',
        'Classic',
        'organic',
        'super',
        'Pure',
        'raw',
        'MULTI',
        'premium',
      ]) {
        expect(splitFoodName('$word 小饼干'), (
          name: '$word 小饼干',
          brand: null,
        ), reason: '$word 既不在自动表、也没被人工裁决为品牌，不该拆');
      }
    });

    test('拆分判据是词表本身，不是一个写死的分支', () {
      // 词表被换掉 ⇒ 拆分随之变化（变异红证的锚点：拔掉词表必须能看出来）。
      expect(splitFoodName('Foo 小饼干', brands: const {}), (
        name: 'Foo 小饼干',
        brand: null,
      ));
      expect(splitFoodName('Foo 小饼干', brands: const {'Foo'}), (
        name: '小饼干',
        brand: 'Foo',
      ));
    });
  });

  if (names.isNotEmpty) {
    group('拆分不丢字（真实种子全量枚举）', () {
      test('normalize(brand + name) == normalize(raw)，共 ${names.length} 条', () {
        // 唯一例外：规则 1 的 5 条括号式名字——括号本身是「品牌」标记，按计划
        // 不进品牌（字面只少那一对括号）。对这 5 条断言「去掉括号后相等」。
        final parenthesized = names
            .where((name) => name.startsWith('('))
            .toList();
        expect(parenthesized.length, 5, reason: '括号式名字的集合变了，例外清单要重看');

        var split = 0;
        var droppedParens = 0;
        for (final raw in names) {
          final parts = splitFoodName(raw);
          final rejoined = parts.brand == null
              ? parts.name
              : '${parts.brand} ${parts.name}';
          final left = normalizeFoodName(rejoined);
          // 例外只对**真的按规则 1 拆了**的括号式名字生效（`(韩国)蜂蜜柚子茶`
          // 没拆，它必须逐字不变）。
          final exception = parts.brand != null && raw.startsWith('(');
          final right = exception
              ? normalizeFoodName(raw.replaceAll('(', '').replaceAll(')', ''))
              : normalizeFoodName(raw);
          expect(left, right, reason: '拆分丢字：$raw');
          if (exception) droppedParens++;
          if (parts.brand != null) split++;
        }
        expect(droppedParens, 4, reason: '按规则 1 丢括号的应恰好是那 4 条拉丁括号式');
        // 拆到 7,000+ 条：词表被打回空集/规则被摘掉时，这条会先红。
        // v5 加了人工词表（含大量纯汉字品牌）后这一数显著上升。
        expect(split, greaterThan(30000), reason: '拆分覆盖的条目数骤降');
      });

      test('括号式那 5 条里只有 4 条认出品牌（(韩国) 不是品牌）', () {
        final parenthesized = names
            .where((name) => name.startsWith('('))
            .toList();
        final brands = <String>[];
        for (final raw in parenthesized) {
          final brand = splitFoodName(raw).brand;
          if (brand != null) brands.add(brand);
        }
        expect(brands, ['BellaMare', 'Beretta', 'PUAS', 'Bergin']);
      });
    });
  }

  group('词表与生成脚本一致', () {
    if (names.isNotEmpty) {
      test('按生成脚本的规则重算，与 kFoodBrandTokens 逐字相同', () {
        final han = RegExp(r'[\u4e00-\u9fff]');
        final ascii = RegExp(r'[A-Za-z0-9]');
        final derived = <String>{};
        for (final name in names) {
          final cut = name.indexOf(' ');
          if (cut <= 0) continue;
          final head = name.substring(0, cut);
          final rest = name.substring(cut + 1);
          if (head.startsWith('(')) continue;
          if (!ascii.hasMatch(head)) continue;
          if (!han.hasMatch(rest)) continue;
          if (stopwords.contains(head)) continue;
          derived.add(head);
        }
        expect(derived, kFoodBrandTokens);
      });
    }

    test('生成文件自洽：sha256 与条数两处声明一致', () {
      // 真正的「词表是否跟得上种子」由上面那条**重算比较**兜住（种子一改，
      // 重算集合就变，逐字比较立刻红）；这里再钉住生成物自己不自相矛盾。
      // sha256 只在 Python 侧算（`build_brand_gazetteer.py --check`，注意
      // `crypto` 不是本项目的直接依赖，测试里不引它）。
      final generated = File('lib/utils/food_brands.g.dart').readAsStringSync();
      expect(generated, contains(kFoodBrandSeedSha256));
      expect(generated, contains('// 条数：${kFoodBrandTokens.length}'));
      expect(kFoodBrandSeedSha256.length, 64, reason: 'sha256 十六进制串');
    });

    test('生成脚本声明同一份停用表（脚本改了忘改这里的清单）', () {
      final script = File(scriptPath).readAsStringSync();
      for (final word in stopwords) {
        expect(script, contains('"$word"'), reason: '脚本少了停用词 $word');
      }
      expect(script, contains('--check'), reason: '脚本要能自检词表新鲜度');
    });
  });

  group('人工词表只含账本裁决过的 token（D13）', () {
    test('kFoodBrandTokensReviewed ⊆ 账本 brand_token 集合', () {
      // 人工表由 `apply_review.py` 从账本生成；这里独立重放账本、收集所有
      // `brand_token` 裁决的 token，断言生成表里的每一个都在其中——手改
      // 生成文件加一个 token（账本里没有）⇒ 红。
      final ledgerTokens = <String>{};
      for (final line in File(ledgerPath).readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final row = jsonDecode(line) as Map<String, dynamic>;
        if (row['decision'] != 'brand_token') continue;
        final after = row['after'] as Map<String, dynamic>?;
        final token = after?['brand_token'];
        if (token is String && token.isNotEmpty) ledgerTokens.add(token);
      }
      expect(ledgerTokens, isNotEmpty, reason: '账本里应当有 brand_token 裁决');
      final extra = kFoodBrandTokensReviewed.difference(ledgerTokens);
      expect(extra, isEmpty, reason: '人工表里有账本没裁过的 token（手改生成文件？）：$extra');
    });

    test('人工表与自动表不相交（自动表已收的不重复收）', () {
      final overlap = kFoodBrandTokensReviewed.intersection(kFoodBrandTokens);
      expect(overlap, isEmpty, reason: '人工表收了自动表已有的 token，并集口径变脏：$overlap');
    });

    test('生成文件记录账本 sha256', () {
      final generated = File('lib/utils/food_brands_reviewed.g.dart')
          .readAsStringSync();
      expect(generated, contains(kFoodBrandsReviewedLedgerSha256));
      expect(
        kFoodBrandsReviewedLedgerSha256.length,
        64,
        reason: 'sha256 十六进制串',
      );
    });
  });
}
