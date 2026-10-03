import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/services.dart';

/// Collects touch, keyboard (and later gamepad) input between simulation
/// ticks.
///
/// Direction is a level (held), bomb and action are edges (pressed since the
/// last tick), and a short input buffer remembers a tap that lands just
/// before a junction so it still takes effect at the junction.
class InputController {
  Direction _held = Direction.none;
  bool _bombPressed = false;
  bool _actionPressed = false;
  PingKind _ping = PingKind.none;

  /// Direction keys currently down, most recent last: releasing one falls
  /// back to the one still held, like a classic keyboard-driven game.
  final List<Direction> _keysDown = [];

  Direction get held => _held;

  void setDirection(Direction d) => _held = d;
  void release() {
    _held = Direction.none;
    _keysDown.clear();
  }

  void pressBomb() => _bombPressed = true;
  void pressAction() => _actionPressed = true;
  void pressPing(PingKind kind) => _ping = kind;

  static final Map<LogicalKeyboardKey, Direction> directionKeys = {
    LogicalKeyboardKey.arrowUp: Direction.up,
    LogicalKeyboardKey.arrowDown: Direction.down,
    LogicalKeyboardKey.arrowLeft: Direction.left,
    LogicalKeyboardKey.arrowRight: Direction.right,
    LogicalKeyboardKey.keyW: Direction.up,
    LogicalKeyboardKey.keyS: Direction.down,
    LogicalKeyboardKey.keyA: Direction.left,
    LogicalKeyboardKey.keyD: Direction.right,
  };

  static final Set<LogicalKeyboardKey> bombKeys = {LogicalKeyboardKey.space};

  static final Set<LogicalKeyboardKey> actionKeys = {
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  static final Set<LogicalKeyboardKey> pauseKeys = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.keyP,
  };

  /// Keyboard controls: arrows or WASD move, Space drops a bomb, X / Enter /
  /// Shift is the Action button and Esc / P pauses. Returns whether the key
  /// was one of ours.
  bool handleKey(KeyEvent event, {void Function()? onPause}) {
    final key = event.logicalKey;
    final dir = directionKeys[key];
    if (dir != null) {
      if (event is KeyDownEvent) {
        _keysDown
          ..remove(dir)
          ..add(dir);
      } else if (event is KeyUpEvent) {
        _keysDown.remove(dir);
      }
      _held = _keysDown.isEmpty ? Direction.none : _keysDown.last;
      return true;
    }
    // Key repeat should not machine-gun bombs or toggle pause.
    if (event is! KeyDownEvent) {
      return bombKeys.contains(key) ||
          actionKeys.contains(key) ||
          pauseKeys.contains(key);
    }
    if (bombKeys.contains(key)) {
      pressBomb();
      return true;
    }
    if (actionKeys.contains(key)) {
      pressAction();
      return true;
    }
    if (pauseKeys.contains(key) && onPause != null) {
      onPause();
      return true;
    }
    return false;
  }

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
