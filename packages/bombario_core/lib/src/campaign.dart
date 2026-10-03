import 'dart:math';

import 'entities.dart';
import 'grid.dart';
import 'level.dart';
import 'world.dart';

/// One campaign stage from the design doc's stage table (§8.2).
///
/// Enemy counts are for two players and scale +25% per extra player; a solo
/// player gets 75%. Bosses gain 60% HP per extra player (§7).
class StageDef {
  const StageDef({
    required this.id,
    required this.name,
    this.enemies = const [],
    this.items = const [],
    this.brickDensity = 0.4,
    this.timeLimit = 240,
    this.layout,
    this.layoutEnemies = const [],
    this.crackedTiles = 0,
    this.friendlyStun = false,
    this.bonus = false,
    this.bonusKind = EnemyKind.puffball,
    this.boss,
    this.stalactites = 0,
    this.tip = '',
  });

  /// "world-stage", e.g. `1-4`.
  final String id;
  final String name;
  final List<(EnemyKind, int)> enemies;

  /// Power-ups hidden under bricks; topped up to one per player plus one.
  final List<ItemType> items;
  final double brickDensity;
  final double timeLimit;

  /// Hand-made layout in the [LevelData.parse] format, or null to generate.
  final String? layout;

  /// Kinds for the layout's `e` tiles, in reading order.
  final List<EnemyKind> layoutEnemies;
  final int crackedTiles;
  final bool friendlyStun;
  final bool bonus;
  final EnemyKind bonusKind;
  final EnemyKind? boss;

  /// Seconds between falling rocks, 0 for none.
  final double stalactites;

  /// One line shown before the stage starts.
  final String tip;

  int get world => int.parse(id.split('-').first);
  int get number => int.parse(id.split('-').last);
  bool get isBoss => boss != null;

  static int scaleCount(int twoPlayerCount, int players) => max(
        1,
        (twoPlayerCount * (players <= 1 ? 0.75 : 1 + 0.25 * (players - 2)))
            .round(),
      );

  static int scaleBossHp(int hp, int players) =>
      (hp * (1 + 0.6 * (max(1, players) - 1))).round();

  /// Builds the stage for [players] players.
  LevelData level({required int seed, required int players}) {
    final n = players.clamp(1, 4);
    final b = boss;
    if (b != null) return _bossArena(b, seed, n);
    final l = layout;
    if (l != null) {
      return LevelData.parse(
        l,
        items: items.isEmpty ? const [ItemType.bombUp] : items,
        enemyKinds:
            layoutEnemies.isEmpty ? const [EnemyKind.puffball] : layoutEnemies,
        timeLimit: timeLimit,
        name: '$id $name',
      );
    }
    final rng = Random(seed);
    const basics = [ItemType.bombUp, ItemType.fireUp, ItemType.speedUp];
    final hidden = [
      ...items,
      for (var i = items.length; i < n + 1; i++)
        basics[rng.nextInt(basics.length)],
    ];
    final mix = bonus
        ? <EnemyKind>[]
        : [
            for (final (kind, count) in enemies)
              for (var i = 0; i < scaleCount(count, n); i++) kind,
          ];
    final big = n > 2;
    return LevelData.generate(
      seed: seed,
      width: big ? 41 : 31,
      height: big ? 17 : 13,
      players: n,
      brickDensity: brickDensity,
      enemyMix: mix,
      itemList: hidden,
      crackedTiles: crackedTiles,
      timeLimit: timeLimit,
      name: '$id $name',
    );
  }

  LevelData _bossArena(EnemyKind b, int seed, int players) {
    const w = 15, h = 13;
    final Grid grid;
    if (b.style == MoveStyle.bounce) {
      // A big floating boss needs an open arena: walls only.
      grid = Grid(w, h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
            grid.set(x, y, TileType.pillar);
          }
        }
      }
    } else {
      final base = LevelData.generate(
        seed: seed,
        width: w,
        height: h,
        players: players,
        brickDensity: brickDensity,
        enemyMix: const [],
        itemList: const [],
      );
      grid = base.grid;
    }
    final spawns = [
      const GridPos(1, 1),
      const GridPos(w - 2, h - 2),
      const GridPos(w - 2, 1),
      const GridPos(1, h - 2),
    ].take(players).toList();
    return LevelData(
      grid: grid,
      playerSpawns: spawns,
      enemySpawns: [
        EnemySpawn(
          const GridPos(w ~/ 2, h ~/ 2),
          b,
          hp: scaleBossHp(b.hp, players),
        ),
      ],
      timeLimit: timeLimit,
      name: '$id $name',
    );
  }

  /// Rules for the stage. [coop] is false for solo play, where the app
  /// handles lives itself.
  WorldConfig config({required int players, bool coop = true}) => WorldConfig(
        exitHoldSeconds: coop ? 3 : 0,
        requireAllPlayersAtExit: coop,
        ghosts: coop,
        sharedLives: coop ? 3 + players : 0,
        friendlyStun: friendlyStun,
        stalactiteInterval: stalactites,
        bonusStage: bonus,
        bonusKind: bonusKind,
        bonusEnemies: bonus ? scaleCount(8, players) : 0,
        bossStage: isBoss,
      );
}

