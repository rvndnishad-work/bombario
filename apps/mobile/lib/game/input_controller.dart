import 'dart:math';

import 'package:bombario_core/bombario_core.dart';

/// Collects touch and keyboard (and later gamepad) input between simulation
/// ticks; see [KeyboardControls] for the keys.
///
/// Direction is a level (held), bomb and action are edges (pressed since the
/// last tick), and a short input buffer remembers a tap that lands just
/// before a junction so it still takes effect at the junction.
class InputController {
  /// A press shorter than this many tiles of walking is a tap, and walks
  /// this far anyway: a quick tap nudges the player a quarter tile instead
  /// of a sliver (or nothing, if it fell between two ticks).
  static const double tapTiles = 0.25;

  /// Tiles the player covers in one tick right now, so a tap is a quarter
  /// tile at any speed. Set by the game once it has a player.
  double Function()? tilesPerTick;

  Direction _held = Direction.none;
  Direction _tap = Direction.none;
  int _tapTicks = 0;
  int _heldTicks = 0;
  bool _bombPressed = false;
  bool _actionPressed = false;
  PingKind _ping = PingKind.none;

  Direction get held => _held;

  /// The direction the next tick will move in, held or tapped.
  Direction get moving =>
      _held != Direction.none ? _held : (_tapTicks > 0 ? _tap : Direction.none);

  /// Ticks a tap walks: [tapTiles] at the current speed, at least one.
  int get tapTicks {
    final per = tilesPerTick?.call() ?? Player.baseSpeed * World.tickDt;
    return max(1, (tapTiles / per).ceil());
  }

  void setDirection(Direction d) {
    if (d != _held) _heldTicks = 0;
    _held = d;
    _tapTicks = 0;
  }

  /// Lets go without the tap top-up: pausing, or a key the game decided
  /// was held long enough already.
  void release() {
    _held = Direction.none;
    _heldTicks = 0;
  }

  /// A finger or key lifting: a press too short to walk [tapTiles] keeps
  /// walking until it has.
  void lift() {
    if (_held != Direction.none && _heldTicks < tapTicks) {
      _tap = _held;
      _tapTicks = tapTicks - _heldTicks;
    }
    release();
  }

  /// Walks a tap's worth in [d] once nothing is held: a tapped key.
  void tap(Direction d) {
    _tap = d;
    _tapTicks = max(_tapTicks, tapTicks);
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
    if (_held != Direction.none) {
      _heldTicks++;
    } else if (_tapTicks > 0) {
      _tapTicks--;
    }
    _bombPressed = false;
    _actionPressed = false;
    _ping = PingKind.none;
    return input;
  }
}
