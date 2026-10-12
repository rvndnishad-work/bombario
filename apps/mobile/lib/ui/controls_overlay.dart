import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/input_controller.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';

/// Touch controls drawn see-through over the board (Arvind's in-game
/// layout): a joystick (or a D-pad) under the left thumb, bomb and action
/// buttons under the right, and in rooms a quick-chat ping button.
///
/// The stick stays put in the corner: it used to jump to wherever the thumb
/// landed, which made it shift under the thumb on every tap. Presses read
/// relative to its fixed centre.
///
/// The joystick turns drag into distance: dragging the knob from the
/// centre to the edge walks [stickTiles] tiles, a shorter drag
/// proportionally less, and holding it at the edge keeps walking. The
/// D-pad walks while an arm is held.
class ControlsOverlay extends StatefulWidget {
  const ControlsOverlay({
    super.key,
    required this.input,
    required this.actionLabel,
    this.pings = false,
    this.opacity = 1,
    this.scale = 1,
    this.leftHanded = false,
    this.haptics = true,
    this.joystick = true,
    this.stickTiles = 2,
  });

  final InputController input;

  /// What the Action button does right now (see
  /// [PlayerState.actionLabel]); null dims it.
  final ValueListenable<String?> actionLabel;

  /// Shows the ping button. Pings only mean something with teammates.
  final bool pings;

  /// Settings: how visible the controls are (0.3 to 1) and how big.
  final double opacity;
  final double scale;

  /// Swaps the D-pad and the buttons.
  final bool leftHanded;
  final bool haptics;

  /// The round joystick rather than the D-pad, and the tiles a full drag
  /// of it walks.
  final bool joystick;
  final double stickTiles;

  static String actionText(String? label) => switch (label) {
    'detonate' => 'Detonate',
    'tether' => 'Tether',
    'haunt' => 'Haunt',
    'pipe' => 'Pipe',
    _ => 'Action',
  };

  static const pingLabels = {
    PingKind.exitHere: 'Exit here!',
    PingKind.powerUp: 'Power-up!',
    PingKind.help: 'Help!',
    PingKind.run: 'Run!',
  };

  static const pingSprites = {
    PingKind.exitHere: 'exit',
    PingKind.powerUp: 'star',
    PingKind.help: 'ping-help',
    PingKind.run: 'ping-run',
  };

  @override
  State<ControlsOverlay> createState() => _ControlsOverlayState();
}

/// The mockups' see-through control style.
abstract final class _Ctl {
  static Color line(double o) => Px.paper.withValues(alpha: 0.55 * o);
  static Color fill(double o) => Px.ink.withValues(alpha: 0.32 * o);
  static Color fillHot(double o) => Px.paper.withValues(alpha: 0.28 * o);
}

class _ControlsOverlayState extends State<ControlsOverlay> {
  Offset? _padCentre;
  int? _padPointer;
  Direction _current = Direction.none;
  bool _wheelOpen = false;

  double get _padRadius => 70 * widget.scale;

  /// A press this close to the centre keeps the last direction, so the
  /// player doesn't stutter when the thumb rolls over the middle.
  double get _deadZone => _padRadius * 0.2;

  /// Presses further than this from the pad are not steering.
  double get _reach => _padRadius * 2.4;

  /// To switch between horizontal and vertical the thumb has to lean
  /// clearly the new way, so a diagonal thumb doesn't flicker between two.
  static const double _axisBias = 1.3;

  /// The direction [delta] from the centre leans: [_current] in the dead
  /// zone, and until the thumb leans clearly another way.
  Direction _lean(Offset delta) {
    if (delta.distance < _deadZone) return _current;
    final ax = delta.dx.abs();
    final ay = delta.dy.abs();
    final wasHorizontal =
        _current == Direction.left || _current == Direction.right;
    final wasVertical = _current == Direction.up || _current == Direction.down;
    final horizontal = wasHorizontal
        ? ay <= ax * _axisBias
        : wasVertical
        ? ax > ay * _axisBias
        : ax > ay;
    return horizontal
        ? (delta.dx > 0 ? Direction.right : Direction.left)
        : (delta.dy > 0 ? Direction.down : Direction.up);
  }

  void _updateDirection(Offset position) {
    final centre = _padCentre;
    if (centre == null) return;
    if (widget.joystick) {
      _updateStick(position - centre);
      return;
    }
    final next = _lean(position - centre);
    if (next != _current) {
      setState(() => _current = next);
      widget.input.setDirection(next);
      _haptic(HapticFeedback.selectionClick);
    }
  }

  // ---- Joystick

  /// Where the base sits while a thumb is down: under the thumb, where it
  /// landed. Idle, it rests where the D-pad would.
  Offset? _stickBase;

  /// Where the knob sits, relative to the base (at most [_rim]).
  Offset _knob = Offset.zero;

  /// The knob at the rim: walking in its direction until it comes back in.
  bool _atRim = false;

  /// Drag made in the dead zone before the stick had a direction.
  double _unspent = 0;

