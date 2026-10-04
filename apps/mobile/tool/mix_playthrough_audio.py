#!/usr/bin/env python3
"""Mixes the soundtrack for a recorded playthrough and muxes it in.

    python3 tool/mix_playthrough_audio.py /tmp/world1

Reads /tmp/world1.cues.json (written by record_playthrough.dart) and the
game's own sounds in assets/audio, then writes /tmp/world1.wav and
/tmp/world1-sound.mp4 (the silent /tmp/world1.mp4 with the soundtrack).
Plays cues the way GameAudio does: music loops and restarts only when the
track changes, jingles can be cut short, effects at 0.8 and music at 0.6.
Needs numpy and ffmpeg.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

RATE = 16000
MUSIC_VOL = 0.6
SFX_VOL = 0.8
AUDIO = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

_cache = {}


def load(name):
    if name not in _cache:
        with wave.open(os.path.join(AUDIO, name)) as w:
            assert w.getframerate() == RATE and w.getnchannels() == 1
            data = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2')
        _cache[name] = data.astype(np.float32) / 32768
    return _cache[name]


def main(base):
    with open(base + '.cues.json') as f:
        log = json.load(f)
    fps = log['fps']
    total = int(log['frames'] / fps * RATE) + RATE
    out = np.zeros(total, dtype=np.float32)

    # Music: a list of (start sample, end sample, file, offset into loop).
    music = None  # [file, start sample, offset]
    paused_at = None
    segments = []

    def end_music(at):
        nonlocal music
        if music is not None:
            segments.append((music[1], at, music[0], music[2]))
        music = None

    sfx_playing = {}  # file -> (start, end) of the latest instance
    for frame, cue, name in log['cues']:
        at = int(frame / fps * RATE)
        if cue == 'music':
            if music is not None and music[0] == name and paused_at is None:
                continue
            end_music(at)
            paused_at = None
            music = [name, at, 0]
        elif cue == 'stopMusic':
            end_music(at)
            paused_at = None
        elif cue == 'pauseMusic':
            if music is not None and paused_at is None:
                paused_at = at
                name0, start, offset = music
                segments.append((start, at, name0, offset))
                music = [name0, None, offset + (at - start)]
        elif cue == 'resumeMusic':
            if music is not None and paused_at is not None:
                music[1] = at
                paused_at = None
        elif cue == 'sfx':
            clip = load(name)
            end = min(total, at + len(clip))
            out[at:end] += clip[: end - at] * SFX_VOL
            sfx_playing[name] = (at, at + len(clip))
        elif cue == 'stopSfx':
            playing = sfx_playing.pop(name, None)
            if playing and playing[0] <= at < playing[1]:
                clip = load(name)
                cut_from = at - playing[0]
                end = min(total, playing[1])
                out[at:end] -= clip[cut_from: cut_from + end - at] * SFX_VOL
    if music is not None and music[1] is not None:
        segments.append((music[1], total, music[0], music[2]))

    for start, end, name, offset in segments:
        if start is None or end <= start:
            continue
        loop = load(name)
        n = end - start
        idx = (np.arange(n) + offset) % len(loop)
        out[start:end] += loop[idx] * MUSIC_VOL

    peak = float(np.max(np.abs(out))) or 1.0
    # Soft limit rather than normalise, so quiet stretches stay quiet.
    out = np.tanh(out * 1.1) if peak > 1 else out
    pcm = (np.clip(out, -1, 1) * 32767).astype('<i2')
    with wave.open(base + '.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    subprocess.run([
        'ffmpeg', '-y', '-loglevel', 'error', '-i', base + '.mp4',
        '-i', base + '.wav', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '64k',
        '-ar', '32000', '-shortest', '-movflags', '+faststart',
        base + '-sound.mp4',
    ], check=True)


if __name__ == '__main__':
    main(sys.argv[1])
