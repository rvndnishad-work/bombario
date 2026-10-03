import 'dart:math';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';

import '../game/blast_game.dart';
import '../game/sprite_atlas.dart';
import '../game/world_renderer.dart';
import '../ui/game_screen.dart';
import '../ui/kit/pixel_theme.dart';
import '../ui/kit/sprite_icon.dart';
import 'admin_cheats.dart';
import 'stage_info.dart';

/// Developer stage viewer: pick any of the 50 stages, see its size, enemies
/// and what every brick hides, then play it with cheats on.
///
/// Opened by tapping the Settings title five times.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.seed});

  /// Fixed seed so generated stages hold still while you inspect them.
  final int? seed;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final int _seed = widget.seed ?? Random().nextInt(1 << 30);
  final AdminCheats _cheats = AdminCheats();
  final Map<int, StageInfo> _cache = {};
  int _selected = 0;
  bool _milestonesOnly = false;

  StageInfo _info(int i) =>
      _cache.putIfAbsent(i, () => StageInfo.of(i, seed: _seed));

  @override
  void initState() {
    super.initState();
    if (SpriteAtlas.instance == null) {
      SpriteAtlas.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _cheats.dispose();
    super.dispose();
  }

  void _play() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GameScreen(seed: _seed, startStage: _selected, admin: _cheats),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indices = [
      for (var i = 0; i < core.Campaign.stages.length; i++)
        if (!_milestonesOnly || (i + 1) % 5 == 0) i,
    ];
    final info = _info(_selected);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Px.night,
        title: Text('Admin: stages', style: Px.title(14)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              key: const Key('admin-milestones'),
              label: Text('Every 5th', style: Px.label(12)),
              selected: _milestonesOnly,
              onSelected: (v) => setState(() => _milestonesOnly = v),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 230,
              child: ListView(
                key: const Key('admin-stage-list'),
                children: [
                  for (final i in indices)
                    _StageRow(
                      info: _info(i),
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 2, color: Px.edge),
            Expanded(
              child: _StageDetail(info: info, cheats: _cheats, onPlay: _play),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final StageInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Px.panel : Colors.transparent,
    child: InkWell(
      key: Key('admin-stage-${info.number}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${info.number}',
                style: Px.label(14, color: info.milestone ? Px.fuse : Px.paper),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${info.def.id}  ${info.def.name}',
                    style: Px.label(12, bold: false),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${info.width} x ${info.height}'
                    '${info.kind == 'Stage' ? '' : '  ${info.kind.toUpperCase()}'}',
                    style: Px.label(10, color: Px.muted, bold: false),
                  ),
                ],
              ),
            ),
            if (info.milestone)
              const Icon(Icons.star, size: 16, color: Px.fuse),
          ],
        ),
      ),
    ),
  );
}

class _StageDetail extends StatelessWidget {
  const _StageDetail({
    required this.info,
    required this.cheats,
    required this.onPlay,
  });

  final StageInfo info;
  final AdminCheats cheats;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final hidden = info.hidden;
    final enemies = info.enemies;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Stage ${info.number} (${info.def.id}): ${info.def.name}',
                style: Px.title(12, color: info.milestone ? Px.fuse : Px.paper),
              ),
            ),
            FilledButton.icon(
              key: const Key('admin-play'),
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          key: const Key('admin-detail-size'),
          '${info.kind}. Map ${info.width} x ${info.height} tiles, '
          '${info.bricks} bricks, ${info.def.timeLimit.round()} s'
          '${info.milestone ? '. Every-5th stage.' : ''}',
          style: Px.label(12, color: Px.muted, bold: false),
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: info.width / info.height,
          child: CustomPaint(painter: _MapPainter(info)),
        ),
        const SizedBox(height: 12),
        Text('UNDER THE BRICKS', style: Px.label(12, color: Px.fuse)),
        const SizedBox(height: 4),
        if (hidden.isEmpty)
          Text(
            'Nothing hidden (boss or bonus stage).',
            style: Px.label(12, bold: false),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final (pos, item) in hidden)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpriteIcon(WorldRenderer.itemSprite(item), size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${item == core.ItemType.exit ? 'Exit' : BlastGame.itemInfo(item).$1}'
                    ' at ${pos.x},${pos.y}',
                    style: Px.label(12, bold: false),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('ENEMIES', style: Px.label(12, color: Px.fuse)),
        const SizedBox(height: 4),
        Text(
          enemies.isEmpty
              ? 'None at the start.'
              : enemies.map((e) => '${e.$2} x ${e.$1}').join(', '),
          style: Px.label(12, bold: false),
        ),
        const SizedBox(height: 12),
        Text('CHEATS IN PLAY', style: Px.label(12, color: Px.fuse)),
        ListenableBuilder(
          listenable: cheats,
          builder: (context, _) => Column(
            children: [
              _Switch(
                'No dying',
                cheats.invincible,
                (v) => cheats.invincible = v,
              ),
              _Switch(
                'No enemies',
                cheats.noEnemies,
                (v) => cheats.noEnemies = v,
              ),
              _Switch(
                'Walk through walls',
                cheats.noClip,
                (v) => cheats.noClip = v,
              ),
              _Switch(
                'Show what bricks hide',
                cheats.revealHidden,
                (v) => cheats.revealHidden = v,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(this.label, this.value, this.onChanged);

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Px.label(13, bold: false)),
    value: value,
    onChanged: onChanged,
  );
}

/// A flat map of the stage: pillars, bricks, spawns, and each hidden item
/// drawn on its brick.
class _MapPainter extends CustomPainter {
  _MapPainter(this.info);

  final StageInfo info;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = info.level.grid;
    final t = size.width / grid.width;
    final paint = Paint();
    Rect cell(int x, int y, [double inset = 0]) => Rect.fromLTWH(
      x * t + inset,
      y * t + inset,
      t - inset * 2,
      t - inset * 2,
    );

    for (var y = 0; y < grid.height; y++) {
      for (var x = 0; x < grid.width; x++) {
        paint.color = switch (grid.at(x, y)) {
          core.TileType.pillar => Px.stone,
          core.TileType.brick => Px.brick,
          core.TileType.cracked => const Color(0xFF8C7A55),
          core.TileType.pit => Px.ink,
          core.TileType.floor => const Color(0xFF3E7A3C),
        };
        canvas.drawRect(cell(x, y), paint);
      }
    }
    for (final s in info.level.playerSpawns) {
      paint.color = const Color(0xFF3D7BFF);
      canvas.drawCircle(cell(s.x, s.y).center, t * 0.35, paint);
    }
    for (final e in info.level.enemySpawns) {
      paint.color = Px.danger;
      canvas.drawCircle(cell(e.pos.x, e.pos.y).center, t * 0.3, paint);
    }
    final atlas = SpriteAtlas.instance;
    for (final (pos, item) in info.hidden) {
      final exit = item == core.ItemType.exit;
      canvas.drawRect(
        cell(pos.x, pos.y, t * 0.04),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.5, t * 0.1)
          ..color = exit ? Px.fuse : const Color(0xFF7CF0FF),
      );
      if (atlas != null) {
        atlas.draw(
          canvas,
          WorldRenderer.itemSprite(item),
          cell(pos.x, pos.y, t * 0.15),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}
