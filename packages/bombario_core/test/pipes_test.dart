import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

import 'world_test.dart' show run;

/// Warp pipes, after Mario's: each juts out of a wall with its mouth facing
/// into the map. Walk into a mouth to go in; you slide out of another
/// pipe's mouth, picked at random, walking the way it faces.
void main() {
  // Pipes on the left wall (mouth right), right wall (mouth left), top wall
  // (mouth down) and bottom wall (mouth up).
  const ascii = '''
###########
#...P.....#
#.........#
#.........#
#.........#
#.........#
###########
''';
  World pipeWorld({int seed = 1}) {
    final level = LevelData.parse(ascii, timeLimit: 10);
    final g = level.grid;
    g.setFeature(1, 3, TileFeature.pipeRight);
    g.setFeature(9, 3, TileFeature.pipeLeft);
    g.setFeature(5, 1, TileFeature.pipeDown);
    g.setFeature(5, 5, TileFeature.pipeUp);
    return World(level, seed: seed);
  }

  test('pipes are solid and face out of their wall', () {
    final w = pipeWorld();
    expect(w.grid.pipeFront(const GridPos(1, 3)), const GridPos(2, 3));
    expect(w.grid.pipeFront(const GridPos(5, 1)), const GridPos(5, 2));
    final p = w.addPlayer()..setPosition(3.5, 3.5);
    run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.up)});
    expect(p.tileY, 1, reason: 'nothing in the way');
    // Walking along the left wall past the pipe's side: blocked, no entry.
    p.setPosition(1.5, 4.5);
    run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.up)});
    expect(p.tile, const GridPos(1, 4));
    expect(p.inPipe, isFalse);
  });

  test('walking into a mouth slides you in and out of another mouth', () {
    final w = pipeWorld();
    final p = w.addPlayer()..setPosition(2.7, 3.5);
    w.tick(const {});
    expect(WorldSnapshot.of(w).player(p.id)!.actionLabel, 'pipe');
    w.tick({p.id: const PlayerInput(direction: Direction.left)});
    final entered = w.events.whereType<PipeEntered>().single;
    expect((entered.x, entered.y), (1, 3));
    expect(p.facing, Direction.left);

    // Nothing hurts a player inside a pipe.
    w.flames.add(Flame(x: 2, y: 3, ownerId: 99));
    final events = run(w, World.pipeTotal + 0.1);
    expect(p.alive, isTrue);
    final exit = GridPos(entered.toX, entered.toY);
    expect(events.whereType<PipeExited>(), hasLength(1));
    expect(p.inPipe, isFalse);
    expect(p.tile, w.grid.pipeFront(exit), reason: 'out in front of it');
    expect(p.facing, w.grid.featureAt(exit.x, exit.y).pipeMouth);
  });

  test('exits are random but never blocked', () {
    final seen = <GridPos>{};
    for (var seed = 0; seed < 16; seed++) {
      final w = pipeWorld(seed: seed);
      final p = w.addPlayer()..setPosition(2.5, 3.5);
      // A bomb in front of the right-wall pipe blocks that exit.
      w.bombs.add(Bomb(
          id: 99, x: 8, y: 3, ownerId: 5, range: 1, fuse: 99, remote: false));
      w.tick({p.id: const PlayerInput(action: true)});
      final e = w.events.whereType<PipeEntered>().single;
      seen.add(GridPos(e.toX, e.toY));
    }
    expect(seen, {const GridPos(5, 1), const GridPos(5, 5)});
  });

  test('Action away from a pipe still detonates', () {
    final w = pipeWorld();
    final p = w.addPlayer()..remote = true;
    p.setPosition(3.5, 2.5);
    w.tick({p.id: const PlayerInput(placeBomb: true)});
    w.tick({p.id: const PlayerInput(action: true)});
    expect(w.events.whereType<PipeEntered>(), isEmpty);
    expect(w.events.whereType<BombExploded>(), hasLength(1));
  });

  test('flames stop at a pipe', () {
    final w = pipeWorld();
    w.addPlayer().setPosition(3.5, 1.5);
    w.bombs.add(Bomb(
        id: 99, x: 3, y: 3, ownerId: 5, range: 5, fuse: 0.01, remote: false));
    run(w, 0.1);
    expect(w.flameAt(1, 3), isNull);
    expect(w.flameAt(2, 3), isNotNull);
  });

  test('campaign stages get wall pipes from stage 3', () {
    expect(Campaign.byId('1-1')!.pipeCount, 0);
    expect(Campaign.byId('1-3')!.pipeCount, 2);
    expect(Campaign.byId('2-1')!.pipeCount, 3);
    expect(Campaign.byId('3-1')!.pipeCount, 4);
    expect(Campaign.byId('1-5')!.pipeCount, 0, reason: 'bonus');
    expect(Campaign.byId('1-10')!.pipeCount, 0, reason: 'boss');
    for (final s in Campaign.stages) {
      for (final players in [1, 4]) {
        final level = s.level(seed: 9, players: players);
        final g = level.grid;
        final pipes = g.pipes;
        expect(pipes.length, lessThanOrEqualTo(s.pipeCount), reason: s.id);
        if (s.pipeCount >= 2) {
          expect(pipes.length, greaterThanOrEqualTo(2), reason: s.id);
        }
        for (final p in pipes) {
          final mouth = g.featureAt(p.x, p.y).pipeMouth;
          final behind = p.step(-mouth.dx, -mouth.dy);
          expect(g.atPos(behind), TileType.pillar, reason: '${s.id} $p');
          final front = g.pipeFront(p);
          expect(g.isWalkable(front.x, front.y), isTrue, reason: s.id);
        }
        expect(level.solvable, isTrue, reason: s.id);
      }
    }
  });

  test('pipe state rides in snapshots', () {
    final w = pipeWorld();
    final p = w.addPlayer()..setPosition(2.5, 3.5);
    w.tick({p.id: const PlayerInput(action: true)});
    final back = WorldSnapshot.fromJson(WorldSnapshot.of(w).toJson());
    expect(back.player(p.id)!.pipe, greaterThan(0));
    expect(back.grid.pipes, hasLength(4));
    expect(back.grid.featureAt(1, 3), TileFeature.pipeRight);
  });
}
