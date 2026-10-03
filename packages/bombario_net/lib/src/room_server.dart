import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'protocol.dart';
import 'room.dart';

/// HTTP + WebSocket front for one or many [Room]s.
///
/// Routes:
/// - `GET /health` → `ok`
/// - `POST /rooms` → `{"code": "K7QX4M"}` creates a room (online play)
/// - `GET /rooms/<code>` → `{"code", "players", "state"}`
/// - WebSocket at `/rooms/<code>` → join that room
/// - WebSocket at `/` → join the default room (local Wi-Fi hosting, where
///   the phone runs one room and friends connect by address)
///
/// The same binary runs in the cloud (`apps/server`) and inside the hosting
/// phone; only the entry point differs.
class RoomServer {
  RoomServer._(this._http, this.hub, this.serveDefaultRoom);

  final HttpServer _http;
  final RoomHub hub;

  /// Whether `/` joins the default room. The cloud server turns this off so
  /// every online room needs a code.
  final bool serveDefaultRoom;

  int get port => _http.port;
  InternetAddress get address => _http.address;

  /// The default room used by local Wi-Fi hosting.
  Room get room => hub.defaultRoom;

  static Future<RoomServer> start({
    int port = 0,
    InternetAddress? address,
    int? seed,
    int maxPlayers = Room.defaultMaxPlayers,
    Duration emptyRoomTtl = const Duration(minutes: 10),
    bool serveDefaultRoom = true,
  }) async {
    final http =
        await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    final hub =
        RoomHub(seed: seed, maxPlayers: maxPlayers, emptyRoomTtl: emptyRoomTtl);
    final server = RoomServer._(http, hub, serveDefaultRoom);
    http.listen(server._handle);
    return server;
  }

  Future<void> _handle(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    try {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final Room? room;
        if (segments.isEmpty) {
          room = serveDefaultRoom ? hub.defaultRoom : null;
        } else if (segments.length == 2 && segments[0] == 'rooms') {
          room = hub.byCode(segments[1]);
        } else {
          room = null;
        }
        if (room == null) {
          req.response
            ..statusCode = HttpStatus.notFound
            ..write('No such room');
          await req.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(req);
        room.accept(socket);
        return;
      }

      req.response.headers.contentType = ContentType.json;
      if (req.method == 'GET' &&
          segments.length == 1 &&
          segments[0] == 'health') {
        req.response.write('{"ok":true,"rooms":${hub.rooms.length}}');
      } else if (req.method == 'POST' &&
          segments.length == 1 &&
          segments[0] == 'rooms') {
        final room = hub.create();
        req.response
          ..statusCode = HttpStatus.created
          ..write(encode({'code': room.code}));
      } else if (req.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'rooms') {
        final room = hub.byCode(segments[1]);
        if (room == null) {
          req.response
            ..statusCode = HttpStatus.notFound
            ..write(encode({'error': 'No such room'}));
        } else {
          req.response.write(encode({
            'code': room.code,
            'players': room.clients.length,
            'maxPlayers': room.maxPlayers,
            'state': room.state.name,
          }));
        }
      } else {
        req.response
          ..statusCode = HttpStatus.notFound
          ..write(encode({'error': 'Not found'}));
      }
    } catch (e) {
      req.response.statusCode = HttpStatus.internalServerError;
    }
    await req.response.close();
  }

  Future<void> close() async {
    await hub.close();
    await _http.close(force: true);
  }
}

/// Owns rooms by code and retires rooms that stay empty.
class RoomHub {
  RoomHub({
    int? seed,
    this.maxPlayers = Room.defaultMaxPlayers,
    this.emptyRoomTtl = const Duration(minutes: 10),
  }) : _rng = Random(seed);

  final int maxPlayers;
  final Duration emptyRoomTtl;
  final Random _rng;
  final Map<String, Room> _rooms = {};
  final Map<String, Timer> _expiry = {};
  Room? _default;

  Iterable<Room> get rooms => _rooms.values;

  /// The single room used when hosting on a phone. Never expires.
  Room get defaultRoom => _default ??= create(expires: false);

  Room? byCode(String code) => _rooms[code.toUpperCase()];

  Room create({bool expires = true}) {
    Room room;
    do {
      room = Room(seed: _rng.nextInt(1 << 30), maxPlayers: maxPlayers);
    } while (_rooms.containsKey(room.code));
    _rooms[room.code] = room;
    if (expires) {
      room.onEmpty = () => _scheduleExpiry(room);
      room.onOccupied = () => _expiry.remove(room.code)?.cancel();
      _scheduleExpiry(room);
    }
    return room;
  }

  void _scheduleExpiry(Room room) {
    _expiry[room.code]?.cancel();
    _expiry[room.code] = Timer(emptyRoomTtl, () {
      if (room.clients.isEmpty) {
        _rooms.remove(room.code);
        _expiry.remove(room.code);
        room.close();
      }
    });
  }

  Future<void> close() async {
    for (final t in _expiry.values) {
      t.cancel();
    }
    _expiry.clear();
    for (final r in _rooms.values.toList()) {
      await r.close();
    }
    _rooms.clear();
    _default = null;
  }
}
