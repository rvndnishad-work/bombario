import 'dart:math' as math;

import 'package:flame/components.dart';

/// The classic top-down Bomberman camera, shared by solo and room play.
///
/// The board always covers the whole screen. Like the original, a standard
/// 31 x 13 maze shows every row and scrolls sideways only; a maze too narrow
/// to fill the width at that size is zoomed until it does, and scrolls a
/// little vertically instead. On a tall (portrait) screen the zoom is capped
/// so at least [minColumns] fit across. The camera eases after the
/// player with a small dead zone, so it doesn't jitter on every step, and
/// stops at the maze walls. It also looks ahead: walking up shifts the view
/// so the player sits low and the rows above come into sight early (and
/// the other way round), so an enemy is on screen well before you meet it.
class FollowCamera {
  /// Never zoom in so far that fewer columns than this are visible.
  static const int minColumns = 9;

  /// How far (in tiles) the player can stray from the centre before the
  /// camera moves.
  static const double deadZoneX = 1.5;
  static const double deadZoneY = 1;

  /// How quickly the camera catches up (per second).
  static const double stiffness = 8;

  /// Look-ahead: this share of the visible rows or columns, at most
  /// [maxLead] tiles, in the direction the player last walked.
  static const double leadShare = 0.3;
  static const double maxLead = 4;

  /// How quickly the look-ahead swings round when the player turns.
  static const double leadStiffness = 3;

  Vector2? _pos;
  Vector2? _lastTarget;
  final Vector2 _lead = Vector2.zero();

  /// The current look-ahead offset in world units (for tests).
  Vector2 get lead => _lead.clone();

  static double zoomFor(
    Vector2 view,
    int gridWidth,
    int gridHeight,
    double tileSize,
  ) {
    final fitHeight = view.y / (gridHeight * tileSize);
    final fitWidth = view.x / (gridWidth * tileSize);
    final keepColumns = view.x / (math.min(gridWidth, minColumns) * tileSize);
    return math.min(math.max(fitHeight, fitWidth), keepColumns);
  }

  /// Jumps straight to the next target instead of easing (new stage).
  void reset() {
    _pos = null;
    _lastTarget = null;
    _lead.setZero();
  }

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
    // Which way the player is walking, from how the target moved. A jump
    // (respawn, warp) or standing still keeps the last look-ahead.
    final last = _lastTarget;
    _lastTarget = Vector2(targetX, targetY);
    if (last != null && dt > 0) {
      final dx = targetX - last.x, dy = targetY - last.y;
      final step = math.max(dx.abs(), dy.abs());
      if (step > 1e-3 && step < tileSize) {
        final leadX = math.min(halfW * 2 * leadShare, maxLead * tileSize);
        final leadY = math.min(halfH * 2 * leadShare, maxLead * tileSize);
        final want = dx.abs() >= dy.abs()
            ? Vector2(dx.sign * leadX, 0)
            : Vector2(0, dy.sign * leadY);
        final k = 1 - math.exp(-leadStiffness * dt);
        _lead.add((want - _lead)..scale(k));
      }
    }
    targetX += _lead.x;
    targetY += _lead.y;
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
