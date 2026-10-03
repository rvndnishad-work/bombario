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
    if (b != null && b.alive) _movement.move(b, input.direction, World.tickDt);
    return _seq;
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
    if (b.alive) {
      for (final p in _pending) {
        _movement.move(b, p.input.direction, World.tickDt);
      }
    }
    final old = _body;
    // Tiny disagreements come from tick phase differences; keep the smooth
    // local value rather than jittering by a few pixels.
    if (old != null &&
        old.alive == b.alive &&
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
