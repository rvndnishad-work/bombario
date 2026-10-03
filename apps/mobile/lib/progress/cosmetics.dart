import 'achievements.dart';

/// A hat from the locker. Cosmetic only (§12): hats never change the rules,
/// and the suit colour underneath still tells players apart.
class SkinDef {
  const SkinDef(this.id, this.name, {this.unlockedBy});

  /// Sent to rooms as the player's skin; `classic` means no hat.
  final String id;
  final String name;

  /// Achievement id that unlocks it, or null when everyone has it.
  final String? unlockedBy;

  /// Atlas sprite drawn over the player, or null for `classic`.
  String? get sprite => id == 'classic' ? null : 'hat-$id';
}

abstract final class Cosmetics {
  static const skins = [
    SkinDef('classic', 'Classic'),
    SkinDef('cap', 'Ball cap'),
    SkinDef('sprout', 'Sprout', unlockedBy: 'world-1'),
    SkinDef('horns', 'Horned helm', unlockedBy: 'world-2'),
    SkinDef('wizard', 'Wizard hat', unlockedBy: 'world-3'),
    SkinDef('tophat', 'Top hat', unlockedBy: 'bomber-100'),
    SkinDef('halo', 'Halo', unlockedBy: 'back-on-feet'),
    SkinDef('crown', 'Crown', unlockedBy: 'versus-win'),
  ];

  static SkinDef byId(String id) =>
      skins.firstWhere((s) => s.id == id, orElse: () => skins.first);

  /// Hat sprite for a skin id from the network, null for none or unknown
  /// (a newer app version may send skins this one doesn't have).
  static String? spriteFor(String? id) =>
      id == null ? null : skins.where((s) => s.id == id).firstOrNull?.sprite;

  static bool isUnlocked(SkinDef skin, Achievements achievements) {
    final need = skin.unlockedBy;
    return need == null || achievements.unlocked.contains(need);
  }

  /// [wanted] if it is unlocked, otherwise classic.
  static String equipped(String wanted, Achievements achievements) {
    final s = byId(wanted);
    return isUnlocked(s, achievements) ? s.id : 'classic';
  }
}
