import 'package:bombario/game/input_controller.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiles [input] walks over its next [ticks] ticks at [per] tiles a tick.
double walked(InputController input, int ticks, double per) {
  var tiles = 0.0;
  for (var i = 0; i < ticks; i++) {
    final step = input.consume();
    if (step.direction != Direction.none) tiles += step.walk * per;
  }
  return tiles;
}

void main() {
  const base = Player.baseSpeed * World.tickDt; // 0.1 tile a tick

  test('a tap walks exactly an eighth of a tile at any speed', () {
    final input = InputController();
    input.tap(Direction.right);
    final first = input.consume();
    expect(first.direction, Direction.right);
    expect(first.walk, closeTo(1, 1e-9));
    final last = input.consume();
    expect(last.direction, Direction.right);
    expect(last.walk, closeTo(0.25, 1e-9)); // the last 0.025 tile
    expect(input.consume().direction, Direction.none);

    const fast = Player.maxSpeed * World.tickDt; // 0.2 tile a tick
    input.tilesPerTick = () => fast;
    input.tap(Direction.left);
    expect(walked(input, 5, fast), closeTo(1 / 8, 1e-9));
  });

  test('a press shorter than a tap keeps walking until it is one', () {
    final input = InputController();
    input.setDirection(Direction.right);
    expect(input.consume().direction, Direction.right);
    input.lift();
    expect(input.held, Direction.none);
    // A third of the tap walked easing in; the lift makes up the rest.
    final step = input.consume();
    expect(step.direction, Direction.right);
    expect(step.walk * base, closeTo(1 / 8 - 1 / 24, 1e-9));
    expect(input.consume().direction, Direction.none);
  });

  test('a normal tap walks exactly an eighth however long it lasted', () {
    for (final speed in [Player.baseSpeed, Player.maxSpeed]) {
      final per = speed * World.tickDt;
      for (var ticks = 0; ticks <= InputController.easeTicks; ticks++) {
        final input = InputController()..tilesPerTick = () => per;
        input.setDirection(Direction.left);
        var tiles = walked(input, ticks, per);
        input.lift();
        tiles += walked(input, 5, per);
        expect(tiles, closeTo(1 / 8, 1e-9), reason: '$ticks ticks at $speed');
      }
    }
  });

  test('a press lifted before any tick walks a whole tap', () {
    final input = InputController();
    input.setDirection(Direction.down);
    input.lift();
    expect(walked(input, 5, base), closeTo(1 / 8, 1e-9));
  });

  test('a long press owes nothing when lifted', () {
    final input = InputController();
    input.setDirection(Direction.up);
    for (var i = 0; i < 5; i++) {
      input.consume();
    }
    input.lift();
    expect(input.consume().direction, Direction.none);
  });

  test('release (pausing) never tops up, and a new direction resets', () {
    final input = InputController();
    input.setDirection(Direction.left);
    input.release();
    expect(input.consume().direction, Direction.none);

    input.setDirection(Direction.left);
    input.consume();
    input.consume();
    input.setDirection(Direction.down);
    input.lift();
    expect(input.consume().direction, Direction.down);
    expect(input.consume().direction, Direction.down);
    expect(input.consume().direction, Direction.none);
  });

  test('a press from standstill eases in over a tap, then walks whole '
      'ticks', () {
    final input = InputController();
    input.setDirection(Direction.right);
    for (var i = 0; i < InputController.easeTicks; i++) {
      expect(input.consume().walk * base, closeTo(1 / 24, 1e-9));
    }
    for (var i = 0; i < 3; i++) {
      expect(input.consume().walk, 1);
    }
  });

  test('turning while walking, and auto-repeats, start at full speed', () {
    final input = InputController();
    input.setDirection(Direction.right);
    walked(input, 5, base);
    input.setDirection(Direction.up);
    expect(input.consume().walk, 1);

    input.release();
    input.setDirection(Direction.left, ease: false);
    expect(input.consume().walk, 1);
  });

  group('walk (the joystick)', () {
    test('accumulates, and the last tick walks only what is left', () {
      final input = InputController();
      input.walk(Direction.right, 0.12);
      input.walk(Direction.right, 0.13);
      final first = input.consume();
      expect(first.direction, Direction.right);
      expect(first.walk, 1);
      expect(input.consume().walk, 1);
      final last = input.consume();
      expect(last.direction, Direction.right);
      expect(last.walk * base, closeTo(0.05, 1e-9));
      expect(input.consume().direction, Direction.none);
    });

    test('caps the budget at one tile, or at a larger cap', () {
      final input = InputController();
      input.walk(Direction.down, 0.8);
      input.walk(Direction.down, 0.8);
      expect(walked(input, 30, base), closeTo(1, 1e-9));
      input.walk(Direction.down, 2.5, cap: 3);
      input.walk(Direction.down, 2.5, cap: 3);
      expect(walked(input, 60, base), closeTo(3, 1e-9));
    });

    test('a new direction replaces the budget', () {
      final input = InputController();
      input.walk(Direction.left, 0.5);
      input.walk(Direction.up, 0.2);
      expect(input.moving, Direction.up);
      expect(walked(input, 30, base), closeTo(0.2, 1e-9));
    });

    test('holding a direction drops the budget', () {
      final input = InputController();
      input.walk(Direction.left, 0.5);
      input.setDirection(Direction.left, ease: false);
      input.release();
      expect(input.consume().direction, Direction.none);
    });
  });
}
