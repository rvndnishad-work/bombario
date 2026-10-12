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
  /// exactly this far anyway: a quick tap nudges the player an eighth of a
  /// tile instead of a sliver (or nothing, if it fell between two ticks).
  static const double tapTiles = 1 / 8;

  /// Tiles the player covers in one tick right now, so a tap is an eighth
  /// of a tile at any speed. Set by the game once it has a player.
  double Function()? tilesPerTick;

  Direction _held = Direction.none;
  Direction _tap = Direction.none;
  double _tapLeft = 0;
  double _heldTiles = 0;
  bool _bombPressed = false;
  bool _actionPressed = false;
  PingKind _ping = PingKind.none;

  /// Below this a tap has walked its distance; float sums are never exact.
  static const double _eps = 1e-6;

  Direction get held => _held;

  /// The direction the next tick will move in, held or tapped.
  Direction get moving => _held != Direction.none
      ? _held
      : (_tapLeft > _eps ? _tap : Direction.none);

  double get _perTick =>
      tilesPerTick?.call() ?? Player.baseSpeed * World.tickDt;

  void setDirection(Direction d) {
    if (d != _held) _heldTiles = 0;
    _held = d;
    _tapLeft = 0;
  }

  /// Lets go without the tap top-up: pausing, or a key the game decided
  /// was held long enough already.
  void release() {
    _held = Direction.none;
    _heldTiles = 0;
  }

  /// A finger or key lifting: a press too short to walk [tapTiles] keeps
  /// walking until it has.
  void lift() {
    if (_held != Direction.none && _heldTiles < tapTiles - _eps) {
      _tap = _held;
      _tapLeft = tapTiles - _heldTiles;
    }
    release();
  }

  /// Walks a tap's worth in [d] once nothing is held: a tapped key.
  void tap(Direction d) {
    _tap = d;
    _tapLeft = max(_tapLeft, tapTiles);
  }

  void pressBomb() => _bombPressed = true;
  void pressAction() => _actionPressed = true;
  void pressPing(PingKind kind) => _ping = kind;

  /// Produces the input for one tick and clears the edge flags.
  PlayerInput consume() {
    final direction = moving;
    final per = _perTick;
    var walk = 1.0;
    if (_held != Direction.none) {
      _heldTiles += per;
    } else if (direction != Direction.none) {
      // The tap's last tick walks only what is left of it.
      if (per > _tapLeft) walk = _tapLeft / per;
      _tapLeft = max(0, _tapLeft - per);
    }
    final input = PlayerInput(
      direction: direction,
      placeBomb: _bombPressed,
      action: _actionPressed,
      ping: _ping,
      walk: walk,
    );
    _bombPressed = false;
    _actionPressed = false;
    _ping = PingKind.none;
    return input;
  }
}
