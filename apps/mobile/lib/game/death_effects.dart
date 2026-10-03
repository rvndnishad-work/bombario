import 'dart:ui';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import 'sprite_atlas.dart';

/// Short-lived animations the rules don't track: bricks bursting into
/// chunks, and enemies and players dying frame by frame the way the 8-bit
/// original's do (a shocked white flash, then hand-drawn death frames; an
/// enemy's points float up as it goes).
///
/// Effects are spotted by comparing consecutive snapshots, so they work the
/// same in solo play and in rooms, where the server's events never reach
/// the renderer.
class DeathEffects {
  /// How long each animation runs, in seconds.
  static const double brickTime = 0.5;
  static const double enemyTime = 1.0;
  static const double pointsTime = 1.4;

  /// The original's death takes about a second, and a respawn comes later
  /// than that, so the pop finishes before the player is back.
  static const double playerTime = 1.0;

  /// More bricks than this vanishing at once is a new maze, not a blast.
  static const int maxBurstsPerFrame = 24;

  /// The brick sprite in the stage's look, so the crumble matches the wall.
  String brickSprite = 'brick';

  final List<_BrickBurst> _bricks = [];
  final List<_EnemyDeath> _enemies = [];
  final List<_PlayerDeath> _players = [];

  List<core.TileType>? _tiles;
  int _width = 0;
  Map<int, core.EnemyState> _alive = {};
  Map<int, core.PlayerState> _standing = {};

  int get activeBricks => _bricks.length;
  int get activeEnemies => _enemies.length;
  int get activePlayers => _players.length;

  /// Looks for bricks that broke and enemies and players that died since
  /// the last call. [playerSprites] gives the layers (body, then hat) to
  /// pop for the player in a slot; without it players vanish as before.
  void observe(
    core.WorldSnapshot sim,
    double now,
    String? Function(core.EnemyState) spriteFor, {
    List<String> Function(int slot, core.PlayerState)? playerSprites,
  }) {
    final grid = sim.grid;
    final tiles = [
      for (var y = 0; y < grid.height; y++)
        for (var x = 0; x < grid.width; x++) grid.at(x, y),
    ];
    final before = _tiles;
    // A different maze (next stage, or the first frame) animates nothing:
    // its bricks didn't break and its enemies didn't die.
    var newMaze =
        before == null || before.length != tiles.length || _width != grid.width;
    final broke = <int>[];
    if (!newMaze) {
      var grew = 0;
      for (var i = 0; i < tiles.length; i++) {
        final was = before[i] == core.TileType.brick;
        final isBrick = tiles[i] == core.TileType.brick;
        if (was && !isBrick) broke.add(i);
        if (!was && isBrick) grew++;
      }
      // Bricks only reappear one at a time (possessed bricks regrowing).
      newMaze = broke.length > maxBurstsPerFrame || grew > 4;
    }
    if (!newMaze) {
      for (final i in broke) {
        _bricks.add(_BrickBurst(i % grid.width, i ~/ grid.width, now));
      }
    }
    _tiles = tiles;
    _width = grid.width;

    final alive = {
      for (final e in sim.enemies)
        if (e.alive) e.id: e,
    };
    // Several enemies in one blast score double each, as the rules do.
    var caught = 0;
    for (final MapEntry(key: id, value: e) in _alive.entries) {
      if (newMaze || alive.containsKey(id)) continue;
      final points = e.kindData?.points ?? 0;
      _enemies.add(
        _EnemyDeath(
          x: e.x,
          y: e.y,
          sprite: spriteFor(e),
          size: (e.kindData?.size ?? 0.4) * 2.5,
          points: points > 0 ? core.World.multiKillPoints(points, caught++) : 0,
          flip: e.facing == core.Direction.left,
          born: now,
        ),
      );
    }
    _alive = alive;

    final standing = {
      for (final p in sim.players)
        if (p.alive) p.id: p,
    };
    if (playerSprites != null && !newMaze) {
      for (var slot = 0; slot < sim.players.length; slot++) {
        final p = sim.players[slot];
        final was = _standing[p.id];
        if (was == null || p.alive) continue;
        _players.add(
          _PlayerDeath(
            x: was.x,
            y: was.y,
            sprites: playerSprites(slot, was),
            flip: was.facing == core.Direction.left,
            born: now,
          ),
        );
      }
    }
    _standing = standing;

    _bricks.removeWhere((b) => now - b.born > brickTime);
    _enemies.removeWhere((e) => now - e.born > pointsTime);
    _players.removeWhere((p) => now - p.born > playerTime);
  }

