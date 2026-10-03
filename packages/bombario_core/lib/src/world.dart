import 'dart:collection';
import 'dart:math';

import 'direction.dart';
import 'entities.dart';
import 'events.dart';
import 'grid.dart';
import 'input.dart';
import 'level.dart';
import 'movement.dart';

/// Rules that differ between modes and stages.
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
    this.ghosts = false,
    this.sharedLives = 0,
    this.friendlyStun = false,
    this.stalactiteInterval = 0,
    this.bonusStage = false,
    this.bonusKind = EnemyKind.puffball,
    this.bonusEnemies = 0,
    this.bossStage = false,
  });

  /// Solo: step on the exit and you're done.
  static const solo = WorldConfig();

  /// Co-op: everyone alive gathers near the exit for three seconds; the
  /// fallen become ghosts that teammates can revive from a shared pool.
  static const coop = WorldConfig(
    exitHoldSeconds: 3,
    requireAllPlayersAtExit: true,
    ghosts: true,
    sharedLives: 4,
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

  /// Dead players become ghosts instead of leaving the stage (co-op).
  final bool ghosts;

  /// Revives the team can still afford (§4.1 shared lives pool).
  final int sharedLives;

  /// A teammate's flame stuns instead of kills (tutorial stages 1-1, 1-2).
  final bool friendlyStun;

  /// Seconds between falling rocks near players, 0 for none (World 2).
  final double stalactiteInterval;

  /// Bonus stage: no exit, enemies keep coming, survive the timer.
  final bool bonusStage;
  final EnemyKind bonusKind;
  final int bonusEnemies;

  /// Boss stage: cleared as soon as every enemy is dead.
  final bool bossStage;

  WorldConfig copyWith({
    int? sharedLives,
    bool? friendlyFire,
    bool? friendlyStun,
  }) =>
      WorldConfig(
        exitHoldSeconds: exitHoldSeconds,
        requireAllPlayersAtExit: requireAllPlayersAtExit,
        exitRadius: exitRadius,
        friendlyFire: friendlyFire ?? this.friendlyFire,
        hunterInterval: hunterInterval,
        hunterKind: hunterKind,
        exitGuardKind: exitGuardKind,
        exitGuardCount: exitGuardCount,
        versusMode: versusMode,
        ghosts: ghosts,
        sharedLives: sharedLives ?? this.sharedLives,
        friendlyStun: friendlyStun ?? this.friendlyStun,
        stalactiteInterval: stalactiteInterval,
        bonusStage: bonusStage,
        bonusKind: bonusKind,
        bonusEnemies: bonusEnemies,
        bossStage: bossStage,
      );
}

/// A quick-chat marker on the map.
class Ping {
  Ping(this.playerId, this.kind, this.x, this.y, this.ttl);
  final int playerId;
  final PingKind kind;
  final int x;
  final int y;
  double ttl;
}

/// What Sonar showed under a brick, visible to the whole team for a while.
class SonarReveal {
  SonarReveal(this.x, this.y, this.type, this.ttl);
  final int x;
  final int y;
  final ItemType type;
  double ttl;
}

/// A telegraphed falling rock: a shadow for [warn] seconds, then impact.
class Hazard {
  Hazard(this.x, this.y, this.warn);
  final int x;
  final int y;
  double warn;
}

/// The whole simulation for one stage. Deterministic given the level, the
/// seed and the sequence of inputs, which is what lets the server and the
/// client run the same code.
class World {
  World(this.level, {int seed = 0, this.config = WorldConfig.solo})
      : grid = level.grid,
        timeLeft = level.timeLimit,
        livesLeft = config.sharedLives,
        _rng = Random(seed) {
    for (final spawn in level.enemySpawns) {
      spawnEnemy(spawn.pos, spawn.kind, hp: spawn.hp);
    }
  }

