import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:bombario_core/bombario_core.dart';

import 'protocol.dart';

/// A connected (or briefly disconnected) player in a room.
class RoomClient {
  RoomClient(this.id, this._socket, this.token);

  final int id;
  WebSocket? _socket;

  /// Secret the client presents to resume after a dropped connection.
  final String token;

  String name = 'Player';
  bool ready = false;
  bool isHost = false;

  /// World player id while a match runs.
  int? playerId;

  /// Inputs waiting for the simulation, one consumed per tick. The client
  /// predicts one movement step per input it sends, so consuming exactly one
  /// per tick keeps the server and the client's prediction in step.
  final Queue<(int, PlayerInput)> _inputs = Queue();

  /// Inputs beyond this are dropped oldest-first so a burst after a stall
  /// doesn't leave the player lagging behind their own thumb.
  static const int maxQueuedInputs = 6;

  int _lastQueuedSeq = 0;

  /// Sequence number of the last input the simulation consumed, echoed in
  /// snapshots so the client can reconcile its prediction.
  int lastInputSeq = 0;

  bool get connected => _socket?.readyState == WebSocket.open;

  void queueInput(int? seq, PlayerInput input) {
    final s = seq ?? _lastQueuedSeq + 1;
    if (s <= _lastQueuedSeq) return; // duplicate or reordered
    _lastQueuedSeq = s;
    _inputs.add((s, input));
    while (_inputs.length > maxQueuedInputs) {
      final (_, dropped) = _inputs.removeFirst();
      // A dropped step may carry a bomb press; never lose that.
      final (nextSeq, next) = _inputs.removeFirst();
      _inputs.addFirst((
        nextSeq,
        PlayerInput(
          direction: next.direction,
          placeBomb: next.placeBomb || dropped.placeBomb,
          action: next.action || dropped.action,
        ),
      ));
    }
  }

  /// Next input for the simulation. With nothing queued the player stands
  /// still rather than guessing, which keeps reconciliation exact.
  PlayerInput takeInput() {
    if (_inputs.isEmpty) return const PlayerInput();
    final (seq, input) = _inputs.removeFirst();
    lastInputSeq = seq;
    return input;
  }

  void resetInputs() {
    _inputs.clear();
    _lastQueuedSeq = 0;
    lastInputSeq = 0;
  }

  void send(Map<String, dynamic> message) {
    if (connected) _socket!.add(encode(message));
  }

  LobbyPlayer get lobbyRow => LobbyPlayer(
        id: id,
        name: name,
        ready: ready,
        isHost: isHost,
        connected: connected,
      );
}

enum RoomState { lobby, playing }

/// Lobby plus match loop. Authoritative: clients only ever send inputs.
class Room {
  Room({int? seed, this.maxPlayers = defaultMaxPlayers})
      : _rng = Random(seed),
        code = _makeCode(Random(seed));

  static const int defaultMaxPlayers = 4;

  /// Snapshots go out every [snapshotEvery] ticks (15 Hz at a 30 Hz tick).
  static const int snapshotEvery = 2;

  /// How long a dropped player may reconnect before they are removed.
  static const Duration resumeWindow = Duration(seconds: 20);

  /// How long a new socket may take to send `join`.
  static const Duration joinTimeout = Duration(seconds: 10);

  final int maxPlayers;
  final String code;
  final Random _rng;
  final List<RoomClient> clients = [];
  final Map<RoomClient, Timer> _resumeTimers = {};

  GameMode mode = GameMode.versus;
  RoomState state = RoomState.lobby;
  World? world;
  Timer? _ticker;
  int _tick = 0;
  int _nextClientId = 1;

  /// Hooks for the hub's empty-room expiry.
  void Function()? onEmpty;
  void Function()? onOccupied;

  /// Fired when a match ends, after the `matchEnd` message went out.
  final StreamController<World> _matchEnded = StreamController.broadcast();
  Stream<World> get onMatchEnded => _matchEnded.stream;

