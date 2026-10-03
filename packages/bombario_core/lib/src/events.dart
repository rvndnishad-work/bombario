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
