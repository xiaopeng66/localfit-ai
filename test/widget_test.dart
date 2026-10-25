import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/localfit_app.dart';

void main() {
  testWidgets('app starts on the today destination', (tester) async {
    await tester.pumpWidget(const LocalFitApp());
    await tester.pumpAndSettle();

    expect(find.text('LocalFit AI'), findsNothing);
    expect(find.text('热量、营养目标和今日训练将在这里汇总。'), findsOneWidget);
  });
}
