import 'dart:collection';
import 'dart:math';

import 'direction.dart';
import 'entities.dart';
import 'events.dart';
import 'grid.dart';
import 'input.dart';
import 'level.dart';
import 'movement.dart';

/// Rules that differ between modes.
class WorldConfig {
  const WorldConfig({
    this.exitHoldSeconds = 0,
    this.requireAllPlayersAtExit = false,
    this.exitRadius = 2,
    this.friendlyFire = true,
    this.hunterInterval = 10,
    this.hunterKind = EnemyKind.hunterCoin,
    this.exitGuardKind = EnemyKind.blueDrop,
    this.exitGuardCount = 3,
    this.versusMode = false,
  });

  /// Solo: step on the exit and you're done.
  static const solo = WorldConfig();

  /// Co-op: everyone alive gathers near the exit for three seconds.
  static const coop = WorldConfig(
    exitHoldSeconds: 3,
    requireAllPlayersAtExit: true,
  );

  /// Versus: no exit, last player standing wins (a draw when the last two
  /// die in the same blast).
  static const versus = WorldConfig(versusMode: true);

  final double exitHoldSeconds;
  final bool requireAllPlayersAtExit;
  final int exitRadius;
  final bool friendlyFire;
  final double hunterInterval;
  final EnemyKind hunterKind;
  final EnemyKind exitGuardKind;
  final int exitGuardCount;
  final bool versusMode;
}

/// The whole simulation for one stage. Deterministic given the level, the
/// seed and the sequence of inputs, which is what lets the server and the
/// client run the same code.
class World {
  World(this.level, {int seed = 0, this.config = WorldConfig.solo})
      : grid = level.grid,
        timeLeft = level.timeLimit,
        _rng = Random(seed) {
    for (final spawn in level.enemySpawns) {
      spawnEnemy(spawn.pos, spawn.kind);
    }
  }

  static const double tickRate = 30;
  static const double tickDt = 1 / tickRate;

  final LevelData level;
  final Grid grid;
  final WorldConfig config;
  final Random _rng;

  final List<Player> players = [];
  final List<Enemy> enemies = [];
  final List<Bomb> bombs = [];
  final List<Flame> flames = [];
  final List<FloorItem> floorItems = [];

  /// Events produced by the most recent [tick].
  final List<GameEvent> events = [];

  double timeLeft;
  double elapsed = 0;
  bool timeUp = false;
  double _hunterTimer = 0;
  double _exitHold = 0;
  bool cleared = false;
  bool failed = false;

  /// Versus only: set when the round ends. -1 means a draw.
  int? winnerId;

  /// True once nothing more can happen in this stage or round.
  bool get over => cleared || failed || winnerId != null;
  int _nextId = 1;

  GridPos? get exitTile {
    for (final item in floorItems) {
      if (item.type == ItemType.exit) return GridPos(item.x, item.y);
    }
    return null;
  }

  bool get exitRevealed => exitTile != null;
  bool get allEnemiesDead => enemies.every((e) => !e.alive);
  Iterable<Player> get alivePlayers => players.where((p) => p.alive);

  // ---------------------------------------------------------------- setup

  Player addPlayer({String name = ''}) {
    final spawn =
        level.playerSpawns[players.length % level.playerSpawns.length];
    final p = Player(
      id: _nextId++,
      x: spawn.x + 0.5,
      y: spawn.y + 0.5,
      name: name,
    );
    players.add(p);
    return p;
  }

  Enemy spawnEnemy(GridPos at, EnemyKind kind) {
    final e = Enemy(id: _nextId++, x: at.x + 0.5, y: at.y + 0.5, kind: kind);
    enemies.add(e);
    events.add(EnemySpawned(e));
    return e;
  }

  /// Puts a dead player back on their spawn point. The game layer decides
  /// whether a life is available.
  void respawn(Player player) {
    final spawn =
        level.playerSpawns[players.indexOf(player) % level.playerSpawns.length];
    player.setPosition(spawn.x + 0.5, spawn.y + 0.5);
    player.alive = true;
    player.invincibleFor = 2;
  }

