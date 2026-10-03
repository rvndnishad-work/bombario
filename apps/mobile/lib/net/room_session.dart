import 'dart:async';
import 'dart:io';

import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
import 'package:flutter/foundation.dart';

import 'discovery.dart';

/// Where a networked session stands, from the UI's point of view.
enum SessionPhase { connecting, lobby, playing, ended, disconnected }

/// One player's connection to a room, hosted here or elsewhere.
///
/// Wraps [GameClient] (and [RoomServer] + a Bonjour broadcast when hosting)
/// in a [ChangeNotifier] the screens can listen to.
class RoomSession extends ChangeNotifier {
  RoomSession._(this._client, this._server, this._broadcast);

  final GameClient _client;
  final RoomServer? _server;
  final RoomBroadcast? _broadcast;
  StreamSubscription<Map<String, dynamic>>? _sub;

  SessionPhase phase = SessionPhase.connecting;
  String? error;

  bool get isHosting => _server != null;
  bool get isHost => _client.isHost;
  String? get code => _client.code;
  LobbyState get lobby => _client.lobby;
  GameMode get mode => _client.lobby.mode;
  int? get myPlayerId => _client.myPlayerId;
  WorldSnapshot? get snapshot => _client.snapshot;
  int? get lastWinner => _client.lastWinner;
  bool get lastCleared => _client.lastCleared;

  /// Host address players on the same Wi-Fi can type in, e.g. 192.168.1.4:40123.
  String? hostAddress;

  /// Starts a room on this device and joins it over loopback.
  static Future<RoomSession> host({required String playerName}) async {
    final server = await RoomServer.start();
    final broadcast = RoomBroadcast(code: server.room.code, port: server.port);
    await broadcast.start();
    final client = await GameClient.connect('127.0.0.1', server.port);
    final session = RoomSession._(client, server, broadcast);
    session.hostAddress = '${await _localIPv4()}:${server.port}';
    session._attach(playerName);
    return session;
  }

  /// Joins a room hosted on another device.
  static Future<RoomSession> join({
    required String host,
    required int port,
    required String playerName,
  }) async {
    final client = await GameClient.connect(host, port);
    final session = RoomSession._(client, null, null);
    session.hostAddress = '$host:$port';
    session._attach(playerName);
    return session;
  }

  void _attach(String playerName) {
    _sub = _client.messages.listen(_onMessage);
    _client.closed.then((_) {
      if (phase != SessionPhase.disconnected) {
        phase = SessionPhase.disconnected;
        notifyListeners();
      }
    });
    _client.join(playerName);
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
        error = msg['m'] as String?;
    }
    notifyListeners();
  }

  void setReady(bool ready) => _client.setReady(ready);
  void setMode(GameMode m) => _client.setMode(m);
  void start() => _client.start();
  void sendInput(PlayerInput input) => _client.sendInput(input);

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
    await _sub?.cancel();
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
