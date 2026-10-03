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
    this.exitGuardKind = EnemyKind.doorWarden,
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
    this.ventInterval = 0,
    this.darkness = 0,
    this.windInterval = 0,
    this.cannonInterval = 0,
    this.keepItemsOnDeath = false,
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

  /// Seconds per steam-vent cycle, 0 for none (World 3). Each cycle ends
  /// with a [World.ventWarning] tell and a [World.ventFiring] jet.
  final double ventInterval;

  /// Vision radius in tiles for dark stages, 0 for lit (World 4). The
  /// renderer draws the darkness; the rules only use it for Shades.
  final int darkness;

  /// Seconds per wind gust, alternating left and right; 0 for none
  /// (World 5).
  final double windInterval;

  /// Seconds between cannon shots across a row, 0 for none (World 5).
  final double cannonInterval;

  /// Solo, as in the original: a fallen player keeps Bomb Up, Fire Up,
  /// Speed Up and Kick and loses only the specials. Otherwise half the
  /// power-ups drop for teammates.
  final bool keepItemsOnDeath;

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
        ventInterval: ventInterval,
        darkness: darkness,
        windInterval: windInterval,
        cannonInterval: cannonInterval,
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

/// What a [Hazard] marker will do when its warning runs out.
///
/// Serialised by index, so new values go at the end.
enum HazardKind {
  /// Falling rock on one tile (World 2).
  rock,

  /// A cannonball sweeps row [Hazard.y] from the left or right wall
  /// (World 5).
  cannonLeft,
  cannonRight,

  /// Overlord Pontan's arena closes this tile into a pillar.
  wall,
}

/// A telegraphed hazard: a marker for [warn] seconds, then impact.
class Hazard {
  Hazard(this.x, this.y, this.warn, {this.kind = HazardKind.rock});
  final int x;
  final int y;
  double warn;
  final HazardKind kind;
}

