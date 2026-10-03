import 'dart:io';

import 'package:bombario/audio/game_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => GameAudio.enabled = false);

  test('disabled GameAudio: every method is a safe no-op', () async {
    final audio = GameAudio.instance;
    await audio.preload();
    for (final s in Sfx.values) {
      audio.play(s);
    }
    await audio.playMusic(1);
    await audio.playMusic(3, hurry: true);
    await audio.playMusic(0);
    await audio.stopMusic();
    await audio.pauseMusic();
    await audio.resumeMusic();
    audio.stopSfx(Sfx.stageStart);
    audio.stopSfx(Sfx.gameOver);
    audio.setVolumes(music: 0.3, sfx: 1.5);
    expect(audio.musicVolume, 0.3);
    expect(audio.sfxVolume, 1.0);
  });

  test('music file names clamp worlds and pick hurry variants', () {
    expect(GameAudio.musicFile(0), 'music_menu.wav');
    expect(GameAudio.musicFile(1), 'music_w1.wav');
    expect(GameAudio.musicFile(9), 'music_w5.wav');
    expect(GameAudio.musicFile(2, hurry: true), 'music_w2_fast.wav');
    expect(GameAudio.sfxFile(Sfx.bombPlaceOther), 'bomb_place_other.wav');
    expect(GameAudio.sfxFile(Sfx.timeLow), 'time_low.wav');
  });

  test('every Sfx and music track has an asset file', () {
    final files = <String>{
      for (final s in Sfx.values) GameAudio.sfxFile(s),
      GameAudio.musicFile(0),
      for (var w = 1; w <= 5; w++) ...[
        GameAudio.musicFile(w),
        GameAudio.musicFile(w, hurry: true),
      ],
      GameAudio.musicFile(1, found: true),
      GameAudio.musicFile(1, hurry: true, found: true),
    };
    expect(files, hasLength(Sfx.values.length + 13));
    for (final f in files) {
      final file = File('assets/audio/$f');
      expect(file.existsSync(), isTrue, reason: 'missing assets/audio/$f');
      expect(file.lengthSync(), greaterThan(44), reason: '$f is empty');
    }
  });
}
