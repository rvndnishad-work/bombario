import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
import 'package:flutter/foundation.dart';

import 'discovery.dart';
import '../progress/cosmetics.dart';
import 'online.dart';

/// Where a networked session stands, from the UI's point of view.
enum SessionPhase {
  connecting,
  lobby,
  playing,
  ended,

  /// The connection dropped and the session is trying to get the seat back.
  reconnecting,
  disconnected,
}

/// One player's connection to a room: hosted on this phone, on another
/// phone on the same Wi-Fi, or on the online server.
///
/// Wraps [GameClient] (and [RoomServer] + a Bonjour broadcast when hosting)
/// in a [ChangeNotifier] the screens can listen to, and reconnects on its
/// own when the connection drops.
class RoomSession extends ChangeNotifier {
  RoomSession._(
    this._client,
    this._server,
    this._broadcast, {
    this.online = false,
  });

  final GameClient _client;
  final RoomServer? _server;
  final RoomBroadcast? _broadcast;
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _dropSub;
  bool _leaving = false;

  /// How long to keep trying after a drop. The server holds a seat for 20 s.
  static const Duration reconnectFor = Duration(seconds: 18);

  SessionPhase phase = SessionPhase.connecting;
  String? error;

  /// True for rooms on the online server (joined by code).
  final bool online;

  bool get isHosting => _server != null;
  bool get isHost => _client.isHost;
  int? get clientId => _client.clientId;
  String? get code => _client.code;
  LobbyState get lobby => _client.lobby;
  GameMode get mode => _client.lobby.mode;
  int? get myPlayerId => _client.myPlayerId;
  WorldSnapshot? get snapshot => _client.snapshot;
  int? get lastWinner => _client.lastWinner;
  bool get lastCleared => _client.lastCleared;

  /// Co-op campaign: the stage picked in the lobby, and while playing the
  /// stage's name and tip; after a clear, the stage that comes next.
  String get lobbyStage => _client.lobby.stage;
  String? get stageId => _client.stageId;
  String? get stageName => _client.stageName;
  String? get stageTip => _client.stageTip;
  String? get nextStage => _client.nextStage;

  /// The local player as predicted on this device: it moves the moment the
  /// stick moves, then reconciles with the server.
  PlayerState? get me => _client.me;

  /// Host address players on the same Wi-Fi can type in, e.g. 192.168.1.4:40123.
  String? hostAddress;

  /// Starts a room on this device and joins it over loopback.
  static Future<RoomSession> host({
    required String playerName,
    String skin = 'classic',
  }) async {
    final server = await RoomServer.start(
      botSkins: [for (final s in Cosmetics.skins) s.id],
    );
    final broadcast = RoomBroadcast(code: server.room.code, port: server.port);
    await broadcast.start();
    final client = await GameClient.connectLocal(
      '127.0.0.1',
      server.port,
      playerName: playerName,
      skin: skin,
    );
    final session = RoomSession._(client, server, broadcast);
    session.hostAddress = '${await _localIPv4()}:${server.port}';
    session._attach();
    return session;
  }

  /// Joins a room hosted on another device.
  static Future<RoomSession> join({
    required String host,
    required int port,
    required String playerName,
    String skin = 'classic',
  }) async {
    final client = await GameClient.connectLocal(
      host,
      port,
      playerName: playerName,
      skin: skin,
    );
    final session = RoomSession._(client, null, null);
    session.hostAddress = '$host:$port';
    session._attach();
    return session;
  }

  /// Creates a room on the online server and joins it as host.
  static Future<RoomSession> createOnline({
    required Uri server,
    required String playerName,
    String skin = 'classic',
  }) async {
    final code = await OnlineServer.createRoom(server);
    return _connectOnline(server, code, playerName, skin);
  }

  /// Joins an online room by its code.
  static Future<RoomSession> joinOnline({
    required Uri server,
    required String code,
    required String playerName,
    String skin = 'classic',
  }) async {
    final c = OnlineServer.normalizeCode(code);
    await OnlineServer.checkRoom(server, c);
    return _connectOnline(server, c, playerName, skin);
  }

