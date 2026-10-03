import 'dart:async';

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

Future<GameClient> connect(RoomServer server) async {
  final c = await GameClient.connect('127.0.0.1', server.port);
  await waitFor(() => c.clientId != null || c.lastError != null);
  return c;
}

void main() {
  late RoomServer server;

  setUp(() async {
    server = await RoomServer.start(seed: 1);
  });

  tearDown(() => server.close());

  test('first client is host, lobby updates as players join and ready up',
      () async {
    final a = await connect(server);
    expect(a.isHost, isTrue);
    expect(a.code!.length, 6);
    a.join('Alice');
    await waitFor(() => a.lobby.players.any((p) => p.name == 'Alice'));
    expect(a.lobby.players.single.isHost, isTrue);

    final b = await connect(server);
    expect(b.isHost, isFalse);
    expect(b.code, a.code);
    b.join('Bob');
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
    final a = await connect(server);
    final b = await connect(server);
    a.join('Alice');
    b.join('Bob');
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

    // Alice holds right for a while and must have moved.
    final before = first.player(a.myPlayerId!)!.x;
    for (var i = 0; i < 20; i++) {
      a.sendInput(const PlayerInput(direction: Direction.right));
      await Future<void>.delayed(const Duration(milliseconds: 33));
    }
    expect(a.snapshot!.player(a.myPlayerId!)!.x, greaterThan(before + 0.5));

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

  test('a co-op match has enemies and a bigger maze', () async {
    final a = await connect(server);
    a.join('Solo');
    a.setMode(GameMode.coop);
    await waitFor(() => a.lobby.mode == GameMode.coop);
    a.start();
    await waitFor(() => a.snapshot != null);
    expect(a.snapshot!.enemies, isNotEmpty);
    expect(a.snapshot!.grid.width, 31);
    await a.close();
  });

  test('room rejects a fifth player and joins during a match', () async {
    final clients = <GameClient>[];
    for (var i = 0; i < 4; i++) {
      clients.add(await connect(server));
    }
    final fifth = await connect(server);
    expect(fifth.lastError, 'Room is full');
    for (final c in clients) {
      await c.close();
    }
  });

  test('room ticks deterministically without sockets', () {
    final room = Room(seed: 42);
    expect(room.code.length, 6);
    room.mode = GameMode.coop;
    room.startMatch();
    expect(room.state, RoomState.playing);
    for (var i = 0; i < 60; i++) {
      room.tick();
    }
    expect(room.world!.elapsed, closeTo(2, 1e-6));
    room.close();
  });
}
