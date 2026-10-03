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
    this.livesLeft = 0,
    this.pings = const [],
    this.sonar = const [],
    this.hazards = const [],
    this.wind = Direction.none,
    this.windNext = Direction.none,
    this.ventPhase = VentPhase.idle,
    this.ventTimeLeft = 0,
    this.darkness = 0,
    this.regrowing = const [],
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

  /// Revives left in the co-op pool.
  final int livesLeft;
  final List<PingState> pings;

  /// Items Sonar revealed under bricks (only these hidden items are sent).
  final List<ItemState> sonar;

  /// Telegraphed hazards: falling-rock shadows, cannon rows, closing arena
  /// tiles. x, y, seconds until impact and [HazardKind].
  final List<HazardState> hazards;

  /// Current gust (World 5), and during a lull the one coming next.
  final Direction wind;
  final Direction windNext;

  /// Shared steam-vent cycle (World 3) and seconds until it changes.
  final VentPhase ventPhase;
  final double ventTimeLeft;

  /// Vision radius in tiles on dark stages (World 4), 0 when lit.
  final int darkness;

  /// Possessed bricks waiting to grow back: x, y and seconds left.
  final List<HazardState> regrowing;

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
        livesLeft: livesLeft,
        pings: pings,
        sonar: sonar,
        hazards: hazards,
        wind: wind,
        windNext: windNext,
        ventPhase: ventPhase,
        ventTimeLeft: ventTimeLeft,
        darkness: darkness,
        regrowing: regrowing,
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
        bombs: [
          for (final b in w.bombs)
            BombState(
              b.x,
              b.y,
              b.fuse,
              b.remote,
              frost: b.frost,
              slide: b.slide,
              slideProgress: b.slideProgress,
            ),
        ],
        flames: [
          for (final f in w.flames) FlameState(f.x, f.y, frost: f.frost)
        ],
        items: [for (final i in w.floorItems) ItemState(i.x, i.y, i.type)],
        enemies: [for (final e in w.enemies) EnemyState.of(e)],
        cleared: w.cleared,
        failed: w.failed,
        winnerId: w.winnerId,
        exitHoldProgress: w.exitHoldProgress,
        livesLeft: w.livesLeft,
        pings: [
          for (final p in w.pings) PingState(p.playerId, p.kind, p.x, p.y),
        ],
        sonar: [for (final s in w.sonar) ItemState(s.x, s.y, s.type)],
        hazards: [
          for (final h in w.hazards)
            HazardState(h.x, h.y, h.warn, kind: h.kind),
        ],
        wind: w.wind,
        windNext: w.windNext,
        ventPhase: w.ventPhase,
        ventTimeLeft: w.ventTimeLeft,
        darkness: w.config.darkness,
        regrowing: [
          for (final r in w.regrowing.entries)
            HazardState(r.key.x, r.key.y, r.value),
        ],
      );

  Map<String, dynamic> toJson() => {
        'tick': tick,
        'time': timeLeft,
        'grid': _encodeGrid(grid),
        'players': [for (final p in players) p.toJson()],
        'bombs': [
          for (final b in bombs)
            [
              b.x,
              b.y,
              b.fuse,
              b.remote,
              b.frost,
              b.slide.index,
              b.slideProgress
            ],
        ],
        'flames': [
          for (final f in flames) [f.x, f.y, f.frost],
        ],
        'items': [
          for (final i in items) [i.x, i.y, i.type.index],
        ],
        'enemies': [for (final e in enemies) e.toJson()],
        'cleared': cleared,
        'failed': failed,
        if (winnerId != null) 'winner': winnerId,
        'exitHold': exitHoldProgress,
        'lives': livesLeft,
        if (pings.isNotEmpty)
          'pings': [
            for (final p in pings) [p.playerId, p.kind.index, p.x, p.y],
          ],
        if (sonar.isNotEmpty)
          'sonar': [
            for (final s in sonar) [s.x, s.y, s.type.index],
          ],
        if (hazards.isNotEmpty)
          'hz': [
            for (final h in hazards) [h.x, h.y, h.warn, h.kind.index],
          ],
        if (wind != Direction.none) 'wind': wind.index,
        if (windNext != Direction.none) 'windNext': windNext.index,
        if (ventPhase != VentPhase.idle || ventTimeLeft > 0)
          'vent': [ventPhase.index, ventTimeLeft],
        if (darkness > 0) 'dark': darkness,
        if (regrowing.isNotEmpty)
          'rg': [
            for (final r in regrowing) [r.x, r.y, r.warn],
          ],
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
            BombState(
              b[0] as int,
              b[1] as int,
              (b[2] as num).toDouble(),
              b[3] as bool,
              frost: (b as List).length > 4 && b[4] as bool,
              slide:
                  b.length > 5 ? Direction.values[b[5] as int] : Direction.none,
              slideProgress: b.length > 6 ? (b[6] as num).toDouble() : 0,
            ),
        ],
        flames: [
          for (final f in j['flames'] as List)
            FlameState(
              f[0] as int,
              f[1] as int,
              frost: (f as List).length > 2 && f[2] as bool,
            ),
        ],
        items: [
          for (final i in j['items'] as List)
            ItemState(i[0] as int, i[1] as int, ItemType.values[i[2] as int]),
        ],
        enemies: [
          for (final e in j['enemies'] as List) EnemyState.fromJson(e as List),
        ],
        cleared: j['cleared'] as bool? ?? false,
        failed: j['failed'] as bool? ?? false,
        winnerId: j['winner'] as int?,
        exitHoldProgress: (j['exitHold'] as num?)?.toDouble() ?? 0,
        livesLeft: j['lives'] as int? ?? 0,
        pings: [
          for (final p in (j['pings'] as List?) ?? const [])
            PingState(
              p[0] as int,
              PingKind.values[p[1] as int],
              p[2] as int,
              p[3] as int,
            ),
        ],
        sonar: [
          for (final s in (j['sonar'] as List?) ?? const [])
            ItemState(s[0] as int, s[1] as int, ItemType.values[s[2] as int]),
        ],
        hazards: [
          for (final h in (j['hz'] as List?) ?? const [])
            HazardState(
              h[0] as int,
              h[1] as int,
              (h[2] as num).toDouble(),
              kind: (h as List).length > 3
                  ? HazardKind.values[h[3] as int]
                  : HazardKind.rock,
            ),
        ],
        wind: Direction.values[j['wind'] as int? ?? 0],
        windNext: Direction.values[j['windNext'] as int? ?? 0],
        ventPhase: VentPhase.values[(j['vent'] as List?)?[0] as int? ?? 0],
        ventTimeLeft: ((j['vent'] as List?)?[1] as num?)?.toDouble() ?? 0,
        darkness: j['dark'] as int? ?? 0,
        regrowing: [
          for (final r in (j['rg'] as List?) ?? const [])
            HazardState(r[0] as int, r[1] as int, (r[2] as num).toDouble()),
        ],
      );

  // Grid as one character per tile. Hidden items stay secret: the server
  // never sends them.
  static const _tileChars = {
    TileType.floor: '.',
    TileType.pillar: '#',
    TileType.brick: '+',
    TileType.cracked: '~',
    TileType.pit: 'o',
  };
  static final _charTiles = {
    for (final e in _tileChars.entries) e.value: e.key,
  };

  static Map<String, dynamic> _encodeGrid(Grid g) {
    final sb = StringBuffer();
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        sb.write(_tileChars[g.at(x, y)]);
      }
    }
    return {
      'w': g.width,
      'h': g.height,
      't': sb.toString(),
      // Features, one character per tile: 'a' + TileFeature.index.
      if (g.hasFeatures)
        'f': String.fromCharCodes([
          for (final p in g.positions)
            _featureBase + g.featureAt(p.x, p.y).index,
        ]),
    };
  }

  static const _featureBase = 0x61; // 'a'

  static Grid _decodeGrid(Map<String, dynamic> j) {
    final w = j['w'] as int, h = j['h'] as int, t = j['t'] as String;
    final g = Grid(w, h);
    for (var i = 0; i < w * h; i++) {
      g.set(i % w, i ~/ w, _charTiles[t[i]] ?? TileType.floor);
    }
    final f = j['f'] as String?;
    if (f != null) {
      for (var i = 0; i < w * h && i < f.length; i++) {
        final index = f.codeUnitAt(i) - _featureBase;
        if (index > 0 && index < TileFeature.values.length) {
          g.setFeature(i % w, i ~/ w, TileFeature.values[index]);
        }
      }
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
    this.ghost = false,
    this.tombstone,
    this.reviveProgress = 0,
    this.hauntUsed = false,
    this.frozenFor = 0,
    this.hearts = 0,
    this.kick = false,
    this.frostBombs = 0,
    this.active = ActiveItem.none,
    this.cursedFor = 0,
    this.momentum = Direction.none,
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

  final bool ghost;
  final GridPos? tombstone;

  /// 0 to 1: how far a teammate has got reviving this ghost.
  final double reviveProgress;
  final bool hauntUsed;
  final double frozenFor;
  final int hearts;
  final bool kick;
  final int frostBombs;
  final ActiveItem active;

  /// Seconds of the Lantern Witch's curse left (controls reversed).
  final double cursedFor;

  /// Direction the player is sliding on ice.
  final Direction momentum;

  bool get frozen => frozenFor > 0;
  bool get cursed => cursedFor > 0;

  /// What the Action button does right now, or null when it does nothing.
  String? get actionLabel {
    if (ghost) return hauntUsed ? null : 'haunt';
    if (!alive) return null;
    return switch (active) {
      ActiveItem.remote => 'detonate',
      ActiveItem.tether => 'tether',
      ActiveItem.none => null,
    };
  }

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
        ghost: p.ghost,
        tombstone: p.tombstone,
        reviveProgress: (p.reviveProgress / World.reviveSeconds).clamp(0, 1),
        hauntUsed: p.hauntUsed,
        frozenFor: p.frozenFor,
        hearts: p.hearts,
        kick: p.kick,
        frostBombs: p.frostBombs,
        active: p.active,
        cursedFor: p.cursedFor,
        momentum: p.momentum,
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
        ghost: ghost,
        tombstone: tombstone,
        reviveProgress: reviveProgress,
        hauntUsed: hauntUsed,
        frozenFor: frozenFor,
        hearts: hearts,
        kick: kick,
        frostBombs: frostBombs,
        active: active,
        cursedFor: cursedFor,
        momentum: momentum,
      );

  /// A mutable [Player] body with this state, for client-side prediction.
  Player toPlayer() => Player(id: id, x: x, y: y, name: name)
    ..alive = alive
    ..facing = facing
    ..speed = speed
    ..wallPass = wallPass
    ..bombPass = bombPass
    ..ghost = ghost
    ..frozenFor = frozenFor
    ..cursedFor = cursedFor
    ..momentum = momentum;

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
        if (ghost) 'g': true,
        if (tombstone != null) 't': [tombstone!.x, tombstone!.y],
        if (reviveProgress > 0) 'rv': reviveProgress,
        if (hauntUsed) 'h': true,
        if (frozenFor > 0) 'z': frozenFor,
        if (hearts > 0) 'hp': hearts,
        if (kick) 'k': true,
        if (frostBombs > 0) 'fb': frostBombs,
        if (active != ActiveItem.none) 'ac': active.index,
        if (cursedFor > 0) 'cu': cursedFor,
        if (momentum != Direction.none) 'mo': momentum.index,
      };

  static PlayerState fromJson(Map<String, dynamic> j) {
    final t = j['t'] as List?;
    return PlayerState(
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
      ghost: j['g'] as bool? ?? false,
      tombstone: t == null ? null : GridPos(t[0] as int, t[1] as int),
      reviveProgress: (j['rv'] as num?)?.toDouble() ?? 0,
      hauntUsed: j['h'] as bool? ?? false,
      frozenFor: (j['z'] as num?)?.toDouble() ?? 0,
      hearts: j['hp'] as int? ?? 0,
      kick: j['k'] as bool? ?? false,
      frostBombs: j['fb'] as int? ?? 0,
      active: ActiveItem.values[j['ac'] as int? ?? 0],
      cursedFor: (j['cu'] as num?)?.toDouble() ?? 0,
      momentum: Direction.values[j['mo'] as int? ?? 0],
    );
  }
}

