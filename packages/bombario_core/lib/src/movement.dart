import 'dart:math';

import 'direction.dart';
import 'entities.dart';

/// Lane-constrained player movement with cornering assist.
///
/// Shared by the authoritative [World] and by clients predicting their own
/// player between server snapshots, so both resolve a press the same way.
/// [isSolid] answers whether tile (x, y) blocks [Player].
class Movement {
  const Movement(this.isSolid);

  final bool Function(Player p, int x, int y) isSolid;

  /// Cornering assist window, as a fraction of a tile from the lane centre.
  static const double cornerAssist = 0.4;

  bool canOccupy(Player p, double cx, double cy) {
    const h = Player.halfBox;
    final x0 = (cx - h).floor();
    final x1 = (cx + h - 1e-6).floor();
    final y0 = (cy - h).floor();
    final y1 = (cy + h - 1e-6).floor();
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (isSolid(p, x, y)) return false;
      }
    }
    return true;
  }

  void move(Player p, Direction dir, double dt) {
    if (dir == Direction.none) return;
    p.facing = dir;
    final dist = p.speed * dt;
    final nx = p.x + dir.dx * dist;
    final ny = p.y + dir.dy * dist;
    if (canOccupy(p, nx, ny)) {
      p.setPosition(nx, ny);
      _centreInLane(p, dir, dist);
      return;
    }

    // Blocked: slide flush against the obstacle...
    _clampToObstacle(p, dir, dist);
    // ...then cornering assist: slide sideways into the nearest open lane.
    _cornerAssist(p, dir, dist);
  }

  void _clampToObstacle(Player p, Direction dir, double dist) {
    const h = Player.halfBox;
    const eps = 1e-4;
    switch (dir) {
      case Direction.right:
        final col = (p.x + h + dist).floor();
        final target = col - h - eps;
        if (target > p.x && canOccupy(p, target, p.y)) {
          p.setPosition(target, p.y);
        }
      case Direction.left:
        final col = (p.x - h - dist).floor();
        final target = col + 1 + h + eps;
        if (target < p.x && canOccupy(p, target, p.y)) {
          p.setPosition(target, p.y);
        }
      case Direction.down:
        final row = (p.y + h + dist).floor();
        final target = row - h - eps;
        if (target > p.y && canOccupy(p, p.x, target)) {
          p.setPosition(p.x, target);
        }
      case Direction.up:
        final row = (p.y - h - dist).floor();
        final target = row + 1 + h + eps;
        if (target < p.y && canOccupy(p, p.x, target)) {
          p.setPosition(p.x, target);
        }
      case Direction.none:
        break;
    }
  }

  /// While walking along a lane, drift back to its centre line so the
  /// player lines up with the next junction without fiddling.
  void _centreInLane(Player p, Direction dir, double dist) {
    final offset = dir.isHorizontal ? p.offsetY : p.offsetX;
    if (offset.abs() < 1e-6) return;
    final step = -offset.sign * min(dist, offset.abs());
    final nx = dir.isHorizontal ? p.x : p.x + step;
    final ny = dir.isHorizontal ? p.y + step : p.y;
    if (canOccupy(p, nx, ny)) p.setPosition(nx, ny);
  }

  void _cornerAssist(Player p, Direction dir, double dist) {
    // Offset perpendicular to the movement direction.
    final offset = dir.isHorizontal ? p.offsetY : p.offsetX;
    if (offset.abs() < 1e-6) return;

    // Candidate lanes: own lane first, then the neighbour we lean towards.
    final ownLane = dir.isHorizontal ? p.tileY : p.tileX;
    final neighbourLane = ownLane + offset.sign.toInt();
    final lanes = offset.abs() <= cornerAssist
        ? [ownLane, neighbourLane]
        : [neighbourLane, ownLane];

    for (final lane in lanes) {
      final aheadX = dir.isHorizontal ? p.tileX + dir.dx : lane;
      final aheadY = dir.isHorizontal ? lane : p.tileY + dir.dy;
      if (isSolid(p, aheadX, aheadY)) continue;

      final laneCentre = lane + 0.5;
      final current = dir.isHorizontal ? p.y : p.x;
      final delta = laneCentre - current;
      final step = delta.sign * min(dist, delta.abs());
      final nx = dir.isHorizontal ? p.x : p.x + step;
      final ny = dir.isHorizontal ? p.y + step : p.y;
      if (canOccupy(p, nx, ny)) {
        p.setPosition(nx, ny);
        return;
      }
    }
  }
}
