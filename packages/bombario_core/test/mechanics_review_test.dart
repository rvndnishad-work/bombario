import 'dart:convert';

import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

// Fixes from the second mechanics review (2026-10-11).

void run(World w, double seconds, [Map<int, PlayerInput> input = const {}]) {
  for (var i = 0; i < (seconds * World.tickRate).round() && !w.over; i++) {
    w.tick(input);
  }
}

List<ItemType> hiddenItems(LevelData level) => [
      for (final p in level.grid.positions)
        if (level.grid.hiddenAt(p.x, p.y) case final i? when i != ItemType.exit)
          i,
    ];

void main() {
  test('solo never gets an item that only helps teammates', () {
    for (final stage in Campaign.stages) {
      if (stage.bonus || stage.isBoss) continue;
      for (var seed = 0; seed < 10; seed++) {
        final items = hiddenItems(stage.level(seed: seed, players: 1));
        for (final item in StageDef.coopOnlyItems) {
          expect(items, isNot(contains(item)),
              reason: '${stage.id} seed $seed');
        }
      }
    }
    // Teams still get them.
    final duo = hiddenItems(Campaign.byId('2-6')!.level(seed: 1, players: 2));
    expect(duo, contains(ItemType.tether));
  });

  test('no regular stage sends a Hunter Coin', () {
    for (final stage in Campaign.stages) {
      expect(
          stage.enemies.map((e) => e.$1), isNot(contains(EnemyKind.hunterCoin)),
          reason: stage.id);
    }
  });

  test('warp doors never cover the exit, a power-up or a buried enemy', () {
    for (final stage in Campaign.stages.where((s) => s.warpPairs > 0)) {
      for (var seed = 0; seed < 100; seed++) {
        final level = stage.level(seed: seed, players: 1);
        final buried = {for (final e in level.enemySpawns) e.pos};
        for (final p in level.grid.positions) {
          if (level.grid.featureAt(p.x, p.y) != TileFeature.warp) continue;
          expect(level.grid.hiddenAt(p.x, p.y), isNull,
              reason: '${stage.id} seed $seed at $p');
          expect(buried, isNot(contains(p)),
              reason: '${stage.id} seed $seed at $p');
        }
      }
    }
  });

  test("3-3's locked room keeps its power-up and nothing else", () {
    final stage = Campaign.byId('3-3')!;
    // The room behind the gate in the hand-made layout.
    bool inRoom(GridPos p) => p.y == 5 && p.x >= 9 && p.x <= 11;
    for (var seed = 0; seed < 100; seed++) {
      final level = stage.level(seed: seed, players: 1);
      final inside = [
        for (final p in level.grid.positions)
          if (inRoom(p)) level.grid.hiddenAt(p.x, p.y),
      ];
      expect(inside.whereType<ItemType>().toList(), [ItemType.kick],
          reason: 'seed $seed');
      expect(level.enemySpawns.where((e) => inRoom(e.pos)), isEmpty,
          reason: 'seed $seed');
    }
  });

  group('time-up Hunters', () {
    World timedOut() {
      final w = World(
        LevelData.generate(seed: 3, players: 1, enemyCount: 1),
        seed: 3,
        config: Campaign.first.config(players: 1, coop: false),
      );
      w.addPlayer().invincibleFor = 999;
      w.timeLeft = 0.05;
      return w;
    }

    test('at most three are out at once', () {
      final w = timedOut();
      run(w, 120);
      final hunters = w.enemies
          .where((e) => e.alive && e.kind == EnemyKind.hunterCoin)
          .length;
      expect(hunters, World.maxHunters);
    });

    test('pay a tenth of their points', () {
      final w = timedOut();
      run(w, 0.2);
      final hunter =
          w.enemies.firstWhere((e) => e.kind == EnemyKind.hunterCoin);
      expect(hunter.killPoints, 800);
      final snap = WorldSnapshot.fromJson(
          jsonDecode(jsonEncode(WorldSnapshot.of(w, tick: 1).toJson()))
              as Map<String, dynamic>);
      expect(snap.enemies.firstWhere((e) => e.id == hunter.id).killPoints, 800);
    });
  });

  test('a buried nest still hatches, but its Pebbles pay nothing', () {
    final w = World(
      LevelData.parse('''
#########
#P......#
#.#.#.#.#
#.......#
#########
''', enemyKinds: const []),
      config: Campaign.first.config(players: 1, coop: false),
    );
    w.addPlayer().invincibleFor = 999;
    w.grid.set(5, 3, TileType.brick);
    final nest = w.spawnEnemy(const GridPos(5, 3), EnemyKind.moleNest);
    run(w, World.nestInterval + 0.1);
    final kid = w.enemies.singleWhere((e) => e.parentId == nest.id);
    expect(kid.killPoints, 0);
    expect(EnemyState.of(kid).killPoints, 0);
  });
}
