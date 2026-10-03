import 'dart:math' as math;
import 'dart:ui';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';

import '../progress/cosmetics.dart';
import 'death_effects.dart';
import 'sprite_atlas.dart';

/// Draws a [core.WorldSnapshot] in immediate mode with the pixel-art sprites
/// from [SpriteAtlas].
///
/// It renders snapshots rather than a live simulation so the same code draws
/// solo play (snapshot of the local world each frame) and networked play
/// (latest snapshot from the server). Every rule a player must read stays
/// visible on top of the art: enemy tells, ghosts and tombstones, frost,
/// pings, Sonar reveals, falling-rock shadows and cracked floor. An enemy
/// kind without a sprite yet falls back to a coloured blob.
class WorldRenderer extends PositionComponent {
  WorldRenderer(
    this.snapshot, {
    required this.tileSize,
    required this.atlas,
    bool Function()? highContrast,
  }) : highContrast = highContrast ?? _off;

  static bool _off() => false;

  /// Returns the snapshot to draw this frame.
  final core.WorldSnapshot Function() snapshot;
  final double tileSize;
  final SpriteAtlas atlas;

  /// Accessibility: outlines every flame tile in white (§9.6).
  final bool Function() highContrast;

  /// Suit colours by player slot: blue, red, green, yellow (the mockups').
  static const playerColors = [
    Color(0xFF3D7BFF),
    Color(0xFFFF4B4B),
    Color(0xFF3FC062),
    Color(0xFFFFC23D),
  ];

  /// Sprite per enemy kind name.
  static const enemySprites = <String, String>{
    'Puffball': 'puff',
    'Blue Drop': 'drop',
    'Barrelhop': 'barrelhop',
    'Grinface': 'grinface',
    'Slime Sage': 'slimeSage',
    'Wisp': 'wisp',
    'Hunter Coin': 'hunterCoin',
    'Door Warden': 'doorWarden',
    'Pebble': 'pebble',
    'Hopper': 'hopper',
    'Splitter': 'splitter',
    'Splitling': 'splitling',
    'Shellback': 'shellback',
    'King Puffball': 'kingPuffball',
    'Rockjaw Worm': 'rockjaw',
    'Bomb Goblin': 'goblin',
    'Tigerclaw': 'tigerclaw',
    'Mimic': 'mimic',
    'Kicker Crab': 'kickerCrab',
    'Shade': 'shade',
    'Mole Queen Nest': 'moleNest',
    'Mirror Knight': 'mirrorKnight',
    'Fuse Eater': 'fuseEater',
    'Phase Wraith': 'phaseWraith',
    'Herder': 'herder',
    'Curse Orb': 'curseOrb',
    'Bomb-O-Tron': 'bombOTron',
    'Lantern Witch': 'lanternWitch',
    'Overlord Pontan': 'overlordPontan',
  };

  static String? featureSprite(core.TileFeature f) => switch (f) {
    core.TileFeature.conveyorUp => 'conveyor-up',
    core.TileFeature.conveyorDown => 'conveyor-down',
    core.TileFeature.conveyorLeft => 'conveyor-left',
    core.TileFeature.conveyorRight => 'conveyor-right',
    core.TileFeature.vent => 'vent',
    core.TileFeature.plate => 'plate',
    core.TileFeature.warp => 'warp',
    core.TileFeature.ice => 'ice',
    // Gates and possessed bricks change the tile itself; see _drawTiles.
    core.TileFeature.gate || core.TileFeature.possessed => null,
    core.TileFeature.none => null,
  };

  /// Body colour for enemies drawn without a sprite (and the minimap).
  static const enemyFallback = Color(0xFFF58CCB);

  static String itemSprite(core.ItemType type) => switch (type) {
    core.ItemType.bombUp => 'pu-bomb',
    core.ItemType.fireUp => 'pu-fire',
    core.ItemType.speedUp => 'pu-speed',
    core.ItemType.wallPass => 'pu-wall',
    core.ItemType.remote => 'pu-remote',
    core.ItemType.bombPass => 'pu-bombpass',
    core.ItemType.flamePass => 'pu-flamepass',
    core.ItemType.mystery => 'pu-mystery',
    core.ItemType.kick => 'pu-kick',
    core.ItemType.heart => 'pu-heart',
    core.ItemType.sonar => 'pu-sonar',
    core.ItemType.teamBoost => 'pu-teamboost',
    core.ItemType.tether => 'pu-tether',
    core.ItemType.frost => 'pu-frost',
    core.ItemType.exit => 'exit',
  };