/// Worlds 1 and 2 of the co-op campaign (Phase 3).
abstract final class Campaign {
  static const _firstSpark = '''
###############
#P.+.+...+.+.P#
#.#+#.#+#.#+#.#
#+..+.e.+e.U..#
#.#.#+#.#+#.#+#
#+.+e..U+..e.+#
#.#+#.#.#+#.#.#
#..+..e.+e.+.+#
#+#.#+#.#E#.#.#
#P.+...+...+.P#
###############
''';

  static const stages = <StageDef>[
    // ---------------------------------------------------- World 1: Meadow
    StageDef(
      id: '1-1',
      name: 'First Spark',
      layout: _firstSpark,
      layoutEnemies: [
        EnemyKind.pebble,
        EnemyKind.pebble,
        EnemyKind.puffball,
        EnemyKind.pebble,
        EnemyKind.pebble,
        EnemyKind.puffball,
      ],
      items: [ItemType.bombUp, ItemType.bombUp],
      friendlyStun: true,
      tip: 'Bomb the bricks, clear the enemies, then meet at the exit.',
    ),
    StageDef(
      id: '1-2',
      name: 'Chain Gang',
      enemies: [(EnemyKind.puffball, 6)],
      items: [ItemType.fireUp, ItemType.fireUp],
      brickDensity: 0.35,
      friendlyStun: true,
      tip: 'A flame that touches a bomb sets it off. Chain them!',
    ),
    StageDef(
      id: '1-3',
      name: 'Drip Drop',
      enemies: [(EnemyKind.puffball, 5), (EnemyKind.blueDrop, 2)],
      items: [ItemType.speedUp],
      brickDensity: 0.38,
      tip: 'Blue Drops chase you when they see you.',
    ),
    StageDef(
      id: '1-4',
      name: 'Kick Off',
      enemies: [(EnemyKind.blueDrop, 4), (EnemyKind.hopper, 3)],
      items: [ItemType.kick],
      brickDensity: 0.4,
      tip: 'Find Kick, then walk into a bomb to send it sliding.',
    ),
    StageDef(
      id: '1-5',
      name: 'Balloon Party',
      bonus: true,
      bonusKind: EnemyKind.puffball,
      items: [
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.speedUp,
        ItemType.mystery,
      ],
      brickDensity: 0.3,
      timeLimit: 60,
      tip: 'Bonus! Pop as many Puffballs as you can in 60 seconds.',
    ),
    StageDef(
      id: '1-6',
      name: 'Rolling Barrels',
      enemies: [(EnemyKind.barrelhop, 4), (EnemyKind.blueDrop, 3)],
      items: [ItemType.bombUp, ItemType.sonar],
      brickDensity: 0.42,
      tip: 'Sonar shows the whole team what hides under nearby bricks.',
    ),
    StageDef(
      id: '1-7',
      name: 'Hop Scotch',
      enemies: [(EnemyKind.hopper, 6), (EnemyKind.barrelhop, 2)],
      items: [ItemType.remote],
      brickDensity: 0.42,
      tip: 'Hoppers squat before they jump. Bomb where they land.',
    ),
    StageDef(
      id: '1-8',
      name: 'Grin and Bear It',
      enemies: [(EnemyKind.grinface, 4), (EnemyKind.puffball, 4)],
      items: [ItemType.fireUp, ItemType.teamBoost],
      brickDensity: 0.44,
      tip: 'Team Boost powers up everyone except whoever grabs it.',
    ),
    StageDef(
      id: '1-9',
      name: 'Meadow Gauntlet',
      enemies: [
        (EnemyKind.grinface, 4),
        (EnemyKind.hopper, 3),
        (EnemyKind.blueDrop, 3),
      ],
      items: [ItemType.heart],
      brickDensity: 0.45,
      tip: 'A Heart takes one hit for you.',
    ),
    StageDef(
      id: '1-10',
      name: 'King Puffball',
      boss: EnemyKind.kingPuffball,
      timeLimit: 180,
      tip: 'He splits when he is hurt. Keep moving!',
    ),

    // --------------------------------------------------- World 2: Caverns
    StageDef(
      id: '2-1',
      name: 'Cave Mouth',
      enemies: [(EnemyKind.barrelhop, 5), (EnemyKind.blueDrop, 3)],
      items: [ItemType.wallPass],
      brickDensity: 0.45,
      timeLimit: 220,
    ),
    StageDef(
      id: '2-2',
      name: 'Seeing Double',
      enemies: [(EnemyKind.splitter, 4), (EnemyKind.puffball, 3)],
      items: [ItemType.fireUp, ItemType.fireUp],
      brickDensity: 0.46,
      timeLimit: 220,
      tip: 'Splitters burst into two. A long blast gets the pieces too.',
    ),
    StageDef(
      id: '2-3',
      name: 'Crumbling Path',
      enemies: [(EnemyKind.splitter, 4), (EnemyKind.hopper, 3)],
      items: [ItemType.frost],
      brickDensity: 0.46,
      crackedTiles: 12,
      stalactites: 9,
      timeLimit: 220,
      tip: 'Cracked floor gives way after two walks. Watch for falling rocks.',
    ),
    StageDef(
      id: '2-4',
      name: 'Ghost Lights',
      enemies: [(EnemyKind.wisp, 4), (EnemyKind.blueDrop, 4)],
      items: [ItemType.bombUp, ItemType.sonar],
      brickDensity: 0.47,
      stalactites: 9,
      timeLimit: 220,
      tip: 'Wisps drift through bricks.',
    ),
    StageDef(
      id: '2-5',
      name: 'Shell Shock',
      bonus: true,
      bonusKind: EnemyKind.shellback,
      items: [
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.speedUp,
        ItemType.fireUp,
        ItemType.kick,
        ItemType.mystery,
      ],
      brickDensity: 0.3,
      timeLimit: 60,
      tip: 'Bonus! Flip Shellbacks from the front, then finish them off.',
    ),
    StageDef(
      id: '2-6',
      name: 'Hard Shells',
      enemies: [
        (EnemyKind.shellback, 3),
        (EnemyKind.wisp, 3),
        (EnemyKind.grinface, 2),
      ],
      items: [ItemType.tether, ItemType.speedUp],
      brickDensity: 0.48,
      stalactites: 9,
      timeLimit: 220,
      tip: 'Tether revives a ghost teammate from 4 tiles away.',
    ),
    StageDef(
      id: '2-7',
      name: 'Sinkholes',
      enemies: [
        (EnemyKind.slimeSage, 3),
        (EnemyKind.splitter, 3),
        (EnemyKind.hopper, 3),
      ],
      items: [ItemType.frost, ItemType.heart],
      brickDensity: 0.48,
      crackedTiles: 18,
      stalactites: 8,
      timeLimit: 220,
      tip: 'Frozen enemies shatter when a normal blast hits them.',
    ),
    StageDef(
      id: '2-8',
      name: 'Sage Advice',
      enemies: [
        (EnemyKind.slimeSage, 3),
        (EnemyKind.shellback, 3),
        (EnemyKind.grinface, 3),
      ],
      items: [ItemType.teamBoost, ItemType.fireUp],
      brickDensity: 0.5,
      stalactites: 8,
      timeLimit: 220,
    ),
    StageDef(
      id: '2-9',
      name: 'Cavern Gauntlet',
      enemies: [
        (EnemyKind.slimeSage, 2),
        (EnemyKind.wisp, 3),
        (EnemyKind.shellback, 3),
        (EnemyKind.splitter, 3),
      ],
      items: [ItemType.heart, ItemType.bombUp, ItemType.tether],
      brickDensity: 0.5,
      stalactites: 7,
      timeLimit: 220,
    ),
    StageDef(
      id: '2-10',
      name: 'Rockjaw Worm',
      boss: EnemyKind.rockjaw,
      brickDensity: 0.15,
      timeLimit: 180,
      tip: 'Dust and rumble mark where it surfaces. Have a bomb waiting.',
    ),
  ];

  static StageDef? byId(String id) {
    for (final s in stages) {
      if (s.id == id) return s;
    }
    return null;
  }

  static StageDef get first => stages.first;

  /// The stage after [id], or null at the end of the campaign.
  static StageDef? next(String id) {
    final i = stages.indexWhere((s) => s.id == id);
    return i < 0 || i + 1 >= stages.length ? null : stages[i + 1];
  }
}
