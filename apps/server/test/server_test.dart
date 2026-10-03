import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Boots the real entry point and talks to it over HTTP.
void main() {
  test('the entry point serves rooms, quick match, scores and events',
      () async {
    final port = 20000 + DateTime.now().millisecond;
    final data = await Directory.systemTemp.createTemp('bombario_server');
    addTearDown(() => data.delete(recursive: true));
    final proc = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/server.dart'],
      environment: {'PORT': '$port', 'DATA_DIR': data.path},
    );
    addTearDown(proc.kill);
    await proc.stdout
        .transform(utf8.decoder)
        .firstWhere((line) => line.contains('listening'))
        .timeout(const Duration(seconds: 60));

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<(int, String)> call(String method, String path,
        [Object? body]) async {
      final req = await client.openUrl(
          method, Uri.parse('http://127.0.0.1:$port$path'));
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    final (healthCode, _) = await call('GET', '/health');
    expect(healthCode, 200);
    final (createCode, body) = await call('POST', '/rooms');
    expect(createCode, 201);
    expect((jsonDecode(body) as Map)['code'], hasLength(6));

    final (quickCode, quick) =
        await call('POST', '/quickmatch', {'mode': 'versus'});
    expect(quickCode, 200);
    expect((jsonDecode(quick) as Map)['code'], hasLength(6));

    final (scoreCode, rank) = await call('POST', '/scores', {
      'board': 'daily-2026-10-03',
      'name': 'Arvind',
      'timeMs': 83450,
      'players': 2,
    });
    expect(scoreCode, 200);
    expect(jsonDecode(rank), {'rank': 1});
    final (boardCode, board) =
        await call('GET', '/leaderboards/daily-2026-10-03');
    expect(boardCode, 200);
    expect((jsonDecode(board) as Map)['entries'], hasLength(1));

    final (eventsCode, _) = await call('POST', '/events', {
      'events': [
        {'name': 'app_open', 'ts': 1696300000000},
      ],
    });
    expect(eventsCode, 204);
    final (missing, _) = await call('GET', '/nothing');
    expect(missing, 404);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
