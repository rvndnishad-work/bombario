import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('solo play starts the campaign at 1-1 and runs', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final state = tester.state(find.byType(GameScreen));
    final game = (state as dynamic).game as BlastGame;
    expect(game.stage.id, '1-1');
    expect(game.sim.elapsed, greaterThan(1));
    expect(find.textContaining('First Spark'), findsOneWidget);
    expect(game.sim.enemies, hasLength(6));

    // The intro popup closes with its button.
    await tester.tap(find.bySemanticsLabel('Close message'));
    await tester.pump();
    expect(find.textContaining('First Spark'), findsNothing);

    // Pausing freezes the simulation until Resume.
    await tester.tap(find.byKey(const Key('pause-button')));
    await tester.pump();
    final frozenAt = game.sim.elapsed;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.sim.elapsed, frozenAt);
    await tester.tap(find.byKey(const Key('resume')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.sim.elapsed, greaterThan(frozenAt));

    // Jump to the boss and make sure it plays too.
    game.stageIndex = 8;
    game.nextStage();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.stage.id, '1-10');
    expect(game.sim.enemies.first.kind.boss, isTrue);
  });
}
