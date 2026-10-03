#!/usr/bin/env python3
"""Synthesise all Bombario audio (SFX + chiptune music) from scratch.

Everything here is original: melodies, chord progressions and sound effects
are written as data in this file and rendered with simple oscillators
(pulse, triangle, noise). Nothing is sampled or transcribed from any existing
game (see game-design-document.md, section 18).

Pure Python 3 standard library. Output: 16-bit mono WAV, 16000 Hz, written to
apps/mobile/assets/audio/. The output is deterministic (fixed random seed).

    python3 tools/audio/make_audio.py
"""

import math
import os
import random
import struct
import wave

SR = 16000
OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "apps", "mobile", "assets", "audio"
)

rng = random.Random(0xB0B)


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def write_wav(name, samples, peak=0.85):
    """Normalise to `peak` and write a 16-bit mono WAV."""
    m = max(1e-9, max(abs(s) for s in samples))
    g = peak / m
    data = bytearray()
    for s in samples:
        v = int(round(s * g * 32767))
        data += struct.pack("<h", max(-32768, min(32767, v)))
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(data))
    return path


def pulse(phase, duty):
    return 1.0 if (phase % 1.0) < duty else -1.0


def tri(phase):
    p = phase % 1.0
    v = 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
    # 4-bit quantised triangle, like classic sound chips.
    return round(v * 7.5) / 7.5


def wave_fn(kind, phase, duty=0.5):
    if kind == "tri":
        return tri(phase)
    if kind == "sine":
        return math.sin(2 * math.pi * phase)
    return pulse(phase, duty)


class Noise:
    """LFSR-style noise; `short` mode gives the metallic periodic variant."""

    def __init__(self, short=False):
        self.reg = 1
        self.short = short

    def step(self):
        bit = (self.reg ^ (self.reg >> (6 if self.short else 1))) & 1
        self.reg = (self.reg >> 1) | (bit << 14)
        return 1.0 if self.reg & 1 else -1.0


def env_adsr(i, n, a=0.004, d=0.05, s=0.7, r=0.03):
    """Envelope value for sample i of an n-sample note (release inside n)."""
    t = i / SR
    dur = n / SR
    a = min(a, dur * 0.3)
    r = min(r, dur * 0.4)
    if t < a:
        v = t / a
    elif t < a + d:
        v = 1.0 - (1.0 - s) * (t - a) / d
    else:
        v = s
    rem = dur - t
    if rem < r:
        v *= max(0.0, rem / r)
    return v


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

def sweep(dur, f0, f1, kind="sq", duty=0.5, vol=1.0, curve=1.0, a=0.002, r=0.02,
          vib=0.0, vib_rate=8.0, decay=None):
    n = int(dur * SR)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        x = i / max(1, n - 1)
        f = f0 + (f1 - f0) * (x ** curve)
        if vib:
            f *= 1.0 + vib * math.sin(2 * math.pi * vib_rate * i / SR)
        ph += f / SR
        e = env_adsr(i, n, a=a, d=0.0, s=1.0, r=r)
        if decay:
            e *= math.exp(-i / SR / decay)
        out[i] = wave_fn(kind, ph, duty) * e * vol
    return out


def noise_burst(dur, vol=1.0, decay=0.1, lp=1.0, lp_end=None, short=False, hp=False,
                rate=1):
    """Noise with exponential decay, sample-and-hold `rate` and one-pole filters."""
    n = int(dur * SR)
    nz = Noise(short)
    out = [0.0] * n
    held = 0.0
    y = 0.0
    prev = 0.0
    for i in range(n):
        if i % rate == 0:
            held = nz.step()
        x = i / max(1, n - 1)
        k = lp if lp_end is None else lp + (lp_end - lp) * x
        y += k * (held - y)
        v = y
        if hp:
            v, prev = y - prev, y
        e = math.exp(-i / SR / decay) * env_adsr(i, n, a=0.001, d=0.0, s=1.0, r=0.01)
        out[i] = v * e * vol
    return out


