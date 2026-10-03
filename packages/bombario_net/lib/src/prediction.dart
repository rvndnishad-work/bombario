import 'package:bombario_core/bombario_core.dart';

/// Client-side prediction for the local player.
///
/// The client applies its own inputs immediately to a predicted body, and
/// when a server snapshot arrives it resets the body to the server's state
/// and re-applies every input the server has not acknowledged yet. Movement
/// uses the same [Movement] rules as the server, so corrections are rare and
/// tiny on a good connection. Bombs, flames, deaths and pickups are never
/// predicted; the server decides those.
class LocalPredictor {
  LocalPredictor({this.maxPending = 90});

  /// Inputs kept for re-application; ~3 s at 30 Hz.
  final int maxPending;

  final List<_PendingInput> _pending = [];
  Player? _body;
  WorldSnapshot? _snapshot;
  int _seq = 0;

  /// Position of the predicted local player, or null before the first snapshot.
  Player? get body => _body;
  int get pendingCount => _pending.length;

  late final Movement _movement = Movement(_isSolid);

  bool _isSolid(Player p, int x, int y) {
    final snap = _snapshot;
    if (snap == null) return true;
    final t = snap.grid.at(x, y);
    if (t == TileType.pillar) return true;
    if (p.ghost) return false; // ghosts float through everything else
    if (t == TileType.pit) return true;
    if (t == TileType.brick && !p.wallPass) return true;
    if (!p.bombPass && snap.bombAt(x, y)) {
      // The server lets a player keep walking off a bomb they overlap; the
      // snapshot doesn't say which, so overlap is the approximation.
      const h = Player.halfBox;
      final overlaps = (p.x - (x + 0.5)).abs() < 0.5 + h &&
          (p.y - (y + 0.5)).abs() < 0.5 + h;
      return !overlaps;
    }
    return false;
  }

  /// Stamps [input] with a sequence number, predicts it and returns the
  /// stamped sequence to send to the server.
  int apply(PlayerInput input) {
    _seq++;
    _pending.add(_PendingInput(_seq, input));
    if (_pending.length > maxPending) _pending.removeAt(0);
    final b = _body;
    if (b != null) _step(b, input);
    return _seq;
  }

  /// One tick of movement, mirroring [World.tick]: ghosts float, the
  /// frozen stand still, the dead don't move.
  void _step(Player b, PlayerInput input) {
    if (b.ghost) {
      _movement.move(b, input.direction, World.tickDt);
      return;
    }
    if (!b.alive) return;
    if (b.cursedFor > 0) b.cursedFor -= World.tickDt;
    if (b.frozenFor > 0) {
      b.frozenFor -= World.tickDt;
      return;
    }
    // Same terrain rules as the server: curse, ice, wind and conveyors.
    final snap = _snapshot;
    _movement.step(
      b,
      input.direction,
      World.tickDt,
      grid: snap?.grid,
      wind: snap?.wind ?? Direction.none,
    );
  }

  /// Reconciles with an authoritative snapshot.
  void onSnapshot(WorldSnapshot snapshot, int myPlayerId) {
    _snapshot = snapshot;
    final me = snapshot.player(myPlayerId);
    if (me == null) {
      _body = null;
      return;
    }
    final b = me.toPlayer();
    _pending.removeWhere((p) => p.seq <= me.ackedInput);
    for (final p in _pending) {
      _step(b, p.input);
    }
    final old = _body;
    // Tiny disagreements come from tick phase differences; keep the smooth
    // local value rather than jittering by a few pixels.
    if (old != null &&
        old.alive == b.alive &&
        old.ghost == b.ghost &&
        (old.x - b.x).abs() < 0.08 &&
        (old.y - b.y).abs() < 0.08) {
      b.setPosition(old.x, old.y);
    }
    _body = b;
  }

  /// Forgets everything, e.g. when a new match starts.
  void reset() {
    _pending.clear();
    _body = null;
    _snapshot = null;
    _seq = 0;
  }
}

class _PendingInput {
  const _PendingInput(this.seq, this.input);
  final int seq;
  final PlayerInput input;
}
