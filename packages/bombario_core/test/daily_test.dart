import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

void main() {
  test('the same date always gives the same dungeon', () {
    final a = DailyDungeon.forDate(DateTime.utc(2026, 10, 3, 1));
    final b = DailyDungeon.forDate(DateTime.utc(2026, 10, 3, 23));
    expect(a.id, '2026-10-03');
    expect(a.board, 'daily-2026-10-03');
    expect(a.seed, b.seed);
    expect(a.stage.name, b.stage.name);
    expect(a.stage.enemies, b.stage.enemies);
  });

  test('a month of dungeons all build and differ', () {
    final seeds = <int>{};
    for (var d = 0; d < 31; d++) {
      final day = DailyDungeon.forDate(DateTime.utc(2026, 10, 1 + d));
      seeds.add(day.seed);
      expect(day.stage.world, inInclusiveRange(1, 5));
      final level = day.stage.level(seed: day.seed, players: 1);
      expect(level.playerSpawns, hasLength(1));
      expect(level.enemySpawns, isNotEmpty);
      final world =
          World(level, config: day.stage.config(players: 1, coop: false));
      for (var i = 0; i < 60; i++) {
        world.tick({});
      }
    }
    expect(seeds.length, 31);
  });
}
