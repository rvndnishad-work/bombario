import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../net/room_session.dart';
import 'input_controller.dart';
import 'world_renderer.dart';

/// Networked match: sends this player's input and renders the server's
/// snapshots.
///
/// Two tricks hide the network: the local player is drawn where this phone
/// predicts it to be (it moves the instant the stick does), and everyone else
/// is interpolated between the last two snapshots so 15 Hz updates still look
/// like smooth 60 fps movement.
class NetworkGame extends FlameGame {
  NetworkGame(this.session);

  static const double tileSize = 32;

  final RoomSession session;
  final InputController input = InputController();
  final ValueNotifier<bool> hasRemote = ValueNotifier(false);

  core.WorldSnapshot? _last;
  core.WorldSnapshot? _prev;
  double _clock = 0;
  double _lastAt = 0;
  core.WorldSnapshot? _view;

  /// Snapshots arrive every other simulation tick.
  static const double snapshotInterval = 2 * core.World.tickDt;

  /// Movement larger than this between snapshots is a teleport (respawn),
  /// not something to slide across.
  static const double maxLerp = 1.5;
  double _accumulator = 0;
  double _shake = 0;
  int _seenFlames = 0;
  final math.Random _rng = math.Random();

  @override
  Color backgroundColor() => const Color(0xFF1B1B1B);

  core.WorldSnapshot get _snapshot =>
      _view ?? session.snapshot ?? _last ?? _emptySnapshot;

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
    _clock += dt;
    final snap = session.snapshot;
    if (snap != null && snap != _last) {
      _prev = _last;
      _lastAt = _clock;
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

    _view = _smoothed();
    _shake = math.max(0, _shake - dt);
    _follow();
  }

  core.WorldSnapshot? _smoothed() {
    final cur = _last;
    if (cur == null) return null;
    final prev = _prev;
    final t = ((_clock - _lastAt) / snapshotInterval).clamp(0.0, 1.0);
    final myId = session.myPlayerId;
    final me = session.me;

    (double, double) lerp(double px, double py, double x, double y) {
      if ((x - px).abs() > maxLerp || (y - py).abs() > maxLerp) return (x, y);
      return (px + (x - px) * t, py + (y - py) * t);
    }

    return cur.copyWith(
      players: [
        for (final p in cur.players)
          if (p.id == myId && me != null)
            me
          else if (prev?.player(p.id) case final old?)
            () {
              final (x, y) = lerp(old.x, old.y, p.x, p.y);
              return p.copyWith(x: x, y: y);
            }()
          else
            p,
      ],
      enemies: [
        for (final e in cur.enemies)
          if (prev?.enemies.where((o) => o.id == e.id).firstOrNull
              case final old?)
            () {
              final (x, y) = lerp(old.x, old.y, e.x, e.y);
              return core.EnemyState(e.id, x, y, e.alive, e.kind);
            }()
          else
            e,
      ],
    );
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
