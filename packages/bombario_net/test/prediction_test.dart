import 'package:bombario_core/bombario_core.dart';
import 'package:bombario_net/bombario_net.dart';
import 'package:test/test.dart';

void main() {
  late World world;
  late int me;

  setUp(() {
    final level = LevelData.generate(
      seed: 5,
      width: 15,
      height: 13,
      players: 1,
      enemyCount: 0,
      brickDensity: 0,
    );
    world = World(level, seed: 5, config: WorldConfig.versus);
    me = world.addPlayer(name: 'Me').id;
  });

  WorldSnapshot snap(int acked) =>
      WorldSnapshot.of(world, tick: 0, ackedInputs: {me: acked});

  test('predicts movement before the server confirms it', () {
    final p = LocalPredictor();
    p.onSnapshot(snap(0), me);
    final start = p.body!.y;
    for (var i = 0; i < 10; i++) {
      p.apply(const PlayerInput(direction: Direction.down));
    }
    expect(p.body!.y, greaterThan(start + 0.3));
    expect(p.pendingCount, 10);
  });

  test('matches the server exactly when it applies the same inputs', () {
    final p = LocalPredictor();
    p.onSnapshot(snap(0), me);
    const input = PlayerInput(direction: Direction.down);
    for (var i = 1; i <= 10; i++) {
      p.apply(input);
      world.tick({me: input});
    }
    // Server has processed the first 6 of them when the snapshot was taken.
    final server = World(world.level, seed: 5, config: WorldConfig.versus);
    final id = server.addPlayer(name: 'Me').id;
    for (var i = 0; i < 6; i++) {
      server.tick({id: input});
    }
    p.onSnapshot(WorldSnapshot.of(server, tick: 6, ackedInputs: {id: 6}), id);
    expect(p.pendingCount, 4);
    expect(p.body!.y, closeTo(world.playerById(me)!.y, 1e-9));
    expect(p.body!.x, closeTo(world.playerById(me)!.x, 1e-9));
  });

  test('snaps to the server when they disagree', () {
    final p = LocalPredictor();
    p.onSnapshot(snap(0), me);
    for (var i = 0; i < 10; i++) {
      p.apply(const PlayerInput(direction: Direction.down));
    }
    // The server never saw those inputs move anyone (all acked, no motion).
    p.onSnapshot(snap(10), me);
    expect(p.pendingCount, 0);
    expect(p.body!.y, world.playerById(me)!.y);
  });

  test('a ghost floats through bricks in prediction too', () {
    world.grid.set(1, 2, TileType.brick);
    final p = world.playerById(me)!
      ..alive = false
      ..ghost = true;
    final pred = LocalPredictor();
    pred.onSnapshot(snap(0), me);
    for (var i = 0; i < 15; i++) {
      pred.apply(const PlayerInput(direction: Direction.down));
    }
    expect(pred.body!.y, greaterThan(p.y + 1));
  });

  test('a frozen player does not move', () {
    world.playerById(me)!.frozenFor = 1;
    final pred = LocalPredictor();
    pred.onSnapshot(snap(0), me);
    final y = pred.body!.y;
    for (var i = 0; i < 10; i++) {
      pred.apply(const PlayerInput(direction: Direction.down));
    }
    expect(pred.body!.y, y);
  });

  test('reset forgets everything', () {
    final p = LocalPredictor();
    p.onSnapshot(snap(0), me);
    p.apply(const PlayerInput(direction: Direction.right));
    p.reset();
    expect(p.body, isNull);
    expect(p.pendingCount, 0);
  });
}