class BombState {
  const BombState(
    this.x,
    this.y,
    this.fuse,
    this.remote, {
    this.frost = false,
    this.slide = Direction.none,
    this.slideProgress = 0,
  });
  final int x;
  final int y;
  final double fuse;
  final bool remote;
  final bool frost;

  /// A kicked bomb's direction and progress towards the next tile, so the
  /// renderer can draw it between tiles.
  final Direction slide;
  final double slideProgress;
}

class FlameState {
  const FlameState(this.x, this.y, {this.frost = false});
  final int x;
  final int y;
  final bool frost;
}

class ItemState {
  const ItemState(this.x, this.y, this.type);
  final int x;
  final int y;
  final ItemType type;
}

class PingState {
  const PingState(this.playerId, this.kind, this.x, this.y);
  final int playerId;
  final PingKind kind;
  final int x;
  final int y;
}

class HazardState {
  const HazardState(this.x, this.y, this.warn, {this.kind = HazardKind.rock});
  final int x;
  final int y;

  /// Seconds until impact (or, for regrowing bricks, until regrowth).
  final double warn;

  /// For cannons, [x] is the wall the shot comes from and [y] the row.
  final HazardKind kind;
}

class EnemyState {
  const EnemyState(
    this.id,
    this.x,
    this.y,
    this.alive,
    this.kind, {
    this.state = EnemyStateKind.normal,
    this.hp = 1,
    this.maxHp = 1,
    this.frozen = false,
    this.slowed = false,
    this.facing = Direction.none,
    this.landing,
    this.disguise,
    this.visible = true,
    this.herded = false,
  });

