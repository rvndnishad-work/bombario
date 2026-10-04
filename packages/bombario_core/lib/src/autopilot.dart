import 'dart:math';
import 'dart:typed_data';

import 'direction.dart';
import 'entities.dart';
import 'grid.dart';
import 'input.dart';
import 'world.dart';

/// A solo campaign player for play-testing and recording: it breaks its way
/// to the stage's exit and power-up, clears the enemies and walks out.
///
/// Unlike [Bot] (a fair co-op buddy or versus rival) it is tuned to finish
/// stages, and by default it knows what each brick hides, like someone who
/// has played the stage before, so it heads for the exit instead of
/// clearing the whole maze. Pair it with [AutopilotRun], which rewinds and
/// retries when it dies.
///
/// Call [think] once per tick before [World.tick]; deterministic for a given
/// world and [seed].
class Autopilot {
  Autopilot(this.world, this.playerId,
      {int seed = 0, this.knowsSecrets = true, this.usePipes = true})
      : _rng = Random(seed),
        _caution = 0.15 + Random(seed).nextDouble() * 0.25;

  final World world;
  final int playerId;
  final bool knowsSecrets;

  /// Take a warp pipe once a stage, for the camera.
  final bool usePipes;
  final Random _rng;

  /// Seconds of slack kept around blasts; varies per seed so a retry after
  /// a rewind plays a little differently.
  final double _caution;

  int _tick = 0;

  /// What it decided last, for debugging.
  String goal = '';
  String debug = '';

  /// A tile to walk to and bomb from, set by a planner; cleared once the
  /// bomb is down or the tile can't be reached.
  int? _plan;

  void setPlan(GridPos tile) => _plan = tile.y * _w + tile.x;
  bool get hasPlan => _plan != null;
  final Map<int, int> _badSpots = {};
  final Map<int, int> _crackVisits = {};
  int? _lastTile;
  bool _piped = false;
  int? _wander;
  int _wanderUntil = 0;

  /// Bombs we placed, by id, with the tick they were first seen.
  final Map<int, int> _seen = {};

  late final int _w = world.grid.width;
  late final int _n = world.grid.width * world.grid.height;
  late List<List<double>> _hard = List.generate(_n, (_) => <double>[]);
  late Uint8List _blocked = Uint8List(_n);
  late Uint8List _near = Uint8List(_n);
  late Uint8List _bombTiles = Uint8List(_n);

  /// Seconds before any harmful enemy could reach each tile.
  late Float64List _enemyEta = Float64List(_n);

  static const double _forever = 1e9;

  /// Why tile ([x], [y]) is unsafe right now, for debugging.
  String why(int x, int y) {
    final i = y * _w + x;
    return 'blocked=${_blocked[i]} near=${_near[i]} eta=${_enemyEta[i].toStringAsFixed(2)} '
        'hard=${_hard[i]} crack=${_crackVisits[i]}';
  }

  /// Keeps track of the world while someone else plays (a replay before a
  /// retry), so cracked floors are still counted.
  void observe() {
    final p = world.playerById(playerId);
    if (p == null || !p.alive) {
      _lastTile = null;
      return;
    }
    final here = p.tileY * _w + p.tileX;
    if (here != _lastTile) {
      if (world.grid.at(p.tileX, p.tileY) == TileType.cracked) {
        _crackVisits[here] = (_crackVisits[here] ?? 0) + 1;
      }
      _lastTile = here;
    }
  }

  /// The input for this tick.
  PlayerInput think() {
    _tick++;
    observe();
    final p = world.playerById(playerId);
    if (p == null || world.over) return PlayerInput.idle;
    if (!p.alive || p.frozen || p.inPipe) return PlayerInput.idle;

    _stepTime = 1 / p.speed;
    _fearless = p.godMode;
    _forgetBombs();
    _buildMaps(p);
    final here = p.tileY * _w + p.tileX;
    final action = p.remote && _shouldDetonate(p);

    if (!_safeToStand(here, 0,
        ignoreEnemies: _plan != null && _blocked[here] == 0)) {
      goal = 'flee';
      final route = _search(p, here, margin: _caution) ??
          _search(p, here, margin: 0) ??
          _search(p, here, margin: 0, ignoreEnemies: true);
      var step = route?.first ?? _awayStep(p, here);
      // Cornered: a bomb between us and the enemy turns it round.
      if (route == null && _cornered(p, here)) {
        return _input(p, Direction.none, bomb: true, action: action);
      }
      if (route != null && route.goal == here) step = Direction.none;
      return _input(p, step, action: action);
    }

    final (dir, bomb, act) = _decide(p, here);
    return _input(p, dir, bomb: bomb, action: action || act);
  }

