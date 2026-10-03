import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/follow_camera.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/settings/settings.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keyboard', () {
    testWidgets('the solo game moves the bomber with the arrow keys', (
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
      final startX = game.player.x;
      final startY = game.player.y;
      // Spawn is the top-left corner: one of right or down is open.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(
        (game.player.x - startX).abs() + (game.player.y - startY).abs(),
        greaterThan(0.2),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.sim.bombs, isNotEmpty);
    });
  });

  group('camera', () {
    test('the board covers the screen; rows fit like the original', () {
      final view = Vector2(1600, 800);
      // A narrow maze is zoomed until it fills the width.
      expect(
        FollowCamera.zoomFor(view, 15, 11, 32),
        closeTo(1600 / (15 * 32), 1e-9),
      );
      expect(
        FollowCamera.zoomFor(view, 31, 13, 32),
        closeTo(800 / (13 * 32), 1e-9),
      );
      expect(
        FollowCamera.zoomFor(view, 41, 17, 32),
        closeTo(800 / (17 * 32), 1e-9),
      );
      // A portrait screen still shows enough columns.
      expect(
        FollowCamera.zoomFor(Vector2(400, 900), 31, 13, 32),
        closeTo(400 / (9 * 32), 1e-9),
      );
    });

    test('follows with a dead zone and stops at the maze walls', () {
      final cam = FollowCamera();
      final view = Vector2(800, 400);
      const zoom = 1.0; // 800x400 world units visible: half = 400 x 200
      Vector2 at(double x, double y, {double dt = 1 / 60}) => cam.follow(
        view: view,
        zoom: zoom,
        targetX: x,
        targetY: y,
        mazeW: 800,
        mazeH: 1000,
        tileSize: 32,
        dt: dt,
      );
      // Starts clamped: maze is exactly as wide as the view, so x centres.
      final first = at(48, 48);
      expect(first.x, 400);
      expect(first.y, 200);
      // A small step inside the dead zone doesn't move the camera.
      expect(at(48, 70).y, 200);
      // Walking far down scrolls, and settles at the bottom wall.
      for (var i = 0; i < 600; i++) {
        at(48, 980);
      }
      expect(at(48, 980).y, closeTo(800, 1e-6));
    });
  });

  test('screen shake is reduced unless the player turns it back on', () {
    final s = AppSettings.memory();
    expect(s.reduceShake, isTrue);
    expect(s.shake, 0);
  });
}
