import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'input_controller.dart';
import 'world_renderer.dart';

/// Overlay ids used with [GameWidget.overlayBuilderMap].
abstract final class Overlays {
  static const hud = 'hud';
  static const controls = 'controls';
  static const stageCleared = 'stageCleared';
  static const gameOver = 'gameOver';
}

/// What the HUD shows. Updated a few times a second from the simulation.
class HudState extends ChangeNotifier {
  int lives = 3;
  int score = 0;
  int timeLeft = 0;
  int bombs = 1;
  int fire = 1;
  int stage = 1;
  bool remote = false;
  int enemiesLeft = 0;

  void updateFrom(
    core.World world,
    core.Player player, {
    required int lives,
    required int stage,
  }) {
    this.lives = lives;
    this.stage = stage;
    score = player.score;
    timeLeft = world.timeLeft.ceil();
    bombs = player.maxBombs;
    fire = player.fireRange;
    remote = player.remote;
    enemiesLeft = world.enemies.where((e) => e.alive).length;
    notifyListeners();
  }
}

/// Solo prototype: one player, generated stages, three lives.
///
/// The simulation lives entirely in `bombario_core`; this class only steps it at
/// a fixed 30 Hz, feeds it input, moves the camera and reacts to events.
class BlastGame extends FlameGame {
  BlastGame({int seed = 1}) : _seed = seed;

  static const double tileSize = 32;
  static const int startingLives = 3;
  static const double respawnDelay = 1.5;

  final InputController input = InputController();
  final HudState hud = HudState();
  final ValueNotifier<bool> hasRemote = ValueNotifier(false);

  int _seed;
  int stage = 1;
  int lives = startingLives;

  late core.World sim;
  late core.Player player;
  WorldRenderer? _renderer;
  bool _hasPlayer = false;

  double _accumulator = 0;
  double _respawnTimer = 0;
  double _hudTimer = 0;
  double _shake = 0;
  final math.Random _shakeRng = math.Random();

  @override
  Color backgroundColor() => const Color(0xFF1B1B1B);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _startStage();
    overlays.add(Overlays.hud);
    overlays.add(Overlays.controls);
  }

  void _startStage() {
    // Difficulty ramps with the stage number: more enemies, smarter kinds,
    // denser bricks. Mirrors the World 1 table in the design doc.
    final kinds = <core.EnemyKind>[
      core.EnemyKind.puffball,
      if (stage >= 3) core.EnemyKind.blueDrop,
      if (stage >= 6) core.EnemyKind.slimeSage,
    ];
    final level = core.LevelData.generate(
      seed: _seed + stage,
      players: 1,
      enemyCount: 4 + stage,
      brickDensity: math.min(0.65, 0.35 + stage * 0.03),
      enemyKinds: kinds,
      items: const [
        core.ItemType.bombUp,
        core.ItemType.fireUp,
        core.ItemType.speedUp,
        core.ItemType.remote,
        core.ItemType.wallPass,
        core.ItemType.bombPass,
        core.ItemType.flamePass,
        core.ItemType.mystery,
      ],
      timeLimit: 200,
    );
    final carryOver = _hasPlayer ? _playerStats() : null;
    sim = core.World(level, seed: _seed + stage, config: core.WorldConfig.solo);
    player = sim.addPlayer(name: 'You');
    _hasPlayer = true;
    carryOver?.call(player);

    final old = _renderer;
    if (old != null) world.remove(old);
    final renderer = WorldRenderer(
      () => core.WorldSnapshot.of(sim),
      tileSize: tileSize,
    );
    _renderer = renderer;
    world.add(renderer);

    camera.viewfinder.anchor = Anchor.center;
    _fitCamera();
    _accumulator = 0;
    _respawnTimer = 0;
    hud.updateFrom(sim, player, lives: lives, stage: stage);
  }

  /// Stat power-ups carry over between stages, as in the original.
  void Function(core.Player) _playerStats() {
    final bombs = player.maxBombs,
        fire = player.fireRange,
        speed = player.speed;
    return (core.Player np) {
      np.maxBombs = bombs;
      np.fireRange = fire;
      np.speed = speed;
    };
  }

  void _fitCamera() {
    // Show the whole maze height; width scrolls like the NES version.
    final rows = sim.grid.height * tileSize;
    final cols = sim.grid.width * tileSize;
    final zoom = math.min(size.y / rows, size.x / cols * 1.6);
    camera.viewfinder.zoom = zoom;
    _followPlayer();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _fitCamera();
  }

  void _followPlayer() {
    final zoom = camera.viewfinder.zoom;
    final halfW = size.x / zoom / 2;
    final halfH = size.y / zoom / 2;
    final mazeW = sim.grid.width * tileSize;
    final mazeH = sim.grid.height * tileSize;
    var x = player.x * tileSize;
    var y = player.y * tileSize;
    // Clamp so the camera never shows outside the maze (when it fits).
    x = mazeW <= halfW * 2 ? mazeW / 2 : x.clamp(halfW, mazeW - halfW);
    y = mazeH <= halfH * 2 ? mazeH / 2 : y.clamp(halfH, mazeH - halfH);
    if (_shake > 0) {
      x += (_shakeRng.nextDouble() - 0.5) * 6;
      y += (_shakeRng.nextDouble() - 0.5) * 6;
    }
    camera.viewfinder.position = Vector2(x, y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (sim.cleared || (sim.failed && lives == 0)) return;

    // Fixed-step simulation so the rules behave identically everywhere.
    _accumulator += math.min(dt, 0.25);
    while (_accumulator >= core.World.tickDt) {
      _accumulator -= core.World.tickDt;
      sim.tick({player.id: input.consume()});
      _handleEvents();
    }

    if (!player.alive) {
      _respawnTimer += dt;
      if (_respawnTimer >= respawnDelay) {
        _respawnTimer = 0;
        if (lives > 0) {
          sim.respawn(player);
          sim.clearFailure();
        } else {
          overlays.add(Overlays.gameOver);
        }
      }
    }

    _shake = math.max(0, _shake - dt);
    _followPlayer();

    _hudTimer += dt;
    if (_hudTimer >= 0.1) {
      _hudTimer = 0;
      hud.updateFrom(sim, player, lives: lives, stage: stage);
      hasRemote.value = player.remote;
    }
  }

  void _handleEvents() {
    for (final event in sim.events) {
      switch (event) {
        case core.BombExploded():
          _shake = 0.15;
        case core.PlayerDied():
          lives--;
          _shake = 0.3;
        case core.StageCleared():
          overlays.add(Overlays.stageCleared);
        case core.StageFailed():
          break; // handled by the respawn timer
        default:
          break;
      }
    }
  }

  void nextStage() {
    overlays.remove(Overlays.stageCleared);
    stage++;
    _startStage();
  }

  void restart() {
    overlays.remove(Overlays.gameOver);
    stage = 1;
    lives = startingLives;
    _seed = _shakeRng.nextInt(1 << 30);
    _startStage();
  }
}
