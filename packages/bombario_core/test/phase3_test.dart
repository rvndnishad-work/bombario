import 'dart:convert';

import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

World makeWorld(String ascii,
    {WorldConfig config = WorldConfig.solo,
    List<EnemyKind> kinds = const [EnemyKind.puffball],
    List<ItemType> items = const [ItemType.bombUp],
    double timeLimit = 100}) {
  final level = LevelData.parse(ascii,
      enemyKinds: kinds, items: items, timeLimit: timeLimit);
  return World(level, seed: 1, config: config);
}

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

const corridor = '''
#########
#P......#
#########
''';

/// Two spawns far apart in an open arena.
const duo = '''
###########
#P........#
#.#.#.#.#.#
#.........#
#.#.#.#.#.#
#........P#
###########
''';

const left = PlayerInput(direction: Direction.left);
const right = PlayerInput(direction: Direction.right);
const bomb = PlayerInput(placeBomb: true);
const action = PlayerInput(action: true);
const boom = PlayerInput(placeBomb: true, action: true);

void main() {
  group('power-ups', () {
    test('Kick sends a bomb sliding until it hits a wall', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()
        ..applyItem(ItemType.kick)
        ..remote = true; // no fuse, so the bomb waits
      p.setPosition(4.5, 1.5);
      w.tick({p.id: bomb});
      expect(w.bombs.single.x, 4);
      p.setPosition(2.5, 1.5);
      w.tick({}); // step off: the bomb becomes solid to the kicker
      final events = run(w, 1, inputs: {p.id: right});
      expect(events.whereType<BombKicked>(), isNotEmpty);
      expect(w.bombs.single.x, 7);
      expect(w.bombs.single.slide, Direction.none);
    });

    test('a Heart absorbs one hit', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()..applyItem(ItemType.heart);
      w.tick({p.id: bomb});
      final events = run(w, 3);
      expect(events.whereType<HeartLost>(), hasLength(1));
      expect(p.alive, isTrue);
      expect(p.hearts, 0);
    });

    test('dying drops the newest half of your items for teammates', () {
      final w = makeWorld(duo);
      final p = w.addPlayer();
      w.addPlayer();
      for (final i in [
        ItemType.bombUp,
        ItemType.bombUp,
        ItemType.fireUp,
        ItemType.speedUp,
      ]) {
        p.applyItem(i);
      }
      p.setPosition(5.5, 3.5);
      w.tick({p.id: bomb});
      run(w, 3);
      expect(p.alive, isFalse);
      expect(p.items, [ItemType.bombUp, ItemType.bombUp]);
      expect(p.maxBombs, 3);
      expect(p.fireRange, 1);
      expect(p.speed, Player.baseSpeed);
      final dropped = w.floorItems.map((i) => i.type).toList();
      expect(dropped, containsAll([ItemType.fireUp, ItemType.speedUp]));
    });

    test('Frost freezes instead of burning, and a real flame shatters', () {
      final w = makeWorld('''
#########
#P...+..#
#########
''');
      final p = w.addPlayer()
        ..applyItem(ItemType.frost)
        ..applyItem(ItemType.fireUp)
        ..applyItem(ItemType.fireUp)
        ..applyItem(ItemType.fireUp)
        ..remote = true
        ..invincibleFor = 99;
      final e = w.spawnEnemy(const GridPos(3, 1), EnemyKind.puffball, hp: 3);
      w.tick({p.id: boom});
      expect(e.alive, isTrue);
      expect(e.frozen, isTrue);
      expect(w.grid.at(5, 1), TileType.brick, reason: 'frost keeps bricks');
      expect(p.frostBombs, 2);

      // Two more frost bombs, then a normal one shatters the frozen enemy.
      p.frostBombs = 0;
      run(w, 0.7);
      w.tick({p.id: boom});
      expect(e.alive, isFalse);
    });

    test('Sonar reveals hidden items nearby to the team', () {
      final w = makeWorld('''
#########
#P.+E+U.#
#########
''');
      final p = w.addPlayer();
      w.floorItems.add(FloorItem(x: 2, y: 1, type: ItemType.sonar));
      run(w, 0.4, inputs: {p.id: right});
      expect(w.sonar.map((s) => s.type),
          containsAll([ItemType.exit, ItemType.bombUp]));
      final snap = WorldSnapshot.fromJson(
          jsonDecode(jsonEncode(WorldSnapshot.of(w).toJson())));
      expect(snap.sonar, hasLength(2));
      run(w, World.sonarSeconds + 0.1);
      expect(w.sonar, isEmpty);
    });

    test('Team Boost powers up everyone but the picker', () {
      final w = makeWorld(duo);
      final a = w.addPlayer();
      final b = w.addPlayer();
      w.floorItems.add(FloorItem(x: 1, y: 1, type: ItemType.teamBoost));
      w.tick({});
      expect(a.maxBombs, 1);
      expect(b.maxBombs, 2);
      expect(b.fireRange, 2);
    });

    test('only one active item at a time', () {
      final p = Player(id: 1, x: 0, y: 0)..applyItem(ItemType.remote);
      expect(p.active, ActiveItem.remote);
      p.applyItem(ItemType.tether);
      expect(p.active, ActiveItem.tether);
      expect(p.remote, isFalse);
    });
  });

  group('co-op ghosts', () {
    World coop({int lives = 3}) =>
        makeWorld(duo, config: WorldConfig.coop.copyWith(sharedLives: lives));

    test('a fallen player becomes a ghost and the stage goes on', () {
      final w = coop();
      final a = w.addPlayer();
      final b = w.addPlayer();
      w.tick({a.id: bomb});
      final events = run(w, 3);
      expect(events.whereType<BecameGhost>(), hasLength(1));
      expect(a.ghost, isTrue);
      expect(a.tombstone, const GridPos(1, 1));
      expect(w.failed, isFalse);
      expect(b.alive, isTrue);

      // Ghosts float through bricks.
      w.grid.set(3, 1, TileType.brick);
      run(w, 1.2, inputs: {a.id: right});
      expect(a.x, greaterThan(3.5));
    });

    test('standing on a tombstone for 2 s revives from the pool', () {
      final w = coop(lives: 2);
      final a = w.addPlayer();
      final b = w.addPlayer();
      w.tick({a.id: bomb});
      run(w, 3);
      b.setPosition(1.5, 1.5);
      run(w, 1);
      expect(a.ghost, isTrue);
      final events = run(w, 1.2);
      expect(events.whereType<PlayerRevived>(), hasLength(1));
      expect(a.alive, isTrue);
      expect(a.ghost, isFalse);
      expect(w.livesLeft, 1);
    });

    test('no revives once the pool is empty', () {
      final w = coop(lives: 0);
      final a = w.addPlayer();
      final b = w.addPlayer();
      w.tick({a.id: bomb});
      run(w, 3);
      b.setPosition(1.5, 1.5);
      run(w, 3);
      expect(a.ghost, isTrue);
    });

    test('Tether revives a ghost from 4 tiles away', () {
      final w = coop();
      final a = w.addPlayer();
      final b = w.addPlayer()..applyItem(ItemType.tether);
      w.tick({a.id: bomb});
      run(w, 3);
      b.setPosition(4.5, 1.5);
      w.tick({b.id: action});
      expect(a.alive, isTrue);
      expect(b.active, ActiveItem.none);
    });

    test('a ghost can haunt one enemy once per life', () {
      final w = coop();
      final a = w.addPlayer();
      w.addPlayer();
      w.tick({a.id: bomb});
      run(w, 3);
      final e = w.spawnEnemy(const GridPos(3, 1), EnemyKind.puffball);
      final events = run(w, 0.1, inputs: {a.id: action});
      expect(events.whereType<Haunted>(), hasLength(1));
      expect(e.slowFor, greaterThan(2));
      expect(a.hauntUsed, isTrue);
    });

    test('the stage fails when everyone is a ghost', () {
      final w = coop();
      final a = w.addPlayer();
      final b = w.addPlayer();
      b.setPosition(2.5, 1.5);
      w.tick({a.id: bomb});
      final events = run(w, 3);
      expect(events.whereType<StageFailed>(), hasLength(1));
      expect(a.ghost && b.ghost, isTrue);
    });

    test('friendly flames only stun on tutorial stages', () {
      final w =
          makeWorld(duo, config: WorldConfig.coop.copyWith(friendlyStun: true));
      final a = w.addPlayer();
      final b = w.addPlayer();
      b.setPosition(2.5, 1.5);
      a.invincibleFor = 99;
      w.tick({a.id: bomb});
      final events = run(w, 2.6);
      expect(events.whereType<PlayerFrozen>(), hasLength(1));
      expect(b.alive, isTrue);
    });

    test('pings show at the sender and expire, with a cooldown', () {
      final w = coop();
      final a = w.addPlayer();
      w.addPlayer();
      w.tick({a.id: const PlayerInput(ping: PingKind.exitHere)});
      w.tick({a.id: const PlayerInput(ping: PingKind.help)});
      expect(w.pings.single.kind, PingKind.exitHere);
      expect(w.pings.single.x, 1);
      run(w, World.pingSeconds);
      expect(w.pings, isEmpty);
    });
  });

  group('hazards', () {
    test('cracked floor collapses after the second walk-over', () {
      final w = makeWorld('''
#########
#P.~....#
#########
''');
      final p = w.addPlayer();
      run(w, 1.2, inputs: {p.id: right});
      expect(w.grid.at(3, 1), TileType.cracked, reason: 'one walk-over');
      final events = run(w, 1.2, inputs: {p.id: left});
      expect(events.whereType<FloorCollapsed>(), hasLength(1));
      expect(w.grid.at(3, 1), TileType.pit);
      run(w, 1.5, inputs: {p.id: right});
      expect(p.x, lessThan(3), reason: 'a pit blocks the way');
    });

    test('cracked floor waits for your heel before it gives way', () {
      final w = makeWorld('''
#########
#P.~....#
#########
''');
      final p = w.addPlayer();
      run(w, 1.2, inputs: {p.id: right});
      // Back over it, then stop just past the tile edge: the body still
      // overlaps the cracked tile, so it holds until we walk on.
      while (p.tileX >= 3) {
        w.tick({p.id: left});
      }
      expect(w.grid.at(3, 1), TileType.cracked);
      run(w, 0.5, inputs: {p.id: left});
      expect(w.grid.at(3, 1), TileType.pit);
      // Walked clear rather than held at the edge by the new pit.
      expect(p.x, lessThan(2.5));
    });

    test('falling rocks are telegraphed, then hurt', () {
      final w =
          makeWorld(duo, config: const WorldConfig(stalactiteInterval: 1));
      final p = w.addPlayer();
      run(w, 1.05);
      expect(w.hazards, hasLength(1));
      final h = w.hazards.single;
      p.setPosition(h.x + 0.5, h.y + 0.5);
      final events = run(w, World.rockWarning);
      expect(events.whereType<RockFell>(), isNotEmpty);
      expect(p.alive, isFalse);
    });
  });

  group('new enemies', () {
    const field = '''
###########
#.........#
#.........#
#.........#
#.........#
#.........#
#.........#
#P........#
###########
''';

    test('Pebble patrols a straight line', () {
      final w = makeWorld(corridor);
      final e = w.spawnEnemy(const GridPos(4, 1), EnemyKind.pebble);
      final xs = <double>{};
      for (var i = 0; i < 300; i++) {
        w.tick({});
        xs.add(e.x);
        expect(e.y, 1.5);
      }
      expect(xs.reduce((a, b) => a < b ? a : b), lessThan(2));
      expect(xs.reduce((a, b) => a > b ? a : b), greaterThan(7));
    });

    test('Hopper squats, then jumps two tiles', () {
      final w = makeWorld(field);
      final e = w.spawnEnemy(const GridPos(5, 3), EnemyKind.hopper);
      var sawTelegraph = false;
      GridPos? takeoff;
      for (var i = 0; i < 200 && takeoff == null; i++) {
        w.tick({});
        if (e.state == EnemyStateKind.telegraph) {
          sawTelegraph = true;
          takeoff = e.tile;
        }
      }
      expect(sawTelegraph, isTrue);
      final landing = e.landing!;
      expect(landing.manhattanTo(takeoff!), 2);
      run(w, 0.5 + 0.4 + 0.05);
      expect(e.tile, landing);
    });

    test('Splitter splits into two Splitlings that fade', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 99;
      p.applyItem(ItemType.fireUp);
      p.applyItem(ItemType.fireUp);
      final s = w.spawnEnemy(const GridPos(3, 1), EnemyKind.splitter);
      w.tick({p.id: boom});
      expect(s.alive, isFalse);
      final kids = w.enemies.where((e) => e.kind == EnemyKind.splitling);
      expect(kids, hasLength(2));
      expect(kids.every((k) => k.alive), isTrue);
      run(w, 10.5);
      expect(kids.every((k) => !k.alive), isTrue);
    });

    test('Shellback: a hit from the front flips it, a second kills', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 99;
      for (var i = 0; i < 3; i++) {
        p.applyItem(ItemType.fireUp);
      }
      final e = w.spawnEnemy(const GridPos(4, 1), EnemyKind.shellback)
        ..direction = Direction.left; // facing the bomb
      w.tick({p.id: boom});
      expect(e.alive, isTrue);
      expect(e.state, EnemyStateKind.stunned);
      expect(e.harmful, isFalse);
      run(w, 0.7);
      w.tick({p.id: boom});
      expect(e.alive, isFalse);
    });

    test('Shellback: a hit from behind kills at once', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 99;
      for (var i = 0; i < 3; i++) {
        p.applyItem(ItemType.fireUp);
      }
      final e = w.spawnEnemy(const GridPos(4, 1), EnemyKind.shellback)
        ..direction = Direction.right; // back to the bomb
      w.tick({p.id: boom});
      expect(e.alive, isFalse);
    });

    test('every enemy kind looks itself up by name', () {
      for (final k in EnemyKind.all) {
        expect(EnemyKind.byName[k.name], same(k));
      }
    });
  });

  group('bosses', () {
    test('King Puffball bounces inside the arena and splits at half HP', () {
      final stage = Campaign.byId('1-10')!;
      final w = World(stage.level(seed: 3, players: 1),
          seed: 3, config: stage.config(players: 1));
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 999;
      final king = w.enemies.firstWhere((e) => e.kind.boss);
      expect(king.kind, EnemyKind.kingPuffball);
      expect(king.hp, 8);
      for (var i = 0; i < 300; i++) {
        w.tick({});
        expect(king.x, inInclusiveRange(1.9, w.grid.width - 1.9));
        expect(king.y, inInclusiveRange(1.9, w.grid.height - 1.9));
      }
      // Four hits, each from a bomb set off right under it.
      for (var hit = 0; hit < 4; hit++) {
        p.setPosition(king.x, king.y);
        w.tick({p.id: boom});
        run(w, 0.7);
      }
      expect(king.hp, 4);
      expect(king.splitDone, isTrue);
      expect(w.enemies.where((e) => e.kind == EnemyKind.puffball && e.alive),
          hasLength(4));
    });

    test('boss HP scales with the team', () {
      final w =
          World(Campaign.byId('1-10')!.level(seed: 1, players: 3), seed: 1);
      expect(w.enemies.single.hp, 18); // 8 × 2.2, rounded
    });

    test('Rockjaw dives, rumbles, then surfaces; only the head is hittable',
        () {
      final stage = Campaign.byId('2-10')!;
      final w = World(stage.level(seed: 5, players: 1),
          seed: 5, config: stage.config(players: 1));
      w.addPlayer().invincibleFor = 999;
      final worm = w.enemies.single;
      expect(worm.state, EnemyStateKind.underground);
      expect(worm.solid, isFalse);
      final seen = <EnemyStateKind>[];
      for (var i = 0; i < 30 * 8; i++) {
        w.tick({});
        if (seen.isEmpty || seen.last != worm.state) seen.add(worm.state);
      }
      expect(
          seen,
          containsAllInOrder([
            EnemyStateKind.telegraph,
            EnemyStateKind.normal,
            EnemyStateKind.underground,
          ]));
    });

    test('a boss stage clears when every enemy is dead', () {
      final stage = Campaign.byId('1-10')!;
      final w = World(stage.level(seed: 1, players: 1),
          seed: 1, config: stage.config(players: 1));
      w.addPlayer();
      for (final e in w.enemies) {
        e.alive = false; // the boss and the mini-boss
      }
      final events = run(w, 0.1);
      expect(events.whereType<StageCleared>(), hasLength(1));
    });
  });

  group('campaign', () {
    test('worlds 1 and 2 have ten stages each, with bosses at 10', () {
      expect(Campaign.byId('1-10')!.isBoss, isTrue);
      expect(Campaign.byId('2-10')!.isBoss, isTrue);
      expect(Campaign.byId('1-5')!.bonus, isTrue);
      expect(Campaign.byId('2-5')!.bonus, isTrue);
      expect(Campaign.next('1-10')!.id, '2-1');
      expect(Campaign.next('2-10')!.id, '3-1');
    });

    test('every stage builds and runs for 1 to 4 players', () {
      for (final stage in Campaign.stages) {
        for (var n = 1; n <= 4; n++) {
          final level = stage.level(seed: 11, players: n);
          final w = World(level, seed: 11, config: stage.config(players: n));
          for (var i = 0; i < n; i++) {
            w.addPlayer().invincibleFor = 999;
          }
          expect(level.playerSpawns.length, greaterThanOrEqualTo(n),
              reason: stage.id);
          final hidden = [
            for (final p in level.grid.positions)
              if (level.grid.hiddenAt(p.x, p.y) case final i?) i,
          ];
          if (!stage.isBoss && !stage.bonus) {
            expect(hidden.where((i) => i == ItemType.exit), hasLength(1),
                reason: '${stage.id} needs an exit');
            final expected = [
              for (final (_, c) in stage.enemies) StageDef.scaleCount(c, n),
            ].fold(0, (a, b) => a + b);
            expect(w.enemies.length,
                stage.layout == null ? expected : level.enemySpawns.length,
                reason: stage.id);
          }
          // One power-up per player (all of them on bonus stages).
          for (final item in stage.bonus ? stage.items : stage.items.take(n)) {
            expect(hidden, contains(item), reason: '${stage.id} hides $item');
          }
          run(w, 2);
        }
      }
    });

    test('a bonus stage tops enemies up and clears when time runs out', () {
      final stage = Campaign.byId('1-5')!;
      final w = World(stage.level(seed: 2, players: 2),
          seed: 2, config: stage.config(players: 2));
      w.addPlayer().invincibleFor = 999;
      w.addPlayer().invincibleFor = 999;
      w.tick({});
      expect(w.enemies.where((e) => e.alive), hasLength(8));
      w.enemies.first.alive = false;
      w.tick({});
      expect(w.enemies.where((e) => e.alive), hasLength(8));
      final events = run(w, 61);
      expect(events.whereType<StageCleared>(), hasLength(1));
    });

    test('the shared lives pool is 3 plus one per player', () {
      expect(Campaign.first.config(players: 3).sharedLives, 6);
      expect(Campaign.first.config(players: 1, coop: false).ghosts, isFalse);
    });
  });

  test('snapshots carry the Phase 3 state over the wire', () {
    final w = makeWorld('''
#########
#P.~+..P#
#########
''', config: WorldConfig.coop);
    final a = w.addPlayer()
      ..applyItem(ItemType.kick)
      ..applyItem(ItemType.heart)
      ..applyItem(ItemType.frost)
      ..applyItem(ItemType.tether);
    final b = w.addPlayer();
    b.alive = false;
    b.ghost = true;
    b.tombstone = const GridPos(7, 1);
    w.tick({a.id: const PlayerInput(ping: PingKind.run, placeBomb: true)});
    w.grid.set(5, 1, TileType.pit);
    w.hazards.add(Hazard(6, 1, 0.5));
    final e = w.spawnEnemy(const GridPos(6, 1), EnemyKind.shellback)
      ..state = EnemyStateKind.stunned
      ..frozenFor = 1;

    final snap = WorldSnapshot.fromJson(
        jsonDecode(jsonEncode(WorldSnapshot.of(w).toJson())));
    expect(snap.grid.at(3, 1), TileType.cracked);
    expect(snap.grid.at(5, 1), TileType.pit);
    final pa = snap.player(a.id)!;
    expect(pa.kick, isTrue);
    expect(pa.hearts, 1);
    expect(pa.frostBombs, 2);
    expect(pa.active, ActiveItem.tether);
    expect(pa.actionLabel, 'tether');
    final pb = snap.player(b.id)!;
    expect(pb.ghost, isTrue);
    expect(pb.tombstone, const GridPos(7, 1));
    expect(pb.actionLabel, 'haunt');
    expect(snap.bombs.single.frost, isTrue);
    expect(snap.pings.single.kind, PingKind.run);
    expect(snap.hazards.single.x, 6);
    final es = snap.enemies.firstWhere((x) => x.id == e.id);
    expect(es.state, EnemyStateKind.stunned);
    expect(es.frozen, isTrue);
    expect(es.kindData, EnemyKind.shellback);
    expect(snap.livesLeft, 4);
  });
}
