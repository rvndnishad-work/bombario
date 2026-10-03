import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bombario_core/bombario_core.dart';

import 'protocol.dart';

/// A WebSocket server hosting one [Room].
///
/// `await RoomServer.start()` binds a port (0 picks a free one); clients
/// connect to `ws://<host>:<port>/` and send a `join`. The first player to
/// join is the host and controls mode and start. For local Wi-Fi play the
/// hosting phone runs this in-process and joins its own room over loopback.
class RoomServer {
  RoomServer._(this._http, this.room);

  final HttpServer _http;
  final Room room;

  int get port => _http.port;
  InternetAddress get address => _http.address;

  static Future<RoomServer> start({
    int port = 0,
    InternetAddress? address,
    int? seed,
    int maxPlayers = Room.defaultMaxPlayers,
  }) async {
    final http =
        await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    final room = Room(seed: seed, maxPlayers: maxPlayers);
    final server = RoomServer._(http, room);
    http.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response
          ..statusCode = HttpStatus.upgradeRequired
          ..write('Bombario room ${room.code}: connect with a WebSocket')
          ..close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(req);
      room.accept(socket);
    });
    return server;
  }

  Future<void> close() async {
    await room.close();
    await _http.close(force: true);
  }
}

/// A connected player in the lobby.
class RoomClient {
  RoomClient(this.id, this._socket);

  final int id;
  final WebSocket _socket;
  String name = 'Player';
  bool ready = false;
  bool isHost = false;

  /// World player id while a match runs.
  int? playerId;

  /// Latest held direction and any bomb/action presses since the last tick.
  Direction held = Direction.none;
  bool bombPressed = false;
  bool actionPressed = false;

  PlayerInput takeInput() {
    final input = PlayerInput(
      direction: held,
      placeBomb: bombPressed,
      action: actionPressed,
    );
    bombPressed = false;
    actionPressed = false;
    return input;
  }

  void send(Map<String, dynamic> message) {
    if (_socket.readyState == WebSocket.open) _socket.add(encode(message));
  }

  LobbyPlayer get lobbyRow =>
      LobbyPlayer(id: id, name: name, ready: ready, isHost: isHost);
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

  final int maxPlayers;
  final String code;
  final Random _rng;
  final List<RoomClient> clients = [];

  GameMode mode = GameMode.versus;
  RoomState state = RoomState.lobby;
  World? world;
  Timer? _ticker;
  int _tick = 0;
  int _nextClientId = 1;

  /// Fired when a match ends, after the `matchEnd` message went out.
  final StreamController<World> _matchEnded = StreamController.broadcast();
  Stream<World> get onMatchEnded => _matchEnded.stream;

  // Room codes avoid letters that read like digits.
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static String _makeCode(Random rng) => List.generate(
        6,
        (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)],
      ).join();

  void accept(WebSocket socket) {
    if (clients.length >= maxPlayers || state != RoomState.lobby) {
      socket.add(encode({
        't': Msg.error,
        'm': state != RoomState.lobby ? 'Match in progress' : 'Room is full',
      }));
      socket.close();
      return;
    }
    final client = RoomClient(_nextClientId++, socket);
    client.isHost = clients.isEmpty;
    clients.add(client);
    client.send({
      't': Msg.welcome,
      'id': client.id,
      'code': code,
      'host': client.isHost,
    });
    _broadcastLobby();
    socket.listen(
      (frame) => _handle(client, decode(frame)),
      onDone: () => _drop(client),
      onError: (_) => _drop(client),
    );
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
        final input = inputFromJson(msg);
        client.held = input.direction;
        client.bombPressed |= input.placeBomb;
        client.actionPressed |= input.action;
    }
  }

  void _drop(RoomClient client) {
    if (!clients.remove(client)) return;
    if (client.isHost && clients.isNotEmpty) clients.first.isHost = true;
    final w = world;
    if (state == RoomState.playing && w != null && client.playerId != null) {
      // A player who leaves mid-match is out. The sim will end the round if
      // that leaves one survivor.
      final p = w.playerById(client.playerId!);
      if (p != null && p.alive) p.alive = false;
    }
    if (clients.isEmpty) {
      _stopMatch();
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
      c.held = Direction.none;
      c.bombPressed = false;
      c.actionPressed = false;
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
    final json = WorldSnapshot.of(w, tick: _tick).toJson()
      ..['t'] = Msg.snapshot;
    for (final c in clients) {
      c.send(json);
    }
  }

  void _stopMatch() {
    _ticker?.cancel();
    _ticker = null;
    state = RoomState.lobby;
    for (final c in clients) {
      c.ready = false;
      c.playerId = null;
    }
    if (clients.isNotEmpty) _broadcastLobby();
  }

  Future<void> close() async {
    _ticker?.cancel();
    for (final c in clients.toList()) {
      await c._socket.close();
    }
    clients.clear();
    await _matchEnded.close();
  }
}
