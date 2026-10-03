import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One achievement. [sprite] names its icon in the sprite atlas.
class AchievementDef {
  const AchievementDef(this.id, this.title, this.description, this.sprite);

  final String id;
  final String title;
  final String description;
  final String sprite;
}

/// Local achievements and lifetime stats (§12), saved on the device. Game
/// Center and Google Play Games can mirror these once accounts exist.
///
/// Games report what happened through the `record…` methods; each returns
/// the achievements it just unlocked so the game can announce them.
class Achievements extends ChangeNotifier {
  Achievements._(this._prefs);

  /// Achievements that live only in memory, for tests and previews.
  Achievements.memory() : _prefs = null;

  static Future<Achievements> load() async {
    final a = Achievements._(await SharedPreferences.getInstance());
    a._read();
    return a;
  }

  final SharedPreferences? _prefs;
  final Set<String> unlocked = {};
  final Map<String, int> stats = {};

  // Stat keys.
  static const bombsPlaced = 'bombsPlaced';
  static const itemsPicked = 'itemsPicked';
  static const chainRecord = 'chainRecord';
  static const revives = 'revives';
  static const friendlyKills = 'friendlyKills';
  static const stagesCleared = 'stagesCleared';
  static const versusWins = 'versusWins';

  static final List<AchievementDef> all = [
    const AchievementDef(
      'first-spark',
      'First Spark',
      'Clear stage 1-1.',
      'fc',
    ),
    for (var w = 1; w <= 5; w++)
      AchievementDef(
        'world-$w',
        'World $w cleared',
        'Beat the boss at stage $w-10.',
        'crown',
      ),
    for (final k in core.EnemyKind.all.where((k) => k.boss))
      AchievementDef(
        'boss-${_slug(k.name)}',
        '${k.name} down',
        'Defeat ${k.name}.',
        'star',
      ),
    const AchievementDef(
      'chain-3',
      'Chain reaction',
      'Set off 3 or more bombs in one blast.',
      'bombr',
    ),
    const AchievementDef(
      'angry-door',
      'Knock knock',
      'Bomb the exit and still clear the stage.',
      'doorWarden',
    ),
    const AchievementDef('kicker', 'Penalty kick', 'Kick a bomb.', 'pu-kick'),
    const AchievementDef(
      'frosty',
      'Cold snap',
      'Freeze an enemy with a frost bomb.',
      'pu-frost',
    ),
    const AchievementDef(
      'haunt',
      'Boo!',
      'Haunt an enemy while you are a ghost.',
      'spirit',
    ),
    const AchievementDef(
      'back-on-feet',
      'Back on your feet',
      'Revive a teammate, or get revived.',
      'tomb',
    ),
    const AchievementDef(
      'versus-win',
      'Last one standing',
      'Win a versus round.',
      'swords',
    ),
    const AchievementDef(
      'bomber-100',
      'Bomb squad',
      'Place 100 bombs.',
      'pu-bomb',
    ),
    const AchievementDef(
      'collector-50',
      'Treasure hunter',
      'Pick up 50 power-ups.',
      'pu-sonar',
    ),
  ];

  static String _slug(String name) =>
      name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');

  static AchievementDef? byId(String id) =>
      all.where((a) => a.id == id).firstOrNull;

  int stat(String key) => stats[key] ?? 0;

  // ------------------------------------------------------------- recording

  bool _exitBombed = false;

  /// Feeds one simulation tick's events from a game this phone runs.
  List<AchievementDef> recordEvents(
    List<core.GameEvent> events, {
    required int myId,
    required String stageId,
    bool coop = true,
  }) {
    final got = <AchievementDef>[];
    var blasts = 0;
    for (final e in events) {
      switch (e) {
        case core.BombPlaced(:final bomb) when bomb.ownerId == myId:
          _bump(bombsPlaced, got);
        case core.BombExploded():
          blasts++;
        case core.ItemPicked(:final playerId) when playerId == myId:
          _bump(itemsPicked, got);
        case core.ExitBombed():
          _exitBombed = true;
        case core.BombKicked(:final playerId) when playerId == myId:
          _unlock('kicker', got);
        case core.EnemyFrozen():
          _unlock('frosty', got);
        case core.Haunted(:final playerId) when playerId == myId:
          _unlock('haunt', got);
        case core.PlayerRevived(:final playerId, :final byPlayerId)
            when playerId == myId || byPlayerId == myId:
          _bump(revives, got);
          _unlock('back-on-feet', got);
        case core.PlayerDied(:final playerId, :final killerId)
            when coop && killerId == myId && playerId != myId:
          _bump(friendlyKills, got);
        case core.EnemyDied(:final enemy) when enemy.kind.boss:
          _unlock('boss-${_slug(enemy.kind.name)}', got);
        case core.StageCleared():
          got.addAll(recordStageCleared(stageId));
        default:
          break;
      }
    }
    if (blasts >= 3) _unlock('chain-3', got);
    if (blasts > stat(chainRecord)) _set(chainRecord, blasts);
    if (got.isNotEmpty) _save();
    return got;
  }

