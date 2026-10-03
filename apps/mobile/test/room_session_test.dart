import 'dart:async';

import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
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
}
