import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/blast_game.dart';

/// Touch controls: a floating D-pad under the left thumb, bomb and action
/// buttons under the right thumb. Pure Flutter widgets over the game.
class ControlsOverlay extends StatefulWidget {
  const ControlsOverlay({super.key, required this.game});

  final BlastGame game;

  @override
  State<ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<ControlsOverlay> {
  Offset? _padOrigin;
  Direction _current = Direction.none;

  static const double _deadZone = 12;
  static const double _padRadius = 70;

  void _updateDirection(Offset position) {
    final origin = _padOrigin;
    if (origin == null) return;
    final delta = position - origin;
    Direction next;
    if (delta.distance < _deadZone) {
      // Inside the dead zone keep the last direction so the player doesn't
      // stutter when the thumb drifts back towards the centre.
      next = _current;
    } else if (delta.dx.abs() > delta.dy.abs()) {
      next = delta.dx > 0 ? Direction.right : Direction.left;
    } else {
      next = delta.dy > 0 ? Direction.down : Direction.up;
    }
    if (next != _current) {
      setState(() => _current = next);
      widget.game.input.setDirection(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Stack(
      children: [
        // Left half: floating D-pad.
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    setState(() => _padOrigin = e.localPosition);
                    _updateDirection(e.localPosition);
                  },
                  onPointerMove: (e) => _updateDirection(e.localPosition),
                  onPointerUp: (_) => _releasePad(),
                  onPointerCancel: (_) => _releasePad(),
                  child: Stack(
                    children: [
                      if (_padOrigin != null)
                        Positioned(
                          left: _padOrigin!.dx - _padRadius,
                          top: _padOrigin!.dy - _padRadius,
                          child:
                              _DPadVisual(radius: _padRadius, active: _current),
                        ),
                    ],
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
        // Right side: bomb and action buttons.
        Positioned(
          right: 28,
          bottom: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ListenableBuilder(
                listenable: game.hud,
                builder: (context, _) => AnimatedOpacity(
                  opacity: game.hud.remote ? 1 : 0.15,
                  duration: const Duration(milliseconds: 200),
                  child: _RoundButton(
                    label: '⚡',
                    size: 56,
                    color: Colors.amber,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      game.input.pressAction();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _RoundButton(
                label: '💣',
                size: 84,
                color: Colors.redAccent,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  game.input.pressBomb();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _releasePad() {
    setState(() {
      _padOrigin = null;
      _current = Direction.none;
    });
    widget.game.input.release();
  }
}

class _DPadVisual extends StatelessWidget {
  const _DPadVisual({required this.radius, required this.active});

  final double radius;
  final Direction active;

  @override
  Widget build(BuildContext context) {
    Widget arrow(Direction d, IconData icon, Alignment alignment) => Align(
          alignment: alignment,
          child: Icon(
            icon,
            size: 36,
            color: active == d ? Colors.white : Colors.white54,
          ),
        );
    return IgnorePointer(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black26,
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Stack(
          children: [
            arrow(Direction.up, Icons.keyboard_arrow_up, Alignment.topCenter),
            arrow(Direction.down, Icons.keyboard_arrow_down,
                Alignment.bottomCenter),
            arrow(Direction.left, Icons.keyboard_arrow_left,
                Alignment.centerLeft),
            arrow(Direction.right, Icons.keyboard_arrow_right,
                Alignment.centerRight),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.size,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final double size;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPressed(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.75),
          border: Border.all(color: Colors.white54, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: size * 0.42)),
      ),
    );
  }
}
