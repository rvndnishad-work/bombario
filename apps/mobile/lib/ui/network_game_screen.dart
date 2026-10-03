import 'dart:async';

import 'package:bombario_core/bombario_core.dart' show Campaign;
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

  /// Shows the stage name and tip for a few seconds at the start.
  bool _showIntro = true;
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _introTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showIntro = false);
    });
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    // `lobby` here means the match ended while this phone was reconnecting.
    final ended =
        s.phase == SessionPhase.ended ||
        s.phase == SessionPhase.disconnected ||
        s.phase == SessionPhase.lobby;
    return Scaffold(
      body: Stack(
        children: [
          GameWidget(
            game: _game,
            overlayBuilderMap: {
              'controls': (context, NetworkGame game) => ControlsOverlay(
                input: game.input,
                actionLabel: game.actionLabel,
                pings: true,
              ),
            },
            initialActiveOverlays: const ['controls'],
          ),
          _NetworkHud(session: s),
          if (_showIntro && s.stageName != null)
            IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -0.45),
                child: Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Stage ${s.stageId}: ${s.stageName}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if ((s.stageTip ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            s.stageTip!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (s.phase == SessionPhase.reconnecting)
            const Center(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Connection lost, reconnecting…'),
                    ],
                  ),
                ),
              ),
            ),
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
                      if (_subtitle(s) case final sub?) ...[
                        const SizedBox(height: 6),
                        Text(
                          sub,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
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

  String? _subtitle(RoomSession s) {
    final next = s.nextStage;
    if (!s.lastCleared || next == null) return null;
    final def = Campaign.byId(next);
    return 'Next up: $next ${def?.name ?? ''}';
  }

  String _title(RoomSession s) {
    if (s.phase == SessionPhase.disconnected) return 'Connection lost';
    if (s.phase == SessionPhase.lobby) return 'Match over';
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
    final coop = session.mode == GameMode.coop;
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
                if (!coop)
                  Text('👥 $alive alive')
                else ...[
                  Text('👾 ${snap.enemies.where((e) => e.alive).length}'),
                  const SizedBox(width: 10),
                  Text('❤️ ${snap.livesLeft}'),
                  if (session.stageId != null) ...[
                    const SizedBox(width: 10),
                    Text(session.stageId!),
                  ],
                ],
                if (me != null && me.ghost) ...[
                  const SizedBox(width: 14),
                  Text(
                    snap.livesLeft > 0
                        ? '👻 ghost: ping, haunt, wait for a revive'
                        : '👻 ghost: no revives left',
                    style: const TextStyle(color: Colors.purpleAccent),
                  ),
                ] else if (me != null && !me.alive) ...[
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
