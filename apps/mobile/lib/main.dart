import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/game_audio.dart';
import 'game/sprite_atlas.dart';
import 'net/analytics.dart';
import 'progress/achievements.dart';
import 'settings/settings.dart';
import 'ui/home_screen.dart';
import 'ui/kit/pixel_theme.dart';
import 'ui/player_name.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape only: the maze is wider than tall and thumbs sit on both sides.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final (settings, achievements, _) = await (
    AppSettings.load(),
    Achievements.load(),
    SpriteAtlas.load(),
  ).wait;
  final audio = GameAudio.instance;
  void applyVolumes() =>
      audio.setVolumes(music: settings.musicVolume, sfx: settings.sfxVolume);
  applyVolumes();
  settings.addListener(applyVolumes);

  final analytics = Analytics.instance..enabled = settings.shareAnalytics;
  settings.addListener(() => analytics.setEnabled(settings.shareAnalytics));
  analytics.start(installId: settings.installId);
  AppLifecycleListener(onPause: analytics.flush);

  // The name shown in rooms and on leaderboards survives restarts.
  if (settings.playerName.isNotEmpty) {
    PlayerName.value.value = settings.playerName;
  }
  PlayerName.value.addListener(
    () => settings.update((s) => s.playerName = PlayerName.value.value),
  );
  unawaited(audio.preload().then((_) => audio.playMusic(0)));
  runApp(BombarioApp(settings: settings, achievements: achievements));
}

class BombarioApp extends StatelessWidget {
  const BombarioApp({super.key, this.settings, this.achievements});

  final AppSettings? settings;
  final Achievements? achievements;

  @override
  Widget build(BuildContext context) {
    return Settings(
      settings: settings ?? AppSettings.memory(),
      child: AchievementsScope(
        achievements: achievements ?? Achievements.memory(),
        child: MaterialApp(
          title: 'Bombario',
          debugShowCheckedModeBanner: false,
          theme: Px.theme(),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
