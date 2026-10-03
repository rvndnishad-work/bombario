import 'direction.dart';
import 'entities.dart';
import 'grid.dart';
import 'world.dart';

/// An immutable, serialisable picture of a [World] at one tick.
///
/// The renderer draws snapshots, never a live [World], so the same renderer
/// works for solo play (snapshot of the local simulation) and for networked
/// play (snapshot decoded from the server). Encoding is JSON for now; a
/// binary encoding can replace [toJson]/[fromJson] without touching callers.
class WorldSnapshot {
  const WorldSnapshot({
    required this.tick,
    required this.timeLeft,
    required this.grid,
    required this.players,
    required this.bombs,
    required this.flames,
    required this.items,
    required this.enemies,
    this.cleared = false,
    this.failed = false,
    this.winnerId,
    this.exitHoldProgress = 0,
  });

  final int tick;
  final double timeLeft;
  final Grid grid;
  final List<PlayerState> players;
  final List<BombState> bombs;
  final List<FlameState> flames;
  final List<ItemState> items;
  final List<EnemyState> enemies;
  final bool cleared;
  final bool failed;
  final int? winnerId;
  final double exitHoldProgress;

  bool get over => cleared || failed || winnerId != null;

  WorldSnapshot copyWith({
    List<PlayerState>? players,
    List<EnemyState>? enemies,
  }) =>
      WorldSnapshot(
        tick: tick,
        timeLeft: timeLeft,
        grid: grid,
        players: players ?? this.players,
        bombs: bombs,
        flames: flames,
        items: items,
        enemies: enemies ?? this.enemies,
        cleared: cleared,
        failed: failed,
        winnerId: winnerId,
        exitHoldProgress: exitHoldProgress,
      );

  bool bombAt(int x, int y) => bombs.any((b) => b.x == x && b.y == y);

  PlayerState? player(int id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// [ackedInputs] maps a player id to the last input sequence number the
  /// server applied for them, which clients use to reconcile prediction.
  static WorldSnapshot of(
    World w, {
    int tick = 0,
    Map<int, int> ackedInputs = const {},
  }) =>
      WorldSnapshot(
        tick: tick,
        timeLeft: w.timeLeft,
        grid: w.grid,
        players: [
          for (final p in w.players)
            PlayerState.of(p, ackedInput: ackedInputs[p.id] ?? 0),
        ],
        bombs: [for (final b in w.bombs) BombState(b.x, b.y, b.fuse, b.remote)],
        flames: [for (final f in w.flames) FlameState(f.x, f.y)],
        items: [for (final i in w.floorItems) ItemState(i.x, i.y, i.type)],
        enemies: [
          for (final e in w.enemies)
            EnemyState(e.id, e.x, e.y, e.alive, e.kind.name),
        ],
        cleared: w.cleared,
        failed: w.failed,
        winnerId: w.winnerId,
        exitHoldProgress: w.exitHoldProgress,
      );

  Map<String, dynamic> toJson() => {
        'tick': tick,
        'time': timeLeft,
        'grid': _encodeGrid(grid),
        'players': [for (final p in players) p.toJson()],
        'bombs': [
          for (final b in bombs) [b.x, b.y, b.fuse, b.remote],
        ],
        'flames': [
          for (final f in flames) [f.x, f.y],
        ],
        'items': [
          for (final i in items) [i.x, i.y, i.type.index],
        ],
        'enemies': [
          for (final e in enemies) [e.id, e.x, e.y, e.alive, e.kind],
        ],
        'cleared': cleared,
        'failed': failed,
        if (winnerId != null) 'winner': winnerId,
        'exitHold': exitHoldProgress,
      };

  static WorldSnapshot fromJson(Map<String, dynamic> j) => WorldSnapshot(
        tick: j['tick'] as int,
        timeLeft: (j['time'] as num).toDouble(),
        grid: _decodeGrid(j['grid'] as Map<String, dynamic>),
        players: [
          for (final p in j['players'] as List)
            PlayerState.fromJson(p as Map<String, dynamic>),
        ],
        bombs: [
          for (final b in j['bombs'] as List)
            BombState(b[0] as int, b[1] as int, (b[2] as num).toDouble(),
                b[3] as bool),
        ],
        flames: [
          for (final f in j['flames'] as List)
            FlameState(f[0] as int, f[1] as int),
        ],
        items: [
          for (final i in j['items'] as List)
            ItemState(i[0] as int, i[1] as int, ItemType.values[i[2] as int]),
        ],
        enemies: [
          for (final e in j['enemies'] as List)
            EnemyState(e[0] as int, (e[1] as num).toDouble(),
                (e[2] as num).toDouble(), e[3] as bool, e[4] as String),
        ],
        cleared: j['cleared'] as bool? ?? false,
        failed: j['failed'] as bool? ?? false,
        winnerId: j['winner'] as int?,
        exitHoldProgress: (j['exitHold'] as num?)?.toDouble() ?? 0,
      );

  // Grid as one character per tile: '.' floor, '#' pillar, '+' brick.
  // Hidden items stay secret: the server never sends them.
  static Map<String, dynamic> _encodeGrid(Grid g) {
    final sb = StringBuffer();
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        sb.write(switch (g.at(x, y)) {
          TileType.floor => '.',
          TileType.pillar => '#',
          TileType.brick => '+',
        });
      }
    }
    return {'w': g.width, 'h': g.height, 't': sb.toString()};
  }

  static Grid _decodeGrid(Map<String, dynamic> j) {
    final w = j['w'] as int, h = j['h'] as int, t = j['t'] as String;
    final g = Grid(w, h);
    for (var i = 0; i < w * h; i++) {
      g.set(
        i % w,
        i ~/ w,
        switch (t[i]) {
          '#' => TileType.pillar,
          '+' => TileType.brick,
          _ => TileType.floor,
        },
      );
    }
    return g;
  }
}

