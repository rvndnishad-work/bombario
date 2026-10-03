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
  const ItemBurned(this.x, this.y, this.type);
  final int x;
  final int y;
  final ItemType type;
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
