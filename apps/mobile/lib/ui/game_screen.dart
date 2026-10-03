import 'package:flame/game.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(
        game: _game,
        overlayBuilderMap: {
          Overlays.hud: (context, BlastGame game) => HudOverlay(game: game),
          Overlays.controls: (context, BlastGame game) =>
              ControlsOverlay(input: game.input, hasRemote: game.hasRemote),
          Overlays.stageCleared: (context, BlastGame game) => _EndCard(
            title: 'Stage ${game.stage} cleared!',
            subtitle: 'Score ${game.player.score}',
            buttonLabel: 'Next stage',
            onPressed: game.nextStage,
          ),
          Overlays.gameOver: (context, BlastGame game) => _EndCard(
            title: 'Game over',
            subtitle:
                'Reached stage ${game.stage} with ${game.player.score} points',
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
