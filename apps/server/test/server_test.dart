import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Boots the real entry point and talks to it over HTTP.
void main() {
  test('the entry point serves health and creates rooms', () async {
    final port = 20000 + DateTime.now().millisecond;
    final proc = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/server.dart'],
      environment: {'PORT': '$port'},
    );
    addTearDown(proc.kill);
    await proc.stdout
        .transform(utf8.decoder)
        .firstWhere((line) => line.contains('listening'))
        .timeout(const Duration(seconds: 60));

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<(int, String)> call(String method, String path) async {
      final req = await client.openUrl(
          method, Uri.parse('http://127.0.0.1:$port$path'));
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    final (healthCode, _) = await call('GET', '/health');
    expect(healthCode, 200);
    final (createCode, body) = await call('POST', '/rooms');
    expect(createCode, 201);
    expect((jsonDecode(body) as Map)['code'], hasLength(6));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
