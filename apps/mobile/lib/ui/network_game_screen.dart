import 'package:bombario_core/bombario_core.dart' show Campaign;
import 'package:bombario_net/bombario_net.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/network_game.dart';
import '../net/room_session.dart';
import '../audio/game_audio.dart';
import '../progress/achievements.dart';
import '../settings/settings.dart';
import 'controls_overlay.dart';
import 'kit/game_chrome.dart';
import 'kit/pixel_theme.dart';

/// Plays one networked match; pops back to the lobby when it ends.
class NetworkGameScreen extends StatefulWidget {
  const NetworkGameScreen({super.key, required this.session});

  final RoomSession session;

  @override
  State<NetworkGameScreen> createState() => _NetworkGameScreenState();
}

class _NetworkGameScreenState extends State<NetworkGameScreen> {
  late final NetworkGame _game = NetworkGame(
    widget.session,
    settings: Settings.read(context),
    achievements: AchievementsScope.read(context),
  );

  bool _menuOpen = false;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  void _onSession() {
    final s = widget.session;
    if (!_recorded && s.phase == SessionPhase.ended) {
      _recorded = true;
      _game.recordResult();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    GameAudio.instance.playMusic(0);
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final settings = Settings.of(context);
    // `lobby` here means the match ended while this phone was reconnecting.
    final ended =
        s.phase == SessionPhase.ended ||
        s.phase == SessionPhase.disconnected ||
        s.phase == SessionPhase.lobby;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            GameToolbar(
              hud: _game.hud,
              onPause: () => setState(() => _menuOpen = true),
            ),
            Expanded(
              child: Stack(
                children: [
                  GameWidget(
                    game: _game,
                    overlayBuilderMap: {
                      'controls': (context, NetworkGame game) =>
                          ControlsOverlay(
                            input: game.input,
                            actionLabel: game.actionLabel,
                            pings: s.mode == GameMode.coop,
                            opacity: settings.controlsOpacity,
                            scale: settings.controlsScale,
                            leftHanded: settings.leftHanded,
                            haptics: settings.haptics,
                          ),
                    },
                    initialActiveOverlays: const ['controls'],
                  ),
                  MessagePopups(messages: _game.messages),
                  if (s.phase == SessionPhase.reconnecting)
                    const MenuCard(
                      title: 'Reconnecting',
                      subtitle: 'Connection lost. Getting your seat back...',
                      actions: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ],
                    )
                  else if (ended)
                    MenuCard(
                      border: s.lastCleared || s.lastWinner == s.myPlayerId
                          ? Px.ok
                          : Px.danger,
                      title: _title(s),
                      subtitle: _subtitle(s),
                      actions: [
                        FilledButton(
                          onPressed: () {
                            s.backToLobby();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Back to lobby'),
                        ),
                      ],
                    )
                  else if (_menuOpen)
                    MenuCard(
                      title: 'Menu',
                      subtitle: 'The match keeps running for everyone else.',
                      actions: [
                        OutlinedButton(
                          onPressed: () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                          child: const Text('Leave room'),
                        ),
                        FilledButton(
                          key: const Key('resume'),
                          onPressed: () => setState(() => _menuOpen = false),
                          child: const Text('Resume'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
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
