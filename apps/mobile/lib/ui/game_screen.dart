import 'dart:async';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../admin/admin_cheats.dart';
import '../admin/admin_panel.dart';
import '../ads/rewarded_ads.dart';
import '../game/blast_game.dart';
import '../net/online.dart';
import '../audio/game_audio.dart';
import '../progress/achievements.dart';
import '../settings/settings.dart';
import 'controls_overlay.dart';
import 'keyboard_controls.dart';
import 'kit/game_chrome.dart';
import 'kit/pixel_theme.dart';

/// Solo campaign, or the Daily Dungeon when [daily] is set: the toolbar on
/// top, the board everywhere else, controls and popups over the board.
///
/// A cleared daily pops with its time in milliseconds.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.seed = 1,
    this.daily,
    this.admin,
    this.startStage = 0,
  });

  final int seed;
  final core.DailyDungeon? daily;

  /// Set when launched from the admin stage viewer.
  final AdminCheats? admin;

  /// Index into [core.Campaign.stages] to start on.
  final int startStage;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final BlastGame _game = BlastGame(
    seed: widget.seed,
    daily: widget.daily,
    admin: widget.admin,
    startStage: widget.startStage,
    settings: Settings.read(context),
    achievements: AchievementsScope.read(context),
  );

  @visibleForTesting
  BlastGame get game => _game;

  @override
  void dispose() {
    // Leaving mid-jingle must not carry it onto the menu loop.
    GameAudio.instance
      ..stopAllOneShots()
      ..playMusic(0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Settings.of(context);
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            GameToolbar(hud: _game.hud, onPause: _game.pause),
            Expanded(
              child: KeyboardControls(
                input: _game.input,
                onPause: _game.pause,
                child: Stack(
                  children: [
                    // The camera can draw past the board's edges (a tall
                    // maze scrolls vertically); clip it so it never paints
                    // over the toolbar or outside the menus' dimming.
                    ClipRect(
                      child: GameWidget(
                        game: _game,
                        // Keys go to KeyboardControls; a focused GameWidget
                        // would swallow them.
                        autofocus: false,
                        overlayBuilderMap: {
                          Overlays.controls: (context, BlastGame game) =>
                              ControlsOverlay(
                                input: game.input,
                                actionLabel: game.actionLabel,
                                opacity: settings.controlsOpacity,
                                scale: settings.controlsScale,
                                leftHanded: settings.leftHanded,
                                haptics: settings.haptics,
                              ),
                          Overlays.pause: (context, BlastGame game) => MenuCard(
                            title: 'Paused',
                            subtitle: game.daily != null
                                ? 'Daily Dungeon: ${game.stage.name}'
                                : 'Stage ${game.stage.id}: ${game.stage.name}',
                            actions: [
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Quit'),
                              ),
                              FilledButton(
                                key: const Key('resume'),
                                onPressed: game.resume,
                                child: const Text('Resume'),
                              ),
                            ],
                          ),
                          Overlays.stageCleared: (context, BlastGame game) =>
                              game.daily != null
                              ? MenuCard(
                                  border: const Color(0xFF3FC062),
                                  title: 'Daily cleared!',
                                  subtitle:
                                      'Time ${formatTime(game.stageTimeMs)}. '
                                      'Score ${game.player.score}',
                                  actions: [
                                    FilledButton(
                                      key: const Key('daily-done'),
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pop(game.stageTimeMs),
                                      child: const Text('Submit time'),
                                    ),
                                  ],
                                )
                              : MenuCard(
                                  border: const Color(0xFF3FC062),
                                  title: game.isLastStage
                                      ? 'Campaign complete!'
                                      : 'Stage ${game.stage.id} cleared!',
                                  subtitle:
                                      (game.isLastStage
                                          ? 'Score ${game.player.score}'
                                          : 'Score ${game.player.score}. Next up: '
                                                '${core.Campaign.stages[game.stageIndex + 1].name}') +
                                      (game.livesForPoints > 0
                                          ? '\n+${game.livesForPoints} '
                                                '${game.livesForPoints == 1 ? 'life' : 'lives'} '
                                                'for your points!'
                                          : ''),
                                  actions: [
                                    FilledButton(
                                      onPressed: game.nextStage,
                                      child: Text(
                                        game.isLastStage
                                            ? 'Play again'
                                            : 'Next stage',
                                      ),
                                    ),
                                  ],
                                ),
                          Overlays
                              .gameOver: (context, BlastGame game) => MenuCard(
                            border: const Color(0xFFFF4B4B),
                            title: 'Game over',
                            subtitle: game.daily != null
                                ? 'Out of lives. Try the dungeon again?'
                                : 'Reached stage ${game.stage.id} with '
                                      '${game.player.score} points'
                                      '${game.adLivesSpent && RewardedAds.instance.supported ? '\nNo ad lives left. Start again from 1-1.' : ''}',
                            actions: [
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Home'),
                              ),
                              if (game.canContinue &&
                                  RewardedAds.instance.supported)
                                ExtraLifeButton(game: game),
                              FilledButton(
                                onPressed: game.restart,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        },
                      ),
                    ),
                    MessagePopups(messages: _game.messages),
                    StageIntroCard(intro: _game.intro, onSkip: _game.skipIntro),
                    if (widget.admin case final admin?)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AdminPanel(game: _game, cheats: admin),
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

/// "Watch an ad for an extra life" on the game-over card: plays a rewarded
/// ad and, once it has been watched, puts the player back in the stage.
class ExtraLifeButton extends StatefulWidget {
  const ExtraLifeButton({super.key, required this.game});

  final BlastGame game;

  @override
  State<ExtraLifeButton> createState() => _ExtraLifeButtonState();
}

class _ExtraLifeButtonState extends State<ExtraLifeButton> {
  /// How long the button stays disarmed after the card appears, so a tap
  /// still landing from play (the bomb button) never starts an ad.
  static const armDelay = Duration(milliseconds: 1200);

  bool _busy = false;
  bool _armed = false;
  String? _note;
  Timer? _arm;

  @override
  void initState() {
    super.initState();
    _arm = Timer(armDelay, () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _arm?.cancel();
    super.dispose();
  }

  Future<void> _watch() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    GameAudio.instance.pauseMusic();
    final rewarded = await RewardedAds.instance.showForReward();
    // The card may have been rebuilt while the ad covered the app (the
    // activity can rotate or resize), so the reward goes to the game
    // whether or not this button is still mounted.
    if (rewarded) {
      widget.game.continueWithExtraLife();
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = 'No ad right now. Try again in a moment.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          key: const Key('extra-life-ad'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3FC062),
          ),
          onPressed: _busy || !_armed ? null : _watch,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(_busy ? 'Loading ad...' : 'Watch ad: +1 life'),
        ),
        if (_note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: Px.label(11, color: Px.muted)),
          ),
      ],
    );
  }
}