  static Future<RoomSession> _connectOnline(
    Uri server,
    String code,
    String playerName,
    String skin,
  ) async {
    final GameClient client;
    try {
      client = await GameClient.connect(
        OnlineServer.socketUri(server, code),
        playerName: playerName,
        skin: skin,
      );
    } on Exception catch (e) {
      throw OnlineException('Could not join room $code ($e)');
    }
    final session = RoomSession._(client, null, null, online: true);
    session._attach();
    return session;
  }

  /// Host only: fills a seat with a bot, or frees the last bot's seat.
  void addBot([BotSkill skill = BotSkill.normal]) =>
      _client.addBot(skill: skill);
  void removeBot([int? lobbyId]) => _client.removeBot(lobbyId);

  void _attach() {
    _sub = _client.messages.listen(_onMessage);
    _dropSub = _client.onDropped.listen((_) => _onDropped());
    if (_client.clientId != null) phase = SessionPhase.lobby;
  }

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['t']) {
      case Msg.welcome:
      case Msg.lobby:
        // The server returns to the lobby right after `matchEnd`; the
        // session stays in `ended` until the UI calls [backToLobby] so the
        // result card is seen.
        if (phase == SessionPhase.connecting) phase = SessionPhase.lobby;
      case Msg.matchStart:
        phase = SessionPhase.playing;
      case Msg.matchEnd:
        phase = SessionPhase.ended;
      case Msg.error:
        // Refusals while reconnecting are handled by the retry loop.
        if (phase != SessionPhase.reconnecting) error = msg['m'] as String?;
    }
    notifyListeners();
  }

  Future<void> _onDropped() async {
    if (_leaving ||
        phase == SessionPhase.disconnected ||
        phase == SessionPhase.reconnecting) {
      return;
    }
    final was = phase;
    phase = SessionPhase.reconnecting;
    notifyListeners();

    final deadline = DateTime.now().add(reconnectFor);
    var wait = const Duration(milliseconds: 250);
    while (!_leaving && DateTime.now().isBefore(deadline)) {
      if (await _client.reconnect(timeout: const Duration(seconds: 4))) {
        if (phase == SessionPhase.reconnecting) {
          // A resumed match re-sends `matchStart`, which already moved us to
          // `playing`. Anything else lands back in the lobby (or keeps the
          // result card up).
          phase = was == SessionPhase.ended
              ? SessionPhase.ended
              : SessionPhase.lobby;
        }
        notifyListeners();
        return;
      }
      // A clear refusal (room full, match moved on) won't change by retrying.
      if (_client.lastError != null) break;
      await Future<void>.delayed(wait);
      wait = Duration(milliseconds: math.min(wait.inMilliseconds * 2, 3000));
    }
    if (_leaving) return;
    phase = SessionPhase.disconnected;
    notifyListeners();
  }

  void setReady(bool ready) => _client.setReady(ready);
  void setMode(GameMode m) => _client.setMode(m);
  void setStage(String id) => _client.setStage(id);
  void start() => _client.start();
  void sendInput(PlayerInput input) => _client.sendInput(input);

  /// Simulates a lost connection. Used by tests.
  @visibleForTesting
  Future<void> dropConnection() => _client.drop();

  /// Leaves the end-of-match state once the result has been shown.
  void backToLobby() {
    if (phase == SessionPhase.ended) {
      phase = SessionPhase.lobby;
      notifyListeners();
    }
  }

  /// Clears a shown error.
  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> leave() async {
    if (_leaving) return;
    _leaving = true;
    await _sub?.cancel();
    await _dropSub?.cancel();
    await _client.close();
    await _broadcast?.stop();
    await _server?.close();
    phase = SessionPhase.disconnected;
  }

  @override
  void dispose() {
    leave();
    super.dispose();
  }

  static Future<String> _localIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      // Prefer Wi-Fi / hotspot style addresses over VPN or emulator ones.
      final all = [for (final i in interfaces) ...i.addresses];
      for (final a in all) {
        if (a.address.startsWith('192.168.') || a.address.startsWith('10.')) {
          return a.address;
        }
      }
      if (all.isNotEmpty) return all.first.address;
    } catch (_) {}
    return '127.0.0.1';
  }
}
