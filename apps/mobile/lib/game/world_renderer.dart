import 'dart:math' as math;
import 'dart:ui';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';

/// Draws the whole simulation in immediate mode with placeholder shapes.
///
/// Phase 0 is about feel, not looks: pillars, bricks, bombs, flames, items,
/// the player and enemies are flat coloured primitives. Sprites replace this
/// in the art pass without touching the rules.
class WorldRenderer extends PositionComponent {
  WorldRenderer(this.sim, {required this.tileSize});

  final core.World sim;
  final double tileSize;

  static final _floor = Paint()..color = const Color(0xFF3FA34D);
  static final _floorAlt = Paint()..color = const Color(0xFF399A47);
  static final _pillar = Paint()..color = const Color(0xFFBDBDBD);
  static final _pillarEdge = Paint()..color = const Color(0xFF8A8A8A);
  static final _brick = Paint()..color = const Color(0xFFB5651D);
  static final _brickLine = Paint()
    ..color = const Color(0xFF7A4312)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final _bomb = Paint()..color = const Color(0xFF111111);
  static final _bombHot = Paint()..color = const Color(0xFFD32F2F);
  static final _fuse = Paint()..color = const Color(0xFFFFC107);
  static final _flameOuter = Paint()..color = const Color(0xFFFF7043);
  static final _flameInner = Paint()..color = const Color(0xFFFFF176);
  static final _player = Paint()..color = const Color(0xFFFFFFFF);
  static final _playerSuit = Paint()..color = const Color(0xFF1E88E5);
  static final _playerHit = Paint()..color = const Color(0xFF9E9E9E);
  static final _enemy = Paint()..color = const Color(0xFFF48FB1);
  static final _enemyEye = Paint()..color = const Color(0xFF000000);
  static final _item = Paint()..color = const Color(0xFFFFEB3B);
  static final _itemEdge = Paint()
    ..color = const Color(0xFF000000)
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  static final _exit = Paint()..color = const Color(0xFF263238);
  static final _exitDoor = Paint()..color = const Color(0xFF8D6E63);

  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  Rect _tileRect(num x, num y, [double inset = 0]) => Rect.fromLTWH(
        x * tileSize + inset,
        y * tileSize + inset,
        tileSize - inset * 2,
        tileSize - inset * 2,
      );

  @override
  void render(Canvas canvas) {
    final grid = sim.grid;
    for (var y = 0; y < grid.height; y++) {
      for (var x = 0; x < grid.width; x++) {
        final r = _tileRect(x, y);
        switch (grid.at(x, y)) {
          case core.TileType.floor:
            canvas.drawRect(r, (x + y).isEven ? _floor : _floorAlt);
          case core.TileType.pillar:
            canvas.drawRect(r, _pillarEdge);
            canvas.drawRect(_tileRect(x, y, 2), _pillar);
          case core.TileType.brick:
            canvas.drawRect(r, _brick);
            final third = tileSize / 3;
            canvas.drawLine(Offset(r.left, r.top + third),
                Offset(r.right, r.top + third), _brickLine);
            canvas.drawLine(Offset(r.left, r.top + 2 * third),
                Offset(r.right, r.top + 2 * third), _brickLine);
            canvas.drawLine(Offset(r.center.dx, r.top),
                Offset(r.center.dx, r.top + third), _brickLine);
            canvas.drawLine(Offset(r.left + third / 2, r.top + third),
                Offset(r.left + third / 2, r.top + 2 * third), _brickLine);
        }
      }
    }

    for (final item in sim.floorItems) {
      final r = _tileRect(item.x, item.y, 4);
      if (item.type == core.ItemType.exit) {
        canvas.drawRect(_tileRect(item.x, item.y), _exit);
        canvas.drawRect(_tileRect(item.x, item.y, 6), _exitDoor);
      } else {
        canvas.drawRect(r, _item);
        canvas.drawRect(r, _itemEdge);
        _drawGlyph(canvas, r, _itemGlyph(item.type));
      }
    }

    for (final bomb in sim.bombs) {
      final centre =
          Offset((bomb.x + 0.5) * tileSize, (bomb.y + 0.5) * tileSize);
      // Pulse faster as the fuse runs out.
      final urgency = bomb.remote
          ? 0.0
          : (1 - bomb.fuse / core.Bomb.defaultFuse).clamp(0.0, 1.0);
      final pulse = 1 + 0.08 * math.sin(_time * (6 + urgency * 20));
      final radius = tileSize * 0.36 * pulse;
      canvas.drawCircle(centre, radius,
          urgency > 0.7 && (_time * 10).floor().isEven ? _bombHot : _bomb);
      canvas.drawCircle(centre + Offset(radius * 0.5, -radius * 0.7), 3, _fuse);
    }

    for (final flame in sim.flames) {
      final r = _tileRect(flame.x, flame.y, 2);
      canvas.drawRect(r, _flameOuter);
      canvas.drawRect(_tileRect(flame.x, flame.y, tileSize * 0.3), _flameInner);
    }

    for (final enemy in sim.enemies) {
      if (!enemy.alive) continue;
      final centre = Offset(enemy.x * tileSize, enemy.y * tileSize);
      final bob = math.sin(_time * 6 + enemy.id) * 1.5;
      canvas.drawCircle(centre + Offset(0, bob), tileSize * 0.38, _enemy);
      canvas.drawCircle(centre + Offset(-5, bob - 3), 2.5, _enemyEye);
      canvas.drawCircle(centre + Offset(5, bob - 3), 2.5, _enemyEye);
    }

    for (final p in sim.players) {
      if (!p.alive) continue;
      final centre = Offset(p.x * tileSize, p.y * tileSize);
      final blink = p.invincible && (_time * 12).floor().isEven;
      final body = Rect.fromCenter(
          center: centre, width: tileSize * 0.7, height: tileSize * 0.8);
      canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(6)),
          blink ? _playerHit : _playerSuit);
      canvas.drawCircle(
          centre + Offset(0, -tileSize * 0.2), tileSize * 0.22, _player);
      // Eyes face the walking direction.
      final f = p.facing;
      final eye = Offset(f.dx * 3.0, -tileSize * 0.2 + f.dy * 2.0);
      canvas.drawCircle(centre + eye + const Offset(-3, 0), 1.8, _enemyEye);
      canvas.drawCircle(centre + eye + const Offset(3, 0), 1.8, _enemyEye);
    }
  }

  String _itemGlyph(core.ItemType type) => switch (type) {
        core.ItemType.bombUp => 'B',
        core.ItemType.fireUp => 'F',
        core.ItemType.speedUp => 'S',
        core.ItemType.wallPass => 'W',
        core.ItemType.remote => 'R',
        core.ItemType.bombPass => 'P',
        core.ItemType.flamePass => 'I',
        core.ItemType.mystery => '?',
        core.ItemType.exit => '',
      };

  void _drawGlyph(Canvas canvas, Rect r, String glyph) {
    final builder = ParagraphBuilder(
        ParagraphStyle(textAlign: TextAlign.center, fontSize: tileSize * 0.55))
      ..pushStyle(TextStyle(
          color: const Color(0xFF000000), fontWeight: FontWeight.bold))
      ..addText(glyph);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: r.width));
    canvas.drawParagraph(
        paragraph, Offset(r.left, r.top + (r.height - paragraph.height) / 2));
  }
}