  // ------------------------------------------------------------ planning

  bool _canBomb(Player p) =>
      p.bombsPlaced < p.maxBombs &&
      world.bombAt(p.tileX, p.tileY) == null &&
      world.grid.isWalkable(p.tileX, p.tileY);

  (Direction, bool, bool) _decide(Player p, int here) {
    final canBomb = _canBomb(p);
    final plan = _plan;
    if (plan != null) {
      goal = 'plan';
      if (here == plan) {
        _plan = null;
        if (canBomb) {
          final blast = _blastFrom(here, p.fireRange);
          if (_blastOk(blast) && _bombEscape(p, here, blast) != null) {
            return (Direction.none, true, false);
          }
        }
      } else {
        // Walk there even if it's close to the enemy: the planner has
        // played this out and knows it works.
        _bold = true;
        final (prev, found) = _bfs(p, here, (i, _) => i == plan);
        _bold = false;
        if (found != null) {
          var node = found;
          while (prev[node] != here) {
            node = prev[node];
          }
          return (_dirBetween(here, node), false, false);
        }
        _plan = null;
      }
    }
    final exit = world.exitTile;
    final exitIdx = exit == null ? -1 : exit.y * _w + exit.x;

    // Power-ups lying about.
    final items = {
      for (final i in world.floorItems)
        if (i.type != ItemType.exit) i.y * _w + i.x,
    };
    if (items.isNotEmpty) {
      final r = _pathTo(p, here, items.contains);
      if (r != null) {
        goal = 'item';
        return (r.first, false, false);
      }
    }

    // Exit open: walk out.
    if (exit != null && world.allEnemiesDead && !world.config.bonusStage) {
      goal = 'exit';
      if (here == exitIdx) return (Direction.none, false, false);
      final r = _pathTo(p, here, (i) => i == exitIdx);
      if (r != null) return (r.first, false, false);
    }

    final targets = _targets();

    // An enemy in reach of a bomb dropped right here.
    if (canBomb && targets.isNotEmpty) {
      final blast = _blastFrom(here, p.fireRange);
      if (_blastOk(blast) &&
          targets.any((e) => _wouldHit(e, blast, here)) &&
          _bombEscape(p, here, blast) != null) {
        goal = 'bomb enemy';
        return (Direction.none, true, false);
      }
    }

    // The treasure chest takes three hits.
    final chest = world.treasure;
    if (chest != null) {
      final c = chest.y * _w + chest.x;
      final spots = _rays(c, p.fireRange, includeOrigin: false)
          .where((s) => !_isBadSpot(s) && _near[s] == 0)
          .toSet();
      final res = _goBomb(p, here, spots, canBomb);
      if (res != null) {
        goal = 'chest';
        return res;
      }
    }

    // Once a stage: show off a warp pipe when one is close by.
    if (usePipes && !_piped && world.grid.pipes.isNotEmpty) {
      final fronts = <int, GridPos>{
        for (final pipe in world.grid.pipes)
          if (_pipeUsable(pipe)) _idx(world.grid.pipeFront(pipe)): pipe,
      };
      if (fronts.containsKey(here)) {
        _piped = true;
        final mouth = world.grid.featureAt(fronts[here]!.x, fronts[here]!.y);
        return (mouth.pipeMouth.opposite, false, true);
      }
      final r = _pathTo(p, here, fronts.containsKey, maxSteps: 6);
      if (r != null) return (r.first, false, false);
    }

    final secrets = _secretBricks();
    final huntRange = (secrets.isEmpty || exit != null) ? 999 : 0;

    // Hunt: walk to a tile that lines up a bomb on an enemy.
    if (targets.isNotEmpty && huntRange > 0) {
      final spots = <int>{};
      for (final e in targets) {
        final at = e.tileY * _w + e.tileX;
        for (final s in _rays(at, p.fireRange, includeOrigin: false)) {
          if (_blocked[s] == 0 && !_isBadSpot(s)) spots.add(s);
        }
      }
      if (spots.contains(here)) {
        // Lined up but the bomb wouldn't land well yet: hold, unless a
        // brick wants breaking from here anyway.
        goal = 'hold for enemy';
        if (huntRange == 999) return (Direction.none, false, false);
      } else {
        _bold = true;
        final (prev, found) =
            _bfs(p, here, (i, _) => spots.contains(i), maxSteps: huntRange);
        _bold = false;
        if (found != null && found != here) {
          goal = 'hunt';
          var node = found;
          while (prev[node] != here) {
            node = prev[node];
          }
          return (_dirBetween(here, node), false, false);
        }
      }
    }

    // Break bricks, the ones in the way of the exit and power-up first.
    final res = _breakBricks(p, here, canBomb, secrets);
    if (res != null) {
      goal = 'bricks';
      return res;
    }

    // Closed gates and a plate to open them.
    if (!world.gatesOpen) {
      final plates = <int>{};
      for (final t in world.grid.positions) {
        if (world.grid.featureAt(t.x, t.y) == TileFeature.plate) {
          plates.add(_idx(t));
        }
      }
      if (plates.isNotEmpty && !plates.contains(here)) {
        final r = _pathTo(p, here, plates.contains);
        if (r != null) return (r.first, false, false);
      }
    }

    // Nothing reachable: chase enemies from afar, else wander.
    if (targets.isNotEmpty) {
      final r = _pathTo(p, here, (i) {
        final x = i % _w, y = i ~/ _w;
        return targets
            .any((e) => (e.tileX - x).abs() + (e.tileY - y).abs() <= 3);
      });
      if (r != null) return (r.first, false, false);
    }
    goal = 'wander';
    return (_wanderStep(p, here), false, false);
  }

