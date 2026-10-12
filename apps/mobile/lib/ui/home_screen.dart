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
import 'kit/arena_backdrop.dart';
import 'kit/motion.dart';
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
/// The tiles drop in one after another over a drifting maze, and Start
/// pulses gently so the eye lands on it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const double _gap = 12;

  /// Stagger between tiles dropping in.
  static Duration _at(int step) => Duration(milliseconds: 60 + 70 * step);

  void _go(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final achievements = AchievementsScope.of(context);
    final skin = Cosmetics.equipped(Settings.of(context).skin, achievements);
    final daily = core.DailyDungeon.today();
    final dailyBest = achievements.dailyBest(daily.id);
    return Scaffold(
      body: ArenaBackdrop(
        child: SafeArea(
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
                      Entrance(
                        offset: const Offset(-30, 0),
                        child: Row(
                          children: [
                            const Ambient(
                              kind: AmbientKind.wobble,
                              period: Duration(milliseconds: 600),
                              child: SpriteIcon('bomb', size: 30),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Bombario',
                              style: Px.title(18, color: Px.fuse),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Pressable(
                        key: const Key('profile-locker'),
                        onTap: () => _go(context, const LockerScreen()),
                        child: Ambient(
                          child: PlayerPreview(skin: skin, size: 40),
                        ),
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
                              child: Entrance(
                                delay: _at(0),
                                child: _PlayTile(
                                  key: const Key('start'),
                                  sprite: 'play',
                                  title: 'Start',
                                  subtitle: 'Solo campaign',
                                  color: Px.ok,
                                  big: true,
                                  scene: const _ChaseScene(),
                                  onTap: () => _go(
                                    context,
                                    GameScreen(seed: Random().nextInt(1 << 30)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: _gap),
                            Expanded(
                              flex: 4,
                              child: Entrance(
                                delay: _at(1),
                                child: _PlayTile(
                                  sprite: 'bomb',
                                  title: 'Online',
                                  subtitle:
                                      'Quick match, or a room with friends',
                                  color: Px.fuse,
                                  scene: const _Crowd(),
                                  onTap: () =>
                                      _go(context, const OnlineScreen()),
                                ),
                              ),
                            ),
                            const SizedBox(height: _gap),
                            Expanded(
                              flex: 4,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Entrance(
                                      delay: _at(2),
                                      child: _PlayTile(
                                        sprite: 'wifi',
                                        title: 'Host Wi-Fi room',
                                        color: Px.blast,
                                        onTap: () => _go(
                                          context,
                                          const LobbyScreen.host(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: _gap),
                                  Expanded(
                                    child: Entrance(
                                      delay: _at(3),
                                      child: _PlayTile(
                                        sprite: 'p2',
                                        title: 'Join Wi-Fi room',
                                        color: Px.panel,
                                        dark: true,
                                        onTap: () =>
                                            _go(context, const JoinScreen()),
                                      ),
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
                              child: Entrance(
                                delay: _at(2),
                                offset: const Offset(30, 0),
                                child: Pressable(
                                  key: const Key('daily'),
                                  onTap: () =>
                                      _go(context, const DailyScreen()),
                                  child: _InfoCard(
                                    sprite: 'cal',
                                    heading: 'Daily dungeon',
                                    headingColor: Px.fuse,
                                    border: Px.fuse,
                                    line1: daily.stage.name,
                                    line2: dailyBest == null
                                        ? 'Race the world. Tap to play'
                                        : 'Best ${formatTime(dailyBest)}',
                                    art: 'skull',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: _gap),
                            Expanded(
                              child: Entrance(
                                delay: _at(3),
                                offset: const Offset(30, 0),
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
                                  art: 'star',
                                  progress:
                                      achievements.unlocked.length /
                                      Achievements.all.length,
                                ),
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
    this.scene,
  });

  final String sprite;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool big;

  /// Light text on a dark tile instead of dark text on a bright one.
  final bool dark;

  /// Art on the right of the tile.
  final Widget? scene;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Px.paper : Px.night;
    final icon = SpriteIcon(sprite, size: big ? 52 : 34);
    final tile = Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: PxPanel(
          bevel: true,
          color: color,
          border: dark ? Px.edge : Color.lerp(color, Colors.black, 0.45)!,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              big
                  ? Ambient(
                      period: const Duration(milliseconds: 700),
                      child: icon,
                    )
                  : icon,
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
              if (scene case final art?) art,
            ],
          ),
        ),
      ),
    );
    return big
        ? Ambient(
            kind: AmbientKind.pulse,
            period: const Duration(milliseconds: 1600),
            child: tile,
          )
        : tile;
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
      child: Pressable(
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

/// A status card in the right column, with an optional sprite on the right
/// and an optional progress bar.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.sprite,
    required this.heading,
    required this.headingColor,
    required this.border,
    required this.line1,
    required this.line2,
    this.art,
    this.progress,
  });

  final String sprite;
  final String heading;
  final Color headingColor;
  final Color border;
  final String line1;
  final String line2;

  /// A sprite drawn large on the right.
  final String? art;

  /// 0 to 1: a bar under the text.
  final double? progress;

  @override
  Widget build(BuildContext context) => PxPanel(
    bevel: true,
    border: border,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        Expanded(
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
                  if (progress case final p?) ...[
                    const SizedBox(height: 8),
                    _Bar(value: p, colour: Px.fuse),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (art case final a?)
          Ambient(
            period: const Duration(milliseconds: 1100),
            child: SpriteIcon(a, size: 48),
          ),
      ],
    ),
  );
}

/// A chunky progress bar that fills up as it appears.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.colour});

  final double value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 180,
    height: 12,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Px.ink,
      border: Border.all(color: Px.edge, width: 2),
    ),
    alignment: Alignment.centerLeft,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => FractionallySizedBox(
        widthFactor: v,
        child: ColoredBox(color: colour),
      ),
    ),
  );
}

/// The Start tile's art: the bomber running from a Puffball, a bomb
/// fizzing between them.
class _ChaseScene extends StatelessWidget {
  const _ChaseScene();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Ambient(
        phase: 0.5,
        period: Duration(milliseconds: 700),
        child: SpriteIcon('puff-side', size: 54),
      ),
      SizedBox(width: 6),
      Ambient(
        kind: AmbientKind.wobble,
        period: Duration(milliseconds: 400),
        child: SpriteIcon('bomb', size: 40),
      ),
      SizedBox(width: 10),
      Ambient(
        period: Duration(milliseconds: 500),
        child: SpriteIcon('p1-side-walk-a', size: 64),
      ),
    ],
  );
}

/// The Online tile's art: four bombers bobbing out of step.
class _Crowd extends StatelessWidget {
  const _Crowd();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 4; i++)
        Ambient(
          phase: i / 4,
          period: const Duration(milliseconds: 800),
          child: SpriteIcon('p$i', size: 40),
        ),
    ],
  );
}
