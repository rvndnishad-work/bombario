import 'dart:math';

import 'package:flutter/material.dart';

import '../progress/achievements.dart';
import 'achievements_screen.dart';
import 'game_screen.dart';
import 'join_screen.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';
import 'lobby_screen.dart';
import 'online_screen.dart';
import 'player_name.dart';
import 'settings_screen.dart';

/// Home (mockup board 02): profile and menus on the left, the ways to play
/// in the middle, progress on the right.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _go(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final achievements = AchievementsScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Left rail: title, profile, menus.
            Container(
              width: 250,
              color: Px.ink,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bombario', style: Px.title(15, color: Px.fuse)),
                  const SizedBox(height: 14),
                  PxPanel(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const SpriteIcon('p1', size: 44),
                        const SizedBox(width: 10),
                        const Expanded(child: PlayerNameField()),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: _SmallTile(
                          sprite: 'star',
                          label: 'Awards',
                          onTap: () => _go(context, const AchievementsScreen()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SmallTile(
                          key: const Key('settings'),
                          sprite: 'wall',
                          label: 'Settings',
                          onTap: () => _go(context, const SettingsScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Middle: ways to play.
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BigTile(
                          sprite: 'bomb',
                          title: 'Online',
                          subtitle: 'Create a room or join with a code',
                          color: Px.fuse,
                          onTap: () => _go(context, const OnlineScreen()),
                        ),
                        const SizedBox(height: 10),
                        _BigTile(
                          sprite: 'swords',
                          title: 'Host Wi-Fi room',
                          subtitle: 'Friends on the same Wi-Fi or hotspot',
                          color: Px.blast,
                          onTap: () => _go(context, const LobbyScreen.host()),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SmallTile(
                                sprite: 'flag',
                                label: 'Solo',
                                wide: true,
                                onTap: () => _go(
                                  context,
                                  GameScreen(seed: Random().nextInt(1 << 30)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SmallTile(
                                sprite: 'p2',
                                label: 'Join Wi-Fi room',
                                wide: true,
                                onTap: () => _go(context, const JoinScreen()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Right: progress.
            SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PxPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PROGRESS',
                            style: Px.label(11, color: Px.muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${achievements.stat(Achievements.stagesCleared)} '
                            'stages cleared',
                            style: Px.label(14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${achievements.unlocked.length} of '
                            '${Achievements.all.length} awards',
                            style: Px.label(12, color: Px.ok, bold: false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.sprite,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String sprite;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: PxPanel(
        color: color,
        border: Color.lerp(color, Colors.white, 0.4)!,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            SpriteIcon(sprite, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Px.label(20, color: Px.night)),
                  Text(
                    subtitle,
                    style: Px.label(12, color: Px.night, bold: false),
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

class _SmallTile extends StatelessWidget {
  const _SmallTile({
    super.key,
    required this.sprite,
    required this.label,
    required this.onTap,
    this.wide = false,
  });

  final String sprite;
  final String label;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: PxPanel(
        color: Px.panel,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: wide ? 14 : 10),
        child: wide
            ? Row(
                children: [
                  SpriteIcon(sprite, size: 26),
                  const SizedBox(width: 10),
                  Flexible(child: Text(label, style: Px.label(15))),
                ],
              )
            : Column(
                children: [
                  SpriteIcon(sprite, size: 26),
                  const SizedBox(height: 4),
                  Text(label, style: Px.label(12)),
                ],
              ),
      ),
    ),
  );
}
