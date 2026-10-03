import 'dart:math';
import 'dart:typed_data';

import 'direction.dart';
import 'entities.dart';
import 'grid.dart';
import 'input.dart';
import 'world.dart';

/// How well a [Bot] plays.
enum BotSkill {
  /// Slow to notice other players' bombs, timid, and now and then cuts its
  /// escape timing too fine.
  easy(
    reaction: 0.4,
    mistakeRate: 0.12,
    aggression: 0.4,
    margin: 0.08,
    decideEvery: 8,
    huntSteps: 10,
  ),

  /// A fair opponent for most players.
  normal(
    reaction: 0.15,
    mistakeRate: 0.03,
    aggression: 0.8,
    margin: 0.15,
    decideEvery: 4,
    huntSteps: 24,
  ),

  /// Sees everything at once and never gambles.
  hard(
    reaction: 0,
    mistakeRate: 0,
    aggression: 1,
    margin: 0.2,
    decideEvery: 1,
    huntSteps: 999,
  );

  const BotSkill({
    required this.reaction,
    required this.mistakeRate,
    required this.aggression,
    required this.margin,
    required this.decideEvery,
    required this.huntSteps,
  });

  /// Seconds before the bot reacts to a bomb someone else placed.
  final double reaction;

  /// Chance that a bomb decision uses sloppy escape timing.
  final double mistakeRate;

  /// Chance of taking a chance to bomb a rival or an enemy.
  final double aggression;

  /// Seconds of slack kept around every blast when planning a route.
  final double margin;

  /// Bomb decisions happen on every n-th tick.
  final int decideEvery;

  /// Rivals and enemies further than this many steps are not hunted.
  final int huntSteps;

  static BotSkill parse(String? s) =>
      values.firstWhere((v) => v.name == s, orElse: () => normal);
}

/// A computer player. Call [think] once per tick before [World.tick] and feed
/// the result in as that player's input, exactly like a human's.
///
/// Built on the enemy AI's ideas (§14 "Bots"): BFS over walkable tiles, a
/// danger map of when each tile will be on fire (bomb fuses, chain
/// reactions, live flames, telegraphed hazards), and the rule "only place a
/// bomb if it threatens something and I can reach a safe tile before the
/// fuse runs out".
///
/// Versus: hunts the nearest rival, breaking bricks to reach them. Co-op and
/// solo: revives fallen teammates, clears enemies, then heads for the exit,
/// and never bombs a teammate when friendly fire is on. A ghost bot floats
/// by its tombstone and haunts enemies that come close.
///
/// Deterministic for a given world, player and [seed].
class Bot {
  Bot(this.world, this.playerId, {this.skill = BotSkill.normal, int seed = 0})
      : _rng = Random(seed);

  final World world;
  final int playerId;
  final BotSkill skill;
  final Random _rng;

  int _tick = 0;

  /// Tick each bomb (by id) was first seen, for the reaction delay.
  final Map<int, int> _seen = {};

  /// Tiles where a bomb turned out to have no escape, until a tick.
  final Map<int, int> _badSpots = {};

  int? _wander;
  int _wanderUntil = 0;

  // Per-tick maps, indexed by y * width + x.
  late final int _w = world.grid.width;
  late final int _n = world.grid.width * world.grid.height;
  late List<List<double>> _hard = List.generate(_n, (_) => <double>[]);
  late Uint8List _soft = Uint8List(_n);
  late Uint8List _blocked = Uint8List(_n);
  late Uint8List _near = Uint8List(_n);
  late Uint8List _bombTiles = Uint8List(_n);

  /// Co-op: tiles at or next to a teammate the bot gives way to, so two
  /// bots don't pile onto one spot and then refuse to bomb each other.
  late Uint8List _crowd = Uint8List(_n);
  bool _enemiesAbout = false;

  static const double _forever = 1e9;

  /// The input for this tick.
  PlayerInput think() {
    _tick++;
    final p = world.playerById(playerId);
    if (p == null || world.over) return PlayerInput.idle;
    if (p.ghost) return _ghost(p);
    if (!p.alive || p.frozen) return PlayerInput.idle;

    _stepTime = 1 / p.speed;
    _forgetBombs();
    _buildMaps(p);
    final here = _idx(p.tile);
    var action = false;
    if (p.remote) action = _shouldDetonate(p);
    if (p.active == ActiveItem.tether) action = _tetherInReach(p);

    // Safety first: anywhere a blast, hazard or enemy can reach is left.
    if (!_safeToStand(here, 0, relaxed: false)) {
      final route = _search(p, here, wait: true, relaxed: false) ??
          _search(p, here, wait: true, relaxed: true);
      return _input(p, route?.first ?? _awayStep(p, here), action: action);
    }

    final (dir, bomb) = _plan(p, here);
    return _input(p, dir, bomb: bomb, action: action);
  }

