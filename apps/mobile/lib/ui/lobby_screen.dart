import 'package:bombario_core/bombario_core.dart' show Campaign;
import 'package:bombario_net/bombario_net.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/room_session.dart';
import 'kit/menu_frame.dart';
import 'kit/motion.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';
import 'locker_screen.dart';
import 'network_game_screen.dart';
import 'player_name.dart';

/// Room lobby, laid out like a character select: four seats with the
/// players (or bots) in them and their ready flags, and a panel with the
/// mode, the co-op stage and Start (host) or Ready.
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
      RoomSession.host(
        playerName: PlayerName.current,
        skin: currentSkin(context),
      ).then(
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
      return MenuFrame(
        title: 'ROOM',
        child: _startError == null
            ? const BusyVeil(text: 'OPENING A ROOM...')
            : Center(
                child: Text(
                  'Could not start a room: $_startError',
                  style: Px.label(14),
                ),
              ),
      );
    }
    final me = s.lobby.players.where((p) => p.id == s.clientId).firstOrNull;
    final disconnected = s.phase == SessionPhase.disconnected;
    final share = s.online ? s.code : s.hostAddress;
    final players = s.lobby.players;
    return MenuFrame(
      title: s.code == null ? 'ROOM' : 'ROOM ${s.code}',
      trailing: [
        if (share != null)
          Pressable(
            onTap: () {
              Clipboard.setData(ClipboardData(text: share));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.online ? 'Code copied' : 'Address copied'),
                ),
              );
            },
            child: PxPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              border: Px.fuse,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.copy, size: 16, color: Px.fuse),
                  const SizedBox(width: 8),
                  Text(share, style: Px.title(12, color: Px.fuse)),
                ],
              ),
            ),
          ),
      ],
      child: disconnected
          ? Center(
              child: Text('Disconnected from the room', style: Px.label(15)),
            )
          : s.phase == SessionPhase.reconnecting
          ? const BusyVeil(text: 'RECONNECTING...')
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Four seats, character-select style.
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: Entrance(
                            delay: Duration(milliseconds: 70 * i),
                            child: i < players.length
                                ? _SeatCard(
                                    // Rebuilt per player so a new arrival
                                    // pops in.
                                    key: ValueKey('seat-${players[i].id}'),
                                    slot: i,
                                    player: players[i],
                                    isMe: players[i].id == s.clientId,
                                    canRemove: s.isHost && !s.lobby.quick,
                                    onRemove: () => s.removeBot(players[i].id),
                                  )
                                : _EmptySeat(
                                    slot: i,
                                    // One message, on the first free seat.
                                    note: i == players.length
                                        ? (s.lobby.startsIn != null
                                              ? 'Bots fill empty seats in '
                                                    '${s.lobby.startsIn} s'
                                              : 'Waiting for players…')
                                        : null,
                                    onAddBot:
                                        i == players.length &&
                                            s.isHost &&
                                            !s.lobby.quick
                                        ? () => s.addBot()
                                        : null,
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 270,
                  child: Entrance(
                    delay: const Duration(milliseconds: 280),
                    offset: const Offset(30, 0),
                    child: _MatchPanel(session: s, me: me),
                  ),
                ),
              ],
            ),
    );
  }

  static const slotColours = [
    Color(0xFF3D7BFF),
    Color(0xFFFF4B4B),
    Color(0xFF3FC062),
    Color(0xFFFFC23D),
  ];
}

/// One taken seat: the slot colour, the player bobbing in their hat, their
/// name and a READY / HOST / BOT badge that stamps in when it changes.
class _SeatCard extends StatelessWidget {
  const _SeatCard({
    super.key,
    required this.slot,
    required this.player,
    required this.isMe,
    required this.canRemove,
    required this.onRemove,
  });

