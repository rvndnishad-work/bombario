import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('arrows steer, Space drops a bomb, Escape pauses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    await tester.pump(const Duration(milliseconds: 50));
    final state = tester.state(find.byType(GameScreen));
    final game = (state as dynamic).game as BlastGame;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    expect(game.input.held, Direction.right);
    // A second arrow takes over; letting it go falls back to the first.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    expect(game.input.held, Direction.down);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(game.input.held, Direction.right);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(game.input.held, Direction.none);
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.input.moving, Direction.none);

    // A quick tap nudges the player a short step, not a whole tile.
    final before = game.sim.players.single.x;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(game.input.moving, Direction.left);
    await tester.pump(const Duration(milliseconds: 300));
    final stepped = before - game.sim.players.single.x;
    expect(stepped, greaterThan(0.05));
    expect(stepped, lessThan(0.4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(before - game.sim.players.single.x, stepped);

    // Held on the emulator: a pair, the repeat delay, then a stream of
    // pairs. The player walks through the repeats and stops soon after
    // the last.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 33));
      expect(game.input.held, Direction.left);
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.input.held, Direction.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.sim.bombs, isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(game.overlays.isActive(Overlays.pause), isTrue);
  });
}
