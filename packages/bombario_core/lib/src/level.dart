import 'dart:collection';
import 'dart:math';

import 'direction.dart';
import 'entities.dart';
import 'grid.dart';

/// Where an enemy starts.
class EnemySpawn {
  const EnemySpawn(this.pos, this.kind, {this.hp});
  final GridPos pos;
  final EnemyKind kind;

  /// Overrides the kind's HP (bosses scale with the player count).
  final int? hp;
}

/// Everything needed to start a stage.
class LevelData {
  LevelData({
    required this.grid,
    required this.playerSpawns,
    required this.enemySpawns,
    this.timeLimit = 200,
    this.name = '',
  });

  final Grid grid;
  final List<GridPos> playerSpawns;
  final List<EnemySpawn> enemySpawns;
  final double timeLimit;
  final String name;

  /// Where the exit is hidden, or null (boss and bonus stages).
  GridPos? get exit {
    for (final p in grid.positions) {
      if (grid.hiddenAt(p.x, p.y) == ItemType.exit) return p;
    }
    return null;
  }

  /// §8.4 step 6: every spawn can reach the exit once bricks are gone.
  /// Pits block; closed gates count as open only if a pressure plate is
  /// reachable without them. Stages without an exit are trivially solvable.
  bool get solvable {
    final target = exit;
    if (target == null) return true;
    for (final s in playerSpawns) {
      var reach = _reach(s, gatesOpen: false);
      final plate =
          reach.any((p) => grid.featureAt(p.x, p.y) == TileFeature.plate);
      if (plate) reach = _reach(s, gatesOpen: true);
      if (!reach.contains(target)) return false;
    }
    return true;
  }

