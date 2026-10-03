import 'direction.dart';
import 'entities.dart';

/// What a tile is made of. Hidden items live on the tile alongside a brick.
enum TileType {
  floor,
  pillar, // indestructible
  brick, // destructible

  /// Walkable, but collapses into a [pit] after two walk-overs (World 2).
  cracked,

  /// A collapsed floor: nobody walks here, but flames pass over it.
  pit,
}

/// A second layer on top of [TileType] for the World 3-5 mechanics (§8.1).
///
/// Kept separate from [TileType] so a tile can be, say, a brick with a
/// conveyor under it, and so older renderers that only know the base tiles
/// still draw something sensible (a closed gate is a pillar underneath).
///
/// Serialised by index (snapshot character), so new values go at the end.
enum TileFeature {
  none,

  /// Conveyor belts move players and still bombs one way (World 3).
  conveyorUp,
  conveyorDown,
  conveyorLeft,
  conveyorRight,

  /// Fires a short flame jet on a timer, telegraphed (World 3).
  vent,

  /// Stepping on it opens every [gate] for good (World 3).
  plate,

  /// Solid ([TileType.pillar]) until a [plate] is pressed, then floor.
  gate,

  /// A brick that grows back 20 s after it is destroyed (World 4).
  possessed,

  /// Warp door: entering one moves you to its partner. Doors pair up in
  /// reading order: 1st with 2nd, 3rd with 4th... (World 4).
  warp,

  /// Players keep sliding on ice until they hit something (World 5).
  ice,

  /// Warp pipes (after Mario's), named for the way the mouth faces. A pipe
  /// juts out of the wall behind it and is solid; walk into its mouth to
  /// go in, and you slide out of another pipe's mouth, picked at random.
  pipeUp,
  pipeDown,
  pipeLeft,
  pipeRight;

  bool get isPipe => pipeMouth != Direction.none;

  /// The way a pipe's mouth faces, and the way you walk out of it.
  Direction get pipeMouth => switch (this) {
        pipeUp => Direction.up,
        pipeDown => Direction.down,
        pipeLeft => Direction.left,
        pipeRight => Direction.right,
        _ => Direction.none,
      };

  static TileFeature pipeFacing(Direction mouth) => switch (mouth) {
        Direction.up => pipeUp,
        Direction.down => pipeDown,
        Direction.left => pipeLeft,
        Direction.right => pipeRight,
        Direction.none => none,
      };

  /// The way a conveyor runs, [Direction.none] for anything else.
  Direction get conveyor => switch (this) {
        conveyorUp => Direction.up,
        conveyorDown => Direction.down,
        conveyorLeft => Direction.left,
        conveyorRight => Direction.right,
        _ => Direction.none,
      };

  static TileFeature conveyorFor(Direction d) => switch (d) {
        Direction.up => conveyorUp,
        Direction.down => conveyorDown,
        Direction.left => conveyorLeft,
        Direction.right => conveyorRight,
        Direction.none => none,
      };
}

/// Integer tile coordinate.
class GridPos {
  const GridPos(this.x, this.y);

  final int x;
  final int y;

  GridPos step(int dx, int dy) => GridPos(x + dx, y + dy);

  int manhattanTo(GridPos other) => (x - other.x).abs() + (y - other.y).abs();

  @override
  bool operator ==(Object other) =>
      other is GridPos && other.x == x && other.y == y;

  @override
  int get hashCode => x * 73856093 ^ y * 19349663;

  @override
  String toString() => '($x, $y)';
}

/// The static part of the maze: tile types and what is hidden under bricks.
class Grid {
  Grid(this.width, this.height)
      : _tiles = List.filled(width * height, TileType.floor),
        _hidden = List.filled(width * height, null),
        _features = List.filled(width * height, TileFeature.none);

  final int width;
  final int height;
  final List<TileType> _tiles;
  final List<ItemType?> _hidden;
  final List<TileFeature> _features;

  TileFeature featureAt(int x, int y) =>
      inBounds(x, y) ? _features[y * width + x] : TileFeature.none;

  void setFeature(int x, int y, TileFeature f) => _features[y * width + x] = f;

  bool get hasFeatures => _features.any((f) => f != TileFeature.none);

  /// Warp doors in reading order; consecutive ones are partners.
  List<GridPos> get warps => [
        for (final p in positions)
          if (featureAt(p.x, p.y) == TileFeature.warp) p,
      ];

  /// Warp pipes in reading order.
  List<GridPos> get pipes => [
        for (final p in positions)
          if (featureAt(p.x, p.y).isPipe) p,
      ];

  bool isPipe(int x, int y) => featureAt(x, y).isPipe;

  /// The tile in front of the pipe at [pipe]'s mouth: where you stand to go
  /// in and where you come out.
  GridPos pipeFront(GridPos pipe) {
    final d = featureAt(pipe.x, pipe.y).pipeMouth;
    return pipe.step(d.dx, d.dy);
  }

  /// The pipe whose mouth opens onto [front], or null.
  GridPos? pipeOpeningOnto(GridPos front) {
    for (final d in Direction.cardinal) {
      final n = front.step(d.dx, d.dy);
      if (featureAt(n.x, n.y).pipeMouth == d.opposite) return n;
    }
    return null;
  }

  /// The partner of the warp door at [at], or null.
  GridPos? warpPartner(GridPos at) {
    final all = warps;
    final i = all.indexOf(at);
    if (i < 0) return null;
    final j = i.isEven ? i + 1 : i - 1;
    return j < all.length ? all[j] : null;
  }

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  TileType at(int x, int y) =>
      inBounds(x, y) ? _tiles[y * width + x] : TileType.pillar;

  TileType atPos(GridPos p) => at(p.x, p.y);

  void set(int x, int y, TileType type) => _tiles[y * width + x] = type;

  ItemType? hiddenAt(int x, int y) => _hidden[y * width + x];

  void hide(int x, int y, ItemType? item) => _hidden[y * width + x] = item;

  /// Removes the hidden item (if any) at a tile and returns it.
  ItemType? takeHidden(int x, int y) {
    final item = _hidden[y * width + x];
    _hidden[y * width + x] = null;
    return item;
  }

  bool isSolidForFlame(int x, int y) => at(x, y) == TileType.pillar;

  /// Floor-like tiles a player can stand and place bombs on.
  bool isWalkable(int x, int y) {
    final t = at(x, y);
    return t == TileType.floor || t == TileType.cracked;
  }

  /// Standard NES-style pillar layout: every even row and column is a pillar,
  /// the outer ring is a wall.
  static Grid classicLayout(int width, int height) {
    final g = Grid(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final border = x == 0 || y == 0 || x == width - 1 || y == height - 1;
        if (border || (x.isEven && y.isEven)) g.set(x, y, TileType.pillar);
      }
    }
    return g;
  }

  Iterable<GridPos> get positions sync* {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        yield GridPos(x, y);
      }
    }
  }
}
