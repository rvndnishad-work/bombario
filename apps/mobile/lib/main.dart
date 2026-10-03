import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/sprite_atlas.dart';
import 'progress/achievements.dart';
import 'settings/settings.dart';
import 'ui/home_screen.dart';
import 'ui/kit/pixel_theme.dart';

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
