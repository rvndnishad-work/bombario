import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One finished run on a leaderboard.
class ScoreEntry {
  ScoreEntry({
    required this.name,
    required this.timeMs,
    required this.players,
    required this.at,
  });

  final String name;
  final int timeMs;
  final int players;

  /// When it was submitted (ms since epoch); breaks ties, earliest first.
  final int at;

  Map<String, dynamic> toJson() =>
      {'name': name, 'timeMs': timeMs, 'players': players, 'at': at};

  static ScoreEntry fromJson(Map<String, dynamic> j) => ScoreEntry(
        name: j['name'] as String,
        timeMs: j['timeMs'] as int,
        players: j['players'] as int,
        at: j['at'] as int? ?? 0,
      );

  String get _key => '${name.toLowerCase()}/$players';
}

/// Why a score was refused.
class ScoreRejected implements Exception {
  ScoreRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fastest-time leaderboards (Daily Dungeon, §7.x), one per board name such
/// as `daily-2026-10-03`.
///
/// Scores are client-reported and can be spoofed until player accounts and
/// server-verified runs exist; treat the boards as for fun.
///
/// Each board keeps one entry per name and player count (the best time) and
/// at most [maxEntries] entries. With a [dataDir] every board is saved to
/// `<dataDir>/leaderboards/<board>.json` and loaded on first use; without
/// one, boards live in memory only.
class Leaderboards {
  Leaderboards({this.dataDir, this.maxEntries = 500, this.maxBoards = 5000});

  final String? dataDir;
  final int maxEntries;

  /// Boards kept in memory at once; new boards beyond this are refused.
  final int maxBoards;

  final Map<String, List<ScoreEntry>> _boards = {};
  final Map<String, Future<void>> _writes = {};

  static final boardPattern = RegExp(r'^[a-z0-9-]{1,40}$');
  static const int maxTimeMs = 3600000;
  static const int maxNameLength = 16;

  static bool validBoard(String board) => boardPattern.hasMatch(board);

  /// Adds a run and returns its rank (1 is fastest). A run slower than the
  /// same player's best keeps the best on the board but still gets the rank
  /// its own time would have. Throws [ScoreRejected] for bad input.
  Future<int> submit({
    required String board,
    required String name,
    required int timeMs,
    required int players,
  }) async {
    if (!validBoard(board)) throw ScoreRejected('bad board');
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNameLength) {
      throw ScoreRejected('name must be 1-$maxNameLength characters');
    }
    if (timeMs < 1 || timeMs > maxTimeMs) {
      throw ScoreRejected('timeMs must be 1..$maxTimeMs');
    }
    if (players < 1 || players > 4) {
      throw ScoreRejected('players must be 1..4');
    }
    final entries = await _load(board, create: true);
    final entry = ScoreEntry(
      name: trimmed,
      timeMs: timeMs,
      players: players,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    final rank = 1 +
        entries.where((e) => e._key != entry._key && e.timeMs <= timeMs).length;
    final mine = entries.indexWhere((e) => e._key == entry._key);
    if (mine >= 0 && entries[mine].timeMs <= timeMs) return rank;
    if (mine >= 0) entries.removeAt(mine);
    entries
      ..add(entry)
      ..sort(_order);
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    _save(board, entries);
    return rank;
  }

  /// The fastest [limit] entries, ranked.
  Future<List<(int, ScoreEntry)>> top(String board, {int limit = 20}) async {
    if (!validBoard(board)) throw ScoreRejected('bad board');
    final entries = await _load(board, create: false);
    return [
      for (var i = 0; i < entries.length && i < limit; i++) (i + 1, entries[i]),
    ];
  }

  static int _order(ScoreEntry a, ScoreEntry b) {
    final t = a.timeMs.compareTo(b.timeMs);
    return t != 0 ? t : a.at.compareTo(b.at);
  }

  File? _file(String board) {
    final dir = dataDir;
    if (dir == null) return null;
    return File('$dir/leaderboards/$board.json');
  }

  Future<List<ScoreEntry>> _load(String board, {required bool create}) async {
    final cached = _boards[board];
    if (cached != null) return cached;
    var entries = <ScoreEntry>[];
    final file = _file(board);
    if (file != null && await file.exists()) {
      try {
        final list = jsonDecode(await file.readAsString()) as List;
        entries = [
          for (final e in list) ScoreEntry.fromJson(e as Map<String, dynamic>),
        ]..sort(_order);
      } on Object {
        entries = []; // a damaged file starts the board afresh
      }
    } else if (!create) {
      return const [];
    }
    if (_boards.length >= maxBoards) {
      // Forget the least recently loaded board; it is on disk if saved.
      if (dataDir == null) throw ScoreRejected('too many boards');
      _boards.remove(_boards.keys.first);
    }
    return _boards[board] = entries;
  }

  void _save(String board, List<ScoreEntry> entries) {
    final file = _file(board);
    if (file == null) return;
    final json = jsonEncode([for (final e in entries) e.toJson()]);
    // Writes to one board happen in order; each replaces the file whole.
    _writes[board] = (_writes[board] ?? Future.value()).then((_) async {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    }).catchError((Object e) {
      stderr.writeln('leaderboard $board not saved: $e');
    });
  }

  /// Waits for pending writes (tests and shutdown).
  Future<void> flush() => Future.wait(_writes.values);
}
