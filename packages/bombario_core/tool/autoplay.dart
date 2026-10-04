// Plays the solo campaign with the autopilot and writes the inputs that
// clear each stage, for the app's playthrough recorder.
//
//   dart run tool/autoplay.dart [--seed 1] [--only 1-3] [--out plays.json]
import 'dart:convert';
import 'dart:io';

import 'package:bombario_core/autopilot.dart';
import 'package:bombario_core/bombario_core.dart';

void main(List<String> args) {
  var seed = 1;
  String? only;
  String? out;
  for (var i = 0; i < args.length - 1; i += 2) {
    switch (args[i]) {
      case '--seed':
        seed = int.parse(args[i + 1]);
      case '--only':
        only = args[i + 1];
      case '--out':
        out = args[i + 1];
    }
  }
  final run = CampaignAutoplay(seed: seed)..verbose = args.contains('-v');
  final plays = <StagePlay>[];
  var first = true;
  final watch = Stopwatch()..start();
  for (var i = 0; i < Campaign.stages.length; i++) {
    final id = Campaign.stages[i].id;
    if (only != null && !RegExp('^($only)\$').hasMatch(id)) continue;
    if (first && i > 0) run.loadoutFor(i);
    first = false;
    final t0 = watch.elapsedMilliseconds;
    plays.add(run.play(i, log: stdout.writeln));
    stdout.writeln(
        "  (${((watch.elapsedMilliseconds - t0) / 1000).toStringAsFixed(1)} s, ${run.rollouts} rollouts so far)");
  }
  final fair = plays.where((p) => p.cleared && !p.godMode).length;
  stdout.writeln(
      'cleared ${plays.where((p) => p.cleared).length}/${plays.length}, '
      '$fair without god mode, ${watch.elapsed.inSeconds} s');
  if (out != null) {
    File(out).writeAsStringSync(jsonEncode({
      'seed': seed,
      'stages': [for (final p in plays) p.toJson()],
    }));
  }
}
