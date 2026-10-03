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

WorldSnapshot roundTrip(World w) =>
    WorldSnapshot.fromJson(jsonDecode(jsonEncode(WorldSnapshot.of(w).toJson()))
        as Map<String, dynamic>);

const corridor = '''
#########
#P......#
#########
''';

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

const left = PlayerInput(direction: Direction.left);
const right = PlayerInput(direction: Direction.right);
const up = PlayerInput(direction: Direction.up);
const bomb = PlayerInput(placeBomb: true);
const boom = PlayerInput(placeBomb: true, action: true);

/// A still bomb nobody will set off by itself.
Bomb plantRemote(World w, int x, int y, {int ownerId = Bomb.enemyOwner}) {
  final b = Bomb(
    id: 9000 + x * 31 + y,
    x: x,
    y: y,
    ownerId: ownerId,
    range: 1,
    fuse: 99,
    remote: true,
  );
  w.bombs.add(b);
  return b;
}

/// Plays a boss stage with one invincible remote-bomber who teleports onto
/// whatever can be hit and sets a bomb off under it.
List<GameEvent> fight(World w, Player p, {double maxSeconds = 240}) {
  final all = <GameEvent>[];
  for (var t = 0; t < maxSeconds * World.tickRate && !w.over; t++) {
    p.invincibleFor = 999;
    Enemy? target;
    for (final e in w.enemies) {
      if (!e.alive || !e.solid || e.hitCooldown > 0) continue;
      if (e.kind.ability == EnemyAbility.bombPatterns &&
          e.state != EnemyStateKind.vulnerable) {
        continue;
      }
      // Minions first, so the boss's death isn't what clears them.
      if (target == null || target.kind.boss) target = e;
    }
    if (target != null && p.alive) {
      p.setPosition(target.tileX + 0.5, target.tileY + 0.5);
      w.tick({p.id: boom});
    } else {
      w.tick({});
    }
    all.addAll(w.events);
  }
  return all;
}

