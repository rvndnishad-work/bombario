import 'direction.dart';
import 'entities.dart';

/// One frame of input from a player. Clients send these to the authority;
/// they never send positions.
class PlayerInput {
  const PlayerInput({
    this.direction = Direction.none,
    this.placeBomb = false,
    this.action = false,
    this.ping = PingKind.none,
  });

  static const idle = PlayerInput();

  final Direction direction;

  /// True on the frame the bomb button was pressed (edge, not level).
  final bool placeBomb;

  /// Context action: detonate (Remote), stop a kicked bomb, etc.
  final bool action;

  /// A quick-chat ping sent this frame, shown at the player's position.
  final PingKind ping;

  PlayerInput copyWith({
    Direction? direction,
    bool? placeBomb,
    bool? action,
    PingKind? ping,
  }) {
    return PlayerInput(
      direction: direction ?? this.direction,
      placeBomb: placeBomb ?? this.placeBomb,
      action: action ?? this.action,
      ping: ping ?? this.ping,
    );
  }
}
