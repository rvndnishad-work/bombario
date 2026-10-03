import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'analytics.dart';
import 'leaderboards.dart';

/// Fixed-window request counter per client address.
class RateLimiter {
  RateLimiter({required this.limit, this.window = const Duration(minutes: 1)});

  final int limit;
  final Duration window;
  final Map<String, (DateTime, int)> _counts = {};

  /// Counts a request from [key]; false once it is over the limit.
  bool allow(String key, [DateTime? now]) {
    final t = now ?? DateTime.now();
    if (_counts.length > 10000) {
      _counts.removeWhere((_, v) => t.difference(v.$1) >= window);
    }
    final (start, n) = _counts[key] ?? (t, 0);
    if (t.difference(start) >= window) {
      _counts[key] = (t, 1);
      return true;
    }
    if (n >= limit) return false;
    _counts[key] = (start, n + 1);
    return true;
  }
}

/// The cloud server's routes beyond rooms, plugged into
/// `RoomServer.start(fallback: api.handle)`:
///
/// - `POST /scores` `{"board", "name", "timeMs", "players"}` → 200
///   `{"rank"}`. 400 bad input, 413 body too big, 429 rate limited.
/// - `GET /leaderboards/<board>?limit=20` → 200 `{"board", "entries":
///   [{"rank", "name", "timeMs", "players"}]}`, fastest first. 400 for a
///   bad board name or limit.
/// - `POST /events` `{"events": [{"name", "ts", "props"}]}` → 204. 400 bad
///   input, 413 body too big, 429 rate limited.
class ServerApi {
  ServerApi({
    String? dataDir,
    int scorePostsPerMinute = 30,
    int eventPostsPerMinute = 60,
  })  : leaderboards = Leaderboards(dataDir: dataDir),
        analytics = Analytics(dataDir: dataDir),
        _scoreLimit = RateLimiter(limit: scorePostsPerMinute),
        _eventLimit = RateLimiter(limit: eventPostsPerMinute);

  final Leaderboards leaderboards;
  final Analytics analytics;
  final RateLimiter _scoreLimit;
  final RateLimiter _eventLimit;

  static const int maxBodyBytes = 64 * 1024;

  /// Returns false for paths it doesn't serve.
  Future<bool> handle(HttpRequest req) async {
    final seg = req.uri.pathSegments;
    final res = req.response;
    if (req.method == 'POST' && seg.length == 1 && seg[0] == 'scores') {
      await _postScore(req);
    } else if (req.method == 'GET' &&
        seg.length == 2 &&
        seg[0] == 'leaderboards') {
      await _getBoard(req, seg[1]);
    } else if (req.method == 'POST' && seg.length == 1 && seg[0] == 'events') {
      await _postEvents(req);
    } else {
      return false;
    }
    await res.close();
    return true;
  }

  /// Behind a load balancer (Cloud Run, Fly.io) the client is the first
  /// `X-Forwarded-For` address; clients can forge that header, so the
  /// limit only slows down casual abuse.
  static String clientKey(HttpRequest req) {
    final fwd = req.headers.value('x-forwarded-for');
    if (fwd != null && fwd.trim().isNotEmpty) {
      return fwd.split(',').first.trim();
    }
    return req.connectionInfo?.remoteAddress.address ?? '?';
  }

  void _json(HttpResponse res, int status, Object body) {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }

  void _tooMany(HttpResponse res) {
    res.headers.set('retry-after', '60');
    _json(res, HttpStatus.tooManyRequests, {'error': 'Too many requests'});
  }

  /// The decoded body, or null after answering 400 or 413.
  Future<(bool, Object?)> _body(HttpRequest req) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) {
        _json(req.response, HttpStatus.requestEntityTooLarge,
            {'error': 'Body too large'});
        return (false, null);
      }
    }
    try {
      return (true, jsonDecode(utf8.decode(bytes.takeBytes())));
    } on FormatException {
      _json(req.response, HttpStatus.badRequest, {'error': 'Invalid JSON'});
      return (false, null);
    }
  }

  Future<void> _postScore(HttpRequest req) async {
    if (!_scoreLimit.allow(clientKey(req))) {
      await req.drain<void>();
      return _tooMany(req.response);
    }
    final (ok, body) = await _body(req);
    if (!ok) return;
    if (body is! Map ||
        body['board'] is! String ||
        body['name'] is! String ||
        body['timeMs'] is! int ||
        body['players'] is! int) {
      return _json(req.response, HttpStatus.badRequest, {
        'error': 'expected {"board", "name", "timeMs", "players"}',
      });
    }
    try {
      final rank = await leaderboards.submit(
        board: body['board'] as String,
        name: body['name'] as String,
        timeMs: body['timeMs'] as int,
        players: body['players'] as int,
      );
      _json(req.response, HttpStatus.ok, {'rank': rank});
    } on ScoreRejected catch (e) {
      _json(req.response, HttpStatus.badRequest, {'error': e.message});
    }
  }

  Future<void> _getBoard(HttpRequest req, String board) async {
    final limitParam = req.uri.queryParameters['limit'];
    final limit = limitParam == null ? 20 : int.tryParse(limitParam);
    if (!Leaderboards.validBoard(board) ||
        limit == null ||
        limit < 1 ||
        limit > 100) {
      return _json(req.response, HttpStatus.badRequest,
          {'error': 'bad board name or limit (1-100)'});
    }
    final top = await leaderboards.top(board, limit: limit);
    _json(req.response, HttpStatus.ok, {
      'board': board,
      'entries': [
        for (final (rank, e) in top)
          {
            'rank': rank,
            'name': e.name,
            'timeMs': e.timeMs,
            'players': e.players
          },
      ],
    });
  }

  Future<void> _postEvents(HttpRequest req) async {
    if (!_eventLimit.allow(clientKey(req))) {
      await req.drain<void>();
      return _tooMany(req.response);
    }
    final (ok, body) = await _body(req);
    if (!ok) return;
    try {
      await analytics.record(Analytics.validate(body));
      req.response.statusCode = HttpStatus.noContent;
    } on EventsRejected catch (e) {
      _json(req.response, HttpStatus.badRequest, {'error': e.message});
    }
  }

  Future<void> flush() async {
    await leaderboards.flush();
    await analytics.flush();
  }
}
