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

  /// The host's key-repeat delay as last observed: the gap between the
  /// first instant pair of a held key and its first auto-repeat. Shared by
  /// every game screen for the life of the app, so one learning hold
  /// tunes the rest. Starts at Windows' default.
  static Duration hostRepeatDelay = const Duration(milliseconds: 500);

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

  /// The first pair can't tell a tap from a hold, so it keeps walking
  /// until a repeat would have arrived, plus this slack: a hold must never
  /// pause (the owner's call), at the cost of a tap on such a keyboard
  /// walking for the whole repeat delay.
  static const _bridgeSlack = Duration(milliseconds: 60);

  /// How long to keep walking after a repeated pair, so a held key walks
  /// smoothly through the short gaps between repeats.
  static const _bridgeRepeat = Duration(milliseconds: 150);

  /// A press this soon after an instant release is an auto-repeat; hosts
  /// allow repeat delays up to about a second.
  static const _maxRepeatDelay = Duration(milliseconds: 1100);
  static const _minRepeatDelay = Duration(milliseconds: 120);

  /// Auto-repeats arrive this close together (30 a second on Windows); a
  /// human can't double-tap that fast, so two in a row prove a hold.
  static const _repeatBurst = Duration(milliseconds: 120);

  final Map<LogicalKeyboardKey, DateTime> _downAt = {};
  final Map<LogicalKeyboardKey, DateTime> _upAt = {};
  final Set<LogicalKeyboardKey> _instantUp = {};
  final Set<LogicalKeyboardKey> _repeating = {};
  final Map<LogicalKeyboardKey, DateTime> _runStart = {};
  final Map<LogicalKeyboardKey, Duration> _pendingDelay = {};
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

  void _steer({bool lifted = false}) {
    if (_held.isNotEmpty) {
      widget.input.setDirection(KeyboardControls.directions[_held.last]!);
    } else if (lifted) {
      widget.input.lift();
    } else {
      widget.input.release();
    }
  }

  /// Learns the host's repeat delay from a run of instant pairs: the gap
  /// to the first repeat, confirmed by a second repeat hard on its heels.
  void _noteRepeat(LogicalKeyboardKey key, DateTime now) {
    final pending = _pendingDelay[key];
    if (pending == null) {
      final start = _runStart[key];
      if (start != null) _pendingDelay[key] = now.difference(start);
      return;
    }
    final lastDown = _downAt[key];
    if (lastDown != null && now.difference(lastDown) < _repeatBurst) {
      if (pending > _minRepeatDelay && pending < _maxRepeatDelay) {
        KeyboardControls.hostRepeatDelay = pending;
      }
      _pendingDelay.remove(key);
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
        // Pressed again soon after an instant release: an auto-repeat.
        final lastUp = _upAt[key];
        if (lastUp != null &&
            _instantUp.contains(key) &&
            now.difference(lastUp) < _maxRepeatDelay) {
          _noteRepeat(key, now);
          _repeating.add(key);
        } else {
          _repeating.remove(key);
          _pendingDelay.remove(key);
          _runStart[key] = now;
        }
        _downAt[key] = now;
        _held
          ..remove(key)
          ..add(key);
        _steer();
      } else if (event is KeyUpEvent) {
        final now = KeyboardControls.clock();
        final heldFor = now.difference(_downAt[key] ?? DateTime(0));
        _upAt[key] = now;
        if (heldFor < _instant) {
          _instantUp.add(key);
          // Keep walking: through the host's repeat delay after the first
          // pair, and between repeats after that.
          final bridge = _repeating.contains(key)
              ? _bridgeRepeat
              : KeyboardControls.hostRepeatDelay + _bridgeSlack;
          _lateRelease[key] = Timer(bridge, () => _letGo(key));
        } else {
          _instantUp.remove(key);
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
