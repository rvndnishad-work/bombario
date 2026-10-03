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
}
