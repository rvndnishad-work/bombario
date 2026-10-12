import 'package:bombario/game/input_controller.dart';
import 'package:bombario/ui/controls_overlay.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiles [input] walks before it stops, at the base 0.1 tile a tick.
double walkedOut(InputController input) {
  var tiles = 0.0;
  for (var i = 0; i < 100; i++) {
    final step = input.consume();
    if (step.direction == Direction.none) break;
    tiles += step.walk * 0.1;
  }
  return tiles;
}

void main() {
  // The stick's radius at scale 1, and how far its knob reaches.
  const radius = 70.0;
  const rim = radius * 0.85;

  Future<(InputController, Offset)> pumpStick(
    WidgetTester tester, {
    double stickTiles = 1,
  }) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = InputController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ControlsOverlay(
            input: input,
            actionLabel: ValueNotifier<String?>(null),
            haptics: false,
            stickTiles: stickTiles,
          ),
        ),
      ),
    );
    // The stick rests low in the left corner.
    final area = tester.getRect(find.byKey(const Key('joystick-area')));
    return (input, area.bottomLeft + const Offset(radius + 28, -radius - 24));
  }

  testWidgets('a drag of half the rim walks half a tile, then stops', (
    tester,
  ) async {
    final (input, rest) = await pumpStick(tester);
    final g = await tester.startGesture(rest);
    await g.moveBy(const Offset(rim / 2, 0));
    await tester.pump();
    expect(input.held, Direction.none);
    expect(input.moving, Direction.right);
    expect(walkedOut(input), closeTo(0.5, 1e-6));
    await g.up();
  });

  testWidgets('sensitivity scales the distance a drag walks', (tester) async {
    final (input, rest) = await pumpStick(tester, stickTiles: 0.5);
    final g = await tester.startGesture(rest);
    await g.moveBy(const Offset(0, -rim / 2));
    await tester.pump();
    expect(input.moving, Direction.up);
    expect(walkedOut(input), closeTo(0.25, 1e-6));
    await g.up();
  });

  testWidgets('the base floats to the thumb; drags read from there', (
    tester,
  ) async {
    final (input, rest) = await pumpStick(tester);
    final g = await tester.startGesture(rest + const Offset(40, -30));
    await tester.pump();
    expect(input.moving, Direction.none);
    await g.moveBy(const Offset(-rim / 2, 0));
    await tester.pump();
    expect(input.moving, Direction.left);
    expect(walkedOut(input), closeTo(0.5, 1e-6));
    await g.up();
  });

  testWidgets('the rim holds the direction; back inside drags; lifting '
      'stops', (tester) async {
    final (input, rest) = await pumpStick(tester);
    final g = await tester.startGesture(rest);
    await g.moveBy(const Offset(rim + 20, 0));
    await tester.pump();
    expect(input.held, Direction.right);
    for (var i = 0; i < 10; i++) {
      expect(input.consume().walk, 1);
    }
    // Back inside the rim: the hold ends and drag walks again.
    await g.moveBy(const Offset(-rim / 2, 0));
    await tester.pump();
    expect(input.held, Direction.none);
    // Pushed out again, then lifted: nothing more walks.
    await g.moveBy(const Offset(rim, 0));
    await tester.pump();
    expect(input.held, Direction.right);
    await g.up();
    await tester.pump();
    expect(input.held, Direction.none);
    expect(input.consume().direction, Direction.none);
  });
}
