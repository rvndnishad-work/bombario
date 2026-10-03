import 'direction.dart';
import 'grid.dart';

/// Power-ups. The first eight are the NES classics (Mystery is timed); the
/// rest are the Phase 3 batch from the design doc (§5.2, §5.3).
///
/// Serialised by index, so new values go before [exit].
enum ItemType {
  bombUp,
  fireUp,
  speedUp,
  wallPass,
  remote,
  bombPass,
  flamePass,
  mystery,

  /// Walk into a bomb to send it sliding.
  kick,

  /// Absorbs one hit (co-op and solo).
  heart,

  /// Reveals what is under every brick within 5 tiles for 6 s, for the team.
  sonar,

  /// +1 bomb and +1 fire for every living teammate, not the picker.
  teamBoost,

  /// Active: revive a ghost teammate from up to 4 tiles away. One use.
  tether,

  /// The next 3 bombs freeze instead of burn.
  frost,
  exit, // not a power-up, but it is hidden under a brick the same way
}

/// The one "active ability" a player can hold at a time. Picking another
/// swaps it out, so the HUD only ever needs one Action button (§5.3).
enum ActiveItem { none, remote, tether }

/// Quick-chat pings (§4.1), shown to teammates at the sender's position.
enum PingKind { none, exitHere, powerUp, help, run }

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
    this.skin = defaultSkin,
  });

  final String name;

  /// Cosmetic look picked in the app. The rules never read it; the room sets
  /// it at match start and snapshots carry it to every client.
  String skin;

  static const String defaultSkin = 'classic';

  bool alive = true;
  Direction facing = Direction.down;

  // Stats (NES defaults). Derived from [items] by [recomputeStats].
  int maxBombs = 1;
  int fireRange = 1;
  double speed = Player.baseSpeed;
  bool wallPass = false;
  bool bombPass = false;
  bool flamePass = false;
  bool kick = false;

  /// Hits a Heart will absorb (0 or 1).
  int hearts = 0;

  /// Frost bombs left; while above zero, bombs freeze instead of burn.
  int frostBombs = 0;

  ActiveItem active = ActiveItem.none;
  bool get remote => active == ActiveItem.remote;
  set remote(bool v) => active = v ? ActiveItem.remote : ActiveItem.none;

  /// Stat and pass power-ups in pickup order. On death the most recent half
  /// is lost and scattered for teammates (§3.4).
  final List<ItemType> items = [];

  /// Seconds of Mystery invincibility left.
  double invincibleFor = 0;

  bool get invincible => invincibleFor > 0;

  /// Seconds the player is frozen (frost bomb) or stunned (friendly flame
  /// on tutorial stages). A frozen player can't move or place bombs.
  double frozenFor = 0;
  bool get frozen => frozenFor > 0;

  // Co-op ghost state (§4.1).
  bool ghost = false;
  GridPos? tombstone;
  bool hauntUsed = false;

  /// Seconds a teammate has stood on this ghost's tombstone.
  double reviveProgress = 0;

  /// Last tile entered, for cracked floors.
  GridPos? lastTile;

  /// Seconds of the Lantern Witch's curse left: controls are reversed.
  double cursedFor = 0;
  bool get cursed => cursedFor > 0;

  /// Direction kept while sliding on ice, [Direction.none] otherwise.
  Direction momentum = Direction.none;

  /// The direction the player tried to move this tick (after curse and
  /// ice), for enemies that copy it. Not sent over the wire.
  Direction moveDir = Direction.none;

  /// Seconds before a warp door will take this player again.
  double warpCooldown = 0;

  int bombsPlaced = 0;
  int score = 0;

  static const double baseSpeed = 3.0;
  static const double speedStep = 0.5;
  static const double maxSpeed = 6.0;
  static const int maxBombCap = 8;
  static const int maxFireCap = 8;

  /// Half the collision box. Smaller than a tile so near misses feel fair.
  static const double halfBox = 0.4;

  /// Items that are kept in [items] and can be lost on death.
  static const _stacking = {
    ItemType.bombUp,
    ItemType.fireUp,
    ItemType.speedUp,
    ItemType.wallPass,
    ItemType.bombPass,
    ItemType.flamePass,
    ItemType.kick,
  };

  void applyItem(ItemType item) {
    if (_stacking.contains(item)) {
      items.add(item);
      _applyStat(item);
      return;
    }
    switch (item) {
      case ItemType.remote:
        active = ActiveItem.remote;
      case ItemType.tether:
        active = ActiveItem.tether;
      case ItemType.mystery:
        invincibleFor = 10;
      case ItemType.heart:
        hearts = 1;
      case ItemType.frost:
        frostBombs = 3;
      default:
        break; // sonar and team boost act on the world, not the player
    }
  }

  void _applyStat(ItemType item) {
    switch (item) {
      case ItemType.bombUp:
        if (maxBombs < maxBombCap) maxBombs++;
      case ItemType.fireUp:
        if (fireRange < maxFireCap) fireRange++;
      case ItemType.speedUp:
        speed = (speed + speedStep).clamp(baseSpeed, maxSpeed);
      case ItemType.wallPass:
        wallPass = true;
      case ItemType.bombPass:
        bombPass = true;
      case ItemType.flamePass:
        flamePass = true;
      case ItemType.kick:
        kick = true;
      default:
        break;
    }
  }

  /// Rebuilds stats from [items].
  void recomputeStats() {
    maxBombs = 1;
    fireRange = 1;
    speed = baseSpeed;
    wallPass = false;
    bombPass = false;
    flamePass = false;
    kick = false;
    for (final i in items) {
      _applyStat(i);
    }
  }

  /// Drops the most recent half of [items] (rounded up), the active item,
  /// hearts and frost charges. Returns the dropped stat items so the world
  /// can scatter them for teammates.
  /// The original's rule: the stat power-ups stay, the specials go.
  void loseSpecialsOnDeath() {
    items.removeWhere((i) => !_keptOnDeath.contains(i));
    recomputeStats();
    active = ActiveItem.none;
    hearts = 0;
    frostBombs = 0;
  }

  static const _keptOnDeath = {
    ItemType.bombUp,
    ItemType.fireUp,
    ItemType.speedUp,
    ItemType.kick,
  };

  List<ItemType> loseItemsOnDeath() {
    final lose = (items.length + 1) ~/ 2;
    final lost = items.sublist(items.length - lose);
    items.removeRange(items.length - lose, items.length);
    recomputeStats();
    active = ActiveItem.none;
    hearts = 0;
    frostBombs = 0;
    return lost;
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
  int x;
  int y;
  final int ownerId;
  final int range;
  final bool remote;

  /// Frost bombs freeze what they hit instead of burning it.
  bool frost = false;

  /// Direction a kicked bomb is sliding in, [Direction.none] when still.
  Direction slide = Direction.none;

  /// Progress towards the next tile while sliding, 0 to 1.
  double slideProgress = 0;

  /// True while a conveyor (not a kick) is carrying it: it stops when it
  /// rolls off the belt.
  bool conveyed = false;

  /// Tiles per second a conveyor carries a bomb.
  static const double conveyorSpeed = 2;

  /// Tiles per second a kicked bomb travels.
  static const double kickSpeed = 8;

  /// Seconds until explosion. Ignored while [remote] is true.
  double fuse;

  /// Bombs planted by enemies (Bomb Goblin, Bomb-O-Tron) use this owner.
  static const int enemyOwner = -1;

  /// Players standing on this bomb when it was placed may keep walking
  /// through it until they step off; after that it is solid to them too.
  final Set<int> passableFor = {};

  GridPos get tile => GridPos(x, y);

  static const double defaultFuse = 2.5;
}

