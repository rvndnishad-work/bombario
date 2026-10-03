import 'package:bombario_core/bombario_core.dart' as core;

/// What the admin viewer shows about one campaign stage, built exactly as
/// the solo game builds it so the hidden items match what you'll play.
class StageInfo {
  /// Builds stage [index] with the seed the solo game would use for it.
  factory StageInfo.of(int index, {required int seed}) {
    final def = core.Campaign.stages[index];
    final level = def.level(seed: seed + index, players: 1);
    // The chest and the mini-boss are placed when the world starts.
    final world = core.World(
      level,
      seed: seed + index,
      config: def.config(players: 1, coop: false),
    );
    return StageInfo._(index, def, level, world);
  }

  StageInfo._(this.index, this.def, this.level, this._world);

  final int index;
  final core.StageDef def;
  final core.LevelData level;
  final core.World _world;

  core.StageExtra? get extra => def.extra;

  /// Where the treasure chest sits, on a treasure stage.
  core.GridPos? get chest => switch (_world.treasure) {
    final t? => core.GridPos(t.x, t.y),
    null => null,
  };

  /// The mini-boss and where it starts, on a mini-boss stage.
  core.Enemy? get miniBoss {
    for (final e in _world.enemies) {
      if (e.id == _world.miniBossId) return e;
    }
    return null;
  }

  /// 1 to 50 across the whole campaign.
  int get number => index + 1;

  /// Every fifth stage (5, 10 ... 50): treasure, mini-boss or challenge on
  /// top of its bonus or boss stage.
  bool get milestone => number % 5 == 0;

  int get width => level.grid.width;
  int get height => level.grid.height;

  String get kind => def.isBoss
      ? 'Boss'
      : def.bonus
      ? 'Bonus'
      : 'Stage';

  /// Bricks with something under them, in reading order.
  List<(core.GridPos, core.ItemType)> get hidden => [
    for (final p in level.grid.positions)
      if (level.grid.hiddenAt(p.x, p.y) case final item?) (p, item),
  ];

  /// Starting enemies by name, most common first.
  List<(String, int)> get enemies {
    final counts = <String, int>{};
    for (final e in _world.enemies) {
      counts.update(
        e.id == _world.miniBossId ? 'Mini-boss ${e.kind.name}' : e.kind.name,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  int get bricks => level.grid.positions
      .where((p) => level.grid.atPos(p) == core.TileType.brick)
      .length;
}
