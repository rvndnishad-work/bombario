import 'dart:ui';

import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/game/world_renderer.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('draws every tile, enemy, state and marker without errors', () async {
    final atlas = await SpriteAtlas.load();
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
    final w = World(
      level,
      seed: 1,
      config: const WorldConfig(ghosts: true, sharedLives: 4, darkness: 4),
    );
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
    // World 3-5 terrain and conditions.
    for (final (i, f) in TileFeature.values.indexed) {
      if (f != TileFeature.none) w.grid.setFeature(1 + i % 13, 5, f);
    }
    w.wind = Direction.left;
    w.ventPhase = VentPhase.warning;
    w.hazards.addAll([
      Hazard(1, 3, 0.5, kind: HazardKind.cannonLeft),
      Hazard(4, 5, 0.5, kind: HazardKind.wall),
    ]);
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

    final renderer = WorldRenderer(
      () => WorldSnapshot.of(w),
      tileSize: 32,
      atlas: atlas,
      highContrast: () => true,
    );
    final recorder = PictureRecorder();
    renderer.update(0.2);
    renderer.render(Canvas(recorder));
    recorder.endRecording().dispose();
  });

  test('the terrain changes colour every five stages', () {
    final looks = [for (final s in Campaign.stages) WorldRenderer.lookFor(s)];
    expect(looks, hasLength(50));
    for (var i = 0; i < looks.length; i++) {
      // Stages 1-5 share a look, 6-10 the next, and so on.
      expect(looks[i], looks[i - i % 5], reason: Campaign.stages[i].id);
      if (i % 5 == 0 && i > 0) {
        expect(looks[i], isNot(looks[i - 1]), reason: Campaign.stages[i].id);
      }
    }
    expect(looks.toSet(), hasLength(10));
    expect(WorldRenderer.lookFor(null), '');
    for (final look in looks.where((l) => l.isNotEmpty)) {
      for (final tile in ['floor', 'cracked', 'pit', 'wall', 'brick', 'vent']) {
        expect(SpriteAtlas.has('$tile$look'), isTrue, reason: '$tile$look');
      }
    }
  });

  test('every item, enemy, player and ping has a sprite', () {
    for (final t in ItemType.values) {
      expect(
        SpriteAtlas.has(WorldRenderer.itemSprite(t)),
        isTrue,
        reason: '$t',
      );
    }
    for (final k in EnemyKind.all) {
      final name = WorldRenderer.enemySprites[k.name];
      expect(name, isNotNull, reason: '${k.name} has no sprite');
      expect(SpriteAtlas.has(name!), isTrue, reason: name);
    }
    for (var slot = 1; slot <= 4; slot++) {
      // Standing and both walk frames, facing the camera, away and sideways.
      for (final view in ['', '-up', '-side']) {
        for (final frame in ['', '-walk-a', '-walk-b']) {
          expect(SpriteAtlas.has('p$slot$view$frame'), isTrue);
        }
      }
      expect(SpriteAtlas.has('spirit-p$slot'), isTrue);
    }
    for (final name in WorldRenderer.pingSprites.values) {
      expect(SpriteAtlas.has(name), isTrue, reason: name);
    }
    for (final shape in ['fc', 'fh', 'fv', 'fl', 'fr', 'fu', 'fd']) {
      expect(SpriteAtlas.has(shape), isTrue);
      expect(SpriteAtlas.has('$shape-frost'), isTrue);
    }
  });

  test('sprites turn to face the way they walk', () {
    expect(WorldRenderer.facingSprite('p1', Direction.down), 'p1');
    expect(WorldRenderer.facingSprite('p1', Direction.up), 'p1-up');
    expect(WorldRenderer.facingSprite('p1', Direction.left), 'p1-side');
    expect(WorldRenderer.facingSprite('p1', Direction.right), 'p1-side');
    expect(WorldRenderer.facingSprite('puff', Direction.up), 'puff-up');
    // Enemies without a drawn view keep their front sprite.
    expect(WorldRenderer.facingSprite('moleNest', Direction.up), 'moleNest');
    expect(WorldRenderer.facingSprite('mimic', Direction.left), 'mimic');
  });
}
