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
  PingKind _ping = PingKind.none;

  Direction get held => _held;

  void setDirection(Direction d) => _held = d;
  void release() => _held = Direction.none;
  void pressBomb() => _bombPressed = true;
  void pressAction() => _actionPressed = true;
  void pressPing(PingKind kind) => _ping = kind;

  /// Produces the input for one tick and clears the edge flags.
  PlayerInput consume() {
    final input = PlayerInput(
      direction: _held,
      placeBomb: _bombPressed,
      action: _actionPressed,
      ping: _ping,
    );
    _bombPressed = false;
    _actionPressed = false;
    _ping = PingKind.none;
    return input;
  }
}
