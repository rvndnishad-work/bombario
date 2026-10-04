import 'dart:math';

import 'autopilot.dart';
import 'campaign.dart';
import 'direction.dart';
import 'entities.dart';
import 'events.dart';
import 'grid.dart';
import 'input.dart';
import 'world.dart';

/// One stage played by [CampaignAutoplay]: the inputs that clear it, one per
/// tick the world actually advanced (ticks while the player lies dead are
/// skipped), so the app can replay it frame for frame.
class StagePlay {
  StagePlay({
    required this.index,
    required this.id,
    required this.seed,
    required this.inputs,
    required this.godMode,
    required this.cleared,
    required this.deaths,
    required this.rewinds,
    required this.seconds,
    required this.notes,
    this.startItems = const [],
    this.startActive = ActiveItem.none,
    this.startHearts = 0,
  });

  final int index;
  final String id;
  final int seed;
  final List<int> inputs;

  /// Fell back to the admin "No dying" switch: the autopilot couldn't
  /// clear the stage fairly within its budget.
  final bool godMode;
  final bool cleared;

  /// Deaths left in the final run (rewinds removed the rest).
  final int deaths;
  final int rewinds;
  final double seconds;
  final List<String> notes;

  /// What the player carried in from the stage before.
  final List<ItemType> startItems;
  final ActiveItem startActive;
  final int startHearts;

  Map<String, dynamic> toJson() => {
        'index': index,
        'id': id,
        'seed': seed,
        'godMode': godMode,
        'cleared': cleared,
        'deaths': deaths,
        'rewinds': rewinds,
        'seconds': seconds,
        'notes': notes,
        'startItems': [for (final i in startItems) i.name],
        'startActive': startActive.name,
        'startHearts': startHearts,
        'inputs': inputs,
      };

  static StagePlay fromJson(Map<String, dynamic> j) => StagePlay(
        index: j['index'] as int,
        id: j['id'] as String,
        seed: j['seed'] as int,
        inputs: (j['inputs'] as List).cast<int>(),
        godMode: j['godMode'] as bool,
        cleared: j['cleared'] as bool,
        deaths: j['deaths'] as int,
        rewinds: j['rewinds'] as int,
        seconds: (j['seconds'] as num).toDouble(),
        notes: (j['notes'] as List).cast<String>(),
        startItems: [
          for (final n in (j['startItems'] as List? ?? const []))
            ItemType.values.byName(n as String),
        ],
        startActive:
            ActiveItem.values.byName(j['startActive'] as String? ?? 'none'),
        startHearts: j['startHearts'] as int? ?? 0,
      );

  static int encode(PlayerInput i) =>
      i.direction.index | (i.placeBomb ? 8 : 0) | (i.action ? 16 : 0);

  static PlayerInput decode(int v) => PlayerInput(
        direction: Direction.values[v & 7],
        placeBomb: v & 8 != 0,
        action: v & 16 != 0,
      );
}

/// Plays the solo campaign the way the app's game screen does (stage seeds
/// `seed + index`, power-ups carried between stages) with an [Autopilot],
/// rewinding a few seconds and trying again whenever it dies.
class CampaignAutoplay {
  CampaignAutoplay({
    this.seed = 1,
    this.tickBudget = 400000,
    this.wallBudget = const Duration(seconds: 150),
  });

  bool verbose = false;

  /// Real time spent per attempt at a stage.
  final Duration wallBudget;

  final int seed;

  /// Ticks simulated per stage, retries included, before giving up and
  /// replaying the stage in god mode.
  final int tickBudget;

  final List<ItemType> _items = [];
  ActiveItem _active = ActiveItem.none;
  int _hearts = 0;

  /// Starts from a typical loadout for reaching stage [index] (a Bomb Up
  /// and a Fire Up per world cleared, Speed Up from World 2), so a world
  /// can be played on its own.
  void loadoutFor(int index) {
    final world = Campaign.stages[index].world;
    _items.clear();
    for (var k = 1; k < world; k++) {
      _items.addAll([ItemType.bombUp, ItemType.fireUp]);
    }
    if (world >= 2) _items.add(ItemType.speedUp);
    if (world >= 4) _items.add(ItemType.speedUp);
    _active = ActiveItem.none;
    _hearts = 0;
  }

  /// Power-ups the next stage starts with.
  List<ItemType> get items => List.unmodifiable(_items);

  World _build(int index) {
    final def = Campaign.stages[index];
    final s = seed + index;
    final w = World(def.level(seed: s, players: 1),
        seed: s, config: def.config(players: 1, coop: false));
    final p = w.addPlayer(name: 'You');
    p.items.addAll(_items);
    p.recomputeStats();
    p.active = _active;
    p.hearts = _hearts;
    return w;
  }