  /// Brick chunks fly out over the flames.
  void drawBricks(
    Canvas canvas,
    SpriteAtlas atlas,
    double tileSize,
    double now,
  ) {
    for (final b in _bricks) {
      final t = ((now - b.born) / brickTime).clamp(0.0, 1.0);
      final tile = Rect.fromLTWH(
        b.x * tileSize,
        b.y * tileSize,
        tileSize,
        tileSize,
      );
      // First a hot glow on the whole brick...
      if (t < 0.35) {
        atlas.draw(canvas, brickSprite, tile);
        canvas.drawRect(
          tile,
          Paint()..color = Color.fromRGBO(255, 150, 40, 0.75 * (1 - t / 0.35)),
        );
        continue;
      }
      // ...then it splits into four chunks that fly apart and fall.
      final k = (t - 0.35) / 0.65;
      final half = tileSize / 2;
      for (var q = 0; q < 4; q++) {
        final dx = q.isEven ? -1.0 : 1.0;
        final dy = q < 2 ? -1.0 : 1.0;
        final quarter = Rect.fromLTWH(
          tile.left + (q.isEven ? 0 : half),
          tile.top + (q < 2 ? 0 : half),
          half,
          half,
        );
        final offset = Offset(
          dx * k * tileSize * 0.6,
          dy * k * tileSize * 0.35 + k * k * tileSize * 0.6,
        );
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        final c = quarter.center;
        canvas.translate(c.dx, c.dy);
        canvas.rotate(dx * k * 1.2);
        canvas.scale(1 - 0.5 * k);
        canvas.translate(-c.dx, -c.dy);
        canvas.clipRect(quarter);
        atlas.draw(canvas, brickSprite, tile, paint: SpriteAtlas.faded(1 - k));
        canvas.restore();
      }
    }
  }

  static final Paint _white = Paint()
    ..filterQuality = FilterQuality.none
    ..colorFilter = const ColorFilter.mode(
      Color(0xFFFFFFFF),
      BlendMode.srcATop,
    );

  /// When each step of an enemy's death ends, as a share of [enemyTime]:
  /// the shocked flash, then the X-shaped burst that puffs up, shrinks and
  /// flies apart (`<sprite>-die-1` to `-4` in the atlas).
  static const List<double> enemySteps = [0.45, 0.62, 0.76, 0.88, 1.0];

  /// Same for players: a white flash, then the six frames of the bomber's
  /// death (`p<n>-die-1` to `-6`): X-eyed shock, a squash into a puddle,
  /// and a ring that breaks into specks.
  static const List<double> playerSteps = [
    0.1,
    0.3,
    0.42,
    0.54,
    0.68,
    0.84,
    1.0,
  ];

  /// How far the hat sits below its usual place on each frame, in sprite
  /// pixels; it is lost once the head has sunk.
  static const List<int> _hatDrop = [0, 0, 1, 4];

  /// Which step a death [t] (0 to 1) of the way through is on.
  static int step(List<double> steps, double t) {
    var i = 0;
    while (i < steps.length - 1 && t >= steps[i]) {
      i++;
    }
    return i;
  }