  /// Tiles worth bombing an enemy from: in reach within [maxSteps], with a
  /// blast covering where an enemy is or could be in a couple of steps.
  /// Nearest first, at most [limit]. Call right after [think].
  List<GridPos> killSpots({int maxSteps = 14, int limit = 8}) {
    final p = world.playerById(playerId);
    if (p == null || !p.alive) return const [];
    final g = world.grid;
    final foes = <int>{};
    for (final e in _targets()) {
      final start = e.tileY * _w + e.tileX;
      final reach = e.kind.style == MoveStyle.stationary ? 0 : 2;
      final dist = <int, int>{start: 0};
      final queue = [start];
      for (var h = 0; h < queue.length; h++) {
        final cur = queue[h];
        foes.add(cur);
        if (dist[cur]! >= reach) continue;
        for (final d in Direction.cardinal) {
          final x = cur % _w + d.dx, y = cur ~/ _w + d.dy;
          if (!g.inBounds(x, y)) continue;
          final n = y * _w + x;
          if (dist.containsKey(n)) continue;
          final t = g.at(x, y);
          if (t == TileType.pillar || t == TileType.pit) continue;
          if (t == TileType.brick && !e.kind.wallPass) continue;
          dist[n] = dist[cur]! + 1;
          queue.add(n);
        }
      }
    }
    if (foes.isEmpty) return const [];
    final here = p.tileY * _w + p.tileX;
    final out = <GridPos>[];
    _bfs(p, here, (i, d) {
      if (out.length >= limit) return true;
      if (!g.isWalkable(i % _w, i ~/ _w) || _hard[i].isNotEmpty) return false;
      if (_rays(i, p.fireRange, includeOrigin: true).any(foes.contains)) {
        out.add(GridPos(i % _w, i ~/ _w));
      }
      return false;
    }, maxSteps: maxSteps);
    return out;
  }

  bool _pipeUsable(GridPos pipe) {
    final f = world.grid.pipeFront(pipe);
    return world.grid.isWalkable(f.x, f.y);
  }

