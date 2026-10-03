import 'dart:async';

import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../game/input_controller.dart';

/// Keyboard play, for hardware keyboards, emulators and accessibility
/// switches: arrow keys (or WASD) move, Space drops a bomb, X or Enter is
/// the Action button, Escape or P pauses.
///
/// Wraps the game area; key presses from anything focused inside it bubble
/// up here. Holding two arrows moves the most recently pressed one, and
/// letting go of it falls back to the one still held.
class KeyboardControls extends StatefulWidget {
  const KeyboardControls({
    super.key,
    required this.input,
    required this.child,
    this.onPause,
  });

  final InputController input;
  final VoidCallback? onPause;
  final Widget child;

  static final Map<LogicalKeyboardKey, Direction> directions = {
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
    LogicalKeyboardKey.numpadEnter,
  };

  static final Set<LogicalKeyboardKey> pauseKeys = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.keyP,
  };

  @override
  State<KeyboardControls> createState() => _KeyboardControlsState();
}

class _KeyboardControlsState extends State<KeyboardControls> {
  /// Direction keys held down, oldest first.
  final List<LogicalKeyboardKey> _held = [];

  /// A quick tap still walks for at least this long. Otherwise a press that
  /// starts and ends between two simulation ticks moves the player a sliver
  /// or not at all, and the arrow keys feel dead.
  static const _minPress = Duration(milliseconds: 160);

  final Map<LogicalKeyboardKey, DateTime> _downAt = {};
  final Map<LogicalKeyboardKey, Timer> _lateRelease = {};

  @override
  void dispose() {
    for (final t in _lateRelease.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _releaseAll() {
    for (final t in _lateRelease.values) {
      t.cancel();
    }
    _lateRelease.clear();
    _held.clear();
    widget.input.release();
  }

  void _letGo(LogicalKeyboardKey key) {
    _lateRelease.remove(key)?.cancel();
    _held.remove(key);
    _steer();
  }

  void _steer() {
    if (_held.isEmpty) {
      widget.input.release();
    } else {
      widget.input.setDirection(KeyboardControls.directions[_held.last]!);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    // A focused menu button (pause, game over) keeps the keys: arrows move
    // between buttons and Space/Enter press them. Anything that can be
    // activated has an ActivateIntent action above its focus node.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && Actions.maybeFind<ActivateIntent>(focused) != null) {
      if (_held.isNotEmpty) _releaseAll();
      return KeyEventResult.ignored;
    }
    if (KeyboardControls.directions.containsKey(key)) {
      if (event is KeyDownEvent) {
        _lateRelease.remove(key)?.cancel();
        _downAt[key] = DateTime.now();
        _held
          ..remove(key)
          ..add(key);
        _steer();
      } else if (event is KeyUpEvent) {
        final heldFor = DateTime.now().difference(_downAt[key] ?? DateTime(0));
        if (heldFor < _minPress) {
          _lateRelease[key] = Timer(_minPress - heldFor, () => _letGo(key));
        } else {
          _letGo(key);
        }
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return KeyboardControls.bombKeys.contains(key) ||
              KeyboardControls.actionKeys.contains(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (KeyboardControls.bombKeys.contains(key)) {
      widget.input.pressBomb();
      return KeyEventResult.handled;
    }
    if (KeyboardControls.actionKeys.contains(key)) {
      widget.input.pressAction();
      return KeyEventResult.handled;
    }
    if (KeyboardControls.pauseKeys.contains(key) && widget.onPause != null) {
      _releaseAll();
      widget.onPause!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    // Keyboard only: as a semantics node it would merge the labels of the
    // popups and buttons inside, hiding them from screen readers.
    includeSemantics: false,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}
