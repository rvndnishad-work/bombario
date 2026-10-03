import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';

import '../game/blast_game.dart';
import '../ui/kit/pixel_theme.dart';
import 'admin_cheats.dart';

/// The admin switches over the board: which stage, how big it is, and the
/// cheats. Folds down to one small button so it doesn't hide the maze.
class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key, required this.game, required this.cheats});

  final BlastGame game;
  final AdminCheats cheats;

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  bool _open = true;

  void _jump(int by) {
    final game = widget.game;
    final n = core.Campaign.stages.length;
    setState(() => game.goToStage((game.stageIndex + by + n) % n));
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final cheats = widget.cheats;
    if (!_open) {
      return _Chip(
        key: const Key('admin-open'),
        label: 'ADMIN',
        on: true,
        onTap: () => setState(() => _open = true),
      );
    }
    // The HUD ticks while playing, which also catches the first stage load.
    return ListenableBuilder(
      listenable: Listenable.merge([cheats, game.hud]),
      builder: (context, _) {
        final grid = game.isLoaded ? game.sim.grid : null;
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Px.ink.withValues(alpha: 0.78),
            border: Border.all(color: Px.fuse, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Arrow(
                    key: const Key('admin-prev'),
                    icon: Icons.chevron_left,
                    onTap: () => _jump(-1),
                  ),
                  Text(
                    'STAGE ${game.stageIndex + 1}  ${game.stage.id}',
                    style: Px.label(12, color: Px.fuse),
                  ),
                  _Arrow(
                    key: const Key('admin-next'),
                    icon: Icons.chevron_right,
                    onTap: () => _jump(1),
                  ),
                  _Arrow(
                    key: const Key('admin-close'),
                    icon: Icons.close,
                    onTap: () => setState(() => _open = false),
                  ),
                ],
              ),
              if (grid != null)
                Text(
                  'Map ${grid.width} x ${grid.height} tiles',
                  key: const Key('admin-size'),
                  style: Px.label(11, color: Px.muted, bold: false),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _Chip(
                    key: const Key('admin-god'),
                    label: 'NO DYING',
                    on: cheats.invincible,
                    onTap: () => cheats.invincible = !cheats.invincible,
                  ),
                  _Chip(
                    key: const Key('admin-enemies'),
                    label: 'NO ENEMIES',
                    on: cheats.noEnemies,
                    onTap: () => cheats.noEnemies = !cheats.noEnemies,
                  ),
                  _Chip(
                    key: const Key('admin-walls'),
                    label: 'WALK WALLS',
                    on: cheats.noClip,
                    onTap: () => cheats.noClip = !cheats.noClip,
                  ),
                  _Chip(
                    key: const Key('admin-reveal'),
                    label: 'SHOW HIDDEN',
                    on: cheats.revealHidden,
                    onTap: () => cheats.revealHidden = !cheats.revealHidden,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: on ? Px.ok : Px.panel,
        border: Border.all(color: on ? Px.paper : Px.edge, width: 2),
      ),
      child: Text(label, style: Px.label(10, color: on ? Px.ink : Px.muted)),
    ),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(icon, size: 20, color: Px.paper),
    ),
  );
}