  static const pingSprites = {
    core.PingKind.exitHere: 'exit',
    core.PingKind.powerUp: 'star',
    core.PingKind.help: 'ping-help',
    core.PingKind.run: 'ping-run',
  };

  static Paint _fill(int c) => Paint()..color = Color(c);
  static Paint _stroke(int c, double w) => Paint()
    ..color = Color(c)
    ..strokeWidth = w
    ..style = PaintingStyle.stroke;

  static final _shadow = _fill(0x55000000);
  static final _iceOverlay = _fill(0x884FC3F7);
  static final _tellRing = _stroke(0xFFFFD23F, 2.5);
  static final _slowRing = _stroke(0xFFB388FF, 2);
  static final _revive = _stroke(0xFF69F0AE, 3);
  static final _hpBack = _fill(0xFF1E2230);
  static final _hpFront = _fill(0xFFFF4B4B);
  static final _bubble = _fill(0xFFF3F1E6);
  static final _flameOutline = _stroke(0xFFFFFFFF, 2);
  static final _vulnerable = _fill(0x66FFFFFF);

  double _time = 0;

  /// Brick bursts and enemy deaths, spotted between snapshots.
  final DeathEffects effects = DeathEffects();

  /// Walk cycle per player id, advanced by how far each player has moved so
  /// the feet keep pace with their speed and stop when they stop.
  final Map<int, _Stride> _strides = {};

  /// Whether the player is walking, and which pose to draw: 0 stand, 1 left
  /// foot up, 2 stand, 3 right foot up.
  ({bool moving, int step}) _pose(core.PlayerState p) {
    final s = _strides.putIfAbsent(p.id, () => _Stride(p.x, p.y, _time));
    final moved = math.sqrt(math.pow(p.x - s.x, 2) + math.pow(p.y - s.y, 2));
    s
      ..x = p.x
      ..y = p.y;
    // Warps and respawns jump; only count real steps.
    if (moved > 0.001 && moved < 1) {
      s
        ..travelled += moved
        ..lastMove = _time;
    }
    if (_time - s.lastMove > 0.12) {
      s.travelled = 0;
      return (moving: false, step: 0);
    }
    // A quarter tile per pose: two full steps per tile walked. The first
    // pose is already a stride so a single tap shows a step.
    return (
      moving: true,
      step: s.travelled < 0.25 ? 1 : (s.travelled / 0.25).floor() % 4,
    );
  }

  /// The sprite for [base] seen facing [facing]: the back when walking up,
  /// the side when walking left or right (the caller mirrors it for left),
  /// or [base] itself when the atlas has no such view.
  static String facingSprite(String base, core.Direction facing) {
    final view = switch (facing) {
      core.Direction.up => '$base-up',
      core.Direction.left || core.Direction.right => '$base-side',
      _ => base,
    };
    return SpriteAtlas.has(view) ? view : base;
  }

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

  Rect _square(Offset centre, double side) =>
      Rect.fromCenter(center: centre, width: side, height: side);

  @override
  void render(Canvas canvas) {
    final sim = snapshot();
    effects.observe(sim, _time, (e) => enemySprites[e.kind]);
    _drawTiles(canvas, sim);
    _drawRegrowing(canvas, sim);
    _drawSonar(canvas, sim);
    _drawItems(canvas, sim);
    _drawHazards(canvas, sim);
    _drawTombstones(canvas, sim);
    _drawBombs(canvas, sim);
    _drawFlames(canvas, sim);
    effects.drawBricks(canvas, atlas, tileSize, _time);
    _drawEnemies(canvas, sim);
    effects.drawEnemies(canvas, atlas, tileSize, _time);
    _drawPlayers(canvas, sim);
    _drawFallingRocks(canvas, sim);
    _drawWind(canvas, sim);
    _drawDarkness(canvas, sim);
    _drawPings(canvas, sim);
  }

