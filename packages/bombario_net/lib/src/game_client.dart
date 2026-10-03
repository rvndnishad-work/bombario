import 'dart:async';
import 'dart:io';

import 'package:bombario_core/bombario_core.dart';

import 'protocol.dart';

/// Client side of the room protocol. Pure Dart; the app wraps it in
/// listenables for the UI.
class GameClient {
  GameClient._(this._socket) {
    _socket.listen(
      (frame) => _handle(decode(frame)),
      onDone: () => _closed.complete(),
      onError: (_) => _closed.complete(),
    );
  }

  final WebSocket _socket;
  final Completer<void> _closed = Completer();

  /// Everything the server sends, parsed, in order.
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  // State mirrored from the server.
  int? clientId;
  String? code;
  bool isHost = false;
  LobbyState lobby = const LobbyState();
  int? myPlayerId;
  GameMode? mode;
  WorldSnapshot? snapshot;
  String? lastError;

  /// Winner of the last versus round (-1 draw), or null when a co-op stage
  /// ended; reset at the next `matchStart`.
  int? lastWinner;
  bool lastCleared = false;

  Future<void> get closed => _closed.future;
  bool get connected => _socket.readyState == WebSocket.open;

  static Future<GameClient> connect(String host, int port,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final socket =
        await WebSocket.connect('ws://$host:$port/').timeout(timeout);
    return GameClient._(socket);
  }

  void _handle(Map<String, dynamic>? msg) {
    if (msg == null) return;
    switch (msg['t']) {
      case Msg.welcome:
        clientId = msg['id'] as int;
        code = msg['code'] as String;
        isHost = msg['host'] == true;
      case Msg.lobby:
        lobby = LobbyState.fromJson(msg);
        isHost = lobby.players.any((p) => p.id == clientId && p.isHost);
      case Msg.matchStart:
        myPlayerId = msg['you'] as int;
        mode = GameMode.parse(msg['mode'] as String);
        lastWinner = null;
        lastCleared = false;
        snapshot = null;
      case Msg.snapshot:
        snapshot = WorldSnapshot.fromJson(msg);
      case Msg.matchEnd:
        lastWinner = msg['winner'] as int?;
        lastCleared = msg['cleared'] == true;
      case Msg.error:
        lastError = msg['m'] as String?;
    }
    _messages.add(msg);
  }

  void _send(Map<String, dynamic> msg) {
    if (connected) _socket.add(encode(msg));
  }

  void join(String name) => _send({'t': Msg.join, 'name': name});
  void setReady(bool ready) => _send({'t': Msg.ready, 'v': ready});
  void setMode(GameMode m) => _send({'t': Msg.mode, 'v': m.name});
  void start() => _send({'t': Msg.start});

  PlayerInput? _lastSent;
  int _sinceLastSend = 0;

  /// Call once per client tick. Sends only when something changed, plus a
  /// heartbeat every half second so the server never holds a stale direction.
  void sendInput(PlayerInput input) {
    final last = _lastSent;
    final changed = last == null ||
        last.direction != input.direction ||
        input.placeBomb ||
        input.action;
    _sinceLastSend++;
    if (changed || _sinceLastSend >= 15) {
      _send(inputToJson(input));
      _lastSent = input;
      _sinceLastSend = 0;
    }
  }

  Future<void> close() async {
    await _socket.close();
    await _messages.close();
  }
}
