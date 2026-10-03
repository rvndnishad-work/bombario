import 'package:bombario_net/bombario_net.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/network_game.dart';
import '../net/room_session.dart';
import 'controls_overlay.dart';

/// Plays one networked match; pops back to the lobby when it ends.
class NetworkGameScreen extends StatefulWidget {
  const NetworkGameScreen({super.key, required this.session});

  final RoomSession session;

  @override
  State<NetworkGameScreen> createState() => _NetworkGameScreenState();
}

class _NetworkGameScreenState extends State<NetworkGameScreen> {
  late final NetworkGame _game = NetworkGame(widget.session);

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final ended =
        s.phase == SessionPhase.ended || s.phase == SessionPhase.disconnected;
    return Scaffold(
      body: Stack(
        children: [
          GameWidget(
            game: _game,
            overlayBuilderMap: {
              'controls': (context, NetworkGame game) =>
                  ControlsOverlay(input: game.input, hasRemote: game.hasRemote),
            },
            initialActiveOverlays: const ['controls'],
          ),
          _NetworkHud(session: s),
          if (ended)
            Center(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _title(s),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          s.backToLobby();
                          Navigator.of(context).pop();
                        },
                        child: const Text('Back to lobby'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _title(RoomSession s) {
    if (s.phase == SessionPhase.disconnected) return 'Connection lost';
    if (s.lastCleared) return 'Stage cleared!';
    final w = s.lastWinner;
    if (w == null) return 'Stage failed';
    if (w == -1) return 'Draw!';
    if (w == s.myPlayerId) return 'You win!';
    final name = s.snapshot?.player(w)?.name ?? 'Player $w';
    return '$name wins';
  }
}

class _NetworkHud extends StatelessWidget {
  const _NetworkHud({required this.session});

  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    final snap = session.snapshot;
    if (snap == null) return const SizedBox.shrink();
    final time = snap.timeLeft.ceil();
    final me = session.myPlayerId == null
        ? null
        : snap.player(session.myPlayerId!);
    final alive = snap.players.where((p) => p.alive).length;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⏱ ${time ~/ 60}:${(time % 60).toString().padLeft(2, '0')}',
                ),
                const SizedBox(width: 14),
                if (me != null) ...[
                  Text('💣 ${me.maxBombs}'),
                  const SizedBox(width: 10),
                  Text('🔥 ${me.fireRange}'),
                  const SizedBox(width: 14),
                ],
                if (session.mode == GameMode.versus)
                  Text('👥 $alive alive')
                else
                  Text('👾 ${snap.enemies.where((e) => e.alive).length}'),
                if (me != null && !me.alive) ...[
                  const SizedBox(width: 14),
                  const Text(
                    '💀 spectating',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
