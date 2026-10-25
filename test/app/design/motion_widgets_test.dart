import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/widgets/entrance_item.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PressableScale 按弹簧压到 0.97 并在松开时回弹', (tester) async {
    const key = Key('target');
    await tester.pumpWidget(
      _host(
        PressableScale(
          child: Container(
            key: key,
            width: 100,
            height: 100,
            color: Colors.blue,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    // springQuick（≈240ms）收敛后按到位。
    // 注意：Transform.scale 的 z 轴恒为 1，getMaxScaleOnAxis 永远读到 1；
    // 均匀缩放读 x 轴分量即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final pressed = tester.widget<Transform>(find.byType(Transform));
    expect(pressed.transform.storage[0], closeTo(0.97, 0.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final released = tester.widget<Transform>(find.byType(Transform));
    expect(released.transform.storage[0], closeTo(1, 0.01));
  });

  testWidgets('PressableScale 在减弱动画下直通', (tester) async {
    await tester.pumpWidget(
      _host(
        disableAnimations: true,
        PressableScale(child: SizedBox(width: 100, height: 100)),
      ),
    );
    expect(find.byType(AnimatedScale), findsNothing);
  });

  testWidgets('EntranceItem 首帧不可见，250ms 后完全入场', (tester) async {
    await tester.pumpWidget(
      _host(const EntranceItem(index: 0, child: Text('行'))),
    );
    var opacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(opacity, closeTo(0, 0.02));

    await tester.pump(AppMotion.base);
    opacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(opacity, 1);
  });

  testWidgets('EntranceItem 按 index 错峰', (tester) async {
    await tester.pumpWidget(
      _host(Column(children: [EntranceItem(index: 5, child: Text('晚'))])),
    );
    await tester.pump(AppMotion.base);
    // index 5 错峰 150ms：单件 250ms 时长尚未走完，仍在入场中。
    final mid = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(0.99));
  });

  testWidgets('EntranceItem 在减弱动画下直通', (tester) async {
    await tester.pumpWidget(
      _host(
        disableAnimations: true,
        const EntranceItem(index: 0, child: Text('行')),
      ),
    );
    expect(find.byType(Opacity), findsNothing);
  });
}
