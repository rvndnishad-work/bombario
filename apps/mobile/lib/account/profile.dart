/// What a signed-in player keeps across phones: their name, hat,
/// achievements and lifetime stats. Saved as one Firestore document,
/// `users/{uid}`.
class CloudProfile {
  const CloudProfile({
    this.name = '',
    this.skin = '',
    this.unlocked = const {},
    this.stats = const {},
  });

  final String name;
  final String skin;
  final Set<String> unlocked;
  final Map<String, int> stats;

  static CloudProfile fromJson(Map<String, Object?>? json) {
    if (json == null) return const CloudProfile();
    final stats = <String, int>{};
    final raw = json['stats'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (e.key is String && v is num) stats[e.key as String] = v.toInt();
      }
    }
    final unlocked = json['unlocked'];
    return CloudProfile(
      name: json['name'] is String ? json['name'] as String : '',
      skin: json['skin'] is String ? json['skin'] as String : '',
      unlocked: {
        if (unlocked is List)
          for (final id in unlocked)
            if (id is String) id,
      },
      stats: stats,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'skin': skin,
    'unlocked': unlocked.toList()..sort(),
    'stats': stats,
  };

  /// Combines the progress on this phone with the account's, so nothing is
  /// lost either way: achievements add up, counters keep the higher value,
  /// Daily Dungeon times keep the faster one. Name and hat prefer this
  /// phone's choice and fall back to the account's.
  static CloudProfile merge(CloudProfile local, CloudProfile cloud) {
    final stats = {...cloud.stats};
    for (final e in local.stats.entries) {
      final theirs = stats[e.key];
      if (theirs == null || theirs <= 0) {
        stats[e.key] = e.value;
      } else if (e.value > 0) {
        stats[e.key] = isTimeStat(e.key)
            ? (e.value < theirs ? e.value : theirs)
            : (e.value > theirs ? e.value : theirs);
      }
    }
    return CloudProfile(
      name: local.name.isNotEmpty ? local.name : cloud.name,
      skin: local.skin.isNotEmpty && local.skin != 'classic'
          ? local.skin
          : (cloud.skin.isNotEmpty ? cloud.skin : local.skin),
      unlocked: {...cloud.unlocked, ...local.unlocked},
      stats: stats,
    );
  }

  /// Stats where lower is better (Daily Dungeon clear times).
  static bool isTimeStat(String key) => key.startsWith('daily.');
}