  // ------------------------------------------------------------ planning

  (Direction, bool) _plan(Player p, int here) {
    final versus = world.config.versusMode;
    final deciding = _tick % skill.decideEvery == 0;

    // Co-op: stand on a fallen teammate's tombstone to revive them.
    if (!versus && world.livesLeft > 0) {
      final graves = {
        for (final g in world.players)
          if (g.ghost && g.tombstone != null && g.id != playerId)
            _idx(g.tombstone!),
      };
      if (graves.contains(here)) return (Direction.none, false);
      final r = _pathTo(p, here, graves.contains);
      if (r != null) return (r.first, false);
    }

    // Power-ups lying close by.
    final items = {
      for (final i in world.floorItems)
        if (i.type != ItemType.exit) i.y * _w + i.x,
    };
    if (items.isNotEmpty) {
      final r = _pathTo(p, here, items.contains, maxSteps: 7);
      if (r != null) return (r.first, false);
    }

    final targets = _targets(p, versus);
    final canBomb = deciding &&
        p.bombsPlaced < p.maxBombs &&
        world.bombAt(p.tileX, p.tileY) == null &&
        world.grid.isWalkable(p.tileX, p.tileY);

    // Enemies can't walk through bombs, so a co-op bot also bombs one a
    // tile beyond its reach: it either walks into the blast or is held off.
    final lure = versus ? 0 : 1;

    // A rival or enemy in reach of a bomb dropped right here?
    if (canBomb && targets.isNotEmpty) {
      final blast = _blastFrom(here, p.fireRange);
      final reach = lure == 0
          ? blast
          : _rays(here, p.fireRange + lure, includeOrigin: true).toSet();
      final hits = targets.any((t) =>
          reach.contains(t.at) ||
          (t.next != null && reach.contains(t.next)) ||
          _trapped(t, blast, here, odds: versus ? 1 : 0.5) ||
          (t.enemy != null && _walksInto(t.enemy!, blast, here)));
      if (hits && _rng.nextDouble() < skill.aggression) {
        final escape = _bombEscape(p, here, blast);
        // Stand still on the drop tick: the world moves before it places,
        // so a step now could carry the bomb onto the next tile.
        if (escape != null) return (Direction.none, true);
      }
    }

    // Hunt: walk to a tile that lines up a bomb on the target.
    if (targets.isNotEmpty) {
      final spots = <int>{};
      for (final t in targets) {
        for (final s
            in _rays(t.at, p.fireRange + lure, includeOrigin: versus)) {
          if (versus || _near[s] == 0) spots.add(s);
        }
      }
      spots.removeWhere((s) => _isBadSpot(s) || _crowd[s] != 0);
      if (spots.contains(here)) return (Direction.none, false);
      final r = _pathTo(p, here, (i) => spots.contains(i) && !_trap(p, i),
          maxSteps: skill.huntSteps);
      if (r != null) return (r.first, false);
    }

    // Co-op: everyone gathers at the exit once the enemies are gone.
    final exit = world.exitTile;
    if (!versus && exit != null && world.allEnemiesDead) {
      final e = _idx(exit);
      if (here == e) return (Direction.none, false);
      final r = _pathTo(p, here, (i) => i == e);
      if (r != null) return (r.first, false);
    }

    // Break bricks to open the way, find items, the exit and enemies.
    final brickSpots = _brickSpots(p);
    if (brickSpots.contains(here) && canBomb) {
      final blast = _blastFrom(here, p.fireRange);
      if (_brickBombOk(blast)) {
        final escape = _bombEscape(p, here, blast);
        // Stand still on the drop tick: the world moves before it places,
        // so a step now could carry the bomb onto the next tile.
        if (escape != null) return (Direction.none, true);
      }
      _badSpots[here] = _tick + World.tickRate.round() * 2;
    }
    brickSpots.removeWhere((s) => _isBadSpot(s) || _crowd[s] != 0);
    if (brickSpots.isNotEmpty && !brickSpots.contains(here)) {
      final r = _pathTo(p, here, brickSpots.contains);
      if (r != null) return (r.first, false);
    } else if (brickSpots.contains(here)) {
      return (Direction.none, false); // wait for a bomb to come back
    }

    return (_wanderStep(p, here), false);
  }

