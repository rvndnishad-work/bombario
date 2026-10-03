import 'dart:math' as math;

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../admin/admin_cheats.dart';
import '../audio/game_audio.dart';
import '../net/analytics.dart';
import '../progress/achievements.dart';
import '../progress/cosmetics.dart';
import '../settings/settings.dart';
import 'follow_camera.dart';
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
  BlastGame({
    int seed = 1,
    this.daily,
    this.admin,
    this.startStage = 0,
    AppSettings? settings,
    Achievements? achievements,
  }) : _seed = seed,
       stageIndex = startStage,
       settings = settings ?? AppSettings.memory(),
       achievements = achievements ?? Achievements.memory();

  final AppSettings settings;
  final Achievements achievements;

  /// Set when playing the Daily Dungeon instead of the campaign: one stage,
  /// the day's seed, timed for the leaderboard.
  final core.DailyDungeon? daily;

  /// Set when launched from the admin stage viewer.
  final AdminCheats? admin;

  /// The campaign stage to start on (and to restart from).
  final int startStage;

  static const double tileSize = 32;
  static const int startingLives = 3;
  static const double respawnDelay = 1.5;

  /// The board waits behind a "Stage N" card this long before play starts,
  /// like the original's stage screen.
  static const double introSeconds = 2;

  /// After the exit, the board holds still while the clear jingle plays
  /// before the results card comes up.
  static const double clearBeatSeconds = 1.6;

  /// The stage card's text while it shows, else null.
  final ValueNotifier<StageIntro?> intro = ValueNotifier(null);
  double _introLeft = 0;
  GameMessage? _pendingTip;
  double _clearBeat = 0;

  /// Tiles walked since the last footstep, and whether the exit has opened.
  double _stride = 0;
  bool _exitOpen = false;

  /// The stage's power-up has been picked up, so the "find the exit" music
  /// plays instead of the world's.
  bool _found = false;

  /// One footstep per this many tiles walked.
  static const double strideTiles = 0.5;

  final InputController input = InputController();
  final GameHud hud = GameHud();
  final GameMessages messages = GameMessages();

  /// What the Action button does right now.
  final ValueNotifier<String?> actionLabel = ValueNotifier(null);

  int _seed;

  /// Index into [core.Campaign.stages].
  int stageIndex;
  int lives = startingLives;

  core.StageDef get stage => daily?.stage ?? core.Campaign.stages[stageIndex];
  bool get isLastStage =>
      daily != null || stageIndex == core.Campaign.stages.length - 1;

  /// Simulation time spent on this stage, deaths included: the Daily
  /// Dungeon's leaderboard time.
  int get stageTimeMs => (_ticks * core.World.tickDt * 1000).round();
  int _ticks = 0;

  late core.World sim;
  late core.Player player;
  late SpriteAtlas _atlas;
  WorldRenderer? _renderer;
  bool _hasPlayer = false;

  double _accumulator = 0;
  double _respawnTimer = 0;
  double _hudTimer = 0;
  double _shake = 0;
  bool _hurry = false;
  final math.Random _shakeRng = math.Random();
  final FollowCamera _camera = FollowCamera();

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
    final seed = daily?.seed ?? _seed + stageIndex;
    final level = def.level(seed: seed, players: 1);
    final carryOver = _hasPlayer ? _playerStats() : null;
    sim = core.World(
      level,
      seed: seed,
      config: def.config(players: 1, coop: false),
    );
    messages.clear();
    // The tip pops up once the stage card has gone.
    _pendingTip = GameMessage(
      title: daily != null
          ? 'Daily Dungeon: ${def.name}'
          : 'Stage ${def.id}: ${def.name}',
      body: [def.tip, def.extraTip].where((t) => t.isNotEmpty).join('\n\n'),
      sprite: 'p1',
    );
    _introLeft = introSeconds;
    intro.value = StageIntro(
      title: daily != null ? 'DAILY DUNGEON' : 'STAGE ${def.id}',
      subtitle: def.name,
    );
    _clearBeat = 0;
    player = sim.addPlayer(
      name: 'You',
      skin: Cosmetics.equipped(settings.skin, achievements),
    );
    // A tap walks a quarter tile whatever the speed.
    input.tilesPerTick = () => player.speed * core.World.tickDt;
    achievements.startStage();
    _ticks = 0;
    Analytics.instance.log('stage_start', {
      'stage': def.id,
      if (daily != null) 'mode': 'daily',
    });
    _hurry = false;
    _stride = 0;
    _exitOpen = false;
    _found = false;
    // The fanfare plays under the stage card; the world's music follows it.
    GameAudio.instance
      ..stopMusic()
      ..play(Sfx.stageStart);
    _hasPlayer = true;
    carryOver?.call(player);
    _applyCheats();

    final old = _renderer;
    if (old != null) world.remove(old);
    final renderer = WorldRenderer(
      () => core.WorldSnapshot.of(sim),
      tileSize: tileSize,
      atlas: _atlas,
      highContrast: () => settings.highContrastFlames,
      revealHidden: () => admin?.revealHidden ?? false,
    );
    _renderer = renderer;
    world.add(renderer);

    camera.viewfinder.anchor = Anchor.center;
    _camera.reset();
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
      stage: daily != null ? 'Daily' : stage.id,
      lives: lives,
      showPlayers: false,
    );
    actionLabel.value = snap.player(player.id)?.actionLabel;
  }

  void _applyCheats() {
    final a = admin;
    if (a == null) return;
    player
      ..godMode = a.invincible
      ..noClip = a.noClip;
    sim.noEnemies = a.noEnemies;
    // The clock can't run out on someone exploring.
    if (a.invincible) sim.timeLeft = math.max(sim.timeLeft, 60);
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
    camera.viewfinder.zoom = FollowCamera.zoomFor(
      size,
      sim.grid.width,
      sim.grid.height,
      tileSize,
    );
    _followPlayer(0);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _fitCamera();
  }

  void _followPlayer(double dt) {
    final pos = _camera.follow(
      view: size,
      zoom: camera.viewfinder.zoom,
      targetX: player.x * tileSize,
      targetY: player.y * tileSize,
      mazeW: sim.grid.width * tileSize,
      mazeH: sim.grid.height * tileSize,
      tileSize: tileSize,
      dt: dt,
    );
    if (_shake > 0 && settings.shake > 0) {
      pos.x += (_shakeRng.nextDouble() - 0.5) * 6;
      pos.y += (_shakeRng.nextDouble() - 0.5) * 6;
    }
    camera.viewfinder.position = pos;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (sim.cleared) {
      if (_clearBeat > 0) {
        _clearBeat -= dt;
        if (_clearBeat <= 0) overlays.add(Overlays.stageCleared);
      }
      return;
    }
    if (_introLeft > 0) {
      // Bomb or Action skips the card; nothing pressed now leaks into play.
      final pressed = input.consume();
      _introLeft -= dt;
      if (pressed.placeBomb || pressed.action) _introLeft = 0;
      if (_introLeft <= 0) _endIntro();
      _followPlayer(dt);
      return;
    }

    // Out of lives: the board freezes, but the respawn timer below still has
    // to run so the game-over menu appears.
    final outOfLives = sim.failed && lives == 0;

    // Fixed-step simulation so the rules behave identically everywhere.
    _accumulator += math.min(dt, 0.25) * settings.soloSpeed;
    while (!outOfLives && _accumulator >= core.World.tickDt) {
      _accumulator -= core.World.tickDt;
      _applyCheats();
      final x0 = player.x, y0 = player.y;
      sim.tick({player.id: input.consume()});
      _footsteps(x0, y0);
      if (!sim.cleared) _ticks++;
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
        } else if (!overlays.isActive(Overlays.gameOver)) {
          Analytics.instance.log('game_over', {
            'stage': stage.id,
            'score': player.score,
            if (daily != null) 'mode': 'daily',
          });
          GameAudio.instance
            ..stopMusic()
            ..play(Sfx.gameOver);
          overlays.add(Overlays.gameOver);
        }
      }
    }

    _shake = math.max(0, _shake - dt);
    _followPlayer(dt);

    messages.tick(dt);
    if (!_hurry && sim.timeLeft <= 30 && sim.timeLeft > 0) {
      _hurry = true;
      GameAudio.instance.playMusic(stage.world, hurry: true, found: _found);
    }
    _hudTimer += dt;
    if (_hudTimer >= 0.1) {
      _hudTimer = 0;
      _refreshHud();
    }
  }

  /// What a power-up is called and what it just did, for the pickup popup.
  static (String, String) itemInfo(core.ItemType type) => switch (type) {
    core.ItemType.bombUp => ('Bomb Up', 'One more bomb at a time.'),
    core.ItemType.fireUp => ('Fire Up', 'Your flames reach one tile further.'),
    core.ItemType.speedUp => ('Speed Up', 'You walk faster.'),
    core.ItemType.wallPass => ('Wall Pass', 'Walk through bricks.'),
    core.ItemType.remote => ('Detonator', 'Action sets off your oldest bomb.'),
    core.ItemType.bombPass => ('Bomb Pass', 'Walk through bombs.'),
    core.ItemType.flamePass => ('Flame Pass', 'Flames can\'t hurt you.'),
    core.ItemType.mystery => ('Mystery', 'Invincible for a while!'),
    core.ItemType.kick => ('Kick', 'Walk into a bomb to send it sliding.'),
    core.ItemType.heart => ('Heart', 'Takes one hit for you.'),
    core.ItemType.sonar => ('Sonar', 'Shows what hides under nearby bricks.'),
    core.ItemType.teamBoost => ('Team Boost', 'Powers up your teammates.'),
    core.ItemType.tether => ('Tether', 'Revive a teammate from a distance.'),
    core.ItemType.frost => ('Frost', 'Your next bombs freeze.'),
    core.ItemType.exit => ('Exit', ''),
  };

  /// A footstep every half tile walked, pitched by axis like the original.
  void _footsteps(double x0, double y0) {
    if (!player.alive || sim.cleared) return;
    final dx = (player.x - x0).abs(), dy = (player.y - y0).abs();
    if (dx + dy < 1e-4 || dx + dy > 0.5) {
      _stride = 0; // standing, or teleported (respawn, warp)
      return;
    }
    _stride += dx + dy;
    if (_stride >= strideTiles) {
      _stride -= strideTiles;
      GameAudio.instance.play(dx >= dy ? Sfx.stepH : Sfx.stepV);
    }
  }

  /// The last enemy is down: chime once so you know to head for the exit.
  void _checkExitOpen() {
    if (_exitOpen || sim.cleared || stage.isBoss || stage.bonus) return;
    if (sim.enemies.isEmpty || !sim.allEnemiesDead) return;
    _exitOpen = true;
    GameAudio.instance.play(Sfx.exitOpen);
  }

  void _buzz(Future<void> Function() f) {
    if (settings.haptics) f();
  }

  void _handleEvents() {
    final audio = GameAudio.instance;
    for (final event in sim.events) {
      switch (event) {
        case core.BombPlaced(:final bomb):
          audio.play(
            bomb.ownerId == player.id ? Sfx.bombPlace : Sfx.bombPlaceOther,
          );
        case core.ItemPicked(:final playerId, :final type)
            when playerId == player.id:
          audio.play(Sfx.pickup);
          _buzz(HapticFeedback.selectionClick);
          if (!_found && !stage.bonus && type != core.ItemType.exit) {
            _found = true;
            audio.playMusic(stage.world, hurry: _hurry, found: true);
          }
          final (title, body) = itemInfo(type);
          messages.show(
            GameMessage(
              title: title,
              body: body,
              sprite: WorldRenderer.itemSprite(type),
              seconds: 2.5,
            ),
          );
        case core.BombKicked():
          audio.play(Sfx.kick);
        case core.EnemyFrozen() || core.PlayerFrozen():
          audio.play(Sfx.freeze);
        case core.BossDamaged():
          audio.play(Sfx.bossHit);
        default:
          break;
      }
      switch (event) {
        case core.BombExploded(:final x, :final y):
          _shake = 0.15;
          final near = (player.x - x).abs() + (player.y - y).abs() < 6;
          audio.play(near ? Sfx.explode : Sfx.explodeFar);
          if (near) _buzz(HapticFeedback.heavyImpact);
        case core.PlayerDied():
          lives--;
          _shake = 0.3;
          audio.play(Sfx.death);
          _buzz(HapticFeedback.vibrate);
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
        case core.EnemyDied():
          _checkExitOpen();
        case core.ItemBurned(releasedWave: true):
          _shake = 0.4;
          audio.play(Sfx.exitAngry);
          messages.show(
            GameMessage(
              title: 'You bombed a power-up!',
              body: 'It is gone, and Door Wardens poured out.',
              sprite: 'doorWarden',
              seconds: 4,
            ),
          );
        case core.ExitBombed():
          _shake = 0.4;
          audio.play(Sfx.exitAngry);
          messages.show(
            GameMessage(
              title: 'The exit is angry!',
              body: 'Door Wardens are pouring out. Run!',
              sprite: 'doorWarden',
              seconds: 4,
            ),
          );
        case core.TreasureHit(:final hp) when hp > 0:
          _shake = 0.15;
          audio.play(Sfx.bossHit);
        case core.TreasureOpened(:final item) ||
            core.MiniBossDefeated(:final item):
          final chest = event is core.TreasureOpened;
          audio.play(Sfx.exitOpen);
          messages.show(
            GameMessage(
              title: chest ? 'Treasure!' : 'Mini-boss down!',
              body:
                  '+${chest ? core.World.treasurePoints : core.World.miniBossPoints}'
                  ' points. It dropped a ${itemInfo(item).$1}.',
              sprite: WorldRenderer.itemSprite(item),
              seconds: 3,
            ),
          );
        case core.ChallengeFailed():
          messages.show(
            GameMessage(
              title: 'Challenge failed',
              body: 'You got hit. Clear the stage anyway!',
              sprite: 'tomb',
              seconds: 3,
            ),
          );
        case core.ChallengeComplete():
          lives++;
          messages.show(
            GameMessage(
              title: 'Challenge complete!',
              body: '+${core.World.challengePoints} points and an extra life.',
              sprite: 'p1',
              seconds: 4,
            ),
          );
        case core.StageCleared():
          Analytics.instance.log('stage_clear', {
            'stage': stage.id,
            'timeMs': stageTimeMs,
            'lives': lives,
            if (daily != null) 'mode': 'daily',
          });
          audio
            ..stopMusic()
            ..play(Sfx.stageClear);
          _clearBeat = clearBeatSeconds;
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

  void _endIntro() {
    _introLeft = 0;
    intro.value = null;
    GameAudio.instance.playMusic(stage.world);
    final tip = _pendingTip;
    _pendingTip = null;
    if (tip != null) messages.show(tip);
  }

  /// Skips the rest of the stage card (a tap or key press).
  void skipIntro() {
    if (_introLeft > 0) _endIntro();
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

  /// Admin view: jumps straight to campaign stage [index], fresh lives.
  void goToStage(int index) {
    overlays
      ..remove(Overlays.stageCleared)
      ..remove(Overlays.gameOver);
    stageIndex = index.clamp(0, core.Campaign.stages.length - 1);
    lives = startingLives;
    _startStage();
  }

  void restart() {
    overlays.remove(Overlays.gameOver);
    stageIndex = admin != null ? startStage : 0;
    _hasPlayer = false;
    lives = startingLives;
    // The daily keeps its seed: everyone races the same dungeon.
    _seed = _shakeRng.nextInt(1 << 30);
    _startStage();
  }
}
