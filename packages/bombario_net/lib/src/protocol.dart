import 'dart:convert';

import 'package:bombario_core/bombario_core.dart';

/// Wire protocol: one JSON object per WebSocket text frame, with a `t` field
/// naming the message. JSON keeps Phase 1 debuggable; a binary encoding can
/// replace [encode]/[decode] later without changing the message shapes.
abstract final class Msg {
  // Client to server.
  static const join = 'join'; // {name, skin?, token?: resume a dropped seat}
  static const ready = 'ready'; // {v: bool}
  static const mode = 'mode'; // {v: 'versus' | 'coop'}  (host only)
  static const stage = 'stage'; // {v: '1-4'}  co-op stage (host only)
  static const start = 'start'; // (host only)
  static const input =
      'input'; // {s: seq, d: Direction index, b: bomb, a: action}
  static const leave = 'leave';
  static const skin = 'skin'; // {v: 'classic'}  cosmetic, any time
  static const addBot = 'addBot'; // {skill?: 'easy'|'normal'|'hard'} (host)
  static const removeBot = 'removeBot'; // {id?: lobby id, else the last bot}

  // Server to client.
  static const welcome = 'welcome'; // {id, code, host, token, resumed?}
  static const lobby = 'lobby'; // {mode, stage, quick?, startsIn?,
  //   players: [{id, name, ready, host, on, skin, bot?}]}
  static const matchStart =
      'matchStart'; // {mode, you: world player id, stage?, name?, tip?}
  static const snapshot = 'snap'; // WorldSnapshot.toJson() fields
  static const matchEnd = 'matchEnd'; // {winner?, cleared, stage?, next?}
  static const error = 'error'; // {m}
}

/// Game modes a room can run.
enum GameMode {
  versus,
  coop;

  WorldConfig get config => switch (this) {
        GameMode.versus => WorldConfig.versus,
        GameMode.coop => WorldConfig.coop,
      };

  static GameMode parse(String s) =>
      GameMode.values.firstWhere((m) => m.name == s, orElse: () => versus);
}

String encode(Map<String, dynamic> message) => jsonEncode(message);

Map<String, dynamic>? decode(Object? frame) {
  if (frame is! String) return null;
  try {
    final v = jsonDecode(frame);
    return v is Map<String, dynamic> && v['t'] is String ? v : null;
  } on FormatException {
    return null;
  }
}

Map<String, dynamic> inputToJson(PlayerInput input, {int seq = 0}) => {
      't': Msg.input,
      's': seq,
      'd': input.direction.index,
      'b': input.placeBomb,
      'a': input.action,
      if (input.ping != PingKind.none) 'g': input.ping.index,
    };

PlayerInput inputFromJson(Map<String, dynamic> j) => PlayerInput(
      direction: Direction.values[(j['d'] as int?)?.clamp(0, 4) ?? 0],
      placeBomb: j['b'] == true,
      action: j['a'] == true,
      ping: PingKind
          .values[(j['g'] as int?)?.clamp(0, PingKind.values.length - 1) ?? 0],
    );

/// One row of the lobby list as clients see it.
class LobbyPlayer {
  const LobbyPlayer({
    required this.id,
    required this.name,
    required this.ready,
    required this.isHost,
    this.connected = true,
    this.bot = false,
    this.skin = Player.defaultSkin,
  });

  final int id;
  final String name;
  final bool ready;
  final bool isHost;

  /// False while a player's connection dropped and their seat is held.
  final bool connected;

  /// A computer player the server drives. Always ready.
  final bool bot;

  /// Cosmetic look; the app decides which values it knows.
  final String skin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ready': ready,
        'host': isHost,
        'on': connected,
        'skin': skin,
        if (bot) 'bot': true,
      };

  static LobbyPlayer fromJson(Map<String, dynamic> j) => LobbyPlayer(
        id: j['id'] as int,
        name: j['name'] as String,
        ready: j['ready'] as bool,
        isHost: j['host'] as bool,
        connected: j['on'] as bool? ?? true,
        bot: j['bot'] as bool? ?? false,
        skin: j['skin'] as String? ?? Player.defaultSkin,
      );
}

class LobbyState {
  const LobbyState({
    this.mode = GameMode.versus,
    this.players = const [],
    this.stage = '1-1',
    this.quick = false,
    this.startsIn,
  });

  final GameMode mode;
  final List<LobbyPlayer> players;

  /// Co-op campaign stage the host picked, e.g. `1-4`.
  final String stage;

  /// A quick-match room: it starts by itself and fills empty seats with
  /// bots.
  final bool quick;

  /// Seconds until a quick-match room starts, while it counts down.
  final int? startsIn;

  Iterable<LobbyPlayer> get humans => players.where((p) => !p.bot);
  Iterable<LobbyPlayer> get bots => players.where((p) => p.bot);

  StageDef get stageDef => Campaign.byId(stage) ?? Campaign.first;

  bool get everyoneReady =>
      players.isNotEmpty && players.every((p) => p.ready || p.isHost);

  Map<String, dynamic> toJson() => {
        't': Msg.lobby,
        'mode': mode.name,
        'stage': stage,
        if (quick) 'quick': true,
        if (startsIn != null) 'startsIn': startsIn,
        'players': [for (final p in players) p.toJson()],
      };

  static LobbyState fromJson(Map<String, dynamic> j) => LobbyState(
        mode: GameMode.parse(j['mode'] as String),
        stage: j['stage'] as String? ?? '1-1',
        quick: j['quick'] as bool? ?? false,
        startsIn: j['startsIn'] as int?,
        players: [
          for (final p in j['players'] as List)
            LobbyPlayer.fromJson(p as Map<String, dynamic>),
        ],
      );
}
