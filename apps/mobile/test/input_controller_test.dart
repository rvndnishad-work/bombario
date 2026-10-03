import 'package:bombario/game/input_controller.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a tap is a quarter tile at the current speed', () {
    final input = InputController();
    expect(input.tapTicks, 3); // 0.25 tile at 0.1 tile per tick
    input.tilesPerTick = () => Player.maxSpeed * World.tickDt;
    expect(input.tapTicks, 2);
  });

  test('a press shorter than a tap keeps walking until it is one', () {
    final input = InputController();
    input.setDirection(Direction.right);
    expect(input.consume().direction, Direction.right);
    input.lift();
    expect(input.held, Direction.none);
    // Two more ticks make up the quarter tile, then it stops.
    expect(input.consume().direction, Direction.right);
    expect(input.consume().direction, Direction.right);
    expect(input.consume().direction, Direction.none);
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
    input.consume();
    input.release();
    expect(input.consume().direction, Direction.none);

    input.setDirection(Direction.left);
    input.consume();
    input.consume();
    input.setDirection(Direction.down);
    input.consume();
    input.lift();
    expect(input.consume().direction, Direction.down);
    expect(input.consume().direction, Direction.down);
    expect(input.consume().direction, Direction.none);
  });
}
