import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario/ui/keyboard_controls.dart';
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
    game.skipIntro();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    expect(game.input.held, Direction.right);
    // A second arrow takes over; letting it go falls back to the first.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    expect(game.input.held, Direction.down);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 600));
    expect(game.input.held, Direction.right);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 600));
    expect(game.input.held, Direction.none);
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.input.moving, Direction.none);

    // An instant press+release (a tap, or the start of a held key on the
    // emulator) keeps walking through the host's repeat delay, then stops.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(game.input.held, Direction.left);
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.input.held, Direction.left);
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.input.held, Direction.none);
    await tester.pump(const Duration(milliseconds: 700));

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

  testWidgets('learns the host repeat delay from a held key', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime(2026, 10, 3);
    KeyboardControls.clock = () => now;
    KeyboardControls.hostRepeatDelay = const Duration(milliseconds: 500);
    addTearDown(() {
      KeyboardControls.clock = DateTime.now;
      KeyboardControls.hostRepeatDelay = const Duration(milliseconds: 500);
    });
    Future<void> advance(int ms) async {
      now = now.add(Duration(milliseconds: ms));
      await tester.pump(Duration(milliseconds: ms));
    }

    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
    await advance(50);
    final game =
        (tester.state(find.byType(GameScreen)) as dynamic).game as BlastGame;
    game.skipIntro();

    // A host with a short (300 ms) repeat delay: pair, 300 ms, then pairs
    // every 33 ms. The second repeat confirms the delay.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await advance(300);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await advance(33);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(KeyboardControls.hostRepeatDelay.inMilliseconds, 300);
    await advance(33);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(game.input.held, Direction.left);
    await advance(200);
    expect(game.input.held, Direction.none);
    await advance(1200);

    // A lone tap now walks only through the shorter delay.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await advance(300);
    expect(game.input.held, Direction.right);
    await advance(100);
    expect(game.input.held, Direction.none);
    await advance(1200);

    // A long (900 ms) delay pauses once, then is learned too.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await advance(500);
    expect(game.input.held, Direction.none);
    await advance(400);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await advance(33);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(KeyboardControls.hostRepeatDelay.inMilliseconds, 900);
    await advance(200);

    // Two human taps 400 ms apart are not a repeat burst: nothing learned.
    await advance(1200);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await advance(400);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await advance(400);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(KeyboardControls.hostRepeatDelay.inMilliseconds, 900);
    await advance(1200);
  });
}