  /// The things worth bombing.
  List<_Target> _targets(Player p, bool versus) {
    if (versus) {
      return [
        for (final o in world.players)
          if (o.id != playerId && o.alive && !o.ghost)
            _Target(_idx(o.tile), null, o.speed, o.wallPass, o.bombPass),
      ];
    }
    return [
      for (final e in world.enemies)
        if (e.alive &&
            e.solid &&
            e.visible &&
            world.grid.inBounds(e.tileX, e.tileY))
          _Target(
              e.tileY * _w + e.tileX,
              e.target == null ? null : _idx(e.target!),
              e.kind.speed,
              e.kind.wallPass,
              false,
              enemy: e),
    ];
  }

  /// Would a bomb at [bombAt] with [blast] catch [t] wherever it runs before
  /// the fuse is out? True when at least [odds] of the tiles it can reach
  /// (bombs block it) are in the blast: 1 means it is trapped for sure.
  bool _trapped(_Target t, Set<int> blast, int bombAt, {required double odds}) {
    final g = world.grid;
    final steps = (Bomb.defaultFuse * t.speed).ceil();
    final dist = <int, int>{t.at: 0};
    final queue = [t.at];
    var inside = 0;
    for (var h = 0; h < queue.length; h++) {
      final cur = queue[h];
      if (blast.contains(cur)) inside++;
      if (dist[cur]! >= steps) continue;
      for (final d in Direction.cardinal) {
        final x = cur % _w + d.dx, y = cur ~/ _w + d.dy;
        final n = y * _w + x;
        if (!g.inBounds(x, y) || dist.containsKey(n)) continue;
        final tile = g.at(x, y);
        if (tile == TileType.pillar || tile == TileType.pit) continue;
        if (tile == TileType.brick && !t.wallPass) continue;
        if (!t.bombPass && (n == bombAt || _bombTiles[n] != 0)) continue;
        dist[n] = dist[cur]! + 1;
        queue.add(n);
      }
    }
    return inside >= odds * queue.length;
  }

  /// A dead end is a trap while enemies roam: one way in, one way out.
  bool _trap(Player p, int i) {
    if (!_enemiesAbout) return false;
    var exits = 0;
    for (final d in Direction.cardinal) {
      final x = i % _w + d.dx, y = i ~/ _w + d.dy;
      if (world.grid.inBounds(x, y) && _passable(p, y * _w + x)) exits++;
    }
    return exits < 2;
  }

  /// Walkers that keep going straight and turn back at walls (Pebbles,
  /// and Puffballs most of the time) are easy to predict: will this one be
  /// in [blast] when a bomb dropped at [bombAt] now goes off?
  bool _walksInto(Enemy e, Set<int> blast, int bombAt) {
    final style = e.kind.style;
    if (style != MoveStyle.patrol && style != MoveStyle.wander) return false;
    if (e.frozen || e.state != EnemyStateKind.normal) return false;
    final g = world.grid;
    bool open(int x, int y) {
      if (!g.inBounds(x, y)) return false;
      final t = g.at(x, y);
      if (t == TileType.pillar || t == TileType.pit) return false;
      if (t == TileType.brick && !e.kind.wallPass) return false;
      final i = y * _w + x;
      return i != bombAt && _bombTiles[i] == 0;
    }

    var x = e.x, y = e.y;
    var d = e.direction;
    var target = e.target;
    if (d == Direction.none) return false;
    final speed = e.kind.speed * (e.slowFor > 0 ? 0.4 : 1);
    const dt = 0.05;
    const fuse = Bomb.defaultFuse;
    for (var t = 0.0; t < fuse + Flame.duration - 0.1; t += dt) {
      if (target == null) {
        final cx = x.floor(), cy = y.floor();
        if (open(cx + d.dx, cy + d.dy)) {
          target = GridPos(cx + d.dx, cy + d.dy);
        } else if (open(cx - d.dx, cy - d.dy)) {
          d = d.opposite;
          target = GridPos(cx + d.dx, cy + d.dy);
        }
      }
      if (target != null) {
        final tx = target.x + 0.5, ty = target.y + 0.5;
        final left = (tx - x).abs() + (ty - y).abs();
        final step = speed * dt;
        if (step >= left) {
          x = tx;
          y = ty;
          target = null;
        } else {
          x += d.dx * step;
          y += d.dy * step;
        }
      }
      if (t >= fuse + 0.05 && !blast.contains(y.floor() * _w + x.floor())) {
        return false;
      }
    }
    return blast.contains(y.floor() * _w + x.floor());
  }

