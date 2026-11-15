import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

/// The 2026-11 genre pass: versus sudden death, the solo growth curve, the
/// base speed and the renamed enemy tiers.
void main() {
  group('versus sudden death', () {
    World arena({double time = 90}) {
      final level = LevelData.generate(
        seed: 5,
        width: 15,
        height: 13,
        players: 2,
        enemyCount: 0,
        brickDensity: 0,
        timeLimit: time,
      );
      return World(level, seed: 5, config: WorldConfig.versus);
    }

    int pillars(World w) => w.grid.positions
        .where((p) => w.grid.atPos(p) == TileType.pillar)
        .length;

    test('at time-up the arena closes in instead of sending Hunters', () {
      final w = arena(time: 1);
      final a = w.addPlayer(name: 'A');
      final b = w.addPlayer(name: 'B');
      a.invincibleFor = 999;
      b.invincibleFor = 999;
      final before = pillars(w);
      for (var i = 0; i < (6 / World.tickDt).round(); i++) {
        w.tick({});
      }
      expect(w.timeUp, isTrue);
      expect(w.enemies.where((e) => e.alive), isEmpty);
      // About one tile every quarter second after a one-second warning.
      expect(pillars(w) - before, greaterThanOrEqualTo(12));
    });

    test('the closing walls end the round', () {
      final w = arena(time: 1);
      w.addPlayer(name: 'A');
      w.addPlayer(name: 'B');
      for (var i = 0; i < (90 / World.tickDt).round() && !w.over; i++) {
        w.tick({});
      }
      expect(w.over, isTrue);
    });
  });

  test('solo growth: bombs and fire climb together, with Speed Ups', () {
    var bombs = 1, fire = 1, speed = 0;
    for (final s in Campaign.stages) {
      if (s.bonus || s.boss != null || s.world > 4) continue;
      switch (s.itemsFor(1).first) {
        case ItemType.bombUp:
          bombs++;
        case ItemType.fireUp:
          fire++;
        case ItemType.speedUp:
          speed++;
        default:
      }
    }
    expect((bombs - fire).abs(), lessThanOrEqualTo(1));
    expect(bombs, greaterThanOrEqualTo(7));
    expect(speed, greaterThanOrEqualTo(3));
  });

  test('co-op item lists are unchanged by the solo curve', () {
    final s = Campaign.byId('1-2')!;
    expect(s.itemsFor(2), s.items);
    expect(s.itemsFor(1).first, ItemType.bombUp);
  });

  test('one Speed Up outruns the fast enemy tier', () {
    expect(Player.baseSpeed + Player.speedStep,
        greaterThan(EnemyKind.grinface.speed));
    expect(Player.baseSpeed, lessThan(EnemyKind.grinface.speed));
  });

  test('old enemy names still resolve', () {
    expect(EnemyKind.byName['Puffball'], EnemyKind.puffball);
    expect(EnemyKind.byName['Hunter Coin'], EnemyKind.hunterCoin);
    expect(EnemyKind.byName['Overlord Pontan'], EnemyKind.overlordPontan);
    expect(EnemyKind.puffball.name, 'Mallow');
  });
}
