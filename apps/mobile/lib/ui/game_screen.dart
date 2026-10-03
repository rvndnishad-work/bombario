import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/blast_game.dart';
import '../audio/game_audio.dart';
import '../progress/achievements.dart';
import '../settings/settings.dart';
import 'controls_overlay.dart';
import 'kit/game_chrome.dart';

/// Solo campaign: the toolbar on top, the board everywhere else, controls
/// and popups over the board.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.seed = 1});

  final int seed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final BlastGame _game = BlastGame(
    seed: widget.seed,
    settings: Settings.read(context),
    achievements: AchievementsScope.read(context),
  );

  @visibleForTesting
  BlastGame get game => _game;

  @override
  void dispose() {
    GameAudio.instance.playMusic(0);
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
              child: Stack(
                children: [
                  GameWidget(
                    game: _game,
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
                        subtitle: 'Stage ${game.stage.id}: ${game.stage.name}',
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
                      Overlays
                          .stageCleared: (context, BlastGame game) => MenuCard(
                        border: const Color(0xFF3FC062),
                        title: game.isLastStage
                            ? 'Campaign complete!'
                            : 'Stage ${game.stage.id} cleared!',
                        subtitle: game.isLastStage
                            ? 'Score ${game.player.score}'
                            : 'Score ${game.player.score}. Next up: '
                                  '${core.Campaign.stages[game.stageIndex + 1].name}',
                        actions: [
                          FilledButton(
                            onPressed: game.nextStage,
                            child: Text(
                              game.isLastStage ? 'Play again' : 'Next stage',
                            ),
                          ),
                        ],
                      ),
                      Overlays.gameOver: (context, BlastGame game) => MenuCard(
                        border: const Color(0xFFFF4B4B),
                        title: 'Game over',
                        subtitle:
                            'Reached stage ${game.stage.id} with '
                            '${game.player.score} points',
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Home'),
                          ),
                          FilledButton(
                            onPressed: game.restart,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    },
                  ),
                  MessagePopups(messages: _game.messages),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
