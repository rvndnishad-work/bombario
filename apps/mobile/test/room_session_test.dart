import 'dart:async';
import 'dart:io';

import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
import 'package:bombario/net/online.dart';
import 'package:bombario/net/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(
  bool Function() condition, {
  String what = 'condition',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('$what not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  // Bonsoir has no platform implementation here; RoomSession.host treats a
  // failed broadcast as non-fatal, so hosting still works over loopback.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('host and a joiner play a versus round end to end', () async {
    final host = await RoomSession.host(playerName: 'Host');
    addTearDown(host.leave);
    await waitFor(() => host.phase == SessionPhase.lobby, what: 'wait 1');
    expect(host.isHost, isTrue);
    expect(host.hostAddress, isNotNull);
    final port = int.parse(host.hostAddress!.split(':').last);

    final guest = await RoomSession.join(
      host: '127.0.0.1',
      port: port,
      playerName: 'Guest',
    );
    addTearDown(guest.leave);
    await waitFor(() => guest.phase == SessionPhase.lobby, what: 'wait 2');
    expect(guest.isHost, isFalse);
    expect(guest.code, host.code);

    guest.setReady(true);
    await waitFor(() => host.lobby.everyoneReady, what: 'wait 3');
    host.start();
    await waitFor(
      () =>
          host.phase == SessionPhase.playing &&
          guest.phase == SessionPhase.playing,
      what: 'wait 4',
    );
    await waitFor(
      () => guest.snapshot != null && host.snapshot != null,
      what: 'wait 5',
    );
    expect(guest.snapshot!.players.length, 2);

    // The guest blows themself up; the host wins and both land in "ended".
    guest.sendInput(const PlayerInput(placeBomb: true));
    await waitFor(
      () =>
          host.phase == SessionPhase.ended && guest.phase == SessionPhase.ended,
      what: 'wait 6',
    );
    expect(host.lastWinner, host.myPlayerId);
    expect(guest.lastWinner, host.myPlayerId);

    // The result stays on screen until the UI dismisses it.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.phase, SessionPhase.ended);
    host.backToLobby();
    guest.backToLobby();
    expect(host.phase, SessionPhase.lobby);
    expect(host.lobby.players.every((p) => !p.ready), isTrue);
    expect(host.mode, GameMode.versus);
  });

  test('co-op: the host picks a stage and everyone sees its name', () async {
    final host = await RoomSession.host(playerName: 'Host');
    addTearDown(host.leave);
    await waitFor(() => host.phase == SessionPhase.lobby, what: 'lobby');
    final port = int.parse(host.hostAddress!.split(':').last);
    final guest = await RoomSession.join(
      host: '127.0.0.1',
      port: port,
      playerName: 'Guest',
    );
    addTearDown(guest.leave);
    await waitFor(() => host.lobby.players.length == 2, what: 'joined');

    host.setMode(GameMode.coop);
    host.setStage('1-4');
    await waitFor(() => guest.lobbyStage == '1-4', what: 'stage');
    guest.setReady(true);
    await waitFor(() => host.lobby.everyoneReady, what: 'ready');
    host.start();
    await waitFor(
      () => guest.phase == SessionPhase.playing && guest.snapshot != null,
      what: 'playing',
    );
    expect(guest.stageName, 'Kick Off');
    expect(guest.stageTip, contains('Kick'));
    expect(guest.snapshot!.livesLeft, 5);

    // A ping reaches the other phone.
    guest.sendInput(const PlayerInput(ping: PingKind.exitHere));
    await waitFor(() => host.snapshot?.pings.isNotEmpty ?? false, what: 'ping');
    expect(host.snapshot!.pings.single.kind, PingKind.exitHere);
  });

  group('online', () {
    late RoomServer cloud;
    late Uri base;

    setUp(() async {
      // The test binding answers every HTTP request with a 400; these tests
      // talk to a real local server.
      HttpOverrides.global = null;
      cloud = await RoomServer.start(seed: 9, serveDefaultRoom: false);
      base = OnlineServer.parse('127.0.0.1:${cloud.port}');
    });

    tearDown(() => cloud.close());

    test('create a room, share the code, join it and reconnect', () async {
      final host = await RoomSession.createOnline(
        server: base,
        playerName: 'Host',
      );
      addTearDown(host.leave);
      await waitFor(() => host.phase == SessionPhase.lobby, what: 'lobby');
      expect(host.online, isTrue);
      expect(host.isHost, isTrue);
      final code = host.code!;
      expect(code, hasLength(6));

      // Friends type codes however they like.
      final guest = await RoomSession.joinOnline(
        server: base,
        code: ' ${code.toLowerCase()} ',
        playerName: 'Guest',
      );
      addTearDown(guest.leave);
      await waitFor(() => host.lobby.players.length == 2, what: 'joined');
      expect(guest.code, code);

      guest.setReady(true);
      await waitFor(() => host.lobby.everyoneReady, what: 'ready');
      host.start();
      await waitFor(
        () => guest.phase == SessionPhase.playing && guest.snapshot != null,
        what: 'playing',
      );
      final seat = guest.myPlayerId;

      // The guest's phone loses its connection and comes back.
      await guest.dropConnection();
      await waitFor(
        () => host.lobby.players.any((p) => !p.connected),
        what: 'seat held',
      );
      await waitFor(
        () =>
            guest.phase == SessionPhase.playing &&
            host.lobby.players.every((p) => p.connected),
        what: 'resumed',
      );
      expect(guest.myPlayerId, seat);
      // Prediction runs for the resumed player.
      for (var i = 0; i < 5; i++) {
        guest.sendInput(const PlayerInput(direction: Direction.right));
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      expect(guest.me, isNotNull);
    });

    test('a wrong code gets a friendly error', () async {
      await expectLater(
        RoomSession.joinOnline(server: base, code: 'ZZZZZZ', playerName: 'X'),
        throwsA(
          isA<OnlineException>().having(
            (e) => e.message,
            'message',
            contains('No room'),
          ),
        ),
      );
    });

    test('socket addresses follow the server scheme', () {
      expect(
        OnlineServer.socketUri(
          OnlineServer.parse('https://x.dev'),
          'ABC234',
        ).toString(),
        'wss://x.dev/rooms/ABC234',
      );
      expect(
        OnlineServer.socketUri(
          OnlineServer.parse('localhost:8080'),
          'ABC234',
        ).toString(),
        'ws://localhost:8080/rooms/ABC234',
      );
    });
  });
}
