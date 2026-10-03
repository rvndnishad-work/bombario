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
    // An instant release (how the emulator sends a held key) keeps walking
    // through the keyboard's auto-repeat delay.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.input.held, Direction.down);
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.input.held, Direction.right);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 700));
    expect(game.input.held, Direction.none);

    // Held on the emulator: a pair, the repeat delay, then a stream of
    // pairs. The player walks the whole time and stops soon after the last.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.input.held, Direction.left);
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
