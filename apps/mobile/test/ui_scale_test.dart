import 'package:bombario/main.dart';
import 'package:bombario/ui/kit/ui_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phones are unchanged; tablets scale up, capped', () {
    expect(UiScale.factor(const Size(914, 411)), 1); // phone landscape
    expect(UiScale.factor(const Size(844, 390)), 1);
    expect(UiScale.factor(const Size(960, 600)), closeTo(1.25, 1e-9));
    expect(UiScale.factor(const Size(1280, 800)), UiScale.maxFactor);
    expect(UiScale.factor(const Size(1366, 1024)), UiScale.maxFactor);
  });

  testWidgets('a tablet lays the app out on a smaller logical screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Size seen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => UiScale(child: child!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.expand(key: Key('page'));
          },
        ),
      ),
    );
    expect(seen.width, closeTo(1280 / 1.5, 1e-6));
    expect(seen.height, closeTo(800 / 1.5, 1e-6));
    // Scaled back up, the page still fills the real screen.
    expect(
      tester.getRect(find.byKey(const Key('page'))),
      const Rect.fromLTWH(0, 0, 1280, 800),
    );
  });

  testWidgets('a phone keeps its real size', (tester) async {
    tester.view.physicalSize = const Size(914, 411);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const BombarioApp());
    final context = tester.element(find.byType(Scaffold).first);
    expect(MediaQuery.sizeOf(context), const Size(914, 411));
  });
}
