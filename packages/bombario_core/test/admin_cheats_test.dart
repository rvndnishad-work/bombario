import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

import 'world_test.dart' show makeWorld, run;

/// The admin viewer's cheats: no dying, no enemies, walk through walls.
void main() {
  test('god mode survives enemies and its own bomb', () {
    final w = makeWorld('''
#######
#P.e..#
#######
''');
    final p = w.addPlayer()..godMode = true;
    w.enemies.single.setPosition(p.x, p.y);
    p.fireRange = 3;
    run(w, 0.1, inputs: {p.id: const PlayerInput(placeBomb: true)});
    final events = run(w, 4);
    expect(p.alive, isTrue);
    expect(events.whereType<PlayerDied>(), isEmpty);
    expect(events.whereType<BombExploded>(), isNotEmpty);
  });

  test('no enemies removes them and opens the exit', () {
    final w = makeWorld('''
#######
#P.e.e#
#######
''');
    w.addPlayer();
    w.noEnemies = true;
    w.tick(const {});
    expect(w.enemies, isEmpty);
    expect(w.allEnemiesDead, isTrue);
  });

  test('walk through walls passes pillars and bricks but not the border', () {
    final w = makeWorld('''
#######
#P#+..#
#######
''');
    final p = w.addPlayer()..noClip = true;
    run(w, 3, inputs: {p.id: const PlayerInput(direction: Direction.right)});
    expect(p.tileX, 5);
    run(w, 1, inputs: {p.id: const PlayerInput(direction: Direction.up)});
    expect(p.tileY, 1, reason: 'the border still stops you');
  });
}
