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

  static Future<(int, Map<String, dynamic>)> _call(
    String method,
    Uri uri,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.openUrl(method, uri);
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

class OnlineException implements Exception {
  OnlineException(this.message);
  final String message;
  @override
  String toString() => message;
}
