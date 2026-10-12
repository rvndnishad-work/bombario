import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/main.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(1280, 800), Size(1366, 1024)]) {
    testWidgets('home, online, settings and game fit at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(SpriteAtlas.load);
      await tester.pumpWidget(const BombarioApp());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: GameScreen(seed: 3)));
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
  }
}