  void _drawTiles(Canvas canvas, core.WorldSnapshot sim) {
    final grid = sim.grid;
    final features = grid.hasFeatures;
    // Vents glow in the warning phase, blinking faster as it runs out.
    final ventHot =
        sim.ventPhase == core.VentPhase.warning &&
        (_time * (4 + 8 / math.max(0.2, sim.ventTimeLeft))).floor().isEven;
    for (var y = 0; y < grid.height; y++) {
      for (var x = 0; x < grid.width; x++) {
        final tile = grid.at(x, y);
        final feature = features ? grid.featureAt(x, y) : core.TileFeature.none;
        final r = _tileRect(x, y);
        if (feature == core.TileFeature.gate && tile == core.TileType.pillar) {
          atlas.draw(canvas, 'gate', r);
          continue;
        }
        if (feature == core.TileFeature.possessed &&
            tile == core.TileType.brick) {
          atlas.draw(canvas, 'brick-possessed', r);
          continue;
        }
        atlas.draw(canvas, switch (tile) {
          core.TileType.floor => 'floor',
          core.TileType.cracked => 'cracked',
          core.TileType.pit => 'pit',
          core.TileType.pillar => 'wall',
          core.TileType.brick => 'brick',
        }, r);
        if (tile == core.TileType.floor || tile == core.TileType.cracked) {
          final name = feature == core.TileFeature.vent && ventHot
              ? 'vent-warn'
              : featureSprite(feature);
          if (name != null) atlas.draw(canvas, name, r);
        }
      }
    }
  }

  void _drawRegrowing(Canvas canvas, core.WorldSnapshot sim) {
    // Possessed bricks fade back in over their last seconds.
    for (final r in sim.regrowing) {
      final t = (1 - r.warn / 5).clamp(0.0, 1.0);
      if (t <= 0) continue;
      atlas.draw(
        canvas,
        'brick-possessed',
        _tileRect(r.x, r.y),
        paint: SpriteAtlas.faded(0.15 + 0.5 * t),
      );
    }
  }

