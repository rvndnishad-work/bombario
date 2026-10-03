/// The four grid directions plus "none" (standing still).
enum Direction {
  none(0, 0),
  up(0, -1),
  down(0, 1),
  left(-1, 0),
  right(1, 0);

  const Direction(this.dx, this.dy);

  final int dx;
  final int dy;

  bool get isHorizontal => dx != 0;
  bool get isVertical => dy != 0;

  Direction get opposite => switch (this) {
        Direction.up => Direction.down,
        Direction.down => Direction.up,
        Direction.left => Direction.right,
        Direction.right => Direction.left,
        Direction.none => Direction.none,
      };

  static const List<Direction> cardinal = [
    Direction.up,
    Direction.down,
    Direction.left,
    Direction.right,
  ];
}
