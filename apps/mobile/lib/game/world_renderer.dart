import 'dart:math' as math;
import 'dart:ui';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';

/// Draws a [core.WorldSnapshot] in immediate mode with placeholder shapes.
///
/// It renders snapshots rather than a live simulation so the same code draws
/// solo play (snapshot of the local world each frame) and networked play
/// (latest snapshot from the server). Shapes and colours stand in for
/// sprites until the art pass, but every rule a player must read is visible:
/// enemy kinds and their tells, ghosts and tombstones, frost, pings, Sonar
/// reveals, falling-rock shadows and cracked floor.
class WorldRenderer extends PositionComponent {
  WorldRenderer(this.snapshot, {required this.tileSize});

  /// Returns the snapshot to draw this frame.
  final core.WorldSnapshot Function() snapshot;
  final double tileSize;

  /// Suit colours by player slot: blue, red, green, yellow.
  static final playerColors = [
    const Color(0xFF1E88E5),
    const Color(0xFFE53935),
    const Color(0xFF43A047),
    const Color(0xFFFDD835),
  ];

  /// Body colour per enemy kind, so each reads at a glance.
  static const enemyColors = <String, Color>{
    'Puffball': Color(0xFFF48FB1),
    'Blue Drop': Color(0xFF4FC3F7),
    'Barrelhop': Color(0xFFA1887F),
    'Grinface': Color(0xFFFFB74D),
    'Slime Sage': Color(0xFF81C784),
    'Wisp': Color(0xFFE1F5FE),
    'Hunter Coin': Color(0xFFD32F2F),
    'Door Warden': Color(0xFF5E35B1),
    'Pebble': Color(0xFF9E9E9E),
    'Hopper': Color(0xFFAED581),
    'Splitter': Color(0xFFBA68C8),
    'Splitling': Color(0xFFCE93D8),
    'Shellback': Color(0xFF8D6E63),
    'King Puffball': Color(0xFFEC407A),
    'Rockjaw Worm': Color(0xFF795548),
  };

  static Paint _fill(int c) => Paint()..color = Color(c);
  static Paint _stroke(int c, double w) => Paint()
    ..color = Color(c)
    ..strokeWidth = w
    ..style = PaintingStyle.stroke;

  static final _floor = _fill(0xFF3FA34D);
  static final _floorAlt = _fill(0xFF399A47);
  static final _pillar = _fill(0xFFBDBDBD);
  static final _pillarEdge = _fill(0xFF8A8A8A);
  static final _brick = _fill(0xFFB5651D);
  static final _brickLine = _stroke(0xFF7A4312, 1.5);
  static final _crack = _stroke(0xFF2E5E33, 1.5);
  static final _pit = _fill(0xFF101010);
  static final _pitRim = _stroke(0xFF3E2723, 2);
  static final _bomb = _fill(0xFF111111);
  static final _bombHot = _fill(0xFFD32F2F);
  static final _bombFrost = _fill(0xFF0277BD);
  static final _fuse = _fill(0xFFFFC107);
  static final _flameOuter = _fill(0xFFFF7043);
  static final _flameInner = _fill(0xFFFFF176);
  static final _frostOuter = _fill(0xFF4FC3F7);
  static final _frostInner = _fill(0xFFE1F5FE);
  static final _white = _fill(0xFFFFFFFF);
  static final _playerHit = _fill(0xFF9E9E9E);
  static final _black = _fill(0xFF000000);
  static final _item = _fill(0xFFFFEB3B);
  static final _itemEdge = _stroke(0xFF000000, 2);
  static final _exit = _fill(0xFF263238);
  static final _exitDoor = _fill(0xFF8D6E63);
  static final _shadow = _fill(0x66000000);
  static final _iceOverlay = _fill(0x884FC3F7);
  static final _tellRing = _stroke(0xFFFFEB3B, 2.5);
  static final _slowRing = _stroke(0xFFB388FF, 2);
  static final _dust = _fill(0xFF6D4C41);
  static final _tomb = _fill(0xFF78909C);
  static final _tombEdge = _stroke(0xFF37474F, 2);
  static final _revive = _stroke(0xFF69F0AE, 3);
  static final _hpBack = _fill(0xFF424242);
  static final _hpFront = _fill(0xFFE53935);
  static final _heart = _fill(0xFFFF5252);

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

  Offset _centre(num x, num y) => Offset(x * tileSize, y * tileSize);