class PlayerState {
  const PlayerState({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.alive,
    required this.facing,
    required this.invincible,
    required this.maxBombs,
    required this.fireRange,
    required this.remote,
    required this.score,
    this.speed = Player.baseSpeed,
    this.wallPass = false,
    this.bombPass = false,
    this.ackedInput = 0,
  });

  final int id;
  final String name;
  final double x;
  final double y;
  final bool alive;
  final Direction facing;
  final bool invincible;
  final int maxBombs;
  final int fireRange;
  final bool remote;
  final int score;
  final double speed;
  final bool wallPass;
  final bool bombPass;

  /// Sequence number of the last input the server applied for this player.
  final int ackedInput;

  static PlayerState of(Player p, {int ackedInput = 0}) => PlayerState(
        id: p.id,
        name: p.name,
        x: p.x,
        y: p.y,
        alive: p.alive,
        facing: p.facing,
        invincible: p.invincible,
        maxBombs: p.maxBombs,
        fireRange: p.fireRange,
        remote: p.remote,
        score: p.score,
        speed: p.speed,
        wallPass: p.wallPass,
        bombPass: p.bombPass,
        ackedInput: ackedInput,
      );

  PlayerState copyWith({double? x, double? y, Direction? facing}) =>
      PlayerState(
        id: id,
        name: name,
        x: x ?? this.x,
        y: y ?? this.y,
        alive: alive,
        facing: facing ?? this.facing,
        invincible: invincible,
        maxBombs: maxBombs,
        fireRange: fireRange,
        remote: remote,
        score: score,
        speed: speed,
        wallPass: wallPass,
        bombPass: bombPass,
        ackedInput: ackedInput,
      );

  /// A mutable [Player] body with this state, for client-side prediction.
  Player toPlayer() => Player(id: id, x: x, y: y, name: name)
    ..alive = alive
    ..facing = facing
    ..speed = speed
    ..wallPass = wallPass
    ..bombPass = bombPass;

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'x': x,
        'y': y,
        'a': alive,
        'f': facing.index,
        'i': invincible,
        'b': maxBombs,
        'r': fireRange,
        'd': remote,
        's': score,
        'v': speed,
        'w': wallPass,
        'p': bombPass,
        'q': ackedInput,
      };

  static PlayerState fromJson(Map<String, dynamic> j) => PlayerState(
        id: j['id'] as int,
        name: j['n'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        alive: j['a'] as bool,
        facing: Direction.values[j['f'] as int],
        invincible: j['i'] as bool,
        maxBombs: j['b'] as int,
        fireRange: j['r'] as int,
        remote: j['d'] as bool,
        score: j['s'] as int,
        speed: (j['v'] as num?)?.toDouble() ?? Player.baseSpeed,
        wallPass: j['w'] as bool? ?? false,
        bombPass: j['p'] as bool? ?? false,
        ackedInput: j['q'] as int? ?? 0,
      );
}

class BombState {
  const BombState(this.x, this.y, this.fuse, this.remote);
  final int x;
  final int y;
  final double fuse;
  final bool remote;
}

class FlameState {
  const FlameState(this.x, this.y);
  final int x;
  final int y;
}

class ItemState {
  const ItemState(this.x, this.y, this.type);
  final int x;
  final int y;
  final ItemType type;
}

class EnemyState {
  const EnemyState(this.id, this.x, this.y, this.alive, this.kind);
  final int id;
  final double x;
  final double y;
  final bool alive;
  final String kind;
}