  final int id;
  final double x;
  final double y;
  final bool alive;

  /// [EnemyKind.name]; look the kind up with [EnemyKind.byName].
  final String kind;
  final EnemyStateKind state;
  final int hp;
  final int maxHp;
  final bool frozen;
  final bool slowed;
  final Direction facing;

  /// Where a Hopper will land or a Phase Wraith / boss will appear.
  final GridPos? landing;

  /// The power-up a disguised Mimic is pretending to be.
  final ItemType? disguise;

  /// False while a Shade is cloaked: draw nothing, or a faint shimmer.
  final bool visible;

  /// Sped up by a nearby Herder: draw an aura.
  final bool herded;

  EnemyKind? get kindData => EnemyKind.byName[kind];

  EnemyState copyWith({double? x, double? y}) => EnemyState(
        id,
        x ?? this.x,
        y ?? this.y,
        alive,
        kind,
        state: state,
        hp: hp,
        maxHp: maxHp,
        frozen: frozen,
        slowed: slowed,
        facing: facing,
        landing: landing,
        disguise: disguise,
        visible: visible,
        herded: herded,
      );

  static EnemyState of(Enemy e) => EnemyState(
        e.id,
        e.x,
        e.y,
        e.alive,
        e.kind.name,
        state: e.state,
        hp: e.hp,
        maxHp: e.maxHp,
        frozen: e.frozen,
        slowed: e.slowFor > 0,
        facing: e.direction,
        landing: e.landing,
        disguise: e.state == EnemyStateKind.disguised ? e.disguise : null,
        visible: e.visible,
        herded: e.herded,
      );

