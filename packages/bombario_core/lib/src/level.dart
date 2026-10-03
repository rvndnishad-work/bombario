import 'dart:math';

import 'entities.dart';
import 'grid.dart';

/// Where an enemy starts.
class EnemySpawn {
  const EnemySpawn(this.pos, this.kind);
  final GridPos pos;
  final EnemyKind kind;
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

  /// Parses the ASCII format used in the design document.
  ///
  /// `#` pillar, `+` brick, `.` floor, `P` player spawn, `E` exit hidden under
  /// a brick, `U` power-up hidden under a brick, `e` enemy spawn
  /// (kind taken from [enemyKinds] in order, cycling).
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

    // One power-up per player plus one shared.
    final itemCount = min(bricks.length, players + 1);
    for (var i = 0; i < itemCount; i++) {
      final b = bricks[rng.nextInt(bricks.length)];
      bricks.remove(b);
      grid.hide(b.x, b.y, items[rng.nextInt(items.length)]);
    }

    // Enemies on floor tiles at least 4 tiles from every spawn.
    final enemyTiles = free
        .skip(brickCount)
        .where((p) => spawns.every((s) => s.manhattanTo(p) >= 4))
        .toList();
    final enemies = <EnemySpawn>[];
    for (var i = 0; i < enemyCount && enemyTiles.isNotEmpty; i++) {
      final p = enemyTiles.removeAt(rng.nextInt(enemyTiles.length));
      enemies.add(EnemySpawn(p, enemyKinds[rng.nextInt(enemyKinds.length)]));
    }

    return LevelData(
      grid: grid,
      playerSpawns: spawns,
      enemySpawns: enemies,
      timeLimit: timeLimit,
      name: 'Random #$seed',
    );
  }
}
