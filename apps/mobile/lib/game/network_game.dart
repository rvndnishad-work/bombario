import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../net/room_session.dart';
import 'input_controller.dart';
import 'world_renderer.dart';

/// Networked match: renders the server's snapshots and sends this player's
/// input. No prediction yet (LAN latency is a few milliseconds); Phase 2 adds
/// prediction and interpolation for online rooms.
class NetworkGame extends FlameGame {
  NetworkGame(this.session);

  static const double tileSize = 32;

  final RoomSession session;
  final InputController input = InputController();
  final ValueNotifier<bool> hasRemote = ValueNotifier(false);

  core.WorldSnapshot? _last;
  double _accumulator = 0;
  double _shake = 0;
  int _seenFlames = 0;
  final math.Random _rng = math.Random();

  @override
  Color backgroundColor() => const Color(0xFF1B1B1B);

  core.WorldSnapshot get _snapshot =>
      session.snapshot ?? _last ?? _emptySnapshot;

  static final _emptySnapshot = core.WorldSnapshot(
    tick: 0,
    timeLeft: 0,
    grid: core.Grid.classicLayout(15, 13),
    players: const [],
    bombs: const [],
    flames: const [],
    items: const [],
    enemies: const [],
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    world.add(WorldRenderer(() => _snapshot, tileSize: tileSize));
    camera.viewfinder.anchor = Anchor.center;
    _fitCamera();
  }

  void _fitCamera() {
    final grid = _snapshot.grid;
    final rows = grid.height * tileSize;
    final cols = grid.width * tileSize;
    final zoom = math.min(size.y / rows, size.x / cols * 1.6);
    camera.viewfinder.zoom = zoom;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _fitCamera();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final snap = session.snapshot;
    if (snap != null && snap != _last) {
      if (_last == null || snap.grid.width != _last!.grid.width) _fitCamera();
      // Any new flame tile means something exploded: shake a little.
      if (snap.flames.length > _seenFlames) _shake = 0.15;
      _seenFlames = snap.flames.length;
      _last = snap;
      final me = session.myPlayerId == null
          ? null
          : snap.player(session.myPlayerId!);
      hasRemote.value = me?.remote ?? false;
    }

    // Send input at the simulation rate.
    _accumulator += math.min(dt, 0.25);
    while (_accumulator >= core.World.tickDt) {
      _accumulator -= core.World.tickDt;
      session.sendInput(input.consume());
    }

    _shake = math.max(0, _shake - dt);
    _follow();
  }

  void _follow() {
    final snap = _snapshot;
    final me = session.myPlayerId == null
        ? null
        : snap.player(session.myPlayerId!);
    final zoom = camera.viewfinder.zoom;
    final halfW = size.x / zoom / 2;
    final halfH = size.y / zoom / 2;
    final mazeW = snap.grid.width * tileSize;
    final mazeH = snap.grid.height * tileSize;
    var x = (me?.x ?? snap.grid.width / 2) * tileSize;
    var y = (me?.y ?? snap.grid.height / 2) * tileSize;
    x = mazeW <= halfW * 2 ? mazeW / 2 : x.clamp(halfW, mazeW - halfW);
    y = mazeH <= halfH * 2 ? mazeH / 2 : y.clamp(halfH, mazeH - halfH);
    if (_shake > 0) {
      x += (_rng.nextDouble() - 0.5) * 6;
      y += (_rng.nextDouble() - 0.5) * 6;
    }
    camera.viewfinder.position = Vector2(x, y);
  }
}
