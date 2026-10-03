import 'package:flutter/foundation.dart';

/// Developer switches for the admin stage viewer. The game reads them every
/// tick, so flipping one mid-stage takes effect at once.
class AdminCheats extends ChangeNotifier {
  AdminCheats({
    bool invincible = true,
    bool noEnemies = false,
    bool noClip = false,
    bool revealHidden = true,
  }) : _invincible = invincible,
       _noEnemies = noEnemies,
       _noClip = noClip,
       _revealHidden = revealHidden;

  bool _invincible;
  bool _noEnemies;
  bool _noClip;
  bool _revealHidden;

  /// Nothing hurts you: enemies, flames, hazards, the clock.
  bool get invincible => _invincible;
  set invincible(bool v) => _set(() => _invincible = v);

  /// Every enemy is removed, spawns and bosses included.
  bool get noEnemies => _noEnemies;
  set noEnemies(bool v) => _set(() => _noEnemies = v);

  /// Walk through bricks, pillars and pits; only the border stops you.
  bool get noClip => _noClip;
  set noClip(bool v) => _set(() => _noClip = v);

  /// Shows what every brick hides (power-ups and the exit).
  bool get revealHidden => _revealHidden;
  set revealHidden(bool v) => _set(() => _revealHidden = v);

  void _set(VoidCallback change) {
    change();
    notifyListeners();
  }
}
