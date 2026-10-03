import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

/// A small open arena: pillars on the ring and at even/even tiles.
const openArena = '''
#######
#P....#
#.#.#.#
#.....#
#.#.#.#
#.....#
#######
''';

World makeWorld(String ascii,
    {WorldConfig config = WorldConfig.solo,
    List<EnemyKind> kinds = const [EnemyKind.puffball]}) {
  final level = LevelData.parse(ascii, enemyKinds: kinds, timeLimit: 10);
  return World(level, seed: 1, config: config);
}

/// Runs [seconds] of simulation with the same input every tick and returns
/// every event that happened along the way.
List<GameEvent> run(World w, double seconds,
    {Map<int, PlayerInput> inputs = const {}}) {
  final ticks = (seconds * World.tickRate).round();
  final all = <GameEvent>[];
  for (var i = 0; i < ticks; i++) {
    w.tick(inputs);
    all.addAll(w.events);
  }
  return all;
}

void main() {
  group('level parsing', () {
    test('reads pillars, bricks, spawns and hidden items', () {
      final level = LevelData.parse('''
#####
#P+E#
#eU.#
#####
''');
      expect(level.grid.width, 5);
      expect(level.grid.height, 4);
      expect(level.grid.at(0, 0), TileType.pillar);
      expect(level.grid.at(2, 1), TileType.brick);
      expect(level.grid.at(3, 1), TileType.brick);
      expect(level.grid.hiddenAt(3, 1), ItemType.exit);
      expect(level.grid.hiddenAt(2, 2), ItemType.bombUp);
      expect(level.playerSpawns, [const GridPos(1, 1)]);
      expect(level.enemySpawns.single.pos, const GridPos(1, 2));
    });

    test('generator produces a valid classic stage', () {
      final level = LevelData.generate(seed: 42, players: 2, enemyCount: 5);
      expect(level.grid.width, 31);
      expect(level.playerSpawns.length, 2);
      expect(level.enemySpawns.length, 5);
      // Spawn safe zones are clear.
      for (final s in level.playerSpawns) {
        expect(level.grid.at(s.x, s.y), TileType.floor);
        expect(level.grid.at(s.x + (s.x == 1 ? 1 : -1), s.y), TileType.floor);
      }
      // Exactly one exit, hidden under a brick.
      var exits = 0;
      for (final p in level.grid.positions) {
        if (level.grid.hiddenAt(p.x, p.y) == ItemType.exit) {
          exits++;
          expect(level.grid.atPos(p), TileType.brick);
        }
      }
      expect(exits, 1);
      // Same seed, same level.
      final again = LevelData.generate(seed: 42, players: 2, enemyCount: 5);
      for (final p in level.grid.positions) {
        expect(again.grid.atPos(p), level.grid.atPos(p));
      }
    });
  });

  group('movement', () {
    test('moves at base speed along an open row', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.right)});
      expect(p.x, closeTo(1.5 + Player.baseSpeed, 0.01));
      expect(p.y, closeTo(1.5, 1e-9));
    });

    test('stops flush against a pillar', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      run(w, 3, inputs: {p.id: const PlayerInput(direction: Direction.right)});
      // Right wall is column 6; the box edge should rest at x = 6.
      expect(p.x, closeTo(6 - Player.halfBox, 0.001));
    });

    test('cornering assist slides into the open lane', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      // Stand slightly left of the column-3 lane, below the pillar at (2,2).
      p.setPosition(3.2, 1.5);
      run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.down)});
      // Should have slid to x = 3.5 and gone down the lane.
      expect(p.x, closeTo(3.5, 0.01));
      expect(p.y, greaterThan(2.5));
    });

    test('cannot walk through bricks without Wall Pass', () {
      final w = makeWorld('''
#####
#P+.#
#####
''');
      final p = w.addPlayer();
      run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.right)});
      expect(p.x, lessThan(2));
      p.applyItem(ItemType.wallPass);
      run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.right)});
      expect(p.x, greaterThan(2.5));
    });
  });

  group('bombs and flames', () {
    test('bomb explodes after its fuse and flames expire', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      expect(w.bombs.length, 1);
      expect(w.events.whereType<BombPlaced>().length, 1);
      run(w, Bomb.defaultFuse - 0.1,
          inputs: {p.id: const PlayerInput(direction: Direction.right)});
      expect(w.bombs.length, 1);
      run(w, 0.2);
      expect(w.bombs, isEmpty);
      expect(w.flames, isNotEmpty);
      expect(w.flameAt(1, 1), isNotNull);
      expect(w.flameAt(2, 1), isNotNull, reason: 'range 1 reaches one tile');
      expect(w.flameAt(3, 1), isNull);
      run(w, Flame.duration + 0.1);
      expect(w.flames, isEmpty);
    });

    test('respects the bomb limit and raises it with Bomb Up', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      run(w, 0.5,
          inputs: {p.id: const PlayerInput(direction: Direction.right)});
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      expect(w.bombs.length, 1, reason: 'one bomb at a time by default');
      p.applyItem(ItemType.bombUp);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      expect(w.bombs.length, 2);
    });

    test('player can walk off their own bomb but not back onto it', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      run(w, 0.5,
          inputs: {p.id: const PlayerInput(direction: Direction.right)});
      expect(p.x, greaterThan(2.4));
      run(w, 0.5, inputs: {p.id: const PlayerInput(direction: Direction.left)});
      expect(p.x, greaterThanOrEqualTo(2 + Player.halfBox - 0.01),
          reason: 'blocked by the bomb tile');
    });

    test('flames destroy bricks, reveal items and stop there', () {
      final w = makeWorld('''
#######
#P+U+.#
#######
''');
      final p = w.addPlayer();
      p.fireRange = 5;
      p.applyItem(ItemType.flamePass);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      final events = run(w, Bomb.defaultFuse + 0.05);
      expect(w.grid.at(2, 1), TileType.floor);
      expect(w.grid.at(3, 1), TileType.brick,
          reason: 'flame stops at first brick');
      expect(events.whereType<BrickDestroyed>().length, 1);
      // Blow the second brick to reveal the item.
      run(w, 1);
      p.setPosition(2.5, 1.5);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      p.setPosition(1.5, 1.5);
      run(w, Bomb.defaultFuse + 0.05);
      expect(w.floorItems.single.type, ItemType.bombUp);
      // Pick it up.
      p.setPosition(3.5, 1.5);
      w.tick({});
      expect(p.maxBombs, 2);
      expect(w.floorItems, isEmpty);
    });

    test('chain reactions detonate in the same tick', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      p.maxBombs = 3;
      p.remote = true; // so fuses don't matter
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      p.setPosition(2.5, 1.5);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      p.setPosition(3.5, 1.5);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      expect(w.bombs.length, 3);
      p.setPosition(5.5, 5.5);
      w.tick({p.id: const PlayerInput(action: true)}); // detonates the oldest
      expect(w.bombs, isEmpty);
      expect(w.events.whereType<BombExploded>().length, 3);
      expect(p.bombsPlaced, 0);
    });

    test('a flame kills the player who stands in it', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      final events = run(w, Bomb.defaultFuse + 0.05);
      expect(p.alive, isFalse);
      expect(events.whereType<PlayerDied>().single.killerId, p.id);
      expect(w.failed, isTrue);
    });

    test('Flame Pass and Mystery protect from flames', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      p.applyItem(ItemType.flamePass);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      run(w, Bomb.defaultFuse + 0.05);
      expect(p.alive, isTrue);
    });

    test('bombing the exit spawns guards', () {
      final w = makeWorld('''
#####
#P.E#
#####
''');
      final p = w.addPlayer();
      p.fireRange = 2;
      p.applyItem(ItemType.flamePass);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      run(w, Bomb.defaultFuse + 0.05);
      expect(w.exitRevealed, isTrue);
      final before = w.enemies.length;
      p.invincibleFor = 100; // the guards spawn next to us
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      final events = run(w, Bomb.defaultFuse + 0.05);
      expect(events.whereType<ExitBombed>(), isNotEmpty);
      expect(w.enemies.length, before + 3);
    });
  });

  group('enemies', () {
    test('a wandering enemy moves and stays on walkable tiles', () {
      final w = makeWorld('''
#######
#P....#
#.#.#.#
#....e#
#.#.#.#
#.....#
#######
''');
      final e = w.enemies.single;
      final start = GridPos(e.tileX, e.tileY);
      var moved = false;
      for (var i = 0; i < 90; i++) {
        w.tick({});
        expect(w.grid.at(e.tileX, e.tileY), isNot(TileType.pillar));
        if (e.tile != start) moved = true;
      }
      expect(moved, isTrue);
    });

    test('a flame kills an enemy and credits the bomb owner', () {
      final w = makeWorld('''
#####
#P.e#
#####
''');
      final p = w.addPlayer();
      p.fireRange = 2;
      p.applyItem(ItemType.flamePass);
      final e = w.enemies.single;
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      final events = run(w, Bomb.defaultFuse + 0.05);
      expect(e.alive, isFalse);
      expect(p.score, greaterThanOrEqualTo(EnemyKind.puffball.points));
      expect(events.whereType<EnemyDied>().single.killerId, p.id);
    });

    test('touching an enemy kills the player', () {
      final w = makeWorld('''
#####
#Pe.#
#####
''');
      final p = w.addPlayer();
      // The enemy wanders in a dead-end corridor, so it must bump into us.
      final events = run(w, 2.5);
      expect(p.alive, isFalse);
      expect(events.whereType<PlayerDied>().single.killerId, -1);
    });

    test('a chaser walks towards the player', () {
      final w = makeWorld('''
#########
#P.....e#
#########
''', kinds: [EnemyKind.blueDrop]);
      final p = w.addPlayer();
      p.applyItem(ItemType.mystery);
      final e = w.enemies.single;
      // Out of sight range (4) at first: it wanders inside a 1-wide corridor.
      run(w, 2);
      expect(e.x, lessThan(7.5));
      // Once in range it must close in.
      final before = e.x;
      run(w, 1);
      expect(e.x, lessThan(before));
    });

    test('a bomb-aware enemy will not step into a blast zone', () {
      final w = makeWorld('''
#######
#P...e#
#.#.#.#
#.....#
#######
''', kinds: [EnemyKind.slimeSage]);
      final p = w.addPlayer();
      p.applyItem(ItemType.mystery);
      p.fireRange = 3;
      p.setPosition(3.5, 1.5);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      final e = w.enemies.single;
      final danger = w.dangerTiles();
      expect(danger, contains(const GridPos(5, 1)),
          reason: 'it starts in the blast zone');
      // It has 2.5 s to walk one tile down to safety; give it 0.6 s.
      run(w, 0.6);
      while (w.bombs.isNotEmpty) {
        expect(danger.contains(e.tile), isFalse, reason: 'at ${e.tile}');
        w.tick({});
      }
      expect(e.alive, isTrue);
    });

    test('hunters flood the stage when time runs out', () {
      final w = makeWorld(openArena);
      final p = w.addPlayer();
      p.applyItem(ItemType.mystery);
      p.invincibleFor = 100;
      run(w, 10.1);
      expect(w.timeUp, isTrue);
      expect(w.enemies.where((e) => e.kind == EnemyKind.hunterCoin).length, 1);
      run(w, 10);
      expect(w.enemies.where((e) => e.kind == EnemyKind.hunterCoin).length, 2);
    });
  });

  group('exit', () {
    test(
        'solo: stepping on the revealed exit after killing all enemies clears the stage',
        () {
      final w = makeWorld('''
#####
#P.E#
#####
''');
      final p = w.addPlayer();
      p.fireRange = 2;
      p.applyItem(ItemType.flamePass);
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      run(w, Bomb.defaultFuse + 0.05);
      expect(w.exitRevealed, isTrue);
      run(w, 1);
      p.setPosition(3.5, 1.5);
      w.tick({});
      expect(w.cleared, isTrue);
      expect(w.events.whereType<StageCleared>(), isNotEmpty);
    });

    test('solo: the exit does nothing while enemies live', () {
      final w = makeWorld('''
#######
#P.E.e#
#######
''');
      final p = w.addPlayer();
      p.fireRange = 2;
      p.invincibleFor = 100;
      w.tick({p.id: const PlayerInput(placeBomb: true)});
      p.setPosition(1.5, 1.5);
      run(w, Bomb.defaultFuse + 0.05);
      run(w, 1);
      p.setPosition(3.5, 1.5);
      w.tick({});
      expect(w.cleared, isFalse);
    });

    test('co-op: all living players must gather at the exit for 3 s', () {
      final w = makeWorld('''
#########
#P.....E#
#.#.#.#.#
#P......#
#########
''', config: WorldConfig.coop);
      final a = w.addPlayer();
      final b = w.addPlayer();
      a.fireRange = 2;
      a.setPosition(6.5, 1.5);
      w.tick({a.id: const PlayerInput(placeBomb: true)});
      a.setPosition(4.5, 1.5);
      run(w, Bomb.defaultFuse + 0.05);
      expect(w.exitRevealed, isTrue);

      a.setPosition(7.5, 1.5);
      run(w, 4);
      expect(w.cleared, isFalse, reason: 'b is still far away');

      b.setPosition(7.5, 3.5); // 2 tiles away: inside the radius
      run(w, 2.9);
      expect(w.cleared, isFalse);
      expect(w.exitHoldProgress, greaterThan(0.9));
      run(w, 0.2);
      expect(w.cleared, isTrue);
    });
  });

  group('determinism', () {
    test('same seed and inputs give the same world', () {
      World build() {
        final level = LevelData.generate(
            seed: 7,
            players: 2,
            enemyCount: 8,
            enemyKinds: [
              EnemyKind.puffball,
              EnemyKind.blueDrop,
              EnemyKind.slimeSage
            ]);
        final w = World(level, seed: 99);
        w.addPlayer();
        w.addPlayer();
        return w;
      }

      final a = build();
      final b = build();
      final dirs = Direction.values;
      for (var i = 0; i < 600; i++) {
        final input = {
          1: PlayerInput(direction: dirs[i % 5], placeBomb: i % 40 == 0),
          2: PlayerInput(direction: dirs[(i ~/ 3) % 5], placeBomb: i % 55 == 0),
        };
        a.tick(input);
        b.tick(input);
      }
      for (var i = 0; i < a.enemies.length; i++) {
        expect(a.enemies[i].x, b.enemies[i].x);
        expect(a.enemies[i].y, b.enemies[i].y);
        expect(a.enemies[i].alive, b.enemies[i].alive);
      }
      expect(a.players[0].score, b.players[0].score);
    });
  });
}
