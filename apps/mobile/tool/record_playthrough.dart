// Records autopilot playthroughs of the solo campaign from the real game
// screen, frame by frame, into a video plus a list of sound cues.
//
// 1. Solve the stages headlessly (packages/bombario_core):
//      dart run tool/autoplay.dart --out /tmp/plays.json
// 2. Record a range of them here (needs ffmpeg on the PATH):
//      PLAYS=/tmp/plays.json FROM=0 TO=9 OUT=/tmp/world1 \
//        flutter test tool/record_playthrough.dart
//    OUT.mp4 (silent) and OUT.cues.json are written; FRAMES=1 writes PNGs
//    every second instead, for a quick look.
// 3. Mix the soundtrack and mux it in:
//      python3 tool/mix_playthrough_audio.py /tmp/world1
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bombario/audio/game_audio.dart';
import 'package:bombario/game/blast_game.dart';
import 'package:bombario/game/game_pilot.dart';
import 'package:bombario/game/sprite_atlas.dart';
import 'package:bombario/ui/game_screen.dart';
import 'package:bombario_core/autopilot.dart';
import 'package:bombario_core/bombario_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const fps = 30;
const frame = Duration(microseconds: 1000000 ~/ fps + 1);

/// Replays the solved stages; anything else plays itself idle.
class ReplayPilot implements GamePilot {
  ReplayPilot(this.plays);

  final Map<int, StagePlay> plays;
  StagePlay? current;
  int cursor = 0;
  int ticks = 0;

  @override
  void onStage(int stageIndex, core.World sim, core.Player player) {
    current = plays[stageIndex];
    cursor = 0;
    final play = current;
    if (play == null) return;
    // Start exactly as the solver did, whatever came before.
    player.items
      ..clear()
      ..addAll(play.startItems);
    player.recomputeStats();
    player.active = play.startActive;
    player.hearts = play.startHearts;
    player.godMode = play.godMode;
  }

  @override
  core.PlayerInput next() {
    ticks++;
    final play = current;
    if (play == null || cursor >= play.inputs.length) {
      return core.PlayerInput.idle;
    }
    return StagePlay.decode(play.inputs[cursor++]);
  }
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }

  await load('PressStart2P', ['assets/fonts/PressStart2P-Regular.ttf']);
  await load('Silkscreen', [
    'assets/fonts/Silkscreen-Regular.ttf',
    'assets/fonts/Silkscreen-Bold.ttf',
  ]);
  await load('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
  // Plain text in the Material theme falls back to Roboto; any real font
  // beats the test font's boxes.
  await load('Roboto', ['assets/fonts/Silkscreen-Regular.ttf']);
}

