import 'dart:ui';

import 'package:bombario/game/death_effects.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  World makeWorld() {
    final level = LevelData.parse('''
#########
#P..+...#
#.#.#.#.#
#.......#
#########
''');
    final w = World(level, seed: 1);
    w.addPlayer();
    w.spawnEnemy(const GridPos(6, 3), EnemyKind.puffball);
    return w;
  }

  test('a broken brick and a dead enemy each play once, then clear', () async {
    final atlas = await SpriteAtlas.load();
    final w = makeWorld();
    final fx = DeathEffects();
    String? sprite(EnemyState e) => 'puff';

    fx.observe(WorldSnapshot.of(w), 0, sprite);
    expect(fx.activeBricks, 0);
    expect(fx.activeEnemies, 0);

    w.grid.set(4, 1, TileType.floor);
    w.enemies.single.alive = false;
    fx.observe(WorldSnapshot.of(w), 0.1, sprite);
    expect(fx.activeBricks, 1);
    expect(fx.activeEnemies, 1);

    // Every phase draws without errors.
    for (final t in [0.15, 0.4, 0.7, 1.0, 1.3]) {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      fx.drawBricks(canvas, atlas, 32, t);
      fx.drawEnemies(canvas, atlas, 32, t);
      recorder.endRecording();
    }

    fx.observe(WorldSnapshot.of(w), 2, sprite);
    expect(fx.activeBricks, 0);
    expect(fx.activeEnemies, 0);
  });

  test('moving to a new maze animates nothing', () {
    final fx = DeathEffects();
    String? sprite(EnemyState e) => 'puff';
    fx.observe(WorldSnapshot.of(makeWorld()), 0, sprite);
    final next = World(
      LevelData.parse('''
###########
#P........#
###########
'''),
      seed: 2,
    )..addPlayer();
    fx.observe(WorldSnapshot.of(next), 0.1, sprite);
    expect(fx.activeBricks, 0);
    expect(fx.activeEnemies, 0);
  });
}