void main() {
  group('World 3-5 enemies', () {
    test('Tigerclaw hunts a player down from across the field', () {
      final w = makeWorld(field);
      final p = w.addPlayer();
      w.spawnEnemy(const GridPos(9, 1), EnemyKind.tigerclaw);
      final events = run(w, 6);
      expect(events.whereType<PlayerDied>(), hasLength(1));
      expect(p.alive, isFalse);
    });

    test('Tigerclaw will not walk into a blast zone', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()..invincibleFor = 99;
      final e = w.spawnEnemy(const GridPos(7, 1), EnemyKind.tigerclaw);
      plantRemote(w, 4, 1).passableFor.clear();
      final danger = w.dangerTiles();
      for (var i = 0; i < 60; i++) {
        w.tick({});
        expect(danger.contains(e.tile), isFalse);
      }
      expect(p.alive, isTrue);
    });

    test('Mimic hides as an item, bites when you step next to it', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer();
      final m = w.spawnEnemy(const GridPos(5, 1), EnemyKind.mimic);
      expect(m.state, EnemyStateKind.disguised);
      expect(m.harmful, isFalse);
      final es = roundTrip(w).enemies.single;
      expect(es.disguise, isNotNull);
      expect(es.state, EnemyStateKind.disguised);

      p.setPosition(4.5, 1.5);
      final reveal = run(w, 0.1);
      expect(reveal.whereType<EnemyRevealed>(), hasLength(1));
      expect(m.state, EnemyStateKind.telegraph);
      expect(p.alive, isTrue, reason: '0.5 s tell before the bite');
      final events = run(w, 0.5);
      expect(events.whereType<PlayerDied>(), hasLength(1));
    });

    test('Sonar exposes a Mimic', () {
      final w = makeWorld(field);
      final p = w.addPlayer();
      final m = w.spawnEnemy(const GridPos(5, 4), EnemyKind.mimic);
      w.floorItems.add(FloorItem(x: 1, y: 7, type: ItemType.sonar));
      final events = run(w, 0.05);
      expect(events.whereType<EnemyRevealed>(), hasLength(1));
      expect(m.state, isNot(EnemyStateKind.disguised));
      expect(p.alive, isTrue);
    });

    test('Bomb Goblin plants a range-2 bomb near players, then flees', () {
      final w = makeWorld(field);
      final p = w.addPlayer()..invincibleFor = 99;
      final g = w.spawnEnemy(const GridPos(3, 6), EnemyKind.bombGoblin);
      var sawTell = false;
      for (var i = 0; i < 60 && w.bombs.isEmpty; i++) {
        w.tick({});
        if (g.state == EnemyStateKind.telegraph) sawTell = true;
      }
      expect(sawTell, isTrue);
      final b = w.bombs.single;
      expect(b.ownerId, Bomb.enemyOwner);
      expect(b.range, 2);
      expect(g.state, EnemyStateKind.fleeing);
      final start = g.tile.manhattanTo(p.tile);
      run(w, 1);
      expect(g.tile.manhattanTo(p.tile), greaterThanOrEqualTo(start));
    });

    test('Kicker Crab kicks a bomb it walks into, after a tell', () {
      final w = makeWorld(corridor);
      w.addPlayer().invincibleFor = 99;
      final c = w.spawnEnemy(const GridPos(7, 1), EnemyKind.kickerCrab)
        ..direction = Direction.left;
      final b = plantRemote(w, 4, 1);
      expect(c.hp, 2);
      final events = run(w, 2);
      expect(events.whereType<EnemyKickedBomb>(), hasLength(1));
      expect(b.x, lessThan(4));
    });

    test('Shade is invisible unless a player is within 3 tiles', () {
      final w = makeWorld(field);
      final p = w.addPlayer()..invincibleFor = 99;
      final s = w.spawnEnemy(const GridPos(9, 1), EnemyKind.shade);
      w.tick({});
      expect(s.visible, isFalse);
      expect(roundTrip(w).enemies.single.visible, isFalse);
      p.setPosition(s.x - 2, s.y);
      w.tick({});
      expect(s.visible, isTrue);
    });

    test('Mole Queen nest hides under a brick and hatches Pebbles', () {
      final w = makeWorld(field);
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 999;
      w.grid.set(5, 3, TileType.brick);
      final nest = w.spawnEnemy(const GridPos(5, 3), EnemyKind.moleNest);
      expect(nest.state, EnemyStateKind.underground);
      expect(nest.solid, isFalse);
      final events = run(w, World.nestInterval + 0.1);
      final kids = events
          .whereType<EnemySpawned>()
          .where((s) => s.enemy.kind == EnemyKind.pebble);
      expect(kids, hasLength(1));
      expect(kids.single.enemy.parentId, nest.id);
      expect(nest.harmful, isFalse);

      // Blow the brick open, then three hits destroy it.
      p.setPosition(4.5, 3.5);
      w.tick({p.id: boom});
      run(w, 0.1);
      expect(nest.state, EnemyStateKind.normal);
      for (var i = 0; i < 3; i++) {
        run(w, 0.7);
        p.setPosition(5.5, 3.5);
        w.tick({p.id: boom});
      }
      expect(nest.alive, isFalse);
    });

    test('Mirror Knight copies your moves with left and right swapped', () {
      final w = makeWorld(field);
      final p = w.addPlayer()..invincibleFor = 99;
      final k = w.spawnEnemy(const GridPos(5, 3), EnemyKind.mirrorKnight);
      run(w, 0.5);
      expect(k.tile, const GridPos(5, 3), reason: 'still while you are');
      run(w, 0.7, inputs: {p.id: right});
      expect(k.x, lessThan(5.5));
      expect(k.y, 3.5);
      final y0 = k.y;
      p.setPosition(3.5, 7.5);
      run(w, 0.7, inputs: {p.id: up});
      expect(k.y, lessThan(y0));
    });

    test('Fuse Eater stops to eat a bomb, then flees', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()..invincibleFor = 99;
      final b = plantRemote(w, 3, 1, ownerId: p.id);
      p.bombsPlaced = 1;
      final f = w.spawnEnemy(const GridPos(7, 1), EnemyKind.fuseEater);
      var sawEating = false;
      final events = <GameEvent>[];
      for (var i = 0; i < 90 && w.bombs.isNotEmpty; i++) {
        w.tick({});
        events.addAll(w.events);
        if (f.state == EnemyStateKind.telegraph) sawEating = true;
      }
      expect(sawEating, isTrue);
      expect(events.whereType<BombEaten>(), hasLength(1));
      expect(w.bombs, isNot(contains(b)));
      expect(p.bombsPlaced, 0);
      expect(f.state, EnemyStateKind.fleeing);
    });

    test('a Fuse Eater dies to the bomb it is eating', () {
      final w = makeWorld(corridor);
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 99;
      p.setPosition(3.5, 1.5);
      w.tick({p.id: bomb});
      p.setPosition(1.5, 1.5);
      final f = w.spawnEnemy(const GridPos(7, 1), EnemyKind.fuseEater);
      for (var i = 0; i < 90 && f.state != EnemyStateKind.telegraph; i++) {
        w.tick({});
      }
      expect(f.state, EnemyStateKind.telegraph);
      w.tick({p.id: const PlayerInput(action: true)});
      run(w, 0.1);
      expect(f.alive, isFalse);
    });

    test('Phase Wraith flickers, then teleports 2-3 steps from a player', () {
      final w = makeWorld(field);
      final p = w.addPlayer()..invincibleFor = 99;
      final e = w.spawnEnemy(const GridPos(9, 1), EnemyKind.phaseWraith);
      expect(e.hp, 2);
      GridPos? landing;
      for (var i = 0; i < 30 * 8 && landing == null; i++) {
        w.tick({});
        if (e.state == EnemyStateKind.telegraph) landing = e.landing;
      }
      expect(landing, isNotNull);
      expect(roundTrip(w).enemies.single.landing, landing);
      final d = landing!.manhattanTo(p.tile);
      expect(d, inInclusiveRange(2, 3));
      final events = run(w, 0.55);
      expect(events.whereType<EnemyTeleported>(), hasLength(1));
      expect(e.tile, landing);
    });

    test('Herder is harmless but speeds up enemies near it', () {
      final w = makeWorld(field);
      final p = w.addPlayer();
      final h = w.spawnEnemy(const GridPos(5, 3), EnemyKind.herder);
      final pal = w.spawnEnemy(const GridPos(6, 3), EnemyKind.puffball);
      final lone = w.spawnEnemy(const GridPos(9, 7), EnemyKind.puffball);
      final x0 = pal.x, y0 = pal.y, lx = lone.x, ly = lone.y;
      w.tick({});
      expect(pal.herded, isTrue);
      expect(lone.herded, isFalse);
      final moved = (pal.x - x0).abs() + (pal.y - y0).abs();
      final lonely = (lone.x - lx).abs() + (lone.y - ly).abs();
      expect(moved, closeTo(lonely * World.herdBoost, 1e-6));
      expect(roundTrip(w).enemies[1].herded, isTrue);

      p.setPosition(h.x, h.y);
      w.tick({});
      expect(p.alive, isTrue, reason: 'Herders never attack');
    });

    test('every new kind is on the roster and named', () {
      for (final k in [
        EnemyKind.tigerclaw,
        EnemyKind.mimic,
        EnemyKind.bombGoblin,
        EnemyKind.kickerCrab,
        EnemyKind.shade,
        EnemyKind.moleNest,
        EnemyKind.mirrorKnight,
        EnemyKind.fuseEater,
        EnemyKind.phaseWraith,
        EnemyKind.herder,
        EnemyKind.curseOrb,
        EnemyKind.bombOTron,
        EnemyKind.lanternWitch,
        EnemyKind.overlordPontan,
      ]) {
        expect(EnemyKind.all, contains(k));
        expect(EnemyKind.byName[k.name], same(k));
      }
    });
  });

  group('World 3-5 terrain', () {
    test('conveyors carry players and still bombs', () {
      final w = makeWorld('''
#########
#P.>>>..#
#########
''');
      final p = w.addPlayer()..remote = true;
      p.setPosition(3.5, 1.5);
      run(w, 0.5);
      expect(p.x, greaterThan(3.9));
      final b = plantRemote(w, 3, 1);
      p.setPosition(1.5, 1.5);
      run(w, 2);
      expect(b.x, 6, reason: 'rolls off the end of the belt and stops');
      expect(b.slide, Direction.none);
    });

    test('ice keeps you sliding until something stops you', () {
      final w = makeWorld('''
#########
#Piiiiii#
#########
''');
      final p = w.addPlayer();
      run(w, 0.2, inputs: {p.id: right});
      run(w, 2);
      expect(p.x, closeTo(7.5, 0.11), reason: 'slid to the wall');
      expect(roundTrip(w).players.single.momentum, Direction.none);
    });

    test('a headwind slows players down', () {
      final calm = makeWorld(corridor);
      final windy =
          makeWorld(corridor, config: const WorldConfig(windInterval: 8));
      final a = calm.addPlayer();
      final b = windy.addPlayer();
      run(calm, World.windCalm + 0.1);
      run(windy, World.windCalm + 0.1);
      expect(windy.wind, Direction.left);
      expect(roundTrip(windy).wind, Direction.left);
      run(calm, 0.5, inputs: {a.id: right});
      run(windy, 0.5, inputs: {b.id: right}); // into a left-blowing gust
      expect(b.x - 1.5, closeTo((a.x - 1.5) * Movement.headwindFactor, 0.05));
    });

    test('steam vents warn, then blast the tiles around them', () {
      final w = makeWorld('''
#########
#P..V...#
#########
''', config: const WorldConfig(ventInterval: 4));
      final p = w.addPlayer();
      p.setPosition(5.5, 1.5);
      run(w, 4 - World.ventFiring - World.ventWarning + 0.05);
      expect(w.ventPhase, VentPhase.warning);
      expect(p.alive, isTrue);
      expect(roundTrip(w).ventPhase, VentPhase.warning);
      final events = run(w, World.ventWarning + 0.1);
      expect(events.whereType<VentsFired>(), hasLength(1));
      expect(p.alive, isFalse);
    });

    test('a pressure plate under a brick opens the gate', () {
      final w = makeWorld('''
#######
#P.p..#
###G###
#..U..#
#######
''');
      final p = w.addPlayer();
      expect(w.grid.at(3, 2), TileType.pillar);
      expect(w.grid.featureAt(3, 2), TileFeature.gate);
      expect(w.level.solvable, isTrue);
      w.grid.set(3, 1, TileType.floor); // as if bombed
      final events = run(w, 0.8, inputs: {p.id: right});
      expect(events.whereType<GatesOpened>(), hasLength(1));
      expect(w.grid.at(3, 2), TileType.floor);
    });

    test('warp doors carry you to their partner', () {
      final w = makeWorld('''
#########
#PW.....#
#.#####.#
#.....W.#
#########
''');
      final p = w.addPlayer();
      final events = run(w, 0.4, inputs: {p.id: right});
      final warp = events.whereType<PlayerWarped>().single;
      expect(warp.toX, 6);
      expect(warp.toY, 3);
      expect(p.tileY, 3);
    });

    test('possessed bricks grow back 20 s after they break', () {
      final w = makeWorld('''
#########
#P..R...#
#########
''');
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 999;
      p.setPosition(3.5, 1.5);
      w.tick({p.id: boom});
      p.setPosition(1.5, 1.5);
      expect(w.grid.at(4, 1), TileType.floor);
      expect(roundTrip(w).regrowing.single.x, 4);
      run(w, World.regrowSeconds - 1);
      expect(w.grid.at(4, 1), TileType.floor);
      final events = run(w, 1.1);
      expect(events.whereType<BrickRegrew>(), hasLength(1));
      expect(w.grid.at(4, 1), TileType.brick);
    });

    test('cannons mark a row, then sweep it', () {
      final w = makeWorld(field, config: const WorldConfig(cannonInterval: 2));
      final p = w.addPlayer();
      run(w, 2.05);
      final h = w.hazards.single;
      expect(h.kind, anyOf(HazardKind.cannonLeft, HazardKind.cannonRight));
      expect(h.y, 7);
      expect(roundTrip(w).hazards.single.kind, h.kind);
      expect(p.alive, isTrue);
      final events = run(w, World.cannonWarning);
      expect(events.whereType<CannonFired>(), hasLength(1));
      expect(p.alive, isFalse);
    });
  });

  group('World 3-5 bosses', () {
    World boss(String id, {int players = 1, int seed = 3}) {
      final stage = Campaign.byId(id)!;
      return World(stage.level(seed: seed, players: players),
          seed: seed, config: stage.config(players: players));
    }

    test('Bomb-O-Tron is armoured until it drops a volley', () {
      final w = boss('3-10');
      final p = w.addPlayer()
        ..remote = true
        ..invincibleFor = 999;
      final tron = w.enemies.single;
      expect(tron.kind, EnemyKind.bombOTron);
      p.setPosition(tron.x, tron.y);
      w.tick({p.id: boom});
      run(w, 0.2);
      expect(tron.hp, tron.maxHp, reason: 'armour holds');
      final events = run(w, 4);
      expect(events.whereType<BossAttack>(), isNotEmpty);
      expect(tron.state, EnemyStateKind.vulnerable);
      expect(w.bombs.where((b) => b.ownerId == Bomb.enemyOwner), isNotEmpty);
      p.setPosition(tron.x, tron.y);
      w.tick({p.id: boom});
      expect(tron.hp, tron.maxHp - 1);
    });

    test('Bomb-O-Tron can be defeated', () {
      final w = boss('3-10');
      final p = w.addPlayer()..remote = true;
      final events = fight(w, p);
      expect(events.whereType<StageCleared>(), hasLength(1));
      expect(w.enemies.every((e) => !e.alive), isTrue);
    });

    test('Lantern Witch blinks away and summons Shades', () {
      final w = boss('4-10');
      w.addPlayer().invincibleFor = 999;
      final witch = w.enemies.single;
      expect(roundTrip(w).darkness, 4);
      final events = run(w, 10);
      expect(events.whereType<EnemyTeleported>(), isNotEmpty);
      expect(w.enemies.where((e) => e.kind == EnemyKind.shade && e.alive),
          isNotEmpty);
      expect(witch.alive, isTrue);
    });

    test('her curse reverses controls until the orb is bombed', () {
      final w = boss('4-10', players: 2);
      final a = w.addPlayer()
        ..invincibleFor = 999
        ..remote = true;
      final b = w.addPlayer()
        ..invincibleFor = 999
        ..remote = true;
      final witch = w.enemies.single;
      witch.hp = witch.maxHp ~/ 2;
      PlayerCursed? curse;
      for (var i = 0; i < 30 * 40 && curse == null; i++) {
        a.invincibleFor = b.invincibleFor = 999;
        w.tick({});
        curse = w.events.whereType<PlayerCursed>().firstOrNull;
      }
      expect(curse, isNotNull);
      expect(witch.alive, isTrue);
      final victim = w.playerById(curse!.playerId)!;
      final helper = victim == a ? b : a;
      expect(roundTrip(w).player(victim.id)!.cursed, isTrue);

      // Pressing right walks a cursed player left.
      victim.setPosition(7.5, 1.5);
      final x0 = victim.x;
      w.tick({victim.id: right});
      expect(victim.x, lessThan(x0));

      final orb =
          w.enemies.singleWhere((e) => e.kind == EnemyKind.curseOrb && e.alive);
      expect(orb.linkedPlayer, victim.id);
      helper.setPosition(orb.x, orb.y);
      w.tick({helper.id: boom});
      expect(orb.alive, isFalse);
      expect(victim.cursed, isFalse);
    });

    test('Lantern Witch can be defeated', () {
      final w = boss('4-10');
      final p = w.addPlayer()..remote = true;
      final events = fight(w, p);
      expect(events.whereType<StageCleared>(), hasLength(1));
    });

    test('Overlord Pontan copies power-ups and cycles boss attacks', () {
      final w = boss('5-10');
      final p = w.addPlayer()..invincibleFor = 999;
      for (var i = 0; i < 4; i++) {
        p.applyItem(ItemType.fireUp);
      }
      final events = run(w, 25);
      final attacks = events.whereType<BossAttack>().map((a) => a.attack);
      expect(attacks, containsAll(['split', 'ring', 'summon', 'dive']));
      final ring = w.bombs.where((b) => b.ownerId == Bomb.enemyOwner);
      if (ring.isNotEmpty) expect(ring.first.range, 3);
    });

    test('Overlord Pontan closes the arena in his last phase', () {
      final w = boss('5-10');
      w.addPlayer().invincibleFor = 999;
      final pontan = w.enemies.single..hp = 4;
      final events = run(w, 4);
      expect(events.whereType<ArenaShrank>(), isNotEmpty);
      expect(roundTrip(w).hazards.map((h) => h.kind),
          everyElement(HazardKind.wall));
      expect(pontan.alive, isTrue);
    });

    test('Overlord Pontan can be defeated', () {
      final w = boss('5-10');
      final p = w.addPlayer()..remote = true;
      final events = fight(w, p);
      expect(events.whereType<StageCleared>(), hasLength(1));
      expect(events.whereType<ArenaShrank>(), isNotEmpty);
    });

    test('boss HP scales with the team', () {
      expect(boss('3-10', players: 4).enemies.single.hp,
          StageDef.scaleBossHp(EnemyKind.bombOTron.hp, 4));
    });
  });

  group('campaign', () {
    test('five worlds of ten: a bonus at 5, a boss at 10', () {
      expect(Campaign.stages, hasLength(50));
      for (var world = 1; world <= 5; world++) {
        for (var n = 1; n <= 10; n++) {
          final s = Campaign.byId('$world-$n');
          expect(s, isNotNull, reason: '$world-$n');
          expect(s!.isBoss, n == 10, reason: s.id);
          expect(s.bonus, n == 5, reason: s.id);
        }
      }
    });

    test('Campaign.next chains 1-1 to 5-10', () {
      final ids = <String>[];
      StageDef? s = Campaign.first;
      while (s != null) {
        ids.add(s.id);
        s = Campaign.next(s.id);
      }
      expect(ids.first, '1-1');
      expect(ids.last, '5-10');
      expect(ids, hasLength(50));
      expect(ids.toSet(), hasLength(50));
    });

    test('every stage generates and is solvable for 1 to 4 players', () {
      for (final stage in Campaign.stages) {
        for (var n = 1; n <= 4; n++) {
          for (final seed in [1, 7, 42]) {
            final level = stage.level(seed: seed, players: n);
            final why = '${stage.id} n=$n seed=$seed';
            expect(level.solvable, isTrue, reason: why);
            if (!stage.isBoss && !stage.bonus) {
              expect(level.exit, isNotNull, reason: why);
            }
            if (stage.layout == null && !stage.isBoss) {
              for (final e in level.enemySpawns) {
                for (final s in level.playerSpawns.take(n)) {
                  expect(e.pos.manhattanTo(s), greaterThanOrEqualTo(4),
                      reason: why);
                }
              }
            }
          }
        }
      }
    });

    test('worlds 3-5 get their terrain and hazards', () {
      bool has(StageDef s, TileFeature f) {
        final g = s.level(seed: 5, players: 2).grid;
        return g.positions.any((p) => g.featureAt(p.x, p.y) == f);
      }

      expect(
          has(Campaign.byId('3-1')!, TileFeature.conveyorLeft) ||
              has(Campaign.byId('3-1')!, TileFeature.conveyorRight) ||
              has(Campaign.byId('3-1')!, TileFeature.conveyorUp) ||
              has(Campaign.byId('3-1')!, TileFeature.conveyorDown),
          isTrue);
      expect(has(Campaign.byId('3-2')!, TileFeature.vent), isTrue);
      expect(has(Campaign.byId('3-3')!, TileFeature.gate), isTrue);
      expect(has(Campaign.byId('4-2')!, TileFeature.possessed), isTrue);
      expect(has(Campaign.byId('4-4')!, TileFeature.warp), isTrue);
      expect(has(Campaign.byId('5-3')!, TileFeature.ice), isTrue);
      expect(Campaign.byId('4-1')!.config(players: 2).darkness, 4);
      expect(Campaign.byId('5-2')!.config(players: 2).windInterval, 8);
      expect(Campaign.byId('5-2')!.config(players: 2).cannonInterval, 12);
      expect(Campaign.byId('3-2')!.config(players: 2).ventInterval,
          greaterThan(0));
      final nests = Campaign.byId('4-3')!
          .level(seed: 5, players: 2)
          .enemySpawns
          .where((e) => e.kind == EnemyKind.moleNest);
      expect(nests, isNotEmpty);
      final grid = Campaign.byId('4-3')!.level(seed: 5, players: 2).grid;
      for (final n in nests) {
        expect(grid.atPos(n.pos), TileType.brick, reason: 'nests are buried');
      }
    });

    test('Gale Gauntlet is always the big field', () {
      final l = Campaign.byId('5-7')!.level(seed: 1, players: 2);
      expect(l.grid.width, 41);
      expect(l.grid.height, 17);
    });
  });

  test('snapshots carry the World 3-5 state over the wire', () {
    final w = makeWorld('''
###########
#P>V_GRWi.#
###########
''', config: const WorldConfig(windInterval: 8, darkness: 4));
    final p = w.addPlayer()
      ..cursedFor = 3
      ..momentum = Direction.right;
    w.regrowing[const GridPos(9, 1)] = 5;
    w.hazards.add(Hazard(0, 1, 9, kind: HazardKind.cannonLeft));
    final m = w.spawnEnemy(const GridPos(9, 1), EnemyKind.mimic);
    run(w, World.windCalm + 0.1);
    final snap = roundTrip(w);
    expect(snap.grid.featureAt(2, 1), TileFeature.conveyorRight);
    expect(snap.grid.featureAt(3, 1), TileFeature.vent);
    expect(snap.grid.featureAt(4, 1), TileFeature.plate);
    expect(snap.grid.featureAt(5, 1), TileFeature.gate);
    expect(snap.grid.at(5, 1), TileType.pillar);
    expect(snap.grid.featureAt(6, 1), TileFeature.possessed);
    expect(snap.grid.featureAt(7, 1), TileFeature.warp);
    expect(snap.grid.featureAt(8, 1), TileFeature.ice);
    expect(snap.wind, Direction.left);
    expect(snap.darkness, 4);
    expect(snap.regrowing.single.x, 9);
    expect(snap.player(p.id)!.cursed, isTrue);
    final es = snap.enemies.firstWhere((e) => e.id == m.id);
    expect(es.state, EnemyStateKind.disguised);
    expect(es.disguise, m.disguise);
    expect(es.kindData, EnemyKind.mimic);
  });
}
