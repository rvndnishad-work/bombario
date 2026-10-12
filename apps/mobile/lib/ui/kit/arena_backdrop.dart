import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/sprite_atlas.dart';
import 'motion.dart';
import 'pixel_theme.dart';

/// The menus' living background: a dim maze drifting sideways, with a
/// bomber chased by a Puffball across the bottom now and then. Still (one
/// frame of the same scene) when looping motion is off.
class ArenaBackdrop extends StatefulWidget {
  const ArenaBackdrop({super.key, required this.child, this.chase = true});

  final Widget child;

  /// Whether the bomber-and-Puffball chase runs along the bottom.
  final bool chase;

  @override
  State<ArenaBackdrop> createState() => _ArenaBackdropState();
}

class _ArenaBackdropState extends State<ArenaBackdrop>
    with SingleTickerProviderStateMixin {
  /// One full loop: the maze scrolls one pillar pair and the chase crosses
  /// once.
  static const _loop = Duration(seconds: 12);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _loop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c
        ..stop()
        ..value = 0.35;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: CustomPaint(painter: _ArenaPainter(_c, chase: widget.chase)),
      ),
      widget.child,
    ],
  );
}

class _ArenaPainter extends CustomPainter {
  _ArenaPainter(this.t, {required this.chase}) : super(repaint: t);

  final Animation<double> t;
  final bool chase;

  static const double _tile = 40;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Px.ink);
    final atlas = SpriteAtlas.instance;
    if (atlas != null) {
      final dim = SpriteAtlas.faded(0.16);
      // Two tiles per scroll loop, so pillars stay on the classic grid.
      final shift = t.value * _tile * 2;
      final cols = (size.width / _tile).ceil() + 3;
      final rows = (size.height / _tile).ceil() + 1;
      for (var y = 0; y < rows; y++) {
        for (var x = -2; x < cols; x++) {
          final rect = Rect.fromLTWH(
            x * _tile + shift,
            y * _tile,
            _tile,
            _tile,
          );
          final pillar = x.isOdd && y.isOdd;
          final brick = !pillar && _brickAt(x, y);
          atlas.draw(
            canvas,
            pillar ? 'wall' : (brick ? 'brick' : 'floor'),
            rect,
            paint: dim,
          );
        }
      }
      if (chase) _chase(canvas, size, atlas);
    }
    // Darker towards the middle so menu text always reads.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Px.ink.withValues(alpha: 0.75),
            Px.ink.withValues(alpha: 0.2),
          ],
          radius: 0.9,
        ).createShader(Offset.zero & size),
    );
  }

  /// A fixed scatter of bricks, the same on every frame.
  static bool _brickAt(int x, int y) => ((x * 7 + y * 13) % 5) == 0;

  void _chase(Canvas canvas, Size size, SpriteAtlas atlas) {
    const s = 44.0;
    final span = size.width + s * 6;
    final x = t.value * span - s * 3;
    final y = size.height - s - 6;
    final step = (t.value * 160).floor().isEven;
    final hero = step ? 'p1-side-walk-a' : 'p1-side-walk-b';
    // The Puffball floats behind, bobbing.
    final bob = math.sin(t.value * math.pi * 24) * 3;
    final glow = SpriteAtlas.faded(0.9);
    atlas.draw(canvas, hero, Rect.fromLTWH(x, y, s, s), paint: glow);
    atlas.draw(
      canvas,
      'puff-side',
      Rect.fromLTWH(x - s * 1.8, y + bob.roundToDouble(), s, s),
      paint: glow,
    );
  }

  @override
  bool shouldRepaint(_ArenaPainter old) => old.chase != chase;
}
