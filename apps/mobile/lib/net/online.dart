import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Talks to the online room server's HTTP API.
///
/// The server address defaults to `--dart-define=BOMBARIO_SERVER=...` and
/// can be changed on the Online screen, which is handy while the server runs
/// on a laptop during development.
class OnlineServer {
  static const String defaultUrl = String.fromEnvironment(
    'BOMBARIO_SERVER',
    defaultValue: 'http://localhost:8080',
  );

  /// Current server address for this app run.
  static final ValueNotifier<String> url = ValueNotifier(defaultUrl);

  /// Parses a typed server address, adding `http://` when no scheme is given.
  static Uri parse(String text) {
    var t = text.trim();
    if (!t.contains('://')) t = 'http://$t';
    final u = Uri.parse(t);
    return u.replace(path: u.path.endsWith('/') ? u.path : '${u.path}/');
  }

  /// Room codes are typed by people, so be forgiving.
  static String normalizeCode(String code) =>
      code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  /// Asks the server for a new room and returns its code.
  static Future<String> createRoom(Uri base) async {
    final (status, body) = await _call('POST', base.resolve('rooms'));
    if (status != HttpStatus.created) {
      throw OnlineException('Server refused to create a room ($status)');
    }
    return body['code'] as String;
  }

  /// Checks a code before connecting so a typo gets a friendly message.
  static Future<void> checkRoom(Uri base, String code) async {
    final (status, body) = await _call('GET', base.resolve('rooms/$code'));
    if (status == HttpStatus.notFound) {
      throw OnlineException('No room with code $code');
    }
    if (status != HttpStatus.ok) {
      throw OnlineException('Server error ($status)');
    }
    if (body['state'] != 'lobby') {
      throw OnlineException('That room is already playing');
    }
    if ((body['players'] as int) >= (body['maxPlayers'] as int)) {
      throw OnlineException('That room is full');
    }
  }

  /// WebSocket address of a room: `http` becomes `ws`, `https` becomes `wss`.
  static Uri socketUri(Uri base, String code) {
    final u = base.resolve('rooms/$code');
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws');
  }

  /// Puts this player in a quick-match room of [mode] (`coop` or
  /// `versus`) and returns its code. The server fills empty seats with bots
  /// if nobody else turns up.
  static Future<String> quickMatch(Uri base, String mode) async {
    final (status, body) = await _call(
      'POST',
      base.resolve('quickmatch'),
      body: {'mode': mode},
    );
    if (status != HttpStatus.ok && status != HttpStatus.created) {
      throw OnlineException('Quick match is unavailable ($status)');
    }
    return body['code'] as String;
  }

  /// Submits a time to [board]; returns the rank it reached.
  static Future<int> submitScore(
    Uri base, {
    required String board,
    required String name,
    required int timeMs,
    int players = 1,
  }) async {
    final (status, body) = await _call(
      'POST',
      base.resolve('scores'),
      body: {
        'board': board,
        'name': name,
        'timeMs': timeMs,
        'players': players,
      },
    );
    if (status == HttpStatus.tooManyRequests) {
      throw OnlineException('Too many scores sent. Try again in a minute');
    }
    if (status != HttpStatus.ok && status != HttpStatus.created) {
      throw OnlineException('Score not accepted ($status)');
    }
    return (body['rank'] as num).toInt();
  }

  /// The fastest times on [board], best first.
  static Future<List<LeaderboardEntry>> leaderboard(
    Uri base,
    String board, {
    int limit = 20,
  }) async {
    final (status, body) = await _call(
      'GET',
      base.resolve('leaderboards/$board?limit=$limit'),
    );
    if (status == HttpStatus.notFound) return const [];
    if (status != HttpStatus.ok) {
      throw OnlineException('Leaderboard unavailable ($status)');
    }
    return [
      for (final e in (body['entries'] as List? ?? const []))
        LeaderboardEntry.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Fire-and-forget upload of analytics events; true when accepted.
  static Future<bool> sendEvents(
    Uri base,
    List<Map<String, Object?>> events,
  ) async {
    final (status, _) = await _call(
      'POST',
      base.resolve('events'),
      body: {'events': events},
    );
    return status >= 200 && status < 300;
  }

  static Future<(int, Map<String, dynamic>)> _call(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final payload = body;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.openUrl(method, uri);
      if (payload != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(payload));
      }
      final res = await req.close().timeout(const Duration(seconds: 8));
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> body;
      try {
        body = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        body = const {};
      }
      return (res.statusCode, body);
    } on SocketException catch (e) {
      throw OnlineException('Could not reach the server (${e.message})');
    } finally {
      client.close(force: true);
    }
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.timeMs,
    this.players = 1,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
    rank: (j['rank'] as num).toInt(),
    name: j['name'] as String,
    timeMs: (j['timeMs'] as num).toInt(),
    players: (j['players'] as num?)?.toInt() ?? 1,
  );

  final int rank;
  final String name;
  final int timeMs;
  final int players;
}

/// `1:23.4` from milliseconds.
String formatTime(int ms) {
  final tenths = (ms ~/ 100) % 10;
  final s = (ms ~/ 1000) % 60;
  final m = ms ~/ 60000;
  return '$m:${s.toString().padLeft(2, '0')}.$tenths';
}

class OnlineException implements Exception {
  OnlineException(this.message);
  final String message;
  @override
  String toString() => message;
}
