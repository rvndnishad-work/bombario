import 'package:bombario_core/bombario_core.dart';

/// Collects touch and keyboard (and later gamepad) input between simulation
/// ticks; see [KeyboardControls] for the keys.
///
/// Direction is a level (held), bomb and action are edges (pressed since the
/// last tick), and a short input buffer remembers a tap that lands just
/// before a junction so it still takes effect at the junction.
class InputController {
  /// How many ticks a tap walks: about a fifth of a tile at base speed, so
  /// a quick tap nudges the player instead of crossing a whole tile.
  static const tapTicks = 2;

  Direction _held = Direction.none;
  Direction _tap = Direction.none;
  int _tapTicks = 0;
  bool _bombPressed = false;
  bool _actionPressed = false;
  PingKind _ping = PingKind.none;

  Direction get held => _held;

  /// The direction the next tick will move in, held or tapped.
  Direction get moving =>
      _held != Direction.none ? _held : (_tapTicks > 0 ? _tap : Direction.none);

  void setDirection(Direction d) {
    _held = d;
    _tapTicks = 0;
  }

  void release() => _held = Direction.none;

  /// Walks [ticks] ticks in [d] once nothing is held: a tapped key.
  void tap(Direction d, {int ticks = tapTicks}) {
    _tap = d;
    _tapTicks = ticks;
  }

  void pressBomb() => _bombPressed = true;
  void pressAction() => _actionPressed = true;
  void pressPing(PingKind kind) => _ping = kind;

  /// Produces the input for one tick and clears the edge flags.
  PlayerInput consume() {
    final input = PlayerInput(
      direction: moving,
      placeBomb: _bombPressed,
      action: _actionPressed,
      ping: _ping,
    );
    if (_held == Direction.none && _tapTicks > 0) _tapTicks--;
    _bombPressed = false;
    _actionPressed = false;
    _ping = PingKind.none;
    return input;
  }
}
