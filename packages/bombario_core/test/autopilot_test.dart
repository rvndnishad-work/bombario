import 'package:bombario_core/autopilot.dart';
import 'package:bombario_core/bombario_core.dart';
import 'package:test/test.dart';

void main() {
  test('autopilot clears 1-1 without god mode, and the inputs replay', () {
    final run = CampaignAutoplay();
    final play = run.play(0);
    expect(play.cleared, isTrue);
    expect(play.godMode, isFalse);

    // Feeding the recorded inputs to a fresh world clears it again.
    final def = Campaign.stages[0];
    final world = World(def.level(seed: play.seed, players: 1),
        seed: play.seed, config: def.config(players: 1, coop: false));
    final p = world.addPlayer(name: 'You');
    for (final v in play.inputs) {
      while (world.over && !world.cleared) {
        world.respawn(p);
        world.clearFailure();
      }
      world.tick({p.id: StagePlay.decode(v)});
    }
    expect(world.cleared, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