def notes_seq(seq, kind="sq", duty=0.5, vol=1.0, gate=0.9, decay=None, vib=0.0):
    """seq: list of (midi or None, seconds)."""
    out = []
    for m, d in seq:
        n = int(d * SR)
        if m is None:
            out += [0.0] * n
            continue
        on = int(n * gate)
        f = midi_hz(m)
        ph = 0.0
        for i in range(on):
            ff = f * (1.0 + vib * math.sin(2 * math.pi * 6 * i / SR)) if vib else f
            ph += ff / SR
            e = env_adsr(i, on, a=0.003, d=0.04, s=0.75, r=0.03)
            if decay:
                e *= math.exp(-i / SR / decay)
            out.append(wave_fn(kind, ph, duty) * e * vol)
        out += [0.0] * (n - on)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def delay(track, seconds):
    return [0.0] * int(seconds * SR) + track


def make_sfx():
    s = {}
    # Your own bomb: bright pulse "thunk-blip" falling in pitch + click.
    s["bomb_place"] = (mix(
        sweep(0.11, 720, 180, duty=0.25, vol=0.7, curve=0.6),
        noise_burst(0.03, vol=0.35, decay=0.01, lp=0.6),
    ), 0.8)
    # Someone else's bomb: lower, softer triangle thud, no click.
    s["bomb_place_other"] = (sweep(0.10, 300, 130, kind="tri", vol=0.8, curve=0.7), 0.55)
    # Explosion: low-passed noise roar + sub thump.
    s["explode"] = (mix(
        noise_burst(0.65, vol=1.0, decay=0.18, lp=0.9, lp_end=0.08, rate=2),
        sweep(0.30, 110, 35, kind="tri", vol=0.9, curve=0.5, decay=0.12),
    ), 0.9)
    # Distant explosion: duller and quieter.
    s["explode_far"] = (mix(
        noise_burst(0.5, vol=1.0, decay=0.14, lp=0.25, lp_end=0.04, rate=3),
        sweep(0.25, 80, 35, kind="tri", vol=0.6, curve=0.5, decay=0.1),
    ), 0.45)
    # Power-up pickup: quick rising arpeggio.
    s["pickup"] = (notes_seq([(84, 0.05), (88, 0.05), (91, 0.05), (96, 0.11)],
                             duty=0.25, vol=0.7, gate=0.95), 0.75)
    # Death: wobbling downward slide.
    s["death"] = (mix(
        sweep(0.85, 880, 110, duty=0.5, vol=0.6, curve=0.8, vib=0.06, vib_rate=11, r=0.1),
        delay(noise_burst(0.3, vol=0.25, decay=0.12, lp=0.3), 0.55),
    ), 0.8)
    # Revive: rising sweep, then a sparkle arpeggio.
    s["revive"] = (mix(
        sweep(0.3, 220, 880, kind="tri", vol=0.7, curve=1.3),
        delay(notes_seq([(81, 0.06), (85, 0.06), (88, 0.06), (93, 0.18)],
                        duty=0.125, vol=0.5), 0.26),
    ), 0.8)
    # Ping (teammate marker): two bright blips.
    s["ping"] = (mix(
        notes_seq([(91, 0.07), (None, 0.03), (96, 0.16)], kind="tri", vol=0.9, decay=0.08),
        notes_seq([(91, 0.07), (None, 0.03), (96, 0.16)], duty=0.125, vol=0.25, decay=0.06),
    ), 0.7)
    # Stage clear jingle (major, ~1.6 s).
    q = 0.11
    lead = [(72, q), (76, q), (79, q), (84, q * 2), (79, q), (84, q * 5),
            (86, q), (88, q * 4)]
    bass = [(48, q * 4), (53, q * 4), (55, q * 3), (48, q * 5)]
    s["stage_clear"] = (mix(
        notes_seq(lead, duty=0.5, vol=0.5, gate=0.92),
        notes_seq([(m + 4 if m else None, d) for m, d in lead], duty=0.25, vol=0.2, gate=0.92),
        notes_seq(bass, kind="tri", vol=0.8, gate=0.95),
    ), 0.8)
    # Game over jingle (minor, falling, ~2 s).
    q = 0.16
    lead = [(76, q), (75, q), (72, q * 2), (71, q), (68, q), (69, q * 6)]
    bass = [(45, q * 2), (44, q * 2), (40, q * 2), (45, q * 6)]
    s["game_over"] = (mix(
        notes_seq(lead, duty=0.5, vol=0.5, vib=0.01),
        notes_seq(bass, kind="tri", vol=0.8, gate=0.95),
    ), 0.8)
    # Exit angry: two-tone alarm, three cycles.
    alarm = []
    for _ in range(3):
        alarm += [(81, 0.12), (75, 0.12)]
    s["exit_angry"] = (notes_seq(alarm, duty=0.5, vol=0.6, gate=0.98), 0.75)
    # Kick a bomb: thwack + up-chirp.
    s["kick"] = (mix(
        noise_burst(0.06, vol=0.6, decay=0.02, lp=0.7),
        sweep(0.1, 200, 600, duty=0.25, vol=0.45, curve=1.0),
    ), 0.7)
    # Freeze: icy descending shimmer.
    shimmer = [(100 - k * 2 + (3 if k % 2 else 0), 0.035) for k in range(12)]
    s["freeze"] = (mix(
        notes_seq(shimmer, kind="tri", vol=0.6, gate=0.9),
        notes_seq(shimmer, duty=0.125, vol=0.2, gate=0.6),
        noise_burst(0.45, vol=0.15, decay=0.2, hp=True, short=True),
    ), 0.7)
    # UI tap: tiny blip.
    s["ui_tap"] = (sweep(0.035, 1400, 1100, duty=0.25, vol=0.5, r=0.012), 0.5)
    # Boss hit: crunchy low pulse + noise.
    s["boss_hit"] = (mix(
        sweep(0.3, 160, 60, duty=0.125, vol=0.6, curve=0.6, r=0.06),
        noise_burst(0.2, vol=0.5, decay=0.06, lp=0.5, rate=4),
    ), 0.85)
    # Ghost: wobbly "wooo" up and down.
    n = int(0.75 * SR)
    ghost = []
    ph = 0.0
    for i in range(n):
        x = i / n
        f = 330 + 260 * math.sin(math.pi * x) + 25 * math.sin(2 * math.pi * 7 * i / SR)
        ph += f / SR
        ghost.append(tri(ph) * env_adsr(i, n, a=0.08, d=0.0, s=1.0, r=0.2) * 0.7)
    s["ghost"] = (ghost, 0.6)
    # Footsteps: a short blip per half tile walked, a different pitch for
    # left/right than for up/down (the original's trick for making movement
    # readable by ear).
    s["step_h"] = (sweep(0.045, 520, 360, duty=0.25, vol=0.5, curve=0.7, r=0.012), 0.35)
    s["step_v"] = (sweep(0.045, 760, 540, duty=0.25, vol=0.5, curve=0.7, r=0.012), 0.35)
    # Stage start: a short bright fanfare under the STAGE card (~1.8 s).
    q = 0.1
    lead = [(67, q), (72, q), (76, q), (79, q * 2), (76, q), (79, q * 2),
            (81, q), (79, q), (84, q * 6)]
    bass = [(48, q * 4), (55, q * 4), (53, q * 2), (48, q * 6)]
    s["stage_start"] = (mix(
        notes_seq(lead, duty=0.5, vol=0.5, gate=0.9),
        notes_seq(bass, kind="tri", vol=0.8, gate=0.95),
    ), 0.75)
    # Exit open: the last enemy is down; a rising three-note chime.
    s["exit_open"] = (mix(
        notes_seq([(84, 0.08), (88, 0.08), (96, 0.3)], kind="tri", vol=0.9, decay=0.2),
        notes_seq([(84, 0.08), (88, 0.08), (96, 0.3)], duty=0.125, vol=0.25, decay=0.15),
    ), 0.7)
    # Pipe: three quick falling blips, like sliding down a warp pipe.
    blip = sweep(0.07, 700, 180, duty=0.5, vol=0.8, curve=1.5)
    gap = [0.0] * int(SR * 0.03)
    s["pipe"] = (blip + gap + blip + gap + blip, 0.6)
    for name, (samples, peak) in s.items():
        write_wav(name, samples, peak)
    return list(s)


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

