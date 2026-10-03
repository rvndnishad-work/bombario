import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/progress/achievements.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stage, chain, exit and boss achievements unlock once', () {
    final a = Achievements.memory();
    a.startStage();
    var got = a.recordEvents(
      const [ExitBombed(), BombExploded(1, 1, 0), BombExploded(2, 1, 0)],
      myId: 0,
      stageId: '1-10',
    );
    expect(got, isEmpty);
    got = a.recordEvents(
      const [
        BombExploded(1, 1, 0),
        BombExploded(2, 1, 0),
        BombExploded(3, 1, 0),
        StageCleared(),
      ],
      myId: 0,
      stageId: '1-10',
    );
    expect(
      got.map((d) => d.id),
      containsAll(['chain-3', 'world-1', 'angry-door']),
    );
    expect(a.stat(Achievements.chainRecord), 3);
    expect(a.stat(Achievements.stagesCleared), 1);
    // Already unlocked: nothing new the second time.
    expect(
      a.recordStageCleared('1-10').map((d) => d.id),
      isNot(contains('world-1')),
    );
  });

  test('every achievement has a sprite in the atlas index', () {
    for (final d in Achievements.all) {
      expect(SpriteAtlas.has(d.sprite), isTrue, reason: d.sprite);
    }
    expect(
      Achievements.all.map((d) => d.id).toSet(),
      hasLength(Achievements.all.length),
    );
  });
}
