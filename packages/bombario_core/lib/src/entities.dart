import 'direction.dart';
import 'grid.dart';

/// Power-ups. The first eight are the NES classics (Mystery is timed).
enum ItemType {
  bombUp,
  fireUp,
  speedUp,
  wallPass,
  remote,
  bombPass,
  flamePass,
  mystery,
  exit, // not a power-up, but it is hidden under a brick the same way
}

/// Something that lives on the grid with a continuous position.
/// Positions are in tile units; the centre of tile (i, j) is (i + 0.5, j + 0.5).
abstract class Entity {
  Entity({required this.id, required double x, required double y})
      : _x = x,
        _y = y;

  final int id;
  double _x;
  double _y;

  double get x => _x;
  double get y => _y;

  void setPosition(double x, double y) {
    _x = x;
    _y = y;
  }

  int get tileX => _x.floor();
  int get tileY => _y.floor();
  GridPos get tile => GridPos(tileX, tileY);

  /// Snaps to the centre of the current tile.
  void snapToTile() => setPosition(tileX + 0.5, tileY + 0.5);

  /// Distance from the centre of the current tile along each axis.
  double get offsetX => _x - (tileX + 0.5);
  double get offsetY => _y - (tileY + 0.5);
}

class Player extends Entity {
  Player({
    required super.id,
    required super.x,
    required super.y,
    this.name = '',
  });

  final String name;

  bool alive = true;
  Direction facing = Direction.down;

  // Stats (NES defaults).
  int maxBombs = 1;
  int fireRange = 1;
  double speed = Player.baseSpeed;
  bool wallPass = false;
  bool bombPass = false;
  bool flamePass = false;
  bool remote = false;

  /// Seconds of Mystery invincibility left.
  double invincibleFor = 0;

  bool get invincible => invincibleFor > 0;

  int bombsPlaced = 0;
  int score = 0;

  static const double baseSpeed = 3.0;
  static const double speedStep = 0.5;
  static const double maxSpeed = 6.0;
  static const int maxBombCap = 8;
  static const int maxFireCap = 8;

  /// Half the collision box. Smaller than a tile so near misses feel fair.
  static const double halfBox = 0.4;

  void applyItem(ItemType item) {
    switch (item) {
      case ItemType.bombUp:
        if (maxBombs < maxBombCap) maxBombs++;
      case ItemType.fireUp:
        if (fireRange < maxFireCap) fireRange++;
      case ItemType.speedUp:
        speed = (speed + speedStep).clamp(baseSpeed, maxSpeed);
      case ItemType.wallPass:
        wallPass = true;
      case ItemType.remote:
        remote = true;
      case ItemType.bombPass:
        bombPass = true;
      case ItemType.flamePass:
        flamePass = true;
      case ItemType.mystery:
        invincibleFor = 10;
      case ItemType.exit:
        break;
    }
  }

  /// On death the NES game drops every power-up. We drop the passes and
  /// Remote but keep stat items, which is kinder in a 4-player game.
  void loseItemsOnDeath() {
    wallPass = false;
    bombPass = false;
    flamePass = false;
    remote = false;
  }
}

class Bomb {
  Bomb({
    required this.id,
    required this.x,
    required this.y,
    required this.ownerId,
    required this.range,
    required this.fuse,
    required this.remote,
  });

  final int id;
  final int x;
  final int y;
  final int ownerId;
  final int range;
  final bool remote;

  /// Seconds until explosion. Ignored while [remote] is true.
  double fuse;

  /// Players standing on this bomb when it was placed may keep walking
  /// through it until they step off; after that it is solid to them too.
  final Set<int> passableFor = {};

  GridPos get tile => GridPos(x, y);

  static const double defaultFuse = 2.5;
}

class Flame {
  Flame(
      {required this.x,
      required this.y,
      required this.ownerId,
      this.ttl = Flame.duration});

  final int x;
  final int y;
  final int ownerId;
  double ttl;

  static const double duration = 0.5;
}

/// A power-up lying on the floor after its brick was destroyed.
class FloorItem {
  FloorItem({required this.x, required this.y, required this.type});

  final int x;
  final int y;
  final ItemType type;
}

/// How an enemy moves. Composed into [EnemyKind] definitions.
enum MoveStyle {
  /// Picks a random open direction at junctions. Puffball/Ballom.
  wander,

  /// Wander, but BFS-chase the nearest player within sight range.
  chase,

  /// Chase, moving through soft bricks and avoiding bomb blast zones.
  phaseChase,
}

/// Data-driven enemy definition. New enemies are mostly new rows here.
class EnemyKind {
  const EnemyKind({
    required this.name,
    required this.speed,
    required this.style,
    required this.points,
    this.sightRange = 0,
    this.hp = 1,
    this.wallPass = false,
    this.bombAware = false,
    this.turnChance = 0.1,
  });

  final String name;
  final double speed;
  final MoveStyle style;
  final int points;
  final int sightRange;
  final int hp;
  final bool wallPass;
  final bool bombAware;

  /// Chance per tile of changing direction while wandering in a corridor.
  final double turnChance;

  // The three starter enemies from the design doc (World 1).
  static const puffball = EnemyKind(
    name: 'Puffball',
    speed: 1.5,
    style: MoveStyle.wander,
    points: 100,
    turnChance: 0.15,
  );
  static const blueDrop = EnemyKind(
    name: 'Blue Drop',
    speed: 2.5,
    style: MoveStyle.chase,
    sightRange: 4,
    points: 200,
  );
  static const slimeSage = EnemyKind(
    name: 'Slime Sage',
    speed: 1.5,
    style: MoveStyle.phaseChase,
    sightRange: 6,
    wallPass: true,
    bombAware: true,
    points: 1000,
  );

  /// Hunters that flood the stage when the timer runs out.
  static const hunterCoin = EnemyKind(
    name: 'Hunter Coin',
    speed: 4.5,
    style: MoveStyle.phaseChase,
    sightRange: 99,
    wallPass: true,
    bombAware: true,
    points: 8000,
  );

  static const byName = <String, EnemyKind>{
    'puffball': puffball,
    'blueDrop': blueDrop,
    'slimeSage': slimeSage,
    'hunterCoin': hunterCoin,
  };
}

class Enemy extends Entity {
  Enemy({
    required super.id,
    required super.x,
    required super.y,
    required this.kind,
  }) : hp = kind.hp;

  final EnemyKind kind;
  int hp;
  bool alive = true;
  Direction direction = Direction.none;

  /// The tile this enemy is walking towards, null when it is centred on a
  /// tile and about to decide.
  GridPos? target;

  /// Seconds of immunity after taking a hit, so one flame doesn't deal
  /// several hits over its 0.5 s lifetime.
  double hitCooldown = 0;
}
