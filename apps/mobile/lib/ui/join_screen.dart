import 'package:flutter/material.dart';

import '../net/discovery.dart';
import '../net/room_session.dart';
import 'lobby_screen.dart';
import 'player_name.dart';

/// Lists rooms announced on the local network and accepts a typed address.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final RoomDiscovery _discovery = RoomDiscovery();
  final TextEditingController _address = TextEditingController();
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _discovery.start();
  }

  @override
  void dispose() {
    _discovery.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _join(String host, int port) async {
    setState(() => _connecting = true);
    try {
      final session = await RoomSession.join(
        host: host,
        port: port,
        playerName: PlayerName.current,
        skin: currentSkin(context),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LobbyScreen.joined(session)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not connect: $e')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _joinTyped() {
    final text = _address.text.trim();
    final parts = text.split(':');
    final port = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (parts.length != 2 || port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter the address as host:port, e.g. 192.168.1.4:40123',
          ),
        ),
      );
      return;
    }
    _join(parts[0], port);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a room')),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: _discovery,
                builder: (context, _) {
                  final rooms = _discovery.rooms;
                  if (rooms.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            _discovery.error ??
                                'Looking for rooms on this Wi-Fi…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final r in rooms)
                        ListTile(
                          leading: const Icon(Icons.wifi_tethering),
                          title: Text(
                            r.code.isEmpty ? r.name : 'Room ${r.code}',
                          ),
                          subtitle: Text('${r.host}:${r.port}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _connecting
                              ? null
                              : () => _join(r.host, r.port),
                        ),
                    ],
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 300,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Or type the address shown on the host\'s screen',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _address,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        hintText: '192.168.1.4:40123',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _joinTyped(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _connecting ? null : _joinTyped,
                      child: _connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Join'),
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
}
