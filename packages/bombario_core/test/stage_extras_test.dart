import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

import 'world_test.dart' show run;

/// Stages 5, 10 ... 50 rotate treasure, mini-boss and challenge.
void main() {
  World stage(String id, {int players = 1, bool coop = false}) {
    final s = Campaign.byId(id)!;
    return World(s.level(seed: 4, players: players),
        seed: 4, config: s.config(players: players, coop: coop));
  }

  test('every fifth stage gets an extra, in rotation', () {
    final extras = {
      for (final s in Campaign.stages)
        if (s.extra != null) s.campaignNumber: s.extra,
    };
    expect(extras.keys, [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]);
    expect(extras.values.take(4), [
      StageExtra.treasure,
      StageExtra.miniBoss,
      StageExtra.challenge,
      StageExtra.treasure,
    ]);
    expect(Campaign.byId('1-4')!.extra, isNull);
    expect(DailyDungeon.forDate(DateTime(2026, 10, 3)).stage.extra, isNull);
  });

  test('the chest blocks, takes three bombs, and drops a rare power-up', () {
    final w = stage('1-5');
    final p = w.addPlayer()..godMode = true;
    final chest = w.treasure!;
    expect(w.grid.isWalkable(chest.x, chest.y), isTrue);
    p.setPosition(chest.x - 0.5, chest.y + 0.5);
    p.fireRange = 1;
    final opened = <TreasureOpened>[];
    for (var i = 0; i < Treasure.maxHp; i++) {
      // Stand next to the chest (left), bomb, and let it blow.
      p.setPosition(chest.x - 0.5, chest.y + 0.5);
      w.bombs.add(Bomb(
          id: 900 + i,
          x: chest.x - 1,
          y: chest.y,
          ownerId: p.id,
          range: 1,
          fuse: 0.01,
          remote: false));
      opened.addAll(run(w, 0.2).whereType<TreasureOpened>());
    }
    expect(opened, hasLength(1));
    expect(w.treasure, isNull);
    expect(World.rareItems, contains(opened.single.item));
    expect(w.floorItems.any((i) => i.x == chest.x && i.y == chest.y), isTrue);
    expect(p.score, greaterThanOrEqualTo(World.treasurePoints));
  });

  test('the mini-boss is tougher, drops loot, and must die to clear', () {
    final w = stage('1-10');
    final p = w.addPlayer();
    final mini = w.enemies.singleWhere((e) => e.id == w.miniBossId);
    expect(mini.kind, EnemyKind.grinface);
    expect(mini.maxHp, greaterThan(EnemyKind.grinface.hp));
    w.enemies.firstWhere((e) => e.kind.boss).alive = false;
    expect(run(w, 0.1).whereType<StageCleared>(), isEmpty);
    mini.hp = 1;
    w.flames.add(Flame(x: mini.tileX, y: mini.tileY, ownerId: p.id));
    final events = run(w, 0.2);
    expect(events.whereType<MiniBossDefeated>(), hasLength(1));
    expect(events.whereType<StageCleared>(), hasLength(1));
  });

  test('a clean challenge pays points and a co-op life; a hit cancels it', () {
    final clean = stage('2-5', coop: true);
    clean.addPlayer().godMode = true;
    final lives = clean.livesLeft;
    clean.timeLeft = 0.05;
    final events = run(clean, 0.2);
    expect(events.whereType<ChallengeComplete>(), hasLength(1));
    expect(clean.livesLeft, lives + 1);

    final hit = stage('2-5');
    final p = hit.addPlayer();
    final e = hit.spawnEnemy(p.tile, EnemyKind.puffball);
    e.setPosition(p.x, p.y);
    expect(run(hit, 0.2).whereType<ChallengeFailed>(), hasLength(1));
    hit.timeLeft = 0.05;
    expect(run(hit, 0.2).whereType<ChallengeComplete>(), isEmpty);
  });

  test('the chest rides in snapshots', () {
    final w = stage('1-5')..addPlayer();
    final snap = WorldSnapshot.fromJson(WorldSnapshot.of(w).toJson());
    expect(snap.chest, (w.treasure!.x, w.treasure!.y, Treasure.maxHp));
  });
}