void main() {
  final env = Platform.environment;
  final from = int.parse(env['FROM'] ?? '0');
  final to = int.parse(env['TO'] ?? '$from');
  // How long to show a stage the solver could not clear.
  final failSeconds = int.parse(env['FAIL_SECONDS'] ?? '90');
  final out = env['OUT'] ?? '/tmp/playthrough';
  final pngs = env['FRAMES'] == '1';
  final width = int.parse(env['WIDTH'] ?? '1280');
  final height = int.parse(env['HEIGHT'] ?? '720');

  testWidgets('record playthrough', (tester) async {
    final json =
        jsonDecode(File(env['PLAYS']!).readAsStringSync())
            as Map<String, dynamic>;
    final seed = json['seed'] as int;
    final plays = {
      for (final j in (json['stages'] as List).cast<Map<String, dynamic>>())
        j['index'] as int: StagePlay.fromJson(j),
    };
    final pilot = ReplayPilot(plays);

    tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);
    await tester.runAsync(SpriteAtlas.load);

    var frameNo = 0;
    final cues = <List<Object>>[];
    GameAudio.cueListener = (cue, file) => cues.add([frameNo, cue, file]);

    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: boundary,
          child: GameScreen(seed: seed, startStage: from),
        ),
      ),
    );
    final game =
        (tester.state(find.byType(GameScreen)) as dynamic).game as BlastGame;
    game.pilot = pilot;
    // The first stage was set up before the pilot was in: set it up again.
    game.goToStage(from);

    // Frames go to ffmpeg through a named pipe with plain blocking
    // writes: async pipes don't get serviced inside the test's fake clock.
    Process? ffmpeg;
    RandomAccessFile? video;
    if (!pngs) {
      final fifo = '$out.frames';
      if (File(fifo).existsSync()) File(fifo).deleteSync();
      Process.runSync('mkfifo', [fifo]);
      ffmpeg = await tester.runAsync(
        () => Process.start('ffmpeg', [
          '-y',
          '-loglevel',
          'error',
          '-f',
          'rawvideo',
          '-pix_fmt',
          'rgba',
          '-s',
          '${width}x$height',
          '-r',
          '$fps',
          '-i',
          fifo,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          env['CRF'] ?? '26',
          '-pix_fmt',
          'yuv420p',
          '$out.mp4',
        ]),
      );
      ffmpeg!.stderr.listen(stderr.add);
      video = File(fifo).openSync(mode: FileMode.writeOnly);
    } else {
      Directory(out).createSync(recursive: true);
    }

    final log = <Map<String, Object>>[];
    final firstSeen = <int, int>{};
    var clearedAt = -1;
    var stageStart = 0;
    var lastStage = game.stageIndex;
    final mark = <String, Object>{
      'stage': core.Campaign.stages[from].id,
      'frame': 0,
    };
    log.add(mark);

    while (true) {
      await tester.pump(frame);
      frameNo++;

      // Never let the run end on Game Over: the autopilot's deaths are
      // part of the show, the menu isn't.
      if (game.lives < 1) game.lives = 1;

      // Tips wait for the close button: give them a few seconds on screen.
      for (final m in game.messages.visible) {
        final seen = firstSeen.putIfAbsent(m.id, () => frameNo);
        if (m.seconds == null && frameNo - seen > fps * 4) {
          game.messages.close(m.id);
        }
      }

      if (game.stageIndex != lastStage) {
        lastStage = game.stageIndex;
        stageStart = frameNo;
        clearedAt = -1;
        log.add({'stage': game.stage.id, 'frame': frameNo});
      }
      if (game.sim.cleared && clearedAt < 0) {
        clearedAt = frameNo;
        // The replay must land exactly where the solver did.
        final play = pilot.current;
        if (play != null && pilot.cursor != play.inputs.length) {
          log.add({
            'stage': game.stage.id,
            'frame': frameNo,
            'diverged': '${pilot.cursor}/${play.inputs.length}',
          });
        }
      }

      final ui.Image image = (await tester.runAsync(() {
        final ro =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return ro.toImage();
      }))!;
      if (pngs) {
        if ((frameNo - stageStart) % fps == 0) {
          final png = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          );
          File(
            '$out/${game.stage.id}-${(frameNo - stageStart) ~/ fps}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        }
      } else {
        final raw = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        video!.writeFromSync(raw!.buffer.asUint8List());
      }
      image.dispose();

      // Results card up for a moment, then on to the next stage.
      if (clearedAt >= 0 && frameNo - clearedAt > fps * 4) {
        if (game.stageIndex >= to) break;
        game.nextStage();
        continue;
      }
      final play = pilot.current;
      // A stage the solver didn't clear: show its attempt for a while,
      // then move on.
      if (play != null &&
          !play.cleared &&
          !game.sim.cleared &&
          (pilot.cursor >= play.inputs.length ||
              frameNo - stageStart > fps * failSeconds)) {
        log.add({'stage': game.stage.id, 'frame': frameNo, 'stuck': true});
        if (game.stageIndex >= to) break;
        game.nextStage();
        continue;
      }
      if (frameNo > fps * 60 * 60) break;
    }

    if (ffmpeg != null) {
      video!.closeSync();
      await tester.runAsync(() => ffmpeg!.exitCode);
      File('$out.frames').deleteSync();
    }
    File('$out.cues.json').writeAsStringSync(
      jsonEncode({'fps': fps, 'frames': frameNo, 'stages': log, 'cues': cues}),
    );
    GameAudio.cueListener = null;
  }, timeout: Timeout.none);
}
