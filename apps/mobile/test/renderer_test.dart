import 'dart:ui';

import 'package:bombario/game/world_renderer.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('draws every Phase 3 tile, enemy, state and marker without errors', () {
    final level = LevelData.parse(
      '''
###############
#P.~..+.....P.#
#.#.#.#.#.#.#.#
#.............#
#.#.#.#.#.#.#.#
#.............#
###############
''',
      items: const [ItemType.sonar],
    );
    final w = World(level, seed: 1, config: WorldConfig.coop);
    final a = w.addPlayer()
      ..applyItem(ItemType.heart)
      ..frozenFor = 1;
    final b = w.addPlayer();
    b
      ..alive = false
      ..ghost = true
      ..tombstone = const GridPos(5, 3)
      ..reviveProgress = 1;
    w.grid.set(5, 1, TileType.pit);
    var x = 1;
    for (final kind in EnemyKind.all) {
      final e = w.spawnEnemy(GridPos(x, 3 + (x.isEven ? 2 : 0)), kind);
      e.state = EnemyStateKind.values[x % EnemyStateKind.values.length];
      e.frozenFor = x.isOdd ? 1 : 0;
      e.slowFor = x % 3 == 0 ? 1 : 0;
      x = x % 13 + 1;
    }
    w.tick({a.id: const PlayerInput(placeBomb: true, ping: PingKind.help)});
    w.hazards.add(Hazard(7, 3, 0.6));
    w.sonar.add(SonarReveal(6, 1, ItemType.exit, 3));
    w.flames.add(Flame(x: 9, y: 3, ownerId: a.id, frost: true));
    w.floorItems.addAll([
      for (final t in ItemType.values) FloorItem(x: 9, y: 5, type: t),
    ]);

    final renderer = WorldRenderer(() => WorldSnapshot.of(w), tileSize: 32);
    final recorder = PictureRecorder();
    renderer.update(0.2);
    renderer.render(Canvas(recorder));
    recorder.endRecording().dispose();
  });

  test('every item has a glyph', () {
    for (final t in ItemType.values) {
      if (t == ItemType.exit) continue;
      expect(WorldRenderer.itemGlyph(t), isNotEmpty);
    }
  });
}
