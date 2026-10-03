import 'dart:async';
import 'dart:io';

import 'package:bombario_core/bombario_core.dart';

import 'prediction.dart';
import 'protocol.dart';

/// Client side of the room protocol. Pure Dart; the app wraps it in
/// listenables for the UI.
///
/// Connects to a room URL (`ws://host:port/` for a phone-hosted room,
/// `wss://server/rooms/CODE` online), mirrors lobby and snapshot state, runs
/// [LocalPredictor] for the local player, and resumes the seat after a
/// dropped connection using the token the server handed out.
class GameClient {
  GameClient._(this.uri, this.playerName);

  final Uri uri;
  final String playerName;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;

  /// Everything the server sends, parsed, in order.
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Fires when the socket drops; [reconnect] may still succeed.
  final StreamController<void> _dropped = StreamController.broadcast();
  Stream<void> get onDropped => _dropped.stream;

  // State mirrored from the server.
  int? clientId;
  String? code;
  String? resumeToken;
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

  /// Co-op stage being played (from `matchStart`), and the one unlocked by
  /// clearing it (from `matchEnd`).
  String? stageId;
  String? stageName;
  String? stageTip;
  String? nextStage;

  final LocalPredictor predictor = LocalPredictor();

  bool get connected => _socket?.readyState == WebSocket.open;

  /// Opens the socket and sends `join`. Throws on connection failure.
  static Future<GameClient> connect(
    Uri uri, {
    required String playerName,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = GameClient._(uri, playerName);
    await client._open(timeout);
    return client;
  }

  /// Convenience for phone-hosted rooms.
  static Future<GameClient> connectLocal(String host, int port,
          {required String playerName}) =>
      connect(Uri.parse('ws://$host:$port/'), playerName: playerName);

  Future<void> _open(Duration timeout) async {
    final socket = await WebSocket.connect(uri.toString()).timeout(timeout);
    _socket = socket;
    _sub = socket.listen(
      (frame) => _handle(decode(frame)),
      onDone: _onSocketDone,
      onError: (_) => _onSocketDone(),
    );
    _send({
      't': Msg.join,
      'name': playerName,
      if (resumeToken != null) 'token': resumeToken,
    });
  }

  void _onSocketDone() {
    _socket = null;
    if (!_dropped.isClosed) _dropped.add(null);
  }

  /// True when the last [reconnect] got the same seat back.
  bool lastResumed = false;

  /// Reconnects after a drop. Mid-match the server gives the same seat back
  /// ([lastResumed]); in the lobby it may admit this player afresh. Returns
  /// false when the room is gone, full, or the match moved on without us.
  Future<bool> reconnect(
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (connected) return true;
    await _sub?.cancel();
    _sub = null;
    lastError = null;
    final reply = messages
        .firstWhere((m) => m['t'] == Msg.welcome || m['t'] == Msg.error)
        .timeout(timeout, onTimeout: () => const {'t': 'timeout'});
    try {
      await _open(timeout);
    } catch (_) {
      reply.ignore();
      return false;
    }
    final welcome = await reply;
    lastResumed = welcome['resumed'] == true;
    return welcome['t'] == Msg.welcome;
  }

  void _handle(Map<String, dynamic>? msg) {
    if (msg == null) return;
    switch (msg['t']) {
      case Msg.welcome:
        clientId = msg['id'] as int;
        code = msg['code'] as String;
        isHost = msg['host'] == true;
        resumeToken = msg['token'] as String? ?? resumeToken;
      case Msg.lobby:
        lobby = LobbyState.fromJson(msg);
        isHost = lobby.players.any((p) => p.id == clientId && p.isHost);
      case Msg.matchStart:
        myPlayerId = msg['you'] as int;
        mode = GameMode.parse(msg['mode'] as String);
        stageId = msg['stage'] as String?;
        stageName = msg['name'] as String?;
        stageTip = msg['tip'] as String?;
        lastWinner = null;
        lastCleared = false;
        nextStage = null;
        snapshot = null;
        predictor.reset();
      case Msg.snapshot:
        final snap = WorldSnapshot.fromJson(msg);
        snapshot = snap;
        final me = myPlayerId;
        if (me != null) predictor.onSnapshot(snap, me);
      case Msg.matchEnd:
        lastWinner = msg['winner'] as int?;
        lastCleared = msg['cleared'] == true;
        nextStage = msg['next'] as String?;
      case Msg.error:
        lastError = msg['m'] as String?;
    }
    _messages.add(msg);
  }

  void _send(Map<String, dynamic> msg) {
    if (connected) _socket!.add(encode(msg));
  }

  void setReady(bool ready) => _send({'t': Msg.ready, 'v': ready});
  void setMode(GameMode m) => _send({'t': Msg.mode, 'v': m.name});
  void setStage(String id) => _send({'t': Msg.stage, 'v': id});
  void start() => _send({'t': Msg.start});

  /// Call once per simulation tick (30 Hz) while playing. The input is
  /// predicted locally and sent with its sequence number; the server consumes
  /// one per tick, so every input must go out, idle ones included.
  void sendInput(PlayerInput input) {
    final seq = predictor.apply(input);
    _send(inputToJson(input, seq: seq));
  }

  /// Predicted position of the local player, falling back to the snapshot.
  PlayerState? get me {
    final snap = snapshot;
    final id = myPlayerId;
    if (snap == null || id == null) return null;
    final server = snap.player(id);
    final body = predictor.body;
    if (server == null || body == null) return server;
    return server.copyWith(x: body.x, y: body.y, facing: body.facing);
  }

  /// Drops the socket without leaving, as a lost connection would. The seat
  /// stays held on the server and [reconnect] can resume it.
  Future<void> drop() async {
    await _sub?.cancel();
    _sub = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    if (!_dropped.isClosed) _dropped.add(null);
  }

  Future<void> close() async {
    _send({'t': Msg.leave});
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
    await _messages.close();
    await _dropped.close();
  }
}
