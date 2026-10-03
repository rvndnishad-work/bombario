import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
import 'package:test/test.dart';

/// Polls [condition] until it holds. Message streams can deliver before a
/// listener is attached, so tests wait on mirrored state instead.
Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<GameClient> connect(RoomServer server, [String name = 'P']) async {
  final c =
      await GameClient.connectLocal('127.0.0.1', server.port, playerName: name);
  await waitFor(() => c.clientId != null || c.lastError != null);
  return c;
}

Future<(int, Map<String, dynamic>)> http(
    String method, RoomServer server, String path) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${server.port}$path'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (res.statusCode, jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late RoomServer server;

  setUp(() async {
    server = await RoomServer.start(seed: 1);
  });

  tearDown(() => server.close());

  test('first client is host, lobby updates as players join and ready up',
      () async {
    final a = await connect(server, 'Alice');
    expect(a.isHost, isTrue);
    expect(a.code!.length, 6);
    expect(a.resumeToken, isNotNull);
    await waitFor(() => a.lobby.players.any((p) => p.name == 'Alice'));
    expect(a.lobby.players.single.isHost, isTrue);

    final b = await connect(server, 'Bob');
    expect(b.isHost, isFalse);
    expect(b.code, a.code);
    b.setReady(true);
    await waitFor(() => a.lobby.players.any((p) => p.name == 'Bob' && p.ready));
    expect(a.lobby.players.map((p) => p.name), containsAll(['Alice', 'Bob']));
    expect(a.lobby.everyoneReady, isTrue);

    await a.close();
    await b.close();
  });

  test('only the host can start, and versus needs two players', () async {
    final a = await connect(server);
    a.start();
    await waitFor(() => a.lastError != null);
    expect(a.lastError, contains('2 players'));

    final b = await connect(server);
    b.start(); // not the host: ignored
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.room.state, RoomState.lobby);

    await a.close();
    await b.close();
  });

  test(
      'a versus match streams snapshots, applies inputs and ends with a winner',
      () async {
    final a = await connect(server, 'Alice');
    final b = await connect(server, 'Bob');
    await waitFor(() => a.lobby.players.length == 2);

    a.start();
    await waitFor(() => a.myPlayerId != null && b.myPlayerId != null);
    expect(b.myPlayerId, isNot(a.myPlayerId));
    expect(a.mode, GameMode.versus);

    // Snapshots flow at ~15 Hz.
    await waitFor(() => (a.snapshot?.tick ?? 0) >= 4);
    final first = a.snapshot!;
    expect(first.players.length, 2);
    expect(first.enemies, isEmpty);
    expect(first.grid.width, 15);

    // Alice holds right for a while and must have moved, on the server and
    // in her own prediction.
    final before = first.player(a.myPlayerId!)!.x;
    for (var i = 0; i < 20; i++) {
      a.sendInput(const PlayerInput(direction: Direction.right));
      await Future<void>.delayed(const Duration(milliseconds: 33));
    }
    expect(a.snapshot!.player(a.myPlayerId!)!.x, greaterThan(before + 0.5));
    expect(a.me!.x, greaterThan(before + 0.5));
    // The server acknowledges her inputs, and once she stops her prediction
    // agrees with the server.
    expect(a.snapshot!.player(a.myPlayerId!)!.ackedInput, greaterThan(0));
    for (var i = 0; i < 15; i++) {
      a.sendInput(const PlayerInput());
      await Future<void>.delayed(const Duration(milliseconds: 33));
    }
    await waitFor(() => a.predictor.pendingCount < 3);
    final truth = a.snapshot!.player(a.myPlayerId!)!;
    expect(a.me!.x, closeTo(truth.x, 0.01));
    expect(a.me!.y, closeTo(truth.y, 0.01));

    // Bob blows himself up: Alice wins.
    b.sendInput(const PlayerInput(placeBomb: true));
    await waitFor(() => a.lastWinner != null);
    expect(a.lastWinner, a.myPlayerId);
    expect(b.lastWinner, a.myPlayerId);
    // Back to the lobby with ready flags cleared.
    await waitFor(() => server.room.state == RoomState.lobby);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(a.lobby.players.every((p) => !p.ready), isTrue);

    await a.close();
    await b.close();
  });

  test('a co-op match plays the stage the host picked', () async {
    final a = await connect(server, 'Solo');
    final b = await connect(server, 'Friend');
    a.setMode(GameMode.coop);
    a.setStage('1-3');
    await waitFor(
        () => b.lobby.mode == GameMode.coop && b.lobby.stage == '1-3');
    expect(b.lobby.stageDef.name, 'Drip Drop');
    b.setStage('2-10'); // not the host: ignored
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(a.lobby.stage, '1-3');
    a.start();
    await waitFor(() => b.snapshot != null && b.stageName != null);
    expect(b.stageId, '1-3');
    expect(b.stageName, 'Drip Drop');
    expect(b.stageTip, isNotEmpty);
    expect(b.snapshot!.enemies, hasLength(7)); // 5 Puffballs + 2 Blue Drops
    expect(b.snapshot!.grid.width, 31);
    expect(b.snapshot!.livesLeft, 5); // 3 + one per player
    await a.close();
    await b.close();
  });

  test('room rejects a fifth player', () async {
    final clients = <GameClient>[];
    for (var i = 0; i < 4; i++) {
      clients.add(await connect(server));
    }
    final fifth = await connect(server);
    expect(fifth.lastError, 'Room is full');
    for (final c in clients) {
      await c.close();
    }
    await fifth.close();
  });

  test('a dropped player resumes their seat mid-match', () async {
    final a = await connect(server, 'Alice');
    final b = await connect(server, 'Bob');
    await waitFor(() => a.lobby.players.length == 2);
    a.start();
    await waitFor(() => b.myPlayerId != null && b.snapshot != null);
    final seat = b.myPlayerId;
    final id = b.clientId;

    await b.drop();
    await waitFor(
        () => a.lobby.players.any((p) => p.name == 'Bob' && !p.connected));
    // The held seat is protected while its owner is away.
    final held = server.room.world!.playerById(seat!)!;
    expect(held.alive, isTrue);
    expect(held.invincibleFor, greaterThan(5));

    expect(await b.reconnect(), isTrue);
    expect(b.lastResumed, isTrue);
    expect(b.clientId, id);
    await waitFor(() => b.myPlayerId == seat && b.snapshot != null);
    await waitFor(() => a.lobby.players.every((p) => p.connected));
    expect(server.room.clients.length, 2);
    expect(server.room.state, RoomState.playing);

    await a.close();
    await b.close();
  });

  test('a dropped player in the lobby simply leaves', () async {
    final a = await connect(server, 'Alice');
    final b = await connect(server, 'Bob');
    await waitFor(() => a.lobby.players.length == 2);
    await b.drop();
    await waitFor(() => a.lobby.players.length == 1);
    await a.close();
    await b.close();
  });

  test('the server consumes one queued input per tick', () {
    final c = RoomClient(1, null, 'T');
    const right = PlayerInput(direction: Direction.right);
    c.queueInput(1, right);
    c.queueInput(2, const PlayerInput(placeBomb: true));
    c.queueInput(2, right); // duplicate: ignored
    expect(c.takeInput().direction, Direction.right);
    expect(c.lastInputSeq, 1);
    expect(c.takeInput().placeBomb, isTrue);
    expect(c.lastInputSeq, 2);
    // Empty queue: stand still, ack unchanged.
    expect(c.takeInput().direction, Direction.none);
    expect(c.lastInputSeq, 2);

    // A burst is trimmed oldest-first but keeps a bomb press.
    c.queueInput(3, const PlayerInput(placeBomb: true));
    for (var s = 4; s <= 3 + RoomClient.maxQueuedInputs; s++) {
      c.queueInput(s, right);
    }
    final first = c.takeInput();
    expect(first.placeBomb, isTrue);
    expect(c.lastInputSeq, 4);
  });

  test('clearing a co-op stage advances the room to the next one', () {
    final room = Room(seed: 4)
      ..mode = GameMode.coop
      ..stageId = '1-10';
    room.startMatch();
    expect(room.world!.enemies.single.kind, EnemyKind.kingPuffball);
    room.world!.enemies.single.alive = false;
    room.tick();
    expect(room.state, RoomState.lobby);
    expect(room.stageId, '2-1');
    room.close();
  });

  test('pings survive the trip over the wire', () {
    final json = inputToJson(
        const PlayerInput(direction: Direction.up, ping: PingKind.help),
        seq: 3);
    final back = inputFromJson(json);
    expect(back.ping, PingKind.help);
    expect(back.direction, Direction.up);
    expect(inputFromJson(inputToJson(const PlayerInput())).ping, PingKind.none);
  });

  test('room ticks deterministically without sockets', () {
    final room = Room(seed: 42);
    expect(room.code.length, 6);
    expect(room.code, isNot(matches(RegExp('[O0I1]'))));
    room.mode = GameMode.coop;
    room.startMatch();
    expect(room.state, RoomState.playing);
    for (var i = 0; i < 60; i++) {
      room.tick();
    }
    expect(room.world!.elapsed, closeTo(2, 1e-6));
    room.close();
  });

  group('online rooms', () {
    late RoomServer cloud;

    setUp(() async {
      cloud = await RoomServer.start(seed: 7, serveDefaultRoom: false);
    });

    tearDown(() => cloud.close());

    Future<GameClient> joinCode(String code, String name) async {
      final c = await GameClient.connect(
          Uri.parse('ws://127.0.0.1:${cloud.port}/rooms/$code'),
          playerName: name);
      await waitFor(() => c.clientId != null || c.lastError != null);
      return c;
    }

    test('health, create and look up a room by code', () async {
      final (healthStatus, health) = await http('GET', cloud, '/health');
      expect(healthStatus, 200);
      expect(health['ok'], isTrue);

      final (status, created) = await http('POST', cloud, '/rooms');
      expect(status, 201);
      final code = created['code'] as String;
      expect(code, hasLength(6));

      final (lookStatus, info) =
          await http('GET', cloud, '/rooms/${code.toLowerCase()}');
      expect(lookStatus, 200);
      expect(info['players'], 0);
      expect(info['state'], 'lobby');

      final (missing, _) = await http('GET', cloud, '/rooms/ZZZZZZ');
      expect(missing, 404);
    });

    test('players join separate rooms by code', () async {
      final (_, r1) = await http('POST', cloud, '/rooms');
      final (_, r2) = await http('POST', cloud, '/rooms');
      final c1 = r1['code'] as String;
      final c2 = r2['code'] as String;
      expect(c1, isNot(c2));

      final a = await joinCode(c1, 'Alice');
      final b = await joinCode(c1, 'Bob');
      final c = await joinCode(c2, 'Cara');
      expect(a.code, c1);
      expect(b.code, c1);
      expect(c.code, c2);
      expect(c.isHost, isTrue);
      await waitFor(() => a.lobby.players.length == 2);
      await waitFor(() => c.lobby.players.length == 1);
      expect(cloud.hub.byCode(c1)!.clients.length, 2);

      for (final x in [a, b, c]) {
        await x.close();
      }
    });

    test('unknown codes and the bare path are refused', () async {
      await expectLater(
          GameClient.connect(
              Uri.parse('ws://127.0.0.1:${cloud.port}/rooms/NOPE22'),
              playerName: 'X'),
          throwsA(isA<WebSocketException>()));
      await expectLater(
          GameClient.connect(Uri.parse('ws://127.0.0.1:${cloud.port}/'),
              playerName: 'X'),
          throwsA(isA<WebSocketException>()));
    });

    test('empty rooms expire', () async {
      final short = await RoomServer.start(
          seed: 3,
          serveDefaultRoom: false,
          emptyRoomTtl: const Duration(milliseconds: 100));
      final (_, r) = await http('POST', short, '/rooms');
      final code = r['code'] as String;
      expect(short.hub.byCode(code), isNotNull);
      await waitFor(() => short.hub.byCode(code) == null);
      await short.close();
    });
  });
}
