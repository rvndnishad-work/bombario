import 'dart:math';

import 'package:flutter/material.dart';

import 'game_screen.dart';

/// Placeholder title screen. The lobby, room codes and online modes from the
/// design doc plug in here in later phases.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💣', style: TextStyle(fontSize: 64)),
            Text('Bombario', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 4),
            const Text('Phase 0 prototype',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Solo'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GameScreen(seed: Random().nextInt(1 << 30)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const FilledButton.tonal(
                onPressed: null, child: Text('Co-op room (soon)')),
            const SizedBox(height: 12),
            const FilledButton.tonal(
                onPressed: null, child: Text('Versus (soon)')),
          ],
        ),
      ),
    );
  }
}
