import 'dart:async';

import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';

import '../game/world_renderer.dart';
import '../net/analytics.dart';
import '../net/online.dart';
import '../progress/achievements.dart';
import 'game_screen.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';
import 'player_name.dart';

/// The Daily Dungeon (§10): today's stage on the left, the world's fastest
/// clears on the right. Times are saved on the phone and sent to the room
/// server's leaderboard.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  late core.DailyDungeon _daily = core.DailyDungeon.today(widget.now);
  late Future<List<LeaderboardEntry>> _board = _load();
  Timer? _clock;
  int? _lastRank;

  @override
  void initState() {
    super.initState();
    // Tick the "new dungeon in" countdown, and roll over at midnight UTC.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final today = core.DailyDungeon.today(widget.now);
      setState(() {
        if (today.id != _daily.id) {
          _daily = today;
          _lastRank = null;
          _board = _load();
        }
      });
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Uri get _server => OnlineServer.parse(OnlineServer.url.value);

  Future<List<LeaderboardEntry>> _load() =>
      OnlineServer.leaderboard(_server, _daily.board);

  Future<void> _play() async {
    final achievements = AchievementsScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final timeMs = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (_) => GameScreen(daily: _daily)));
    if (timeMs == null || !mounted) return;
    final best = achievements.recordDaily(_daily.id, timeMs);
    Analytics.instance.log('daily_clear', {
      'day': _daily.id,
      'timeMs': timeMs,
      'best': best,
    });
    try {
      final rank = await OnlineServer.submitScore(
        _server,
        board: _daily.board,
        name: PlayerName.current,
        timeMs: timeMs,
      );
      if (!mounted) return;
      setState(() {
        _lastRank = rank;
        _board = _load();
      });
      messenger.showSnackBar(
        SnackBar(content: Text('${formatTime(timeMs)}: rank #$rank today')),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Time saved on this phone. $e')),
      );
    }
  }

  String _untilReset() {
    final now = (widget.now ?? DateTime.now()).toUtc();
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    final left = next.difference(now);
    return '${left.inHours}h ${(left.inMinutes % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final achievements = AchievementsScope.of(context);
    final best = achievements.dailyBest(_daily.id);
    final stage = _daily.stage;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Px.night,
        title: Text('Daily Dungeon', style: Px.title(12)),
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PxPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_daily.id, style: Px.label(11, color: Px.muted)),
                      const SizedBox(height: 4),
                      Text(stage.name, style: Px.title(14, color: Px.fuse)),
                      const SizedBox(height: 6),
                      Text(
                        'World ${stage.world} terrain. Same dungeon for '
                        'everyone today; the fastest clear wins.',
                        style: Px.label(12, bold: false),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (kind, count) in stage.enemies)
                            _EnemyChip(kind: kind, count: count),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        best == null
                            ? 'No clear yet today'
                            : 'Your best: ${formatTime(best)}'
                                  '${_lastRank == null ? '' : '  (#$_lastRank)'}',
                        style: Px.label(
                          13,
                          color: best == null ? Px.muted : Px.ok,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            key: const Key('daily-play'),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(best == null ? 'Play' : 'Try again'),
                            onPressed: _play,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'New dungeon in ${_untilReset()}',
                            style: Px.label(11, color: Px.muted, bold: false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 300,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: PxPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'TODAY\'S FASTEST',
                              style: Px.label(12, color: Px.fuse),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh',
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: () => setState(() => _board = _load()),
                          ),
                        ],
                      ),
                      Expanded(
                        child: FutureBuilder<List<LeaderboardEntry>>(
                          future: _board,
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snap.hasError) {
                              return Text(
                                'Leaderboard offline. Your times are saved '
                                'on this phone.',
                                style: Px.label(
                                  12,
                                  color: Px.muted,
                                  bold: false,
                                ),
                              );
                            }
                            final rows = snap.data!;
                            if (rows.isEmpty) {
                              return Text(
                                'No times yet. Be the first!',
                                style: Px.label(
                                  12,
                                  color: Px.muted,
                                  bold: false,
                                ),
                              );
                            }
                            return ListView(
                              children: [
                                for (final e in rows) _BoardRow(entry: e),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnemyChip extends StatelessWidget {
  const _EnemyChip({required this.kind, required this.count});

  final core.EnemyKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final sprite = WorldRenderer.enemySprites[kind.name] ?? 'skull';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Px.ink,
        border: Border.all(color: Px.edge, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpriteIcon(sprite, size: 22),
          const SizedBox(width: 4),
          Text('${kind.name} x$count', style: Px.label(11, bold: false)),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final me = entry.name == PlayerName.current;
    final colour = entry.rank == 1 ? Px.fuse : (me ? Px.ok : Px.paper);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text('#${entry.rank}', style: Px.label(12, color: colour)),
          ),
          Expanded(
            child: Text(
              entry.name,
              style: Px.label(12, color: colour, bold: me),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(formatTime(entry.timeMs), style: Px.label(12, color: colour)),
        ],
      ),
    );
  }
}