  /// Walk to one of [spots] and bomb there.
  (Direction, bool, bool)? _goBomb(
      Player p, int here, Set<int> spots, bool canBomb) {
    if (spots.isEmpty) return null;
    if (spots.contains(here)) {
      if (!canBomb) return (Direction.none, false, false);
      final blast = _blastFrom(here, p.fireRange);
      if (_blastOk(blast) && _bombEscape(p, here, blast) != null) {
        return (Direction.none, true, false);
      }
      _badSpots[here] = _tick + 45;
      return null;
    }
    _bold = true;
    final (prev, found) = _bfs(p, here, (i, _) => spots.contains(i));
    _bold = false;
    if (found == null || found == here) return null;
    var node = found;
    while (prev[node] != here) {
      node = prev[node];
    }
    return (_dirBetween(here, node), false, false);
  }

  /// Bricks hiding the exit or a power-up, while they still hide them.
  Set<int> _secretBricks() {
    if (!knowsSecrets) return const {};
    final g = world.grid;
    final out = <int>{};
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        if (g.at(x, y) == TileType.brick && g.hiddenAt(x, y) != null) {
          out.add(y * _w + x);
        }
      }
    }
    return out;
  }

  (Direction, bool, bool)? _breakBricks(
      Player p, int here, bool canBomb, Set<int> secrets) {
    final g = world.grid;
    // Cheapest way through to a secret, bricks costing extra: the bricks
    // on that way are worth the most.
    final key = <int>{};
    if (secrets.isNotEmpty) {
      key.addAll(_bricksOnWayTo(p, here, secrets));
    } else {
      final foes = {
        for (final e in _targets()) e.tileY * _w + e.tileX,
      };
      if (foes.isNotEmpty) key.addAll(_bricksOnWayTo(p, here, foes));
    }

    // Score every standing spot by what a bomb there would break.
    final dist = Int32List(_n)..fillRange(0, _n, -1);
    _bfs(p, here, (i, d) {
      dist[i] = d;
      return false;
    });
    var best = -1;
    var bestScore = 0.0;
    for (var i = 0; i < _n; i++) {
      final d = dist[i];
      if (d < 0 || _blocked[i] != 0 || _isBadSpot(i) || _hard[i].isNotEmpty) {
        continue;
      }
      if (!g.isWalkable(i % _w, i ~/ _w)) continue;
      var value = 0.0;
      for (final t
          in _rays(i, p.fireRange, includeOrigin: false, blast: true)) {
        if (g.at(t % _w, t ~/ _w) != TileType.brick) continue;
        if (_hard[t].isNotEmpty) continue; // already doomed
        value += key.contains(t)
            ? 12
            : secrets.contains(t)
                ? 20
                : (key.isEmpty ? 1 : 0.1);
      }
      if (value == 0) continue;
      final score = value / (d + 3) + _rng.nextDouble() * 0.01;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    debug = 'bricks: ${key.length} on the way, best spot $best';
    if (best < 0) return null;
    return _goBomb(p, here, {best}, canBomb);
  }

  /// Bricks on the cheapest route from [here] to the nearest of [goals],
  /// walking through bricks at a cost.
  Set<int> _bricksOnWayTo(Player p, int here, Set<int> goals) {
    final g = world.grid;
    const brickCost = 10;
    final cost = Int32List(_n)..fillRange(0, _n, 1 << 30);
    final prev = Int32List(_n)..fillRange(0, _n, -1);
    // Small integer costs: a bucket queue.
    final buckets = <List<int>>[for (var i = 0; i < 16; i++) []];
    cost[here] = 0;
    buckets[0].add(here);
    var found = -1;
    var c = 0;
    var pending = 1;
    while (pending > 0 && found < 0) {
      final bucket = buckets[c % 16];
      while (bucket.isNotEmpty) {
        final cur = bucket.removeLast();
        pending--;
        if (cost[cur] != c) continue;
        if (goals.contains(cur)) {
          found = cur;
          break;
        }
        for (final d in Direction.cardinal) {
          final x = cur % _w + d.dx, y = cur ~/ _w + d.dy;
          if (!g.inBounds(x, y)) continue;
          final t = g.at(x, y);
          if (t == TileType.pillar || t == TileType.pit) continue;
          if (g.isPipe(x, y) || world.chestAt(x, y)) continue;
          final n = y * _w + x;
          final nc = c + (t == TileType.brick ? brickCost : 1);
          if (nc < cost[n]) {
            cost[n] = nc;
            prev[n] = cur;
            buckets[nc % 16].add(n);
            pending++;
          }
        }
      }
      c++;
      if (c > 4000) break;
    }
    final out = <int>{};
    for (var node = found; node >= 0 && node != here; node = prev[node]) {
      if (g.at(node % _w, node ~/ _w) == TileType.brick) out.add(node);
    }
    return out;
  }

  List<Enemy> _targets() => [
        for (final e in world.enemies)
          if (e.alive &&
              e.solid &&
              // Cloaked Shades too: we know where they lurk.
              (e.visible || knowsSecrets) &&
              !e.kind.harmless &&
              world.grid.inBounds(e.tileX, e.tileY))
            e,
      ];

  /// A blast that won't burn the open exit (it calls guards) or a power-up.
  bool _blastOk(Set<int> blast) {
    final exit = world.exitTile;
    if (exit != null && blast.contains(_idx(exit))) return false;
    for (final i in world.floorItems) {
      if (blast.contains(i.y * _w + i.x)) return false;
    }
    return true;
  }

  bool _wouldHit(Enemy e, Set<int> blast, int bombAt) {
    final at = e.tileY * _w + e.tileX;
    if (blast.contains(at)) return true;
    final t = e.target;
    if (t != null && world.grid.inBounds(t.x, t.y) && blast.contains(_idx(t))) {
      return true;
    }
    if (e.kind.style == MoveStyle.stationary) return false;
    return _trapped(e, blast, bombAt);
  }

  /// Will [e] be caught wherever it goes before the fuse runs out? True
  /// when at least half the tiles it can reach are in the blast.
  bool _trapped(Enemy e, Set<int> blast, int bombAt) {
    final g = world.grid;
    final start = e.tileY * _w + e.tileX;
    final steps = (Bomb.defaultFuse * e.kind.speed).ceil();
    final dist = <int, int>{start: 0};
    final queue = [start];
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
        if (g.isPipe(x, y) || world.chestAt(x, y)) continue;
        if (tile == TileType.brick && !e.kind.wallPass) continue;
        if (n == bombAt || _bombTiles[n] != 0) continue;
        dist[n] = dist[cur]! + 1;
        queue.add(n);
      }
    }
    return inside * 2 >= queue.length;
  }

  bool _isBadSpot(int i) => (_badSpots[i] ?? 0) > _tick;

  /// Is an enemy right next to us with no way out?
  bool _cornered(Player p, int here) {
    if (!_canBomb(p)) return false;
    for (final e in world.enemies) {
      if (!e.harmful) continue;
      if ((e.x - p.x).abs() + (e.y - p.y).abs() < 1.6) return true;
    }
    return false;
  }

  /// First step of an escape from a bomb dropped at [here] with [blast], or
  /// null when there is no safe way out.
  Direction? _bombEscape(Player p, int here, Set<int> blast) {
    final saved = _cloneHard();
    _addBlast(blast, Bomb.defaultFuse, Bomb.defaultFuse);
    _virtualBomb = here;
    final route = _search(p, here, margin: _caution);
    _virtualBomb = -1;
    _hard = saved;
    if (route == null || route.goal == here) {
      _badSpots[here] = _tick + 30;
      return null;
    }
    return route.first;
  }

  Direction _wanderStep(Player p, int here) {
    var goal = _wander;
    if (goal == null ||
        goal == here ||
        _tick > _wanderUntil ||
        !_safeToStand(goal, 0)) {
      final options = <int>[];
      _bfs(p, here, (i, d) {
        if (d >= 2 && d <= 6) options.add(i);
        return false;
      });
      if (options.isEmpty) return Direction.none;
      goal = options[_rng.nextInt(options.length)];
      _wander = goal;
      _wanderUntil = _tick + 60;
    }
    final g = goal;
    return _pathTo(p, here, (i) => i == g)?.first ?? Direction.none;
  }

  /// No safe tile in reach: the open neighbour furthest from enemies that
  /// isn't about to burn.
  Direction _awayStep(Player p, int here) {
    var best = Direction.none;
    var bestScore = _enemyEta[here] - 0.05;
    for (final d in Direction.cardinal) {
      final x = here % _w + d.dx, y = here ~/ _w + d.dy;
      if (!world.grid.inBounds(x, y)) continue;
      final n = y * _w + x;
      if (!_passable(p, n) || !_clearAt(n, 1, 0)) continue;
      final score = _enemyEta[n];
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best;
  }

  // ------------------------------------------------------------- actions

  bool _shouldDetonate(Player p) {
    for (final b in world.bombs) {
      if (b.ownerId != playerId || !b.remote) continue;
      final age = _tick - (_seen[b.id] ?? _tick);
      if (age < Bomb.defaultFuse * World.tickRate) continue;
      final blast = _blastFrom(b.y * _w + b.x, b.range);
      if (blast.contains(p.tileY * _w + p.tileX)) continue;
      // Our escape planning assumed a normal fuse; sit on it no longer.
      return true;
    }
    return false;
  }

  /// Turns a tile step into a stick direction: lines up with the lane
  /// first so the turn doesn't snag on a pillar corner.
  PlayerInput _input(Player p, Direction dir,
      {bool bomb = false, bool action = false}) {
    var d = dir;
    final threshold = max(0.06, p.speed * World.tickDt * 0.55);
    if (d == Direction.none) {
      if (p.offsetX.abs() > threshold) {
        d = p.offsetX > 0 ? Direction.left : Direction.right;
      } else if (p.offsetY.abs() > threshold) {
        d = p.offsetY > 0 ? Direction.up : Direction.down;
      }
      // Stand still on the drop tick so the bomb lands where planned.
      if (bomb) d = Direction.none;
    } else {
      final off = d.isHorizontal ? p.offsetY : p.offsetX;
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

  void _buildMaps(Player p) {
    _hard = List.generate(_n, (_) => <double>[]);
    _blocked = Uint8List(_n);
    _near = Uint8List(_n);
    _bombTiles = Uint8List(_n);
    _enemyEta = Float64List(_n)..fillRange(0, _n, _forever);
    final g = world.grid;

    // Cracked floor walked over twice gives way behind you: treat it as
    // gone once we have crossed it twice.
    for (final e in _crackVisits.entries) {
      if (e.value >= 2 && e.key != p.tileY * _w + p.tileX) _blocked[e.key] = 1;
    }

    for (final f in world.flames) {
      _hard[f.y * _w + f.x].addAll([0, f.ttl]);
    }

    final bombs = <_PlannedBomb>[];
    for (final b in world.bombs) {
      _bombTiles[b.y * _w + b.x] = 1;
    }
    for (final b in world.bombs) {
      double early, late;
      if (!b.remote) {
        early = late = max(0, b.fuse);
      } else if (b.ownerId == playerId) {
        // Ours: we set it off once a normal fuse would have run out.
        final age = (_tick - (_seen[b.id] ?? _tick)) * World.tickDt;
        early = late = max(0.3, Bomb.defaultFuse - age);
      } else {
        early = 0;
        late = _forever;
      }
      // A sliding bomb could stop anywhere along its lane: widen it.
      bombs.add(_PlannedBomb(b.y * _w + b.x,
          b.range + (b.slide != Direction.none ? 2 : 0), early, late));
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
      _addBlast(tiles, b.early, min(b.late, 60));
    }

    for (final h in world.hazards) {
      switch (h.kind) {
        case HazardKind.rock:
          _hard[h.y * _w + h.x].addAll([h.warn - 0.2, h.warn + 0.3]);
        case HazardKind.wall:
          _hard[h.y * _w + h.x].addAll([h.warn - 0.4, _forever]);
        case HazardKind.cannonLeft || HazardKind.cannonRight:
          final dx = h.kind == HazardKind.cannonLeft ? 1 : -1;
          for (var x = h.x + dx; g.inBounds(x, h.y); x += dx) {
            final t = g.at(x, h.y);
            if (t == TileType.pillar || t == TileType.brick) break;
            _hard[h.y * _w + x]
                .addAll([h.warn - 0.15, h.warn + Flame.duration + 0.1]);
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
            if (!g.inBounds(vx, vy)) continue;
            final t = g.at(vx, vy);
            if (t == TileType.pillar || t == TileType.brick) continue;
            _hard[vy * _w + vx].addAll([start - 0.15, end + 0.15]);
            // And the next cycle.
            _hard[vy * _w + vx]
                .addAll([start + period - 0.15, end + period + 0.15]);
          }
        }
      }
    }

    // Where enemies are, and how soon each could reach every tile.
    final queue = <int>[];
    final eta = _enemyEta;
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
          if (dx < reach + 0.2 && dy < reach + 0.2) {
            _blocked[i] = 1;
          } else if (dx < reach + 0.6 && dy < reach + 0.6) {
            _near[i] = 1;
          }
        }
      }
      final t = e.target;
      if (t != null && g.inBounds(t.x, t.y)) _blocked[_idx(t)] = 1;
      final d = e.direction;
      if (d != Direction.none) {
        for (var r = 1; r <= 1; r++) {
          final x = e.tileX + d.dx * r, y = e.tileY + d.dy * r;
          if (!g.inBounds(x, y) || !g.isWalkable(x, y)) break;
          _near[y * _w + x] = 1;
        }
      }
      // Time for this enemy to reach each tile, walking.
      final speed = max(0.5, e.kind.speed * (e.herded ? World.herdBoost : 1));
      final start = e.tileY * _w + e.tileX;
      if (!g.inBounds(e.tileX, e.tileY)) continue;
      final steps = <int, int>{start: 0};
      queue
        ..clear()
        ..add(start);
      final chaser = e.kind.style == MoveStyle.chase ||
          e.kind.style == MoveStyle.phaseChase ||
          e.herded;
      final slack = chaser ? 1.0 : 1.4;
      for (var h = 0; h < queue.length; h++) {
        final cur = queue[h];
        final s = steps[cur]!;
        final time = max(0.0, (s - e.kind.size) / speed * slack);
        if (time < eta[cur]) eta[cur] = time;
        if (s >= 8) continue;
        for (final dd in Direction.cardinal) {
          final x = cur % _w + dd.dx, y = cur ~/ _w + dd.dy;
          if (!g.inBounds(x, y)) continue;
          final n = y * _w + x;
          if (steps.containsKey(n)) continue;
          final tile = g.at(x, y);
          if (tile == TileType.pillar && e.kind.style != MoveStyle.phaseChase) {
            continue;
          }
          if ((tile == TileType.brick) && !e.kind.wallPass) continue;
          if (tile == TileType.pit && e.kind.style != MoveStyle.phaseChase) {
            continue;
          }
          if (_bombTiles[n] != 0 && !e.kind.wallPass) continue;
          steps[n] = s + 1;
          queue.add(n);
        }
      }
    }
  }

  void _addBlast(Iterable<int> tiles, double early, double late) {
    for (final t in tiles) {
      _hard[t].addAll([early - 0.05, late + Flame.duration]);
    }
  }

  List<List<double>> _cloneHard() => [for (final l in _hard) List.of(l)];

  /// Tiles in line with [origin] up to [range], stopped by pillars, bricks,
  /// pipes, the chest and bombs as a blast is. With [blast] the stopping
  /// brick, chest or bomb tile is included (it gets hit).
  List<int> _rays(int origin, int range,
      {required bool includeOrigin, bool blast = false}) {
    final g = world.grid;
    final ox = origin % _w, oy = origin ~/ _w;
    final out = <int>[if (includeOrigin) origin];
    for (final d in Direction.cardinal) {
      for (var r = 1; r <= range; r++) {
        final x = ox + d.dx * r, y = oy + d.dy * r;
        if (!g.inBounds(x, y)) break;
        final t = g.at(x, y);
        if (t == TileType.pillar || g.isPipe(x, y)) break;
        final i = y * _w + x;
        if (t == TileType.brick || _bombTiles[i] != 0 || world.chestAt(x, y)) {
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
      for (final t in _rays(o, r, includeOrigin: true, blast: true)) {
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

  bool _passable(Player p, int i) {
    final g = world.grid;
    final x = i % _w, y = i ~/ _w;
    if (!g.inBounds(x, y)) return false;
    final t = g.at(x, y);
    if (t == TileType.pillar || t == TileType.pit) return false;
    if (t == TileType.brick && !p.wallPass) return false;
    if (g.isPipe(x, y) || world.chestAt(x, y)) return false;
    if (g.featureAt(x, y) == TileFeature.warp) return false;
    if (i == _virtualBomb && !p.bombPass) return false;
    if (_bombTiles[i] != 0 && !p.bombPass) {
      final b = world.bombAt(x, y);
      if (b != null && !b.passableFor.contains(p.id)) return false;
    }
    return true;
  }

  double _stepTime = 1 / Player.baseSpeed;
  int _virtualBomb = -1;

  /// In god mode enemies can't hurt us: walk right through them.
  bool _fearless = false;

  /// Following a plan: walk close to enemies, just not into them.
  bool _bold = false;

  /// Is tile [i] clear of fire while we pass it at step [k]?
  bool _clearAt(int i, int k, double margin) {
    final st = _stepTime;
    final lo = (k - 1) * st - margin, hi = (k + 1) * st + margin;
    final list = _hard[i];
    for (var j = 0; j < list.length; j += 2) {
      if (list[j] < hi && list[j + 1] > lo) return false;
    }
    return true;
  }

  /// Is an enemy unable to get to tile [i] before we're through it?
  bool _enemyClear(int i, int k) =>
      _bold || _enemyEta[i] > (k + 1) * _stepTime * 0.7 + 0.15;

  /// Can we stop on tile [i] after [k] steps and stay there?
  bool _safeToStand(int i, int k,
      {double? margin, bool ignoreEnemies = false}) {
    if (!ignoreEnemies && !_fearless) {
      if (_blocked[i] != 0) return false;
      if (_enemyEta[i] < 0.6) return false;
    }
    final m = margin ?? _caution;
    final arrive = (k - 1) * _stepTime - m;
    final list = _hard[i];
    for (var j = 0; j < list.length; j += 2) {
      if (list[j + 1] > arrive && list[j] < 30) return false;
    }
    return true;
  }

  bool _enterable(Player p, int i, int k, {bool ignoreEnemies = false}) {
    if (!_passable(p, i)) return false;
    if (ignoreEnemies || _fearless) return true;
    if (_blocked[i] != 0) return false;
    return _enemyClear(i, k);
  }

  /// Time-aware search for the nearest tile we can stay on, allowing waits
  /// so a flame can die down before we pass.
  _Route? _search(Player p, int start,
      {required double margin, bool ignoreEnemies = false}) {
    final maxK = min(48, (5 / _stepTime).ceil() + 2);
    final states = _n * (maxK + 1);
    final prev = Int32List(states)..fillRange(0, states, -1);
    prev[start] = start;
    final queue = <int>[start];
    for (var h = 0; h < queue.length; h++) {
      final s = queue[h];
      final k = s ~/ _n, i = s % _n;
      if (_safeToStand(i, k, margin: margin, ignoreEnemies: ignoreEnemies)) {
        if (s == start) return _Route(Direction.none, i, 0);
        var node = s;
        while (prev[node] != start) {
          node = prev[node];
        }
        return _Route(_dirBetween(start % _n, node % _n), i, k);
      }
      if (k >= maxK) continue;
      for (final next in [
        i,
        for (final d in Direction.cardinal) i + d.dx + d.dy * _w,
      ]) {
        if (next < 0 || next >= _n) continue;
        if (next != i) {
          final dx = (next % _w) - (i % _w);
          if (dx.abs() > 1) continue;
          if (!_enterable(p, next, k, ignoreEnemies: ignoreEnemies)) continue;
        } else if (!ignoreEnemies && _blocked[i] != 0 && k > 0) {
          continue;
        }
        if (!_clearAt(next, k + 1, margin)) continue;
        final ns = (k + 1) * _n + next;
        if (prev[ns] != -1) continue;
        prev[ns] = s;
        queue.add(ns);
      }
    }
    return null;
  }

  /// Breadth-first walk over tiles that are clear when we pass them.
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
        if (!_enterable(p, n, dist[cur])) continue;
        if (!_clearAt(n, dist[cur] + 1, _caution)) continue;
        prev[n] = cur;
        dist[n] = dist[cur] + 1;
        queue.add(n);
      }
    }
    return (prev, null);
  }

  /// Shortest safe path to a tile matching [goal] that we can stand on.
  _Route? _pathTo(Player p, int start, bool Function(int) goal,
      {int maxSteps = 9999}) {
    final (prev, found) = _bfs(
      p,
      start,
      (i, d) => i != start && goal(i) && _safeToStand(i, d),
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

class _Route {
  const _Route(this.first, this.goal, this.steps);
  final Direction first;
  final int goal;
  final int steps;
}
