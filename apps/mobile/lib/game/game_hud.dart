import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/foundation.dart';

enum HudPlayerStatus { alive, ghost, out }

/// One teammate or rival in the toolbar.
class HudPlayer {
  const HudPlayer({
    required this.name,
    required this.slot,
    required this.status,
    required this.isMe,
  });

  final String name;
  final int slot;
  final HudPlayerStatus status;
  final bool isMe;

  @override
  bool operator ==(Object other) =>
      other is HudPlayer &&
      other.name == name &&
      other.slot == slot &&
      other.status == status &&
      other.isMe == isMe;

  @override
  int get hashCode => Object.hash(name, slot, status, isMe);
}

/// What the in-game toolbar shows, for solo and room play alike. Games
/// refresh it from a snapshot a few times a second; it only notifies when
/// something visible changed.
class GameHud extends ChangeNotifier {
  int timeLeft = 0;
  String stage = '';

  /// Solo lives, or the co-op team's shared revive pool. Null in versus.
  int? lives;
  int bombs = 1;
  int fire = 1;

  /// Speed-ups collected, 0 at base speed.
  int speed = 0;
  int score = 0;
  int enemiesLeft = 0;
  core.ActiveItem active = core.ActiveItem.none;
  List<HudPlayer> players = const [];

  void updateFrom(
    core.WorldSnapshot snap, {
    required int? myId,
    required String stage,
    int? lives,
    bool showPlayers = true,
  }) {
    final me = myId == null ? null : snap.player(myId);
    final next = (
      snap.timeLeft.ceil(),
      stage,
      lives,
      me?.maxBombs ?? bombs,
      me?.fireRange ?? fire,
      me == null
          ? speed
          : ((me.speed - core.Player.baseSpeed) / core.Player.speedStep)
                .round(),
      me?.score ?? score,
      snap.enemies.where((e) => e.alive).length,
      me?.active ?? active,
    );
    final roster = showPlayers
        ? [
            for (var i = 0; i < snap.players.length; i++)
              HudPlayer(
                name: snap.players[i].name,
                slot: i,
                status: snap.players[i].alive
                    ? HudPlayerStatus.alive
                    : snap.players[i].ghost
                    ? HudPlayerStatus.ghost
                    : HudPlayerStatus.out,
                isMe: snap.players[i].id == myId,
              ),
          ]
        : const <HudPlayer>[];
    final current = (
      timeLeft,
      this.stage,
      this.lives,
      bombs,
      fire,
      speed,
      score,
      enemiesLeft,
      active,
    );
    if (next == current && listEquals(roster, players)) return;
    timeLeft = next.$1;
    this.stage = next.$2;
    this.lives = next.$3;
    bombs = next.$4;
    fire = next.$5;
    speed = next.$6;
    score = next.$7;
    enemiesLeft = next.$8;
    active = next.$9;
    players = roster;
    notifyListeners();
  }
}

/// A closable in-game message (the mockups' red-bordered popup).
class GameMessage {
  GameMessage({
    required this.title,
    this.body = '',
    this.sprite,
    this.seconds = 5,
  }) : id = _next++;

  static int _next = 0;

  final int id;
  final String title;
  final String body;

  /// Atlas sprite shown on the left, such as the sender's player sprite.
  final String? sprite;

  /// Closes itself after this long; null waits for the close button.
  final double? seconds;
}

/// Queue of popups over the board. At most [maxVisible] show at once; the
/// newest is on top.
class GameMessages extends ChangeNotifier {
  static const maxVisible = 2;

  final List<GameMessage> _items = [];
  final Map<int, double> _age = {};

  List<GameMessage> get visible => _items.reversed.take(maxVisible).toList();

  void show(GameMessage m) {
    _items.add(m);
    _age[m.id] = 0;
    notifyListeners();
  }

  void close(int id) {
    _items.removeWhere((m) => m.id == id);
    _age.remove(id);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _age.clear();
    notifyListeners();
  }

  /// Ages the visible messages; called from the game loop.
  void tick(double dt) {
    final expired = <int>[];
    for (final m in visible) {
      final age = (_age[m.id] ?? 0) + dt;
      _age[m.id] = age;
      if (m.seconds != null && age >= m.seconds!) expired.add(m.id);
    }
    if (expired.isEmpty) return;
    _items.removeWhere((m) => expired.contains(m.id));
    expired.forEach(_age.remove);
    notifyListeners();
  }
}
