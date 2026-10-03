import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';

import '../../game/game_hud.dart';
import 'pixel_theme.dart';
import 'sprite_icon.dart';

/// The one opaque strip above the board (Arvind's in-game layout): pause,
/// timer, your stats, the stage, and every player's status. Everything else
/// on screen is the board.
class GameToolbar extends StatelessWidget {
  const GameToolbar({super.key, required this.hud, required this.onPause});

  static const double height = 44;

  final GameHud hud;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: Px.night,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListenableBuilder(
        listenable: hud,
        builder: (context, _) {
          final h = hud;
          final minutes = h.timeLeft ~/ 60;
          final seconds = (h.timeLeft % 60).toString().padLeft(2, '0');
          return Row(
            children: [
              _Box(
                key: const Key('pause-button'),
                onTap: onPause,
                child: const Icon(Icons.pause, size: 18, color: Px.paper),
              ),
              const SizedBox(width: 6),
              _Box(
                child: Text(
                  '$minutes:$seconds',
                  style: Px.title(
                    12,
                    color: h.timeLeft <= 30 ? Px.danger : Px.paper,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (h.lives case final lives?) _Stat('heart', '$lives'),
                      _Stat('bomb', '${h.bombs}'),
                      _Stat('pu-fire', '${h.fire}'),
                      _Stat('pu-speed', '${h.speed}'),
                      if (h.active != core.ActiveItem.none)
                        _Box(
                          border: Px.ok,
                          child: Row(
                            children: [
                              SpriteIcon(
                                h.active == core.ActiveItem.remote
                                    ? 'remote'
                                    : 'icon-tether',
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                h.active == core.ActiveItem.remote
                                    ? 'Remote'
                                    : 'Tether',
                                style: Px.label(12),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (h.stage.isNotEmpty)
                        Text(
                          'Stage ${h.stage}',
                          style: Px.label(12, color: Px.muted, bold: false),
                        ),
                      if (h.players.isEmpty) ...[
                        const SizedBox(width: 12),
                        Text('${h.score}', style: Px.title(10)),
                      ],
                      const SizedBox(width: 12),
                      for (final p in h.players) _PlayerChip(p),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.onTap, this.border});

  final Widget child;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Px.ink,
        border: Border.all(color: border ?? Px.edge, width: 2),
      ),
      child: child,
    );
    return onTap == null
        ? box
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: box,
          );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.sprite, this.value);

  final String sprite;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Row(
      children: [
        SpriteIcon(sprite, size: 18),
        const SizedBox(width: 3),
        Text(value, style: Px.label(13)),
      ],
    ),
  );
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip(this.player);

  final HudPlayer player;

  static const colours = [
    Color(0xFF3D7BFF),
    Color(0xFFFF4B4B),
    Color(0xFF3FC062),
    Color(0xFFFFC23D),
  ];

  @override
  Widget build(BuildContext context) {
    final colour = colours[player.slot % colours.length];
    final down = player.status != HudPlayerStatus.alive;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 2, right: 7),
        decoration: BoxDecoration(
          color: Px.ink,
          border: Border.all(color: down ? Px.stone : colour, width: 2),
        ),
        child: Row(
          children: [
            SpriteIcon(
              player.status == HudPlayerStatus.alive
                  ? 'p${player.slot % 4 + 1}'
                  : player.status == HudPlayerStatus.ghost
                  ? 'spirit-p${player.slot % 4 + 1}'
                  : 'tomb',
              size: 22,
            ),
            const SizedBox(width: 4),
            Text(
              switch (player.status) {
                HudPlayerStatus.alive => player.name,
                HudPlayerStatus.ghost => '${player.name} · down',
                HudPlayerStatus.out => '${player.name} · out',
              },
              style: Px.label(12, color: down ? Px.muted : Px.paper).copyWith(
                decoration: player.isMe ? TextDecoration.underline : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Closable popups over the top of the board.
class MessagePopups extends StatelessWidget {
  const MessagePopups({super.key, required this.messages});

  final GameMessages messages;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ListenableBuilder(
          listenable: messages,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in messages.visible)
                Padding(
                  key: ValueKey(m.id),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _Popup(
                    message: m,
                    onClose: () => messages.close(m.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Popup extends StatelessWidget {
  const _Popup({required this.message, required this.onClose});

  final GameMessage message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: Px.night.withValues(alpha: 0.94),
          border: Border.all(color: Px.danger, width: 2),
          boxShadow: const [BoxShadow(color: Px.ink, offset: Offset(3, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.sprite case final s?) ...[
              SpriteIcon(s, size: 32),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message.title, style: Px.label(14)),
                  if (message.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message.body,
                      style: Px.label(12, color: Px.muted, bold: false),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Close message',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Px.edge, width: 2),
                  ),
                  child: const Icon(Icons.close, size: 18, color: Px.paper),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A centred menu card: pause, stage cleared, game over, match over.
class MenuCard extends StatelessWidget {
  const MenuCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.actions,
    this.border = Px.edge,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Px.ink.withValues(alpha: 0.55),
      child: Center(
        child: PxPanel(
          border: border,
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Px.title(16), textAlign: TextAlign.center),
              if (subtitle case final s?) ...[
                const SizedBox(height: 10),
                Text(
                  s,
                  style: Px.label(13, color: Px.muted, bold: false),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 10, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}