class Flame {
  Flame({
    required this.x,
    required this.y,
    required this.ownerId,
    this.ttl = Flame.duration,
    this.originX = -1,
    this.originY = -1,
    this.frost = false,
  });

  final int x;
  final int y;
  final int ownerId;
  double ttl;

  /// Tile of the bomb that made this flame, for armoured enemies.
  int originX;
  int originY;

  /// Frost flames freeze instead of burn.
  bool frost;

  static const double duration = 0.5;
}

/// A power-up lying on the floor after its brick was destroyed.
class FloorItem {
  FloorItem({
    required this.x,
    required this.y,
    required this.type,
    this.fromBrick = false,
  });

  final int x;
  final int y;
  final ItemType type;

  /// Revealed from under a brick (not dropped by a fallen player). Bombing
  /// one of these releases a wave of enemies, as in the original.
  final bool fromBrick;
}

/// How an enemy moves. Composed into [EnemyKind] definitions.
enum MoveStyle {
  /// Picks a random open direction at junctions. Puffball/Ballom.
  wander,

  /// Walks a straight line and turns back when blocked. Pebble.
  patrol,

  /// Wander, but BFS-chase the nearest player within sight range.
  chase,

  /// Chase, moving through soft bricks and avoiding bomb blast zones.
  phaseChase,

