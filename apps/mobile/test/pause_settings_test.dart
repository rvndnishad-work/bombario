import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/settings/settings.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Settings opens from the pause card and applies on return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    final settings = AppSettings.memory();
    await tester.pumpWidget(
      Settings(
        settings: settings,
        child: const MaterialApp(home: GameScreen(seed: 3)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final game =
        (tester.state(find.byType(GameScreen)) as dynamic).game as BlastGame;
    game.skipIntro();
    await tester.pump();
    expect(find.byKey(const Key('joystick-area')), findsOneWidget);

    game.pause();
    await tester.pump();
    await tester.tap(find.byKey(const Key('pause-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('joystick')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('joystick')));
    await tester.pump();
    expect(settings.joystick, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Back on the same pause card, with the arrow pad already in place.
    expect(find.byType(SettingsScreen), findsNothing);
    expect(game.overlays.isActive(Overlays.pause), isTrue);
    expect(find.byKey(const Key('dpad-area')), findsOneWidget);
    expect(find.byKey(const Key('joystick-area')), findsNothing);
    final frozenAt = game.sim.elapsed;
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.sim.elapsed, frozenAt);

    await tester.tap(find.byKey(const Key('resume')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.overlays.isActive(Overlays.pause), isFalse);
    expect(game.sim.elapsed, greaterThan(frozenAt));
  });
}
