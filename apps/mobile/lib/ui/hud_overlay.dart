import 'package:flutter/material.dart';

import '../game/blast_game.dart';

/// Top bar: lives, timer, stage, stats. Mirrors the NES `TIME / score / LEFT`
/// strip with the stats the design doc adds.
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});

  final BlastGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ListenableBuilder(
          listenable: game.hud,
          builder: (context, _) {
            final h = game.hud;
            final minutes = h.timeLeft ~/ 60;
            final seconds = (h.timeLeft % 60).toString().padLeft(2, '0');
            return Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Stat('♥', '${h.lives}'),
                    _Stat(
                      '⏱',
                      '$minutes:$seconds',
                      color: h.timeLeft <= 30 ? Colors.redAccent : null,
                    ),
                    _Stat('STAGE', h.stage),
                    _Stat('💣', '${h.bombs}'),
                    _Stat('🔥', '${h.fire}'),
                    _Stat('👾', '${h.enemiesLeft}'),
                    _Stat('SCORE', '${h.score}'),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