  bool _isBadSpot(int i) => (_badSpots[i] ?? 0) > _tick;

  /// Where a bomb would break a brick that isn't already doomed.
  Set<int> _brickSpots(Player p) {
    final g = world.grid;
    final spots = <int>{};
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        if (g.at(x, y) != TileType.brick) continue;
        final i = y * _w + x;
        if (_hard[i].isNotEmpty) continue;
        spots.addAll(_rays(i, p.fireRange, includeOrigin: false));
      }
    }
    spots.removeWhere((s) => _near[s] != 0 || _hard[s].isNotEmpty);
    return spots;
  }

  /// Don't blow up the exit (it summons guards), loose power-ups, or
  /// anything when nothing would break.
  bool _brickBombOk(Set<int> blast) {
    final exit = world.exitTile;
    if (exit != null && blast.contains(_idx(exit))) return false;
    for (final i in world.floorItems) {
      if (blast.contains(i.y * _w + i.x)) return false;
    }
    return true;
  }

  /// First step of an escape from a bomb dropped at [here] with [blast], or
  /// null when the bomb would be unsafe (no way out, or a teammate in it).
  Direction? _bombEscape(Player p, int here, Set<int> blast) {
    if (!world.config.versusMode && world.config.friendlyFire) {
      for (final o in world.players) {
        if (o.id == playerId || !o.alive || o.ghost) continue;
        final t = _idx(o.tile);
        if (blast.contains(t)) return null;
        // A teammate walking next to it would step in.
        for (final d in Direction.cardinal) {
          if (blast.contains(_idx(o.tile.step(d.dx, d.dy))) && o.moveDir == d) {
            return null;
          }
        }
      }
    }
    final sloppy = _rng.nextDouble() < skill.mistakeRate;
    final saved = _cloneHard();
    _addBlast(blast, Bomb.defaultFuse, Bomb.defaultFuse);
    // The new bomb blocks its tile once the bot steps off.
    _virtualBomb = here;
    final route = _search(p, here,
        wait: true, relaxed: false, margin: sloppy ? -0.1 : null);
    _virtualBomb = -1;
    _hard = saved;
    if (route == null || route.goal == here) {
      _badSpots[here] = _tick + World.tickRate.round() * 2;
      return null;
    }
    return route.first;
  }

  Direction _wanderStep(Player p, int here) {
    var goal = _wander;
    if (goal == null ||
        goal == here ||
        _tick > _wanderUntil ||
        !_safeToStand(goal, 0, relaxed: false)) {
      final options = <int>[];
      _bfs(p, here, (i, d) {
        if (d >= 2 && d <= 6 && !_trap(p, i)) options.add(i);
        return false;
      });
      if (options.isEmpty) return Direction.none;
      goal = options[_rng.nextInt(options.length)];
      _wander = goal;
      _wanderUntil = _tick + World.tickRate.round() * 3;
    }
    final g = goal;
    return _pathTo(p, here, (i) => i == g)?.first ?? Direction.none;
  }

  /// Last resort when no safe tile is in reach: the open neighbour furthest
  /// from the nearest enemy that isn't about to burn.
  Direction _awayStep(Player p, int here) {
    var best = Direction.none;
    var bestScore = _enemyDistance(here) - 0.5;
    for (final d in Direction.cardinal) {
      final x = here % _w + d.dx, y = here ~/ _w + d.dy;
      if (!world.grid.inBounds(x, y)) continue;
      final n = y * _w + x;
      if (!_enterable(p, n, true) || !_clearAt(n, 1, 0)) continue;
      final score = _enemyDistance(n);
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best;
  }

  double _enemyDistance(int i) {
    final cx = i % _w + 0.5, cy = i ~/ _w + 0.5;
    var best = 99.0;
    for (final e in world.enemies) {
      if (!e.harmful) continue;
      best = min(best, (e.x - cx).abs() + (e.y - cy).abs() - e.kind.size);
    }
    return best;
  }

  // --------------------------------------------------------------- ghosts

  PlayerInput _ghost(Player p) {
    final t = p.tombstone;
    var action = false;
    if (!p.hauntUsed) {
      for (final e in world.enemies) {
        if (e.harmful &&
            (e.x - p.x).abs() + (e.y - p.y).abs() <= World.hauntRange) {
          action = true;
        }
      }
    }
    if (t == null || p.tile.manhattanTo(t) <= 1) {
      return PlayerInput(action: action);
    }
    // Ghosts float through everything but pillars.
    final g = world.grid;
    final start = _idx(p.tile), goal = _idx(t);
    final prev = Int32List(_n)..fillRange(0, _n, -1);
    prev[start] = start;
    final queue = <int>[start];
    for (var h = 0; h < queue.length; h++) {
      final cur = queue[h];
      if (cur == goal) break;
      for (final d in Direction.cardinal) {
        final x = cur % _w + d.dx, y = cur ~/ _w + d.dy;
        if (!g.inBounds(x, y) || g.at(x, y) == TileType.pillar) continue;
        final n = y * _w + x;
        if (prev[n] != -1) continue;
        prev[n] = cur;
        queue.add(n);
      }
    }
    if (prev[goal] == -1) return PlayerInput(action: action);
    var node = goal;
    while (prev[node] != start) {
      node = prev[node];
    }
    return _input(p, _dirBetween(start, node), action: action);
  }

  // ------------------------------------------------------------- actions

  /// Remote bombs go off once the bot (and, in co-op, its team) is clear.
  bool _shouldDetonate(Player p) {
    Bomb? oldest;
    for (final b in world.bombs) {
      if (b.ownerId == playerId && b.remote) {
        oldest = b;
        break;
      }
    }
    if (oldest == null) return false;
    final age = _tick - (_seen[oldest.id] ?? _tick);
    if (age < 6) return false;
    final blast = _blastFrom(_idx(oldest.tile), oldest.range);
    for (final o in world.players) {
      if (!o.alive || o.ghost) continue;
      final mine = o.id == playerId;
      if (!mine && (world.config.versusMode || !world.config.friendlyFire)) {
        continue;
      }
      if (blast.contains(_idx(o.tile))) return false;
    }
    return true;
  }

  bool _tetherInReach(Player p) {
    if (world.livesLeft <= 0) return false;
    for (final g in world.players) {
      final t = g.tombstone;
      if (g.ghost && t != null && t.manhattanTo(p.tile) <= World.tetherRange) {
        return true;
      }
    }
    return false;
  }

  /// Turns a tile step into a stick direction: lines up with the lane
  /// first so the turn doesn't snag on a pillar corner.
  PlayerInput _input(Player p, Direction dir,
      {bool bomb = false, bool action = false}) {
    var d = dir;
    if (d != Direction.none && !p.ghost) {
      final off = d.isHorizontal ? p.offsetY : p.offsetX;
      final threshold = max(0.06, p.speed * World.tickDt * 0.55);
      if (off.abs() > threshold) {
        d = d.isHorizontal
            ? (off > 0 ? Direction.up : Direction.down)
            : (off > 0 ? Direction.left : Direction.right);
      }
    }
    if (p.cursed) d = d.opposite;
    return PlayerInput(direction: d, placeBomb: bomb, action: action);
  }

  // ---------------------------------------------------------- danger map

  void _forgetBombs() {
    final live = {for (final b in world.bombs) b.id};
    _seen.removeWhere((id, _) => !live.contains(id));
    for (final b in world.bombs) {
      _seen.putIfAbsent(b.id, () => _tick);
    }
    _badSpots.removeWhere((_, until) => until <= _tick);
  }

  bool _noticed(Bomb b) =>
      b.ownerId == playerId ||
      (_tick - _seen[b.id]!) * World.tickDt >= skill.reaction;

  void _buildMaps(Player p) {
    _hard = List.generate(_n, (_) => <double>[]);
    _soft = Uint8List(_n);
    _blocked = Uint8List(_n);
    _near = Uint8List(_n);
    _bombTiles = Uint8List(_n);
    _crowd = Uint8List(_n);
    _enemiesAbout = world.enemies.any((e) => e.harmful);
    final g = world.grid;
    if (!world.config.versusMode) {
      for (final o in world.players) {
        // Lower ids have right of way, so exactly one of two bots yields.
        if (o.id >= playerId || !o.alive) continue;
        for (final (dx, dy) in const [
          (0, 0),
          (1, 0),
          (-1, 0),
          (0, 1),
          (0, -1)
        ]) {
          final x = o.tileX + dx, y = o.tileY + dy;
          if (g.inBounds(x, y)) _crowd[y * _w + x] = 1;
        }
      }
    }

    for (final f in world.flames) {
      _hard[f.y * _w + f.x].addAll([0, f.ttl]);
    }

    // Each bomb's earliest and latest explosion time, chains included.
    final bombs = <_PlannedBomb>[];
    for (final b in world.bombs) {
      _bombTiles[b.y * _w + b.x] = 1;
      if (!_noticed(b)) continue;
      double early, late;
      if (!b.remote) {
        early = late = max(0, b.fuse);
      } else if (b.ownerId == playerId) {
        // Our own remote goes off when we say so; plan as if it had a fuse.
        final age = (_tick - _seen[b.id]!) * World.tickDt;
        early = late = max(0.2, Bomb.defaultFuse - age);
      } else {
        early = 0;
        late = _forever;
      }
      bombs.add(_PlannedBomb(b.y * _w + b.x, b.range, early, late));
    }
    var changed = true;
    for (var round = 0; changed && round < bombs.length; round++) {
      changed = false;
      for (final a in bombs) {
        for (final c in bombs) {
          if (identical(a, c)) continue;
          if (!_rays(a.at, a.range, includeOrigin: false, blast: true)
              .contains(c.at)) {
            continue;
          }
          if (a.early < c.early || a.late < c.late) {
            c.early = min(c.early, a.early);
            c.late = min(c.late, a.late);
            changed = true;
          }
        }
      }
    }
    for (final b in bombs) {
      final tiles = _rays(b.at, b.range, includeOrigin: true);
      if (b.late >= _forever) {
        for (final t in tiles) {
          _soft[t] = 1;
        }
      } else {
        _addBlast(tiles, b.early, b.late);
      }
    }

    for (final h in world.hazards) {
      switch (h.kind) {
        case HazardKind.rock:
          _hard[h.y * _w + h.x].addAll([h.warn - 0.15, h.warn + 0.2]);
        case HazardKind.wall:
          _hard[h.y * _w + h.x].addAll([h.warn - 0.3, _forever]);
        case HazardKind.cannonLeft || HazardKind.cannonRight:
          final dx = h.kind == HazardKind.cannonLeft ? 1 : -1;
          for (var x = h.x + dx; g.inBounds(x, h.y); x += dx) {
            final t = g.at(x, h.y);
            if (t == TileType.pillar || t == TileType.brick) break;
            _hard[h.y * _w + x].addAll([h.warn - 0.1, h.warn + Flame.duration]);
          }
      }
    }

    final period = world.config.ventInterval;
    if (period > 0) {
      final (start, end) = switch (world.ventPhase) {
        VentPhase.firing => (0.0, world.ventTimeLeft),
        VentPhase.warning => (
            world.ventTimeLeft,
            world.ventTimeLeft + World.ventFiring
          ),
        VentPhase.idle => (
            world.ventTimeLeft + World.ventWarning,
            world.ventTimeLeft + World.ventWarning + World.ventFiring
          ),
      };
      for (var y = 0; y < g.height; y++) {
        for (var x = 0; x < g.width; x++) {
          if (g.featureAt(x, y) != TileFeature.vent || !g.isWalkable(x, y)) {
            continue;
          }
          for (final (vx, vy) in [
            (x, y),
            for (final d in Direction.cardinal) (x + d.dx, y + d.dy)
          ]) {
            final t = g.at(vx, vy);
            if (t == TileType.pillar || t == TileType.brick) continue;
            _hard[vy * _w + vx].addAll([start - 0.1, end + 0.1]);
          }
        }
      }
    }

    for (final e in world.enemies) {
      if (!e.alive || !e.solid) continue;
      final dangerous = e.harmful || e.state == EnemyStateKind.disguised;
      if (!dangerous) continue;
      final reach = e.kind.size + Player.halfBox;
      for (var y = (e.y - reach - 2).floor(); y <= e.y + reach + 2; y++) {
        for (var x = (e.x - reach - 2).floor(); x <= e.x + reach + 2; x++) {
          if (!g.inBounds(x, y)) continue;
          final dx = (e.x - (x + 0.5)).abs(), dy = (e.y - (y + 0.5)).abs();
          final i = y * _w + x;
          if (e.harmful && dx < reach + 0.15 && dy < reach + 0.15) {
            _blocked[i] = 1;
          } else if (dx < reach + 1.05 && dy < reach + 1.05) {
            _near[i] = 1;
          }
        }
      }
      final t = e.target;
      if (t != null && e.harmful && g.inBounds(t.x, t.y)) {
        _blocked[_idx(t)] = 1;
      }
    }
  }

  void _addBlast(Iterable<int> tiles, double early, double late) {
    for (final t in tiles) {
      _hard[t].addAll([early, late + Flame.duration]);
    }
  }

  List<List<double>> _cloneHard() => [for (final l in _hard) List.of(l)];

  /// Tiles in line with [origin] up to [range], stopped by pillars, bricks
  /// and bombs as a blast is. With [blast] the stopping brick or bomb tile is
  /// included (it gets hit); without, only tiles one can stand on are.
  List<int> _rays(int origin, int range,
      {required bool includeOrigin, bool blast = false}) {
    final g = world.grid;
    final ox = origin % _w, oy = origin ~/ _w;
    final out = <int>[if (includeOrigin) origin];
    for (final d in Direction.cardinal) {
      for (var r = 1; r <= range; r++) {
        final x = ox + d.dx * r, y = oy + d.dy * r;
        final t = g.at(x, y);
        if (t == TileType.pillar) break;
        final i = y * _w + x;
        if (t == TileType.brick || _bombTiles[i] != 0) {
          if (blast) out.add(i);
          break;
        }
        out.add(i);
      }
    }
    return out;
  }

  /// Everything a new bomb at [at] would burn, including the bombs it sets
  /// off.
  Set<int> _blastFrom(int at, int range) {
    final out = <int>{at};
    final queue = <(int, int)>[(at, range)];
    final done = <int>{at};
    for (var h = 0; h < queue.length; h++) {
      final (o, r) = queue[h];
      final rays = _rays(o, r, includeOrigin: true, blast: true);
      for (final t in rays) {
        if (_bombTiles[t] != 0 && done.add(t)) {
          final b = world.bombAt(t % _w, t ~/ _w);
          if (b != null) queue.add((t, b.range));
        }
        out.add(t);
      }
    }
    return out;
  }

  // ------------------------------------------------------------- search

  int _idx(GridPos t) => t.y * _w + t.x;

  Direction _dirBetween(int from, int to) {
    final d = to - from;
    if (d == 1) return Direction.right;
    if (d == -1) return Direction.left;
    if (d == _w) return Direction.down;
    if (d == -_w) return Direction.up;
    return Direction.none;
  }

  /// Can the bot's body walk onto tile [i] at all?
  bool _passable(Player p, int i) {
    final g = world.grid;
    final x = i % _w, y = i ~/ _w;
    if (!g.inBounds(x, y)) return false;
    final t = g.at(x, y);
    if (t == TileType.pillar || t == TileType.pit) return false;
    if (t == TileType.brick && !p.wallPass) return false;
    if (g.featureAt(x, y) == TileFeature.warp) return false;
    if (i == _virtualBomb && !p.bombPass) return false;
    if (_bombTiles[i] != 0 && !p.bombPass) {
      final b = world.bombAt(x, y);
      if (b != null && !b.passableFor.contains(p.id)) return false;
    }
    return true;
  }

  /// Seconds per tile at the bot's current speed.
  double _stepTime = 1 / Player.baseSpeed;

  /// Tile of a bomb the bot is thinking of placing.
  int _virtualBomb = -1;

  /// Is tile [i] clear of fire while the bot passes it at step [k]?
  bool _clearAt(int i, int k, double margin) {
    final st = _stepTime;
    final lo = (k - 1) * st - margin, hi = (k + 1) * st + margin;
    final list = _hard[i];
    for (var j = 0; j < list.length; j += 2) {
      if (list[j] < hi && list[j + 1] > lo) return false;
    }
    return true;
  }

  /// Can the bot stop on tile [i] after [k] steps and stay there?
  bool _safeToStand(int i, int k, {required bool relaxed, double? margin}) {
    if (_blocked[i] != 0) return false;
    if (_near[i] != 0 || (!relaxed && _soft[i] != 0)) return false;
    final m = margin ?? skill.margin;
    final arrive = (k - 1) * _stepTime - m;
    final list = _hard[i];
    for (var j = 0; j < list.length; j += 2) {
      if (list[j + 1] > arrive) return false;
    }
    return true;
  }

  bool _enterable(Player p, int i, bool relaxed) {
    if (_blocked[i] != 0 || !_passable(p, i)) return false;
    if (!relaxed && (_soft[i] != 0 || _near[i] != 0)) return false;
    return true;
  }

  /// Time-aware search for the nearest tile the bot can stay on, allowing
  /// waits so it can let a flame die down before passing.
  _Route? _search(Player p, int start,
      {required bool wait, required bool relaxed, double? margin}) {
    final m = relaxed ? 0.0 : (margin ?? skill.margin);
    final maxK = min(48, (5 / _stepTime).ceil() + 2);
    final states = _n * (maxK + 1);
    final prev = Int32List(states)..fillRange(0, states, -1);
    prev[start] = start;
    final queue = <int>[start];
    for (var h = 0; h < queue.length; h++) {
      final s = queue[h];
      final k = s ~/ _n, i = s % _n;
      if (_safeToStand(i, k, relaxed: relaxed, margin: m)) {
        if (s == start) return _Route(Direction.none, i, 0);
        var node = s;
        while (prev[node] != start) {
          node = prev[node];
        }
        return _Route(_dirBetween(start % _n, node % _n), i, k);
      }
      if (k >= maxK) continue;
      for (final next in [
        if (wait) i,
        for (final d in Direction.cardinal) i + d.dx + d.dy * _w,
      ]) {
        if (next < 0 || next >= _n) continue;
        if (next != i) {
          final dx = (next % _w) - (i % _w);
          if (dx.abs() > 1) continue; // wrapped a row
          if (!_enterable(p, next, relaxed)) continue;
        }
        if (!_clearAt(next, k + 1, m)) continue;
        final ns = (k + 1) * _n + next;
        if (prev[ns] != -1) continue;
        prev[ns] = s;
        queue.add(ns);
      }
    }
    return null;
  }

  /// Breadth-first walk over enterable tiles that are clear when the bot
  /// passes them. [visit] gets each tile and its distance; returning true
  /// stops the walk there. Returns the predecessor map.
  (Int32List, int?) _bfs(Player p, int start, bool Function(int, int) visit,
      {int maxSteps = 9999}) {
    final prev = Int32List(_n)..fillRange(0, _n, -1);
    final dist = Int32List(_n);
    prev[start] = start;
    final queue = <int>[start];
    for (var h = 0; h < queue.length; h++) {
      final cur = queue[h];
      if (visit(cur, dist[cur])) return (prev, cur);
      if (dist[cur] >= maxSteps) continue;
      for (final d in Direction.cardinal) {
        final x = cur % _w + d.dx, y = cur ~/ _w + d.dy;
        if (!world.grid.inBounds(x, y)) continue;
        final n = y * _w + x;
        if (prev[n] != -1) continue;
        if (!_enterable(p, n, false)) continue;
        if (!_clearAt(n, dist[cur] + 1, skill.margin)) continue;
        prev[n] = cur;
        dist[n] = dist[cur] + 1;
        queue.add(n);
      }
    }
    return (prev, null);
  }

  /// Shortest safe path to a tile matching [goal] that the bot can stand on.
  _Route? _pathTo(Player p, int start, bool Function(int) goal,
      {int maxSteps = 9999}) {
    final (prev, found) = _bfs(
      p,
      start,
      (i, d) => i != start && goal(i) && _safeToStand(i, d, relaxed: false),
      maxSteps: maxSteps,
    );
    if (found == null) return null;
    var node = found;
    while (prev[node] != start) {
      node = prev[node];
    }
    return _Route(_dirBetween(start, node), found, 0);
  }
}

class _PlannedBomb {
  _PlannedBomb(this.at, this.range, this.early, this.late);
  final int at;
  final int range;
  double early;
  double late;
}

class _Target {
  const _Target(this.at, this.next, this.speed, this.wallPass, this.bombPass,
      {this.enemy});
  final Enemy? enemy;
  final int at;
  final int? next;
  final double speed;
  final bool wallPass;
  final bool bombPass;
}

class _Route {
  const _Route(this.first, this.goal, this.steps);
  final Direction first;
  final int goal;
  final int steps;
}
