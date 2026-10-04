import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account/account.dart';
import 'account/firebase_accounts.dart';
import 'ads/rewarded_ads.dart';
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
  final (settings, achievements, _, accounts) = await (
    AppSettings.load(),
    Achievements.load(),
    SpriteAtlas.load(),
    FirebaseAccounts.start(),
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
  // Guest by default; a signed-in player's progress syncs in the background.
  final account = accounts == null
      ? Account.offline(settings: settings, achievements: achievements)
      : Account(
          backend: accounts,
          settings: settings,
          achievements: achievements,
        );
  unawaited(account.start());
  unawaited(audio.preload().then((_) => audio.playMusic(0)));
  // Loads the first "extra life" ad in the background.
  unawaited(RewardedAds.instance.start());
  runApp(
    BombarioApp(
      settings: settings,
      achievements: achievements,
      account: account,
    ),
  );
}

class BombarioApp extends StatelessWidget {
  const BombarioApp({
    super.key,
    this.settings,
    this.achievements,
    this.account,
  });

  final AppSettings? settings;
  final Achievements? achievements;

  /// Null in tests: Settings then shows sign-in as not set up.
  final Account? account;

  @override
  Widget build(BuildContext context) {
    return Settings(
      settings: settings ?? AppSettings.memory(),
      child: AchievementsScope(
        achievements: achievements ?? Achievements.memory(),
        child: _withAccount(
          MaterialApp(
            title: 'Bombario',
            debugShowCheckedModeBanner: false,
            theme: Px.theme(),
            home: const HomeScreen(),
          ),
        ),
      ),
    );
  }

  Widget _withAccount(Widget child) {
    final a = account;
    return a == null ? child : AccountScope(account: a, child: child);
  }
}