  List<Object> toJson() => [
        id,
        x,
        y,
        alive,
        kind,
        state.index,
        hp,
        maxHp,
        frozen,
        slowed,
        facing.index,
        landing?.x ?? -1,
        landing?.y ?? -1,
        disguise?.index ?? -1,
        visible,
        herded,
      ];

  static EnemyState fromJson(List e) => EnemyState(
        e[0] as int,
        (e[1] as num).toDouble(),
        (e[2] as num).toDouble(),
        e[3] as bool,
        e[4] as String,
        state: e.length > 5
            ? EnemyStateKind.values[e[5] as int]
            : EnemyStateKind.normal,
        hp: e.length > 6 ? e[6] as int : 1,
        maxHp: e.length > 7 ? e[7] as int : 1,
        frozen: e.length > 8 && e[8] as bool,
        slowed: e.length > 9 && e[9] as bool,
        facing: e.length > 10 ? Direction.values[e[10] as int] : Direction.none,
        landing: e.length > 12 && (e[11] as int) >= 0
            ? GridPos(e[11] as int, e[12] as int)
            : null,
        disguise: e.length > 13 && (e[13] as int) >= 0
            ? ItemType.values[e[13] as int]
            : null,
        visible: e.length <= 14 || e[14] as bool,
        herded: e.length > 15 && e[15] as bool,
      );
}
