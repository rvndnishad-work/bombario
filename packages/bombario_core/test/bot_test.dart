import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

/// Runs [w] with every player in [bots] driven by its bot, for at most
/// [seconds] or until the world is over. [each] sees the world after every
/// tick; [before] sees it before.
void runBots(World w, List<Bot> bots, double seconds,
    {void Function()? before, void Function()? each}) {
  final ticks = (seconds * World.tickRate).round();
  for (var i = 0; i < ticks && !w.over; i++) {
    final inputs = {for (final b in bots) b.playerId: b.think()};
    before?.call();
    w.tick(inputs);
    each?.call();
  }
}

World versusArena(int seed, int players) => World(
      LevelData.generate(
        seed: seed,
        width: 15,
        height: 13,
        players: players,
        enemyCount: 0,
        brickDensity: 0.55,
        items: const [ItemType.bombUp, ItemType.fireUp, ItemType.speedUp],
        timeLimit: 120,
      ),
      seed: seed,
      config: WorldConfig.versus,
    );

/// An open arena with a pillar grid and two spawns in opposite corners.
const openArena = '''
###########
#P........#
#.#.#.#.#.#
#.........#
#.#.#.#.#.#
#.........#
#.#.#.#.#.#
#........P#
###########
''';

void main() {
  test('BotSkill parses by name and falls back to normal', () {
    expect(BotSkill.parse('hard'), BotSkill.hard);
    expect(BotSkill.parse('nonsense'), BotSkill.normal);
    expect(BotSkill.parse(null), BotSkill.normal);
  });

  test('a bot escapes its own bombs in many seeded mazes', () {
    for (final skill in BotSkill.values) {
      var died = 0, bombs = 0, runs = 0;
      for (var seed = 0; seed < 25; seed++) {
        final w = World(
          LevelData.generate(
              seed: seed,
              width: 15,
              height: 13,
              enemyCount: 0,
              brickDensity: 0.6),
          seed: seed,
        );
        final bot = Bot(w, w.addPlayer().id, skill: skill, seed: seed);
        runBots(w, [bot], 30, each: () {
          bombs += w.events.whereType<BombPlaced>().length;
        });
        runs++;
        if (w.failed) died++;
      }
      // Bricks are broken all game long, so the bot bombs a lot.
      expect(bombs, greaterThan(runs * 5), reason: '$skill bombs');
      final survival = 1 - died / runs;
      expect(
          survival, greaterThanOrEqualTo(skill == BotSkill.easy ? 0.8 : 0.95),
          reason: '$skill survival');
    }
  });

  test('a bot kills a stationary dummy in an open arena', () {
    for (var seed = 0; seed < 5; seed++) {
      final w = World(LevelData.parse(openArena), config: WorldConfig.versus);
      final bot = Bot(w, w.addPlayer(name: 'bot').id, seed: seed);
      final dummy = w.addPlayer(name: 'dummy');
      runBots(w, [bot], 20);
      expect(w.winnerId, bot.playerId, reason: 'seed $seed');
      expect(dummy.alive, isFalse);
      expect(w.elapsed, lessThan(20));
    }
  });

  test('a bot hunts down a dummy behind bricks', () {
    final w = World(
      LevelData.parse('''
###########
#P..*.....#
#.#*#.#.#.#
#..*......#
#.#.#.#.#*#
#......*.P#
###########
'''),
      config: WorldConfig.versus,
    );
    final bot = Bot(w, w.addPlayer().id, skill: BotSkill.hard);
    w.addPlayer();
    runBots(w, [bot], 60);
    expect(w.winnerId, bot.playerId);
  });

  test('bots never step into a live flame', () {
    var steps = 0;
    for (var seed = 0; seed < 6; seed++) {
      final w = versusArena(seed, 4);
      final bots = [
        for (var i = 0; i < 4; i++)
          Bot(w, w.addPlayer().id,
              skill: BotSkill.values[i % 3], seed: seed * 7 + i),
      ];
      var flames = <GridPos>{};
      final where = <int, GridPos>{};
      runBots(w, bots, 90, before: () {
        flames = {for (final f in w.flames) GridPos(f.x, f.y)};
        for (final p in w.players) {
          where[p.id] = p.tile;
        }
      }, each: () {
        for (final p in w.players) {
          if (!p.alive &&
              !w.events
                  .whereType<PlayerDied>()
                  .any((e) => e.playerId == p.id)) {
            continue;
          }
          if (p.tile == where[p.id]) continue;
          steps++;
          expect(flames.contains(p.tile), isFalse,
              reason: 'seed $seed player ${p.id} walked into fire at '
                  '${p.tile} t=${w.elapsed}');
        }
      });
    }
    expect(steps, greaterThan(500));
  });

  test('a co-op bot revives a fallen teammate', () {
    final w = World(
      LevelData.parse('''
###########
#P........#
#.#.#.#.#.#
#.........#
#.#.#.#.#.#
#........P#
###########
'''),
      config: WorldConfig.coop,
    );
    final human = w.addPlayer(name: 'human');
    final bot = Bot(w, w.addPlayer(name: 'bot').id);
    // The human falls where they spawned.
    human
      ..alive = false
      ..ghost = true
      ..tombstone = human.tile;
    final lives = w.livesLeft;
    final revived = <PlayerRevived>[];
    runBots(w, [bot], 20, each: () {
      revived.addAll(w.events.whereType<PlayerRevived>());
      if (revived.isNotEmpty) w.cleared = true; // stop here
    });
    expect(revived.single.playerId, human.id);
    expect(revived.single.byPlayerId, bot.playerId);
    expect(human.alive, isTrue);
    expect(w.livesLeft, lives - 1);
  });

  test('a co-op bot blasts through bricks to revive a walled-off teammate', () {
    final w = World(
      LevelData.parse('''
###########
#P.+......#
#.#+#.#.#.#
#..+......#
#.#+#.#.#.#
#..+.....P#
###########
'''),
      config: WorldConfig.coop,
    );
    final human = w.addPlayer(name: 'human');
    final bot = Bot(w, w.addPlayer(name: 'bot').id);
    human
      ..alive = false
      ..ghost = true
      ..tombstone = human.tile;
    final revived = <PlayerRevived>[];
    runBots(w, [bot], 40, each: () {
      revived.addAll(w.events.whereType<PlayerRevived>());
      if (revived.isNotEmpty) w.cleared = true; // stop here
    });
    expect(revived.single.byPlayerId, bot.playerId);
  });

  test('a co-op bot with a fallen teammate never just runs out the clock', () {
    // Regression: the bot used to chase enemies it could never catch, or
    // stop short of a grave behind bricks, until the timer ran out.
    for (var seed = 1; seed <= 12; seed++) {
      final stage = Campaign.first;
      final w = World(stage.level(seed: seed, players: 2),
          seed: seed, config: stage.config(players: 2));
      final human = w.addPlayer(name: 'human');
      final bot = Bot(w, w.addPlayer(name: 'bot').id, seed: seed);
      human
        ..alive = false
        ..ghost = true
        ..tombstone = human.tile;
      var revived = false;
      runBots(w, [bot], w.timeLeft + 1, each: () {
        if (w.events.any((e) => e is PlayerRevived)) {
          revived = true;
          w.cleared = true; // stop here
        }
      });
      expect(revived || w.failed, isTrue, reason: 'seed $seed');
      expect(w.timeLeft, greaterThan(0), reason: 'seed $seed');
    }
  });

  test('a ghost bot floats by its tombstone', () {
    final w = World(LevelData.parse(openArena), config: WorldConfig.coop);
    final p = w.addPlayer();
    w.addPlayer();
    final bot = Bot(w, p.id);
    p
      ..alive = false
      ..ghost = true
      ..tombstone = const GridPos(5, 3)
      ..setPosition(1.5, 1.5);
    runBots(w, [bot], 6);
    expect(p.tile.manhattanTo(const GridPos(5, 3)), lessThanOrEqualTo(1));
  });

  test('co-op bots clear a small stage together', () {
    // The old 15 x 11 first stage, from before 1-1 went full width.
    const small = '''
###############
#P.+.+...+.+.P#
#.#+#.#+#.#+#.#
#+..+.e.+e.U..#
#.#.#+#.#+#.#+#
#+.+e..U+..e.+#
#.#+#.#.#+#.#.#
#..+..e.+e.+.+#
#+#.#+#.#E#.#.#
#P.+...+...+.P#
###############
''';
    var cleared = 0;
    for (var seed = 0; seed < 4; seed++) {
      final stage = Campaign.first;
      final level = LevelData.parse(
        StageDef.shuffleBricks(small, seed),
        items: stage.items,
        enemyKinds: stage.layoutEnemies,
        timeLimit: stage.timeLimit,
      );
      final w = World(level, seed: seed, config: stage.config(players: 2));
      final bots = [
        for (var i = 0; i < 2; i++)
          Bot(w, w.addPlayer().id, skill: BotSkill.hard, seed: seed + i),
      ];
      runBots(w, bots, 240);
      if (w.cleared) cleared++;
    }
    expect(cleared, greaterThanOrEqualTo(2));
  });

  test('a co-op bot does not bomb a teammate standing in the blast', () {
    final w = World(
      LevelData.parse('''
#######
#P.*..#
#.#.#.#
#P....#
#######
'''),
      config: WorldConfig.coop,
    );
    final bot = Bot(w, w.addPlayer().id, skill: BotSkill.hard);
    final mate = w.addPlayer();
    // The bot's only brick is in line with where the teammate stands.
    mate.setPosition(2.5, 1.5);
    var bombs = 0;
    runBots(w, [bot], 5, each: () {
      mate.setPosition(2.5, 1.5);
      for (final b in w.events.whereType<BombPlaced>()) {
        final blastHitsMate =
            (b.bomb.y == 1 && (b.bomb.x - 2).abs() <= b.bomb.range) ||
                (b.bomb.x == 2 && (b.bomb.y - 1).abs() <= b.bomb.range);
        if (blastHitsMate) bombs++;
      }
    });
    expect(bombs, 0);
    expect(mate.alive, isTrue);
  });

  test('4-bot versus matches end with a winner or a draw', () {
    for (var seed = 0; seed < 6; seed++) {
      final w = versusArena(seed, 4);
      final bots = [
        for (var i = 0; i < 4; i++)
          Bot(w, w.addPlayer().id,
              skill: BotSkill.values[(seed + i) % 3], seed: seed * 10 + i),
      ];
      // Time-up sends hunters, so every round ends eventually.
      runBots(w, bots, 400);
      expect(w.over, isTrue, reason: 'seed $seed');
      expect(w.winnerId, isNotNull);
      expect(w.winnerId == -1 || bots.any((b) => b.playerId == w.winnerId),
          isTrue);
    }
  });

  test('bots are deterministic for a seed', () {
    String play() {
      final w = versusArena(3, 2);
      final bots = [
        for (var i = 0; i < 2; i++) Bot(w, w.addPlayer().id, seed: i),
      ];
      runBots(w, bots, 60);
      return [for (final p in w.players) '${p.x},${p.y},${p.alive}'].join('|');
    }

    expect(play(), play());
  });

  test('player skins ride in snapshots, omitted when classic', () {
    final w = World(LevelData.parse(openArena), config: WorldConfig.versus);
    final a = w.addPlayer(name: 'a', skin: 'ninja');
    final b = w.addPlayer(name: 'b');
    expect(b.skin, 'classic');
    final json = WorldSnapshot.of(w).toJson();
    final players = json['players'] as List;
    expect((players[0] as Map)['sk'], 'ninja');
    expect((players[1] as Map).containsKey('sk'), isFalse);
    final back = WorldSnapshot.fromJson(json);
    expect(back.player(a.id)!.skin, 'ninja');
    expect(back.player(b.id)!.skin, 'classic');
    expect(back.player(a.id)!.copyWith(x: 1).skin, 'ninja');
    expect(back.player(a.id)!.toPlayer().skin, 'ninja');
  });
}
