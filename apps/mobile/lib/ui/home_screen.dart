import 'dart:math';

import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'join_screen.dart';
import 'lobby_screen.dart';
import 'online_screen.dart';
import 'player_name.dart';

/// Title screen: solo, online rooms, or a room on the local Wi-Fi.
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
            const Text(
              'Phase 2 prototype: online and Wi-Fi rooms',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            const SizedBox(width: 260, child: PlayerNameField()),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Solo'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          GameScreen(seed: Random().nextInt(1 << 30)),
                    ),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.public),
                  label: const Text('Online'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OnlineScreen()),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Host Wi-Fi room'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LobbyScreen.host()),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.login),
                  label: const Text('Join Wi-Fi room'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const JoinScreen())),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Wi-Fi rooms need everyone on the same Wi-Fi or hotspot.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
