import 'package:flutter/material.dart';

import '../../game/sprite_atlas.dart';

/// One pixel-art sprite from the atlas, for menus and the toolbar. Draws
/// nothing until [SpriteAtlas.load] has finished.
class SpriteIcon extends StatelessWidget {
  const SpriteIcon(this.name, {super.key, this.size = 24, this.opacity = 1});

  final String name;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _SpritePainter(name, opacity)),
  );
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.name, this.opacity);

  final String name;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    SpriteAtlas.instance?.draw(
      canvas,
      name,
      Offset.zero & size,
      paint: opacity < 1 ? SpriteAtlas.faded(opacity) : null,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.name != name || old.opacity != opacity;
}