  /// Floats diagonally and bounces off walls, ignoring lanes. King Puffball.
  bounce,

  /// Travels underground and surfaces near players. Rockjaw Worm.
  burrow,

  /// Never moves. Mole Queen nests, Bomb-O-Tron, curse orbs.
  stationary,

  /// Copies the nearest player's movement, mirrored left/right.
  mirror,

  /// Blinks between spots instead of walking. The Lantern Witch.
  blink,
}

/// Special behaviour on top of movement (§6.3, §7).
enum EnemyAbility {
  none,

  /// Squats for 0.5 s, then jumps 2 tiles over bricks every 3 s. Hopper.
  hop,

  /// Splits into two short-lived Splitlings when killed. Splitter.
  split,

  /// A flame from the front flips it (stunned 3 s); hit it again, or from
  /// the side or back, to kill it. Shellback.
  armoured,

  /// Boss: splits off four Puffballs at half health. King Puffball.
  spawnAtHalf,

  /// Sits still looking like a power-up; bites anyone who steps next to
  /// it, then chases for a while. Sonar exposes it. Mimic.
  mimic,

  /// Plants its own range-2 bomb near players, then flees. Bomb Goblin.
  plantBombs,

  /// Kicks any bomb it walks into along its lane. Kicker Crab.
  kickBombs,

  /// Invisible unless a player is within 3 tiles or a flame is next to it.
  /// Shade.
  cloak,

  /// Buried under a brick; spawns a Pebble every 8 s. Mole Queen nest.
  nest,

  /// Runs to the nearest bomb and eats it, then flees. Fuse Eater.
  eatBombs,

  /// Teleports near a player every 6 s. Phase Wraith.
  teleport,

  /// Harmless; drives nearby enemies at players and speeds them up. Herder.
  herd,

  /// Boss: drops bomb rings and lines, exposed only after each volley.
  /// Bomb-O-Tron.
  bombPatterns,

  /// Boss: blinks around, summons Shades, curses players in phase 2.
  /// The Lantern Witch.
  witch,

  /// Boss: copies the team's power-ups, cycles earlier bosses' attacks,
  /// shrinks the arena in the last phase. Overlord Pontan.
  overlord,
}

/// What an enemy is doing right now, for rendering and rules.
enum EnemyStateKind {
  normal,

  /// Visible warning before an ability (squat, rumble). Always 0.5 s or more
  /// so touch players can react (§6.3 "telegraphing rule").
  telegraph,

  /// Mid-jump: can't be hit and doesn't hurt.
  airborne,

  /// Flipped on its back: harmless, dies to the next hit.
  stunned,

  /// Below ground: can't be hit and doesn't hurt.
  underground,

  /// Mimic pretending to be a power-up ([Enemy.disguise]). Can be bombed,
  /// doesn't hurt on touch.
  disguised,

  /// A boss with its guard down: only now do flames hurt it (Bomb-O-Tron).
  vulnerable,

  /// Running away after an ability (Bomb Goblin, Fuse Eater).
  fleeing,
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
    this.ability = EnemyAbility.none,
    this.lifespan = 0,
    this.size = 0.4,
    this.boss = false,
    this.harmless = false,
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
  final EnemyAbility ability;

  /// Seconds before it vanishes on its own, 0 for never. Splitlings.
  final double lifespan;

  /// Half the body size in tiles. Bosses are big and hit by any flame they
  /// overlap.
  final double size;
  final bool boss;

  /// Touching it doesn't hurt (Herder, nests, curse orbs).
  final bool harmless;