  Player? playerById(int id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ----------------------------------------------------------------- tick

  /// Advances the simulation by [dt] seconds using one input per player.
  /// Missing players get [PlayerInput.idle].
  void tick(Map<int, PlayerInput> inputs, [double dt = tickDt]) {
    events.clear();
    if (over) return;
    elapsed += dt;

    _tickTimer(dt);
    for (final p in players) {
      if (!p.alive) continue;
      final input = inputs[p.id] ?? PlayerInput.idle;
      _movePlayer(p, input.direction, dt);
      if (input.placeBomb) _placeBomb(p);
      if (input.action && p.remote) _detonateOldest(p);
      if (p.invincibleFor > 0) p.invincibleFor = max(0, p.invincibleFor - dt);
    }
    _updateBombPassability();
    _tickBombs(dt);
    _tickFlames(dt);
    _tickEnemies(dt);
    _pickUpItems();
    _checkEnemyContact();
    if (config.versusMode) {
      _checkVersusEnd();
    } else {
      _checkExit(dt);
      _checkFailure();
    }
  }

  void _tickTimer(double dt) {
    if (timeUp) {
      _hunterTimer += dt;
      if (_hunterTimer >= config.hunterInterval) {
        _hunterTimer = 0;
        final tile = _randomFloorTileFarFromPlayers(6);
        if (tile != null) spawnEnemy(tile, config.hunterKind);
      }
      return;
    }
    timeLeft -= dt;
    if (timeLeft <= 0) {
      timeLeft = 0;
      timeUp = true;
      events.add(const TimeUp());
      // First wave arrives immediately, like the NES Pontans.
      final tile = _randomFloorTileFarFromPlayers(6);
      if (tile != null) spawnEnemy(tile, config.hunterKind);
    }
  }

  // ------------------------------------------------------------- movement

  bool _tileSolidFor(Player p, int x, int y) {
    final t = grid.at(x, y);
    if (t == TileType.pillar) return true;
    if (t == TileType.brick && !p.wallPass) return true;
    if (!p.bombPass) {
      for (final b in bombs) {
        if (b.x == x && b.y == y && !b.passableFor.contains(p.id)) return true;
      }
    }
    return false;
  }

  late final Movement _movement = Movement(_tileSolidFor);

  void _movePlayer(Player p, Direction dir, double dt) =>
      _movement.move(p, dir, dt);

  // ---------------------------------------------------------------- bombs

  Bomb? bombAt(int x, int y) {
    for (final b in bombs) {
      if (b.x == x && b.y == y) return b;
    }
    return null;
  }

  bool _overlapsTile(Entity e, int x, int y) {
    const h = Player.halfBox;
    return (e.x - (x + 0.5)).abs() < 0.5 + h &&
        (e.y - (y + 0.5)).abs() < 0.5 + h;
  }

  Bomb? _placeBomb(Player p) {
    if (p.bombsPlaced >= p.maxBombs) return null;
    final x = p.tileX, y = p.tileY;
    if (bombAt(x, y) != null) return null;
    if (grid.at(x, y) != TileType.floor) return null;
    final bomb = Bomb(
      id: _nextId++,
      x: x,
      y: y,
      ownerId: p.id,
      range: p.fireRange,
      fuse: Bomb.defaultFuse,
      remote: p.remote,
    );
    for (final other in players) {
      if (other.alive && _overlapsTile(other, x, y)) {
        bomb.passableFor.add(other.id);
      }
    }
    bombs.add(bomb);
    p.bombsPlaced++;
    events.add(BombPlaced(bomb));
    return bomb;
  }

  void _detonateOldest(Player p) {
    for (final b in bombs) {
      if (b.ownerId == p.id && b.remote) {
        _explode(b);
        return;
      }
    }
  }

  void _updateBombPassability() {
    for (final b in bombs) {
      b.passableFor.removeWhere((id) {
        final p = playerById(id);
        return p == null || !_overlapsTile(p, b.x, b.y);
      });
    }
  }

  void _tickBombs(double dt) {
    final due = <Bomb>[];
    for (final b in bombs) {
      if (b.remote) continue;
      b.fuse -= dt;
      if (b.fuse <= 0) due.add(b);
    }
    for (final b in due) {
      if (bombs.contains(b)) _explode(b);
    }
  }

  void _explode(Bomb bomb) {
    bombs.remove(bomb);
    playerById(bomb.ownerId)?.bombsPlaced--;
    events.add(BombExploded(bomb.x, bomb.y, bomb.ownerId));

    final chain = <Bomb>[];
    _addFlame(bomb.x, bomb.y, bomb.ownerId);
    for (final dir in Direction.cardinal) {
      for (var r = 1; r <= bomb.range; r++) {
        final x = bomb.x + dir.dx * r;
        final y = bomb.y + dir.dy * r;
        final tile = grid.at(x, y);
        if (tile == TileType.pillar) break;
        if (tile == TileType.brick) {
          _destroyBrick(x, y, bomb.ownerId);
          break;
        }
        final other = bombAt(x, y);
        if (other != null) {
          chain.add(other);
          break;
        }
        _addFlame(x, y, bomb.ownerId);
        _burnFloorItem(x, y);
      }
    }
    // Chain reactions detonate in the same tick.
    for (final other in chain) {
      if (bombs.contains(other)) _explode(other);
    }
  }

  void _addFlame(int x, int y, int ownerId) {
    for (final f in flames) {
      if (f.x == x && f.y == y) {
        f.ttl = Flame.duration;
        return;
      }
    }
    flames.add(Flame(x: x, y: y, ownerId: ownerId));
  }

  void _destroyBrick(int x, int y, int ownerId) {
    grid.set(x, y, TileType.floor);
    final revealed = grid.takeHidden(x, y);
    if (revealed != null) floorItems.add(FloorItem(x: x, y: y, type: revealed));
    playerById(ownerId)?.score += 10;
    events.add(BrickDestroyed(x, y, revealed));
  }

  void _burnFloorItem(int x, int y) {
    for (final item in floorItems.toList()) {
      if (item.x != x || item.y != y) continue;
      if (item.type == ItemType.exit) {
        // Bombing the exit angers it, as in the original.
        events.add(const ExitBombed());
        for (var i = 0; i < config.exitGuardCount; i++) {
          spawnEnemy(GridPos(x, y), config.exitGuardKind);
        }
      } else {
        floorItems.remove(item);
        events.add(ItemBurned(x, y, item.type));
      }
    }
  }

  // --------------------------------------------------------------- flames

  Flame? flameAt(int x, int y) {
    for (final f in flames) {
      if (f.x == x && f.y == y) return f;
    }
    return null;
  }

  void _tickFlames(double dt) {
    for (final f in flames) {
      f.ttl -= dt;
    }
    // Kill checks happen before expiry so a 0.5 s flame always hits.
    for (final p in players) {
      if (!p.alive || p.invincible || p.flamePass) continue;
      final f = flameAt(p.tileX, p.tileY);
      if (f == null) continue;
      if (!config.friendlyFire &&
          f.ownerId != p.id &&
          playerById(f.ownerId) != null) {
        continue;
      }
      _killPlayer(p, f.ownerId);
    }
    for (final e in enemies) {
      if (!e.alive) continue;
      if (e.hitCooldown > 0) {
        e.hitCooldown = max(0, e.hitCooldown - dt);
        continue;
      }
      final f = flameAt(e.tileX, e.tileY);
      if (f == null) continue;
      e.hp--;
      e.hitCooldown = Flame.duration + 0.1;
      if (e.hp <= 0) _killEnemy(e, f.ownerId);
    }
    flames.removeWhere((f) => f.ttl <= 0);
  }

  void _killPlayer(Player p, int killerId) {
    p.alive = false;
    p.loseItemsOnDeath();
    events.add(PlayerDied(p.id, killerId));
  }

  void _killEnemy(Enemy e, int killerId) {
    e.alive = false;
    playerById(killerId)?.score += e.kind.points;
    events.add(EnemyDied(e, killerId));
  }

  // -------------------------------------------------------------- enemies

  bool _enemyCanEnter(Enemy e, int x, int y) {
    final t = grid.at(x, y);
    if (t == TileType.pillar) return false;
    if (t == TileType.brick && !e.kind.wallPass) return false;
    if (bombAt(x, y) != null) return false;
    return true;
  }

  void _tickEnemies(double dt) {
    Set<GridPos>?
        danger; // computed lazily, only if a bomb-aware enemy needs it
    for (final e in enemies) {
      if (!e.alive) continue;
      var remaining = e.kind.speed * dt;
      while (remaining > 1e-9) {
        // Enemies decide only when centred on a tile, then commit to the
        // whole next tile. Cheap, deterministic, and very NES-feeling.
        if (e.target == null) {
          danger ??= e.kind.bombAware ? dangerTiles() : null;
          e.direction = _decideDirection(e, danger ?? const {});
          if (e.direction == Direction.none) break; // boxed in, wait
          e.target = e.tile.step(e.direction.dx, e.direction.dy);
        }
        final target = e.target!;
        final tx = target.x + 0.5, ty = target.y + 0.5;
        final toTarget = (tx - e.x).abs() + (ty - e.y).abs();
        final step = min(remaining, toTarget);
        remaining -= step;
        if (step >= toTarget - 1e-9) {
          e.setPosition(tx, ty);
          e.target = null;
        } else {
          e.setPosition(
              e.x + e.direction.dx * step, e.y + e.direction.dy * step);
        }
      }
    }
  }

  Direction _decideDirection(Enemy e, Set<GridPos> danger) {
    final open = <Direction>[];
    for (final d in Direction.cardinal) {
      if (_enemyCanEnter(e, e.tileX + d.dx, e.tileY + d.dy)) open.add(d);
    }
    if (open.isEmpty) return Direction.none;

    final style = e.kind.style;
    if (style == MoveStyle.chase || style == MoveStyle.phaseChase) {
      final step = _chaseStep(e, danger);
      if (step != null) return step;
    }

    // Bomb-aware enemies never step into a blast zone if they can help it,
    // and leave one they are standing in.
    var candidates = open;
    if (e.kind.bombAware) {
      final safe = open
          .where(
              (d) => !danger.contains(GridPos(e.tileX + d.dx, e.tileY + d.dy)))
          .toList();
      if (safe.isNotEmpty) candidates = safe;
    }

    // Wander: keep going most of the time, avoid doubling back.
    if (e.direction != Direction.none &&
        candidates.contains(e.direction) &&
        _rng.nextDouble() > e.kind.turnChance) {
      return e.direction;
    }
    final forward = candidates.where((d) => d != e.direction.opposite).toList();
    final pool = forward.isNotEmpty ? forward : candidates;
    return pool[_rng.nextInt(pool.length)];
  }

  /// First step of a BFS path to the nearest living player within sight,
  /// or null when none is in range.
  Direction? _chaseStep(Enemy e, Set<GridPos> danger) {
    final targets = {for (final p in alivePlayers) p.tile};
    if (targets.isEmpty) return null;
    final start = e.tile;
    final avoidDanger = e.kind.bombAware;
    final visited = <GridPos, Direction>{start: Direction.none};
    final queue = Queue<GridPos>()..add(start);
    final dist = <GridPos, int>{start: 0};

    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      if (dist[cur]! > e.kind.sightRange) break;
      if (cur != start && targets.contains(cur)) {
        // Walk back to find the first step.
        var node = cur;
        var first = visited[node]!;
        while (visited[node] != Direction.none) {
          first = visited[node]!;
          node = node.step(-first.dx, -first.dy);
        }
        return first;
      }
      for (final d in Direction.cardinal) {
        final next = cur.step(d.dx, d.dy);
        if (visited.containsKey(next)) continue;
        if (!_enemyCanEnter(e, next.x, next.y)) continue;
        if (avoidDanger && danger.contains(next) && !targets.contains(next)) {
          continue;
        }
        visited[next] = d;
        dist[next] = dist[cur]! + 1;
        queue.add(next);
      }
    }
    return null;
  }

