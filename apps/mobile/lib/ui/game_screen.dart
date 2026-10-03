import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/blast_game.dart';
import 'controls_overlay.dart';
import 'hud_overlay.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.seed = 1});

  final int seed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final BlastGame _game = BlastGame(seed: widget.seed);

  @visibleForTesting
  BlastGame get game => _game;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(
        game: _game,
        overlayBuilderMap: {
          Overlays.hud: (context, BlastGame game) => HudOverlay(game: game),
          Overlays.controls: (context, BlastGame game) => Stack(
            children: [
              ControlsOverlay(input: game.input, actionLabel: game.actionLabel),
              _Banner(text: game.banner),
            ],
          ),
          Overlays.stageCleared: (context, BlastGame game) => _EndCard(
            title: game.isLastStage
                ? 'Campaign complete!'
                : 'Stage ${game.stage.id} cleared!',
            subtitle: game.isLastStage
                ? 'Score ${game.player.score}'
                : 'Score ${game.player.score}. Next up: '
                      '${core.Campaign.stages[game.stageIndex + 1].name}',
            buttonLabel: game.isLastStage ? 'Play again' : 'Next stage',
            onPressed: game.nextStage,
          ),
          Overlays.gameOver: (context, BlastGame game) => _EndCard(
            title: 'Game over',
            subtitle:
                'Reached stage ${game.stage.id} with '
                '${game.player.score} points',
            buttonLabel: 'Try again',
            onPressed: game.restart,
            secondaryLabel: 'Home',
            onSecondary: () => Navigator.of(context).pop(),
          ),
        },
      ),
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        color: Colors.black87,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (secondaryLabel != null) ...[
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                    const SizedBox(width: 12),
                  ],
                  FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The stage name and tip, shown for the first few seconds.
class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final ValueListenable<String?> text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<String?>(
        valueListenable: text,
        builder: (context, value, _) => AnimatedOpacity(
          opacity: value == null ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: Align(
            alignment: const Alignment(0, -0.45),
            child: value == null
                ? const SizedBox.shrink()
                : Card(
                    color: Colors.black87,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      child: Text(
                        value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
