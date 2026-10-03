import 'package:bombario_net/bombario_net.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/room_session.dart';
import 'network_game_screen.dart';
import 'player_name.dart';

/// Room lobby: players, ready flags, mode (host) and start (host).
///
/// `LobbyScreen.host()` creates the room on this device; `.joined` wraps a
/// session that already connected elsewhere.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen.host({super.key}) : session = null;
  const LobbyScreen.joined(RoomSession this.session, {super.key});

  final RoomSession? session;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  RoomSession? _session;
  String? _startError;
  bool _inMatch = false;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    if (s != null) {
      _bind(s);
    } else {
      RoomSession.host(playerName: PlayerName.current).then(
        _bind,
        onError: (Object e) {
          if (mounted) setState(() => _startError = '$e');
        },
      );
    }
  }

  void _bind(RoomSession s) {
    if (!mounted) {
      s.leave();
      return;
    }
    setState(() => _session = s);
    s.addListener(_onSession);
  }

  void _onSession() {
    final s = _session!;
    if (s.phase == SessionPhase.playing && !_inMatch) {
      _inMatch = true;
      Navigator.of(context)
          .push(
            MaterialPageRoute(builder: (_) => NetworkGameScreen(session: s)),
          )
          .then((_) {
            _inMatch = false;
            s.backToLobby();
          });
    }
    if (s.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.error!)));
      s.clearError();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room')),
        body: Center(
          child: _startError == null
              ? const CircularProgressIndicator()
              : Text('Could not start a room: $_startError'),
        ),
      );
    }
    final me = s.lobby.players
        .where((p) => p.name == PlayerName.current)
        .firstOrNull;
    final disconnected = s.phase == SessionPhase.disconnected;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.code == null ? 'Room' : 'Room ${s.code}'),
        actions: [
          if (s.hostAddress != null)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(s.hostAddress!),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: s.hostAddress!));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Address copied')));
              },
            ),
        ],
      ),
      body: SafeArea(
        child: disconnected
            ? const Center(child: Text('Disconnected from the room'))
            : Row(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final p in s.lobby.players)
                          ListTile(
                            leading: Icon(p.isHost ? Icons.star : Icons.person),
                            title: Text(p.name),
                            trailing: p.isHost
                                ? const Text('Host')
                                : Icon(
                                    p.ready
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: p.ready
                                        ? Colors.greenAccent
                                        : Colors.white38,
                                  ),
                          ),
                        if (s.lobby.players.length < 4)
                          const ListTile(
                            leading: Icon(
                              Icons.hourglass_empty,
                              color: Colors.white38,
                            ),
                            title: Text(
                              'Waiting for players…',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 280,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<GameMode>(
                            segments: const [
                              ButtonSegment(
                                value: GameMode.versus,
                                label: Text('Versus'),
                              ),
                              ButtonSegment(
                                value: GameMode.coop,
                                label: Text('Co-op'),
                              ),
                            ],
                            selected: {s.mode},
                            onSelectionChanged: s.isHost
                                ? (v) => s.setMode(v.first)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.mode == GameMode.versus
                                ? 'Last one standing wins. 2 to 4 players.'
                                : 'Clear the enemies, then gather at the exit.',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (s.isHost)
                            FilledButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Start'),
                              onPressed: s.lobby.everyoneReady ? s.start : null,
                            )
                          else
                            FilledButton.tonalIcon(
                              icon: Icon(
                                me?.ready == true ? Icons.close : Icons.check,
                              ),
                              label: Text(
                                me?.ready == true ? 'Not ready' : 'Ready',
                              ),
                              onPressed: () =>
                                  s.setReady(!(me?.ready ?? false)),
                            ),
                          if (s.isHost && !s.lobby.everyoneReady)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Everyone needs to tap Ready.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (s.lastWinner != null || s.lastCleared)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _lastResult(s),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.amber),
                              ),
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

  String _lastResult(RoomSession s) {
    if (s.lastCleared) return 'Last round: stage cleared!';
    final w = s.lastWinner;
    if (w == null || w == -1) return 'Last round: draw';
    return w == s.myPlayerId
        ? 'Last round: you won!'
        : 'Last round: player $w won';
  }
}
