import 'dart:convert';

import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

void main() {
  group('versus', () {
    World arena() {
      final level = LevelData.generate(
        seed: 3,
        width: 15,
        height: 13,
        players: 2,
        enemyCount: 0,
        brickDensity: 0.3,
      );
      return World(level, seed: 3, config: WorldConfig.versus);
    }

    test('last player standing wins', () {
      final w = arena();
      final a = w.addPlayer(name: 'A');
      final b = w.addPlayer(name: 'B');
      // Trap B next to A's bomb.
      b.setPosition(a.x + 1, a.y);
      a.applyItem(ItemType.flamePass);
      w.tick({a.id: const PlayerInput(placeBomb: true)});
      for (var i = 0; i < 90 && !w.over; i++) {
        w.tick({});
      }
      expect(w.over, isTrue);
      expect(w.winnerId, a.id);
      expect(b.alive, isFalse);
    });

    test('both dying in the same blast is a draw', () {
      final w = arena();
      final a = w.addPlayer(name: 'A');
      final b = w.addPlayer(name: 'B');
      b.setPosition(a.x + 1, a.y);
      w.tick({a.id: const PlayerInput(placeBomb: true)});
      for (var i = 0; i < 90 && !w.over; i++) {
        w.tick({});
      }
      expect(w.winnerId, -1);
      expect(w.events.whereType<MatchEnded>().single.winnerId, -1);
    });

    test('a single player never ends the round', () {
      final w = arena();
      final a = w.addPlayer(name: 'A');
      w.tick({a.id: const PlayerInput(placeBomb: true)});
      for (var i = 0; i < 90; i++) {
        w.tick({});
      }
      expect(a.alive, isFalse);
      expect(w.winnerId, isNull);
    });
  });

  group('snapshot', () {
    test('round-trips through JSON', () {
      final level = LevelData.generate(seed: 5, players: 2, enemyCount: 3);
      final w = World(level, seed: 5);
      final a = w.addPlayer(name: 'Alice');
      w.addPlayer(name: 'Bob');
      a.applyItem(ItemType.remote);
      w.tick({a.id: const PlayerInput(placeBomb: true)});
      w.tick({a.id: const PlayerInput(direction: Direction.right)});

      final snap = WorldSnapshot.of(w, tick: 2);
      final decoded = WorldSnapshot.fromJson(
          jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>);

      expect(decoded.tick, 2);
      expect(decoded.timeLeft, closeTo(w.timeLeft, 1e-9));
      expect(decoded.players.length, 2);
      expect(decoded.player(a.id)!.name, 'Alice');
      expect(decoded.player(a.id)!.x, closeTo(a.x, 1e-9));
      expect(decoded.player(a.id)!.remote, isTrue);
      expect(decoded.player(a.id)!.facing, Direction.right);
      expect(decoded.bombs.single.remote, isTrue);
      expect(decoded.enemies.length, 3);
      expect(decoded.enemies.first.kind, 'Puffball');
      for (final p in w.grid.positions) {
        expect(decoded.grid.atPos(p), w.grid.atPos(p));
      }
      // Hidden items are not leaked.
      var hidden = 0;
      for (final p in decoded.grid.positions) {
        if (decoded.grid.hiddenAt(p.x, p.y) != null) hidden++;
      }
      expect(hidden, 0);
    });
  });
}
