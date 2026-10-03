import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

void run(World w, int ticks, [Map<int, PlayerInput> Function(int)? input]) {
  for (var i = 0; i < ticks && !w.over; i++) {
    w.tick(input?.call(i) ?? const {});
  }
}

void main() {
  test('a remote bomb left behind at death goes off on a fuse', () {
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
    final p = w.addPlayer()..applyItem(ItemType.remote);
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    run(w, 20, (_) => {p.id: const PlayerInput(direction: Direction.right)});
    w.spawnEnemy(p.tile, EnemyKind.puffball);
    run(w, 2);
    expect(p.alive, isFalse);
    expect(w.bombs.single.remote, isFalse);
    w
      ..respawn(p)
      ..clearFailure();
    w.enemies.clear();
    run(w, 5 * World.tickRate.round());
    expect(w.bombs, isEmpty);
    expect(p.bombsPlaced, 0);
  });

  test('a respawn never lands inside a closed arena wall', () {
    final def = Campaign.byId('5-10')!;
    final w = World(
      def.level(seed: 1, players: 1),
      seed: 1,
      config: def.config(players: 1, coop: false),
    );
    final p = w.addPlayer()..invincibleFor = 1e9;
    w.enemies.firstWhere((e) => e.kind.boss).hp = 3;
    run(w, 30 * World.tickRate.round());
    final spawn = w.level.playerSpawns.first;
    expect(w.grid.atPos(spawn), TileType.pillar);
    p.alive = false;
    w.respawn(p);
    expect(w.grid.isWalkable(p.tileX, p.tileY), isTrue);
  });

  test('beating a boss after time-up clears the stage despite Hunters', () {
    final def = Campaign.byId('1-10')!;
    final w = World(
      def.level(seed: 1, players: 1),
      seed: 1,
      config: def.config(players: 1, coop: false),
    );
    final p = w.addPlayer()..invincibleFor = 1e9;
    run(w, (def.timeLimit + 1).ceil() * World.tickRate.round());
    expect(w.timeUp, isTrue);
    // Anything that isn't the boss or a Hunter (a mini-boss) is beaten.
    for (final e in w.enemies) {
      if (!e.kind.boss && e.kind != EnemyKind.hunterCoin) e.alive = false;
    }
    final boss = w.enemies.firstWhere((e) => e.kind.boss)
      ..hp = 1
      ..hitCooldown = 0;
    w.flames.add(Flame(x: boss.tileX, y: boss.tileY, ownerId: p.id));
    run(w, 25 * World.tickRate.round());
    expect(boss.alive, isFalse);
    expect(w.cleared, isTrue);
    expect(w.enemies.where((e) => e.alive), isEmpty);
  });

  test('only the first exit wave pays points', () {
    final w = World(
      LevelData.parse('''
###########
#P........#
###########
''', enemyKinds: const []),
      config: Campaign.byId('1-3')!.config(players: 1, coop: false),
    );
    final p = w.addPlayer()..invincibleFor = 1e9;
    w.floorItems.add(
      FloorItem(x: 8, y: 1, type: ItemType.exit, fromBrick: true),
    );
    final scores = <int>[];
    for (var k = 0; k < 4; k++) {
      final before = p.score;
      w.bombs.add(
        Bomb(
          id: 5000 + k,
          x: 7,
          y: 1,
          ownerId: p.id,
          range: 2,
          fuse: 0.01,
          remote: false,
        ),
      );
      run(w, 2);
      // Kill the wave with a second blast once the guards can be hit.
      for (final e in w.enemies) {
        e
          ..hitCooldown = 0
          ..setPosition(8.5, 1.5);
      }
      w.bombs.add(
        Bomb(
          id: 6000 + k,
          x: 6,
          y: 1,
          ownerId: p.id,
          range: 1,
          fuse: 0.01,
          remote: false,
        ),
      );
      for (final e in w.enemies) {
        e.hp = 1;
        w.flames.add(Flame(x: e.tileX, y: e.tileY, ownerId: p.id));
      }
      run(w, 2);
      w.enemies.removeWhere((e) => !e.alive);
      scores.add(p.score - before);
    }
    expect(scores.first, greaterThan(0));
    expect(scores.skip(1), everyElement(0));
  });

  test('bonus and boss arenas keep their exit calm', () {
    for (final id in ['1-5', '1-10']) {
      final def = Campaign.byId(id)!;
      final w = World(
        LevelData.parse('''
###########
#P........#
###########
''', enemyKinds: const []),
        config: def.config(players: 1, coop: false),
      );
      final p = w.addPlayer()..invincibleFor = 1e9;
      w.floorItems.add(
        FloorItem(x: 8, y: 1, type: ItemType.exit, fromBrick: true),
      );
      w.bombs.add(
        Bomb(
          id: 1,
          x: 7,
          y: 1,
          ownerId: p.id,
          range: 2,
          fuse: 0.01,
          remote: false,
        ),
      );
      run(w, 2);
      expect(
        w.enemies.where((e) => e.kind == EnemyKind.doorWarden),
        isEmpty,
        reason: id,
      );
    }
  });

  test('a blast reaches a Wall Pass player inside the brick it breaks', () {
    final w = World(
      LevelData.parse('''
#########
#P.+....#
#########
''', enemyKinds: const []),
    );
    final p = w.addPlayer()
      ..applyItem(ItemType.wallPass)
      ..setPosition(3.5, 1.5);
    w.bombs.add(
      Bomb(
        id: 1,
        x: 1,
        y: 1,
        ownerId: Bomb.enemyOwner,
        range: 3,
        fuse: 0.01,
        remote: false,
      ),
    );
    run(w, 3);
    expect(p.alive, isFalse);
    expect(w.flameAt(4, 1), isNull, reason: 'the brick still stops it');
  });

  test('copyWith keeps every field', () {
    const c = WorldConfig(keepItemsOnDeath: true);
    expect(c.copyWith(sharedLives: 2).keepItemsOnDeath, isTrue);
  });
}
