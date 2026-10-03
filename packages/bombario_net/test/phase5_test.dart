import 'dart:convert';
import 'dart:io';

import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
import 'package:test/test.dart';

import 'room_server_test.dart' show waitFor;

Future<(int, Map<String, dynamic>?)> post(
    RoomServer server, String path, Object? body) async {
  final client = HttpClient();
  try {
    final req = await client.post('127.0.0.1', server.port, path);
    req.write(body is String ? body : jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (
      res.statusCode,
      text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('protocol', () {
    test('lobby rows carry bot and skin, with old-style defaults', () {
      const row = LobbyPlayer(
          id: 3,
          name: 'Bot Pip',
          ready: true,
          isHost: false,
          bot: true,
          skin: 'robot');
      final back = LobbyPlayer.fromJson(
          jsonDecode(jsonEncode(row.toJson())) as Map<String, dynamic>);
      expect(back.bot, isTrue);
      expect(back.skin, 'robot');
      // A row from an older server has neither field.
      final old = LobbyPlayer.fromJson(
          {'id': 1, 'name': 'A', 'ready': false, 'host': true});
      expect(old.bot, isFalse);
      expect(old.skin, 'classic');
      expect(
          const LobbyPlayer(id: 1, name: 'A', ready: false, isHost: true)
              .toJson()
              .containsKey('bot'),
          isFalse);
    });

    test('lobby state round-trips quick and startsIn', () {
      const state = LobbyState(
          mode: GameMode.coop, quick: true, startsIn: 12, stage: '1-1');
      final back = LobbyState.fromJson(state.toJson());
      expect(back.quick, isTrue);
      expect(back.startsIn, 12);
      expect(back.mode, GameMode.coop);
      final plain = LobbyState.fromJson(const LobbyState().toJson());
      expect(plain.quick, isFalse);
      expect(plain.startsIn, isNull);
    });
  });

  group('bots in rooms', () {
    late RoomServer server;
    setUp(() async {
      server = await RoomServer.start(seed: 5, botSkins: const ['robot']);
    });
    tearDown(() => server.close());

    Future<GameClient> join(String name, {String skin = 'classic'}) async {
      final c = await GameClient.connectLocal('127.0.0.1', server.port,
          playerName: name, skin: skin);
      await waitFor(() => c.clientId != null || c.lastError != null);
      return c;
    }

    test('the host adds and removes bots; they are always ready', () async {
      final a = await join('Alice', skin: 'ninja');
      final b = await join('Bob');
      b.addBot(); // not the host: ignored
      a.addBot(skill: BotSkill.hard);
      a.addBot();
      await waitFor(() => b.lobby.bots.length == 2);
      final bots = b.lobby.bots.toList();
      expect(bots.every((p) => p.ready && p.connected), isTrue);
      expect(bots.every((p) => p.name.startsWith('Bot ')), isTrue);
      expect(bots.map((p) => p.name).toSet(), hasLength(2));
      expect(bots.every((p) => p.skin == 'robot'), isTrue);
      expect(
          b.lobby.players.firstWhere((p) => p.name == 'Alice').skin, 'ninja');
      expect(server.room.clients.where((c) => c.isBot).first.botSkill,
          BotSkill.hard);

      // Full: a fifth seat is refused...
      a.addBot();
      await waitFor(() => a.lastError != null);
      expect(a.lastError, 'Room is full');

      a.removeBot(bots.first.id);
      await waitFor(() => b.lobby.bots.length == 1);
      expect(b.lobby.bots.single.id, bots.last.id);
      a.removeBot();
      await waitFor(() => b.lobby.bots.isEmpty);
      await a.close();
      await b.close();
    });

    test('a person bumps a bot out of a full lobby', () async {
      final a = await join('Alice');
      for (var i = 0; i < 3; i++) {
        server.room.addBot();
      }
      await waitFor(() => a.lobby.players.length == 4);
      final b = await join('Bob');
      expect(b.lastError, isNull);
      await waitFor(() =>
          a.lobby.players.length == 4 &&
          a.lobby.players.any((p) => p.name == 'Bob'));
      expect(a.lobby.bots, hasLength(2));
      await a.close();
      await b.close();
    });

    test('a human and a bot play versus; the bot is driven server-side',
        () async {
      final a = await join('Alice', skin: 'ninja');
      a.addBot(skill: BotSkill.hard);
      await waitFor(() => a.lobby.players.length == 2);
      a.start();
      await waitFor(() => a.snapshot != null && a.myPlayerId != null);
      final botSeat = server.room.clients.firstWhere((c) => c.isBot);
      final botId = botSeat.playerId!;
      expect(a.snapshot!.player(a.myPlayerId!)!.skin, 'ninja');
      expect(a.snapshot!.player(botId)!.skin, 'robot');
      final start = a.snapshot!.player(botId)!;
      // The bot walks off without anyone sending it inputs over a socket.
      await waitFor(() {
        final now = a.snapshot!.player(botId)!;
        return (now.x - start.x).abs() + (now.y - start.y).abs() > 1;
      });
      expect(server.room.world!.playerById(botId)!.skin, 'robot');
      // Its inputs went through the per-tick queue and were acknowledged.
      expect(botSeat.lastInputSeq, greaterThan(0));
      await a.close();
    });

    test('bots alone do not keep a room alive', () async {
      final a = await join('Alice');
      a.addBot();
      await waitFor(() => a.lobby.players.length == 2);
      await a.close();
      await waitFor(() => server.room.clients.isEmpty);
    });

    test('setSkin changes the lobby row and the next match', () async {
      final a = await join('Alice');
      final b = await join('Bob');
      a.setSkin('pirate');
      await waitFor(() =>
          b.lobby.players.any((p) => p.name == 'Alice' && p.skin == 'pirate'));
      a.setSkin('x' * 40); // too long: ignored
      a.start();
      await waitFor(() => b.snapshot != null && a.myPlayerId != null);
      expect(b.snapshot!.player(a.myPlayerId!)!.skin, 'pirate');
      await a.close();
      await b.close();
    });

    test('a room of bots plays a whole versus round deterministically', () {
      final room = Room(seed: 9);
      for (var i = 0; i < 4; i++) {
        room.addBot(skill: BotSkill.values[i % 3]);
      }
      room.startMatch();
      final w = room.world!;
      for (var i = 0; i < 30 * 400 && room.state == RoomState.playing; i++) {
        room.tick();
      }
      expect(w.over, isTrue);
      expect(w.winnerId, isNotNull);
      room.close();
    });
  });

  group('quick match', () {
    late RoomServer cloud;
    setUp(() async {
      cloud = await RoomServer.start(
        seed: 11,
        serveDefaultRoom: false,
        quickStartDelay: const Duration(milliseconds: 600),
      );
    });
    tearDown(() => cloud.close());

    Future<GameClient> joinCode(String code, String name) async {
      final c = await GameClient.connect(
          Uri.parse('ws://127.0.0.1:${cloud.port}/rooms/$code'),
          playerName: name);
      await waitFor(() => c.clientId != null || c.lastError != null);
      return c;
    }

    test('bad bodies are refused', () async {
      expect((await post(cloud, '/quickmatch', {'mode': 'solo'})).$1, 400);
      expect((await post(cloud, '/quickmatch', 'nope')).$1, 400);
      expect((await post(cloud, '/quickmatch', [1])).$1, 400);
    });

    test('players share an open room until it starts, then fill with bots',
        () async {
      final (s1, r1) = await post(cloud, '/quickmatch', {'mode': 'versus'});
      final (_, r2) = await post(cloud, '/quickmatch', {'mode': 'versus'});
      final (_, r3) = await post(cloud, '/quickmatch', {'mode': 'coop'});
      expect(s1, 200);
      final code = r1!['code'] as String;
      expect(r2!['code'], code);
      expect(r3!['code'], isNot(code));

      final a = await joinCode(code, 'Alice');
      await waitFor(() => a.lobby.quick && a.lobby.startsIn != null);
      expect(a.lobby.mode, GameMode.versus);
      // Quick rooms keep their mode.
      a.setMode(GameMode.coop);
      final b = await joinCode(code, 'Bob');
      await waitFor(() => a.lobby.players.length == 2);
      expect(a.lobby.mode, GameMode.versus);

      // The countdown runs out: two bots join and the match starts.
      await waitFor(() => a.myPlayerId != null && a.snapshot != null);
      expect(a.snapshot!.players, hasLength(4));
      expect(a.lobby.bots, hasLength(2));
      final room = cloud.hub.byCode(code)!;
      expect(room.quickStarted, isTrue);

      // A started room takes nobody new.
      final (_, r4) = await post(cloud, '/quickmatch', {'mode': 'versus'});
      expect(r4!['code'], isNot(code));

      final (_, info) = await getJson(cloud, '/rooms/$code');
      expect(info['quick'], isTrue);
      await a.close();
      await b.close();
    });

    test('co-op quick match pairs a lone player with one bot on 1-1', () async {
      final (_, r) = await post(cloud, '/quickmatch', {'mode': 'coop'});
      final a = await joinCode(r!['code'] as String, 'Solo');
      await waitFor(() => a.snapshot != null && a.stageId != null);
      expect(a.stageId, '1-1');
      expect(a.snapshot!.players, hasLength(2));
      expect(a.lobby.bots, hasLength(1));
      await a.close();
    });

    test('four humans start a quick match at once', () async {
      final slow = await RoomServer.start(
          seed: 12,
          serveDefaultRoom: false,
          quickStartDelay: const Duration(minutes: 5));
      addTearDown(slow.close);
      final clients = <GameClient>[];
      for (var i = 0; i < 4; i++) {
        final (_, r) = await post(slow, '/quickmatch', {'mode': 'versus'});
        clients.add(await GameClient.connect(
            Uri.parse('ws://127.0.0.1:${slow.port}/rooms/${r!['code']}'),
            playerName: 'P$i'));
      }
      expect(clients.map((c) => c.uri).toSet(), hasLength(1));
      await waitFor(() => clients.every((c) => c.snapshot != null));
      expect(clients.first.snapshot!.players, hasLength(4));
      expect(clients.first.lobby.bots, isEmpty);
      for (final c in clients) {
        await c.close();
      }
    });
  });
}

Future<(int, Map<String, dynamic>)> getJson(
    RoomServer server, String path) async {
  final client = HttpClient();
  try {
    final req = await client.get('127.0.0.1', server.port, path);
    final res = await req.close();
    return (
      res.statusCode,
      jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>
    );
  } finally {
    client.close(force: true);
  }
}
