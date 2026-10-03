import 'package:flutter/material.dart';

import '../progress/achievements.dart';
import '../progress/cosmetics.dart';
import '../settings/settings.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';

/// The cosmetics locker (§12): hats unlocked by achievements. Everything is
/// earned by playing; nothing here is for sale yet.
class LockerScreen extends StatelessWidget {
  const LockerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Settings.of(context);
    final achievements = AchievementsScope.of(context);
    final equipped = Cosmetics.equipped(settings.skin, achievements);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Px.night,
        title: Text('Locker', style: Px.title(12)),
      ),
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: Center(child: PlayerPreview(skin: equipped, size: 128)),
            ),
            Expanded(
              child: GridView.extent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.95,
                padding: const EdgeInsets.all(16),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (final skin in Cosmetics.skins)
                    _SkinTile(
                      skin: skin,
                      unlocked: Cosmetics.isUnlocked(skin, achievements),
                      equipped: skin.id == equipped,
                      onTap: () => settings.update((s) => s.skin = skin.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A player sprite wearing [skin]'s hat.
class PlayerPreview extends StatelessWidget {
  const PlayerPreview({
    super.key,
    required this.skin,
    this.look = 1,
    this.size = 48,
    this.opacity = 1,
  });

  final String skin;

  /// Suit colour, 1 to 4.
  final int look;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final hat = Cosmetics.spriteFor(skin);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          SpriteIcon('p$look', size: size, opacity: opacity),
          if (hat != null) SpriteIcon(hat, size: size, opacity: opacity),
        ],
      ),
    );
  }
}

class _SkinTile extends StatelessWidget {
  const _SkinTile({
    required this.skin,
    required this.unlocked,
    required this.equipped,
    required this.onTap,
  });

  final SkinDef skin;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final need = skin.unlockedBy;
    final hint = need == null ? '' : Achievements.byId(need)?.title ?? need;
    return Semantics(
      button: unlocked,
      selected: equipped,
      label: unlocked ? skin.name : '${skin.name}, locked',
      child: GestureDetector(
        key: Key('skin-${skin.id}'),
        onTap: unlocked ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Px.night,
            border: Border.all(
              color: equipped
                  ? Px.fuse
                  : unlocked
                  ? Px.edge
                  : Px.night,
              width: equipped ? 3 : 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PlayerPreview(
                skin: skin.id,
                size: 56,
                opacity: unlocked ? 1 : 0.3,
              ),
              const SizedBox(height: 6),
              Text(
                skin.name,
                style: Px.label(12, color: unlocked ? Px.paper : Px.muted),
                textAlign: TextAlign.center,
              ),
              Text(
                equipped
                    ? 'Wearing'
                    : unlocked
                    ? 'Tap to wear'
                    : 'Unlock: $hint',
                style: Px.label(10, color: Px.muted, bold: false),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
