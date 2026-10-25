enum FoodCategory {
  staple(
    id: 'staple',
    label: '主食',
    assetPath: 'assets/icons/food_categories/staple.svg',
  ),
  protein(
    id: 'protein',
    label: '蛋白质食物',
    assetPath: 'assets/icons/food_categories/protein.svg',
  ),
  vegetable(
    id: 'vegetable',
    label: '蔬菜',
    assetPath: 'assets/icons/food_categories/vegetable.svg',
  ),
  fruit(
    id: 'fruit',
    label: '水果',
    assetPath: 'assets/icons/food_categories/fruit.svg',
  ),
  dairy(
    id: 'dairy',
    label: '乳制品',
    assetPath: 'assets/icons/food_categories/dairy.svg',
  ),
  beverage(
    id: 'beverage',
    label: '饮品',
    assetPath: 'assets/icons/food_categories/beverage.svg',
  ),
  snack(
    id: 'snack',
    label: '零食甜点',
    assetPath: 'assets/icons/food_categories/snack.svg',
  ),
  condiment(
    id: 'condiment',
    label: '调味品',
    assetPath: 'assets/icons/food_categories/condiment.svg',
  ),
  prepared(
    id: 'prepared',
    label: '预制餐食',
    assetPath: 'assets/icons/food_categories/prepared.svg',
  ),
  other(
    id: 'other',
    label: '其他食物',
    assetPath: 'assets/icons/food_categories/other.svg',
  );

  const FoodCategory({
    required this.id,
    required this.label,
    required this.assetPath,
  });

  final String id;
  final String label;
  final String assetPath;

  /// 由落库的枚举 id 反查（`foods.category` 存的是 [FoodCategory.id] 文本）。
  /// 库里出现未知 id（旧目录分片 / 手改数据）时返回 null，由调用方决定回落，
  /// 不猜「其他」——猜了会把坏数据洗成合法样子。
  static FoodCategory? tryFromId(String? id) {
    if (id == null) return null;
    for (final category in values) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// 由中文标签反查（CSV 导入的 category 列认标签也认 id，docs/31 S5 ⑥）。
  static FoodCategory? tryFromLabel(String? label) {
    if (label == null) return null;
    for (final category in values) {
      if (category.label == label) return category;
    }
    return null;
  }

  /// 用户食物库「一级分类」→ 本枚举（Round 5 T11 新结构，2026-10-13）。
  ///
  /// 新结构里那一列是**库自己的自由文本**（用户流水线的 24 个中文大类），本枚举
  /// 是 App 内部的展示/筛选口径——两者不是一件事。这张表是它们之间唯一的翻译，
  /// 写死、可评审：表外的新值 ⇒ 导入按「不是有效种类」整行拒绝（大声失败，
  /// 加一行映射即可）；表内 24 条一条不落、值都是真枚举，由测试钉住。
  static const Map<String, FoodCategory> _libraryGroups = {
    '谷物及主食': FoodCategory.staple,
    '薯类及淀粉': FoodCategory.staple,
    '粥类': FoodCategory.staple,
    '中式面点': FoodCategory.staple,
    '零食及甜品': FoodCategory.snack,
    '烘焙食品': FoodCategory.snack,
    '蔬菜及制品': FoodCategory.vegetable,
    '菌藻类': FoodCategory.vegetable,
    '水果及制品': FoodCategory.fruit,
    '乳类及制品': FoodCategory.dairy,
    '饮料类': FoodCategory.beverage,
    '调味品': FoodCategory.condiment,
    '油脂类': FoodCategory.condiment,
    '菜肴及地方食品': FoodCategory.prepared,
    '菜肴及快餐': FoodCategory.prepared,
    '汤羹炖品': FoodCategory.prepared,
    '酱卤熟食': FoodCategory.prepared,
    '蛋类及制品': FoodCategory.protein,
    '畜肉及制品': FoodCategory.protein,
    '禽肉及制品': FoodCategory.protein,
    '水产及制品': FoodCategory.protein,
    '豆类及制品': FoodCategory.protein,
    '坚果种子': FoodCategory.protein,
    '其他食品': FoodCategory.other,
  };

  /// 表内 24 个库大类的只读视图（测试钉「一条不落」与文档引用同一份事实）。
  static Map<String, FoodCategory> get libraryGroups =>
      Map.unmodifiable(_libraryGroups);

  /// 按用户食物库的一级分类反查；表外返回 null（由调用方决定回落——
  /// 导入侧会再试枚举标签/id，最后按名字归类，都不猜「其他」）。
  static FoodCategory? tryFromLibraryGroup(String? group) {
    if (group == null) return null;
    return _libraryGroups[group.trim()];
  }

  static FoodCategory classify({required String name, String? rawCategory}) {
    final normalizedName = name.toLowerCase();
    final normalizedCategory = (rawCategory ?? '').toLowerCase();

    if (_containsAny(normalizedCategory, _preparedCategoryKeywords)) {
      return FoodCategory.prepared;
    }
    if (_containsAny(normalizedCategory, _snackCategoryKeywords)) {
      return FoodCategory.snack;
    }
    if (_containsAny(normalizedCategory, _dairyCategoryKeywords)) {
      return FoodCategory.dairy;
    }
    if (_containsAny(normalizedCategory, _beverageCategoryKeywords)) {
      return FoodCategory.beverage;
    }
    if (_containsAny(normalizedCategory, _proteinCategoryKeywords)) {
      return FoodCategory.protein;
    }
    if (_containsAny(normalizedCategory, _condimentCategoryKeywords)) {
      return FoodCategory.condiment;
    }

    if (_containsAny(normalizedName, _preparedNameKeywords)) {
      return FoodCategory.prepared;
    }
    if (_containsAny(normalizedName, _dairyNameKeywords)) {
      return FoodCategory.dairy;
    }
    if (_containsAny(normalizedName, _beverageNameKeywords)) {
      return FoodCategory.beverage;
    }
    if (_containsAny(normalizedName, _snackNameKeywords)) {
      return FoodCategory.snack;
    }
    if (_containsAny(normalizedName, _fruitNameKeywords)) {
      return FoodCategory.fruit;
    }
    if (_containsAny(normalizedName, _vegetableNameKeywords)) {
      return FoodCategory.vegetable;
    }
    if (_containsAny(normalizedName, _proteinNameKeywords)) {
      return FoodCategory.protein;
    }
    if (_containsAny(normalizedName, _condimentNameKeywords)) {
      return FoodCategory.condiment;
    }
    if (_containsAny(normalizedName, _stapleNameKeywords)) {
      return FoodCategory.staple;
    }
    return FoodCategory.other;
  }

  static bool _containsAny(String value, List<String> keywords) =>
      keywords.any(value.contains);

  static const _preparedCategoryKeywords = [
    'prepared',
    'meal',
    'plat préparé',
    'comidas preparadas',
    'sandwich',
    'surgelé',
    'frozen',
  ];
  static const _snackCategoryKeywords = [
    'snack',
    'botana',
    'imbiss',
    'gustări',
    'закуски',
    'dessert',
    'postres',
  ];
  static const _dairyCategoryKeywords = [
    'dair',
    'laitier',
    'milch',
    'lácteo',
    'laticínio',
    'latticini',
    'zuivel',
    '乳製品',
    '乳制品',
    'молоч',
  ];
  static const _beverageCategoryKeywords = [
    'beverage',
    'boisson',
    'getränk',
    'bebida',
    'bevande',
    'băuturi',
    'напитки',
    '飲料',
    '饮料',
  ];
  static const _proteinCategoryKeywords = [
    'seafood',
    'produits de la mer',
    'fisch',
    'meat',
    'viande',
    'fleisch',
    'productos del mar',
    'produits d’élevages',
    "produits d'elevages",
  ];
  static const _condimentCategoryKeywords = [
    'condiment',
    'gewürz',
    '調味料',
    '调味料',
  ];

  static const _preparedNameKeywords = ['速冻披萨', '方便面', '盒饭', '便当', '汉堡', '三明治'];
  static const _dairyNameKeywords = [
    '牛奶',
    '羊奶',
    '酸奶',
    '奶酪',
    '芝士',
    '炼乳',
    '奶粉',
    '奶油',
    'yogurt',
    'yoghurt',
    'cheese',
    'milk',
  ];
  static const _beverageNameKeywords = [
    '可乐',
    '饮料',
    '果汁',
    '咖啡',
    '茶饮',
    '奶茶',
    '豆浆',
    '矿泉水',
    '啤酒',
    '葡萄酒',
    'juice',
    'coffee',
    'cola',
  ];
  static const _snackNameKeywords = [
    '薯片',
    '饼干',
    '糖果',
    '巧克力',
    '蛋糕',
    '甜点',
    '冰淇淋',
    '爆米花',
    '曲奇',
  ];
  static const _fruitNameKeywords = [
    '苹果',
    '香蕉',
    '橙',
    '柚',
    '梨',
    '桃',
    '葡萄',
    '草莓',
    '蓝莓',
    '芒果',
    '西瓜',
    '哈密瓜',
    '猕猴桃',
    '菠萝',
    '樱桃',
  ];
  static const _vegetableNameKeywords = [
    '西兰花',
    '菠菜',
    '生菜',
    '白菜',
    '青菜',
    '油菜',
    '番茄',
    '西红柿',
    '黄瓜',
    '茄子',
    '胡萝卜',
    '土豆',
    '蘑菇',
    '豆芽',
    '南瓜',
    '芹菜',
  ];
  static const _proteinNameKeywords = [
    '鸡胸',
    '鸡肉',
    '鸡蛋',
    '鸭肉',
    '牛肉',
    '猪肉',
    '羊肉',
    '鱼',
    '虾',
    '蟹',
    '贝',
    '豆腐',
    '豆干',
    '火腿',
    '肉',
    'egg',
    'chicken',
    'beef',
    'pork',
    'fish',
    'tofu',
  ];
  static const _condimentNameKeywords = [
    '酱油',
    '食醋',
    '陈醋',
    '调味酱',
    '食用盐',
    '食用油',
    '橄榄油',
    '花生油',
    '调味料',
  ];
  static const _stapleNameKeywords = [
    '米饭',
    '米粥',
    '粥',
    '面条',
    '面包',
    '馒头',
    '包子',
    '饺子',
    '燕麦',
    '谷物',
    '意面',
    '米粉',
    '河粉',
    'rice',
    'noodle',
    'pasta',
    'bread',
    'cereal',
  ];
}
