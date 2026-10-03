import 'dart:math' as math;

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:bombario_net/bombario_net.dart' show GameMode;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../net/room_session.dart';
import '../audio/game_audio.dart';
import '../progress/achievements.dart';
import '../settings/settings.dart';
import 'game_hud.dart';
import 'input_controller.dart';
import 'sprite_atlas.dart';
import 'world_renderer.dart';

/// Networked match: sends this player's input and renders the server's
/// snapshots.
///
/// Two tricks hide the network: the local player is drawn where this phone
/// predicts it to be (it moves the instant the stick does), and everyone else
/// is interpolated between the last two snapshots so 15 Hz updates still look
/// like smooth 60 fps movement.
class NetworkGame extends FlameGame {
  NetworkGame(this.session, {AppSettings? settings, Achievements? achievements})
    : settings = settings ?? AppSettings.memory(),
      achievements = achievements ?? Achievements.memory();

  final AppSettings settings;
  final Achievements achievements;
  final GameHud hud = GameHud();
  final GameMessages messages = GameMessages();

  static const double tileSize = 32;

  final RoomSession session;
  final InputController input = InputController();

  /// What the Action button does for the local player right now.
  final ValueNotifier<String?> actionLabel = ValueNotifier(null);

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
  Color backgroundColor() => const Color(0xFF0D1120);

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
    world.add(
      WorldRenderer(
        () => _snapshot,
        tileSize: tileSize,
        atlas: await SpriteAtlas.load(),
        highContrast: () => settings.highContrastFlames,
      ),
    );
    final name = session.stageName;
    if (name != null) {
      messages.show(
        GameMessage(
          title: 'Stage ${session.stageId}: $name',
          body: session.stageTip ?? '',
          sprite: 'p${_mySlot + 1}',
        ),
      );
    }
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
      if (snap.flames.length > _seenFlames && settings.shake > 0) {
        _shake = 0.15;
      }
      _sounds(_last, snap);
      _seenFlames = snap.flames.length;
      _last = snap;
      final me = session.myPlayerId == null
          ? null
          : snap.player(session.myPlayerId!);
      actionLabel.value = me?.actionLabel;
      _announce(snap, me);
      _unlocked(achievements.recordRoomChange(_meBefore, me));
      _meBefore = me;
      hud.updateFrom(
        snap,
        myId: session.myPlayerId,
        stage: session.stageId ?? '',
        lives: session.mode == GameMode.coop ? snap.livesLeft : null,
      );
    }
    messages.tick(dt);

    // Send input at the simulation rate.
    _accumulator += math.min(dt, 0.25);
    while (_accumulator >= core.World.tickDt) {
      _accumulator -= core.World.tickDt;
      final sent = input.consume();
      if (sent.placeBomb) {
        achievements.recordRoomBomb();
        _myBombAt = _clock;
      }
      session.sendInput(sent);
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
              return e.copyWith(x: x, y: y);
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
    if (_shake > 0 && settings.shake > 0) {
      x += (_rng.nextDouble() - 0.5) * 6;
      y += (_rng.nextDouble() - 0.5) * 6;
    }
    camera.viewfinder.position = Vector2(x, y);
  }

  int get _mySlot {
    final snap = session.snapshot;
    final id = session.myPlayerId;
    if (snap == null || id == null) return 0;
    return math.max(0, snap.players.indexWhere((p) => p.id == id)) % 4;
  }

  core.PlayerState? _meBefore;
  double _myBombAt = -1;
  bool _hurry = false;
  bool _musicStarted = false;

  /// Room play only sees snapshots, so sounds come from what changed.
  void _sounds(core.WorldSnapshot? before, core.WorldSnapshot now) {
    final audio = GameAudio.instance;
    final world = int.tryParse((session.stageId ?? '1').split('-').first) ?? 1;
    if (!_musicStarted) {
      _musicStarted = true;
      audio.playMusic(world);
    }
    if (!_hurry && now.timeLeft <= 30 && now.timeLeft > 0) {
      _hurry = true;
      audio.playMusic(world, hurry: true);
    }
    if (before == null) return;
    if (now.bombs.length > before.bombs.length) {
      // Ours if we pressed Bomb just before this snapshot.
      audio.play(_clock - _myBombAt < 0.4 ? Sfx.bombPlace : Sfx.bombPlaceOther);
    }
    if (now.flames.length > before.flames.length) audio.play(Sfx.explode);
    if (now.pings.length > before.pings.length) audio.play(Sfx.ping);
    final id = session.myPlayerId;
    final was = id == null ? null : before.player(id);
    final me = id == null ? null : now.player(id);
    if (was != null && me != null) {
      if (!was.ghost && me.ghost) audio.play(Sfx.ghost);
      if (was.alive && !me.alive && !me.ghost) audio.play(Sfx.death);
      if (was.ghost && me.alive) audio.play(Sfx.revive);
      if (me.alive &&
          (me.maxBombs > was.maxBombs ||
              me.fireRange > was.fireRange ||
              me.speed > was.speed)) {
        audio.play(Sfx.pickup);
        if (settings.haptics) HapticFeedback.selectionClick();
      }
    }
  }

  void _unlocked(List<AchievementDef> unlocked) {
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

  /// Called once when the match ends.
  void recordResult() {
    GameAudio.instance
      ..stopMusic()
      ..play(
        session.lastCleared || session.lastWinner == session.myPlayerId
            ? Sfx.stageClear
            : Sfx.gameOver,
      );
    final stage = session.stageId;
    if (session.lastCleared && stage != null) {
      _unlocked(achievements.recordStageCleared(stage));
    } else if (session.mode == GameMode.versus &&
        session.lastWinner != null &&
        session.lastWinner == session.myPlayerId) {
      _unlocked(achievements.recordVersusWin());
    }
  }

  final Set<(int, core.PingKind, int, int)> _seenPings = {};
  bool _wasGhost = false;

  /// Turns snapshot changes into popups: teammates' pings and becoming a
  /// ghost.
  void _announce(core.WorldSnapshot snap, core.PlayerState? me) {
    final live = <(int, core.PingKind, int, int)>{};
    for (final ping in snap.pings) {
      final key = (ping.playerId, ping.kind, ping.x, ping.y);
      live.add(key);
      if (_seenPings.contains(key) || ping.playerId == session.myPlayerId) {
        continue;
      }
      final slot = snap.players.indexWhere((p) => p.id == ping.playerId);
      final who = snap.player(ping.playerId)?.name ?? 'Teammate';
      messages.show(
        GameMessage(
          title: '$who: ${pingText[ping.kind]}',
          body: 'Pinged on the map.',
          sprite: 'p${math.max(0, slot) % 4 + 1}',
          seconds: 4,
        ),
      );
    }
    _seenPings
      ..clear()
      ..addAll(live);

    final ghost = me?.ghost ?? false;
    if (ghost && !_wasGhost) {
      messages.show(
        GameMessage(
          title: "You're a ghost",
          body: snap.livesLeft > 0
              ? 'Ping your team, haunt an enemy once, and wait by your '
                    'tombstone for a revive.'
              : 'No revives left. Ping to help your team.',
          sprite: 'spirit-p${_mySlot + 1}',
          seconds: null,
        ),
      );
    }
    _wasGhost = ghost;
  }

  static const pingText = {
    core.PingKind.exitHere: 'Exit is here!',
    core.PingKind.powerUp: 'Power-up here!',
    core.PingKind.help: 'Help!',
    core.PingKind.run: 'Run!',
    core.PingKind.none: '',
  };
}
