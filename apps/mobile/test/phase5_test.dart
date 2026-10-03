import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/main.dart';
import 'package:bombario/net/analytics.dart';
import 'package:bombario/net/online.dart';
import 'package:bombario/progress/achievements.dart';
import 'package:bombario/progress/cosmetics.dart';
import 'package:bombario/settings/settings.dart';
import 'package:bombario/ui/daily_screen.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario/ui/locker_screen.dart';
import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _landscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the daily dungeon plays its own stage and returns the time', (
    tester,
  ) async {
    _landscape(tester);
    await tester.runAsync(SpriteAtlas.load);
    final daily = core.DailyDungeon.forDate(DateTime.utc(2026, 10, 3));
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<int>(
                MaterialPageRoute(builder: (_) => GameScreen(daily: daily)),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final game =
        (tester.state(find.byType(GameScreen)) as dynamic).game as BlastGame;
    game.skipIntro();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.stage.id, 'daily-2026-10-03');
    expect(game.sim.level.name, contains(daily.stage.name));
    expect(game.stageTimeMs, greaterThan(500));
    expect(game.isLastStage, isTrue);

    game.overlays.add(Overlays.stageCleared);
    await tester.pump();
    expect(find.text('Daily cleared!'), findsOneWidget);
    final time = game.stageTimeMs;
    await tester.tap(find.byKey(const Key('daily-done')));
    await tester.pumpAndSettle();
    expect(result, time);
  });

  test('daily records keep the best time per day', () {
    final a = Achievements.memory();
    expect(a.dailyBest('2026-10-03'), isNull);
    expect(a.recordDaily('2026-10-03', 90000), isTrue);
    expect(a.recordDaily('2026-10-03', 95000), isFalse);
    expect(a.recordDaily('2026-10-03', 80000), isTrue);
    expect(a.dailyBest('2026-10-03'), 80000);
    expect(a.dailyBest('2026-10-04'), isNull);
  });

  testWidgets('daily screen shows the dungeon and copes with no server', (
    tester,
  ) async {
    _landscape(tester);
    await tester.runAsync(SpriteAtlas.load);
    await tester.pumpWidget(
      MaterialApp(home: DailyScreen(now: DateTime.utc(2026, 10, 3, 20))),
    );
    final daily = core.DailyDungeon.forDate(DateTime.utc(2026, 10, 3));
    expect(find.text(daily.stage.name), findsOneWidget);
    expect(find.text('New dungeon in 4h 00m'), findsOneWidget);
    // The test binding answers every HTTP call with 400.
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump();
    expect(find.textContaining('Leaderboard offline'), findsOneWidget);
  });

  testWidgets('locker equips unlocked hats and refuses locked ones', (
    tester,
  ) async {
    _landscape(tester);
    await tester.runAsync(SpriteAtlas.load);
    final settings = AppSettings.memory();
    final achievements = Achievements.memory()..unlocked.add('world-1');
    await tester.pumpWidget(
      BombarioApp(settings: settings, achievements: achievements),
    );
    await tester.tap(find.byKey(const Key('locker')));
    await tester.pumpAndSettle();
    expect(find.byType(LockerScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('skin-sprout')));
    await tester.pump();
    expect(settings.skin, 'sprout');

    await tester.tap(find.byKey(const Key('skin-crown')));
    await tester.pump();
    expect(settings.skin, 'sprout');
    expect(find.text('Unlock: Last one standing'), findsOneWidget);
  });

  test('cosmetics fall back to classic for locked or unknown hats', () {
    final a = Achievements.memory();
    expect(Cosmetics.equipped('crown', a), 'classic');
    expect(Cosmetics.equipped('cap', a), 'cap');
    expect(Cosmetics.spriteFor('classic'), isNull);
    expect(Cosmetics.spriteFor('cap'), 'hat-cap');
    expect(Cosmetics.spriteFor('jetpack'), isNull);
  });

  test('every hat has a sprite in the atlas', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SpriteAtlas.load();
    for (final s in Cosmetics.skins) {
      final sprite = s.sprite;
      if (sprite != null) expect(SpriteAtlas.has(sprite), isTrue, reason: s.id);
    }
  });

  test('analytics batches, retries failures and respects the switch', () async {
    final a = Analytics.instance;
    final sent = <List<Map<String, Object?>>>[];
    var up = false;
    a.sender = (events) async {
      if (!up) return false;
      sent.add(events);
      return true;
    };
    a
      ..setEnabled(false) // drops events earlier tests queued
      ..setEnabled(true)
      ..start(installId: 'abc');
    a.log('stage_clear', {'stage': '1-1'});
    expect(a.pending, hasLength(2));
    expect((a.pending.last['props'] as Map)['install'], 'abc');

    await a.flush();
    expect(a.pending, hasLength(2), reason: 'kept after a failed upload');
    up = true;
    await a.flush();
    expect(a.pending, isEmpty);
    expect(sent.single.map((e) => e['name']), ['app_open', 'stage_clear']);

    a.setEnabled(false);
    a.log('ignored');
    expect(a.pending, isEmpty);
    a.setEnabled(true);
  });

  test('times format as minutes, seconds and tenths', () {
    expect(formatTime(83450), '1:23.4');
    expect(formatTime(5000), '0:05.0');
  });
}
