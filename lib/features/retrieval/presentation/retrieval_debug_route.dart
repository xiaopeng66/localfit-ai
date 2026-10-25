import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:localfit_ai/core/errors/diagnostic_text.dart';

import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/jobs/application/power_state_source.dart';
import 'package:localfit_ai/features/retrieval/application/index_coordinator.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/presentation/retrieval_debug_page.dart';

/// 调试面板的装配壳：把仓储读成面板需要的两个列表（菜品库 + 食堂菜）。
///
/// 读失败**如实显示**（而不是白屏或空列表冒充「没有菜」）——调试面板的
/// 全部价值就在于它显示的是真实数据。
class RetrievalDebugRoute extends StatefulWidget {
  const RetrievalDebugRoute({
    super.key,
    required this.dishLibraryRepository,
    this.canteenRepository,
    this.semantic,
    this.onClose,
  });

  final DishLibraryRepository dishLibraryRepository;
  final CanteenRepository? canteenRepository;

  /// 语义运行时（docs/39 §6.4）：null＝未接线，面板如实显示「不可用」。
  final SemanticRuntime? semantic;
  final VoidCallback? onClose;

  @override
  State<RetrievalDebugRoute> createState() => _RetrievalDebugRouteState();
}

class _RetrievalDebugRouteState extends State<RetrievalDebugRoute> {
  late final Future<
    ({
      List<DishRecord> dishes,
      List<CanteenDish> canteen,
      RetrievalIndexStatus status,
    })
  >
  _load = _loadData();

  Future<
    ({
      List<DishRecord> dishes,
      List<CanteenDish> canteen,
      RetrievalIndexStatus status,
    })
  >
  _loadData() async {
    final dishes = await widget.dishLibraryRepository.watchAll().first;
    final canteen = <CanteenDish>[];
    final repository = widget.canteenRepository;
    if (repository != null) {
      for (final windows in (await repository.listWindowsByVenue()).values) {
        for (final window in windows) {
          canteen.addAll(window.dishes);
        }
      }
    }
    final database = widget.dishLibraryRepository.database;
    final status = RetrievalIndexStatus(
      indexedCount: await IndexCoordinator(database: database).indexedCount(),
      powerNote: kPowerStateNote,
      jobs: [
        for (final row
            in await (database.select(database.backgroundJobs)
                  ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
                  ..limit(5))
                .get())
          RetrievalJobLine(
            type: row.type,
            state: row.state,
            progress: row.progress,
            lastError: row.lastError,
          ),
      ],
    );
    return (dishes: dishes, canteen: canteen, status: status);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('搜索调试')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '读取菜品数据失败，无法调试：'
                '${sanitizeDiagnosticText('${snapshot.error}')}',
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(
          appBar: null,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      final data = snapshot.data!;
      return RetrievalDebugPage(
        dishes: data.dishes,
        canteenDishes: data.canteen,
        status: data.status,
        semantic: widget.semantic,
        onClose: widget.onClose,
      );
    },
  );
}
