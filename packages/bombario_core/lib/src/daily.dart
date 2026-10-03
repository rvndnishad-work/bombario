import 'dart:math';

import 'campaign.dart';
import 'entities.dart';

/// The Daily Dungeon (§10): one generated stage per calendar day, the same
/// for everyone, played solo for a place on that day's leaderboard.
///
/// The day's seed picks a campaign world as the theme, borrows the terrain of
/// one of that world's generated stages, and mixes in enemies from any world
/// up to the theme. Pure function of the date, so the server and every phone
/// agree without talking.
class DailyDungeon {
  DailyDungeon._(this.date, this.seed, this.stage);

  /// Today's dungeon in UTC, so the whole world shares one board.
  factory DailyDungeon.today([DateTime? now]) =>
      DailyDungeon.forDate((now ?? DateTime.now()).toUtc());

  factory DailyDungeon.forDate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final seed = seedFor(day);
    final rng = Random(seed);
    final theme = 1 + rng.nextInt(5);

    final templates = [
      for (final s in Campaign.stages)
        if (s.world == theme && s.layout == null && !s.isBoss && !s.bonus) s,
    ];
    final base = templates[rng.nextInt(templates.length)];

    final pool = <EnemyKind>{
      for (final s in Campaign.stages)
        if (s.world <= theme && !s.isBoss && !s.bonus)
          for (final (kind, _) in s.enemies) kind,
    }.toList();
    final kinds = <EnemyKind>{};
    while (kinds.length < min(4, pool.length)) {
      kinds.add(pool[rng.nextInt(pool.length)]);
    }
    final total = 6 + theme + rng.nextInt(3);
    final counts = {for (final k in kinds) k: 1};
    for (var i = kinds.length; i < total; i++) {
      final k = kinds.elementAt(rng.nextInt(kinds.length));
      counts[k] = counts[k]! + 1;
    }

    const extras = [
      ItemType.kick,
      ItemType.remote,
      ItemType.heart,
      ItemType.bombPass,
      ItemType.wallPass,
      ItemType.flamePass,
    ];
    final stage = StageDef(
      id: 'daily-${idFor(day)}',
      name: _names[rng.nextInt(_names.length)],
      theme: theme,
      enemies: [for (final e in counts.entries) (e.key, e.value)],
      items: [
        ItemType.bombUp,
        ItemType.fireUp,
        extras[rng.nextInt(extras.length)],
      ],
      brickDensity: 0.35 + rng.nextDouble() * 0.15,
      timeLimit: 200,
      crackedTiles: base.crackedTiles,
      stalactites: base.stalactites,
      conveyors: base.conveyors,
      vents: base.vents,
      ventInterval: base.ventInterval,
      iceTiles: base.iceTiles,
      warpPairs: base.warpPairs,
      possessed: base.possessed,
      darkness: base.darkness,
      wind: base.wind,
      cannons: base.cannons,
      tip: 'Same dungeon for everyone today. Fastest clear wins.',
    );
    return DailyDungeon._(day, seed, stage);
  }

  /// The UTC day this dungeon belongs to.
  final DateTime date;

  /// Seed for both the stage plan and [StageDef.level].
  final int seed;
  final StageDef stage;

  /// `YYYY-MM-DD`, the leaderboard key.
  String get id => idFor(date);

  /// Leaderboard name on the server.
  String get board => 'daily-$id';

  static String idFor(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Stable across platforms: FNV-1a over the date string.
  static int seedFor(DateTime d) {
    var h = 0x811c9dc5;
    for (final c in 'bombario-daily-${idFor(d)}'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  static const _names = [
    'Fuse Box',
    'Crumble Keep',
    'Spark Cellar',
    'Ember Vault',
    'Rubble Run',
    'Tick Tock Tomb',
    'Powder Hall',
    'Blast Furnace',
    'Cinder Crypt',
    'Short Fuse',
  ];
}