  /// Enemies flash in shock, burst frame by frame like the original's, and
  /// leave their points behind.
  void drawEnemies(
    Canvas canvas,
    SpriteAtlas atlas,
    double tileSize,
    double now,
  ) {
    for (final e in _enemies) {
      final age = now - e.born;
      final centre = Offset(e.x * tileSize, e.y * tileSize);
      final side = e.size * tileSize;
      if (age < enemyTime) {
        final frame = step(enemySteps, age / enemyTime);
        var name = e.sprite;
        Paint? paint;
        if (frame == 0) {
          // Shocked: blinks white, frozen in place.
          if ((age * 16).floor().isEven) paint = _white;
        } else {
          final own = '${e.sprite}-die-$frame';
          name = SpriteAtlas.has(own) ? own : 'edie-$frame';
        }
        canvas.save();
        canvas.translate(centre.dx, centre.dy);
        if (e.flip) canvas.scale(-1, 1);
        final dst = Rect.fromCenter(
          center: Offset.zero,
          width: side,
          height: side,
        );
        if (name == null || !atlas.draw(canvas, name, dst, paint: paint)) {
          canvas.drawOval(dst, Paint()..color = const Color(0xFFF58CCB));
        }
        canvas.restore();
      }
      if (e.points > 0 && age > 0.4) {
        final k = ((age - 0.4) / (pointsTime - 0.4)).clamp(0.0, 1.0);
        _points(
          canvas,
          e.points,
          centre - Offset(0, k * tileSize * 0.8),
          tileSize,
          1 - k,
        );
      }
    }
  }

  /// Players flash white, then play the bomber's death frame by frame.
  void drawPlayers(
    Canvas canvas,
    SpriteAtlas atlas,
    double tileSize,
    double now,
  ) {
    for (final p in _players) {
      final t = ((now - p.born) / playerTime).clamp(0.0, 1.0);
      final frame = step(playerSteps, t);
      final centre = Offset(p.x * tileSize, p.y * tileSize - tileSize * 0.08);
      final dst = Rect.fromCenter(
        center: centre,
        width: tileSize,
        height: tileSize,
      );
      final body = p.sprites.first;
      canvas.save();
      if (p.flip) {
        canvas.translate(centre.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-centre.dx, 0);
      }
      if (frame == 0) {
        for (final sprite in p.sprites) {
          atlas.draw(canvas, sprite, dst, paint: _white);
        }
      } else {
        final own = '$body-die-$frame';
        atlas.draw(canvas, SpriteAtlas.has(own) ? own : 'p1-die-$frame', dst);
        if (frame < _hatDrop.length) {
          final hat = dst.shift(Offset(0, _hatDrop[frame] * tileSize / 16));
          for (final sprite in p.sprites.skip(1)) {
            atlas.draw(canvas, sprite, hat);
          }
        }
      }
      canvas.restore();
    }
  }

  final Map<int, TextPainter> _labels = {};

  void _points(
    Canvas canvas,
    int points,
    Offset at,
    double tileSize,
    double opacity,
  ) {
    final label = _labels.putIfAbsent(points, () {
      return TextPainter(
        text: TextSpan(
          text: '$points',
          style: TextStyle(
            fontFamily: 'PressStart2P',
            fontSize: tileSize * 0.32,
            color: const Color(0xFFFFFFFF),
            shadows: const [Shadow(offset: Offset(1, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    canvas.saveLayer(
      Rect.fromCenter(
        center: at,
        width: label.width + 8,
        height: label.height + 8,
      ),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    label.paint(canvas, at - Offset(label.width / 2, label.height / 2));
    canvas.restore();
  }
}

class _BrickBurst {
  _BrickBurst(this.x, this.y, this.born);
  final int x;
  final int y;
  final double born;
}

class _PlayerDeath {
  _PlayerDeath({
    required this.x,
    required this.y,
    required this.sprites,
    required this.flip,
    required this.born,
  });
  final double x;
  final double y;
  final List<String> sprites;
  final bool flip;
  final double born;
}

class _EnemyDeath {
  _EnemyDeath({
    required this.x,
    required this.y,
    required this.sprite,
    required this.size,
    required this.points,
    required this.flip,
    required this.born,
  });
  final double x;
  final double y;
  final String? sprite;
  final double size;
  final int points;
  final bool flip;
  final double born;
}