  /// Plays campaign stage [index] and carries the power-ups on.
  StagePlay play(int index, {void Function(String)? log}) {
    var result = _play(index, god: false, log: log);
    if (!result.$1.cleared) {
      log?.call('${Campaign.stages[index].id}: falling back to god mode');
      final fair = result.$1;
      result = _play(index, god: true, log: log);
      result.$1.notes.add('Could not clear without dying after '
          '${fair.rewinds} retries; replayed with No dying.');
    }
    final p = result.$2.players.first;
    _items
      ..clear()
      ..addAll(p.items);
    _active = p.active;
    _hearts = p.hearts;
    return result.$1;
  }

  static bool _canBomb(Player p) => p.alive && p.bombsPlaced < p.maxBombs;

  static bool _enemyNear(World w, Player p, int steps) {
    for (final e in w.enemies) {
      if (!e.alive || !e.solid || e.kind.harmless) continue;
      if ((e.tileX - p.tileX).abs() + (e.tileY - p.tileY).abs() <= steps) {
        return true;
      }
    }
    return false;
  }

  /// Rebuilds the stage and replays [inputs] into it, and an autopilot that
  /// watched it happen.
  (World, Autopilot) _replay(int index, List<int> inputs, bool god, int seed) {
    final w = _build(index);
    final p = w.players.first..godMode = god;
    final pilot = Autopilot(w, p.id, seed: seed);
    for (final v in inputs) {
      while (w.over && !w.cleared) {
        w.respawn(p);
        w.clearFailure();
      }
      pilot.observe();
      w.tick({p.id: StagePlay.decode(v)});
    }
    return (w, pilot);
  }

  /// Tries walking to each of the autopilot's kill spots and bombing
  /// there, plus leaving it to the autopilot, playing each future out. The
  /// inputs of the best one that kills something (up to just after the
  /// kill), or null when none does.
  List<int>? _bestPlan(int index, List<int> inputs, Autopilot pilot, bool god) {
    final spots = pilot.killSpots();
    final options = <GridPos?>[null, ...spots];
    (int, List<int>)? best;
    for (final spot in options) {
      final r = _rollout(index, inputs, god, plan: spot);
      if (r.kill < 0 || r.score < 0) continue;
      final score = r.score - r.kill;
      // Keep the whole verified future: the kill and getting clear after.
      if (best == null || score > best.$1) best = (score, r.inputs);
    }
    return best?.$2;
  }

  /// Plays the autopilot on from [inputs] (walking to [plan] and bombing
  /// there first, if given) for a few seconds and scores what happened.
  /// [kill] is the tick of the first enemy hit, or -1.
  ({int score, int kill, List<int> inputs}) _rollout(
      int index, List<int> inputs, bool god,
      {GridPos? plan, int horizon = 150}) {
    final (w, pilot) = _replay(index, inputs, god, rolloutSeed);
    final p = w.players.first;
    if (plan != null) pilot.setPlan(plan);
    rollouts++;
    var score = 0;
    var kill = -1;
    final hpBefore = _enemyHp(w);
    final played = <int>[];
    for (var h = 0; h < horizon; h++) {
      if (w.cleared) {
        score += 5000;
        break;
      }
      if (w.over) return (score: -10000, kill: kill, inputs: played);
      final input = pilot.think();
      played.add(StagePlay.encode(input));
      w.tick({p.id: input});
      for (final e in w.events) {
        switch (e) {
          case EnemyDied(:final killerId) when killerId == p.id:
            score += 1000;
            if (kill < 0) kill = h;
          case BrickDestroyed():
            score += 10;
          case ItemPicked():
            score += 200;
          case PlayerDied() || HeartLost():
            return (score: -10000, kill: kill, inputs: played);
          case ExitBombed():
            score -= 3000;
          case ItemBurned():
            score -= 2000;
          default:
            break;
        }
      }
      // A boss or tough enemy taking a hit counts too.
      if (kill < 0 && _enemyHp(w) < hpBefore) kill = h;
      // Once something is hit, a little more to see us get clear.
      if (kill >= 0 && h > kill + 60) break;
    }
    final hits = hpBefore - _enemyHp(w);
    score += hits * 400;
    return (score: score, kill: kill, inputs: played);
  }

  static int _enemyHp(World w) {
    var hp = 0;
    for (final e in w.enemies) {
      if (e.alive && !e.kind.harmless) hp += max(1, e.hp);
    }
    return hp;
  }

  /// Seed of the autopilot that plays futures out; changes on each rewind
  /// so a retry tries different things.
  int rolloutSeed = 4242;

  /// Futures played out to pick bomb timings (for stats).
  int rollouts = 0;

