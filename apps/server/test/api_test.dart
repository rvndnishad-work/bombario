import 'dart:convert';
import 'dart:io';

import 'package:bombario_net/bombario_net.dart';
import 'package:bombario_server/bombario_server.dart';
import 'package:test/test.dart';

/// Matches a `(200, {"rank": n})` reply.
Matcher ranked(int n) => predicate<(int, Object?)>(
    (r) => r.$1 == 200 && r.$2 is Map && (r.$2 as Map)['rank'] == n,
    '200 with rank $n');

void main() {
  late Directory dir;
  late ServerApi api;
  late RoomServer server;
  late HttpClient http;

  Future<(int, Object?)> call(String method, String path,
      {Object? body, Map<String, String> headers = const {}}) async {
    final req = await http.openUrl(
        method, Uri.parse('http://127.0.0.1:${server.port}$path'));
    headers.forEach(req.headers.set);
    if (body != null) req.write(body is String ? body : jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  Future<RoomServer> boot(ServerApi a) =>
      RoomServer.start(seed: 1, serveDefaultRoom: false, fallback: a.handle);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bombario_api');
    api = ServerApi(dataDir: dir.path, scorePostsPerMinute: 1000);
    server = await boot(api);
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await server.close();
    await api.flush();
    await dir.delete(recursive: true);
  });

  Map<String, Object> score(String name, int ms, {int players = 1}) => {
        'board': 'daily-2026-10-03',
        'name': name,
        'timeMs': ms,
        'players': players,
      };

  group('leaderboards', () {
    test('ranks by time and lists the board fastest first', () async {
      expect(
          await call('POST', '/scores', body: score('Cara', 90000)), ranked(1));
      expect(
          await call('POST', '/scores',
              body: score('Arvind', 83450, players: 2)),
          ranked(1));
      expect(
          await call('POST', '/scores', body: score('Bea', 85000)), ranked(2));
      expect(
          await call('POST', '/scores', body: score('Dee', 99999)), ranked(4));

      final (status, body) =
          await call('GET', '/leaderboards/daily-2026-10-03?limit=3');
      expect(status, 200);
      final map = body! as Map;
      expect(map['board'], 'daily-2026-10-03');
      final entries = map['entries'] as List;
      expect(entries, hasLength(3));
      expect(entries.first,
          {'rank': 1, 'name': 'Arvind', 'timeMs': 83450, 'players': 2});
      expect([for (final e in entries) (e as Map)['name']],
          ['Arvind', 'Bea', 'Cara']);

      // An unknown board is simply empty.
      final (s2, empty) = await call('GET', '/leaderboards/daily-1999-01-01');
      expect(s2, 200);
      expect((empty! as Map)['entries'], isEmpty);
    });

    test('keeps each player best time once', () async {
      await call('POST', '/scores', body: score('Arvind', 90000));
      await call('POST', '/scores', body: score('Bea', 95000));
      // Slower than their best: ranked, not stored.
      expect(await call('POST', '/scores', body: score('arvind ', 99000)),
          ranked(2));
      expect(await call('POST', '/scores', body: score('Arvind', 80000)),
          ranked(1));
      final (_, body) = await call('GET', '/leaderboards/daily-2026-10-03');
      final entries = (body! as Map)['entries'] as List;
      expect(entries, hasLength(2));
      expect((entries.first as Map)['timeMs'], 80000);
    });

    test('validates input', () async {
      Future<int> status(Object body) async =>
          (await call('POST', '/scores', body: body)).$1;
      expect(await status({...score('A', 1), 'board': 'Daily!'}), 400);
      expect(await status({...score('A', 1), 'board': 'x' * 41}), 400);
      expect(await status(score('   ', 1000)), 400);
      expect(await status(score('x' * 17, 1000)), 400);
      expect(await status(score('A', 0)), 400);
      expect(await status(score('A', 3600001)), 400);
      expect(await status(score('A', 1000, players: 0)), 400);
      expect(await status(score('A', 1000, players: 5)), 400);
      expect(await status({...score('A', 1000), 'timeMs': '1000'}), 400);
      expect(await status('not json'), 400);
      expect(await status('x' * 70000), 413);
      expect((await call('GET', '/leaderboards/BAD')).$1, 400);
      expect((await call('GET', '/leaderboards/ok?limit=0')).$1, 400);
      expect((await call('GET', '/leaderboards/ok?limit=101')).$1, 400);
      expect((await call('GET', '/nope')).$1, 404);
    });

    test('caps a board at 500 entries', () async {
      final boards = Leaderboards();
      for (var i = 0; i < 520; i++) {
        await boards.submit(
            board: 'b', name: 'p$i', timeMs: 1000 + i, players: 1);
      }
      expect(await boards.top('b', limit: 1000), hasLength(500));
      expect(
          await boards.submit(
              board: 'b', name: 'late', timeMs: 5000, players: 1),
          501);
      expect((await boards.top('b', limit: 1000)).last.$2.timeMs, 1499);
    });

    test('persists to DATA_DIR and loads back', () async {
      await call('POST', '/scores', body: score('Arvind', 83450, players: 2));
      await api.flush();
      final file = File('${dir.path}/leaderboards/daily-2026-10-03.json');
      expect(await file.exists(), isTrue);

      final fresh = ServerApi(dataDir: dir.path);
      final top = await fresh.leaderboards.top('daily-2026-10-03');
      expect(top.single.$2.name, 'Arvind');
      expect(top.single.$2.players, 2);
    });

    test('rate limits score posts per address', () async {
      final strict = ServerApi(scorePostsPerMinute: 3);
      final s = await boot(strict);
      addTearDown(s.close);
      final old = server;
      server = s;
      final codes = [
        for (var i = 0; i < 5; i++)
          (await call('POST', '/scores', body: score('P$i', 1000 + i))).$1,
      ];
      expect(codes, [200, 200, 200, 429, 429]);
      // Another forwarded client has its own allowance.
      final (other, _) = await call('POST', '/scores',
          body: score('Q', 1), headers: {'x-forwarded-for': '10.0.0.9'});
      expect(other, 200);
      server = old;
    });
  });

  group('rate limiter', () {
    test('resets after the window', () {
      final r = RateLimiter(limit: 2);
      final t = DateTime(2026, 10, 3);
      expect(r.allow('a', t), isTrue);
      expect(r.allow('a', t), isTrue);
      expect(r.allow('a', t), isFalse);
      expect(r.allow('b', t), isTrue);
      expect(r.allow('a', t.add(const Duration(minutes: 1))), isTrue);
    });
  });

  group('events', () {
    Map<String, Object> event(String name, [Map<String, Object?>? props]) => {
          'name': name,
          'ts': 1696300000000,
          if (props != null) 'props': props,
        };

    test('appends JSONL to a file per day', () async {
      final (status, body) = await call('POST', '/events', body: {
        'events': [
          event('stage_cleared', {'stage': '1-4', 'ms': 83450, 'coop': true}),
          event('app_open'),
        ],
      });
      expect(status, 204);
      expect(body, isNull);
      await api.flush();
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final lines = await File('${dir.path}/events-$day.jsonl').readAsLines();
      expect(lines, hasLength(2));
      final first = jsonDecode(lines.first) as Map;
      expect(first['name'], 'stage_cleared');
      expect(first['props'], {'stage': '1-4', 'ms': 83450, 'coop': true});
      expect(first['ts'], 1696300000000);
      expect(first.keys, unorderedEquals(['name', 'ts', 'props', 'rx']));
    });

    test('keeps a bounded ring in memory without DATA_DIR', () async {
      final a = Analytics(ringSize: 3);
      for (var i = 0; i < 5; i++) {
        await a.record(Analytics.validate({
          'events': [event('e$i')],
        }));
      }
      expect([for (final e in a.recent) e['name']], ['e2', 'e3', 'e4']);
    });

    test('validates batches', () async {
      Future<int> status(Object body) async =>
          (await call('POST', '/events', body: body)).$1;
      expect(await status({'events': []}), 400);
      expect(
          await status({
            'events': [for (var i = 0; i < 51; i++) event('x')]
          }),
          400);
      expect(
          await status({
            'events': [event('Bad-Name')]
          }),
          400);
      expect(
          await status({
            'events': [event('x' * 41)]
          }),
          400);
      expect(
          await status({
            'events': [
              event('nested', {
                'a': {'b': 1}
              })
            ]
          }),
          400);
      expect(
          await status({
            'events': [
              event('big', {'a': 'x' * 2100})
            ]
          }),
          400);
      expect(
          await status({
            'events': [
              {'name': 'no_ts'}
            ]
          }),
          400);
      expect(await status([1]), 400);
      expect(
          await status({
            'events': [for (var i = 0; i < 50; i++) event('ok')]
          }),
          204);
    });
  });
}
