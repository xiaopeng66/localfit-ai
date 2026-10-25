import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

abstract interface class LocalFoodSearch {
  Future<List<FoodRecord>> search(String query, {int limit = 30});
}