  @override
  void render(Canvas canvas) {
    final sim = snapshot();
    _drawTiles(canvas, sim.grid);
    _drawSonar(canvas, sim);
    _drawItems(canvas, sim);
    _drawHazards(canvas, sim);
    _drawTombstones(canvas, sim);
    _drawBombs(canvas, sim);
    _drawFlames(canvas, sim);
    _drawEnemies(canvas, sim);
    _drawPlayers(canvas, sim);
    _drawPings(canvas, sim);
  }

  void _drawTiles(Canvas canvas, core.Grid grid) {
    for (var y = 0; y < grid.height; y++) {
      for (var x = 0; x < grid.width; x++) {
        final r = _tileRect(x, y);
        switch (grid.at(x, y)) {
          case core.TileType.floor:
            canvas.drawRect(r, (x + y).isEven ? _floor : _floorAlt);
          case core.TileType.cracked:
            canvas.drawRect(r, (x + y).isEven ? _floor : _floorAlt);
            final path = Path()
              ..moveTo(r.left + r.width * 0.2, r.top + r.height * 0.3)
              ..lineTo(r.left + r.width * 0.5, r.top + r.height * 0.5)
              ..lineTo(r.left + r.width * 0.4, r.top + r.height * 0.8)
              ..moveTo(r.left + r.width * 0.5, r.top + r.height * 0.5)
              ..lineTo(r.left + r.width * 0.85, r.top + r.height * 0.4);
            canvas.drawPath(path, _crack);
          case core.TileType.pit:
            canvas.drawRect(r, _pit);
            canvas.drawOval(r.deflate(3), _pitRim);
          case core.TileType.pillar:
            canvas.drawRect(r, _pillarEdge);
            canvas.drawRect(_tileRect(x, y, 2), _pillar);
          case core.TileType.brick:
            canvas.drawRect(r, _brick);
            final third = tileSize / 3;
            canvas.drawLine(
              Offset(r.left, r.top + third),
              Offset(r.right, r.top + third),
              _brickLine,
            );
            canvas.drawLine(
              Offset(r.left, r.top + 2 * third),
              Offset(r.right, r.top + 2 * third),
              _brickLine,
            );
            canvas.drawLine(
              Offset(r.center.dx, r.top),
              Offset(r.center.dx, r.top + third),
              _brickLine,
            );
            canvas.drawLine(
              Offset(r.left + third / 2, r.top + third),
              Offset(r.left + third / 2, r.top + 2 * third),
              _brickLine,
            );
        }
      }
    }
  }

