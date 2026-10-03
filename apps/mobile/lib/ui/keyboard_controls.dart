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

  /// Some keyboards (the Android emulator's, notably) send a held key as a
  /// burst of instant press+release pairs: one at once, then auto-repeats
  /// after the host's repeat delay (half a second by default). A release
  /// this soon after its press is one of those, or a quick tap.
  static const _instant = Duration(milliseconds: 60);

  /// A press that comes this soon after the last release is an auto-repeat
  /// of a held key, not a new tap.
  static const _repeatGap = Duration(milliseconds: 600);

  /// How long to keep walking after a repeated pair, so a held key walks
  /// smoothly through the short gaps between repeats.
  static const _bridgeRepeat = Duration(milliseconds: 150);

  final Map<LogicalKeyboardKey, DateTime> _downAt = {};
  final Map<LogicalKeyboardKey, DateTime> _upAt = {};
  final Set<LogicalKeyboardKey> _repeating = {};
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
        final now = DateTime.now();
        // Pressed again right after an instant release: an auto-repeat.
        final lastUp = _upAt[key];
        if (lastUp != null && now.difference(lastUp) < _repeatGap) {
          _repeating.add(key);
        } else {
          _repeating.remove(key);
        }
        _downAt[key] = now;
        _held
          ..remove(key)
          ..add(key);
        _steer();
      } else if (event is KeyUpEvent) {
        final now = DateTime.now();
        final heldFor = now.difference(_downAt[key] ?? DateTime(0));
        _upAt[key] = now;
        if (heldFor < _instant && _repeating.contains(key)) {
          _lateRelease[key] = Timer(_bridgeRepeat, () => _letGo(key));
        } else {
          _letGo(key);
          // A tap would otherwise start and end between two simulation
          // ticks and move the player a sliver or not at all, so it walks
          // a short, fixed step instead (until a repeat says it is held).
          if (heldFor < _instant && _held.isEmpty) {
            widget.input.tap(KeyboardControls.directions[key]!);
          }
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
