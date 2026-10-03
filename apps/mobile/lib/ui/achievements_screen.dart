import 'package:flutter/material.dart';

import '../progress/achievements.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';

/// Achievements and lifetime stats (§12).
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = AchievementsScope.of(context);
    final done = Achievements.all.where((d) => a.unlocked.contains(d.id));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Px.night,
        title: Text(
          'Achievements ${done.length}/${Achievements.all.length}',
          style: Px.title(12),
        ),
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GridView.extent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 3.4,
                padding: const EdgeInsets.all(16),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (final d in Achievements.all)
                    _Tile(def: d, unlocked: a.unlocked.contains(d.id)),
                ],
              ),
            ),
            SizedBox(
              width: 240,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: PxPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('STATS', style: Px.label(12, color: Px.fuse)),
                      const SizedBox(height: 8),
                      for (final (label, key) in const [
                        ('Bombs placed', Achievements.bombsPlaced),
                        ('Power-ups', Achievements.itemsPicked),
                        ('Chain record', Achievements.chainRecord),
                        ('Stages cleared', Achievements.stagesCleared),
                        ('Revives', Achievements.revives),
                        ('Versus wins', Achievements.versusWins),
                        ('Oops (team kills)', Achievements.friendlyKills),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: Px.label(12, bold: false),
                                ),
                              ),
                              Text('${a.stat(key)}', style: Px.label(13)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.def, required this.unlocked});

  final AchievementDef def;
  final bool unlocked;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Px.night,
      border: Border.all(color: unlocked ? Px.fuse : Px.edge, width: 2),
    ),
    child: Row(
      children: [
        SpriteIcon(def.sprite, size: 36, opacity: unlocked ? 1 : 0.25),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                def.title,
                style: Px.label(13, color: unlocked ? Px.paper : Px.muted),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                def.description,
                style: Px.label(11, color: Px.muted, bold: false),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