  // ---- The NES roster (§6.2), renamed.
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
  static const barrelhop = EnemyKind(
    name: 'Barrelhop',
    speed: 2.5,
    style: MoveStyle.wander,
    points: 400,
    turnChance: 0.5,
  );
  static const grinface = EnemyKind(
    name: 'Grinface',
    speed: 3.5,
    style: MoveStyle.chase,
    sightRange: 4,
    points: 800,
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
  static const wisp = EnemyKind(
    name: 'Wisp',
    speed: 2.5,
    style: MoveStyle.wander,
    wallPass: true,
    points: 2000,
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

  /// The wave that pours out when a flame hits the revealed exit: faster
  /// than an unboosted player, takes two hits, and steps around bombs.
  static const doorWarden = EnemyKind(
    name: 'Door Warden',
    speed: 4,
    style: MoveStyle.chase,
    sightRange: 8,
    bombAware: true,
    hp: 2,
    points: 1000,
  );

  // ---- New enemies (§6.3).
  static const pebble = EnemyKind(
    name: 'Pebble',
    speed: 1.5,
    style: MoveStyle.patrol,
    points: 100,
  );
  static const hopper = EnemyKind(
    name: 'Hopper',
    speed: 2.5,
    style: MoveStyle.wander,
    points: 300,
    ability: EnemyAbility.hop,
  );
  static const splitter = EnemyKind(
    name: 'Splitter',
    speed: 2.5,
    style: MoveStyle.wander,
    points: 500,
    ability: EnemyAbility.split,
  );
  static const splitling = EnemyKind(
    name: 'Splitling',
    speed: 3.5,
    style: MoveStyle.wander,
    points: 100,
    turnChance: 0.3,
    lifespan: 10,
    size: 0.3,
  );
  static const shellback = EnemyKind(
    name: 'Shellback',
    speed: 1.5,
    style: MoveStyle.wander,
    points: 600,
    ability: EnemyAbility.armoured,
  );

  // ---- Worlds 3-5 (§6.2 tier 7, §6.3 tiers 5-13).
  static const tigerclaw = EnemyKind(
    name: 'Tigerclaw',
    speed: 3.5,
    style: MoveStyle.chase,
    sightRange: 10,
    bombAware: true,
    points: 4000,
  );
  static const mimic = EnemyKind(
    name: 'Mimic',
    speed: 2.5,
    style: MoveStyle.chase,
    sightRange: 5,
    points: 700,
    ability: EnemyAbility.mimic,
  );
  static const bombGoblin = EnemyKind(
    name: 'Bomb Goblin',
    speed: 2.5,
    style: MoveStyle.wander,
    bombAware: true,
    points: 900,
    ability: EnemyAbility.plantBombs,
  );
  static const kickerCrab = EnemyKind(
    name: 'Kicker Crab',
    speed: 2.5,
    style: MoveStyle.wander,
    hp: 2,
    points: 1200,
    turnChance: 0.2,
    ability: EnemyAbility.kickBombs,
  );
  static const shade = EnemyKind(
    name: 'Shade',
    speed: 3.5,
    style: MoveStyle.chase,
    sightRange: 5,
    points: 1500,
    ability: EnemyAbility.cloak,
  );
  static const moleNest = EnemyKind(
    name: 'Mole Queen Nest',
    speed: 0,
    style: MoveStyle.stationary,
    hp: 3,
    points: 2500,
    harmless: true,
    ability: EnemyAbility.nest,
  );
  static const mirrorKnight = EnemyKind(
    name: 'Mirror Knight',
    speed: 3,
    style: MoveStyle.mirror,
    hp: 2,
    points: 2000,
  );
  static const fuseEater = EnemyKind(
    name: 'Fuse Eater',
    speed: 3.5,
    style: MoveStyle.wander,
    points: 1800,
    turnChance: 0.3,
    ability: EnemyAbility.eatBombs,
  );
  static const phaseWraith = EnemyKind(
    name: 'Phase Wraith',
    speed: 3.5,
    style: MoveStyle.phaseChase,
    sightRange: 6,
    wallPass: true,
    bombAware: true,
    hp: 2,
    points: 3000,
    ability: EnemyAbility.teleport,
  );
  static const herder = EnemyKind(
    name: 'Herder',
    speed: 2.5,
    style: MoveStyle.wander,
    hp: 3,
    points: 3500,
    harmless: true,
    ability: EnemyAbility.herd,
  );

  /// The Lantern Witch's curse anchor: bomb it to free the cursed player.
  static const curseOrb = EnemyKind(
    name: 'Curse Orb',
    speed: 0,
    style: MoveStyle.stationary,
    points: 500,
    harmless: true,
  );

  // ---- Bosses (§7). HP scales +60% per extra player at stage build.
  static const kingPuffball = EnemyKind(
    name: 'King Puffball',
    speed: 2,
    style: MoveStyle.bounce,
    points: 10000,
    hp: 8,
    size: 0.9,
    ability: EnemyAbility.spawnAtHalf,
    boss: true,
  );
  static const rockjaw = EnemyKind(
    name: 'Rockjaw Worm',
    speed: 0,
    style: MoveStyle.burrow,
    points: 12000,
    hp: 6,
    size: 0.6,
    boss: true,
  );
  static const bombOTron = EnemyKind(
    name: 'Bomb-O-Tron',
    speed: 0,
    style: MoveStyle.stationary,
    points: 15000,
    hp: 8,
    size: 0.9,
    ability: EnemyAbility.bombPatterns,
    boss: true,
  );
  static const lanternWitch = EnemyKind(
    name: 'Lantern Witch',
    speed: 0,
    style: MoveStyle.blink,
    points: 18000,
    hp: 8,
    size: 0.6,
    ability: EnemyAbility.witch,
    boss: true,
  );
  static const overlordPontan = EnemyKind(
    name: 'Overlord Pontan',
    speed: 2,
    style: MoveStyle.bounce,
    points: 30000,
    hp: 12,
    size: 0.9,
    ability: EnemyAbility.overlord,
    boss: true,
  );

  static const all = [
    puffball,
    blueDrop,
    barrelhop,
    grinface,
    slimeSage,
    wisp,
    hunterCoin,
    doorWarden,
    pebble,
    hopper,
    splitter,
    splitling,
    shellback,
    kingPuffball,
    rockjaw,
    tigerclaw,
    mimic,
    bombGoblin,
    kickerCrab,
    shade,
    moleNest,
    mirrorKnight,
    fuseEater,
    phaseWraith,
    herder,
    curseOrb,
    bombOTron,
    lanternWitch,
    overlordPontan,
  ];

  static final byName = <String, EnemyKind>{
    for (final k in all) k.name: k,
    // Short keys used by level files.
    'puffball': puffball,
    'blueDrop': blueDrop,
    'slimeSage': slimeSage,
    'hunterCoin': hunterCoin,
    'doorWarden': doorWarden,
    'tigerclaw': tigerclaw,
    'mimic': mimic,
    'bombGoblin': bombGoblin,
    'kickerCrab': kickerCrab,
    'shade': shade,
    'moleNest': moleNest,
    'mirrorKnight': mirrorKnight,
    'fuseEater': fuseEater,
    'phaseWraith': phaseWraith,
    'herder': herder,
  };
}

class Enemy extends Entity {
  Enemy({
    required super.id,
    required super.x,
    required super.y,
    required this.kind,
    int? hp,
  })  : hp = hp ?? kind.hp,
        maxHp = hp ?? kind.hp,
        lifeLeft = kind.lifespan;

  final EnemyKind kind;
  int hp;
  final int maxHp;
  bool alive = true;
  Direction direction = Direction.none;

  /// The tile this enemy is walking towards, null when it is centred on a
  /// tile and about to decide.
  GridPos? target;

  /// Seconds of immunity after taking a hit, so one flame doesn't deal
  /// several hits over its 0.5 s lifetime.
  double hitCooldown = 0;

  EnemyStateKind state = EnemyStateKind.normal;

  /// Seconds left in the current [state] (telegraph, airborne, stunned...).
  double stateFor = 0;

  /// Counts towards the next ability use.
  double abilityTimer = 0;

  /// Frozen by a frost bomb: can't move, shatters if a normal flame hits it.
  double frozenFor = 0;

  /// Slowed by a ghost's haunt.
  double slowFor = 0;

  /// Splitlings vanish when this reaches zero.
  double lifeLeft;

  /// King Puffball has already split off its Puffballs.
  bool splitDone = false;

  /// What a disguised Mimic looks like.
  ItemType? disguise;

  /// False while a Shade is cloaked. Everything else is always visible.
  bool visible = true;

  /// Sped up and driven at players by a nearby Herder this tick.
  bool herded = false;

  /// The enemy that spawned this one (nest Pebbles, boss minions), or 0.
  int parentId = 0;

  /// Curse orbs: the player whose curse ends when this dies.
  int linkedPlayer = 0;

  /// Seconds until a cooldown-based ability is ready again.
  double cooldown = 0;

  /// Boss attack counter, for bosses that cycle through attacks.
  int attackIndex = 0;

  /// Bounce direction for diagonal movers, and the jump start/landing for
  /// Hoppers.
  double vx = 1, vy = 1;
  double fromX = 0, fromY = 0;
  GridPos? landing;

  bool get frozen => frozenFor > 0;

  /// Can a flame hurt it, and does touching it hurt?
  bool get solid =>
      state != EnemyStateKind.airborne &&
      state != EnemyStateKind.underground &&
      !(kind.style == MoveStyle.burrow && state == EnemyStateKind.telegraph);

  bool get harmful =>
      alive &&
      solid &&
      !kind.harmless &&
      state != EnemyStateKind.stunned &&
      state != EnemyStateKind.disguised &&
      !frozen;
}
