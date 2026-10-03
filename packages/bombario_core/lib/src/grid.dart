import 'entities.dart';

/// What a tile is made of. Hidden items live on the tile alongside a brick.
enum TileType {
  floor,
  pillar, // indestructible
  brick, // destructible
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
        _hidden = List.filled(width * height, null);

  final int width;
  final int height;
  final List<TileType> _tiles;
  final List<ItemType?> _hidden;

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
