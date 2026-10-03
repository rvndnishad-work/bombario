import 'dart:async';
import 'dart:io';

import 'package:bombario_net/bombario_net.dart';

/// Runs the online room server.
///
/// Environment:
/// - `PORT` (default 8080): port to listen on. Most hosts (Cloud Run, Fly.io,
///   Render) set this for you.
/// - `MAX_PLAYERS` (default 4): seats per room.
/// - `ROOM_TTL_MINUTES` (default 10): how long an empty room keeps its code.
Future<void> main() async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final maxPlayers =
      int.tryParse(env['MAX_PLAYERS'] ?? '') ?? Room.defaultMaxPlayers;
  final ttl = int.tryParse(env['ROOM_TTL_MINUTES'] ?? '') ?? 10;

  final server = await RoomServer.start(
    port: port,
    address: InternetAddress.anyIPv4,
    maxPlayers: maxPlayers,
    emptyRoomTtl: Duration(minutes: ttl),
    serveDefaultRoom: false,
  );
  stdout.writeln('bombario server listening on :${server.port}');

  // Stop cleanly on Ctrl-C or a container stop.
  final signals = [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  await Future.any([for (final s in signals) s.watch().first]);
  stdout.writeln('shutting down');
  await server.close();
  exit(0);
}
