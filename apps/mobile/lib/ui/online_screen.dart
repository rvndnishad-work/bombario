import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/analytics.dart';
import '../net/online.dart';
import '../net/room_session.dart';
import 'lobby_screen.dart';
import 'player_name.dart';

/// Online play: create a room and share its code, or type a friend's code.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final TextEditingController _code = TextEditingController();
  late final TextEditingController _server = TextEditingController(
    text: OnlineServer.url.value,
  );
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Uri get _serverUri {
    OnlineServer.url.value = _server.text.trim();
    return OnlineServer.parse(_server.text);
  }

  Future<void> _go(Future<RoomSession> Function() connect) async {
    setState(() => _busy = true);
    try {
      final session = await connect();
      if (!mounted) {
        session.leave();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LobbyScreen.joined(session)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _create() => _go(
    () => RoomSession.createOnline(
      server: _serverUri,
      playerName: PlayerName.current,
    ),
  );

  /// Quick match (§7): the server picks or makes a room of [mode] and
  /// fills empty seats with bots after 20 seconds.
  void _quick(String mode) => _go(() async {
    final server = _serverUri;
    final code = await OnlineServer.quickMatch(server, mode);
    Analytics.instance.log('quick_match', {'mode': mode});
    return RoomSession.joinOnline(
      server: server,
      code: code,
      playerName: PlayerName.current,
    );
  });

  void _join() {
    final code = OnlineServer.normalizeCode(_code.text);
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room codes are 6 letters and digits')),
      );
      return;
    }
    _go(
      () => RoomSession.joinOnline(
        server: _serverUri,
        code: code,
        playerName: PlayerName.current,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play online')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Quick match: play with anyone, bots fill in'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('quick-coop'),
                          icon: const Icon(Icons.groups),
                          label: const Text('Co-op'),
                          onPressed: _busy ? null : () => _quick('coop'),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('quick-versus'),
                          icon: const Icon(Icons.sports_mma),
                          label: const Text('Versus'),
                          onPressed: _busy ? null : () => _quick('versus'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 40),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Start a room and share its code'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Create room'),
                              onPressed: _busy ? null : _create,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Have a code? Join your friends'),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('online-code'),
                              controller: _code,
                              textAlign: TextAlign.center,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 6,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp('[a-zA-Z0-9]'),
                                ),
                              ],
                              style: const TextStyle(
                                fontSize: 22,
                                letterSpacing: 6,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'K7QX4M',
                                counterText: '',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _join(),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: _busy ? null : _join,
                              child: const Text('Join'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_busy) const LinearProgressIndicator(),
                  ExpansionTile(
                    title: const Text(
                      'Server',
                      style: TextStyle(color: Colors.white54),
                    ),
                    children: [
                      TextField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Room server address',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
