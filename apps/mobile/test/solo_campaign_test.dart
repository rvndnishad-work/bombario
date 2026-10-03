import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('solo play starts the campaign at 1-1 and runs', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    await tester.pump(const Duration(milliseconds: 50));
    final state = tester.state(find.byType(GameScreen));
    final game = (state as dynamic).game as BlastGame;

    // The stage card holds the board still, then play starts on its own.
    expect(find.text('STAGE 1-1'), findsOneWidget);
    expect(game.sim.elapsed, 0);
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('STAGE 1-1'), findsNothing);
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

  testWidgets('losing the last life shows the game-over menu', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    await tester.pump(const Duration(milliseconds: 50));
    final state = tester.state(find.byType(GameScreen));
    final game = (state as dynamic).game as BlastGame;

    // Down to the last life, then an enemy lands on the player.
    game.lives = 1;
    game.player.invincibleFor = 0;
    game.sim.spawnEnemy(game.player.tile, game.sim.enemies.first.kind);
    for (var i = 0; i < 80 && game.lives > 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.lives, 0);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.overlays.isActive(Overlays.gameOver), isTrue);
  });

  testWidgets('standing on the exit with enemies left says it is locked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    await tester.pump(const Duration(milliseconds: 50));
    final game =
        (tester.state(find.byType(GameScreen)) as dynamic).game as BlastGame;
    game.skipIntro();
    await tester.pump(const Duration(milliseconds: 50));

    final me = game.sim.players.single;
    game.sim.floorItems.add(
      core.FloorItem(x: me.tileX, y: me.tileY, type: core.ItemType.exit),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('The exit is locked'), findsOneWidget);
    expect(find.textContaining('6 enemies left'), findsOneWidget);
    expect(game.sim.cleared, isFalse);
  });
}
