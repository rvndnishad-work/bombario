import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

import 'world_test.dart' show makeWorld, run;

/// Rules matched to the 1985 original's feel.
void main() {
  test('an enemy walking into a freshly dropped bomb turns around', () {
    final w = makeWorld('''
#########
#P...e..#
#########
''', kinds: [EnemyKind.pebble]);
    w.addPlayer();
    final e = w.enemies.single;
    // Mid-way from (5,1) to (4,1), heading left.
    e.direction = Direction.left;
    e.target = const GridPos(4, 1);
    e.setPosition(5.2, 1.5);
    w.bombs.add(Bomb(
        id: 999, x: 4, y: 1, ownerId: 0, range: 1, fuse: 5, remote: false));
    w.tick(const {});
    expect(e.direction, Direction.right);
    expect(e.x, greaterThan(5.2));
    run(w, 1);
    expect(e.tileX, greaterThanOrEqualTo(5), reason: 'never enters the bomb');
  });

  test('each extra enemy caught in one blast is worth double', () {
    expect(World.multiKillPoints(100, 0), 100);
    expect(World.multiKillPoints(100, 1), 200);
    expect(World.multiKillPoints(100, 2), 400);

    final w = makeWorld('''
#######
#P.eee#
#######
''', kinds: [EnemyKind.shellback]);
    final p = w.addPlayer();
    p.fireRange = 5;
    p.applyItem(ItemType.flamePass);
    for (final e in w.enemies) {
      e.frozenFor = 99; // hold still; a frozen enemy shatters to any flame
    }
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    run(w, Bomb.defaultFuse + 0.05);
    expect(w.enemies.where((e) => e.alive), isEmpty);
    final base = EnemyKind.shellback.points;
    expect(p.score, base + base * 2 + base * 4);
  });

  test('brushing past an enemy is forgiven, a real overlap kills', () {
    final w = makeWorld('''
#######
#P.+e+#
#######
''', kinds: [EnemyKind.pebble]);
    final p = w.addPlayer();
    final e = w.enemies.single; // boxed in by bricks, so it stays put
    final reach = e.kind.size + Player.halfBox;
    p.setPosition(e.x - reach + 0.1, e.y);
    w.tick(const {});
    expect(p.alive, isTrue);
    p.setPosition(e.x - reach + World.contactGrace + 0.05, e.y);
    w.tick(const {});
    expect(p.alive, isFalse);
  });

  test('bombing an uncovered power-up burns it and releases a wave', () {
    final w = makeWorld('''
#######
#P..U.#
#######
''', kinds: const []);
    final p = w.addPlayer();
    p.fireRange = 5;
    p.applyItem(ItemType.flamePass);
    // First bomb uncovers it; the second burns it.
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    run(w, Bomb.defaultFuse + 0.1);
    expect(w.floorItems, hasLength(1));
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    final events = run(w, Bomb.defaultFuse + 0.1);
    expect(w.floorItems, isEmpty);
    expect(events.whereType<ItemBurned>().single.releasedWave, isTrue);
    expect(w.enemies.where((e) => e.kind == EnemyKind.doorWarden),
        hasLength(WorldConfig.solo.exitGuardCount));
  });

  test('a power-up dropped by a fallen player just burns', () {
    final w = makeWorld('''
#######
#P....#
#######
''', kinds: const []);
    final p = w.addPlayer();
    p.fireRange = 5;
    p.applyItem(ItemType.flamePass);
    w.floorItems.add(FloorItem(x: 4, y: 1, type: ItemType.bombUp));
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    final events = run(w, Bomb.defaultFuse + 0.1);
    expect(w.floorItems, isEmpty);
    expect(events.whereType<ItemBurned>().single.releasedWave, isFalse);
    expect(w.enemies, isEmpty);
  });

  List<ItemType> powerUps(LevelData level) => [
        for (var y = 0; y < level.grid.height; y++)
          for (var x = 0; x < level.grid.width; x++)
            if (level.grid.hiddenAt(x, y) case final t? when t != ItemType.exit)
              t,
      ];

  test('a solo stage hides one power-up plus the exit', () {
    for (final stage in Campaign.stages) {
      if (stage.bonus || stage.isBoss) continue;
      final level = stage.level(seed: 7, players: 1);
      expect(powerUps(level), hasLength(1), reason: stage.id);
    }
    expect(powerUps(Campaign.byId('1-1')!.level(seed: 1, players: 1)),
        [ItemType.fireUp]);
    // Co-op: one each.
    expect(powerUps(Campaign.byId('1-2')!.level(seed: 1, players: 3)),
        hasLength(3));
  });

  test('solo keeps stat power-ups on death, as in the original', () {
    final config = Campaign.byId('1-2')!.config(players: 1, coop: false);
    expect(config.keepItemsOnDeath, isTrue);
    final w = makeWorld('''
#######
#P...e#
#######
''', config: config);
    final p = w.addPlayer();
    p.applyItem(ItemType.fireUp);
    p.applyItem(ItemType.bombUp);
    p.applyItem(ItemType.wallPass);
    final e = w.enemies.single;
    e.setPosition(p.x, p.y);
    w.tick(const {});
    expect(p.alive, isFalse);
    expect(p.items, [ItemType.fireUp, ItemType.bombUp]);
    expect(p.fireRange, 2);
    expect(p.wallPass, isFalse);
    expect(w.floorItems, isEmpty);
  });

  test('each start deals stage 1-1 bricks out afresh, pillars stay put', () {
    final stage = Campaign.byId('1-1')!;
    LevelData at(int seed) => stage.level(seed: seed, players: 1);
    String tiles(LevelData l, TileType t) => [
          for (var y = 0; y < l.grid.height; y++)
            for (var x = 0; x < l.grid.width; x++)
              if (l.grid.at(x, y) == t) '$x,$y',
        ].join(' ');
    int count(LevelData l, TileType t) =>
        tiles(l, t).split(' ').where((s) => s.isNotEmpty).length;
    final a = at(1), b = at(2);
    expect(tiles(a, TileType.pillar), tiles(b, TileType.pillar));
    expect(tiles(a, TileType.brick), isNot(tiles(b, TileType.brick)));
    expect(count(a, TileType.brick), count(b, TileType.brick));
    // Same seed, same maze: rooms and replays stay in step.
    expect(tiles(at(7), TileType.brick), tiles(at(7), TileType.brick));
    for (final l in [a, b, at(3), at(4)]) {
      final spawn = l.playerSpawns.first;
      // The spawn corner is clear and enemies start well away.
      for (final (dx, dy) in [(0, 0), (1, 0), (0, 1), (2, 0), (0, 2)]) {
        expect(l.grid.at(spawn.x + dx, spawn.y + dy), isNot(TileType.brick));
      }
      expect(l.enemySpawns, hasLength(6));
      for (final e in l.enemySpawns) {
        expect((e.pos.x - spawn.x).abs() + (e.pos.y - spawn.y).abs(),
            greaterThanOrEqualTo(5));
      }
      // One power-up and the exit, each under a brick.
      final hidden = [
        for (var y = 0; y < l.grid.height; y++)
          for (var x = 0; x < l.grid.width; x++)
            if (l.grid.hiddenAt(x, y) case final item?) (x, y, item),
      ];
      expect(hidden.map((h) => h.$3),
          unorderedEquals([ItemType.fireUp, ItemType.exit]));
      for (final (x, y, _) in hidden) {
        expect(l.grid.at(x, y), TileType.brick);
      }
    }
  });
}