/// Steam vents: idle, then a visible tell, then the jet.
enum VentPhase { idle, warning, firing }

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
  static const double cannonWarning = 1.5;
  static const double ventWarning = 0.8;
  static const double ventFiring = 0.7;
  static const double regrowSeconds = 20;
  static const double windCalm = 2;
  static const double warpCooldown = 1;
  static const double curseSeconds = 10;
  static const double herdRange = 3;
  static const double herdBoost = 1.3;
  static const int shadeSight = 3;

  /// How far a player and an enemy may overlap, in tiles, before the touch
  /// counts. The original forgives a brush of the sprites; only a real
  /// overlap kills.
  static const double contactGrace = 0.2;

  static const double tickRate = 30;
  static const double tickDt = 1 / tickRate;

  /// No way of earning lives (1-Ups, points, rewards) goes past this.
  static const int maxLives = 7;

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

  /// Enemies each player has killed this tick, for the multi-kill bonus.
  final Map<int, int> _killsThisTick = {};

  /// Points for a kill: each further enemy caught in the same blast (chain
  /// reactions included) is worth double the one before, as in the original.
  static int multiKillPoints(int base, int nth) => base << min(nth, 10);
  bool cleared = false;
  bool failed = false;
  double _rockTimer = 0;
  final Map<GridPos, int> _cracks = {};

  /// Possessed bricks waiting to grow back: tile and seconds left.
  final Map<GridPos, double> regrowing = {};

  /// Current wind, [Direction.none] when calm.
  Direction wind = Direction.none;

  /// While calm, the gust that comes next, for the HUD tell.
  Direction windNext = Direction.none;

  VentPhase ventPhase = VentPhase.idle;

  /// Seconds until [ventPhase] changes.
  double ventTimeLeft = 0;
  double _cannonTimer = 0;
  bool gatesOpen = false;
  late final List<GridPos> _vents = [
    for (final p in grid.positions)
      if (grid.featureAt(p.x, p.y) == TileFeature.vent) p,
  ];

  /// Overlord Pontan's last phase: ring tiles still to close, in order.
  List<GridPos>? _shrinkQueue;
  double _shrinkTimer = 0;
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

  Player addPlayer({String name = '', String skin = Player.defaultSkin}) {
    final spawn =
        level.playerSpawns[players.length % level.playerSpawns.length];
    final p = Player(
      id: _nextId++,
      x: spawn.x + 0.5,
      y: spawn.y + 0.5,
      name: name,
      skin: skin,
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
    switch (kind.ability) {
      case EnemyAbility.mimic:
        e.state = EnemyStateKind.disguised;
        e.disguise = _mimicLooks[_rng.nextInt(_mimicLooks.length)];
      case EnemyAbility.nest:
        if (grid.atPos(at) == TileType.brick) {
          e.state = EnemyStateKind.underground;
        }
      case EnemyAbility.cloak:
        e.visible = false;
      case EnemyAbility.bombPatterns || EnemyAbility.witch:
        e.cooldown = 3;
      case EnemyAbility.overlord:
        e.cooldown = 4;
      default:
        break;
    }
    enemies.add(e);
    events.add(EnemySpawned(e));
    return e;
  }

  static const _mimicLooks = [
    ItemType.bombUp,
    ItemType.fireUp,
    ItemType.speedUp,
  ];

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
    _killsThisTick.clear();

    _tickTimer(dt);
    _tickWeather(dt);
    for (final p in players) {
      if (p.invincibleFor > 0) p.invincibleFor = max(0, p.invincibleFor - dt);
      if (p.warpCooldown > 0) p.warpCooldown = max(0, p.warpCooldown - dt);
      if (p.cursedFor > 0) {
        p.cursedFor = max(0, p.cursedFor - dt);
        if (p.cursedFor == 0) _liftCurse(p);
      }
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
        p.moveDir = Direction.none;
        continue;
      }
      _movement.step(p, input.direction, dt, grid: grid, wind: wind);
      _tryKick(p, p.moveDir);
      if (input.placeBomb) _placeBomb(p);
      if (input.action) _useActive(p);
      _trackTile(p);
    }
    _updateBombPassability();
    _tickBombs(dt);
    _tickFlames(dt);
    _tickEnemies(dt);
    _tickHazards(dt);
    _tickTerrain(dt);
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
    switch (grid.featureAt(now.x, now.y)) {
      case TileFeature.plate when !gatesOpen && grid.isWalkable(now.x, now.y):
        _openGates(now);
      case TileFeature.warp when p.warpCooldown <= 0:
        _warp(p, now);
      default:
        break;
    }
  }

  /// A pressure plate opens every gate on the stage for good.
  void _openGates(GridPos plate) {
    gatesOpen = true;
    for (final t in grid.positions) {
      if (grid.featureAt(t.x, t.y) == TileFeature.gate &&
          grid.atPos(t) == TileType.pillar) {
        grid.set(t.x, t.y, TileType.floor);
      }
    }
    events.add(GatesOpened(plate.x, plate.y));
  }

  /// Warp doors carry a player to the partner door.
  void _warp(Player p, GridPos from) {
    final to = grid.warpPartner(from);
    if (to == null ||
        !grid.isWalkable(to.x, to.y) ||
        bombAt(to.x, to.y) != null) {
      return;
    }
    p.setPosition(to.x + 0.5, to.y + 0.5);
    p.lastTile = to;
    p.momentum = Direction.none;
    p.warpCooldown = warpCooldown;
    events.add(PlayerWarped(p.id, from.x, from.y, to.x, to.y));
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
      // A still bomb on a conveyor rides it.
      if (b.slide == Direction.none) {
        final belt = grid.featureAt(b.x, b.y).conveyor;
        if (belt != Direction.none &&
            _bombCanEnter(b.x + belt.dx, b.y + belt.dy)) {
          b.slide = belt;
          b.slideProgress = 0;
          b.conveyed = true;
        }
      }
      if (b.slide != Direction.none) {
        var speed = b.conveyed ? Bomb.conveyorSpeed : Bomb.kickSpeed;
        // Wind pushes kicked bombs along and holds them back (World 5).
        if (!b.conveyed && wind != Direction.none) {
          if (b.slide == wind) speed *= 1.5;
          if (b.slide == wind.opposite) speed *= 0.5;
        }
        b.slideProgress += speed * dt;
        while (b.slideProgress >= 1) {
          final nx = b.x + b.slide.dx, ny = b.y + b.slide.dy;
          if (!_bombCanEnter(nx, ny)) {
            b.slide = Direction.none;
            b.slideProgress = 0;
            b.conveyed = false;
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
          if (b.conveyed) {
            // Off the belt, or onto one running another way: re-evaluate.
            b.slide = Direction.none;
            b.slideProgress = 0;
            b.conveyed = false;
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
    if (grid.featureAt(x, y) == TileFeature.possessed) {
      regrowing[GridPos(x, y)] = regrowSeconds;
    }
    final revealed = grid.takeHidden(x, y);
    if (revealed != null) {
      floorItems.add(FloorItem(x: x, y: y, type: revealed, fromBrick: true));
    }
    playerById(ownerId)?.score += 10;
    events.add(BrickDestroyed(x, y, revealed));
  }

  void _burnFloorItem(int x, int y) {
    for (final item in floorItems.toList()) {
      if (item.x != x || item.y != y) continue;
      if (item.type == ItemType.exit) {
        // Bombing the exit angers it, as in the original. The wave is
        // spared by the flame that summoned it.
        events.add(const ExitBombed());
        for (var i = 0; i < config.exitGuardCount; i++) {
          spawnEnemy(GridPos(x, y), config.exitGuardKind).hitCooldown =
              Flame.duration + 0.1;
        }
      } else {
        floorItems.remove(item);
        // Bombing a power-up you uncovered angers it too: it's gone and a
        // wave pours out, as in the original. Dropped items just burn.
        final wave = item.fromBrick &&
            !config.versusMode &&
            !config.bonusStage &&
            !config.bossStage;
        events.add(ItemBurned(x, y, item.type, releasedWave: wave));
        if (wave) {
          for (var i = 0; i < config.exitGuardCount; i++) {
            spawnEnemy(GridPos(x, y), config.exitGuardKind).hitCooldown =
                Flame.duration + 0.1;
          }
        }
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
    // Bomb-O-Tron's armour only opens after a volley.
    if (e.kind.ability == EnemyAbility.bombPatterns &&
        e.state != EnemyStateKind.vulnerable) {
      return;
    }
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
        spawnEnemy(t, EnemyKind.puffball)
          ..hitCooldown = Flame.duration + 0.1
          ..parentId = e.id;
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
    if (config.keepItemsOnDeath) {
      p.loseSpecialsOnDeath();
    } else {
      _scatter(p.loseItemsOnDeath(), p.tile);
    }
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
    final killer = playerById(killerId);
    if (killer != null) {
      final nth = _killsThisTick[killerId] ?? 0;
      _killsThisTick[killerId] = nth + 1;
      killer.score += multiKillPoints(e.kind.points, nth);
    }
    events.add(EnemyDied(e, killerId));
    if (e.linkedPlayer != 0) {
      final cursed = playerById(e.linkedPlayer);
      if (cursed != null && cursed.cursed) {
        cursed.cursedFor = 0;
        events.add(CurseLifted(cursed.id));
      }
    }
    // A boss takes its summons with it.
    if (e.kind.boss) {
      for (final m in enemies) {
        if (m.alive && m.parentId == e.id) {
          m.alive = false;
          events.add(EnemyDied(m, -2));
        }
      }
    }
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
    _updateAuras();
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
      if (_tickAbility(e, dt)) continue;
      var pace = e.slowFor > 0 ? 0.4 : 1.0;
      if (e.herded) pace *= herdBoost;
      switch (e.kind.style) {
        case MoveStyle.bounce:
          if (e.kind.ability == EnemyAbility.overlord) pace *= _copiedSpeed();
          _moveBounce(e, e.kind.speed * pace * dt);
          continue;
        case MoveStyle.burrow:
          _tickBurrow(e, dt);
          continue;
        case MoveStyle.stationary || MoveStyle.blink:
          continue;
        default:
          break;
      }
      // A bomb dropped (or a brick regrown) on the tile an enemy is walking
      // into turns it around on the spot, as in the original: that's how
      // you herd enemies with bombs.
      final heading = e.target;
      if (heading != null && !_enemyCanEnter(e, heading.x, heading.y)) {
        final back = heading.step(-e.direction.dx, -e.direction.dy);
        if (!_enemyCanEnter(e, back.x, back.y)) continue; // boxed in, wait
        e.direction = e.direction.opposite;
        e.target = back;
      }
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

  /// Per-tick auras: Shades show up near players and flames, Herders speed
  /// up their flock.
  void _updateAuras() {
    final herders = [
      for (final e in enemies)
        if (e.alive && e.kind.ability == EnemyAbility.herd && e.solid) e,
    ];
    for (final e in enemies) {
      if (!e.alive) continue;
      e.herded = !e.kind.boss &&
          e.kind.ability != EnemyAbility.herd &&
          e.kind.style != MoveStyle.stationary &&
          herders.any((h) => _dist(h.x, h.y, e.x, e.y) <= herdRange);
      if (e.kind.ability == EnemyAbility.cloak) {
        e.visible =
            alivePlayers.any((p) => _dist(p.x, p.y, e.x, e.y) <= shadeSight) ||
                flames.any((f) =>
                    (f.x - e.tileX).abs() <= 1 && (f.y - e.tileY).abs() <= 1);
      }
    }
  }

  static double _dist(double ax, double ay, double bx, double by) =>
      sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

  Direction _decideDirection(Enemy e, Set<GridPos> danger) {
    final open = <Direction>[];
    for (final d in Direction.cardinal) {
      if (_enemyCanEnter(e, e.tileX + d.dx, e.tileY + d.dy)) open.add(d);
    }
    if (open.isEmpty) return Direction.none;

    final style = e.kind.style;
    if (e.state == EnemyStateKind.fleeing ||
        (e.kind.ability == EnemyAbility.herd && _nearestPlayerSteps(e) <= 4)) {
      return _fleeStep(e, open, danger);
    }
    if (style == MoveStyle.mirror) return _mirrorStep(e, open);
    if (e.herded) {
      // A Herder drives its flock straight at the players.
      final step =
          _pathStep(e, {for (final p in alivePlayers) p.tile}, 10, danger);
      if (step != null) return step;
    }
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
    if (e.kind.ability == EnemyAbility.eatBombs) {
      // Fuse Eater: head for a tile next to the nearest bomb.
      final near = <GridPos>{
        for (final b in bombs)
          for (final d in Direction.cardinal) b.tile.step(d.dx, d.dy),
      };
      final step = _pathStep(e, near, 12, danger);
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

  /// Steps away from the nearest player, out of blast zones when possible.
  Direction _fleeStep(Enemy e, List<Direction> open, Set<GridPos> danger) {
    final dangerNow = danger.isEmpty ? dangerTiles() : danger;
    var candidates = open
        .where(
            (d) => !dangerNow.contains(GridPos(e.tileX + d.dx, e.tileY + d.dy)))
        .toList();
    if (candidates.isEmpty) candidates = open;
    Direction best = candidates.first;
    var bestScore = -1;
    for (final d in candidates) {
      final t = e.tile.step(d.dx, d.dy);
      var score = 999;
      for (final p in alivePlayers) {
        score = min(score, p.tile.manhattanTo(t));
      }
      if (d == e.direction.opposite) score -= 1; // don't dither
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best;
  }

  /// Mirror Knight: does what the nearest player does, left and right
  /// swapped. Stands still while they do.
  Direction _mirrorStep(Enemy e, List<Direction> open) {
    Player? nearest;
    var best = double.infinity;
    for (final p in alivePlayers) {
      final d = _dist(p.x, p.y, e.x, e.y);
      if (d < best) {
        best = d;
        nearest = p;
      }
    }
    if (nearest == null) return Direction.none;
    final move = nearest.moveDir;
    final mirrored = move.isHorizontal ? move.opposite : move;
    return open.contains(mirrored) ? mirrored : Direction.none;
  }

  /// Manhattan tile distance to the nearest living player.
  int _nearestPlayerSteps(Enemy e) {
    var best = 1 << 20;
    for (final p in alivePlayers) {
      best = min(best, p.tile.manhattanTo(e.tile));
    }
    return best;
  }

  // ------------------------------------------------------------ abilities

  /// Abilities that can take over an enemy's tick. Returns true when the
  /// enemy shouldn't walk this tick.
  bool _tickAbility(Enemy e, double dt) {
    if (e.cooldown > 0) e.cooldown = max(0, e.cooldown - dt);
    if (e.state == EnemyStateKind.fleeing) {
      e.stateFor -= dt;
      if (e.stateFor <= 0) e.state = EnemyStateKind.normal;
    }
    return switch (e.kind.ability) {
      EnemyAbility.hop => _tickHop(e, dt),
      EnemyAbility.mimic => _tickMimic(e, dt),
      EnemyAbility.plantBombs => _tickGoblin(e, dt),
      EnemyAbility.kickBombs => _tickCrab(e, dt),
      EnemyAbility.nest => _tickNest(e, dt),
      EnemyAbility.eatBombs => _tickFuseEater(e, dt),
      EnemyAbility.teleport => _tickWraith(e, dt),
      EnemyAbility.bombPatterns => _tickBombOTron(e, dt),
      EnemyAbility.witch => _tickWitch(e, dt),
      EnemyAbility.overlord => _tickOverlord(e, dt),
      _ => false,
    };
  }

  /// Counts down a telegraph. True on the tick it ends.
  bool _telegraphDone(Enemy e, double dt) {
    e.stateFor -= dt;
    return e.stateFor <= 0;
  }

  void _telegraph(Enemy e, [double seconds = 0.5]) {
    e.state = EnemyStateKind.telegraph;
    e.stateFor = seconds;
  }

  /// Mimic: waits in disguise, bares its teeth for 0.5 s when a player
  /// steps next to it, bites everyone next to it, then chases for 6 s.
  bool _tickMimic(Enemy e, double dt) {
    switch (e.state) {
      case EnemyStateKind.disguised:
        if (_nearestPlayerSteps(e) <= 1) {
          _telegraph(e);
          events.add(EnemyRevealed(e));
        }
        return true;
      case EnemyStateKind.telegraph:
        if (_telegraphDone(e, dt)) {
          for (final p in alivePlayers.toList()) {
            if (!p.invincible && p.tile.manhattanTo(e.tile) <= 1) {
              _hurtPlayer(p, -1);
            }
          }
          e.state = EnemyStateKind.normal;
          e.cooldown = 6;
        }
        return true;
      default:
        if (e.cooldown <= 0 && e.target == null) {
          e.state = EnemyStateKind.disguised;
          return true;
        }
        return false;
    }
  }

  /// Bomb Goblin: within 3 tiles of a player it winds up, plants a range-2
  /// bomb and runs.
  bool _tickGoblin(Enemy e, double dt) {
    if (e.state == EnemyStateKind.telegraph) {
      if (_telegraphDone(e, dt)) {
        if (bombAt(e.tileX, e.tileY) == null) _enemyBomb(e.tile, 2);
        e.state = EnemyStateKind.fleeing;
        e.stateFor = 2.5;
        e.cooldown = 5;
      }
      return true;
    }
    if (e.state == EnemyStateKind.normal &&
        e.target == null &&
        e.cooldown <= 0 &&
        grid.isWalkable(e.tileX, e.tileY) &&
        bombAt(e.tileX, e.tileY) == null &&
        _nearestPlayerSteps(e) <= 3) {
      _telegraph(e);
      return true;
    }
    return false;
  }

  /// Kicker Crab: winds up for 0.5 s next to a still bomb, then kicks it
  /// away along the lane.
  bool _tickCrab(Enemy e, double dt) {
    if (e.state == EnemyStateKind.telegraph) {
      if (_telegraphDone(e, dt)) {
        e.state = EnemyStateKind.normal;
        e.cooldown = 1;
        final d = e.direction;
        final bx = e.tileX + d.dx, by = e.tileY + d.dy;
        final b = bombAt(bx, by);
        if (b != null &&
            b.slide == Direction.none &&
            _bombCanEnter(bx + d.dx, by + d.dy)) {
          b.slide = d;
          b.slideProgress = 0;
          b.conveyed = false;
          b.passableFor.clear();
          events.add(EnemyKickedBomb(e, bx, by));
        }
      }
      return true;
    }
    if (e.state != EnemyStateKind.normal ||
        e.target != null ||
        e.cooldown > 0) {
      return false;
    }
    final dirs = [
      if (e.direction != Direction.none) e.direction,
      ...Direction.cardinal,
    ];
    for (final d in dirs) {
      final bx = e.tileX + d.dx, by = e.tileY + d.dy;
      final b = bombAt(bx, by);
      if (b != null &&
          b.slide == Direction.none &&
          _bombCanEnter(bx + d.dx, by + d.dy)) {
        e.direction = d;
        _telegraph(e);
        return true;
      }
    }
    return false;
  }

  static const double nestInterval = 8;
  static const int nestBrood = 3;

  /// Mole Queen nest: buried under a brick until it is blown open; spawns
  /// a Pebble every 8 s (at most three alive at once).
  bool _tickNest(Enemy e, double dt) {
    if (e.state == EnemyStateKind.underground &&
        grid.at(e.tileX, e.tileY) != TileType.brick) {
      e.state = EnemyStateKind.normal;
    }
    if (e.state == EnemyStateKind.telegraph) {
      if (_telegraphDone(e, dt)) {
        e.state = EnemyStateKind.normal;
        _hatch(e);
      }
      return true;
    }
    e.abilityTimer += dt;
    if (e.abilityTimer < nestInterval) return true;
    e.abilityTimer = 0;
    final brood = enemies.where((m) => m.alive && m.parentId == e.id).length;
    if (brood >= nestBrood) return true;
    if (e.state == EnemyStateKind.underground) {
      _hatch(e); // the brick itself is the tell: it shakes in the renderer
    } else {
      _telegraph(e);
    }
    return true;
  }

  void _hatch(Enemy nest) {
    final options = [
      for (final d in Direction.cardinal)
        if (grid.isWalkable(nest.tileX + d.dx, nest.tileY + d.dy) &&
            bombAt(nest.tileX + d.dx, nest.tileY + d.dy) == null)
          nest.tile.step(d.dx, d.dy),
    ];
    if (options.isEmpty) return;
    final at = options[_rng.nextInt(options.length)];
    spawnEnemy(at, EnemyKind.pebble).parentId = nest.id;
  }

  /// Fuse Eater: next to a still bomb it stops to eat it (0.5 s, the moment
  /// to set it off), then flees for 2 s.
  bool _tickFuseEater(Enemy e, double dt) {
    if (e.state == EnemyStateKind.telegraph) {
      if (_telegraphDone(e, dt)) {
        final at = e.landing;
        final b = at == null ? null : bombAt(at.x, at.y);
        if (b != null) {
          bombs.remove(b);
          playerById(b.ownerId)?.bombsPlaced--;
          events.add(BombEaten(e, b.x, b.y));
        }
        e.landing = null;
        e.state = EnemyStateKind.fleeing;
        e.stateFor = 2;
      }
      return true;
    }
    if (e.state != EnemyStateKind.normal || e.target != null) return false;
    for (final d in Direction.cardinal) {
      final b = bombAt(e.tileX + d.dx, e.tileY + d.dy);
      if (b != null && b.slide == Direction.none) {
        e.direction = d;
        e.landing = b.tile;
        _telegraph(e);
        return true;
      }
    }
    return false;
  }

  /// Phase Wraith: every 6 s it marks a tile 2-3 steps from a player,
  /// flickers for 0.5 s, then appears there.
  bool _tickWraith(Enemy e, double dt) {
    if (e.state == EnemyStateKind.telegraph) {
      if (_telegraphDone(e, dt)) {
        e.state = EnemyStateKind.normal;
        e.abilityTimer = 0;
        final to = e.landing;
        e.landing = null;
        if (to != null &&
            grid.isWalkable(to.x, to.y) &&
            bombAt(to.x, to.y) == null) {
          final from = e.tile;
          e.setPosition(to.x + 0.5, to.y + 0.5);
          e.target = null;
          events.add(EnemyTeleported(e, from.x, from.y));
        }
      }
      return true;
    }
    e.abilityTimer += dt;
    if (e.abilityTimer < 6 ||
        e.target != null ||
        e.state != EnemyStateKind.normal) {
      return false;
    }
    final spot = _spotNearPlayer(2, 3);
    if (spot == null) {
      e.abilityTimer = 5;
      return false;
    }
    e.landing = spot;
    _telegraph(e);
    return true;
  }

  /// A random safe open tile [minSteps]..[maxSteps] from a random player.
  GridPos? _spotNearPlayer(int minSteps, int maxSteps) {
    final alive = alivePlayers.toList();
    if (alive.isEmpty) return null;
    final target = alive[_rng.nextInt(alive.length)];
    final danger = dangerTiles();
    final options = _openTilesNear(target.tile, maxSteps)
        .where((t) =>
            t.manhattanTo(target.tile) >= minSteps &&
            !danger.contains(t) &&
            alivePlayers.every((p) => p.tile.manhattanTo(t) >= minSteps))
        .toList();
    if (options.isEmpty) return null;
    return options[_rng.nextInt(options.length)];
  }

  /// Plants an enemy bomb (no player owns it).
  Bomb? _enemyBomb(GridPos at, int range) {
    if (!grid.isWalkable(at.x, at.y) || bombAt(at.x, at.y) != null) {
      return null;
    }
    final bomb = Bomb(
      id: _nextId++,
      x: at.x,
      y: at.y,
      ownerId: Bomb.enemyOwner,
      range: range,
      fuse: Bomb.defaultFuse,
      remote: false,
    );
    for (final p in players) {
      if (p.alive && _overlapsTile(p, at.x, at.y)) bomb.passableFor.add(p.id);
    }
    bombs.add(bomb);
    events.add(BombPlaced(bomb));
    return bomb;
  }

  // ---------------------------------------------------------------- bosses

  /// Bomb-O-Tron: armoured; winds up for 1 s, drops a ring or lines of
  /// bombs, then opens its core for 4 s. Kick its bombs back at it.
  bool _tickBombOTron(Enemy e, double dt) {
    switch (e.state) {
      case EnemyStateKind.telegraph:
        if (_telegraphDone(e, dt)) {
          final range = e.hp * 2 <= e.maxHp ? 2 : 1;
          final lines = e.attackIndex.isOdd;
          e.attackIndex++;
          if (lines) {
            _bombLines(e, range);
          } else {
            _bombRing(e, range + 2, range);
          }
          e.state = EnemyStateKind.vulnerable;
          e.stateFor = 4;
        }
      case EnemyStateKind.vulnerable:
        e.stateFor -= dt;
        if (e.stateFor <= 0) {
          e.state = EnemyStateKind.normal;
          e.cooldown = 2.5;
        }
      default:
        if (e.cooldown <= 0) {
          _telegraph(e, 1);
          events.add(BossAttack(e, e.attackIndex.isOdd ? 'lines' : 'ring'));
        }
    }
    return true;
  }

  /// Bombs every other tile on the square ring [radius] tiles out.
  void _bombRing(Enemy boss, int radius, int range) {
    final c = boss.tile;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        if (max(dx.abs(), dy.abs()) != radius || (dx + dy).isOdd) continue;
        _enemyBomb(c.step(dx, dy), range);
      }
    }
  }

  /// Bombs every other tile along the row and column of a random player,
  /// keeping clear of the boss's own body.
  void _bombLines(Enemy boss, int range) {
    final alive = alivePlayers.toList();
    if (alive.isEmpty) return;
    final target = alive[_rng.nextInt(alive.length)].tile;
    final c = boss.tile;
    final keepOut = range + 1;
    for (var x = 1; x < grid.width - 1; x++) {
      if ((x - target.x).isOdd) continue;
      if ((x - c.x).abs() <= keepOut && (target.y - c.y).abs() <= keepOut) {
        continue;
      }
      _enemyBomb(GridPos(x, target.y), range);
    }
    for (var y = 1; y < grid.height - 1; y++) {
      if ((y - target.y).isOdd || y == target.y) continue;
      if ((y - c.y).abs() <= keepOut && (target.x - c.x).abs() <= keepOut) {
        continue;
      }
      _enemyBomb(GridPos(target.x, y), range);
    }
  }

  /// The Lantern Witch: hittable for 3.5 s, then flickers and blinks away
  /// from the players. Every second blink she summons two Shades; at half
  /// health every third blink curses a player (controls reversed) until a
  /// teammate bombs the Curse Orb.
  bool _tickWitch(Enemy e, double dt) {
    if (e.state == EnemyStateKind.telegraph) {
      if (_telegraphDone(e, dt)) {
        e.state = EnemyStateKind.normal;
        final to = e.landing;
        e.landing = null;
        if (to != null && grid.isWalkable(to.x, to.y)) {
          final from = e.tile;
          e.setPosition(to.x + 0.5, to.y + 0.5);
          events.add(EnemyTeleported(e, from.x, from.y));
        }
        e.attackIndex++;
        if (e.attackIndex.isEven) _summonShades(e, 2, cap: 4);
        if (e.hp * 2 <= e.maxHp && e.attackIndex % 3 == 0) _curse(e);
        e.cooldown = 3.5;
      }
      return true;
    }
    if (e.cooldown > 0) return true;
    final spot =
        _randomFloorTileFarFromPlayers(4) ?? _randomFloorTileFarFromPlayers(2);
    if (spot == null) {
      e.cooldown = 1;
      return true;
    }
    e.landing = spot;
    _telegraph(e, 0.6);
    events.add(BossAttack(e, 'blink'));
    return true;
  }

  void _summonShades(Enemy boss, int count, {required int cap}) {
    final alive = enemies
        .where((m) =>
            m.alive && m.parentId == boss.id && m.kind == EnemyKind.shade)
        .length;
    events.add(BossAttack(boss, 'summon'));
    for (var i = 0; i < count && alive + i < cap; i++) {
      final at = _randomFloorTileFarFromPlayers(4);
      if (at == null) return;
      spawnEnemy(at, EnemyKind.shade).parentId = boss.id;
    }
  }

  void _curse(Enemy witch) {
    final victims = alivePlayers.where((p) => !p.cursed).toList();
    if (victims.isEmpty) return;
    final victim = victims[_rng.nextInt(victims.length)];
    final orbAt =
        _randomFloorTileFarFromPlayers(4) ?? _randomFloorTileFarFromPlayers(2);
    if (orbAt == null) return;
    victim.cursedFor = curseSeconds;
    spawnEnemy(orbAt, EnemyKind.curseOrb)
      ..parentId = witch.id
      ..linkedPlayer = victim.id;
    events.add(BossAttack(witch, 'curse'));
    events.add(PlayerCursed(victim.id));
  }

  /// A curse ran out on its own: its orb fades.
  void _liftCurse(Player p) {
    for (final orb in enemies) {
      if (orb.alive && orb.linkedPlayer == p.id) {
        orb.alive = false;
        events.add(EnemyDied(orb, -2));
      }
    }
    events.add(CurseLifted(p.id));
  }

  /// Overlord Pontan's speed copies the fastest player.
  double _copiedSpeed() {
    var fastest = Player.baseSpeed;
    for (final p in alivePlayers) {
      fastest = max(fastest, p.speed);
    }
    return 1 + (fastest - Player.baseSpeed) / Player.baseSpeed;
  }

  /// Overlord Pontan's bombs copy the team's best Fire Up (at most 3).
  int _copiedRange() {
    var best = 1;
    for (final p in alivePlayers) {
      best = max(best, p.fireRange);
    }
    return min(best, 3);
  }

  /// Overlord Pontan: bounces like King Puffball and cycles through the
  /// earlier bosses' attacks (split, bomb ring, Shades, dive), each with a
  /// 1 s tell. Below a third of his health the arena starts closing in.
  /// Returns true while he is not bouncing.
  bool _tickOverlord(Enemy e, double dt) {
    if (e.hp * 3 <= e.maxHp && _shrinkQueue == null) {
      _shrinkQueue = _shrinkRings(2);
    }
    _tickShrink(dt, e);
    switch (e.state) {
      case EnemyStateKind.underground:
        if (_telegraphDone(e, dt)) {
          final spot = _overlordSurfaceSpot(e);
          if (spot != null) {
            final from = e.tile;
            e.setPosition(spot.x + 0.5, spot.y + 0.5);
            events.add(EnemyTeleported(e, from.x, from.y));
          }
          _telegraph(e, 1);
          e.attackIndex = -1; // the tell after a dive is just the rumble
        }
        return true;
      case EnemyStateKind.telegraph:
        if (!_telegraphDone(e, dt)) return true;
        e.state = EnemyStateKind.normal;
        e.cooldown = 4;
        final attack = e.attackIndex;
        if (attack < 0) {
          e.attackIndex = 0;
          return true;
        }
        e.attackIndex = (attack + 1) % 4;
        switch (attack % 4) {
          case 0:
            events.add(BossAttack(e, 'split'));
            for (final t in _openTilesNear(e.tile, 3).take(2)) {
              spawnEnemy(t, EnemyKind.puffball)
                ..parentId = e.id
                ..hitCooldown = 0.6;
            }
          case 1:
            events.add(BossAttack(e, 'ring'));
            final range = _copiedRange();
            _bombRing(e, range + 2, range);
          case 2:
            _summonShades(e, 2, cap: 3);
          case 3:
            events.add(BossAttack(e, 'dive'));
            e.state = EnemyStateKind.underground;
            e.stateFor = 1.5;
        }
        return true;
      default:
        if (e.cooldown <= 0) {
          _telegraph(e, 1);
          return true;
        }
        return false;
    }
  }

  /// Where a big bouncing boss can surface near a player: its whole body
  /// must fit on open floor.
  GridPos? _overlordSurfaceSpot(Enemy e) {
    final r = e.kind.size;
    bool fits(GridPos t) {
      final cx = t.x + 0.5, cy = t.y + 0.5;
      for (var y = (cy - r).floor(); y <= (cy + r - 1e-6).floor(); y++) {
        for (var x = (cx - r).floor(); x <= (cx + r - 1e-6).floor(); x++) {
          final tile = grid.at(x, y);
          if (tile == TileType.pillar || tile == TileType.brick) return false;
        }
      }
      return true;
    }

    final alive = alivePlayers.toList();
    if (alive.isNotEmpty) {
      final target = alive[_rng.nextInt(alive.length)].tile;
      final options = _openTilesNear(target, 3)
          .where((t) => t.manhattanTo(target) >= 2 && fits(t))
          .toList();
      if (options.isNotEmpty) return options[_rng.nextInt(options.length)];
    }
    final any = grid.positions.where(fits).toList();
    return any.isEmpty ? null : any[_rng.nextInt(any.length)];
  }

  /// The tiles of the outer [rings] rings inside the wall, outermost first,
  /// each ring walked clockwise from its top-left corner.
  List<GridPos> _shrinkRings(int rings) {
    final out = <GridPos>[];
    for (var r = 1; r <= rings; r++) {
      final x0 = r, y0 = r, x1 = grid.width - 1 - r, y1 = grid.height - 1 - r;
      if (x0 >= x1 || y0 >= y1) break;
      for (var x = x0; x <= x1; x++) {
        out.add(GridPos(x, y0));
      }
      for (var y = y0 + 1; y <= y1; y++) {
        out.add(GridPos(x1, y));
      }
      for (var x = x1 - 1; x >= x0; x--) {
        out.add(GridPos(x, y1));
      }
      for (var y = y1 - 1; y > y0; y--) {
        out.add(GridPos(x0, y));
      }
    }
    return out;
  }

  static const int shrinkBatch = 4;
  static const double shrinkEvery = 1;

  void _tickShrink(double dt, Enemy boss) {
    final queue = _shrinkQueue;
    if (queue == null || queue.isEmpty) return;
    _shrinkTimer += dt;
    if (_shrinkTimer < shrinkEvery) return;
    _shrinkTimer = 0;
    for (var i = 0; i < shrinkBatch && queue.isNotEmpty; i++) {
      final t = queue.removeAt(0);
      if (grid.atPos(t) == TileType.pillar) continue;
      hazards.add(Hazard(t.x, t.y, 1, kind: HazardKind.wall));
    }
  }

  /// The arena closes a tile: it becomes a pillar. Anyone on it is crushed
  /// unless invincible, in which case they're shoved to the nearest floor.
  void _closeTile(GridPos t) {
    for (final e in enemies) {
      if (!e.alive || !e.kind.boss) continue;
      final r = e.kind.size;
      if ((e.x - (t.x + 0.5)).abs() < 0.5 + r &&
          (e.y - (t.y + 0.5)).abs() < 0.5 + r) {
        return; // the boss is in the way; leave this tile open
      }
    }
    grid.set(t.x, t.y, TileType.pillar);
    final bomb = bombAt(t.x, t.y);
    if (bomb != null) {
      bombs.remove(bomb);
      playerById(bomb.ownerId)?.bombsPlaced--;
    }
    floorItems.removeWhere((i) => i.x == t.x && i.y == t.y);
    for (final e in enemies) {
      if (e.alive && !e.kind.boss && e.tile == t) _killEnemy(e, -2);
    }
    GridPos? refuge() {
      final near = _openTilesNear(t, 4).where((o) => o != t);
      return near.isEmpty ? null : near.first;
    }

    for (final p in players) {
      if ((p.alive || p.ghost) && _overlapsTile(p, t.x, t.y)) {
        if (p.alive && !p.invincible) _killPlayer(p, -2);
        final to = refuge();
        if (to != null) p.setPosition(to.x + 0.5, to.y + 0.5);
      }
      if (p.tombstone == t) p.tombstone = refuge() ?? t;
    }
    events.add(ArenaShrank(t.x, t.y));
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
        final land = e.landing ?? e.tile; // lands in place if it had no target
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

  // ------------------------------------------------- weather and terrain

  /// Wind (World 5): each [WorldConfig.windInterval] the gust flips between
  /// left and right, after a [windCalm] lull that announces the next one.
  void _tickWeather(double dt) {
    final period = config.windInterval;
    if (period <= 0) return;
    final cycle = elapsed % (2 * period);
    final gust = cycle < period ? Direction.left : Direction.right;
    final within = cycle < period ? cycle : cycle - period;
    final now = within < windCalm ? Direction.none : gust;
    windNext = now == Direction.none ? gust : Direction.none;
    if (now != wind) {
      wind = now;
      events.add(WindChanged(now));
    }
  }

  void _tickTerrain(double dt) {
    _tickVents(dt);
    _tickRegrowth(dt);
    if (config.cannonInterval > 0) {
      _cannonTimer += dt;
      final alive = alivePlayers.toList();
      if (_cannonTimer >= config.cannonInterval && alive.isNotEmpty) {
        _cannonTimer = 0;
        var row = alive[_rng.nextInt(alive.length)].tileY;
        // Pillar rows would stop the shot at once; aim at a lane instead.
        if (row.isEven) row = row - 1 >= 1 ? row - 1 : row + 1;
        final fromLeft = _rng.nextBool();
        hazards.add(Hazard(
          fromLeft ? 0 : grid.width - 1,
          row,
          cannonWarning,
          kind: fromLeft ? HazardKind.cannonLeft : HazardKind.cannonRight,
        ));
      }
    }
  }

  /// Steam vents (World 3) all share one cycle: idle, a [ventWarning] tell,
  /// then a [ventFiring] jet on the vent and the four tiles around it.
  void _tickVents(double dt) {
    final period = config.ventInterval;
    if (period <= 0 || _vents.isEmpty) return;
    final cycle = elapsed % period;
    final fireAt = period - ventFiring;
    final warnAt = fireAt - ventWarning;
    final VentPhase phase;
    if (cycle >= fireAt) {
      phase = VentPhase.firing;
      ventTimeLeft = period - cycle;
    } else if (cycle >= warnAt) {
      phase = VentPhase.warning;
      ventTimeLeft = fireAt - cycle;
    } else {
      phase = VentPhase.idle;
      ventTimeLeft = warnAt - cycle;
    }
    if (phase == VentPhase.firing && ventPhase != VentPhase.firing) {
      events.add(const VentsFired());
    }
    ventPhase = phase;
    if (phase != VentPhase.firing) return;
    for (final v in _vents) {
      if (!grid.isWalkable(v.x, v.y)) continue; // still under a brick
      for (final t in [
        v,
        for (final d in Direction.cardinal) v.step(d.dx, d.dy)
      ]) {
        final tile = grid.atPos(t);
        if (tile == TileType.pillar || tile == TileType.brick) continue;
        _hazardFlame(t.x, t.y, v.x, v.y);
      }
    }
  }

  /// A flame no player owns. Bombs it touches go off.
  void _hazardFlame(int x, int y, int originX, int originY) {
    _addFlame(x, y, -2, originX, originY);
    final b = bombAt(x, y);
    if (b != null) _explode(b);
  }

  /// Possessed bricks (World 4) grow back once their tile is clear.
  void _tickRegrowth(double dt) {
    if (regrowing.isEmpty) return;
    for (final t in regrowing.keys.toList()) {
      final left = regrowing[t]! - dt;
      if (left > 0) {
        regrowing[t] = left;
        continue;
      }
      regrowing[t] = 0;
      final blocked = grid.atPos(t) != TileType.floor ||
          bombAt(t.x, t.y) != null ||
          flameAt(t.x, t.y) != null ||
          floorItems.any((i) => i.x == t.x && i.y == t.y) ||
          players
              .any((p) => (p.alive || p.ghost) && _overlapsTile(p, t.x, t.y)) ||
          enemies.any((e) => e.alive && e.tile == t);
      if (blocked) continue;
      regrowing.remove(t);
      grid.set(t.x, t.y, TileType.brick);
      events.add(BrickRegrew(t.x, t.y));
    }
  }

  /// A cannonball sweeps the row from the wall until a pillar or brick
  /// stops it, setting off bombs on the way.
  void _fireCannon(Hazard h) {
    final fromLeft = h.kind == HazardKind.cannonLeft;
    final dx = fromLeft ? 1 : -1;
    events.add(CannonFired(h.y, fromLeft: fromLeft));
    for (var x = h.x + dx; grid.inBounds(x, h.y); x += dx) {
      final tile = grid.at(x, h.y);
      if (tile == TileType.pillar || tile == TileType.brick) break;
      _hazardFlame(x, h.y, h.x, h.y);
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
      switch (h.kind) {
        case HazardKind.cannonLeft || HazardKind.cannonRight:
          _fireCannon(h);
          continue;
        case HazardKind.wall:
          _closeTile(GridPos(h.x, h.y));
          continue;
        case HazardKind.rock:
          break;
      }
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
  Direction? _chaseStep(Enemy e, Set<GridPos> danger) => _pathStep(
        e,
        {for (final p in alivePlayers) p.tile},
        e.kind.sightRange,
        danger,
      );

  /// First step of a BFS path to the nearest of [targets] within [range]
  /// steps, or null. Bomb-aware enemies route around blast zones.
  Direction? _pathStep(
    Enemy e,
    Set<GridPos> targets,
    int range,
    Set<GridPos> danger,
  ) {
    if (targets.isEmpty) return null;
    final start = e.tile;
    final avoidDanger = e.kind.bombAware;
    final visited = <GridPos, Direction>{start: Direction.none};
    final queue = Queue<GridPos>()..add(start);
    final dist = <GridPos, int>{start: 0};

    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      if (dist[cur]! > range) break;
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
            case ItemType.extraLife:
              // Solo lives live in the app; co-op's pool lives here.
              if (config.ghosts) livesLeft = min(maxLives, livesLeft + 1);
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
    for (final e in enemies) {
      if (e.alive &&
          e.state == EnemyStateKind.disguised &&
          (e.tileX - p.tileX).abs() <= sonarRadius &&
          (e.tileY - p.tileY).abs() <= sonarRadius) {
        e.state = EnemyStateKind.normal;
        e.cooldown = 6;
        events.add(EnemyRevealed(e));
      }
    }
    events.add(SonarPulse(p.id, p.tileX, p.tileY));
  }

  void _checkEnemyContact() {
    for (final p in players) {
      if (!p.alive || p.invincible) continue;
      for (final e in enemies) {
        if (!e.harmful) continue;
        final reach = e.kind.size + Player.halfBox - contactGrace;
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
