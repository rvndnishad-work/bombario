import 'dart:async';
import 'dart:io';

import 'package:bombario_net/bombario_net.dart';
import 'package:bombario_server/bombario_server.dart';

/// Runs the online room server. See README.md for the HTTP API.
///
/// Environment:
/// - `PORT` (default 8080): port to listen on. Most hosts (Cloud Run, Fly.io,
///   Render) set this for you.
/// - `MAX_PLAYERS` (default 4): seats per room.
/// - `ROOM_TTL_MINUTES` (default 10): how long an empty room keeps its code.
/// - `QUICK_START_SECONDS` (default 20): how long a quick-match room waits
///   for more people after its first player joins before bots fill in.
/// - `BOT_SKINS` (default: every app hat): comma-separated skins bots pick from.
/// - `DATA_DIR` (unset by default): where leaderboards and analytics are
///   saved. Unset keeps leaderboards in memory and only the latest analytics
///   events, so a restart forgets them.
Future<void> main() async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final maxPlayers =
      int.tryParse(env['MAX_PLAYERS'] ?? '') ?? Room.defaultMaxPlayers;
  final ttl = int.tryParse(env['ROOM_TTL_MINUTES'] ?? '') ?? 10;
  final quickStart = int.tryParse(env['QUICK_START_SECONDS'] ?? '') ??
      Room.defaultQuickStartDelay.inSeconds;
  final botSkins =
      (env['BOT_SKINS'] ?? 'classic,cap,sprout,horns,wizard,tophat,halo,crown')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
  final dataDir = env['DATA_DIR'];

  final api =
      ServerApi(dataDir: dataDir == null || dataDir.isEmpty ? null : dataDir);
  final server = await RoomServer.start(
    port: port,
    address: InternetAddress.anyIPv4,
    maxPlayers: maxPlayers,
    emptyRoomTtl: Duration(minutes: ttl),
    serveDefaultRoom: false,
    quickStartDelay: Duration(seconds: quickStart),
    botSkins: botSkins.isEmpty ? const ['classic'] : botSkins,
    fallback: api.handle,
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
  await api.flush();
  exit(0);
}