  (StagePlay, World) _play(int index,
      {required bool god, void Function(String)? log}) {
    final def = Campaign.stages[index];
    final rng = Random(seed * 7919 + index);
    final inputs = <int>[];
    var world = _build(index);
    var player = world.players.first;
    player.godMode = god;
    var pilot = Autopilot(world, player.id, seed: rng.nextInt(1 << 30));
    var deadTicks = 0;
    var deaths = 0;
    var rewinds = 0;
    var simulated = 0;
    final failures = <int, int>{};
    var timeUpRewinds = 0;
    final notes = <String>[];
    final queued = <int>[];
    var nextPlan = 0;

    void rewindTo(int keep) {
      rewinds++;
      inputs.length = keep;
      queued.clear();
      rolloutSeed = rng.nextInt(1 << 30);
      nextPlan = keep + 15;
      world = _build(index);
      player = world.players.first;
      player.godMode = god;
      pilot = Autopilot(world, player.id, seed: rng.nextInt(1 << 30));
      for (final v in inputs) {
        while (world.over && !world.cleared) {
          world.respawn(player);
          world.clearFailure();
        }
        pilot.observe();
        world.tick({player.id: StagePlay.decode(v)});
        simulated++;
      }
      deadTicks = 0;
    }

    final clock = Stopwatch()..start();
    while (!world.cleared &&
        simulated < tickBudget &&
        clock.elapsed < wallBudget) {
      if (world.over) {
        world.tick(const {});
        if (++deadTicks >= 45) {
          deadTicks = 0;
          world.respawn(player);
          world.clearFailure();
        }
        continue;
      }
      PlayerInput input;
      if (queued.isNotEmpty) {
        // Replaying a future the planner already played out.
        pilot.observe();
        input = StagePlay.decode(queued.removeAt(0));
      } else {
        input = pilot.think();
        if (inputs.length >= nextPlan &&
            pilot.goal != 'flee' &&
            _canBomb(player) &&
            _enemyNear(world, player, 14)) {
          nextPlan = inputs.length + 9;
          final best = _bestPlan(index, inputs, pilot, god);
          if (best != null) {
            queued.addAll(best);
            input = StagePlay.decode(queued.removeAt(0));
          }
        }
      }
      if (verbose && inputs.length % 300 == 0) {
        log?.call('    ${inputs.length ~/ 30}s ${pilot.goal} at ${player.tile} '
            'queued=${queued.length} enemies=${world.enemies.where((e) => e.alive).length} '
            'exit=${world.exitRevealed} ${pilot.debug} ${pilot.goal == 'flee' ? pilot.why(player.tileX, player.tileY) : ''} '
            '${world.enemies.where((e) => e.alive).map((e) => '${e.kind.name}@${e.tile}/${e.state.name}').join(' ')}');
      }
      final wasTimeUp = world.timeUp;
      world.tick({player.id: input});
      simulated++;
      inputs.add(StagePlay.encode(input));
      final died = world.events.any((e) => e is PlayerDied || e is HeartLost);
      if (died) {
        final t = inputs.length;
        final bucket = t ~/ 45;
        final n = failures[bucket] = (failures[bucket] ?? 0) + 1;
        if (n <= 14) {
          final back = 30 * (n < 4 ? n : 3 * n) + rng.nextInt(45);
          if (verbose) {
            log?.call(
                '  died at ${t ~/ 30}s (try $n), back to ${max(0, t - back) ~/ 30}s; '
                'enemies ${world.enemies.where((e) => e.alive).map((e) => e.kind.name).join(',')}');
          }
          rewindTo(max(0, t - back));
          continue;
        }
        deaths++;
        notes.add('Died at ${(t / 30).toStringAsFixed(0)} s');
      }
      if (!wasTimeUp && world.timeUp && !def.bonus && timeUpRewinds < 6) {
        // Out of time: go back a good while and play it differently.
        timeUpRewinds++;
        final t = inputs.length;
        if (verbose) {
          log?.call(
              '  time up; enemies ${world.enemies.where((e) => e.alive).map((e) => '${e.kind.name}@${e.tile}').join(',')} exit=${world.exitRevealed}');
        }
        rewindTo(max(0, t - 30 * (20 + 15 * timeUpRewinds)));
        continue;
      }
    }
    if (world.cleared) {
      log?.call(
          '${def.id}: cleared in ${(inputs.length / 30).toStringAsFixed(0)} s, '
          '$deaths deaths, $rewinds rewinds${god ? ' (god mode)' : ''}');
    } else {
      log?.call(
          '${def.id}: NOT cleared (${world.enemies.where((e) => e.alive).length} enemies left, '
          'exit ${world.exitRevealed ? 'open' : 'hidden'})');
    }
    return (
      StagePlay(
        index: index,
        id: def.id,
        seed: seed + index,
        inputs: List.of(inputs),
        godMode: god,
        cleared: world.cleared,
        deaths: deaths,
        rewinds: rewinds,
        seconds: inputs.length / 30,
        notes: notes,
        startItems: List.of(_items),
        startActive: _active,
        startHearts: _hearts,
      ),
      world
    );
  }
}