  final int slot;
  final LobbyPlayer player;
  final bool isMe;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colour = _LobbyScreenState.slotColours[slot % 4];
    final p = player;
    final (badge, badgeColour, ink) = p.bot
        ? ('BOT', Px.edge, Px.paper)
        : p.isHost
        ? ('HOST', Px.fuse, Px.night)
        : p.ready
        ? ('READY', Px.ok, Px.night)
        : ('NOT READY', Px.ink, Px.muted);
    return PxPanel(
      border: isMe ? Px.paper : colour,
      color: Color.lerp(Px.night, colour, 0.14)!,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colour,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text('P${slot + 1}', style: Px.title(11, color: Px.night)),
                const Spacer(),
                if (isMe) Text('YOU', style: Px.label(11, color: Px.night)),
                if (p.bot && canRemove)
                  GestureDetector(
                    key: Key('remove-bot-${p.id}'),
                    onTap: onRemove,
                    child: Semantics(
                      button: true,
                      label: 'Remove bot',
                      child: const Icon(Icons.close, size: 16, color: Px.night),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                child: Ambient(
                  phase: slot / 4,
                  period: const Duration(milliseconds: 900),
                  child: PlayerPreview(
                    skin: p.skin,
                    look: slot % 4 + 1,
                    size: 72,
                    opacity: p.connected ? 1 : 0.4,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              p.name,
              style: Px.label(14),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!p.connected)
            Text(
              'reconnecting…',
              style: Px.label(11, color: Px.blast),
              textAlign: TextAlign.center,
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, a) => ScaleTransition(
                scale: CurvedAnimation(parent: a, curve: Motion.pop),
                child: child,
              ),
              child: Container(
                key: ValueKey(badge),
                padding: const EdgeInsets.symmetric(vertical: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColour,
                  border: Border.all(color: Px.ink, width: 2),
                ),
                child: Text(badge, style: Px.label(11, color: ink)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A free seat: a faded silhouette, and on the first one the wait message
/// and (for the host) Add bot.
class _EmptySeat extends StatelessWidget {
  const _EmptySeat({required this.slot, this.note, this.onAddBot});

  final int slot;
  final String? note;
  final VoidCallback? onAddBot;

  @override
  Widget build(BuildContext context) => PxPanel(
    border: Px.edge,
    color: Px.ink.withValues(alpha: 0.7),
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('P${slot + 1}', style: Px.title(11, color: Px.edge)),
        ),
        Expanded(
          child: FittedBox(
            child: Ambient(
              kind: AmbientKind.pulse,
              period: const Duration(milliseconds: 1400),
              phase: slot / 4,
              child: SpriteIcon('p${slot % 4 + 1}', size: 72, opacity: 0.18),
            ),
          ),
        ),
        if (note case final n?)
          Text(
            n,
            style: Px.label(11, color: Px.muted, bold: false),
            textAlign: TextAlign.center,
          ),
        if (onAddBot case final add?) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('add-bot'),
              icon: const Icon(Icons.smart_toy, size: 16),
              label: const Text('Add bot'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: add,
            ),
          ),
        ],
      ],
    ),
  );
}

/// The right-hand panel: mode tabs, co-op stage, how it plays, and the
/// Start (host) or Ready button.
class _MatchPanel extends StatelessWidget {
  const _MatchPanel({required this.session, required this.me});

  final RoomSession session;
  final LobbyPlayer? me;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final canEdit = s.isHost && !s.lobby.quick;
    final ready = s.isHost ? s.lobby.everyoneReady : true;
    final Widget action = s.isHost
        ? FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(
              s.lobby.quick && s.lobby.startsIn != null ? 'Start now' : 'Start',
            ),
            onPressed: s.lobby.everyoneReady ? s.start : null,
          )
        : FilledButton.tonalIcon(
            icon: Icon(me?.ready == true ? Icons.close : Icons.check),
            label: Text(me?.ready == true ? 'Not ready' : 'Ready'),
            onPressed: () => s.setReady(!(me?.ready ?? false)),
          );
    return PxPanel(
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final (mode, label, colour) in [
                  (GameMode.versus, 'VERSUS', Px.danger),
                  (GameMode.coop, 'CO-OP', Px.ok),
                ])
                  Expanded(
                    child: Pressable(
                      onTap: canEdit ? () => s.setMode(mode) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s.mode == mode ? colour : Px.ink,
                          border: Border.all(
                            color: s.mode == mode ? Px.paper : Px.edge,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          label,
                          style: Px.label(
                            14,
                            color: s.mode == mode ? Px.night : Px.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (s.mode == GameMode.coop) ...[
              if (canEdit)
                DropdownButton<String>(
                  key: const Key('stage-picker'),
                  isExpanded: true,
                  value: s.lobbyStage,
                  items: [
                    for (final st in Campaign.stages)
                      DropdownMenuItem(
                        value: st.id,
                        child: Text('${st.id}  ${st.name}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) s.setStage(v);
                  },
                )
              else
                Text(
                  'Stage ${s.lobbyStage}  '
                  '${Campaign.byId(s.lobbyStage)?.name ?? ''}',
                  style: Px.label(14),
                ),
              const SizedBox(height: 6),
            ],
            Text(
              s.mode == GameMode.versus
                  ? 'Last one standing wins. 2 to 4 players.'
                  : 'Clear the enemies, then gather at the exit. '
                        'Fallen players become ghosts until a '
                        'teammate revives them.',
              style: Px.label(12, color: Px.muted, bold: false),
            ),
            const SizedBox(height: 16),
            // A ready Start button breathes to say "go".
            ready
                ? Ambient(
                    kind: AmbientKind.pulse,
                    period: const Duration(milliseconds: 1200),
                    child: action,
                  )
                : action,
            if (s.isHost && !s.lobby.everyoneReady)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Everyone needs to tap Ready.',
                  textAlign: TextAlign.center,
                  style: Px.label(12, color: Px.muted, bold: false),
                ),
              ),
            if (s.lastWinner != null || s.lastCleared)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _lastResult(s),
                  textAlign: TextAlign.center,
                  style: Px.label(13, color: Px.fuse),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _lastResult(RoomSession s) {
    if (s.lastCleared) return 'Last round: stage cleared!';
    final w = s.lastWinner;
    if (w == null || w == -1) return 'Last round: draw';
    return w == s.myPlayerId
        ? 'Last round: you won!'
        : 'Last round: player $w won';
  }
}
