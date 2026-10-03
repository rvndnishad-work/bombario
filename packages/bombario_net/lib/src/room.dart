import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:bombario_core/bombario_core.dart';

import 'protocol.dart';

/// A connected (or briefly disconnected) player in a room, or a bot seat.
class RoomClient {
  RoomClient(this.id, this._socket, this.token);

  /// A seat the server plays with a [Bot]. It has no socket and is always
  /// ready and connected.
  RoomClient.bot(this.id, this.botSkill)
      : _socket = null,
        token = '',
        ready = true;

  final int id;
  WebSocket? _socket;

  /// Secret the client presents to resume after a dropped connection.
  final String token;

  String name = 'Player';
  bool ready = false;
  bool isHost = false;

  /// Cosmetic look sent by the app (any string up to [maxSkinLength]).
  String skin = Player.defaultSkin;

  static const int maxSkinLength = 32;

  /// Set for bot seats: how well the bot plays.
  BotSkill? botSkill;
  bool get isBot => botSkill != null;

  /// The bot driving this seat while a match runs.
  Bot? bot;

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

  bool get connected => isBot || _socket?.readyState == WebSocket.open;

  void queueInput(int? seq, PlayerInput input) {
    final s = seq ?? _lastQueuedSeq + 1;
    if (s <= _lastQueuedSeq) return; // duplicate or reordered
    _lastQueuedSeq = s;
    _inputs.add((s, input));
    while (_inputs.length > maxQueuedInputs) {
      final (_, dropped) = _inputs.removeFirst();
      // A dropped step may carry a bomb press or ping; never lose that.
      final (nextSeq, next) = _inputs.removeFirst();
      _inputs.addFirst((
        nextSeq,
        PlayerInput(
          direction: next.direction,
          placeBomb: next.placeBomb || dropped.placeBomb,
          action: next.action || dropped.action,
          ping: next.ping != PingKind.none ? next.ping : dropped.ping,
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
    final socket = _socket; // bots have none
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(encode(message));
    }
  }

  LobbyPlayer get lobbyRow => LobbyPlayer(
        id: id,
        name: name,
        ready: ready,
        isHost: isHost,
        connected: connected,
        bot: isBot,
        skin: skin,
      );
}

enum RoomState { lobby, playing }

/// Lobby plus match loop. Authoritative: clients only ever send inputs.
class Room {
  Room({
    int? seed,
    this.maxPlayers = defaultMaxPlayers,
    this.quick = false,
    this.quickStartDelay = defaultQuickStartDelay,
    this.botSkins = const [Player.defaultSkin],
  })  : _rng = Random(seed),
        code = _makeCode(Random(seed));

  /// A quick-match room (§7.x): it starts [quickStartDelay] after its first
  /// human joins, or at once when every seat has a human, and fills empty
  /// seats with bots. Players can't change its mode or stage.
  final bool quick;
  final Duration quickStartDelay;

  /// Skins bots pick from at random. Not validated here; the app does.
  final List<String> botSkins;

  static const Duration defaultQuickStartDelay = Duration(seconds: 20);

  /// Quick matches: seats bots fill up to, by mode. Co-op pairs a lone
  /// player with one bot buddy rather than a full team of bots.
  static const int quickVersusSeats = 4;
  static const int quickCoopSeats = 2;

  static const botNames = [
    'Pip',
    'Bolt',
    'Fizz',
    'Nib',
    'Dot',
    'Zap',
    'Momo',
    'Rex',
  ];

  /// True once a quick-match room has started its first match; the hub
  /// stops sending new players to it.
  bool quickStarted = false;
  Timer? _autoStart;
  Timer? _countdown;
  DateTime? _startsAt;

  /// Seats promised by the hub to players who haven't connected yet.
  final List<DateTime> _reservations = [];
  static const Duration reservationTtl = Duration(seconds: 15);

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

  /// Seats held by people (not bots).
  Iterable<RoomClient> get humans => clients.where((c) => !c.isBot);
  Iterable<RoomClient> get bots => clients.where((c) => c.isBot);
  final Map<RoomClient, Timer> _resumeTimers = {};

  GameMode mode = GameMode.versus;

  /// Co-op campaign stage. Advances by itself when a stage is cleared.
  String stageId = Campaign.first.id;
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
        c.send(_matchStartMsg(c));
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
    // A person bumps a bot out of a full lobby.
    if (clients.length >= maxPlayers && state == RoomState.lobby) {
      final bot = bots.lastOrNull;
      if (bot != null) clients.remove(bot);
    }
    if (clients.length >= maxPlayers || state != RoomState.lobby) {
      socket.add(encode({
        't': Msg.error,
        'm': state != RoomState.lobby ? 'Match in progress' : 'Room is full',
      }));
      socket.close();
      return null;
    }
    final client = RoomClient(_nextClientId++, socket, _makeToken());
    client.isHost = humans.isEmpty;
    clients.add(client);
    if (_reservations.isNotEmpty) _reservations.removeAt(0);
    if (humans.length == 1) {
      onOccupied?.call();
      if (quick && !quickStarted) _scheduleQuickStart();
    }
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
        _setSkin(client, msg['skin']);
        _broadcastLobby();
        if (quick &&
            !quickStarted &&
            state == RoomState.lobby &&
            humans.length >= maxPlayers) {
          startQuickMatch();
        }
      case Msg.skin:
        _setSkin(client, msg['v']);
        _broadcastLobby();
      case Msg.addBot:
        if (!client.isHost || state != RoomState.lobby) return;
        if (addBot(skill: BotSkill.parse(msg['skill'] as String?)) == null) {
          client.send({'t': Msg.error, 'm': 'Room is full'});
        }
      case Msg.removeBot:
        if (!client.isHost || state != RoomState.lobby) return;
        removeBot(id: msg['id'] as int?);
      case Msg.ready:
        client.ready = msg['v'] == true;
        _broadcastLobby();
      case Msg.mode:
        if (!client.isHost || state != RoomState.lobby || quick) return;
        mode = GameMode.parse(msg['v'] as String? ?? '');
        _broadcastLobby();
      case Msg.stage:
        if (!client.isHost || state != RoomState.lobby || quick) return;
        final id = msg['v'] as String? ?? '';
        if (Campaign.byId(id) == null) return;
        stageId = id;
        _broadcastLobby();
      case Msg.start:
        if (!client.isHost || state != RoomState.lobby) return;
        if (clients.length < 2 && mode == GameMode.versus) {
          if (!quick) {
            client
                .send({'t': Msg.error, 'm': 'Versus needs at least 2 players'});
            return;
          }
        }
        quick ? startQuickMatch() : startMatch();
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
    if (client.isHost) {
      client.isHost = false;
      humans.firstOrNull?.isHost = true;
    }
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
    if (humans.isEmpty) {
      // Bots don't keep a room alive.
      clients.clear();
      _cancelQuickStart();
      _stopMatch();
      onEmpty?.call();
    } else {
      _broadcastLobby();
    }
  }

  void _setSkin(RoomClient client, Object? skin) {
    if (skin is! String) return;
    final s = skin.trim();
    if (s.isEmpty || s.length > RoomClient.maxSkinLength) return;
    client.skin = s;
  }

  /// Adds a bot seat in the lobby. Returns null when the room is full or a
  /// match is running.
  RoomClient? addBot({BotSkill skill = BotSkill.normal}) {
    if (clients.length >= maxPlayers || state != RoomState.lobby) return null;
    final taken = {for (final c in clients) c.name};
    final free = [
      for (final n in botNames)
        if (!taken.contains('Bot $n')) n,
    ];
    final name = free.isEmpty
        ? botNames[_rng.nextInt(botNames.length)]
        : free[_rng.nextInt(free.length)];
    final bot = RoomClient.bot(_nextClientId++, skill)
      ..name = 'Bot $name'
      ..skin = botSkins.isEmpty
          ? Player.defaultSkin
          : botSkins[_rng.nextInt(botSkins.length)];
    clients.add(bot);
    _broadcastLobby();
    return bot;
  }

  /// Removes the bot with lobby id [id], or the most recently added bot.
  bool removeBot({int? id}) {
    if (state != RoomState.lobby) return false;
    final bot = id == null
        ? bots.lastOrNull
        : bots.where((c) => c.id == id).firstOrNull;
    if (bot == null) return false;
    clients.remove(bot);
    _broadcastLobby();
    return true;
  }

  /// Free seats a quick match can still promise to new players.
  int get openQuickSeats {
    final now = DateTime.now();
    _reservations.removeWhere((t) => t.isBefore(now));
    return maxPlayers - humans.length - _reservations.length;
  }

  /// Can the hub send another player here?
  bool get acceptsQuickPlayers =>
      quick && !quickStarted && state == RoomState.lobby && openQuickSeats > 0;

  /// Holds a seat for a player the hub is sending here.
  void reserveSeat() => _reservations.add(DateTime.now().add(reservationTtl));

  /// Seconds until a quick match starts, while it counts down.
  int? get startsIn {
    final at = _startsAt;
    if (at == null) return null;
    final ms = at.difference(DateTime.now()).inMilliseconds;
    return max(0, (ms / 1000).ceil());
  }

  void _scheduleQuickStart() {
    _cancelQuickStart();
    _startsAt = DateTime.now().add(quickStartDelay);
    _autoStart = Timer(quickStartDelay, () {
      if (state == RoomState.lobby && !quickStarted && humans.isNotEmpty) {
        startQuickMatch();
      }
    });
    // A lobby update each second carries the countdown.
    _countdown =
        Timer.periodic(const Duration(seconds: 1), (_) => _broadcastLobby());
  }

  void _cancelQuickStart() {
    _autoStart?.cancel();
    _countdown?.cancel();
    _autoStart = null;
    _countdown = null;
    _startsAt = null;
  }

  /// Fills empty seats with bots (up to four for versus, two for co-op) and
  /// starts. Quick co-op plays stage 1-1: its friendly flames only stun,
  /// which suits strangers who have never played together.
  void startQuickMatch() {
    if (state != RoomState.lobby) return;
    _cancelQuickStart();
    quickStarted = true;
    final seats = min(
      maxPlayers,
      mode == GameMode.versus ? quickVersusSeats : quickCoopSeats,
    );
    while (clients.length < seats) {
      if (addBot() == null) break;
    }
    startMatch();
  }

  /// What the lobby looks like right now.
  LobbyState get lobby => LobbyState(
        mode: mode,
        stage: stageId,
        quick: quick,
        startsIn: state == RoomState.lobby ? startsIn : null,
        players: [for (final c in clients) c.lobbyRow],
      );

  void _broadcastLobby() {
    final msg = lobby.toJson();
    for (final c in clients) {
      c.send(msg);
    }
  }

  /// Builds the stage and starts ticking. Public so tests and the host UI
  /// can start without a socket round-trip.
  void startMatch() {
    final seed = _rng.nextInt(1 << 30);
    final LevelData level;
    var config = mode.config;
    final stage = Campaign.byId(stageId) ?? Campaign.first;
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
      level = stage.level(seed: seed, players: clients.length);
      config = stage.config(players: clients.length);
    }
    final w = World(level, seed: seed, config: config);
    for (final c in clients) {
      c.playerId = w.addPlayer(name: c.name, skin: c.skin).id;
      c.resetInputs();
      final skill = c.botSkill;
      c.bot = skill == null
          ? null
          : Bot(w, c.playerId!, skill: skill, seed: _rng.nextInt(1 << 30));
    }
    world = w;
    state = RoomState.playing;
    _tick = 0;
    for (final c in clients) {
      c.send(_matchStartMsg(c));
    }
    _sendSnapshot(w);
    _ticker = Timer.periodic(
      Duration(microseconds: (World.tickDt * 1e6).round()),
      (_) => tick(),
    );
  }

  Map<String, dynamic> _matchStartMsg(RoomClient c) {
    final stage = Campaign.byId(stageId) ?? Campaign.first;
    return {
      't': Msg.matchStart,
      'mode': mode.name,
      'you': c.playerId,
      if (mode == GameMode.coop) ...{
        'stage': stage.id,
        'name': stage.name,
        'tip': stage.tip,
      },
    };
  }

  /// One simulation step. Public so tests can drive the room without a timer.
  void tick() {
    final w = world;
    if (w == null || state != RoomState.playing) return;
    // Bots think on the server and queue their input like anyone else.
    for (final c in clients) {
      final bot = c.bot;
      if (bot != null) c.queueInput(null, bot.think());
    }
    final inputs = <int, PlayerInput>{
      for (final c in clients)
        if (c.playerId != null) c.playerId!: c.takeInput(),
    };
    w.tick(inputs);
    _tick++;
    if (_tick % snapshotEvery == 0 || w.over) _sendSnapshot(w);
    if (w.over) {
      final played = stageId;
      if (mode == GameMode.coop && w.cleared) {
        stageId = Campaign.next(stageId)?.id ?? stageId;
      }
      for (final c in clients) {
        c.send({
          't': Msg.matchEnd,
          if (w.winnerId != null) 'winner': w.winnerId,
          'cleared': w.cleared,
          if (mode == GameMode.coop) ...{
            'stage': played,
            if (w.cleared && Campaign.next(played) != null)
              'next': Campaign.next(played)!.id,
          },
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
      c.ready = c.isBot;
      c.playerId = null;
      c.bot = null;
      // Nobody waits for a dropped player once the match is over.
      if (!c.connected) _remove(c);
    }
    if (clients.isNotEmpty) _broadcastLobby();
  }

  Future<void> close() async {
    _ticker?.cancel();
    _cancelQuickStart();
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
