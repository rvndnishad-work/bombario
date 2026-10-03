import 'package:bombario/admin/admin_screen.dart';
import 'package:bombario/admin/stage_info.dart';
import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario/ui/settings_screen.dart';
import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stage info matches what the solo game builds', () {
    for (var i = 0; i < core.Campaign.stages.length; i++) {
      final info = StageInfo.of(i, seed: 7);
      final def = core.Campaign.stages[i];
      final game = def.level(seed: 7 + i, players: 1);
      expect(info.width, game.grid.width);
      expect(info.height, game.grid.height);
      expect(info.milestone, (i + 1) % 5 == 0);
      if (!def.isBoss && !def.bonus) {
        expect(
          info.hidden.map((h) => h.$2),
          contains(core.ItemType.exit),
          reason: def.id,
        );
      }
    }
  });

  testWidgets('five taps on the Settings title open the admin viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('settings-title')));
    }
    await tester.pumpAndSettle();
    expect(find.byType(AdminScreen), findsNothing);
    await tester.tap(find.byKey(const Key('settings-title')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminScreen), findsOneWidget);
  });

  testWidgets('admin plays any stage with cheats that can be flipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(const MaterialApp(home: AdminScreen(seed: 3)));

    await tester.tap(find.byKey(const Key('admin-milestones')));
    await tester.pump();
    expect(find.byKey(const Key('admin-stage-1')), findsNothing);
    await tester.tap(find.byKey(const Key('admin-stage-10')));
    await tester.pump();
    expect(find.textContaining('Stage 10 (1-10)'), findsOneWidget);
    expect(find.textContaining('EXTRA: MINI-BOSS'), findsOneWidget);
    expect(StageInfo.of(9, seed: 3).miniBoss, isNotNull);
    expect(StageInfo.of(4, seed: 3).chest, isNotNull);

    await tester.tap(find.byKey(const Key('admin-stage-15')));
    await tester.pump();
    final info = StageInfo.of(14, seed: 3);
    expect(
      find.textContaining('Map ${info.width} x ${info.height} tiles'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('admin-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final state = tester.state(find.byType(GameScreen));
    final game = (state as dynamic).game as BlastGame;
    expect(game.stage.id, '2-5');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.player.godMode, isTrue);
    expect(find.byKey(const Key('admin-size')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-enemies')));
    await tester.tap(find.byKey(const Key('admin-walls')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.sim.enemies, isEmpty);
    expect(game.player.noClip, isTrue);

    await tester.tap(find.byKey(const Key('admin-next')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.stage.id, '2-6');
    expect(find.text('STAGE 16  2-6'), findsOneWidget);
  });
}
