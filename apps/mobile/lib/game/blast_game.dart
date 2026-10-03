import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../progress/achievements.dart';
import '../settings/settings.dart';
import 'game_hud.dart';
import 'input_controller.dart';
import 'sprite_atlas.dart';
import 'world_renderer.dart';

/// Overlay ids used with [GameWidget.overlayBuilderMap].
abstract final class Overlays {
  static const controls = 'controls';
  static const pause = 'pause';
  static const stageCleared = 'stageCleared';
  static const gameOver = 'gameOver';
}

/// Solo campaign: the co-op stages played alone (§4.3 "Solo Campaign"),
/// three lives, power-ups carried between stages.
///
/// The simulation lives entirely in `bombario_core`; this class only steps it at
/// a fixed 30 Hz, feeds it input, moves the camera and reacts to events.
class BlastGame extends FlameGame {
  BlastGame({int seed = 1, AppSettings? settings, Achievements? achievements})
    : _seed = seed,
      settings = settings ?? AppSettings.memory(),
      achievements = achievements ?? Achievements.memory();

  final AppSettings settings;
  final Achievements achievements;

  static const double tileSize = 32;
  static const int startingLives = 3;
  static const double respawnDelay = 1.5;

  final InputController input = InputController();
  final GameHud hud = GameHud();
  final GameMessages messages = GameMessages();

  /// What the Action button does right now.
  final ValueNotifier<String?> actionLabel = ValueNotifier(null);

  int _seed;

  /// Index into [core.Campaign.stages].
  int stageIndex = 0;
  int lives = startingLives;

  core.StageDef get stage => core.Campaign.stages[stageIndex];
  bool get isLastStage => stageIndex == core.Campaign.stages.length - 1;

  late core.World sim;
  late core.Player player;
  late SpriteAtlas _atlas;
  WorldRenderer? _renderer;
  bool _hasPlayer = false;

  double _accumulator = 0;
  double _respawnTimer = 0;
  double _hudTimer = 0;
  double _shake = 0;
  final math.Random _shakeRng = math.Random();

  @override
  Color backgroundColor() => const Color(0xFF0D1120);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _atlas = await SpriteAtlas.load();
    _startStage();
    overlays.add(Overlays.controls);
  }

  void _startStage() {
    final def = stage;
    final seed = _seed + stageIndex;
    final level = def.level(seed: seed, players: 1);
    final carryOver = _hasPlayer ? _playerStats() : null;
    sim = core.World(
      level,
      seed: seed,
      config: def.config(players: 1, coop: false),
    );
    messages
      ..clear()
      ..show(
        GameMessage(
          title: 'Stage ${def.id}: ${def.name}',
          body: def.tip,
          sprite: 'p1',
        ),
      );
    player = sim.addPlayer(name: 'You');
    achievements.startStage();
    _hasPlayer = true;
    carryOver?.call(player);

    final old = _renderer;
    if (old != null) world.remove(old);
    final renderer = WorldRenderer(
      () => core.WorldSnapshot.of(sim),
      tileSize: tileSize,
      atlas: _atlas,
      highContrast: () => settings.highContrastFlames,
    );
    _renderer = renderer;
    world.add(renderer);

    camera.viewfinder.anchor = Anchor.center;
    _fitCamera();
    _accumulator = 0;
    _respawnTimer = 0;
    _refreshHud();
  }

  void _refreshHud() {
    final snap = core.WorldSnapshot.of(sim);
    hud.updateFrom(
      snap,
      myId: player.id,
      stage: stage.id,
      lives: lives,
      showPlayers: false,
    );
    actionLabel.value = snap.player(player.id)?.actionLabel;
  }

  /// Power-ups carry over between stages, as in the original.
  void Function(core.Player) _playerStats() {
    final items = [...player.items];
    final active = player.active;
    final hearts = player.hearts;
    return (core.Player np) {
      np.items.addAll(items);
      np.recomputeStats();
      np.active = active;
      np.hearts = hearts;
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
    if (_shake > 0 && settings.shake > 0) {
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
    _accumulator += math.min(dt, 0.25) * settings.soloSpeed;
    while (_accumulator >= core.World.tickDt) {
      _accumulator -= core.World.tickDt;
      sim.tick({player.id: input.consume()});
      _handleEvents();
      _announce(
        achievements.recordEvents(
          sim.events,
          myId: player.id,
          stageId: stage.id,
          coop: false,
        ),
      );
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

    messages.tick(dt);
    _hudTimer += dt;
    if (_hudTimer >= 0.1) {
      _hudTimer = 0;
      _refreshHud();
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
          messages.show(
            GameMessage(
              title: lives > 0 ? 'Ouch!' : 'Out of lives',
              body: lives == 1
                  ? '1 life left.'
                  : lives > 1
                  ? '$lives lives left.'
                  : '',
              sprite: 'tomb',
              seconds: 3,
            ),
          );
        case core.ExitBombed():
          _shake = 0.4;
          messages.show(
            GameMessage(
              title: 'The exit is angry!',
              body: 'Door Wardens are pouring out. Run!',
              sprite: 'doorWarden',
              seconds: 4,
            ),
          );
        case core.StageCleared():
          overlays.add(Overlays.stageCleared);
        case core.StageFailed():
          break; // handled by the respawn timer
        default:
          break;
      }
    }
  }

  void _announce(List<AchievementDef> unlocked) {
    for (final a in unlocked) {
      messages.show(
        GameMessage(
          title: 'Achievement: ${a.title}',
          body: a.description,
          sprite: a.sprite,
          seconds: 4,
        ),
      );
    }
  }

  /// Freezes the simulation behind the pause menu.
  void pause() {
    if (paused) return;
    input.release();
    pauseEngine();
    overlays.add(Overlays.pause);
  }

  void resume() {
    overlays.remove(Overlays.pause);
    resumeEngine();
  }

  void nextStage() {
    overlays.remove(Overlays.stageCleared);
    // After the last stage, loop back to the start with everything kept.
    stageIndex = isLastStage ? 0 : stageIndex + 1;
    _startStage();
  }

  void restart() {
    overlays.remove(Overlays.gameOver);
    stageIndex = 0;
    _hasPlayer = false;
    lives = startingLives;
    _seed = _shakeRng.nextInt(1 << 30);
    _startStage();
  }
}
