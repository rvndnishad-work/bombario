import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'sprite_atlas.g.dart';

/// The game's 16x16 pixel-art sprites, packed into one image by
/// `tools/sprites/build.py` from the UI mockups plus the extra sprites drawn
/// for the game.
///
/// Load it once with [load]; after that [instance] serves the renderer and
/// the [SpriteIcon] widgets in menus and the toolbar.
class SpriteAtlas {
  SpriteAtlas(this.image);

  static const asset = 'assets/images/sprites.png';

  final ui.Image image;

  static SpriteAtlas? instance;
  static Future<SpriteAtlas>? _loading;

  /// Decodes the atlas once and keeps it for the rest of the app run.
  static Future<SpriteAtlas> load({AssetBundle? bundle}) {
    final existing = instance;
    if (existing != null) return Future.value(existing);
    return _loading ??= () async {
      final data = await (bundle ?? rootBundle).load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return instance = SpriteAtlas(frame.image);
    }();
  }

  static bool has(String name) => spriteIndex.containsKey(name);

  /// Nearest-neighbour sampling keeps the pixels crisp at any scale.
  static final ui.Paint _crisp = ui.Paint()
    ..filterQuality = ui.FilterQuality.none
    ..isAntiAlias = false;

  /// A paint that draws sprites see-through.
  static ui.Paint faded(double opacity) => ui.Paint()
    ..filterQuality = ui.FilterQuality.none
    ..isAntiAlias = false
    ..color = ui.Color.fromRGBO(0, 0, 0, opacity.clamp(0, 1));

  static ui.Rect source(int index) => ui.Rect.fromLTWH(
    (index % spriteColumns) * spriteCell.toDouble(),
    (index ~/ spriteColumns) * spriteCell.toDouble(),
    spriteCell.toDouble(),
    spriteCell.toDouble(),
  );

  /// Draws [name] into [dst]. Returns false when there is no such sprite so
  /// callers can fall back to a placeholder shape.
  bool draw(ui.Canvas canvas, String name, ui.Rect dst, {ui.Paint? paint}) {
    final index = spriteIndex[name];
    if (index == null) return false;
    canvas.drawImageRect(image, source(index), dst, paint ?? _crisp);
    return true;
  }
}