  /// How far the knob reaches from the centre.
  double get _rim => _padRadius * 0.85;

  void _updateStick(Offset delta) {
    final input = widget.input;
    final knob = delta.distance > _rim ? delta / delta.distance * _rim : delta;
    final moved = (knob - _knob).distance;
    final dir = _lean(knob);
    if (dir != _current && dir != Direction.none) {
      _haptic(HapticFeedback.selectionClick);
    }
    _current = dir;
    if (dir == Direction.none) {
      _unspent += moved;
    } else if (knob.distance >= _rim - 0.5) {
      // Pushed to the rim: keep walking. The player is already moving.
      if (!_atRim || input.held != dir) input.setDirection(dir, ease: false);
      _atRim = true;
      _unspent = 0;
    } else {
      if (_atRim) {
        // Back inside the rim: stop holding, and drag again.
        _atRim = false;
        input.release();
      }
      // Every bit of drag walks its share: centre to rim is [stickTiles].
      input.walk(dir, (moved + _unspent) * widget.stickTiles / _rim);
      _unspent = 0;
    }
    setState(() => _knob = knob);
  }

  void _haptic(Future<void> Function() f) {
    if (widget.haptics) f();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.opacity;
    final s = widget.scale;
    final pad = Expanded(
      child: LayoutBuilder(
        builder: (context, box) {
          // Resting spot: low in the outer corner.
          final rest = Offset(
            widget.leftHanded
                ? box.maxWidth - _padRadius - 28
                : _padRadius + 28,
            box.maxHeight - _padRadius - 24,
          );
          final centre = widget.joystick ? _stickBase ?? rest : rest;
          _padCentre = centre;
          return Listener(
            key: Key(widget.joystick ? 'joystick-area' : 'dpad-area'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              // One thumb steers; a second finger landing here is ignored.
              if (_padPointer != null) return;
              if ((e.localPosition - rest).distance > _reach) return;
              _padPointer = e.pointer;
              if (widget.joystick) {
                // The base floats to the thumb; drags read from there.
                setState(() => _stickBase = e.localPosition);
                return;
              }
              _updateDirection(e.localPosition);
            },
            onPointerMove: (e) {
              if (e.pointer == _padPointer) _updateDirection(e.localPosition);
            },
            onPointerUp: (e) {
              if (e.pointer == _padPointer) _releasePad();
            },
            onPointerCancel: (e) {
              if (e.pointer == _padPointer) _releasePad();
            },
            child: Stack(
              children: [
                Positioned(
                  left: centre.dx - _padRadius,
                  top: centre.dy - _padRadius,
                  child: widget.joystick
                      ? _StickVisual(
                          radius: _padRadius,
                          knob: _knob,
                          active: _padPointer != null,
                          atRim: _atRim,
                          opacity: o,
                        )
                      : _DPadVisual(
                          radius: _padRadius,
                          active: _current,
                          opacity: o,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final buttons = Positioned(
      right: widget.leftHanded ? null : 24,
      left: widget.leftHanded ? 24 : null,
      bottom: 20,
      child: Column(
        crossAxisAlignment: widget.leftHanded
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          if (widget.pings && _wheelOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final e in ControlsOverlay.pingLabels.entries)
                    _PingChip(
                      key: Key('ping-${e.key.name}'),
                      label: e.value,
                      sprite: ControlsOverlay.pingSprites[e.key]!,
                      onPressed: () {
                        _haptic(HapticFeedback.selectionClick);
                        widget.input.pressPing(e.key);
                        setState(() => _wheelOpen = false);
                      },
                    ),
                ],
              ),
            ),
          ValueListenableBuilder<String?>(
            valueListenable: widget.actionLabel,
            builder: (context, label, _) => AnimatedOpacity(
              opacity: label != null ? 1 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: _RoundButton(
                key: const Key('action-button'),
                size: 76 * s,
                ring: label == 'haunt' ? const Color(0xFFB388FF) : Px.ok,
                opacity: o,
                semantics: ControlsOverlay.actionText(label),
                onPressed: () {
                  _haptic(HapticFeedback.selectionClick);
                  widget.input.pressAction();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (label == 'pipe')
                      Icon(
                        Icons.south,
                        size: 24 * s,
                        color: Px.paper.withValues(alpha: 0.9 * o),
                      )
                    else
                      SpriteIcon(
                        label == 'haunt'
                            ? 'spirit'
                            : label == 'tether'
                            ? 'icon-tether'
                            : 'remote',
                        size: 24 * s,
                        opacity: 0.9 * o,
                      ),
                    Text(
                      ControlsOverlay.actionText(label).toUpperCase(),
                      style: Px.label(
                        9 * s,
                        color: Px.paper.withValues(alpha: 0.92 * o),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 10 * s),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.pings && !widget.leftHanded) ...[
                _pingButton(o, s),
                SizedBox(width: 12 * s),
              ],
              _RoundButton(
                key: const Key('bomb-button'),
                size: 100 * s,
                ring: Px.danger,
                opacity: o,
                semantics: 'Drop bomb',
                onPressed: () {
                  _haptic(HapticFeedback.lightImpact);
                  widget.input.pressBomb();
                },
                child: SpriteIcon('bomb', size: 52 * s, opacity: 0.95 * o),
              ),
              if (widget.pings && widget.leftHanded) ...[
                SizedBox(width: 12 * s),
                _pingButton(o, s),
              ],
            ],
          ),
        ],
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: widget.leftHanded
                ? [const Expanded(child: SizedBox()), pad]
                : [pad, const Expanded(child: SizedBox())],
          ),
        ),
        buttons,
      ],
    );
  }

  Widget _pingButton(double o, double s) => _RoundButton(
    key: const Key('ping-button'),
    size: 58 * s,
    ring: Px.paper,
    opacity: o,
    semantics: 'Quick chat',
    onPressed: () => setState(() => _wheelOpen = !_wheelOpen),
    child: Icon(
      Icons.chat_bubble,
      size: 22 * s,
      color: Px.paper.withValues(alpha: 0.9 * o),
    ),
  );

  void _releasePad() {
    _padPointer = null;
    setState(() {
      _current = Direction.none;
      _knob = Offset.zero;
      _stickBase = null;
      _atRim = false;
    });
    _unspent = 0;
    if (widget.joystick) {
      // Stops a rim hold; a drag's last bit of budget (under a tile) walks.
      widget.input.release();
    } else {
      widget.input.lift();
    }
  }
}

/// A round base with a knob that follows the thumb, lit at the rim.
class _StickVisual extends StatelessWidget {
  const _StickVisual({
    required this.radius,
    required this.knob,
    required this.active,
    required this.atRim,
    required this.opacity,
  });

  final double radius;
  final Offset knob;
  final bool active;
  final bool atRim;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final knobRadius = radius * 0.42;
    Widget chevron(String sprite, Alignment alignment) => Align(
      alignment: alignment,
      child: Padding(
        padding: EdgeInsets.all(radius * 0.08),
        child: SpriteIcon(sprite, size: radius * 0.32, opacity: 0.6 * opacity),
      ),
    );
    return IgnorePointer(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _Ctl.fill(opacity),
                border: Border.all(color: _Ctl.line(opacity), width: 2),
              ),
            ),
            chevron('arrow-up', Alignment.topCenter),
            chevron('arrow-down', Alignment.bottomCenter),
            chevron('arrow-left', Alignment.centerLeft),
            chevron('arrow-right', Alignment.centerRight),
            Positioned(
              key: const Key('stick-knob'),
              left: radius + knob.dx - knobRadius,
              top: radius + knob.dy - knobRadius,
              child: Container(
                width: knobRadius * 2,
                height: knobRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? _Ctl.fillHot(opacity) : _Ctl.fill(opacity),
                  border: Border.all(
                    color: atRim
                        ? Px.paper.withValues(alpha: opacity)
                        : _Ctl.line(opacity),
                    width: atRim ? 4 : 3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DPadVisual extends StatelessWidget {
  const _DPadVisual({
    required this.radius,
    required this.active,
    required this.opacity,
  });

  final double radius;
  final Direction active;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final cell = radius * 0.72;
    Widget key(Direction d, String sprite, Alignment alignment) => Align(
      alignment: alignment,
      child: Container(
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: active == d ? _Ctl.fillHot(opacity) : _Ctl.fill(opacity),
          border: Border.all(color: _Ctl.line(opacity), width: 2),
        ),
        alignment: Alignment.center,
        child: SpriteIcon(
          sprite,
          size: cell * 0.7,
          opacity: (active == d ? 1 : 0.75) * opacity,
        ),
      ),
    );
    return IgnorePointer(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: cell,
                height: cell,
                color: _Ctl.fill(opacity),
              ),
            ),
            key(Direction.up, 'arrow-up', Alignment.topCenter),
            key(Direction.down, 'arrow-down', Alignment.bottomCenter),
            key(Direction.left, 'arrow-left', Alignment.centerLeft),
            key(Direction.right, 'arrow-right', Alignment.centerRight),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.size,
    required this.ring,
    required this.opacity,
    required this.onPressed,
    required this.child,
    required this.semantics,
  });

  final double size;
  final Color ring;
  final double opacity;
  final VoidCallback onPressed;
  final Widget child;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      child: Listener(
        onPointerDown: (_) => onPressed(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ring.withValues(alpha: 0.16 * opacity),
            border: Border.all(
              color: ring.withValues(alpha: 0.7 * opacity),
              width: 3,
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

class _PingChip extends StatelessWidget {
  const _PingChip({
    super.key,
    required this.label,
    required this.sprite,
    required this.onPressed,
  });

  final String label;
  final String sprite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Px.night.withValues(alpha: 0.9),
          border: Border.all(color: Px.edge, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpriteIcon(sprite, size: 20),
            const SizedBox(width: 6),
            Text(label, style: Px.label(12)),
          ],
        ),
      ),
    );
  }
}