  /// A new stage started; forgets per-stage progress.
  void startStage() => _exitBombed = false;

  List<AchievementDef> recordStageCleared(String stageId) {
    final got = <AchievementDef>[];
    _bump(stagesCleared, got);
    if (stageId == '1-1') _unlock('first-spark', got);
    final parts = stageId.split('-');
    if (parts.length == 2 && parts[1] == '10') {
      _unlock('world-${parts[0]}', got);
    }
    if (_exitBombed) _unlock('angry-door', got);
    _exitBombed = false;
    _save();
    return got;
  }

  List<AchievementDef> recordVersusWin() {
    final got = <AchievementDef>[];
    _bump(versusWins, got);
    _unlock('versus-win', got);
    _save();
    return got;
  }

  /// Room play only sees snapshots: compares this player's state across two
  /// of them for the moments that matter here.
  List<AchievementDef> recordRoomChange(
    core.PlayerState? before,
    core.PlayerState? after,
  ) {
    final got = <AchievementDef>[];
    if (before == null || after == null) return got;
    if (after.ghost == false && after.alive && before.ghost) {
      _bump(revives, got);
      _unlock('back-on-feet', got);
    }
    if (after.hauntUsed && !before.hauntUsed) _unlock('haunt', got);
    if (after.alive &&
        before.alive &&
        (after.maxBombs > before.maxBombs ||
            after.fireRange > before.fireRange ||
            after.speed > before.speed ||
            after.hearts > before.hearts ||
            after.active != before.active)) {
      _bump(itemsPicked, got);
    }
    if (got.isNotEmpty) _save();
    return got;
  }

  /// Counts a bomb this player dropped in a room.
  void recordRoomBomb() {
    final got = <AchievementDef>[];
    _bump(bombsPlaced, got);
    if (got.isNotEmpty) _save();
  }

  /// Best Daily Dungeon clear for [dayId] (`YYYY-MM-DD`) in milliseconds.
  int? dailyBest(String dayId) {
    final v = stat('daily.$dayId');
    return v > 0 ? v : null;
  }

  /// Saves a Daily Dungeon clear; true when it beats the day's best.
  bool recordDaily(String dayId, int timeMs) {
    final best = dailyBest(dayId);
    if (best != null && best <= timeMs) return false;
    _set('daily.$dayId', timeMs);
    return true;
  }

  void _bump(String key, List<AchievementDef> got) {
    _set(key, stat(key) + 1);
    if (key == bombsPlaced && stat(key) >= 100) _unlock('bomber-100', got);
    if (key == itemsPicked && stat(key) >= 50) _unlock('collector-50', got);
  }

  void _set(String key, int value) {
    stats[key] = value;
    _prefs?.setInt('stat.$key', value);
    notifyListeners();
  }

  void _unlock(String id, List<AchievementDef> got) {
    final def = byId(id);
    if (def == null || !unlocked.add(id)) return;
    got.add(def);
    notifyListeners();
  }

  void _read() {
    final p = _prefs;
    if (p == null) return;
    unlocked.addAll(p.getStringList('achievements') ?? const []);
    for (final key in p.getKeys().where((k) => k.startsWith('stat.'))) {
      stats[key.substring(5)] = p.getInt(key) ?? 0;
    }
  }

  void _save() => _prefs?.setStringList('achievements', unlocked.toList());
}

/// Puts [Achievements] in the widget tree.
class AchievementsScope extends InheritedNotifier<Achievements> {
  const AchievementsScope({
    super.key,
    required Achievements achievements,
    required super.child,
  }) : super(notifier: achievements);

  static Achievements of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AchievementsScope>()
          ?.notifier ??
      _fallback;

  static Achievements read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AchievementsScope>()?.notifier ??
      _fallback;

  static final _fallback = Achievements.memory();
}