  // Tuning from the design doc.
  static const double reviveSeconds = 2;
  static const int tetherRange = 4;
  static const double hauntRange = 3;
  static const double hauntSeconds = 3;
  static const double pingSeconds = 4;
  static const double pingCooldown = 1;
  static const int sonarRadius = 5;
  static const double sonarSeconds = 6;
  static const double freezeSeconds = 3;
  static const double stunSeconds = 1.5;
  static const double rockWarning = 1.2;

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
  final List<Ping> pings = [];
  final List<SonarReveal> sonar = [];
  final List<Hazard> hazards = [];

  /// Revives left in the shared pool (co-op).
  int livesLeft;

  /// Events produced by the most recent [tick].
  final List<GameEvent> events = [];

  double timeLeft;
  double elapsed = 0;
  bool timeUp = false;
  double _hunterTimer = 0;
  double _exitHold = 0;
  bool cleared = false;
  bool failed = false;
  double _rockTimer = 0;
  final Map<GridPos, int> _cracks = {};
  final Map<int, double> _pingCooldowns = {};

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
  Iterable<Player> get ghosts => players.where((p) => p.ghost);

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

  Enemy spawnEnemy(GridPos at, EnemyKind kind, {int? hp}) {
    final e = Enemy(
      id: _nextId++,
      x: at.x + 0.5,
      y: at.y + 0.5,
      kind: kind,
      hp: hp,
    );
    switch (kind.style) {
      case MoveStyle.bounce:
        e.vx = _rng.nextBool() ? 1 : -1;
        e.vy = _rng.nextBool() ? 1 : -1;
      case MoveStyle.burrow:
        e.state = EnemyStateKind.underground;
        e.stateFor = 1.5;
      default:
        break;
    }
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
    player.ghost = false;
    player.tombstone = null;
    player.frozenFor = 0;
    player.lastTile = null;
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
      if (p.invincibleFor > 0) p.invincibleFor = max(0, p.invincibleFor - dt);
      final input = inputs[p.id] ?? PlayerInput.idle;
      if (input.ping != PingKind.none) _ping(p, input.ping);
      if (p.ghost) {
        _movePlayer(p, input.direction, dt);
        if (input.action) _haunt(p);
        continue;
      }
      if (!p.alive) continue;
      if (p.frozenFor > 0) {
        p.frozenFor = max(0, p.frozenFor - dt);
        continue;
      }
      _movePlayer(p, input.direction, dt);
      _tryKick(p, input.direction);
      if (input.placeBomb) _placeBomb(p);
      if (input.action) _useActive(p);
      _trackTile(p);
    }
    _updateBombPassability();
    _tickBombs(dt);
    _tickFlames(dt);
    _tickEnemies(dt);
    _tickHazards(dt);
    _tickMarkers(dt);
    _pickUpItems();
    _checkEnemyContact();
    _checkRevives(dt);
    if (config.versusMode) {
      _checkVersusEnd();
    } else {
      if (config.bossStage) {
        _checkBossCleared();
      } else if (!config.bonusStage) {
        _checkExit(dt);
      }
      _checkFailure();
    }
  }

  void _tickTimer(double dt) {
    if (config.bonusStage) {
      _topUpBonusEnemies();
      timeLeft = max(0, timeLeft - dt);
      if (timeLeft <= 0 && !cleared) {
        cleared = true;
        events.add(const StageCleared());
      }
      return;
    }
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

  void _topUpBonusEnemies() {
    final alive =
        enemies.where((e) => e.alive && e.kind == config.bonusKind).length;
    for (var i = alive; i < config.bonusEnemies; i++) {
      final tile = _randomFloorTileFarFromPlayers(4);
      if (tile == null) return;
      spawnEnemy(tile, config.bonusKind);
    }
  }

  // ------------------------------------------------------------- movement

  bool _tileSolidFor(Player p, int x, int y) {
    final t = grid.at(x, y);
    if (t == TileType.pillar) return true;
    if (p.ghost) return false; // ghosts float through everything else
    if (t == TileType.pit) return true;
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

  /// Walking into a bomb with Kick sends it sliding (§5.2).
  void _tryKick(Player p, Direction dir) {
    if (!p.kick || dir == Direction.none) return;
    final bx = p.tileX + dir.dx, by = p.tileY + dir.dy;
    final b = bombAt(bx, by);
    if (b == null ||
        b.slide != Direction.none ||
        b.passableFor.contains(p.id)) {
      return;
    }
    final along =
        dir.isHorizontal ? (bx + 0.5 - p.x).abs() : (by + 0.5 - p.y).abs();
    final across = dir.isHorizontal ? p.offsetY.abs() : p.offsetX.abs();
    if (along > 0.5 + Player.halfBox + 0.05 || across > 0.3) return;
    if (!_bombCanEnter(bx + dir.dx, by + dir.dy)) return;
    b.slide = dir;
    b.slideProgress = 0;
    events.add(BombKicked(p.id, bx, by));
  }

  /// Cracked floor collapses once a player leaves it after the second
  /// walk-over (§8.1, World 2).
  void _trackTile(Player p) {
    final now = p.tile;
    final before = p.lastTile;
    if (before == now) return;
    if (before != null &&
        grid.atPos(before) == TileType.cracked &&
        (_cracks[before] ?? 0) >= 2 &&
        !players.any((o) => o.alive && o.tile == before)) {
      _collapse(before);
    }
    if (grid.atPos(now) == TileType.cracked) {
      _cracks[now] = (_cracks[now] ?? 0) + 1;
    }
    p.lastTile = now;
  }

  void _collapse(GridPos at) {
    grid.set(at.x, at.y, TileType.pit);
    _cracks.remove(at);
    final bomb = bombAt(at.x, at.y);
    if (bomb != null) {
      bombs.remove(bomb);
      playerById(bomb.ownerId)?.bombsPlaced--;
    }
    for (final e in enemies) {
      if (e.alive && e.solid && !e.kind.boss && e.tile == at) {
        _killEnemy(e, -2);
      }
    }
    events.add(FloorCollapsed(at.x, at.y));
  }

  void _useActive(Player p) {
    switch (p.active) {
      case ActiveItem.remote:
        _detonateOldest(p);
      case ActiveItem.tether:
        _tether(p);
      case ActiveItem.none:
        break;
    }
  }

  // ------------------------------------------------- ghosts and revives

  void _haunt(Player ghost) {
    if (ghost.hauntUsed) return;
    Enemy? best;
    var bestD = hauntRange;
    for (final e in enemies) {
      if (!e.alive || !e.solid) continue;
      final d = sqrt(pow(e.x - ghost.x, 2) + pow(e.y - ghost.y, 2));
      if (d <= bestD) {
        bestD = d;
        best = e;
      }
    }
    if (best == null) return;
    best.slowFor = hauntSeconds;
    ghost.hauntUsed = true;
    events.add(Haunted(ghost.id, best.id));
  }

  void _tether(Player p) {
    if (livesLeft <= 0) return;
    Player? best;
    var bestD = tetherRange + 1;
    for (final g in ghosts) {
      final t = g.tombstone;
      if (t == null) continue;
      final d = t.manhattanTo(p.tile);
      if (d < bestD) {
        bestD = d;
        best = g;
      }
    }
    if (best == null) return;
    _revive(best, p.id);
    p.active = ActiveItem.none;
  }

  void _checkRevives(double dt) {
    for (final g in players) {
      final t = g.tombstone;
      if (!g.ghost || t == null) continue;
      Player? rescuer;
      for (final p in alivePlayers) {
        if (p.tile == t) rescuer = p;
      }
      if (rescuer == null || livesLeft <= 0) {
        g.reviveProgress = 0;
        continue;
      }
      g.reviveProgress += dt;
      if (g.reviveProgress >= reviveSeconds) _revive(g, rescuer.id);
    }
  }

  void _revive(Player g, int byId) {
    final t = g.tombstone ?? g.tile;
    g.ghost = false;
    g.alive = true;
    g.tombstone = null;
    g.reviveProgress = 0;
    g.hauntUsed = false;
    g.frozenFor = 0;
    g.setPosition(t.x + 0.5, t.y + 0.5);
    g.lastTile = null;
    g.invincibleFor = 2;
    livesLeft--;
    events.add(PlayerRevived(g.id, byId));
  }

  void _ping(Player p, PingKind kind) {
    final cooldown = _pingCooldowns[p.id] ?? -1;
    if (elapsed < cooldown) return;
    _pingCooldowns[p.id] = elapsed + pingCooldown;
    pings.removeWhere((x) => x.playerId == p.id);
    pings.add(Ping(p.id, kind, p.tileX, p.tileY, pingSeconds));
    events.add(Pinged(p.id, kind, p.tileX, p.tileY));
  }

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
    if (!grid.isWalkable(x, y)) return null;
    final bomb = Bomb(
      id: _nextId++,
      x: x,
      y: y,
      ownerId: p.id,
      range: p.fireRange,
      fuse: Bomb.defaultFuse,
      remote: p.remote,
    );
    if (p.frostBombs > 0) {
      bomb.frost = true;
      p.frostBombs--;
    }
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

  /// Can a sliding bomb move onto this tile?
  bool _bombCanEnter(int x, int y) {
    if (!grid.isWalkable(x, y)) return false;
    if (bombAt(x, y) != null) return false;
    for (final e in enemies) {
      if (e.alive && e.solid && e.tile == GridPos(x, y)) return false;
    }
    for (final p in alivePlayers) {
      if (_overlapsTile(p, x, y)) return false;
    }
    return true;
  }

  void _tickBombs(double dt) {
    final due = <Bomb>[];
    for (final b in bombs) {
      if (b.slide != Direction.none) {
        b.slideProgress += Bomb.kickSpeed * dt;
        while (b.slideProgress >= 1) {
          final nx = b.x + b.slide.dx, ny = b.y + b.slide.dy;
          if (!_bombCanEnter(nx, ny)) {
            b.slide = Direction.none;
            b.slideProgress = 0;
            break;
          }
          b.x = nx;
          b.y = ny;
          b.slideProgress -= 1;
          b.passableFor.clear();
          if (flameAt(nx, ny) != null) {
            due.add(b);
            break;
          }
        }
      }
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
    final frost = bomb.frost;
    void flame(int x, int y) =>
        _addFlame(x, y, bomb.ownerId, bomb.x, bomb.y, frost: frost);
    flame(bomb.x, bomb.y);
    for (final dir in Direction.cardinal) {
      for (var r = 1; r <= bomb.range; r++) {
        final x = bomb.x + dir.dx * r;
        final y = bomb.y + dir.dy * r;
        final tile = grid.at(x, y);
        if (tile == TileType.pillar) break;
        if (tile == TileType.brick) {
          // Frost freezes; it doesn't break bricks.
          if (!frost) _destroyBrick(x, y, bomb.ownerId);
          break;
        }
        final other = bombAt(x, y);
        if (other != null) {
          chain.add(other);
          break;
        }
        flame(x, y);
        if (!frost) _burnFloorItem(x, y);
      }
    }
    // Chain reactions detonate in the same tick.
    for (final other in chain) {
      if (bombs.contains(other)) _explode(other);
    }
  }

  void _addFlame(
    int x,
    int y,
    int ownerId,
    int originX,
    int originY, {
    bool frost = false,
  }) {
    for (final f in flames) {
      if (f.x == x && f.y == y) {
        f.ttl = Flame.duration;
        // A real flame overrides frost on the same tile.
        if (!frost) {
          f.frost = false;
          f.originX = originX;
          f.originY = originY;
        }
        return;
      }
    }
    flames.add(Flame(
      x: x,
      y: y,
      ownerId: ownerId,
      originX: originX,
      originY: originY,
      frost: frost,
    ));
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
    // Hit checks happen before expiry so a 0.5 s flame always hits.
    for (final p in players) {
      if (!p.alive || p.ghost) continue;
      final f = flameAt(p.tileX, p.tileY);
      if (f == null) continue;
      if (f.frost) {
        if (!p.frozen && !p.invincible) {
          p.frozenFor = freezeSeconds;
          events.add(PlayerFrozen(p.id));
        }
        continue;
      }
      if (p.invincible || p.flamePass) continue;
      final byTeammate = f.ownerId != p.id && playerById(f.ownerId) != null;
      if (byTeammate && !config.friendlyFire) continue;
      if (byTeammate && config.friendlyStun) {
        if (!p.frozen) {
          p.frozenFor = stunSeconds;
          events.add(PlayerFrozen(p.id));
        }
        continue;
      }
      _hurtPlayer(p, f.ownerId);
    }
    for (final e in enemies.toList()) {
      if (!e.alive) continue;
      if (e.hitCooldown > 0) {
        e.hitCooldown = max(0, e.hitCooldown - dt);
        continue;
      }
      if (!e.solid) continue;
      final f = _flameTouching(e);
      if (f != null) _hitEnemy(e, f);
    }
    flames.removeWhere((f) => f.ttl <= 0);
  }

  /// The flame on any tile the enemy's body overlaps. Bosses are big.
  Flame? _flameTouching(Enemy e) {
    final r = e.kind.size;
    if (r <= Player.halfBox + 1e-9) return flameAt(e.tileX, e.tileY);
    for (var y = (e.y - r).floor(); y <= (e.y + r - 1e-6).floor(); y++) {
      for (var x = (e.x - r).floor(); x <= (e.x + r - 1e-6).floor(); x++) {
        final f = flameAt(x, y);
        if (f != null) return f;
      }
    }
    return null;
  }

  void _hitEnemy(Enemy e, Flame f) {
    e.hitCooldown = Flame.duration + 0.1;
    if (f.frost) {
      if (e.kind.boss) {
        e.slowFor = freezeSeconds; // too big to freeze solid
      } else if (!e.frozen) {
        e.frozenFor = freezeSeconds;
        events.add(EnemyFrozen(e));
      }
      return;
    }
    // A frozen enemy shatters to any real flame.
    if (e.frozen) {
      _killEnemy(e, f.ownerId);
      return;
    }
    if (e.kind.ability == EnemyAbility.armoured) {
      if (e.state != EnemyStateKind.stunned && _flameFromFront(e, f)) {
        e.state = EnemyStateKind.stunned;
        e.stateFor = 3;
        e.target = null;
        e.snapToTile();
        events.add(EnemyStunned(e));
      } else {
        _killEnemy(e, f.ownerId);
      }
      return;
    }
    e.hp--;
    if (e.kind.boss) events.add(BossDamaged(e));
    if (e.hp <= 0) {
      _killEnemy(e, f.ownerId);
    } else if (e.kind.ability == EnemyAbility.spawnAtHalf &&
        !e.splitDone &&
        e.hp * 2 <= e.maxHp) {
      e.splitDone = true;
      for (final t in _openTilesNear(e.tile, 2).take(4)) {
        // Born inside the blast that hurt him; don't let it pop them.
        spawnEnemy(t, EnemyKind.puffball).hitCooldown = Flame.duration + 0.1;
      }
      events.add(EnemyStunned(e));
    }
  }

  /// Is the bomb that made [f] in front of the enemy (the way it faces)?
  bool _flameFromFront(Enemy e, Flame f) {
    final dx = (f.originX - e.tileX).sign;
    final dy = (f.originY - e.tileY).sign;
    if (dx == 0 && dy == 0) return false; // a bomb underneath hits the belly
    final facing = e.direction == Direction.none ? Direction.down : e.direction;
    return dx == facing.dx && dy == facing.dy;
  }

  /// A hit that a Heart can absorb.
  void _hurtPlayer(Player p, int killerId) {
    if (p.hearts > 0) {
      p.hearts--;
      p.invincibleFor = 1.5;
      events.add(HeartLost(p.id));
      return;
    }
    _killPlayer(p, killerId);
  }

  void _killPlayer(Player p, int killerId) {
    p.alive = false;
    p.frozenFor = 0;
    final lost = p.loseItemsOnDeath();
    _scatter(lost, p.tile);
    events.add(PlayerDied(p.id, killerId));
    if (config.ghosts) {
      p.ghost = true;
      p.tombstone = p.tile;
      p.reviveProgress = 0;
      p.hauntUsed = false;
      events.add(BecameGhost(p.id));
    }
  }

  /// Drops lost power-ups on free tiles near [at] for teammates (§3.4).
  void _scatter(List<ItemType> lost, GridPos at) {
    if (lost.isEmpty) return;
    final spots = _openTilesNear(at, 3)
        .where((t) =>
            t != at &&
            flameAt(t.x, t.y) == null &&
            !floorItems.any((i) => i.x == t.x && i.y == t.y))
        .toList()
      ..shuffle(_rng);
    for (var i = 0; i < lost.length && i < spots.length; i++) {
      floorItems.add(FloorItem(x: spots[i].x, y: spots[i].y, type: lost[i]));
    }
  }

  /// Walkable, bomb-free tiles reachable from [from] within [radius] steps,
  /// nearest first.
  List<GridPos> _openTilesNear(GridPos from, int radius) {
    final result = <GridPos>[];
    final seen = {from};
    var frontier = [from];
    for (var d = 0; d <= radius && frontier.isNotEmpty; d++) {
      final next = <GridPos>[];
      for (final t in frontier) {
        if (grid.isWalkable(t.x, t.y) && bombAt(t.x, t.y) == null) {
          result.add(t);
        }
        for (final dir in Direction.cardinal) {
          final n = t.step(dir.dx, dir.dy);
          if (seen.add(n) && grid.at(n.x, n.y) != TileType.pillar) next.add(n);
        }
      }
      frontier = next;
    }
    return result;
  }

  void _killEnemy(Enemy e, int killerId) {
    e.alive = false;
    playerById(killerId)?.score += e.kind.points;
    events.add(EnemyDied(e, killerId));
    if (e.kind.ability == EnemyAbility.split) {
      for (var i = 0; i < 2; i++) {
        final child = spawnEnemy(e.tile, EnemyKind.splitling);
        // Immune to the flame that split it; a long blast still gets them.
        child.hitCooldown = Flame.duration + 0.1;
      }
    }
  }

  // -------------------------------------------------------------- enemies

  bool _enemyCanEnter(Enemy e, int x, int y) {
    final t = grid.at(x, y);
    if (t == TileType.pillar || t == TileType.pit) return false;
    if (t == TileType.brick && !e.kind.wallPass) return false;
    if (bombAt(x, y) != null) return false;
    return true;
  }

  void _tickEnemies(double dt) {
    Set<GridPos>?
        danger; // computed lazily, only if a bomb-aware enemy needs it
    for (final e in enemies.toList()) {
      if (!e.alive) continue;
      if (e.slowFor > 0) e.slowFor = max(0, e.slowFor - dt);
      if (e.kind.lifespan > 0) {
        e.lifeLeft -= dt;
        if (e.lifeLeft <= 0) {
          e.alive = false;
          events.add(EnemyDied(e, -2));
          continue;
        }
      }
      if (e.frozenFor > 0) {
        e.frozenFor = max(0, e.frozenFor - dt);
        continue;
      }
      if (e.state == EnemyStateKind.stunned) {
        e.stateFor -= dt;
        if (e.stateFor <= 0) e.state = EnemyStateKind.normal;
        continue;
      }
      final pace = e.slowFor > 0 ? 0.4 : 1.0;
      switch (e.kind.style) {
        case MoveStyle.bounce:
          _moveBounce(e, e.kind.speed * pace * dt);
          continue;
        case MoveStyle.burrow:
          _tickBurrow(e, dt);
          continue;
        default:
          break;
      }
      if (e.kind.ability == EnemyAbility.hop && _tickHop(e, dt)) continue;
      var remaining = e.kind.speed * pace * dt;
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
    if (style == MoveStyle.patrol) {
      // Straight line, back and forth.
      if (open.contains(e.direction)) return e.direction;
      if (open.contains(e.direction.opposite)) return e.direction.opposite;
      return open[_rng.nextInt(open.length)];
    }
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

  /// Hopper: squat (telegraph), then jump two tiles over anything. Returns
  /// true when the hop took over this tick.
  bool _tickHop(Enemy e, double dt) {
    const airTime = 0.4;
    switch (e.state) {
      case EnemyStateKind.telegraph:
        e.stateFor -= dt;
        if (e.stateFor <= 0) {
          e.state = EnemyStateKind.airborne;
          e.stateFor = airTime;
          e.fromX = e.x;
          e.fromY = e.y;
        }
        return true;
      case EnemyStateKind.airborne:
        e.stateFor -= dt;
        final land = e.landing!;
        final t = (1 - e.stateFor / airTime).clamp(0.0, 1.0);
        e.setPosition(
          e.fromX + (land.x + 0.5 - e.fromX) * t,
          e.fromY + (land.y + 0.5 - e.fromY) * t,
        );
        if (e.stateFor <= 0) {
          e.setPosition(land.x + 0.5, land.y + 0.5);
          e.state = EnemyStateKind.normal;
          e.target = null;
          e.landing = null;
          e.abilityTimer = 0;
        }
        return true;
      default:
        e.abilityTimer += dt;
        if (e.abilityTimer < 3 || e.target != null) return false;
        final land = _hopLanding(e);
        if (land == null) {
          e.abilityTimer = 2.5; // try again shortly
          return false;
        }
        e.landing = land;
        e.state = EnemyStateKind.telegraph;
        e.stateFor = 0.5;
        return true;
    }
  }

  GridPos? _hopLanding(Enemy e) {
    final dirs = [...Direction.cardinal]..shuffle(_rng);
    if (e.direction != Direction.none) {
      dirs
        ..remove(e.direction)
        ..insert(0, e.direction);
    }
    for (final d in dirs) {
      final x = e.tileX + d.dx * 2, y = e.tileY + d.dy * 2;
      if (grid.isWalkable(x, y) && bombAt(x, y) == null) {
        e.direction = d;
        return GridPos(x, y);
      }
    }
    return null;
  }

  /// King Puffball: floats diagonally and bounces off pillars and bricks.
  void _moveBounce(Enemy e, double dist) {
    final step = dist / sqrt2;
    bool fits(double x, double y) {
      final r = e.kind.size;
      for (var ty = (y - r).floor(); ty <= (y + r - 1e-6).floor(); ty++) {
        for (var tx = (x - r).floor(); tx <= (x + r - 1e-6).floor(); tx++) {
          final t = grid.at(tx, ty);
          if (t == TileType.pillar || t == TileType.brick) return false;
        }
      }
      return true;
    }

    final nx = e.x + e.vx * step;
    if (fits(nx, e.y)) {
      e.setPosition(nx, e.y);
    } else {
      e.vx = -e.vx;
    }
    final ny = e.y + e.vy * step;
    if (fits(e.x, ny)) {
      e.setPosition(e.x, ny);
    } else {
      e.vy = -e.vy;
    }
    e.direction = e.vx > 0 ? Direction.right : Direction.left;
  }

  /// Rockjaw Worm: underground, then a rumble where it will surface, then
  /// the head is out and vulnerable, then it dives again.
  void _tickBurrow(Enemy e, double dt) {
    e.stateFor -= dt;
    if (e.stateFor > 0) return;
    switch (e.state) {
      case EnemyStateKind.underground:
        final near = alivePlayers.toList();
        GridPos? spot;
        if (near.isNotEmpty) {
          final target = near[_rng.nextInt(near.length)];
          final options = _openTilesNear(target.tile, 2)
              .where((t) => t.manhattanTo(target.tile) >= 1)
              .toList();
          if (options.isNotEmpty) spot = options[_rng.nextInt(options.length)];
        }
        spot ??= _randomFloorTileFarFromPlayers(0);
        if (spot != null) e.setPosition(spot.x + 0.5, spot.y + 0.5);
        e.state = EnemyStateKind.telegraph;
        e.stateFor = 1.0;
      case EnemyStateKind.telegraph:
        e.state = EnemyStateKind.normal;
        e.stateFor = 2.5;
      default:
        e.state = EnemyStateKind.underground;
        e.stateFor = 2.0;
    }
  }

  // ------------------------------------------------- hazards and markers

  void _tickHazards(double dt) {
    if (config.stalactiteInterval > 0) {
      _rockTimer += dt;
      final alive = alivePlayers.toList();
      if (_rockTimer >= config.stalactiteInterval && alive.isNotEmpty) {
        _rockTimer = 0;
        final target = alive[_rng.nextInt(alive.length)];
        final options = _openTilesNear(target.tile, 3);
        if (options.isNotEmpty) {
          final t = options[_rng.nextInt(options.length)];
          hazards.add(Hazard(t.x, t.y, rockWarning));
        }
      }
    }
    for (final h in hazards.toList()) {
      h.warn -= dt;
      if (h.warn > 0) continue;
      hazards.remove(h);
      events.add(RockFell(h.x, h.y));
      for (final p in players) {
        if (p.alive && !p.invincible && p.tile == GridPos(h.x, h.y)) {
          _hurtPlayer(p, -2);
        }
      }
      for (final e in enemies.toList()) {
        if (e.alive && e.solid && !e.kind.boss && e.tile == GridPos(h.x, h.y)) {
          _killEnemy(e, -2);
        }
      }
    }
  }

  void _tickMarkers(double dt) {
    for (final p in pings) {
      p.ttl -= dt;
    }
    pings.removeWhere((p) => p.ttl <= 0);
    for (final s in sonar) {
      s.ttl -= dt;
    }
    sonar.removeWhere((s) => s.ttl <= 0 || grid.at(s.x, s.y) != TileType.brick);
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
          switch (item.type) {
            case ItemType.sonar:
              _sonarPulse(p);
            case ItemType.teamBoost:
              for (final mate in alivePlayers) {
                if (mate == p) continue;
                mate.applyItem(ItemType.bombUp);
                mate.applyItem(ItemType.fireUp);
              }
            default:
              break;
          }
        }
      }
    }
  }

  void _sonarPulse(Player p) {
    for (var y = p.tileY - sonarRadius; y <= p.tileY + sonarRadius; y++) {
      for (var x = p.tileX - sonarRadius; x <= p.tileX + sonarRadius; x++) {
        if (!grid.inBounds(x, y)) continue;
        final hidden = grid.hiddenAt(x, y);
        if (hidden == null) continue;
        sonar.removeWhere((s) => s.x == x && s.y == y);
        sonar.add(SonarReveal(x, y, hidden, sonarSeconds));
      }
    }
    events.add(SonarPulse(p.id, p.tileX, p.tileY));
  }

  void _checkEnemyContact() {
    for (final p in players) {
      if (!p.alive || p.invincible) continue;
      for (final e in enemies) {
        if (!e.harmful) continue;
        final reach = e.kind.size + Player.halfBox;
        if ((e.x - p.x).abs() < reach && (e.y - p.y).abs() < reach) {
          _hurtPlayer(p, -1);
          break;
        }
      }
    }
  }

  void _checkBossCleared() {
    if (enemies.isEmpty || !allEnemiesDead || cleared) return;
    cleared = true;
    for (final p in alivePlayers) {
      p.score += timeLeft.floor() * 10;
    }
    events.add(const StageCleared());
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
        .where((p) => grid.isWalkable(p.x, p.y))
        .where((p) => bombAt(p.x, p.y) == null)
        .where((p) =>
            alivePlayers.every((pl) => pl.tile.manhattanTo(p) >= minDistance))
        .toList();
    if (candidates.isEmpty) return null;
    return candidates[_rng.nextInt(candidates.length)];
  }
}