  /// Tiles that will be hit when the current bombs go off (flame-blocking
  /// rules applied). Enemies with [EnemyKind.bombAware] avoid these.
  Set<GridPos> dangerTiles() {
    final result = <GridPos>{};
    for (final f in flames) {
      result.add(GridPos(f.x, f.y));
    }
    for (final b in bombs) {
      result.add(b.tile);
      for (final dir in Direction.cardinal) {
        for (var r = 1; r <= b.range; r++) {
          final x = b.x + dir.dx * r, y = b.y + dir.dy * r;
          final t = grid.at(x, y);
          if (t == TileType.pillar) break;
          result.add(GridPos(x, y));
          if (t == TileType.brick) break;
        }
      }
    }
    return result;
  }

  // ------------------------------------------------------ items and exit

  void _pickUpItems() {
    for (final p in alivePlayers) {
      for (final item in floorItems.toList()) {
        if (item.type == ItemType.exit) continue;
        if (item.x == p.tileX && item.y == p.tileY) {
          floorItems.remove(item);
          p.applyItem(item.type);
          p.score += 100;
          events.add(ItemPicked(p.id, item.type));
        }
      }
    }
  }

  void _checkEnemyContact() {
    const reach = Player.halfBox * 2;
    for (final p in players) {
      if (!p.alive || p.invincible) continue;
      for (final e in enemies) {
        if (!e.alive) continue;
        if ((e.x - p.x).abs() < reach && (e.y - p.y).abs() < reach) {
          _killPlayer(p, -1);
          break;
        }
      }
    }
  }

