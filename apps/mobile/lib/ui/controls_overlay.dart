import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/input_controller.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';

/// Touch controls drawn see-through over the board (Arvind's in-game
/// layout): a D-pad under the left thumb, bomb and action buttons under the
/// right, and in rooms a quick-chat ping button.
///
/// The D-pad stays put in the corner: it used to jump to wherever the thumb
/// landed, which made it shift under the thumb on every tap. Presses read
/// relative to its fixed centre, so pressing an arm (or past it) steers.
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

  void _updateDirection(Offset position) {
    final centre = _padCentre;
    if (centre == null) return;
    final delta = position - centre;
    final ax = delta.dx.abs();
    final ay = delta.dy.abs();
    Direction next;
    if (delta.distance < _deadZone) {
      next = _current;
    } else {
      final wasHorizontal =
          _current == Direction.left || _current == Direction.right;
      final wasVertical =
          _current == Direction.up || _current == Direction.down;
      final horizontal = wasHorizontal
          ? ay <= ax * _axisBias
          : wasVertical
          ? ax > ay * _axisBias
          : ax > ay;
      next = horizontal
          ? (delta.dx > 0 ? Direction.right : Direction.left)
          : (delta.dy > 0 ? Direction.down : Direction.up);
    }
    if (next != _current) {
      setState(() => _current = next);
      widget.input.setDirection(next);
      _haptic(HapticFeedback.selectionClick);
    }
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
          _padCentre = rest;
          return Listener(
            key: const Key('dpad-area'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              // One thumb steers; a second finger landing here is ignored.
              if (_padPointer != null) return;
              if ((e.localPosition - rest).distance > _reach) return;
              _padPointer = e.pointer;
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
                  left: rest.dx - _padRadius,
                  top: rest.dy - _padRadius,
                  child: _DPadVisual(
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
    setState(() => _current = Direction.none);
    widget.input.lift();
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
