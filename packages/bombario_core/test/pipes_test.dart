import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

import 'world_test.dart' show makeWorld, run;

/// Warp pipes, after Mario's: Action on one sinks you in, and you rise out
/// of another pipe picked at random.
void main() {
  World pipeWorld() {
    final w = makeWorld('''
#########
#P......#
#.......#
#.......#
#########
''');
    for (final (x, y) in [(1, 1), (7, 1), (7, 3), (1, 3)]) {
      w.grid.setFeature(x, y, TileFeature.pipe);
    }
    return w;
  }

  test('Action on a pipe sinks in, travels safely, and rises elsewhere', () {
    final w = pipeWorld();
    final p = w.addPlayer();
    w.tick(const {});
    expect(WorldSnapshot.of(w).player(p.id)!.actionLabel, 'pipe');

    w.tick({p.id: const PlayerInput(action: true)});
    final entered = w.events.whereType<PipeEntered>().single;
    expect(p.inPipe, isTrue);
    expect(p.tile, const GridPos(1, 1), reason: 'still sinking');

    // Nothing hurts a player inside a pipe.
    w.enemies.clear();
    w.flames.add(Flame(x: 1, y: 1, ownerId: 99));
    final events = run(w, World.pipeTotal + 0.1);
    expect(p.alive, isTrue);
    expect(events.whereType<PipeExited>(), hasLength(1));
    expect(p.inPipe, isFalse);
    expect(p.tile, GridPos(entered.toX, entered.toY));
    expect(p.tile, isNot(const GridPos(1, 1)));
    expect(p.onPipe, isTrue, reason: 'you can hop straight back in');
  });

  test('exits are random but never blocked', () {
    final seen = <GridPos>{};
    for (var seed = 0; seed < 12; seed++) {
      final level = LevelData.parse('''
#########
#P......#
#.......#
#.......#
#########
''', timeLimit: 10);
      for (final (x, y) in [(1, 1), (7, 1), (7, 3), (1, 3)]) {
        level.grid.setFeature(x, y, TileFeature.pipe);
      }
      final w = World(level, seed: seed);
      final p = w.addPlayer();
      w.bombs.add(Bomb(
          id: 99, x: 7, y: 3, ownerId: 5, range: 1, fuse: 99, remote: false));
      w.tick(const {});
      w.tick({p.id: const PlayerInput(action: true)});
      final e = w.events.whereType<PipeEntered>().single;
      seen.add(GridPos(e.toX, e.toY));
    }
    expect(seen, {const GridPos(7, 1), const GridPos(1, 3)});
  });

  test('Action off a pipe still detonates', () {
    final w = pipeWorld();
    final p = w.addPlayer()..remote = true;
    p.setPosition(3.5, 2.5);
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    w.tick({p.id: const PlayerInput(action: true)});
    expect(w.events.whereType<PipeEntered>(), isEmpty);
    expect(w.events.whereType<BombExploded>(), hasLength(1));
  });

  test('campaign stages get pipes near the edges from stage 3', () {
    expect(Campaign.byId('1-1')!.pipeCount, 0);
    expect(Campaign.byId('1-3')!.pipeCount, 2);
    expect(Campaign.byId('2-1')!.pipeCount, 3);
    expect(Campaign.byId('3-1')!.pipeCount, 4);
    expect(Campaign.byId('1-5')!.pipeCount, 0, reason: 'bonus');
    expect(Campaign.byId('1-10')!.pipeCount, 0, reason: 'boss');
    for (final s in Campaign.stages) {
      final level = s.level(seed: 9, players: 1);
      final pipes = level.grid.pipes;
      expect(pipes.length, lessThanOrEqualTo(s.pipeCount), reason: s.id);
      if (s.pipeCount >= 2) {
        expect(pipes.length, greaterThanOrEqualTo(2), reason: s.id);
      }
      for (final p in pipes) {
        expect(level.grid.isWalkable(p.x, p.y), isTrue, reason: s.id);
      }
      expect(level.solvable, isTrue, reason: s.id);
    }
  });

  test('pipe state rides in snapshots', () {
    final w = pipeWorld();
    final p = w.addPlayer();
    w.tick(const {});
    w.tick({p.id: const PlayerInput(action: true)});
    final back = WorldSnapshot.fromJson(WorldSnapshot.of(w).toJson());
    expect(back.player(p.id)!.pipe, greaterThan(0));
    expect(back.grid.pipes, hasLength(4));
  });
}
