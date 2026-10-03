import 'dart:math';

import 'package:flutter/material.dart';

import 'package:bombario_core/bombario_core.dart' as core;

import '../net/online.dart';
import '../progress/achievements.dart';
import '../progress/cosmetics.dart';
import '../settings/settings.dart';
import 'achievements_screen.dart';
import 'daily_screen.dart';
import 'game_screen.dart';
import 'join_screen.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';
import 'lobby_screen.dart';
import 'locker_screen.dart';
import 'online_screen.dart';
import 'player_name.dart';
import 'settings_screen.dart';

/// Home: a top bar with the profile and menus, the ways to play on the
/// left (Start first, the main thing to tap), and today's challenge and
/// progress on the right. Everything sits on one grid so tile edges line up.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const double _gap = 12;

  void _go(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final achievements = AchievementsScope.of(context);
    final skin = Cosmetics.equipped(Settings.of(context).skin, achievements);
    final daily = core.DailyDungeon.today();
    final dailyBest = achievements.dailyBest(daily.id);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar: title, profile, menus.
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Text('Bombario', style: Px.title(18, color: Px.fuse)),
                    const Spacer(),
                    GestureDetector(
                      key: const Key('profile-locker'),
                      onTap: () => _go(context, const LockerScreen()),
                      child: PlayerPreview(skin: skin, size: 40),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(width: 190, child: PlayerNameField()),
                    const SizedBox(width: _gap),
                    _IconTile(
                      key: const Key('locker'),
                      sprite: 'crown',
                      label: 'Locker',
                      onTap: () => _go(context, const LockerScreen()),
                    ),
                    const SizedBox(width: 8),
                    _IconTile(
                      key: const Key('awards'),
                      sprite: 'star',
                      label: 'Awards',
                      onTap: () => _go(context, const AchievementsScreen()),
                    ),
                    const SizedBox(width: 8),
                    _IconTile(
                      key: const Key('settings'),
                      sprite: 'gear',
                      label: 'Settings',
                      onTap: () => _go(context, const SettingsScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _gap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ways to play.
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _PlayTile(
                              key: const Key('start'),
                              sprite: 'play',
                              title: 'Start',
                              subtitle: 'Solo campaign',
                              color: Px.ok,
                              big: true,
                              onTap: () => _go(
                                context,
                                GameScreen(seed: Random().nextInt(1 << 30)),
                              ),
                            ),
                          ),
                          const SizedBox(height: _gap),
                          Expanded(
                            flex: 4,
                            child: _PlayTile(
                              sprite: 'bomb',
                              title: 'Online',
                              subtitle: 'Quick match, or a room with friends',
                              color: Px.fuse,
                              onTap: () => _go(context, const OnlineScreen()),
                            ),
                          ),
                          const SizedBox(height: _gap),
                          Expanded(
                            flex: 4,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _PlayTile(
                                    sprite: 'wifi',
                                    title: 'Host Wi-Fi room',
                                    color: Px.blast,
                                    onTap: () =>
                                        _go(context, const LobbyScreen.host()),
                                  ),
                                ),
                                const SizedBox(width: _gap),
                                Expanded(
                                  child: _PlayTile(
                                    sprite: 'p2',
                                    title: 'Join Wi-Fi room',
                                    color: Px.panel,
                                    dark: true,
                                    onTap: () =>
                                        _go(context, const JoinScreen()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: _gap),
                    // Today's challenge and progress.
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const Key('daily'),
                              onTap: () => _go(context, const DailyScreen()),
                              child: _InfoCard(
                                sprite: 'cal',
                                heading: 'Daily dungeon',
                                headingColor: Px.fuse,
                                border: Px.fuse,
                                line1: daily.stage.name,
                                line2: dailyBest == null
                                    ? 'Race the world. Tap to play'
                                    : 'Best ${formatTime(dailyBest)}',
                              ),
                            ),
                          ),
                          const SizedBox(height: _gap),
                          Expanded(
                            child: _InfoCard(
                              sprite: 'flag',
                              heading: 'Progress',
                              headingColor: Px.muted,
                              border: Px.edge,
                              line1:
                                  '${achievements.stat(Achievements.stagesCleared)} '
                                  'stages cleared',
                              line2:
                                  '${achievements.unlocked.length} of '
                                  '${Achievements.all.length} awards',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A way to play: a coloured tile filling its grid cell.
class _PlayTile extends StatelessWidget {
  const _PlayTile({
    super.key,
    required this.sprite,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.big = false,
    this.dark = false,
  });

  final String sprite;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool big;

  /// Light text on a dark tile instead of dark text on a bright one.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Px.paper : Px.night;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: PxPanel(
          color: color,
          border: dark ? Px.edge : Color.lerp(color, Colors.white, 0.4)!,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SpriteIcon(sprite, size: big ? 52 : 34),
              SizedBox(width: big ? 18 : 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: big
                            ? Px.title(26, color: ink)
                            : Px.label(18, color: ink),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Px.label(12, color: ink, bold: false),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square menu button for the top bar.
class _IconTile extends StatelessWidget {
  const _IconTile({
    super.key,
    required this.sprite,
    required this.label,
    required this.onTap,
  });

  final String sprite;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Px.panel,
            border: Border.all(color: Px.edge, width: 3),
          ),
          child: SpriteIcon(sprite, size: 28),
        ),
      ),
    ),
  );
}

/// A status card in the right column.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.sprite,
    required this.heading,
    required this.headingColor,
    required this.border,
    required this.line1,
    required this.line2,
  });

  final String sprite;
  final String heading;
  final Color headingColor;
  final Color border;
  final String line1;
  final String line2;

  @override
  Widget build(BuildContext context) => PxPanel(
    border: border,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SpriteIcon(sprite, size: 22),
                const SizedBox(width: 8),
                Text(
                  heading.toUpperCase(),
                  style: Px.label(12, color: headingColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(line1, style: Px.label(15)),
            const SizedBox(height: 4),
            Text(line2, style: Px.label(12, color: Px.ok, bold: false)),
          ],
        ),
      ),
    ),
  );
}
