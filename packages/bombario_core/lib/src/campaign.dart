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
    this.conveyors = 0,
    this.vents = 0,
    this.ventInterval = 5,
    this.iceTiles = 0,
    this.warpPairs = 0,
    this.possessed = 0,
    this.darkness = 0,
    this.wind = 0,
    this.cannons = 0,
    this.big = false,
    this.theme,
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

  // ---- World 3-5 terrain (§8.1). Counts are for generated stages.
  /// Conveyor belt runs.
  final int conveyors;

  /// Steam vents, and the seconds per vent cycle.
  final int vents;
  final double ventInterval;
  final int iceTiles;
  final int warpPairs;

  /// Fraction of bricks that are possessed (grow back after 20 s).
  final double possessed;

  /// Vision radius on dark stages, 0 when lit.
  final int darkness;

  /// Seconds per wind gust, 0 for calm.
  final double wind;

  /// Seconds between cannon shots, 0 for none.
  final double cannons;

  /// Always the large 41 × 17 field, whatever the team size.
  final bool big;

  /// The world whose look and music a stage outside the campaign borrows
  /// (the Daily Dungeon).
  final int? theme;

  int get world => theme ?? int.parse(id.split('-').first);
  int get number => int.tryParse(id.split('-').last) ?? 0;
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
        bonus ? l : _onePowerUpEach(l, n),
        items: items.isEmpty ? const [ItemType.bombUp] : items,
        enemyKinds:
            layoutEnemies.isEmpty ? const [EnemyKind.puffball] : layoutEnemies,
        timeLimit: timeLimit,
        name: '$id $name',
      );
    }
    final rng = Random(seed);
    const basics = [ItemType.bombUp, ItemType.fireUp, ItemType.speedUp];
    // One power-up per player, as in the original's one per stage (bonus
    // stages are a power-up party); the exit is hidden separately.
    final hidden = bonus
        ? items
        : [
            ...items.take(n),
            for (var i = items.length; i < n; i++)
              basics[rng.nextInt(basics.length)],
          ];
    final mix = bonus
        ? <EnemyKind>[]
        : [
            for (final (kind, count) in enemies)
              for (var i = 0; i < scaleCount(count, n); i++) kind,
          ];
    final large = big || n > 2;
    return LevelData.generate(
      seed: seed,
      width: large ? 41 : 31,
      height: large ? 17 : 13,
      players: n,
      brickDensity: brickDensity,
      enemyMix: mix,
      itemList: hidden,
      crackedTiles: crackedTiles,
      conveyors: conveyors,
      vents: vents,
      iceTiles: iceTiles,
      warpPairs: warpPairs,
      possessed: possessed,
      timeLimit: timeLimit,
      name: '$id $name',
    );
  }

  /// Keeps the first [players] power-up bricks (`U`) of a hand-made layout
  /// and turns the rest into plain bricks.
  static String _onePowerUpEach(String layout, int players) {
    var kept = 0;
    return layout.replaceAllMapped(
      'U',
      (_) => kept++ < players ? 'U' : '+',
    );
  }

  LevelData _bossArena(EnemyKind b, int seed, int players) {
    const w = 15, h = 13;
    final Grid grid;
    if (b.style == MoveStyle.bounce || b.style == MoveStyle.stationary) {
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
    // Power-ups for the fight sit under bricks near the spawns.
    const stash = [
      GridPos(3, 3),
      GridPos(w - 4, h - 4),
      GridPos(w - 4, 3),
      GridPos(3, h - 4),
    ];
    for (var i = 0; i < items.length && i < stash.length; i++) {
      final s = stash[i];
      grid.set(s.x, s.y, TileType.brick);
      grid.hide(s.x, s.y, items[i]);
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
        exitGuardCount: scaleCount(4, players),
        ventInterval:
            vents > 0 || layout?.contains('V') == true ? ventInterval : 0,
        darkness: darkness,
        windInterval: wind,
        cannonInterval: cannons,
        keepItemsOnDeath: !coop,
      );
}

/// The co-op campaign: five worlds of ten stages (§8.2).
abstract final class Campaign {
  /// 3-3 "Assembly Line" from §8.3: conveyors carry kicked bombs, and the
  /// power-up room opens when someone finds the plate under a brick.
  static const _assemblyLine = '''
#####################
#P.+.+..>>>>>..+.+.P#
#.#+#.#+#.#.#+#.#+#.#
#+..+..V+.e.+...+..+#
#.#.#+#.#####.#+#.#.#
#+.+..+.#.U.#.+..p.+#
#.#+#.#.#GGG#.#.#+#.#
#..e.+..+...+..+.e..#
#.#.#+#.#+#.#+#.#.#.#
#P.+.<<<<<..+.E+.+.P#
#####################
''';

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
      // Fire first, as in the original's stage 1: longer flames are the
      // power-up you feel straight away.
      items: [ItemType.fireUp, ItemType.bombUp],
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

    // --------------------------------------------------- World 3: Factory
    StageDef(
      id: '3-1',
      name: 'Rust Belt',
      enemies: [(EnemyKind.mimic, 4), (EnemyKind.barrelhop, 3)],
      items: [ItemType.sonar, ItemType.bombUp],
      brickDensity: 0.5,
      conveyors: 3,
      timeLimit: 210,
      tip: 'Some power-ups shimmer. Those ones bite. Sonar shows Mimics.',
    ),
    StageDef(
      id: '3-2',
      name: 'Steam Works',
      enemies: [
        (EnemyKind.mimic, 3),
        (EnemyKind.grinface, 3),
        (EnemyKind.splitter, 2),
      ],
      items: [ItemType.fireUp, ItemType.kick],
      brickDensity: 0.5,
      conveyors: 2,
      vents: 4,
      timeLimit: 210,
      tip: 'Vents hiss before they blast. Conveyors carry you and your bombs.',
    ),
    StageDef(
      id: '3-3',
      name: 'Assembly Line',
      layout: _assemblyLine,
      layoutEnemies: [
        EnemyKind.grinface,
        EnemyKind.mimic,
        EnemyKind.splitter,
      ],
      items: [ItemType.kick],
      ventInterval: 5,
      timeLimit: 210,
      tip: 'A pressure plate hides under a brick. It opens the locked room.',
    ),
    StageDef(
      id: '3-4',
      name: 'Goblin Workshop',
      enemies: [
        (EnemyKind.bombGoblin, 4),
        (EnemyKind.shellback, 2),
        (EnemyKind.mimic, 2),
      ],
      items: [ItemType.bombPass, ItemType.fireUp],
      brickDensity: 0.52,
      conveyors: 2,
      vents: 3,
      timeLimit: 210,
      tip: 'Bomb Goblins plant bombs and run. Their bombs chain yours.',
    ),
    StageDef(
      id: '3-5',
      name: 'Treasure Trove',
      bonus: true,
      bonusKind: EnemyKind.mimic,
      items: [
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.speedUp,
        ItemType.fireUp,
        ItemType.remote,
        ItemType.mystery,
      ],
      brickDensity: 0.3,
      conveyors: 3,
      timeLimit: 60,
      tip: 'Bonus! Every shiny thing is a Mimic. Bomb as many as you can.',
    ),
    StageDef(
      id: '3-6',
      name: 'Hot Pipes',
      enemies: [
        (EnemyKind.bombGoblin, 3),
        (EnemyKind.tigerclaw, 2),
        (EnemyKind.splitter, 3),
      ],
      items: [ItemType.remote, ItemType.heart],
      brickDensity: 0.52,
      conveyors: 3,
      vents: 6,
      ventInterval: 4,
      timeLimit: 210,
      tip: 'Tigerclaws hunt you down and step around your bombs.',
    ),
    StageDef(
      id: '3-7',
      name: 'Crab Line',
      enemies: [
        (EnemyKind.kickerCrab, 4),
        (EnemyKind.bombGoblin, 2),
        (EnemyKind.mimic, 2),
      ],
      items: [ItemType.remote, ItemType.fireUp],
      brickDensity: 0.53,
      conveyors: 4,
      vents: 3,
      timeLimit: 210,
      tip: 'Kicker Crabs boot bombs back at you. Remote bombs beat them.',
    ),
    StageDef(
      id: '3-8',
      name: 'Overtime',
      enemies: [
        (EnemyKind.tigerclaw, 3),
        (EnemyKind.kickerCrab, 3),
        (EnemyKind.shellback, 2),
      ],
      items: [ItemType.teamBoost, ItemType.bombUp],
      brickDensity: 0.54,
      conveyors: 3,
      vents: 5,
      timeLimit: 210,
    ),
    StageDef(
      id: '3-9',
      name: 'Factory Gauntlet',
      enemies: [
        (EnemyKind.tigerclaw, 3),
        (EnemyKind.kickerCrab, 3),
        (EnemyKind.bombGoblin, 3),
        (EnemyKind.mimic, 2),
      ],
      items: [ItemType.heart, ItemType.tether, ItemType.fireUp],
      brickDensity: 0.55,
      conveyors: 4,
      vents: 6,
      ventInterval: 4,
      timeLimit: 210,
    ),
    StageDef(
      id: '3-10',
      name: 'Bomb-O-Tron',
      boss: EnemyKind.bombOTron,
      items: [ItemType.kick, ItemType.kick],
      timeLimit: 180,
      tip: 'Its core opens after each volley. Kick its bombs back at it!',
    ),

    // --------------------------------------------- World 4: Haunted Manor
    StageDef(
      id: '4-1',
      name: 'Lights Out',
      enemies: [(EnemyKind.shade, 4), (EnemyKind.wisp, 3)],
      items: [ItemType.sonar, ItemType.bombUp],
      brickDensity: 0.55,
      darkness: 4,
      possessed: 0.15,
      warpPairs: 1,
      timeLimit: 200,
      tip: 'Shades are invisible until they are close. Flames light them up.',
    ),
    StageDef(
      id: '4-2',
      name: 'Creaky Halls',
      enemies: [
        (EnemyKind.shade, 4),
        (EnemyKind.slimeSage, 2),
        (EnemyKind.mimic, 2),
      ],
      items: [ItemType.flamePass, ItemType.fireUp],
      brickDensity: 0.56,
      darkness: 4,
      possessed: 0.2,
      warpPairs: 1,
      timeLimit: 200,
      tip: 'Possessed bricks grow back. Warp doors come in pairs.',
    ),
    StageDef(
      id: '4-3',
      name: 'The Nursery',
      enemies: [
        (EnemyKind.moleNest, 2),
        (EnemyKind.shade, 3),
        (EnemyKind.wisp, 2),
      ],
      items: [ItemType.frost, ItemType.bombUp],
      brickDensity: 0.57,
      darkness: 4,
      possessed: 0.2,
      warpPairs: 2,
      timeLimit: 200,
      tip: 'Pebbles keep coming from nests under the bricks. Find them first.',
    ),
    StageDef(
      id: '4-4',
      name: 'Hall of Doors',
      enemies: [
        (EnemyKind.shade, 4),
        (EnemyKind.tigerclaw, 2),
        (EnemyKind.moleNest, 1),
      ],
      items: [ItemType.tether, ItemType.sonar],
      brickDensity: 0.57,
      darkness: 4,
      possessed: 0.2,
      warpPairs: 3,
      timeLimit: 200,
    ),
    StageDef(
      id: '4-5',
      name: 'Shade Hunt',
      bonus: true,
      bonusKind: EnemyKind.shade,
      items: [
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.fireUp,
        ItemType.speedUp,
        ItemType.sonar,
        ItemType.mystery,
      ],
      brickDensity: 0.3,
      darkness: 4,
      timeLimit: 60,
      tip: 'Bonus! Catch Shades in the dark. Explosions light the way.',
    ),
    StageDef(
      id: '4-6',
      name: 'Mirror Gallery',
      enemies: [
        (EnemyKind.mirrorKnight, 3),
        (EnemyKind.shade, 3),
        (EnemyKind.moleNest, 1),
      ],
      items: [ItemType.fireUp, ItemType.heart],
      brickDensity: 0.58,
      darkness: 4,
      possessed: 0.25,
      warpPairs: 2,
      timeLimit: 200,
      tip: 'Mirror Knights copy you, left and right swapped. Lead them in.',
    ),
    StageDef(
      id: '4-7',
      name: 'Haunted Library',
      enemies: [
        (EnemyKind.mirrorKnight, 3),
        (EnemyKind.shellback, 3),
        (EnemyKind.shade, 3),
      ],
      items: [ItemType.remote, ItemType.frost],
      brickDensity: 0.58,
      darkness: 4,
      possessed: 0.25,
      warpPairs: 2,
      timeLimit: 200,
    ),
    StageDef(
      id: '4-8',
      name: 'Ballroom',
      enemies: [
        (EnemyKind.mirrorKnight, 3),
        (EnemyKind.tigerclaw, 3),
        (EnemyKind.moleNest, 2),
      ],
      items: [ItemType.teamBoost, ItemType.flamePass],
      brickDensity: 0.6,
      darkness: 4,
      possessed: 0.25,
      warpPairs: 2,
      timeLimit: 200,
    ),
    StageDef(
      id: '4-9',
      name: 'Manor Gauntlet',
      enemies: [
        (EnemyKind.mirrorKnight, 3),
        (EnemyKind.shade, 4),
        (EnemyKind.moleNest, 2),
        (EnemyKind.tigerclaw, 2),
      ],
      items: [ItemType.heart, ItemType.tether, ItemType.sonar],
      brickDensity: 0.6,
      darkness: 4,
      possessed: 0.3,
      warpPairs: 3,
      timeLimit: 200,
    ),
    StageDef(
      id: '4-10',
      name: 'The Lantern Witch',
      boss: EnemyKind.lanternWitch,
      items: [ItemType.fireUp, ItemType.bombUp],
      brickDensity: 0.15,
      darkness: 4,
      timeLimit: 180,
      tip: 'If she curses a friend, bomb the Curse Orb to set them free.',
    ),

    // ---------------------------------------------- World 5: Sky Fortress
    StageDef(
      id: '5-1',
      name: 'Cloud Steps',
      enemies: [(EnemyKind.fuseEater, 4), (EnemyKind.grinface, 3)],
      items: [ItemType.remote, ItemType.speedUp],
      brickDensity: 0.6,
      iceTiles: 8,
      wind: 8,
      timeLimit: 180,
      tip: 'Fuse Eaters swallow bombs. Blow them up mid-meal with Remote.',
    ),
    StageDef(
      id: '5-2',
      name: 'Updraft',
      enemies: [(EnemyKind.fuseEater, 3), (EnemyKind.tigerclaw, 3)],
      items: [ItemType.bombUp, ItemType.kick],
      brickDensity: 0.6,
      iceTiles: 10,
      wind: 8,
      cannons: 12,
      timeLimit: 180,
      tip: 'Walking into the wind is slow. Cannons mark their row first.',
    ),
    StageDef(
      id: '5-3',
      name: 'Frozen Ramparts',
      enemies: [
        (EnemyKind.fuseEater, 3),
        (EnemyKind.mirrorKnight, 2),
        (EnemyKind.splitter, 3),
      ],
      items: [ItemType.frost, ItemType.fireUp],
      brickDensity: 0.61,
      iceTiles: 16,
      cannons: 12,
      timeLimit: 180,
      tip: 'On ice you keep sliding until something stops you.',
    ),
    StageDef(
      id: '5-4',
      name: 'Wraith Watch',
      enemies: [(EnemyKind.phaseWraith, 3), (EnemyKind.fuseEater, 3)],
      items: [ItemType.flamePass, ItemType.heart],
      brickDensity: 0.62,
      iceTiles: 10,
      wind: 8,
      cannons: 11,
      timeLimit: 180,
      tip: 'Phase Wraiths flicker before they teleport next to you.',
    ),
    StageDef(
      id: '5-5',
      name: 'Snack Time',
      bonus: true,
      bonusKind: EnemyKind.fuseEater,
      items: [
        ItemType.bombUp,
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.remote,
        ItemType.speedUp,
        ItemType.mystery,
      ],
      brickDensity: 0.3,
      wind: 8,
      timeLimit: 60,
      tip: 'Bonus! Feed the Fuse Eaters... remote bombs.',
    ),
    StageDef(
      id: '5-6',
      name: 'The Herd',
      enemies: [
        (EnemyKind.herder, 1),
        (EnemyKind.phaseWraith, 2),
        (EnemyKind.grinface, 4),
        (EnemyKind.tigerclaw, 2),
      ],
      items: [ItemType.teamBoost, ItemType.fireUp],
      brickDensity: 0.62,
      iceTiles: 10,
      wind: 8,
      cannons: 10,
      timeLimit: 180,
      tip: 'The Herder speeds up everything near it. Take it out first.',
    ),
    StageDef(
      id: '5-7',
      name: 'Gale Gauntlet',
      enemies: [
        (EnemyKind.herder, 2),
        (EnemyKind.tigerclaw, 3),
        (EnemyKind.phaseWraith, 2),
        (EnemyKind.fuseEater, 3),
        (EnemyKind.kickerCrab, 2),
      ],
      items: [ItemType.heart, ItemType.remote, ItemType.bombUp],
      brickDensity: 0.65,
      possessed: 0.1,
      iceTiles: 8,
      wind: 8,
      cannons: 10,
      big: true,
      timeLimit: 120,
      tip: 'Split up: some of you keep the Herders busy, the rest dig.',
    ),
    StageDef(
      id: '5-8',
      name: "Hunter's Moon",
      enemies: [
        (EnemyKind.hunterCoin, 1),
        (EnemyKind.phaseWraith, 3),
        (EnemyKind.herder, 1),
        (EnemyKind.mirrorKnight, 2),
      ],
      items: [ItemType.heart, ItemType.tether],
      brickDensity: 0.64,
      iceTiles: 12,
      wind: 8,
      cannons: 9,
      timeLimit: 180,
    ),
    StageDef(
      id: '5-9',
      name: 'Sky Gauntlet',
      enemies: [
        (EnemyKind.hunterCoin, 1),
        (EnemyKind.herder, 2),
        (EnemyKind.phaseWraith, 3),
        (EnemyKind.fuseEater, 2),
        (EnemyKind.tigerclaw, 2),
      ],
      items: [ItemType.heart, ItemType.remote, ItemType.sonar],
      brickDensity: 0.65,
      iceTiles: 12,
      wind: 8,
      cannons: 9,
      timeLimit: 180,
    ),
    StageDef(
      id: '5-10',
      name: 'Overlord Pontan',
      boss: EnemyKind.overlordPontan,
      items: [ItemType.bombUp, ItemType.fireUp],
      timeLimit: 180,
      tip: 'He copies your power-ups. When he is hurt, the walls close in.',
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
