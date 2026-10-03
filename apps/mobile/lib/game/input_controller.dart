import 'package:bombario_core/bombario_core.dart';

/// Collects touch (and later gamepad) input between simulation ticks.
///
/// Direction is a level (held), bomb and action are edges (pressed since the
/// last tick), and a short input buffer remembers a tap that lands just
/// before a junction so it still takes effect at the junction.
class InputController {
  Direction _held = Direction.none;
  bool _bombPressed = false;
  bool _actionPressed = false;

  Direction get held => _held;

  void setDirection(Direction d) => _held = d;
  void release() => _held = Direction.none;
  void pressBomb() => _bombPressed = true;
  void pressAction() => _actionPressed = true;

  /// Produces the input for one tick and clears the edge flags.
  PlayerInput consume() {
    final input = PlayerInput(
      direction: _held,
      placeBomb: _bombPressed,
      action: _actionPressed,
    );
    _bombPressed = false;
    _actionPressed = false;
    return input;
  }
}
