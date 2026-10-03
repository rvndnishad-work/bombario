import 'direction.dart';
import 'entities.dart';

/// Things that happened during a tick. The renderer, audio and the network
/// layer consume these; the simulation never depends on them.
sealed class GameEvent {
  const GameEvent();
}

class BombPlaced extends GameEvent {
  const BombPlaced(this.bomb);
  final Bomb bomb;
}

class BombExploded extends GameEvent {
  const BombExploded(this.x, this.y, this.ownerId);
  final int x;
  final int y;
  final int ownerId;
}

class BrickDestroyed extends GameEvent {
  const BrickDestroyed(this.x, this.y, this.revealed);
  final int x;
  final int y;
  final ItemType? revealed;
}

class ItemPicked extends GameEvent {
  const ItemPicked(this.playerId, this.type);
  final int playerId;
  final ItemType type;
}

class ItemBurned extends GameEvent {
  const ItemBurned(this.x, this.y, this.type, {this.releasedWave = false});
  final int x;
  final int y;
  final ItemType type;

  /// It was a power-up uncovered from a brick, so enemies poured out.
  final bool releasedWave;
}

class PlayerDied extends GameEvent {
  const PlayerDied(this.playerId, this.killerId);
  final int playerId;

  /// Player id whose bomb did it, -1 for an enemy touch, -2 for a hazard.
  final int killerId;
}

class EnemyDied extends GameEvent {
  const EnemyDied(this.enemy, this.killerId);
  final Enemy enemy;
  final int killerId;
}

class EnemySpawned extends GameEvent {
  const EnemySpawned(this.enemy);
  final Enemy enemy;
}

class ExitBombed extends GameEvent {
  const ExitBombed();
}

/// A bomb hit the treasure chest; [hp] hits are left.
class TreasureHit extends GameEvent {
  const TreasureHit(this.x, this.y, this.hp);
  final int x;
  final int y;
  final int hp;
}

/// The chest broke open and dropped [item].
class TreasureOpened extends GameEvent {
  const TreasureOpened(this.x, this.y, this.item);
  final int x;
  final int y;
  final ItemType item;
}

/// The mini-boss is down and dropped [item].
class MiniBossDefeated extends GameEvent {
  const MiniBossDefeated(this.x, this.y, this.item);
  final int x;
  final int y;
  final ItemType item;
}

/// Someone got hit on a challenge stage: no reward this time.
class ChallengeFailed extends GameEvent {
  const ChallengeFailed();
}

/// The stage cleared with nobody hit: points and a life.
class ChallengeComplete extends GameEvent {
  const ChallengeComplete();
}

/// A player sank into the pipe at (x, y), heading for (toX, toY).
class PipeEntered extends GameEvent {
  const PipeEntered(this.playerId, this.x, this.y, this.toX, this.toY);
  final int playerId;
  final int x;
  final int y;
  final int toX;
  final int toY;
}

/// A player is rising out of the pipe at (x, y).
class PipeExited extends GameEvent {
  const PipeExited(this.playerId, this.x, this.y);
  final int playerId;
  final int x;
  final int y;
}

class TimeUp extends GameEvent {
  const TimeUp();
}

class StageCleared extends GameEvent {
  const StageCleared();
}

class StageFailed extends GameEvent {
  const StageFailed();
}

/// Versus round over. [winnerId] is -1 for a draw.
class MatchEnded extends GameEvent {
  const MatchEnded(this.winnerId);
  final int winnerId;
}

/// A Heart absorbed a hit.
class HeartLost extends GameEvent {
  const HeartLost(this.playerId);
  final int playerId;
}

/// A player became a ghost (co-op) and left a tombstone.
class BecameGhost extends GameEvent {
  const BecameGhost(this.playerId);
  final int playerId;
}

/// A ghost was brought back, by standing on the tombstone or by Tether.
class PlayerRevived extends GameEvent {
  const PlayerRevived(this.playerId, this.byPlayerId);
  final int playerId;
  final int byPlayerId;
}

class BombKicked extends GameEvent {
  const BombKicked(this.playerId, this.x, this.y);
  final int playerId;
  final int x;
  final int y;
}

