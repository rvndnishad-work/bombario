import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bombario_core/bombario_core.dart';

import 'protocol.dart';
import 'room.dart';

/// HTTP + WebSocket front for one or many [Room]s.
///
/// Routes:
/// - `GET /health` → `ok`
/// - `POST /rooms` → `{"code": "K7QX4M"}` creates a room (online play)
/// - `GET /rooms/<code>` → `{"code", "players", "maxPlayers", "state",
///   "quick"}`
/// - `POST /quickmatch` with `{"mode": "coop" | "versus"}` → `{"code"}`: a
///   seat in an open quick-match room of that mode, or a new one. 400 for a
///   bad body.
/// - WebSocket at `/rooms/<code>` → join that room
/// - WebSocket at `/` → join the default room (local Wi-Fi hosting, where
///   the phone runs one room and friends connect by address)
///
/// The same binary runs in the cloud (`apps/server`) and inside the hosting
/// phone; only the entry point differs. Anything else goes to [fallback]
/// when given (the cloud server adds leaderboards and analytics there).
class RoomServer {
  RoomServer._(this._http, this.hub, this.serveDefaultRoom, this.fallback);

  /// Handles requests no built-in route matched. Returns false to let the
  /// server answer 404. It must close the response when it returns true.
  final Future<bool> Function(HttpRequest req)? fallback;

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
    Duration quickStartDelay = Room.defaultQuickStartDelay,
    List<String> botSkins = const [Player.defaultSkin],
    Future<bool> Function(HttpRequest req)? fallback,
  }) async {
    final http =
        await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    final hub = RoomHub(
      seed: seed,
      maxPlayers: maxPlayers,
      emptyRoomTtl: emptyRoomTtl,
      quickStartDelay: quickStartDelay,
      botSkins: botSkins,
    );
    final server = RoomServer._(http, hub, serveDefaultRoom, fallback);
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
            'quick': room.quick,
          }));
        }
      } else if (req.method == 'POST' &&
          segments.length == 1 &&
          segments[0] == 'quickmatch') {
        final body = await readJsonBody(req);
        final mode = body?['mode'];
        if (mode != 'coop' && mode != 'versus') {
          req.response
            ..statusCode = HttpStatus.badRequest
            ..write(encode({'error': 'mode must be "coop" or "versus"'}));
        } else {
          final room = hub.quickMatch(GameMode.parse(mode as String));
          req.response.write(encode({'code': room.code}));
        }
      } else if (fallback != null && await fallback!(req)) {
        return;
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

  /// Reads a small JSON object body, or null when it is missing, too big
  /// or not a JSON object.
  static Future<Map<String, dynamic>?> readJsonBody(HttpRequest req,
      {int maxBytes = 16 * 1024}) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) return null;
    }
    try {
      final v = jsonDecode(utf8.decode(bytes));
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }
}

/// Owns rooms by code and retires rooms that stay empty.
class RoomHub {
  RoomHub({
    int? seed,
    this.maxPlayers = Room.defaultMaxPlayers,
    this.emptyRoomTtl = const Duration(minutes: 10),
    this.quickStartDelay = Room.defaultQuickStartDelay,
    this.botSkins = const [Player.defaultSkin],
  }) : _rng = Random(seed);

  final int maxPlayers;
  final Duration emptyRoomTtl;

  /// How long a quick-match room waits after its first player joins.
  final Duration quickStartDelay;

  /// Skins bots pick from.
  final List<String> botSkins;
  final Random _rng;
  final Map<String, Room> _rooms = {};
  final Map<String, Timer> _expiry = {};
  Room? _default;

  Iterable<Room> get rooms => _rooms.values;

  /// The single room used when hosting on a phone. Never expires.
  Room get defaultRoom => _default ??= create(expires: false);

  Room? byCode(String code) => _rooms[code.toUpperCase()];

  Room create({bool expires = true, bool quick = false}) {
    Room room;
    do {
      room = Room(
        seed: _rng.nextInt(1 << 30),
        maxPlayers: maxPlayers,
        quick: quick,
        quickStartDelay: quickStartDelay,
        botSkins: botSkins,
      );
    } while (_rooms.containsKey(room.code));
    _rooms[room.code] = room;
    if (expires) {
      room.onEmpty = () => _scheduleExpiry(room);
      room.onOccupied = () => _expiry.remove(room.code)?.cancel();
      _scheduleExpiry(room);
    }
    return room;
  }

  /// A seat in an open quick-match room of [mode] (not started, not full),
  /// or a new one. The seat is held for [Room.reservationTtl] until the
  /// player's WebSocket joins.
  Room quickMatch(GameMode mode) {
    final room = rooms
            .where((r) => r.mode == mode && r.acceptsQuickPlayers)
            .firstOrNull ??
        (create(quick: true)
          ..mode = mode
          ..stageId = Campaign.first.id);
    room.reserveSeat();
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
