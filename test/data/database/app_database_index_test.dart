import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';

void main() {
  test('onCreate creates the annotated indexes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY name",
        )
        .get();

    final names = rows.map((row) => row.read<String>('name')).toList();
    expect(names, contains('idx_meals_local_date'));
    expect(names, contains('idx_meal_items_meal_id'));
    expect(names, contains('idx_measurements_local_date'));
    expect(names, contains('idx_workout_sessions_status_local_date'));
    expect(names, contains('idx_workout_sets_session_id'));
  });

  test('schema declares the index entities', () {
    final names = AppDatabase(NativeDatabase.memory()).allSchemaEntities
        .map((entity) => entity.entityName)
        .toSet();

    expect(
      names,
      containsAll(<String>[
        'idx_meals_local_date',
        'idx_meal_items_meal_id',
        'idx_measurements_local_date',
        'idx_workout_sessions_status_local_date',
        'idx_workout_sets_session_id',
      ]),
    );
  });
}
