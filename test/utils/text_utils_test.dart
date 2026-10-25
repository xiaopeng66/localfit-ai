import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/utils/text_utils.dart';

/// 食物名称规范化（docs/28 §5.4）：改大小写**不改信息**。
///
/// 旧实现把每个词都 `first.toUpperCase() + rest.toLowerCase()`，于是
/// 含中文的混合词里的内部大写被压平（`AB100健能` 类），而品牌在名称里的
/// 唯一线索正是这些大写。
void main() {
  test('下划线/连字符换空格并折叠空白', () {
    expect(normalizeFoodName('  米饭  '), '米饭');
    expect(normalizeFoodName('生_菜__沙拉'), '生 菜 沙拉');
    expect(normalizeFoodName('7-11御饭团'), '7 11御饭团');
    expect(normalizeFoodName(''), '');
  });

  test('含中文的混合词原样保留内部大写', () {
    expect(
      normalizeFoodName('dplus 天然酵母面包HokkaidoCream'),
      'Dplus 天然酵母面包HokkaidoCream',
    );
    expect(normalizeFoodName('AB100健能发酵乳'), 'AB100健能发酵乳');
    expect(normalizeFoodName('KITTY猫巧克力棒糖'), 'KITTY猫巧克力棒糖');
    expect(
      normalizeFoodName('100%WHOLEWHEATBREAD100%全麦面包'),
      '100%WHOLEWHEATBREAD100%全麦面包',
    );
  });

  test('全大写数字字母串保留（量表/缩略语）', () {
    for (final word in const ['OREO', 'AGF', '250ML', 'V8', '12OZ']) {
      expect(normalizeFoodName('$word 饼干'), '$word 饼干');
    }
  });

  test('纯拉丁词只补首字母：内部大写不被压平', () {
    expect(normalizeFoodName('ACfarm 大米'), 'ACfarm 大米');
    expect(normalizeFoodName('HokkaidoCream 面包'), 'HokkaidoCream 面包');
    expect(normalizeFoodName('mcdonald 汉堡'), 'Mcdonald 汉堡');
    expect(normalizeFoodName('milk'), 'Milk');
  });

  test('标点与数字不动', () {
    expect(normalizeFoodName('85℃ 奶香可颂面包'), '85℃ 奶香可颂面包');
    expect(normalizeFoodName('35%M.E. 奶油'), '35%M.E. 奶油');
    expect(normalizeFoodName('面条(生)'), '面条(生)');
  });
}