  // Room codes avoid letters that read like digits.
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static String _makeCode(Random rng) => List.generate(
        6,
        (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)],
      ).join();

  String _makeToken() => List.generate(
        24,
        (_) => _codeAlphabet[_rng.nextInt(_codeAlphabet.length)],
      ).join();

  void accept(WebSocket socket) {
    // A WebSocket can only be listened to once, so one subscription lives as
    // long as the socket. Until `join` arrives it has no client; the first
    // `join` decides whether this is a new player or a resume.
    RoomClient? owner;
    final hello = Timer(joinTimeout, () {
      if (owner == null) socket.close();
    });
    socket.listen(
      (frame) {
        final msg = decode(frame);
        final client = owner;
        if (client != null) {
          _handle(client, msg);
          return;
        }
        if (msg == null || msg['t'] != Msg.join) return;
        hello.cancel();
        final token = msg['token'] as String?;
        owner = (token == null ? null : _tryResume(token, socket)) ??
            _admit(socket);
        if (owner != null) _handle(owner!, msg);
      },
      onDone: () {
        hello.cancel();
        final client = owner;
        if (client != null) _detach(client, socket);
      },
      onError: (_) {
        hello.cancel();
        final client = owner;
        if (client != null) _detach(client, socket);
      },
    );
  }

  RoomClient? _tryResume(String token, WebSocket socket) {
    for (final c in clients) {
      if (c.token != token) continue;
      _resumeTimers.remove(c)?.cancel();
      // The old socket may be half-open (the phone switched networks before
      // the server noticed). The new one wins; [_detach] ignores the old.
      final old = c._socket;
      c._socket = socket;
      old?.close();
      c.send({
        't': Msg.welcome,
        'id': c.id,
        'code': code,
        'host': c.isHost,
        'token': c.token,
        'resumed': true,
      });
      _broadcastLobby();
      final w = world;
      if (state == RoomState.playing && w != null && c.playerId != null) {
        c.send({'t': Msg.matchStart, 'mode': mode.name, 'you': c.playerId});
        _sendSnapshot(w);
        // Back from the dead-zone: a moment of protection while they catch up.
        w.playerById(c.playerId!)?.invincibleFor = 2;
      }
      return c;
    }
    return null;
  }

  /// Admits a new player, or refuses with an error and returns null.
  RoomClient? _admit(WebSocket socket) {
    if (clients.length >= maxPlayers || state != RoomState.lobby) {
      socket.add(encode({
        't': Msg.error,
        'm': state != RoomState.lobby ? 'Match in progress' : 'Room is full',
      }));
      socket.close();
      return null;
    }
    final client = RoomClient(_nextClientId++, socket, _makeToken());
    client.isHost = clients.isEmpty;
    clients.add(client);
    if (clients.length == 1) onOccupied?.call();
    client.send({
      't': Msg.welcome,
      'id': client.id,
      'code': code,
      'host': client.isHost,
      'token': client.token,
    });
    return client;
  }

  void _handle(RoomClient client, Map<String, dynamic>? msg) {
    if (msg == null) return;
    switch (msg['t']) {
      case Msg.join:
        final name = (msg['name'] as String? ?? '').trim();
        client.name = name.isEmpty ? 'Player ${client.id}' : name;
        _broadcastLobby();
      case Msg.ready:
        client.ready = msg['v'] == true;
        _broadcastLobby();
      case Msg.mode:
        if (!client.isHost || state != RoomState.lobby) return;
        mode = GameMode.parse(msg['v'] as String? ?? '');
        _broadcastLobby();
      case Msg.start:
        if (!client.isHost || state != RoomState.lobby) return;
        if (clients.length < 2 && mode == GameMode.versus) {
          client.send({'t': Msg.error, 'm': 'Versus needs at least 2 players'});
          return;
        }
        startMatch();
      case Msg.input:
        if (state != RoomState.playing) return;
        client.queueInput(msg['s'] as int?, inputFromJson(msg));
      case Msg.leave:
        _remove(client);
    }
  }

  /// Socket closed. Mid-match the seat is held for [resumeWindow]; in the
  /// lobby the player simply leaves.
  void _detach(RoomClient client, WebSocket socket) {
    if (client._socket != socket) return; // an old socket of a resumed client
    client._socket = null;
    if (!clients.contains(client)) return;
    final w = world;
    if (state == RoomState.playing && w != null && client.playerId != null) {
      client._inputs.clear();
      w.playerById(client.playerId!)?.invincibleFor =
          resumeWindow.inSeconds.toDouble();
      _resumeTimers[client] = Timer(resumeWindow, () => _remove(client));
      _broadcastLobby();
    } else {
      _remove(client);
    }
  }

  void _remove(RoomClient client) {
    _resumeTimers.remove(client)?.cancel();
    if (!clients.remove(client)) return;
    client._socket?.close();
    client._socket = null;
    if (client.isHost && clients.isNotEmpty) clients.first.isHost = true;
    final w = world;
    if (state == RoomState.playing && w != null && client.playerId != null) {
      // A player who leaves mid-match is out. The sim will end the round if
      // that leaves one survivor.
      final p = w.playerById(client.playerId!);
      if (p != null && p.alive) {
        p.alive = false;
        p.invincibleFor = 0;
      }
    }
    if (clients.isEmpty) {
      _stopMatch();
      onEmpty?.call();
    } else {
      _broadcastLobby();
    }
  }

  void _broadcastLobby() {
    final msg = {
      't': Msg.lobby,
      'mode': mode.name,
      'players': [for (final c in clients) c.lobbyRow.toJson()],
    };
    for (final c in clients) {
      c.send(msg);
    }
  }

  /// Builds the stage and starts ticking. Public so tests and the host UI
  /// can start without a socket round-trip.
  void startMatch() {
    final seed = _rng.nextInt(1 << 30);
    final LevelData level;
    if (mode == GameMode.versus) {
      // Single-screen arena, no enemies, plenty of items under the bricks.
      level = LevelData.generate(
        seed: seed,
        width: 15,
        height: 13,
        players: clients.length,
        enemyCount: 0,
        brickDensity: 0.55,
        items: const [
          ItemType.bombUp,
          ItemType.fireUp,
          ItemType.speedUp,
          ItemType.remote,
        ],
        timeLimit: 120,
      );
    } else {
      level = LevelData.generate(
        seed: seed,
        width: clients.length <= 2 ? 31 : 41,
        height: clients.length <= 2 ? 13 : 17,
        players: clients.length,
        enemyCount: 6 + 2 * clients.length,
        brickDensity: 0.45,
        enemyKinds: const [EnemyKind.puffball, EnemyKind.blueDrop],
        timeLimit: 240,
      );
    }
    final w = World(level, seed: seed, config: mode.config);
    for (final c in clients) {
      c.playerId = w.addPlayer(name: c.name).id;
      c.resetInputs();
    }
    world = w;
    state = RoomState.playing;
    _tick = 0;
    for (final c in clients) {
      c.send({'t': Msg.matchStart, 'mode': mode.name, 'you': c.playerId});
    }
    _sendSnapshot(w);
    _ticker = Timer.periodic(
      Duration(microseconds: (World.tickDt * 1e6).round()),
      (_) => tick(),
    );
  }

  /// One simulation step. Public so tests can drive the room without a timer.
  void tick() {
    final w = world;
    if (w == null || state != RoomState.playing) return;
    final inputs = <int, PlayerInput>{
      for (final c in clients)
        if (c.playerId != null) c.playerId!: c.takeInput(),
    };
    w.tick(inputs);
    _tick++;
    if (_tick % snapshotEvery == 0 || w.over) _sendSnapshot(w);
    if (w.over) {
      for (final c in clients) {
        c.send({
          't': Msg.matchEnd,
          if (w.winnerId != null) 'winner': w.winnerId,
          'cleared': w.cleared,
        });
      }
      _stopMatch();
      _matchEnded.add(w);
    }
  }

  void _sendSnapshot(World w) {
    final acked = {
      for (final c in clients)
        if (c.playerId != null) c.playerId!: c.lastInputSeq,
    };
    final json = WorldSnapshot.of(w, tick: _tick, ackedInputs: acked).toJson()
      ..['t'] = Msg.snapshot;
    for (final c in clients) {
      c.send(json);
    }
  }

  void _stopMatch() {
    _ticker?.cancel();
    _ticker = null;
    state = RoomState.lobby;
    for (final c in clients.toList()) {
      c.ready = false;
      c.playerId = null;
      // Nobody waits for a dropped player once the match is over.
      if (!c.connected) _remove(c);
    }
    if (clients.isNotEmpty) _broadcastLobby();
  }

  Future<void> close() async {
    _ticker?.cancel();
    for (final t in _resumeTimers.values) {
      t.cancel();
    }
    _resumeTimers.clear();
    for (final c in clients.toList()) {
      await c._socket?.close();
    }
    clients.clear();
    if (!_matchEnded.isClosed) await _matchEnded.close();
  }
}