class PlayerFrozen extends GameEvent {
  const PlayerFrozen(this.playerId);
  final int playerId;
}

class EnemyFrozen extends GameEvent {
  const EnemyFrozen(this.enemy);
  final Enemy enemy;
}

/// A ghost slowed an enemy.
class Haunted extends GameEvent {
  const Haunted(this.playerId, this.enemyId);
  final int playerId;
  final int enemyId;
}

class Pinged extends GameEvent {
  const Pinged(this.playerId, this.kind, this.x, this.y);
  final int playerId;
  final PingKind kind;
  final int x;
  final int y;
}

class SonarPulse extends GameEvent {
  const SonarPulse(this.playerId, this.x, this.y);
  final int playerId;
  final int x;
  final int y;
}

/// A falling rock landed (World 2 hazard).
class RockFell extends GameEvent {
  const RockFell(this.x, this.y);
  final int x;
  final int y;
}

class FloorCollapsed extends GameEvent {
  const FloorCollapsed(this.x, this.y);
  final int x;
  final int y;
}

/// Flipped a Shellback, or a boss changed phase.
class EnemyStunned extends GameEvent {
  const EnemyStunned(this.enemy);
  final Enemy enemy;
}

class BossDamaged extends GameEvent {
  const BossDamaged(this.enemy);
  final Enemy enemy;
}

// ------------------------------------------------------- Worlds 3 to 5

/// A Mimic dropped its disguise (Sonar, or it bit someone).
class EnemyRevealed extends GameEvent {
  const EnemyRevealed(this.enemy);
  final Enemy enemy;
}

/// A Kicker Crab kicked a bomb.
class EnemyKickedBomb extends GameEvent {
  const EnemyKickedBomb(this.enemy, this.x, this.y);
  final Enemy enemy;
  final int x;
  final int y;
}

/// A Fuse Eater swallowed a bomb.
class BombEaten extends GameEvent {
  const BombEaten(this.enemy, this.x, this.y);
  final Enemy enemy;
  final int x;
  final int y;
}

/// An enemy or boss blinked from one tile to another.
class EnemyTeleported extends GameEvent {
  const EnemyTeleported(this.enemy, this.fromX, this.fromY);
  final Enemy enemy;
  final int fromX;
  final int fromY;
}

/// A player went through a warp door.
class PlayerWarped extends GameEvent {
  const PlayerWarped(this.playerId, this.fromX, this.fromY, this.toX, this.toY);
  final int playerId;
  final int fromX;
  final int fromY;
  final int toX;
  final int toY;
}

/// Steam vents fired their jets (World 3).
class VentsFired extends GameEvent {
  const VentsFired();
}

/// A pressure plate opened the gates (World 3).
class GatesOpened extends GameEvent {
  const GatesOpened(this.x, this.y);
  final int x;
  final int y;
}

/// A possessed brick grew back (World 4).
class BrickRegrew extends GameEvent {
  const BrickRegrew(this.x, this.y);
  final int x;
  final int y;
}

/// A cannon shot swept row [y] (World 5).
class CannonFired extends GameEvent {
  const CannonFired(this.y, {required this.fromLeft});
  final int y;
  final bool fromLeft;
}

/// The wind changed; [Direction.none] means calm.
class WindChanged extends GameEvent {
  const WindChanged(this.direction);
  final Direction direction;
}

/// The Lantern Witch possessed a player: controls reversed.
class PlayerCursed extends GameEvent {
  const PlayerCursed(this.playerId);
  final int playerId;
}

class CurseLifted extends GameEvent {
  const CurseLifted(this.playerId);
  final int playerId;
}

/// Overlord Pontan's arena closed in on this tile.
class ArenaShrank extends GameEvent {
  const ArenaShrank(this.x, this.y);
  final int x;
  final int y;
}

/// A boss starts an attack; [attack] is a short name: `ring`, `lines`,
/// `summon`, `curse`, `split`, `dive`, `blink`.
class BossAttack extends GameEvent {
  const BossAttack(this.enemy, this.attack);
  final Enemy enemy;
  final String attack;
}