  Set<GridPos> _reach(GridPos from, {required bool gatesOpen}) {
    bool open(GridPos p) {
      final t = grid.atPos(p);
      if (t == TileType.pit) return false;
      if (t == TileType.pillar) {
        return gatesOpen && grid.featureAt(p.x, p.y) == TileFeature.gate;
      }
      return true;
    }

    final seen = {from};
    final queue = Queue<GridPos>()..add(from);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      for (final d in Direction.cardinal) {
        final n = cur.step(d.dx, d.dy);
        if (grid.inBounds(n.x, n.y) && open(n) && seen.add(n)) queue.add(n);
      }
    }
    return seen;
  }

  /// Parses the ASCII format used in the design document.
  ///
  /// `#` pillar, `+` brick, `.` floor, `P` player spawn, `E` exit hidden under
  /// a brick, `U` power-up hidden under a brick, `~` cracked floor, `e` enemy
  /// spawn (kind taken from [enemyKinds] in order, cycling).
  ///
  /// Worlds 3-5 add: `>` `<` `^` `v` conveyors, `V` steam vent, `G` gate,
  /// `_` pressure plate, `p` pressure plate under a brick, `R` possessed
  /// brick, `W` warp door, `i` ice, `N` Mole Queen nest under a brick.
  ///
  /// [items] lists which power-ups go under the `U` tiles, in reading order
  /// (cycled if there are more `U`s than items).
  static LevelData parse(
    String ascii, {
    List<ItemType> items = const [ItemType.bombUp, ItemType.fireUp],
    List<EnemyKind> enemyKinds = const [EnemyKind.puffball],
    double timeLimit = 200,
    String name = '',
  }) {
    final rows = ascii
        .split('\n')
        .map((r) => r.trimRight())
        .where((r) => r.isNotEmpty)
        .toList();
    final height = rows.length;
    final width = rows.map((r) => r.length).reduce(max);
    final grid = Grid(width, height);
    final players = <GridPos>[];
    final enemies = <EnemySpawn>[];
    var itemIndex = 0;
    var enemyIndex = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = x < rows[y].length ? rows[y][x] : '#';
        switch (c) {
          case '#':
            grid.set(x, y, TileType.pillar);
          case '+':
            grid.set(x, y, TileType.brick);
          case '~':
            grid.set(x, y, TileType.cracked);
          case 'E':
            grid.set(x, y, TileType.brick);
            grid.hide(x, y, ItemType.exit);
          case 'U':
            grid.set(x, y, TileType.brick);
            grid.hide(x, y, items[itemIndex++ % items.length]);
          case 'P':
            players.add(GridPos(x, y));
          case 'e':
            enemies.add(EnemySpawn(
              GridPos(x, y),
              enemyKinds[enemyIndex++ % enemyKinds.length],
            ));
          case '>':
            grid.setFeature(x, y, TileFeature.conveyorRight);
          case '<':
            grid.setFeature(x, y, TileFeature.conveyorLeft);
          case '^':
            grid.setFeature(x, y, TileFeature.conveyorUp);
          case 'v':
            grid.setFeature(x, y, TileFeature.conveyorDown);
          case 'V':
            grid.setFeature(x, y, TileFeature.vent);
          case 'G':
            grid.set(x, y, TileType.pillar);
            grid.setFeature(x, y, TileFeature.gate);
          case '_':
            grid.setFeature(x, y, TileFeature.plate);
          case 'p':
            grid.set(x, y, TileType.brick);
            grid.setFeature(x, y, TileFeature.plate);
          case 'R':
            grid.set(x, y, TileType.brick);
            grid.setFeature(x, y, TileFeature.possessed);
          case 'W':
            grid.setFeature(x, y, TileFeature.warp);
          case 'i':
            grid.setFeature(x, y, TileFeature.ice);
          case 'N':
            grid.set(x, y, TileType.brick);
            enemies.add(EnemySpawn(GridPos(x, y), EnemyKind.moleNest));
          default:
            break; // floor
        }
      }
    }
    return LevelData(
      grid: grid,
      playerSpawns: players,
      enemySpawns: enemies,
      timeLimit: timeLimit,
      name: name,
    );
  }

  /// Seeded random classic stage, following §8.4 of the design doc:
  /// pillar grid, safe zones at spawns, bricks to a target density, exit far
  /// from the spawns, one power-up per player, enemies away from spawns.
  ///
  /// World 3-5 terrain: [conveyors] belt runs, [vents], [iceTiles] (in
  /// patches), [warpPairs] and a [possessed] fraction of bricks. Mole Queen
  /// nests in [enemyMix] are buried under bricks.
  ///
  /// The result is validated with [solvable]; an unsolvable roll is
  /// regenerated from the next seed.
  static LevelData generate({
    required int seed,
    int width = 31,
    int height = 13,
    int players = 1,
    double brickDensity = 0.4,
    int enemyCount = 6,
    List<EnemyKind> enemyKinds = const [EnemyKind.puffball],
    List<ItemType> items = const [
      ItemType.bombUp,
      ItemType.fireUp,
      ItemType.speedUp
    ],
    double timeLimit = 200,
    List<EnemyKind>? enemyMix,
    List<ItemType>? itemList,
    int crackedTiles = 0,
    int conveyors = 0,
    int vents = 0,
    int iceTiles = 0,
    int warpPairs = 0,
    double possessed = 0,
    String name = '',
  }) {
    late LevelData level;
    for (var attempt = 0; attempt < 20; attempt++) {
      level = _generate(
        seed: seed + attempt * 7919,
        width: width,
        height: height,
        players: players,
        brickDensity: brickDensity,
        enemyCount: enemyCount,
        enemyKinds: enemyKinds,
        items: items,
        timeLimit: timeLimit,
        enemyMix: enemyMix,
        itemList: itemList,
        crackedTiles: crackedTiles,
        conveyors: conveyors,
        vents: vents,
        iceTiles: iceTiles,
        warpPairs: warpPairs,
        possessed: possessed,
        name: name.isEmpty ? 'Random #$seed' : name,
      );
      if (level.solvable) break;
    }
    return level;
  }

  static LevelData _generate({
    required int seed,
    int width = 31,
    int height = 13,
    int players = 1,
    double brickDensity = 0.4,
    int enemyCount = 6,
    List<EnemyKind> enemyKinds = const [EnemyKind.puffball],
    List<ItemType> items = const [
      ItemType.bombUp,
      ItemType.fireUp,
      ItemType.speedUp
    ],
    double timeLimit = 200,

    /// Exact enemies to place, overriding [enemyCount] and [enemyKinds].
    List<EnemyKind>? enemyMix,

    /// Exact power-ups to hide, overriding the one-per-player rule.
    List<ItemType>? itemList,

    /// Floor tiles turned into cracked floor (World 2).
    int crackedTiles = 0,
    int conveyors = 0,
    int vents = 0,
    int iceTiles = 0,
    int warpPairs = 0,
    double possessed = 0,
    String name = '',
  }) {
    assert(width.isOdd && height.isOdd, 'classic layouts need odd sizes');
    final rng = Random(seed);
    final grid = Grid.classicLayout(width, height);

    final corners = [
      GridPos(1, 1),
      GridPos(width - 2, height - 2),
      GridPos(width - 2, 1),
      GridPos(1, height - 2),
    ];
    final spawns = corners.take(players.clamp(1, 4)).toList();

    bool inSafeZone(int x, int y) => spawns.any(
          (s) => (s.x - x).abs() + (s.y - y).abs() <= 2,
        );

    final free = <GridPos>[];
    for (final p in grid.positions) {
      if (grid.atPos(p) != TileType.floor) continue;
      if (inSafeZone(p.x, p.y)) continue;
      free.add(p);
    }

    free.shuffle(rng);
    final brickCount = (free.length * brickDensity).round();
    final bricks = free.take(brickCount).toList();
    for (final b in bricks) {
      grid.set(b.x, b.y, TileType.brick);
    }

    // Exit: the brick furthest (manhattan) from the average spawn.
    final avgX = spawns.map((s) => s.x).reduce((a, b) => a + b) / spawns.length;
    final avgY = spawns.map((s) => s.y).reduce((a, b) => a + b) / spawns.length;
    bricks.sort((a, b) {
      final da = (a.x - avgX).abs() + (a.y - avgY).abs();
      final db = (b.x - avgX).abs() + (b.y - avgY).abs();
      return db.compareTo(da);
    });
    if (bricks.isNotEmpty) {
      // Pick among the farthest 20% so it isn't always the same corner.
      final pool = bricks.take(max(1, bricks.length ~/ 5)).toList();
      final exit = pool[rng.nextInt(pool.length)];
      grid.hide(exit.x, exit.y, ItemType.exit);
      bricks.remove(exit);
    }

    // One power-up per player plus one shared, unless the stage says.
    final hiddenItems = itemList ??
        [
          for (var i = 0; i < players + 1; i++)
            items[rng.nextInt(items.length)],
        ];
    for (final item in hiddenItems) {
      if (bricks.isEmpty) break;
      final b = bricks[rng.nextInt(bricks.length)];
      bricks.remove(b);
      grid.hide(b.x, b.y, item);
    }

    // Enemies on floor tiles at least 4 tiles from every spawn.
    final enemyTiles = free
        .skip(brickCount)
        .where((p) => spawns.every((s) => s.manhattanTo(p) >= 4))
        .toList();
    final mix = enemyMix ??
        [
          for (var i = 0; i < enemyCount; i++)
            enemyKinds[rng.nextInt(enemyKinds.length)],
        ];
    final enemies = <EnemySpawn>[];
    for (final kind in mix) {
      if (kind.ability == EnemyAbility.nest) {
        // Nests hide under plain bricks, away from the spawns.
        final spots = bricks
            .where((b) => spawns.every((s) => s.manhattanTo(b) >= 4))
            .toList();
        if (spots.isNotEmpty) {
          final b = spots[rng.nextInt(spots.length)];
          bricks.remove(b);
          enemies.add(EnemySpawn(b, kind));
          continue;
        }
      }
      if (enemyTiles.isEmpty) break;
      final p = enemyTiles.removeAt(rng.nextInt(enemyTiles.length));
      enemies.add(EnemySpawn(p, kind));
    }

    // ---- World 3-5 terrain, on tiles away from the spawns.
    final open = [
      for (final p in grid.positions)
        if (grid.atPos(p) != TileType.pillar &&
            spawns.every((s) => s.manhattanTo(p) >= 3))
          p,
    ];
    bool bare(GridPos p) => grid.featureAt(p.x, p.y) == TileFeature.none;
    GridPos? pick() {
      final options = open.where(bare).toList();
      return options.isEmpty ? null : options[rng.nextInt(options.length)];
    }

    for (var i = 0; i < conveyors; i++) {
      final start = pick();
      if (start == null) break;
      // Belts run along a lane: horizontal on odd rows, else vertical.
      final horizontal = start.y.isOdd;
      final dir = horizontal
          ? (rng.nextBool() ? Direction.right : Direction.left)
          : (rng.nextBool() ? Direction.down : Direction.up);
      final length = 3 + rng.nextInt(3);
      var t = start;
      for (var k = 0; k < length; k++) {
        if (!open.contains(t) || !bare(t)) break;
        grid.setFeature(t.x, t.y, TileFeature.conveyorFor(dir));
        t = t.step(dir.dx, dir.dy);
      }
    }
    for (var i = 0; i < vents; i++) {
      final v = pick();
      if (v == null) break;
      grid.setFeature(v.x, v.y, TileFeature.vent);
    }
    var ice = iceTiles;
    while (ice > 0) {
      final centre = pick();
      if (centre == null) break;
      for (final p in [
        centre,
        for (final d in Direction.cardinal) centre.step(d.dx, d.dy),
      ]) {
        if (ice > 0 && open.contains(p) && bare(p)) {
          grid.setFeature(p.x, p.y, TileFeature.ice);
          ice--;
        }
      }
    }
    for (var i = 0; i < warpPairs; i++) {
      final a = pick();
      if (a == null) break;
      final far = open
          .where((p) => bare(p) && p != a && p.manhattanTo(a) >= 10)
          .toList();
      if (far.isEmpty) break;
      final b = far[rng.nextInt(far.length)];
      for (final w in [a, b]) {
        // Doors stand on open floor so they can be seen from the start.
        if (grid.atPos(w) == TileType.brick &&
            grid.hiddenAt(w.x, w.y) == null) {
          grid.set(w.x, w.y, TileType.floor);
        }
        grid.setFeature(w.x, w.y, TileFeature.warp);
      }
    }
    if (possessed > 0) {
      final all = [
        for (final p in grid.positions)
          if (grid.atPos(p) == TileType.brick && bare(p)) p,
      ]..shuffle(rng);
      for (final b in all.take((all.length * possessed).round())) {
        grid.setFeature(b.x, b.y, TileFeature.possessed);
      }
    }

    // Cracked floor on open tiles away from spawns.
    for (var i = 0; i < crackedTiles && enemyTiles.isNotEmpty; i++) {
      final p = enemyTiles.removeAt(rng.nextInt(enemyTiles.length));
      grid.set(p.x, p.y, TileType.cracked);
    }

    return LevelData(
      grid: grid,
      playerSpawns: spawns,
      enemySpawns: enemies,
      timeLimit: timeLimit,
      name: name,
    );
  }
}
