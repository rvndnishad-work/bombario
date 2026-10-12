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

  /// Wall clock for timing presses; tests replace it.
  static DateTime Function() clock = DateTime.now;

  @override
  State<KeyboardControls> createState() => _KeyboardControlsState();
}

class _KeyboardControlsState extends State<KeyboardControls> {
  /// Direction keys held down, oldest first.
  final List<LogicalKeyboardKey> _held = [];

  /// Some keyboards (the Android emulator's, notably) send every host key
  /// press as an instant press+release pair, tapped or held: one at once,
  /// then auto-repeats after the host's repeat delay. A release this soon
  /// after its press is one of those; a real keyboard releases when the
  /// finger lifts.
  static const _instant = Duration(milliseconds: 60);

  /// A pair this soon after the last one is an auto-repeat (about 30 a
  /// second on Windows); a person can't tap that fast. A lone pair is a
  /// tap and walks exactly a tap's distance, so taps stay predictable: a
  /// held key on such a keyboard takes one tap's step, waits out the
  /// host's repeat delay, then walks.
  static const _repeatGap = Duration(milliseconds: 100);

  /// How long to keep walking after a repeated pair, so a held key walks
  /// smoothly through the short gaps between repeats.
  static const _bridgeRepeat = Duration(milliseconds: 120);

  final Map<LogicalKeyboardKey, DateTime> _downAt = {};
  final Map<LogicalKeyboardKey, DateTime> _upAt = {};
  final Set<LogicalKeyboardKey> _instantUp = {};
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

  /// [lifted] is a real finger lifting, which may still owe a tap's step.
  void _letGo(LogicalKeyboardKey key, {bool lifted = false}) {
    _lateRelease.remove(key)?.cancel();
    _held.remove(key);
    _steer(lifted: lifted);
  }

  /// [ease] false for an auto-repeat, which carries on a hold rather than
  /// starting a press.
  void _steer({bool lifted = false, bool ease = true}) {
    if (_held.isNotEmpty) {
      widget.input.setDirection(
        KeyboardControls.directions[_held.last]!,
        ease: ease,
      );
    } else if (lifted) {
      widget.input.lift();
    } else {
      widget.input.release();
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
        final now = KeyboardControls.clock();
        // Pressed again hard on an instant release: an auto-repeat.
        final lastUp = _upAt[key];
        if (lastUp != null &&
            _instantUp.contains(key) &&
            now.difference(lastUp) < _repeatGap) {
          _repeating.add(key);
        } else {
          _repeating.remove(key);
        }
        _downAt[key] = now;
        _held
          ..remove(key)
          ..add(key);
        _steer(ease: !_repeating.contains(key));
      } else if (event is KeyUpEvent) {
        final now = KeyboardControls.clock();
        final heldFor = now.difference(_downAt[key] ?? DateTime(0));
        _upAt[key] = now;
        if (heldFor < _instant) {
          _instantUp.add(key);
        } else {
          _instantUp.remove(key);
        }
        if (heldFor < _instant && _repeating.contains(key)) {
          // Keep walking between repeats.
          _lateRelease[key] = Timer(_bridgeRepeat, () => _letGo(key));
        } else {
          _letGo(key, lifted: true);
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
