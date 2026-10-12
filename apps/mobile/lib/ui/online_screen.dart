import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/analytics.dart';
import '../net/online.dart';
import '../net/room_session.dart';
import 'kit/menu_frame.dart';
import 'kit/motion.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';
import 'lobby_screen.dart';
import 'player_name.dart';

/// Online play, laid out as a match select: quick co-op or versus on the
/// left, a room with friends (create, or join by code) on the right.
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
      skin: currentSkin(context),
    ),
  );

  /// Quick match (§7): the server picks or makes a room of [mode] and
  /// fills empty seats with bots after 20 seconds.
  void _quick(String mode) => _go(() async {
    final server = _serverUri;
    final skin = currentSkin(context);
    final code = await OnlineServer.quickMatch(server, mode);
    Analytics.instance.log('quick_match', {'mode': mode});
    return RoomSession.joinOnline(
      server: server,
      code: code,
      playerName: PlayerName.current,
      skin: skin,
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
        skin: currentSkin(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MenuFrame(
          title: 'MATCH SELECT',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Quick match: pick a mode and go.
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Entrance(
                      child: Text(
                        'QUICK MATCH  ·  bots fill empty seats',
                        style: Px.label(13, color: Px.muted),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Entrance(
                              delay: const Duration(milliseconds: 80),
                              child: _ModeCard(
                                key: const Key('quick-coop'),
                                title: 'CO-OP',
                                blurb:
                                    'Team up. Clear the stage, '
                                    'revive fallen friends.',
                                color: Px.ok,
                                sprites: const ['p1', 'p2'],
                                onTap: _busy ? null : () => _quick('coop'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Entrance(
                              delay: const Duration(milliseconds: 160),
                              child: _ModeCard(
                                key: const Key('quick-versus'),
                                title: 'VERSUS',
                                blurb:
                                    'Last one standing wins. '
                                    '2 to 4 players.',
                                color: Px.danger,
                                sprites: const ['p1', 'swords', 'p3'],
                                onTap: _busy ? null : () => _quick('versus'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Friends: make a room or join one by code.
              Expanded(
                flex: 2,
                child: Entrance(
                  delay: const Duration(milliseconds: 240),
                  offset: const Offset(30, 0),
                  child: PxPanel(
                    border: Px.fuse,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'PLAY WITH FRIENDS',
                            style: Px.label(13, color: Px.fuse),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Create room'),
                            onPressed: _busy ? null : _create,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Have a code? Join your friends',
                            style: Px.label(12, color: Px.muted, bold: false),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('online-code'),
                                  controller: _code,
                                  textAlign: TextAlign.center,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  maxLength: 6,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp('[a-zA-Z0-9]'),
                                    ),
                                  ],
                                  style: Px.title(
                                    16,
                                    color: Px.fuse,
                                  ).copyWith(letterSpacing: 4),
                                  decoration: InputDecoration(
                                    hintText: 'K7QX4M',
                                    hintStyle: Px.title(
                                      16,
                                      color: Px.edge,
                                    ).copyWith(letterSpacing: 4),
                                    counterText: '',
                                    isDense: true,
                                  ),
                                  onSubmitted: (_) => _join(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _busy ? null : _join,
                                child: const Text('Join'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            // The tile's ink needs a Material under it.
                            child: Material(
                              type: MaterialType.transparency,
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text(
                                  'Server',
                                  style: Px.label(12, color: Px.muted),
                                ),
                                children: [
                                  TextField(
                                    controller: _server,
                                    keyboardType: TextInputType.url,
                                    decoration: const InputDecoration(
                                      labelText: 'Room server address',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_busy) const BusyVeil(text: 'FINDING A ROOM...'),
      ],
    );
  }
}

/// A big game-mode card: the mode's heroes bobbing over a coloured plate,
/// its name and one line on how it plays.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.title,
    required this.blurb,
    required this.color,
    required this.sprites,
    required this.onTap,
  });

  final String title;
  final String blurb;
  final Color color;
  final List<String> sprites;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title quick match',
    child: Pressable(
      onTap: onTap,
      child: PxPanel(
        color: Color.lerp(Px.night, color, 0.18)!,
        border: color,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FittedBox(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, s) in sprites.indexed)
                      Ambient(
                        phase: i / sprites.length,
                        period: const Duration(milliseconds: 800),
                        child: SpriteIcon(s, size: 56),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(title, style: Px.title(20, color: color)),
            const SizedBox(height: 8),
            Text(blurb, style: Px.label(12, color: Px.paper, bold: false)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              color: color,
              child: Text('QUICK MATCH', style: Px.label(14, color: Px.night)),
            ),
          ],
        ),
      ),
    ),
  );
}
