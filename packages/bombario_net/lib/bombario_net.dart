/// Room server and client for Bombario.
///
/// The same [RoomServer] runs on a cloud host and, for local Wi-Fi play,
/// inside the hosting phone. Clients talk to it over a WebSocket using the
/// small JSON protocol in `protocol.dart`.
library;

export 'src/game_client.dart';
export 'src/protocol.dart';
export 'src/room_server.dart';
