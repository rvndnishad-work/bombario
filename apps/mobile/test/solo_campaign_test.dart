import 'package:bombario/ads/rewarded_ads.dart';
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

  testWidgets('watching an ad on game over puts you back with one life', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ads = _FakeAds();
    RewardedAds.instance = ads;
    addTearDown(() => RewardedAds.instance = const NoRewardedAds());
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    await tester.pump(const Duration(milliseconds: 50));
    final game =
        (tester.state(find.byType(GameScreen)) as dynamic).game as BlastGame;
    game.skipIntro();

    game.lives = 1;
    game.player.invincibleFor = 0;
    game.sim.spawnEnemy(game.player.tile, game.sim.enemies.first.kind);
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (game.overlays.isActive(Overlays.gameOver)) break;
    }
    expect(game.overlays.isActive(Overlays.gameOver), isTrue);
    await tester.pump();

    // A tap still landing from play can't start an ad.
    await tester.tap(find.byKey(const Key('extra-life-ad')));
    await tester.pump();
    expect(ads.shown, 0);
    await tester.pump(const Duration(milliseconds: 1300));

    // A skipped ad gives nothing.
    ads.reward = false;
    await tester.tap(find.byKey(const Key('extra-life-ad')));
    await tester.pump();
    expect(find.textContaining('No ad right now'), findsOneWidget);
    expect(game.lives, 0);

    // A watched one puts the player back on the same stage.
    ads.reward = true;
    await tester.tap(find.byKey(const Key('extra-life-ad')));
    await tester.pump();
    expect(game.overlays.isActive(Overlays.gameOver), isFalse);
    expect(game.lives, 1);
    expect(game.player.alive, isTrue);
    expect(game.stage.id, '1-1');
    expect(ads.shown, 2);
    expect(game.adLivesUsed, 1);
    // A run gets two ad lives; after that Game Over means starting over.
    game.adLivesUsed = BlastGame.maxAdLives;
    game.lives = 0;
    expect(game.canContinue, isFalse);
    expect(game.adLivesSpent, isTrue);
    game.restart();
    expect(game.adLivesUsed, 0);
    expect(game.stage.id, '1-1');
    // Clear the enemy we dropped on the spawn before time moves on.
    for (final e in game.sim.enemies) {
      e.alive = false;
    }
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('lives never pass seven, from 1-Ups or points', (tester) async {
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

    // A 1-Up under the player's feet.
    final me = game.sim.players.single;
    game.sim.floorItems.add(
      core.FloorItem(x: me.tileX, y: me.tileY, type: core.ItemType.extraLife),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.lives, BlastGame.startingLives + 1);
    expect(find.text('1-Up!'), findsOneWidget);

    final before = game.lives;
    expect(game.gainLives(10), BlastGame.maxLives - before);
    expect(game.lives, BlastGame.maxLives);
    expect(game.gainLives(1), 0);
    expect(game.lives, 7);
  });
}

class _FakeAds implements RewardedAds {
  bool reward = true;
  int shown = 0;

  @override
  bool get supported => true;

  @override
  Future<void> start() async {}

  @override
  Future<bool> showForReward() async {
    shown++;
    return reward;
  }
}