  void _drawSonar(Canvas canvas, core.WorldSnapshot sim) {
    // What Sonar found under bricks, drawn as a ghostly outline on the brick.
    final pulse = 0.5 + 0.3 * math.sin(_time * 5);
    for (final s in sim.sonar) {
      final r = _tileRect(s.x, s.y, 6);
      canvas.drawRect(
        r,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: pulse * 0.6),
      );
      _drawGlyph(
        canvas,
        r,
        s.type == core.ItemType.exit ? '🚪' : itemGlyph(s.type),
      );
    }
  }

  void _drawItems(Canvas canvas, core.WorldSnapshot sim) {
    for (final item in sim.items) {
      final r = _tileRect(item.x, item.y, 4);
      if (item.type == core.ItemType.exit) {
        canvas.drawRect(_tileRect(item.x, item.y), _exit);
        canvas.drawRect(_tileRect(item.x, item.y, 6), _exitDoor);
      } else {
        canvas.drawRect(r, _item);
        canvas.drawRect(r, _itemEdge);
        _drawGlyph(canvas, r, itemGlyph(item.type));
      }
    }
  }

  void _drawHazards(Canvas canvas, core.WorldSnapshot sim) {
    // A shadow that grows as the rock gets closer (§8.1 telegraphed rocks).
    for (final h in sim.hazards) {
      final t = (1 - h.warn / core.World.rockWarning).clamp(0.0, 1.0);
      canvas.drawCircle(
        _centre(h.x + 0.5, h.y + 0.5),
        tileSize * (0.15 + 0.3 * t),
        _shadow,
      );
    }
  }

  void _drawTombstones(Canvas canvas, core.WorldSnapshot sim) {
    for (final p in sim.players) {
      final t = p.tombstone;
      if (t == null) continue;
      final r = Rect.fromCenter(
        center: _centre(t.x + 0.5, t.y + 0.55),
        width: tileSize * 0.5,
        height: tileSize * 0.6,
      );
      final slab = RRect.fromRectAndCorners(
        r,
        topLeft: Radius.circular(tileSize * 0.25),
        topRight: Radius.circular(tileSize * 0.25),
      );
      canvas.drawRRect(slab, _tomb);
      canvas.drawRRect(slab, _tombEdge);
      if (p.reviveProgress > 0) {
        canvas.drawArc(
          _tileRect(t.x, t.y, 1),
          -math.pi / 2,
          math.pi * 2 * p.reviveProgress,
          false,
          _revive,
        );
      }
    }
  }

  void _drawBombs(Canvas canvas, core.WorldSnapshot sim) {
    for (final bomb in sim.bombs) {
      final slide = bomb.slide;
      final centre = _centre(
        bomb.x + 0.5 + slide.dx * bomb.slideProgress,
        bomb.y + 0.5 + slide.dy * bomb.slideProgress,
      );
      // Pulse faster as the fuse runs out.
      final urgency = bomb.remote
          ? 0.0
          : (1 - bomb.fuse / core.Bomb.defaultFuse).clamp(0.0, 1.0);
      final pulse = 1 + 0.08 * math.sin(_time * (6 + urgency * 20));
      final radius = tileSize * 0.36 * pulse;
      final hot = urgency > 0.7 && (_time * 10).floor().isEven;
      canvas.drawCircle(
        centre,
        radius,
        hot ? _bombHot : (bomb.frost ? _bombFrost : _bomb),
      );
      canvas.drawCircle(centre + Offset(radius * 0.5, -radius * 0.7), 3, _fuse);
    }
  }

  void _drawFlames(Canvas canvas, core.WorldSnapshot sim) {
    for (final flame in sim.flames) {
      canvas.drawRect(
        _tileRect(flame.x, flame.y, 2),
        flame.frost ? _frostOuter : _flameOuter,
      );
      canvas.drawRect(
        _tileRect(flame.x, flame.y, tileSize * 0.3),
        flame.frost ? _frostInner : _flameInner,
      );
    }
  }

  void _drawEnemies(Canvas canvas, core.WorldSnapshot sim) {
    for (final e in sim.enemies) {
      if (!e.alive) continue;
      final kind = e.kindData;
      final size = (kind?.size ?? 0.4) * tileSize;
      final base = enemyColors[e.kind] ?? const Color(0xFFF48FB1);
      var centre = _centre(e.x, e.y);

      if (e.state == core.EnemyStateKind.underground ||
          (kind?.style == core.MoveStyle.burrow &&
              e.state == core.EnemyStateKind.telegraph)) {
        // Below ground: a dust mound, shaking when about to surface.
        final shake = e.state == core.EnemyStateKind.telegraph
            ? math.sin(_time * 60) * 2
            : 0.0;
        if (e.state == core.EnemyStateKind.telegraph) {
          canvas.drawCircle(centre + Offset(shake, 0), tileSize * 0.45, _dust);
          canvas.drawCircle(centre, tileSize * 0.5, _tellRing);
        }
        continue;
      }

      final bob = math.sin(_time * 6 + e.id) * 1.5;
      if (e.state == core.EnemyStateKind.airborne) {
        canvas.drawCircle(centre, size * 0.7, _shadow);
        centre += Offset(0, -tileSize * 0.35);
      } else {
        centre += Offset(0, bob);
      }

      var scaleY = 1.0;
      if (e.state == core.EnemyStateKind.telegraph) {
        scaleY = 0.7; // squat
        canvas.drawCircle(centre, size + 4, _tellRing);
      }
      final body = Rect.fromCenter(
        center: centre,
        width: size * 2,
        height: size * 2 * scaleY,
      );
      final paint = Paint()
        ..color = e.slowed ? base.withValues(alpha: 0.6) : base;
      if (e.kind == 'Shellback' || e.kind == 'Pebble') {
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(size * 0.5)),
          paint,
        );
      } else {
        canvas.drawOval(body, paint);
      }

      if (e.state == core.EnemyStateKind.stunned) {
        // Flipped: X eyes.
        final p = _stroke(0xFF000000, 2);
        for (final dx in [-5.0, 5.0]) {
          final c = centre + Offset(dx, -2);
          canvas.drawLine(c + const Offset(-2, -2), c + const Offset(2, 2), p);
          canvas.drawLine(c + const Offset(-2, 2), c + const Offset(2, -2), p);
        }
      } else {
        final eye = size * 0.3;
        canvas.drawCircle(centre + Offset(-eye, -eye * 0.6), 2.5, _black);
        canvas.drawCircle(centre + Offset(eye, -eye * 0.6), 2.5, _black);
      }
      if (e.frozen) canvas.drawOval(body.inflate(2), _iceOverlay);
      if (e.slowed) canvas.drawCircle(centre, size + 3, _slowRing);

      if (kind?.boss ?? false) {
        final bar = Rect.fromLTWH(
          centre.dx - size,
          centre.dy - size - 10,
          size * 2,
          5,
        );
        canvas.drawRect(bar, _hpBack);
        canvas.drawRect(
          Rect.fromLTWH(
            bar.left,
            bar.top,
            bar.width * (e.hp / math.max(1, e.maxHp)),
            bar.height,
          ),
          _hpFront,
        );
      }
    }
  }

  void _drawPlayers(Canvas canvas, core.WorldSnapshot sim) {
    for (var slot = 0; slot < sim.players.length; slot++) {
      final p = sim.players[slot];
      if (!p.alive && !p.ghost) continue;
      final suitColor = playerColors[slot % playerColors.length];
      var centre = _centre(p.x, p.y);

      if (p.ghost) {
        // Floating, see-through, suit-coloured outline.
        centre += Offset(0, math.sin(_time * 3 + slot) * 3 - 4);
        final body = Rect.fromCenter(
          center: centre,
          width: tileSize * 0.6,
          height: tileSize * 0.75,
        );
        final shape = RRect.fromRectAndCorners(
          body,
          topLeft: Radius.circular(tileSize * 0.3),
          topRight: Radius.circular(tileSize * 0.3),
        );
        canvas.drawRRect(shape, Paint()..color = const Color(0x88FFFFFF));
        canvas.drawRRect(
          shape,
          Paint()
            ..color = suitColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(centre + const Offset(-4, -3), 2, _black);
        canvas.drawCircle(centre + const Offset(4, -3), 2, _black);
        continue;
      }

      final blink = p.invincible && (_time * 12).floor().isEven;
      final body = Rect.fromCenter(
        center: centre,
        width: tileSize * 0.7,
        height: tileSize * 0.8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(6)),
        blink ? _playerHit : (Paint()..color = suitColor),
      );
      canvas.drawCircle(
        centre + Offset(0, -tileSize * 0.2),
        tileSize * 0.22,
        _white,
      );
      // Eyes face the walking direction.
      final f = p.facing;
      final eye = Offset(f.dx * 3.0, -tileSize * 0.2 + f.dy * 2.0);
      canvas.drawCircle(centre + eye + const Offset(-3, 0), 1.8, _black);
      canvas.drawCircle(centre + eye + const Offset(3, 0), 1.8, _black);
      if (p.frozen) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(body.inflate(2), const Radius.circular(6)),
          _iceOverlay,
        );
      }
      if (p.hearts > 0) {
        canvas.drawCircle(
          centre + Offset(tileSize * 0.32, -tileSize * 0.42),
          4,
          _heart,
        );
      }
    }
  }

  static const pingGlyphs = {
    core.PingKind.exitHere: '🚪',
    core.PingKind.powerUp: '⭐',
    core.PingKind.help: '🆘',
    core.PingKind.run: '🏃',
  };

  void _drawPings(Canvas canvas, core.WorldSnapshot sim) {
    for (final ping in sim.pings) {
      final slot = sim.players.indexWhere((p) => p.id == ping.playerId);
      final colour = playerColors[math.max(0, slot) % playerColors.length];
      final lift = math.sin(_time * 4) * 2;
      final c = _centre(ping.x + 0.5, ping.y - 0.4) + Offset(0, lift);
      canvas.drawCircle(c, tileSize * 0.42, _white);
      canvas.drawCircle(
        c,
        tileSize * 0.42,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      _drawGlyph(
        canvas,
        Rect.fromCenter(center: c, width: tileSize, height: tileSize),
        pingGlyphs[ping.kind] ?? '!',
      );
    }
  }

  static String itemGlyph(core.ItemType type) => switch (type) {
    core.ItemType.bombUp => 'B',
    core.ItemType.fireUp => 'F',
    core.ItemType.speedUp => 'S',
    core.ItemType.wallPass => 'W',
    core.ItemType.remote => 'R',
    core.ItemType.bombPass => 'P',
    core.ItemType.flamePass => 'I',
    core.ItemType.mystery => '?',
    core.ItemType.kick => 'K',
    core.ItemType.heart => '♥',
    core.ItemType.sonar => '◎',
    core.ItemType.teamBoost => '+',
    core.ItemType.tether => '∞',
    core.ItemType.frost => '❄',
    core.ItemType.exit => '',
  };

  void _drawGlyph(Canvas canvas, Rect r, String glyph) {
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: tileSize * 0.55,
            ),
          )
          ..pushStyle(
            TextStyle(
              color: const Color(0xFF000000),
              fontWeight: FontWeight.bold,
            ),
          )
          ..addText(glyph);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: r.width));
    canvas.drawParagraph(
      paragraph,
      Offset(r.left, r.top + (r.height - paragraph.height) / 2),
    );
  }
}