  void _drawWind(Canvas canvas, core.WorldSnapshot sim) {
    final wind = sim.wind != core.Direction.none ? sim.wind : sim.windNext;
    if (wind == core.Direction.none) return;
    final blowing = sim.wind != core.Direction.none;
    final w = sim.grid.width * tileSize;
    final h = sim.grid.height * tileSize;
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: blowing ? 0.35 : 0.15)
      ..strokeWidth = 2;
    // Streaks drift with the gust; a faint preview during the lull.
    for (var i = 0; i < 14; i++) {
      final lane = (i * 0.37 % 1);
      final along = ((_time * (blowing ? 0.6 : 0.2) + i * 0.29) % 1);
      final len = tileSize * 1.2;
      final horizontal = wind.dx != 0;
      final dir = horizontal ? wind.dx.toDouble() : wind.dy.toDouble();
      final pos = dir > 0 ? along : 1 - along;
      final start = horizontal
          ? Offset(pos * w, lane * h)
          : Offset(lane * w, pos * h);
      final end =
          start + (horizontal ? Offset(len * dir, 0) : Offset(0, len * dir));
      canvas.drawLine(start, end, paint);
    }
  }

  void _drawDarkness(Canvas canvas, core.WorldSnapshot sim) {
    if (sim.darkness <= 0) return;
    final bounds = Rect.fromLTWH(
      0,
      0,
      sim.grid.width * tileSize,
      sim.grid.height * tileSize,
    );
    // A dark layer with soft holes around players and flames.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xF20D1120));
    final clear = Paint()..blendMode = BlendMode.dstOut;
    void light(Offset c, double radius) {
      canvas.drawCircle(
        c,
        radius,
        clear
          ..shader = Gradient.radial(
            c,
            radius,
            const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            const [0, 0.6, 1],
          ),
      );
    }

    for (final p in sim.players) {
      if (p.alive || p.ghost) {
        light(_centre(p.x, p.y), sim.darkness * tileSize);
      }
    }
    for (final f in sim.flames) {
      light(_centre(f.x + 0.5, f.y + 0.5), tileSize * 1.5);
    }
    canvas.restore();
  }

  void _drawSonar(Canvas canvas, core.WorldSnapshot sim) {
    // What Sonar found under bricks shows through, pulsing.
    final pulse = 0.45 + 0.25 * math.sin(_time * 5);
    for (final s in sim.sonar) {
      atlas.draw(
        canvas,
        itemSprite(s.type),
        _tileRect(s.x, s.y, tileSize * 0.15),
        paint: SpriteAtlas.faded(pulse),
      );
    }
  }

  void _drawItems(Canvas canvas, core.WorldSnapshot sim) {
    for (final item in sim.items) {
      if (item.type == core.ItemType.exit) {
        if (sim.enemies.every((e) => !e.alive)) {
          // Open: a warm glow breathes behind the door.
          final glow = 0.35 + 0.25 * math.sin(_time * 6);
          canvas.drawRect(
            _tileRect(item.x, item.y),
            Paint()
              ..color = const Color(0xFFFFD23F).withValues(alpha: glow)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
        atlas.draw(canvas, 'exit', _tileRect(item.x, item.y));
      } else {
        // Power-ups bob gently so they read as "pick me up".
        final lift = math.sin(_time * 4 + item.x + item.y) * tileSize * 0.03;
        atlas.draw(
          canvas,
          itemSprite(item.type),
          _tileRect(item.x, item.y, tileSize * 0.08).translate(0, lift),
        );
      }
    }
  }

  void _drawHazards(Canvas canvas, core.WorldSnapshot sim) {
    for (final h in sim.hazards) {
      switch (h.kind) {
        case core.HazardKind.rock:
          // A shadow that grows as the rock gets closer (§8.1).
          final t = (1 - h.warn / core.World.rockWarning).clamp(0.0, 1.0);
          canvas.drawOval(
            Rect.fromCenter(
              center: _centre(h.x + 0.5, h.y + 0.7),
              width: tileSize * (0.3 + 0.5 * t),
              height: tileSize * (0.15 + 0.25 * t),
            ),
            _shadow,
          );
        case core.HazardKind.cannonLeft || core.HazardKind.cannonRight:
          // The row the cannonball will sweep, blinking, with the ball
          // waiting at its wall.
          final blink = (_time * 8).floor().isEven;
          canvas.drawRect(
            Rect.fromLTWH(
              0,
              h.y * tileSize,
              sim.grid.width * tileSize,
              tileSize,
            ),
            Paint()
              ..color = const Color(
                0xFFFF4B4B,
              ).withValues(alpha: blink ? 0.28 : 0.14),
          );
          atlas.draw(canvas, 'cannonball', _tileRect(h.x, h.y));
        case core.HazardKind.wall:
          // An arena tile about to close: the wall fades in and shakes.
          final shake = math.sin(_time * 50) * 1.5;
          atlas.draw(
            canvas,
            'wall',
            _tileRect(h.x, h.y).translate(shake, 0),
            paint: SpriteAtlas.faded(0.5),
          );
      }
    }
  }

  void _drawFallingRocks(Canvas canvas, core.WorldSnapshot sim) {
    // In the last half of the warning the rock itself drops into view.
    for (final h in sim.hazards) {
      if (h.kind != core.HazardKind.rock) continue;
      final t = (1 - h.warn / core.World.rockWarning).clamp(0.0, 1.0);
      if (t < 0.5) continue;
      final fall = (t - 0.5) * 2;
      final centre = _centre(h.x + 0.5, h.y + 0.5 - 2.5 * (1 - fall));
      atlas.draw(canvas, 'rock', _square(centre, tileSize));
    }
  }

  void _drawTombstones(Canvas canvas, core.WorldSnapshot sim) {
    for (final p in sim.players) {
      final t = p.tombstone;
      if (t == null) continue;
      atlas.draw(canvas, 'tomb', _tileRect(t.x, t.y));
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
      // Pulse faster as the fuse runs out; the last second flashes red.
      final urgency = bomb.remote
          ? 0.0
          : (1 - bomb.fuse / core.Bomb.defaultFuse).clamp(0.0, 1.0);
      final pulse = 1 + 0.06 * math.sin(_time * (6 + urgency * 20));
      final hot = bomb.fuse <= 1 && !bomb.remote && (_time * 8).floor().isEven;
      final name = (hot ? 'bombr' : 'bomb') + (bomb.frost ? '-frost' : '');
      atlas.draw(canvas, name, _square(centre, tileSize * pulse));
    }
  }

  void _drawFlames(Canvas canvas, core.WorldSnapshot sim) {
    // The snapshot carries flame tiles, not blasts, so each tile's shape
    // comes from its neighbours: a crossing is a centre, a straight run is
    // an arm, and a tile with one neighbour is an end cap pointing away.
    final lit = {for (final f in sim.flames) (f.x, f.y)};
    final outline = highContrast();
    for (final f in sim.flames) {
      final l = lit.contains((f.x - 1, f.y));
      final r = lit.contains((f.x + 1, f.y));
      final u = lit.contains((f.x, f.y - 1));
      final d = lit.contains((f.x, f.y + 1));
      final horizontal = l || r;
      final vertical = u || d;
      final String shape;
      if (horizontal && vertical || !horizontal && !vertical) {
        shape = 'fc';
      } else if (horizontal) {
        shape = l && r ? 'fh' : (l ? 'fr' : 'fl');
      } else {
        shape = u && d ? 'fv' : (u ? 'fd' : 'fu');
      }
      atlas.draw(canvas, f.frost ? '$shape-frost' : shape, _tileRect(f.x, f.y));
      if (outline) canvas.drawRect(_tileRect(f.x, f.y, 1), _flameOutline);
    }
  }

  void _drawEnemies(Canvas canvas, core.WorldSnapshot sim) {
    for (final e in sim.enemies) {
      if (!e.alive || !e.visible) continue;
      final kind = e.kindData;
      if (e.state == core.EnemyStateKind.disguised && e.disguise != null) {
        // A Mimic looks exactly like the power-up it pretends to be.
        atlas.draw(
          canvas,
          itemSprite(e.disguise!),
          _square(_centre(e.x, e.y), tileSize * 0.84),
        );
        continue;
      }
      final bodySize = (kind?.size ?? 0.4) * tileSize * 2.5;
      var centre = _centre(e.x, e.y);

      if (e.state == core.EnemyStateKind.underground ||
          (kind?.style == core.MoveStyle.burrow &&
              e.state == core.EnemyStateKind.telegraph)) {
        // Below ground: a dust mound, shaking when about to surface.
        if (e.state == core.EnemyStateKind.telegraph) {
          final shake = math.sin(_time * 60) * 2;
          atlas.draw(
            canvas,
            'mound',
            _square(centre + Offset(shake, 0), bodySize),
          );
          canvas.drawCircle(centre, bodySize * 0.5, _tellRing);
        }
        continue;
      }

      if (e.state == core.EnemyStateKind.airborne) {
        canvas.drawOval(
          Rect.fromCenter(
            center: centre + Offset(0, bodySize * 0.35),
            width: bodySize * 0.7,
            height: bodySize * 0.25,
          ),
          _shadow,
        );
        centre += Offset(0, -tileSize * 0.35);
      } else if (e.state != core.EnemyStateKind.stunned && !e.frozen) {
        centre += Offset(0, math.sin(_time * 6 + e.id) * tileSize * 0.04);
      }

      var scaleY = 1.0;
      if (e.state == core.EnemyStateKind.telegraph) {
        scaleY = 0.75; // squat before the move
        canvas.drawCircle(centre, bodySize * 0.55, _tellRing);
      }
      final body = Rect.fromCenter(
        center: centre + Offset(0, bodySize * (1 - scaleY) / 2),
        width: bodySize,
        height: bodySize * scaleY,
      );

      canvas.save();
      // Face the way they walk; stunned enemies lie upside down.
      final flipX = e.facing == core.Direction.left;
      final flipY = e.state == core.EnemyStateKind.stunned;
      if (flipX || flipY) {
        canvas.translate(centre.dx, centre.dy);
        canvas.scale(flipX ? -1 : 1, flipY ? -1 : 1);
        canvas.translate(-centre.dx, -centre.dy);
      }
      final sprite = enemySprites[e.kind];
      final drawn =
          sprite != null &&
          atlas.draw(
            canvas,
            facingSprite(sprite, e.facing),
            body,
            paint: e.slowed ? SpriteAtlas.faded(0.6) : null,
          );
      if (!drawn) {
        canvas.drawOval(
          body.deflate(bodySize * 0.1),
          Paint()..color = enemyFallback,
        );
      }
      canvas.restore();

      if (e.frozen) {
        canvas.drawRect(body.deflate(bodySize * 0.08), _iceOverlay);
      }
      if (e.state == core.EnemyStateKind.vulnerable &&
          (_time * 10).floor().isEven) {
        // Guard down: flashes so players know to strike now.
        canvas.drawRect(body.deflate(bodySize * 0.1), _vulnerable);
      }
      if (e.slowed) canvas.drawCircle(centre, bodySize * 0.55, _slowRing);

      if (kind?.boss ?? false) {
        final bar = Rect.fromLTWH(
          centre.dx - bodySize / 2,
          body.top - 9,
          bodySize,
          5,
        );
        canvas.drawRect(bar.inflate(1), _hpBack);
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
      final look = (slot % playerColors.length) + 1;
      var centre = _centre(p.x, p.y);

      if (p.ghost) {
        // Floating, see-through, outlined in the player's colour.
        centre += Offset(0, math.sin(_time * 3 + slot) * 3 - 4);
        atlas.draw(
          canvas,
          'spirit-p$look',
          _square(centre, tileSize),
          paint: SpriteAtlas.faded(0.75),
        );
        continue;
      }

      final blink = p.invincible && (_time * 12).floor().isEven;
      final pose = p.frozen ? (moving: false, step: 0) : _pose(p);
      // The body lifts a pixel on each stride, so the walk has a bounce.
      final lift = pose.step.isOdd ? tileSize / 16 : 0.0;
      final body = _square(
        centre - Offset(0, tileSize * 0.08 + lift),
        tileSize,
      );
      // Faces the way it walks and turns back to the camera when it stops.
      final facing = pose.moving ? p.facing : core.Direction.down;
      final frame = switch (pose.step) {
        1 => '-walk-a',
        3 => '-walk-b',
        _ => '',
      };
      final paint = blink ? SpriteAtlas.faded(0.35) : null;
      canvas.save();
      if (facing == core.Direction.left) {
        canvas.translate(body.center.dx, body.center.dy);
        canvas.scale(-1, 1);
        canvas.translate(-body.center.dx, -body.center.dy);
      }
      atlas.draw(
        canvas,
        '${facingSprite('p$look', facing)}$frame',
        body,
        paint: paint,
      );
      // The hat turns with the head, so a cap's peak points the way walked.
      final hat = Cosmetics.spriteFor(p.skin);
      if (hat != null) atlas.draw(canvas, hat, body, paint: paint);
      canvas.restore();
      if (p.frozen) canvas.drawRect(body.deflate(2), _iceOverlay);
      if (p.cursedFor > 0) {
        // Reversed controls: an orb circles the cursed player's head.
        final a = _time * 4;
        atlas.draw(
          canvas,
          'curseOrb',
          _square(
            body.topCenter +
                Offset(math.cos(a) * tileSize * 0.35, math.sin(a) * 4),
            tileSize * 0.4,
          ),
        );
      }
      if (p.hearts > 0) {
        atlas.draw(
          canvas,
          'heart',
          _square(
            body.topRight + Offset(-tileSize * 0.12, tileSize * 0.12),
            tileSize * 0.4,
          ),
        );
      }
    }
  }

  void _drawPings(Canvas canvas, core.WorldSnapshot sim) {
    for (final ping in sim.pings) {
      final slot = sim.players.indexWhere((p) => p.id == ping.playerId);
      final colour = playerColors[math.max(0, slot) % playerColors.length];
      final lift = math.sin(_time * 4) * 2;
      final c = _centre(ping.x + 0.5, ping.y - 0.4) + Offset(0, lift);
      canvas.drawCircle(c, tileSize * 0.42, _bubble);
      canvas.drawCircle(
        c,
        tileSize * 0.42,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      atlas.draw(
        canvas,
        pingSprites[ping.kind] ?? 'ping-help',
        _square(c, tileSize * 0.6),
      );
    }
  }
}

class _Stride {
  _Stride(this.x, this.y, this.lastMove);

  double x;
  double y;
  double lastMove;
  double travelled = 0;
}