  void _checkExit(double dt) {
    final exit = exitTile;
    if (exit == null || !allEnemiesDead) {
      _exitHold = 0;
      return;
    }
    final alive = alivePlayers.toList();
    if (alive.isEmpty) return;

    final bool ready;
    if (config.requireAllPlayersAtExit) {
      ready = alive.every((p) => p.tile.manhattanTo(exit) <= config.exitRadius);
    } else {
      ready = alive.any((p) => p.tile == exit);
    }
    if (!ready) {
      _exitHold = 0;
      return;
    }
    _exitHold += dt;
    if (_exitHold >= config.exitHoldSeconds) {
      cleared = true;
      for (final p in alive) {
        p.score += timeLeft.floor() * 10;
      }
      events.add(const StageCleared());
    }
  }

  /// How long the team has been gathered at the exit, for the HUD ring.
  double get exitHoldProgress => config.exitHoldSeconds == 0
      ? 0
      : (_exitHold / config.exitHoldSeconds).clamp(0, 1);

  void _checkFailure() {
    if (players.isNotEmpty && alivePlayers.isEmpty && !failed) {
      failed = true;
      events.add(const StageFailed());
    }
  }

  /// Called by the game layer after a respawn so a failed stage can continue.
  void clearFailure() => failed = false;

  void _checkVersusEnd() {
    if (players.length < 2) return;
    final alive = alivePlayers.toList();
    if (alive.length > 1) return;
    winnerId = alive.isEmpty ? -1 : alive.single.id;
    if (alive.isNotEmpty) alive.single.score += 1000;
    events.add(MatchEnded(winnerId!));
  }

  GridPos? _randomFloorTileFarFromPlayers(int minDistance) {
    final candidates = grid.positions
        .where((p) => grid.atPos(p) == TileType.floor)
        .where((p) => bombAt(p.x, p.y) == null)
        .where((p) =>
            alivePlayers.every((pl) => pl.tile.manhattanTo(p) >= minDistance))
        .toList();
    if (candidates.isEmpty) return null;
    return candidates[_rng.nextInt(candidates.length)];
  }
}
