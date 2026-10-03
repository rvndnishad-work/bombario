import 'dart:math' as math;

import 'package:flame/components.dart';

/// The classic top-down Bomberman camera, shared by solo and room play.
///
/// The board fills the screen width (up to [maxColumns] tiles, so big mazes
/// keep readable tiles) and scrolls on whichever axis the maze overflows.
/// The camera eases after the player with a small dead zone, so it doesn't
/// jitter on every step, and stops at the maze walls.
class FollowCamera {
  /// The most tiles shown across; wider mazes scroll sideways.
  static const int maxColumns = 17;

  /// Never zoom in so far that fewer rows than this are visible.
  static const int minRows = 5;

  /// How far (in tiles) the player can stray from the centre before the
  /// camera moves.
  static const double deadZoneX = 1.5;
  static const double deadZoneY = 1;

  /// How quickly the camera catches up (per second).
  static const double stiffness = 8;

  Vector2? _pos;

  static double zoomFor(Vector2 view, int gridWidth, double tileSize) {
    final fillWidth = view.x / (math.min(gridWidth, maxColumns) * tileSize);
    final keepRows = view.y / (minRows * tileSize);
    return math.min(fillWidth, keepRows);
  }

  /// Jumps straight to the next target instead of easing (new stage).
  void reset() => _pos = null;

  /// Where the camera centre should be this frame.
  Vector2 follow({
    required Vector2 view,
    required double zoom,
    required double targetX,
    required double targetY,
    required double mazeW,
    required double mazeH,
    required double tileSize,
    required double dt,
  }) {
    final halfW = view.x / zoom / 2;
    final halfH = view.y / zoom / 2;
    var pos = _pos;
    if (pos == null) {
      pos = Vector2(targetX, targetY);
    } else {
      final dzX = deadZoneX * tileSize;
      final dzY = deadZoneY * tileSize;
      var wantX = pos.x;
      var wantY = pos.y;
      if (targetX > pos.x + dzX) wantX = targetX - dzX;
      if (targetX < pos.x - dzX) wantX = targetX + dzX;
      if (targetY > pos.y + dzY) wantY = targetY - dzY;
      if (targetY < pos.y - dzY) wantY = targetY + dzY;
      final k = 1 - math.exp(-stiffness * dt);
      pos = Vector2(pos.x + (wantX - pos.x) * k, pos.y + (wantY - pos.y) * k);
    }
    pos.x = mazeW <= halfW * 2 ? mazeW / 2 : pos.x.clamp(halfW, mazeW - halfW);
    pos.y = mazeH <= halfH * 2 ? mazeH / 2 : pos.y.clamp(halfH, mazeH - halfH);
    _pos = pos;
    return pos.clone();
  }
}