MODES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
}


def degree_to_semi(mode, d):
    sc = MODES[mode]
    return 12 * (d // 7) + sc[d % 7]


def parse_melody(text):
    """'4:1 r:2 | ...' -> list of bars, each a list of (degree|None, eighths)."""
    bars = []
    for bar in text.split("|"):
        notes = []
        for tok in bar.split():
            deg, ln = tok.split(":")
            notes.append((None if deg == "r" else int(deg), int(ln)))
        bars.append(notes)
    return bars


# Each song: key (MIDI tonic of the lead octave), mode, bpm, beats per bar,
# chord root degree per bar, a hand-written melody (scale degrees, lengths in
# eighth notes), and style choices for the other channels.
SONGS = {
    "menu": dict(
        tonic=72, mode="major", bpm=112, beats=4,
        chords=[0, 5, 3, 4, 0, 5, 1, 4],
        melody="""4:2 2:1 4:1 7:2 4:2 | 5:3 4:1 2:2 0:2 | 3:2 5:1 7:1 8:2 7:2 |
                  6:3 4:1 1:2 r:2 | 4:2 2:1 4:1 9:2 7:2 | 7:3 5:1 2:2 r:2 |
                  1:2 3:1 5:1 8:2 5:2 | 6:2 4:2 r:4""",
        lead_duty=0.5, harm="offbeat", bass="rootfifth",
        drums=["k-h-s-h-k-k-s-h-"],
    ),
    # World 1: sunny grassland - G major, bouncy.
    "w1": dict(
        tonic=67, mode="major", bpm=120, beats=4,
        chords=[0, 3, 4, 0, 5, 3, 4, 4],
        melody="""4:1 4:1 7:2 6:1 4:1 2:2 | 3:2 5:1 7:1 5:2 r:2 |
                  4:1 6:1 8:2 6:1 4:1 1:2 | 2:3 0:1 2:2 4:2 |
                  5:1 5:1 9:2 7:1 5:1 2:2 | 3:1 5:1 7:2 8:1 7:1 5:2 |
                  4:2 6:2 8:1 7:1 6:2 | 4:1 r:1 4:1 6:1 8:2 r:2""",
        lead_duty=0.25, harm="arp16", bass="octave",
        drums=["k-h-s-h-k-h-s-hh"],
    ),
    # World 2: caves - D dorian, sparse, with an echo channel.
    "w2": dict(
        tonic=62, mode="dorian", bpm=100, beats=4,
        chords=[0, 0, 6, 6, 3, 3, 4, 6],
        melody="""0:2 2:1 4:3 r:2 | 3:1 2:1 0:2 r:4 | 6:2 1:1 3:3 r:2 |
                  4:1 3:1 1:2 -1:4 | 3:2 5:1 7:3 r:2 | 9:1 7:1 5:2 3:2 2:2 |
                  4:3 6:1 8:2 7:2 | 6:2 5:1 4:1 3:2 1:2""",
        lead_duty=0.5, harm="echo", bass="drone",
        drums=["k-----h-s-----h-", "k-----h-s---k-h-"],
    ),
    # World 3: ice - E lydian, sparkling 16th arpeggios, long lead notes.
    "w3": dict(
        tonic=76, mode="lydian", bpm=108, beats=4,
        chords=[0, 1, 0, 1, 5, 3, 1, 4],
        melody="""4:4 3:2 4:2 | 5:4 3:2 1:2 | 7:3 6:1 4:4 | 8:2 5:2 3:4 |
                  2:2 5:2 7:4 | 7:2 5:2 3:2 0:2 | 1:3 3:1 5:2 8:2 | 6:4 4:2 r:2""",
        lead_duty=0.25, harm="sparkle", bass="rootfifth",
        drums=["k---h---s---h--h"],
    ),
    # World 4: haunted - A harmonic minor waltz in 3/4.
    "w4": dict(
        tonic=69, mode="harmonic_minor", bpm=132, beats=3,
        chords=[0, 0, 3, 3, 5, 5, 4, 4, 0, 3, 4, 4],
        melody="""4:2 3:1 2:1 1:1 2:1 | 0:4 -3:2 | 3:2 5:2 7:2 | 6:3 5:1 3:2 |
                  5:2 7:2 9:2 | 8:3 7:1 5:2 | 4:2 6:2 8:2 | 7:3 6:3 |
                  7:2 4:1 2:1 0:2 | 3:2 5:1 3:1 2:2 | 1:2 4:2 6:2 | 4:4 r:2""",
        lead_duty=0.125, harm="waltz", bass="waltz",
        drums=["k---h-s-h---"],
        vibrato=0.012,
    ),
    # World 5: volcano fortress - C phrygian, driving.
    "w5": dict(
        tonic=72, mode="phrygian", bpm=152, beats=4,
        chords=[0, 0, 1, 0, 5, 6, 0, 0, 3, 5, 1, 1],
        melody="""0:1 0:1 2:1 0:1 3:2 2:2 | 1:1 0:1 -1:2 0:4 |
                  1:1 1:1 3:1 1:1 5:2 3:2 | 2:1 1:1 0:2 r:4 |
                  7:2 5:1 7:1 9:2 7:2 | 8:2 6:1 4:1 6:4 |
                  7:1 7:1 9:1 7:1 11:2 9:2 | 8:1 7:1 6:2 7:4 |
                  3:2 5:2 7:2 5:2 | 5:1 7:1 9:2 8:2 7:2 |
                  8:2 1:2 3:2 5:2 | 6:1 5:1 3:1 1:1 8:4""",
        lead_duty=0.5, harm="power", bass="root8",
        drums=["k-h-s-hkk-h-s-h-", "k-h-s-hkk-hks-ss"],
    ),
    # Power-up found: the stage's music gives way to this quick, bright
    # loop that says "now find the exit" (the original changes tune too).
    "found": dict(
        tonic=72, mode="major", bpm=150, beats=4,
        chords=[0, 4, 5, 3, 0, 4, 3, 4],
        melody="""0:1 2:1 4:1 7:1 9:2 7:2 | 8:1 7:1 5:1 4:1 2:4 |
                  3:1 5:1 7:1 10:1 9:2 7:2 | 6:2 4:2 1:2 r:2 |
                  4:1 4:1 7:1 4:1 9:2 11:2 | 12:2 11:1 9:1 7:4 |
                  5:1 7:1 9:1 7:1 5:2 3:2 | 4:2 6:2 7:2 r:2""",
        lead_duty=0.25, harm="arp16", bass="octave",
        drums=["k-hhs-hhk-hhs-hh"],
    ),
}


class Track:
    """A loop buffer. Notes that run past the end wrap around to the start,
    so the loop is seamless by construction."""

    def __init__(self, n):
        self.n = n
        self.buf = [0.0] * n

    def add_tone(self, start, length, freq, vol, kind="sq", duty=0.5, a=0.003,
                 d=0.06, s=0.6, r=0.02, vib=0.0, vib_delay=0.15, decay=None):
        ph = 0.0
        n = self.n
        buf = self.buf
        vd = int(vib_delay * SR)
        for i in range(length):
            f = freq
            if vib and i > vd:
                f *= 1.0 + vib * math.sin(2 * math.pi * 5.5 * (i - vd) / SR)
            ph += f / SR
            e = env_adsr(i, length, a=a, d=d, s=s, r=r)
            if decay:
                e *= math.exp(-i / SR / decay)
            buf[(start + i) % n] += wave_fn(kind, ph, duty) * e * vol

    def add_samples(self, start, samples):
        n = self.n
        for i, v in enumerate(samples):
            self.buf[(start + i) % n] += v


def drum_sounds():
    kick = mix(sweep(0.12, 150, 40, kind="tri", vol=1.0, curve=0.4, r=0.02),
               noise_burst(0.02, vol=0.4, decay=0.008, lp=0.5))
    snare = noise_burst(0.14, vol=0.7, decay=0.05, lp=0.8, rate=1)
    hat = noise_burst(0.035, vol=0.35, decay=0.012, hp=True, short=True)
    return {"k": kick, "s": snare, "h": hat}


DRUMS = None


def render_song(spec, tempo_mult=1.0, hurry=False):
    global DRUMS
    if DRUMS is None:
        DRUMS = drum_sounds()
    bpm = spec["bpm"] * tempo_mult
    beats = spec["beats"]
    mode = spec["mode"]
    tonic = spec["tonic"]
    chords = spec["chords"]
    melody = parse_melody(spec["melody"])
    nbars = len(chords)
    assert len(melody) == nbars, (len(melody), nbars)
    eighths_per_bar = beats * 2
    for bi, bar in enumerate(melody):
        assert sum(ln for _, ln in bar) == eighths_per_bar, (bi, bar)

    sixteenth = 60.0 / bpm / 4.0
    steps_per_bar = beats * 4
    total_steps = nbars * steps_per_bar
    n = int(round(total_steps * sixteenth * SR))

    def pos(step):  # sample index of a 16th step (exact bar grid)
        return int(round(step * n / total_steps))

    def span(step, steps):
        return pos(step + steps) - pos(step)

    def note(d, octave=0):
        return midi_hz(tonic + degree_to_semi(mode, d) + 12 * octave)

    lead = Track(n)
    harm = Track(n)
    bass = Track(n)
    drums = Track(n)
    vib = spec.get("vibrato", 0.006)
    duty = spec["lead_duty"]

    # Lead.
    step = 0
    lead_events = []
    for bar in melody:
        for deg, ln in bar:
            steps = ln * 2
            if deg is not None:
                length = int(span(step, steps) * 0.92)
                lead.add_tone(pos(step), length, note(deg), 0.30, duty=duty, vib=vib)
                lead_events.append((step, steps, deg))
            step += steps

    # Harmony.
    style = spec["harm"]
    for b, root in enumerate(chords):
        triad = [root, root + 2, root + 4]
        base = b * steps_per_bar
        if style == "arp16":
            pat = [0, 1, 2, 1]
            for k in range(steps_per_bar):
                d = triad[pat[k % 4]]
                harm.add_tone(pos(base + k), int(span(base + k, 1) * 0.8), note(d, -1),
                              0.11, duty=0.125, d=0.03, s=0.4)
        elif style == "sparkle":
            pat = [0, 1, 2, 3, 2, 1]
            for k in range(steps_per_bar):
                p = pat[k % 6]
                d = triad[p] if p < 3 else root + 7
                harm.add_tone(pos(base + k), int(span(base + k, 1) * 0.7), note(d, 0),
                              0.08, kind="sq", duty=0.125, d=0.02, s=0.3, decay=0.08)
        elif style == "offbeat":
            for k in range(2, steps_per_bar, 4):
                for j, d in enumerate(triad):
                    # Fast chip arpeggio inside each stab.
                    for t in range(2):
                        st = pos(base + k) + int((j + 3 * t) * 0.012 * SR)
                        harm.add_tone(st, int(0.012 * SR), note(d, -1), 0.12, duty=0.25,
                                      a=0.001, d=0.0, s=1.0, r=0.002)
        elif style == "waltz":
            for beat in (1, 2):
                st0 = pos(base + beat * 4)
                L = int(span(base + beat * 4, 3))
                cyc = int(0.02 * SR)
                k = 0
                while k * cyc < L:
                    d = triad[k % 3]
                    harm.add_tone(st0 + k * cyc, cyc, note(d, -1),
                                  0.10 * math.exp(-k * cyc / SR / 0.25),
                                  duty=0.25, a=0.001, d=0.0, s=1.0, r=0.002)
                    k += 1
        elif style == "power":
            # Power-chord chugs on 8ths (root + fifth).
            for k in range(0, steps_per_bar, 2):
                L = int(span(base + k, 2) * 0.6)
                harm.add_tone(pos(base + k), L, note(root, -1), 0.07, duty=0.5, d=0.04, s=0.5)
                harm.add_tone(pos(base + k), L, note(root + 4, -1), 0.06, duty=0.5, d=0.04,
                              s=0.5)
    if style == "echo":
        # Delayed, quieter, thinner copy of the lead: cave reverb.
        for st, steps, deg in lead_events:
            for rep, (dl, v) in enumerate(((3, 0.13), (6, 0.06))):
                length = int(span(st, steps) * 0.85)
                harm.add_tone(pos(st + dl), length, note(deg), v, duty=0.125, vib=vib)

    # Bass (triangle, two octaves under the lead).
    bstyle = spec["bass"]
    for b, root in enumerate(chords):
        base = b * steps_per_bar
        r0 = note(root, -2)
        fifth = note(root + 4, -2)
        if bstyle == "octave":
            for k in range(0, steps_per_bar, 2):
                f = r0 if (k // 2) % 2 == 0 else r0 * 2
                bass.add_tone(pos(base + k), int(span(base + k, 2) * 0.8), f, 0.45, kind="tri",
                              d=0.02, s=0.9)
        elif bstyle == "rootfifth":
            for k in range(0, steps_per_bar, 4):
                f = r0 if (k // 4) % 2 == 0 else fifth
                bass.add_tone(pos(base + k), int(span(base + k, 4) * 0.85), f, 0.5, kind="tri",
                              d=0.02, s=0.9)
        elif bstyle == "drone":
            bass.add_tone(pos(base), int(span(base, 10) * 0.95), r0, 0.5, kind="tri",
                          d=0.3, s=0.7, r=0.08)
            bass.add_tone(pos(base + 12), int(span(base + 12, 4) * 0.8), fifth, 0.4,
                          kind="tri", d=0.05, s=0.8)
        elif bstyle == "waltz":
            bass.add_tone(pos(base), int(span(base, 4) * 0.9), r0, 0.55, kind="tri",
                          d=0.05, s=0.8)
        elif bstyle == "root8":
            for k in range(0, steps_per_bar, 2):
                f = r0 if k != steps_per_bar - 2 else r0 * 2
                bass.add_tone(pos(base + k), int(span(base + k, 2) * 0.7), f, 0.5, kind="tri",
                              d=0.02, s=0.9)

    # Drums: pattern strings of 16th steps, cycling per bar.
    pats = spec["drums"]
    for b in range(nbars):
        pat = pats[b % len(pats)]
        if b == nbars - 1:
            # Fill on the last bar so the loop turns over with energy.
            pat = pat[: len(pat) // 2] + ("s-ss" + "s" * steps_per_bar)[: len(pat) - len(pat) // 2]
        base = b * steps_per_bar
        for k in range(steps_per_bar):
            c = pat[k % len(pat)]
            if hurry and c == "-" and k % 2 == 1:
                c = "h"  # busier hats when time is running out
            if c in DRUMS:
                drums.add_samples(pos(base + k), DRUMS[c])

    out = [0.0] * n
    for t, g in ((lead, 1.0), (harm, 1.0), (bass, 1.0), (drums, 0.35)):
        for i, v in enumerate(t.buf):
            out[i] += v * g
    # Gentle one-pole low-pass to tame aliasing of the naive pulses. Run it
    # twice around the loop so the filter state at the seam is steady.
    y = 0.0
    filt = [0.0] * n
    for _ in range(2):
        for i in range(n):
            y += 0.6 * (out[i] - y)
            filt[i] = y
    return filt


def make_music():
    names = []
    for key, spec in SONGS.items():
        write_wav("music_" + key, render_song(spec), peak=0.8)
        names.append("music_" + key)
        if key.startswith("w") or key == "found":
            write_wav("music_%s_fast" % key, render_song(spec, 1.25, hurry=True), peak=0.8)
            names.append("music_%s_fast" % key)
    return names


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    names = make_sfx() + make_music()
    total = 0
    for name in names:
        p = os.path.join(OUT_DIR, name + ".wav")
        size = os.path.getsize(p)
        total += size
        with wave.open(p) as w:
            dur = w.getnframes() / SR
        print("%-22s %6.2fs %8d bytes" % (name, dur, size))
    print("total: %d files, %.2f MB" % (len(names), total / 1e6))


if __name__ == "__main__":
    main()
