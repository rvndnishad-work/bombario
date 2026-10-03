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


def hits(burst, times):
    """The same one-shot dropped at several onsets (seconds)."""
    return mix(*[delay(burst, t) for t in times])


def squash(track, drive=1.6):
    """tanh soft clip: raises RMS ~4 dB without changing the peak that write_wav normalises."""
    return [math.tanh(drive * v) for v in track]


def pad(track, seconds):
    """Pad with silence to an exact total length."""
    return track + [0.0] * max(0, int(seconds * SR) - len(track))


def make_sfx():
    s = {}
    # Your own bomb: a hard click plus a 12.5 % duty pitch drop.
    s["bomb_place"] = (mix(
        noise_burst(0.012, vol=0.9, decay=0.004, lp=1.0, hp=True),
        sweep(0.07, 900, 220, duty=0.125, vol=0.8, curve=0.45, r=0.03, decay=0.03),
    ), 0.75)
    # Someone else's bomb: lower, softer triangle thud with a tiny click.
    s["bomb_place_other"] = (mix(
        sweep(0.07, 380, 150, kind="tri", vol=0.8, curve=0.5, decay=0.03),
        noise_burst(0.01, vol=0.3, decay=0.003, lp=0.5),
    ), 0.5)
    # Explosion: crack, then bright / mid / low noise periods over a sub thump.
    # The core action, so it is the loudest thing in the game (soft-clipped).
    s["explode"] = (squash(mix(
        noise_burst(0.04, vol=1.0, decay=0.012, lp=1.0),                                   # crack
        noise_burst(0.30, vol=0.9, decay=0.09, lp=0.95, rate=1),                           # bright period
        delay(noise_burst(0.40, vol=0.8, decay=0.14, lp=0.6, lp_end=0.2, rate=3), 0.08),   # mid period
        delay(noise_burst(0.45, vol=0.7, decay=0.2, lp=0.25, lp_end=0.05, rate=8), 0.2),   # low rumble
        sweep(0.22, 140, 38, kind="sine", vol=1.0, curve=0.35, a=0.001, decay=0.09),       # sub thump
        sweep(0.12, 70, 45, kind="tri", vol=0.6, decay=0.05),
    ), 1.2), 0.95)
    # Distant explosion: no crack, dull rumble and a sub.
    s["explode_far"] = (squash(mix(
        noise_burst(0.35, vol=0.8, decay=0.12, lp=0.35, lp_end=0.06, rate=3),
        delay(noise_burst(0.4, vol=0.7, decay=0.18, lp=0.15, lp_end=0.03, rate=8), 0.06),
        sweep(0.2, 90, 35, kind="sine", vol=0.9, curve=0.4, decay=0.08),
    ), 1.4), 0.5)
    # Power-up pickup: a click and a 12.5 % duty C6-C7 run, the top note doubled.
    s["pickup"] = (mix(
        noise_burst(0.008, vol=0.4, decay=0.003, lp=1.0),
        notes_seq([(84, 0.045), (88, 0.045), (91, 0.045), (96, 0.14)],
                  duty=0.125, vol=0.7, gate=0.8, decay=0.09),
        notes_seq([(None, 0.135), (96, 0.14)], duty=0.5, vol=0.2, decay=0.06),
    ), 0.75)
    # Death: a hit, a two-voice stepwise fall, a drooping last note with a
    # wobble, a low thud, then silence (fits inside the 1.5 s respawn delay).
    hit = mix(noise_burst(0.05, vol=0.8, decay=0.015, lp=0.9),
              sweep(0.08, 600, 200, duty=0.5, vol=0.7, curve=0.5, decay=0.03))
    fall = delay(notes_seq([(81, 0.12), (79, 0.12), (77, 0.12), (76, 0.12), (74, 0.12)],
                           duty=0.5, vol=0.45, gate=0.8, decay=0.1), 0.10)
    fall3 = delay(notes_seq([(77, 0.12), (76, 0.12), (74, 0.12), (72, 0.12), (71, 0.12)],
                            duty=0.25, vol=0.2, gate=0.8, decay=0.1), 0.10)
    droop = delay(sweep(0.38, midi_hz(72), midi_hz(67), duty=0.5, vol=0.45, curve=1.3,
                        vib=0.05, vib_rate=9, r=0.08), 0.70)
    droop3 = delay(sweep(0.38, midi_hz(69), midi_hz(64), duty=0.25, vol=0.18, curve=1.3,
                         vib=0.05, vib_rate=9, r=0.08), 0.70)
    thud = delay(mix(sweep(0.25, 90, 40, kind="tri", vol=1.0, curve=0.4, decay=0.09),
                     noise_burst(0.06, vol=0.5, decay=0.02, lp=0.4)), 1.08)
    s["death"] = (pad(mix(hit, fall, fall3, droop, droop3, thud), 1.42), 0.85)
    # Revive: rising triangle sweep, a click, then a sparkle arpeggio.
    s["revive"] = (mix(
        sweep(0.25, 220, 880, kind="tri", vol=0.6, curve=1.3, a=0.01, r=0.03),
        delay(noise_burst(0.015, vol=0.4, decay=0.004, hp=True), 0.22),
        delay(notes_seq([(81, 0.05), (85, 0.05), (88, 0.05), (93, 0.05), (96, 0.25)],
                        duty=0.125, vol=0.5, gate=0.85, decay=0.12), 0.22),
    ), 0.8)
    # Ping (teammate marker): sonar G5 -> D6 with an echo.
    sonar = [(79, 0.06), (None, 0.04), (86, 0.14)]
    base = mix(notes_seq(sonar, kind="tri", vol=0.9, decay=0.07),
               notes_seq(sonar, duty=0.125, vol=0.25, decay=0.06))
    s["ping"] = (mix(base, delay([v * 0.3 for v in base], 0.2)), 0.65)
    # Stage clear jingle (1.9 s): staccato rising figure in thirds over a
    # triangle bass with hats and snares, then a fast run into a held top
    # note on a crash.
    q = 0.1
    lead = notes_seq([(72, q), (76, q), (79, q), (84, q), (None, q), (83, q), (84, q), (None, q),
                      (79, q), (84, q), (88, q), (None, q)],
                     duty=0.5, vol=0.5, gate=0.55, decay=0.1)
    tail = delay(notes_seq([(84, 0.04), (88, 0.04), (91, 0.04), (96, 0.55)],
                           duty=0.5, vol=0.5, gate=1.0, decay=0.25), 1.2)
    harm = notes_seq([(67, q), (72, q), (76, q), (79, q), (None, q), (79, q), (81, q), (None, q),
                      (76, q), (79, q), (84, q), (None, q)],
                     duty=0.25, vol=0.24, gate=0.55, decay=0.1)
    harm_tail = delay(notes_seq([(91, 0.58)], duty=0.25, vol=0.2, gate=1.0, decay=0.25), 1.32)
    bass = notes_seq([(48, 2 * q), (52, 2 * q), (55, 2 * q), (53, 2 * q), (55, 2 * q), (55, 2 * q)],
                     kind="tri", vol=0.85, gate=0.8, decay=0.15)
    bass_tail = delay(notes_seq([(48, 0.58)], kind="tri", vol=0.9, gate=1.0, decay=0.35), 1.32)
    hats = hits(noise_burst(0.02, vol=0.3, decay=0.006, hp=True), [k * q for k in range(12)])
    snares = hits(noise_burst(0.05, vol=0.45, decay=0.018, lp=0.8), [4 * q, 8 * q])
    crash = delay(mix(noise_burst(0.5, vol=0.7, decay=0.14, lp=0.95, lp_end=0.3),
                      sweep(0.2, 120, 45, kind="sine", vol=0.8, decay=0.08)), 1.32)
    s["stage_clear"] = (pad(mix(lead, tail, harm, harm_tail, bass, bass_tail, hats, snares, crash),
                            1.9), 0.85)
    # Game over jingle (2.5 s): a slow chromatic fall in two voices, a sagging
    # last note, an A1 triangle and a thud.
    q = 0.17
    lead = notes_seq([(76, q), (75, q), (74, q), (72, q * 2), (None, q), (71, q), (70, q)],
                     duty=0.5, vol=0.5, gate=0.85, decay=0.25)
    lead_end = delay(sweep(0.85, midi_hz(69), midi_hz(68), duty=0.5, vol=0.5, curve=2.0,
                           vib=0.015, vib_rate=5, r=0.3), 1.36)
    harm = notes_seq([(72, q), (71, q), (70, q), (69, q * 2), (None, q), (68, q), (67, q)],
                     duty=0.25, vol=0.2, gate=0.85, decay=0.25)
    harm_end = delay(sweep(0.85, midi_hz(64), midi_hz(63), duty=0.25, vol=0.2, curve=2.0,
                           vib=0.015, vib_rate=5, r=0.3), 1.36)
    bass = notes_seq([(45, q * 2), (44, q * 2), (43, q * 2), (None, q * 2)],
                     kind="tri", vol=0.8, gate=0.9)
    bass_end = delay(notes_seq([(33, 1.0)], kind="tri", vol=1.0, gate=1.0, decay=0.5), 1.36)
    thud = delay(sweep(0.3, 80, 35, kind="sine", vol=0.8, decay=0.1), 1.36)
    s["game_over"] = (pad(mix(lead, lead_end, harm, harm_end, bass, bass_end, thud), 2.5), 0.8)
    # Exit angry: B5/F5 alarm with a tritone double, snare hits and a rumble
    # (a different register from the timer alarm, time_low).
    s["exit_angry"] = (mix(
        notes_seq([(83, 0.09), (77, 0.09)] * 4, duty=0.5, vol=0.6, gate=0.7, decay=0.06),
        notes_seq([(77, 0.09), (71, 0.09)] * 4, duty=0.125, vol=0.25, gate=0.7, decay=0.06),
        hits(noise_burst(0.04, vol=0.5, decay=0.012, lp=0.7, rate=2), [k * 0.09 for k in range(8)]),
        noise_burst(0.72, vol=0.4, decay=0.4, lp=0.1, rate=8),
    ), 0.85)
    # Kick a bomb: click, up-chirp and a low thump.
    s["kick"] = (mix(
        noise_burst(0.015, vol=0.9, decay=0.005, lp=0.9),
        sweep(0.09, 180, 520, duty=0.25, vol=0.5, curve=0.8, decay=0.04),
        sweep(0.05, 150, 70, kind="tri", vol=0.7, decay=0.02),
    ), 0.75)
    # Freeze: a crack, an icy descending shimmer and a frosty hiss.
    shimmer = [(100 - k * 2 + (3 if k % 2 else 0), 0.03) for k in range(12)]
    s["freeze"] = (mix(
        noise_burst(0.03, vol=0.6, decay=0.008, short=True, hp=True),
        sweep(0.08, 300, 120, kind="tri", vol=0.5, decay=0.03),
        notes_seq(shimmer, kind="tri", vol=0.6, gate=0.9, decay=0.05),
        notes_seq(shimmer, duty=0.125, vol=0.25, gate=0.5, decay=0.04),
        delay(noise_burst(0.5, vol=0.12, decay=0.25, hp=True, short=True), 0.1),
    ), 0.7)
    # UI tap: tiny dry click.
    s["ui_tap"] = (mix(
        sweep(0.02, 1800, 1300, duty=0.125, vol=0.6, curve=0.5, a=0.001, r=0.006, decay=0.007),
        noise_burst(0.005, vol=0.4, decay=0.0015, lp=1.0),
    ), 0.5)
    # Boss hit: crack, crunchy low pulse, sub and a short rumble (soft-clipped).
    s["boss_hit"] = (squash(mix(
        noise_burst(0.03, vol=1.0, decay=0.008, lp=1.0),
        sweep(0.25, 180, 55, duty=0.125, vol=0.6, curve=0.5, decay=0.07),
        sweep(0.2, 90, 40, kind="sine", vol=0.9, decay=0.07),
        noise_burst(0.2, vol=0.5, decay=0.06, lp=0.4, rate=4),
    ), 1.5), 0.9)
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
    s["step_h"] = (sweep(0.03, 520, 380, duty=0.125, vol=0.5, curve=0.6, r=0.01, decay=0.012), 0.3)
    s["step_v"] = (sweep(0.03, 780, 560, duty=0.125, vol=0.5, curve=0.6, r=0.01, decay=0.012), 0.3)
    # Stage start (1.69 s, under the 2 s STAGE card): a pitch-slide pickup, a
    # staccato fanfare in thirds over a triangle bass with snares on the
    # downbeats, a fast run and a final chord on a crash and a sub thud.
    q = 0.09
    slide = sweep(0.05, 392, 523, duty=0.5, vol=0.5, curve=0.7, r=0.01)
    lead = notes_seq([(72, q), (72, q), (72, q), (None, q), (76, q), (79, q), (None, q), (84, q),
                      (None, q), (81, q)], duty=0.5, vol=0.5, gate=0.6, decay=0.12) + \
        notes_seq([(76, 0.03), (79, 0.03), (83, 0.03)], duty=0.125, vol=0.45)
    lead_final = delay(notes_seq([(84, 0.7)], duty=0.5, vol=0.55, gate=1.0, decay=0.3), 0.99)
    harm = notes_seq([(67, q), (67, q), (67, q), (None, q), (72, q), (76, q), (None, q), (79, q),
                      (None, q), (77, q)], duty=0.25, vol=0.24, gate=0.6, decay=0.12)
    harm_final = delay(notes_seq([(88, 0.7)], duty=0.25, vol=0.22, gate=1.0, decay=0.3), 0.99)
    bass = notes_seq([(48, q * 3), (None, q), (52, q * 2), (None, q), (55, q * 2), (53, q)],
                     kind="tri", vol=0.85, gate=0.8, decay=0.15)
    bass_final = delay(notes_seq([(48, 0.7)], kind="tri", vol=0.9, gate=1.0, decay=0.35), 0.99)
    snares = hits(noise_burst(0.05, vol=0.45, decay=0.018, lp=0.8), [0.0, 4 * q, 7 * q])
    crash = delay(noise_burst(0.5, vol=0.7, decay=0.14, lp=0.95, lp_end=0.3), 0.99)
    sub = delay(sweep(0.2, 120, 45, kind="sine", vol=0.9, curve=0.4, decay=0.08), 0.99)
    s["stage_start"] = (mix(slide, lead, lead_final, harm, harm_final, bass, bass_final, snares,
                            crash, sub), 0.85)
    # Exit open: the last enemy is down; a clunk and a triangle bell G5/C6/G6.
    bell = [(79, 0.09), (84, 0.09), (91, 0.42)]
    s["exit_open"] = (mix(
        sweep(0.06, 200, 90, kind="tri", vol=0.8, decay=0.025),
        noise_burst(0.01, vol=0.3, decay=0.003, short=True),
        delay(notes_seq(bell, kind="tri", vol=0.9, gate=0.95, decay=0.18), 0.05),
        delay(notes_seq(bell, duty=0.5, vol=0.2, gate=0.95, decay=0.1), 0.05),
        delay(noise_burst(0.3, vol=0.12, decay=0.1, hp=True, short=True), 0.23),
    ), 0.7)
    # Timer: alarm sting at 30 s (two alternating pitches, four cycles, dry).
    s["time_low"] = (pad(mix(
        notes_seq([(88, 0.07), (81, 0.07)] * 4, duty=0.5, vol=0.6, gate=0.9, decay=0.3),
        notes_seq([(76, 0.07), (69, 0.07)] * 4, duty=0.25, vol=0.25, gate=0.9),
        hits(noise_burst(0.05, vol=0.5, decay=0.015, lp=0.8), [0.0, 0.28]),
        sweep(0.12, 110, 50, kind="sine", vol=0.7, decay=0.05),
    ), 0.6), 0.85)
    # Timer: one dry click per displayed second for 10..1.
    s["tick"] = (mix(
        sweep(0.025, 2200, 1600, duty=0.125, vol=0.6, curve=0.5, a=0.001, r=0.008),
        noise_burst(0.006, vol=0.5, decay=0.002, lp=1.0),
    ), 0.6)
    # Timer: time's up; snare roll, descending stabs, siren drop and a sub
    # thud announce the hunter swarm.
    roll = hits(noise_burst(0.03, vol=0.45, decay=0.01, lp=0.85), [k * 0.04 for k in range(8)])
    stabs = notes_seq([(88, 0.08), (84, 0.08), (81, 0.08), (76, 0.08)] * 2,
                      duty=0.5, vol=0.55, gate=0.7, decay=0.08)
    stabs_lo = notes_seq([(76, 0.08), (72, 0.08), (69, 0.08), (64, 0.08)] * 2,
                         duty=0.125, vol=0.25, gate=0.7, decay=0.08)
    siren = delay(sweep(0.3, 660, 110, duty=0.5, vol=0.6, curve=0.7, vib=0.1, vib_rate=25, r=0.05),
                  0.64)
    thud = delay(mix(sweep(0.2, 100, 38, kind="sine", vol=0.9, decay=0.08),
                     noise_burst(0.3, vol=0.6, decay=0.1, lp=0.3, rate=6)), 0.64)
    s["time_up"] = (pad(squash(mix(roll, stabs, stabs_lo, siren, thud), 1.5), 0.95), 0.9)
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


# Melody syntax: deg:len[flags]   len in eighths, may be fractional (0.5 = 16th)
# flags: ! accent  . staccato  _ legato  ~ slide from previous note  ^ / v octave
def parse_melody(text):
    bars = []
    for bar in text.split("|"):
        notes = []
        for tok in bar.split():
            deg, rest = tok.split(":")
            i = 0
            while i < len(rest) and (rest[i].isdigit() or (
                    rest[i] == "." and i + 1 < len(rest) and rest[i + 1].isdigit())):
                i += 1
            ln = float(rest[:i])
            flags = rest[i:]
            notes.append((None if deg == "r" else int(deg), ln, flags))
        bars.append(notes)
    return bars


# Each song: key (MIDI tonic of the lead octave), mode, bpm, beats per bar,
# then sections of chord root degrees per bar with a hand-written melody
# (scale degrees, lengths in eighths) and style choices for the other
# channels. Section keys override song keys. `hurry` renders a whole step up
# with a clipped lead, louder drums and an alarm arpeggio every bar.
FOUND_A = """0:0.5! 2:0.5 4:0.5 7:0.5 9:2 7:1 4:1 7:1 9:1 |
             8:1! 7:0.5 8:0.5 6:1 4:1 2:2 4:1 6:1 |
             9:1! 9:0.5. 9:0.5. 11:1 9:1 7:1 5:1 7:1 9:1 |
             8:1! 7:1 5:1 3:1 4:1. 5:1. 6:1. 7:1."""

SONGS = {
    "menu": dict(
        name="menu", tonic=72, mode="major", bpm=112, beats=4, swing=0.08,
        lead_duty=[0.5, 0.25], lead_env=dict(d=0.08, s=0.5),
        sections=[
            dict(chords=[0, 5, 3, 4],
                 melody="""4:2! 2:1 4:1 7:2! 4:2 | 5:3! 4:1 2:2 0:2 |
                           3:2! 5:1 7:1 8:2! 7:2 | 6:3! 4:1 1:2 r:2""",
                 harm="offbeat", bass="rootfifth", drums=["K-h-S-h-k-h-S-h-"], crash=False,
                 drum_vol=0.8, harm_vol=0.85),
            dict(chords=[5, 3, 1, 4],
                 melody="""9:2! 7:1 5:1 7:1 9:1 11:2 | 10:2! 8:1 7:1 5:2 3:2 |
                           5:1! 3:1 5:2 8:1 7:1 6:2 | 8:2! 7:1 6:1 4:4_""",
                 harm=["thirds", "stab"], bass="walk", lead_duty=[0.25, 0.5],
                 drums=["K-h-S-hoK-h-S-oh"], lead_vol=1.1, fill="k-sS-s-S"),
        ],
    ),
    "w1": dict(
        name="w1", tonic=67, mode="major", bpm=126, beats=4, swing=0.12,
        lead_env=dict(d=0.09, s=0.45),
        sections=[
            dict(chords=[0, 3, 4, 0],
                 melody="""4:1! 4:0.5. 4:0.5. 7:1 6:0.5 7:0.5 4:2 2:1 0:1 |
                           3:1! 5:1 7:2 5:0.5 7:0.5 8:1 7:1 5:1 |
                           4:1! 6:1 8:2 6:1 4:1 1:1 2:1 |
                           0:1 2:1 4:1! 7:1_ 7:2 r:2""",
                 harm="arp16", bass="synco", lead_duty=[0.125, 0.25],
                 drums=["K-h-S-h-k-h-S-hh"], fill="k-ssk-SS", drum_vol=0.8, harm_vol=0.85),
            dict(chords=[5, 3, 1, 4],
                 melody="""9:2! 7:1 5:1 7:1.5 9:0.5 7:2 | 8:2! 7:1 5:1 3:1~ 5:1 7:2 |
                           5:1! 3:1 5:1 8:1 7:0.5 6:0.5 5:0.5 3:0.5 1:2 |
                           2:1 4:1 6:1 8:1! 11:2_ 11:1 r:1""",
                 harm=["thirds", "stab"], bass="walk", lead_duty=[0.25, 0.5], lead_vol=1.1,
                 drums=["K-hoS-h-K-h-S-ho"], fill="k-sS-tTS"),
        ],
    ),
    "w2": dict(
        name="w2", tonic=62, mode="dorian", bpm=100, beats=4, lp=0.7,
        lead_env=dict(d=0.1, s=0.7), lead_gate=0.92,
        sections=[
            dict(chords=[0, 0, 6, 6],
                 melody="""0:2! 2:1 4:3 r:2 | 3:1 2:1 0:2 r:4 | 6:2! 1:1 3:3 r:2 |
                           4:1 3:1 1:2 -1:4_""",
                 harm="echo", bass="drone", lead_duty=0.5, kit="metal",
                 drums=["K-----h-S-----h-", "K-----h-S---k-h-"], crash=False, fill="t-t-T-S-"),
            dict(chords=[3, 3, 4, 6],
                 melody="""3:2! 5:1 7:3 r:2 | 9:1! 7:1 5:2 3:2 2:2 | 4:3! 6:1 8:2 7:2 |
                           6:2! 5:1 4:1 3:2 1:2""",
                 harm=["thirds", "echo"], bass="octave", lead_duty=[0.125, 0.25], lead_vol=1.1,
                 kit="metal", drums=["K-h-h-S-h-k-h-S-"], fill="t-tt-T-S"),
        ],
    ),
    "w3": dict(
        name="w3", tonic=76, mode="lydian", bpm=108, beats=4,
        lead_env=dict(d=0.12, s=0.7), lead_gate=0.9,
        sections=[
            dict(chords=[0, 1, 0, 1],
                 melody="""4:4! 3:2 4:2 | 5:4! 3:2 1:2 | 7:3! 6:1 4:4_ | 8:2! 5:2 3:4""",
                 harm="sparkle", bass="rootfifth", lead_duty=0.25,
                 drums=["K---h---S---h--h"], fill="r-r-S-rr", drum_vol=0.8),
            dict(chords=[5, 3, 1, 4],
                 melody="""2:2! 5:2 7:4_ | 7:2! 5:2 3:2 0:2 | 1:3! 3:1 5:2 8:2 | 6:4! 4:2 r:2""",
                 harm=["thirds", "sparkle"], bass="walk", lead_duty=[0.25, 0.5], lead_vol=1.1,
                 echo=((2, 0.08),), drums=["K-h-h-S-h-k-h-S-"], fill="r-rS-rSS"),
        ],
    ),
    "w4": dict(
        name="w4", tonic=69, mode="harmonic_minor", bpm=132, beats=3, vibrato=0.012,
        lead_env=dict(d=0.08, s=0.55),
        sections=[
            dict(chords=[0, 0, 3, 3],
                 melody="""4:2! 3:1 2:1 1:1 2:1 | 0:4! -3:2~ | 3:2! 5:2 7:2 | 6:3! 5:1 3:2""",
                 harm="waltz", bass="waltz", lead_duty=0.125, drums=["K---h-S-h---"],
                 crash=False, fill="t-tT-S", drum_vol=0.8, harm_vol=0.85),
            dict(chords=[5, 5, 4, 4],
                 melody="""5:2! 7:2 9:2 | 8:3! 7:1 5:2 | 4:2! 6:2 8:2 | 7:3! 6:3_""",
                 harm=["waltz", "thirds"], bass="waltz", lead_duty=0.25, lead_vol=1.1,
                 drums=["K---h-S-h-h-"], fill="t-tT-S"),
            dict(chords=[0, 3, 4, 4],
                 melody="""7:2! 4:1 2:1 0:2 | 3:2! 5:1 3:1 2:2 | 1:2! 4:2 6:2 | 4:4! r:2""",
                 harm=["chipchord", "thirds"], bass="octave", lead_duty=[0.125, 0.5],
                 lead_vol=1.15, drums=["K-h-S-h-S-hh"], fill="K-tT-S"),
        ],
    ),
    "w5": dict(
        name="w5", tonic=72, mode="phrygian", bpm=152, beats=4,
        lead_env=dict(d=0.07, s=0.5),
        sections=[
            dict(chords=[0, 0, 1, 0],
                 melody="""0:1! 0:1. 2:1 0:1 3:2 2:2 | 1:1 0:1 -1:2~ 0:4_ |
                           1:1! 1:1. 3:1 1:1 5:2 3:2 | 2:1 1:1 0:2 r:4""",
                 harm="power", bass="root8", lead_duty=[0.125, 0.5],
                 drums=["K-h-S-hkK-h-S-h-"], fill="k-sS-ttT", drum_vol=0.85, harm_vol=0.85),
            dict(chords=[5, 6, 0, 0],
                 melody="""7:2! 5:1 7:1 9:2 7:2 | 8:2! 6:1 4:1 6:4_ |
                           7:1! 7:1. 9:1 7:1 11:2 9:2 | 8:1 7:1 6:2 7:4_""",
                 harm="stab", bass="synco", lead_duty=0.25, lead_vol=1.05,
                 drums=["K-h-S-hkK-hkS-sS"], fill="k-sS-ttT"),
            dict(chords=[3, 5, 1, 1],
                 melody="""3:2! 5:2 7:2 5:2 | 5:1 7:1 9:2! 8:2 7:2 | 8:2! 1:2 3:2 5:2 |
                           6:1 5:1 3:1 1:1 8:4!""",
                 harm=["thirds", "power"], bass="walk", lead_duty=0.5, lead_vol=1.15,
                 lead_double=dict(octave=1, duty=0.125, vol=0.25),
                 drums=["K-k-S-k-K-k-S-kk"], fill="K-SSk-tT"),
        ],
    ),
    "found": dict(
        name="found", tonic=72, mode="major", bpm=150, beats=4, swing=0.06,
        lead_env=dict(d=0.07, s=0.45),
        sections=[
            dict(chords=[0, 4, 5, 3], melody=FOUND_A,
                 harm="chipchord", bass="octave", lead_duty=[0.125, 0.25],
                 drums=["K-hhS-hhk-hhS-hh"], fill="k-sS-sSS", drum_vol=0.8, harm_vol=0.85),
            dict(chords=[1, 4, 5, 3],
                 melody="""5:1.5! 5:0.5 3:1 1:1 3:1 5:1 8:2 |
                           8:1! 6:1 4:1 6:1 8:0.5 9:0.5 8:0.5 6:0.5 4:2 |
                           9:1! 11:1 9:1 7:1 5:1 7:1 9:2_ |
                           10:1! 9:1 7:1 5:1 7:1 9:1 11:2""",
                 harm="arp16", bass="walk", lead_duty=[0.25, 0.5], lead_vol=1.1,
                 drums=["K-hoS-hhK-hoS-oh"], fill="k-sS-tTS"),
            dict(chords=[0, 4, 5, 3], melody=FOUND_A,
                 harm=["thirds", "stab"], bass="synco", lead_duty=0.5, lead_vol=1.15,
                 lead_double=dict(octave=1, duty=0.125, vol=0.22),
                 drums=["K-hhS-hhK-hhS-oh"], fill="K-SSk-tT"),
        ],
    ),
}


# A loop buffer. Notes that run past the end wrap around to the start, so the
# loop is seamless by construction.
class Track:
    def __init__(self, n):
        self.n = n
        self.buf = [0.0] * n

    def add_tone(self, start, length, freq, vol, kind="sq", duty=0.5, a=0.003,
                 d=0.06, s=0.6, r=0.02, vib=0.0, vib_rate=5.5, vib_delay=0.15,
                 decay=None, bend=0.0, bend_len=0.03, detune=0.0):
        if length <= 0:
            return
        ph = 0.0
        n = self.n
        buf = self.buf
        vd = int(vib_delay * SR)
        bl = max(1, int(bend_len * SR))
        seq = duty if isinstance(duty, (list, tuple)) else None
        frame = SR // 60
        for i in range(length):
            f = freq * (1.0 + detune)
            if bend and i < bl:
                f *= 2.0 ** (bend * (1.0 - i / bl) / 12.0)
            if vib and i > vd:
                f *= 1.0 + vib * math.sin(2 * math.pi * vib_rate * (i - vd) / SR)
            ph += f / SR
            dt = seq[min(len(seq) - 1, i // frame)] if seq else duty
            e = env_adsr(i, length, a=a, d=d, s=s, r=r)
            if decay:
                e *= math.exp(-i / SR / decay)
            buf[(start + i) % n] += wave_fn(kind, ph, dt) * e * vol

    def add_samples(self, start, samples, gain=1.0):
        n = self.n
        buf = self.buf
        for i, v in enumerate(samples):
            buf[(start + i) % n] += v * gain


def drum_kit(kind="std"):
    kick = mix(sweep(0.12, 150, 40, kind="tri", vol=1.0, curve=0.4, r=0.02),
               noise_burst(0.02, vol=0.4, decay=0.008, lp=0.5),
               sweep(0.01, 1200, 600, duty=0.5, vol=0.5))  # click so it cuts through
    if kind == "metal":
        snare = noise_burst(0.12, vol=0.7, decay=0.04, lp=0.9, rate=2, short=True)
        hat = noise_burst(0.025, vol=0.35, decay=0.008, hp=True, short=True)
    else:
        snare = noise_burst(0.14, vol=0.7, decay=0.05, lp=0.8, rate=1)
        hat = noise_burst(0.035, vol=0.35, decay=0.012, hp=True, short=True)
    ohat = noise_burst(0.09, vol=0.4, decay=0.045, hp=True, short=True)
    crash = noise_burst(0.45, vol=0.6, decay=0.22, lp=0.9, lp_end=0.3)
    tom = sweep(0.10, 260, 140, kind="tri", vol=0.9, curve=0.5)
    rim = noise_burst(0.02, vol=0.5, decay=0.006, lp=0.9, short=True)
    return {"k": kick, "s": snare, "h": hat, "o": ohat, "c": crash, "t": tom, "r": rim}


KITS = {}


def render_song(spec, tempo_mult=1.0, hurry=False):
    sections = spec.get("sections") or [dict(chords=spec["chords"], melody=spec["melody"])]
    chords, melody, sec_of_bar = [], [], []
    for si, sec in enumerate(sections):
        m = parse_melody(sec["melody"])
        assert len(m) == len(sec["chords"]), (spec.get("name"), si, len(m), len(sec["chords"]))
        chords += list(sec["chords"])
        melody += m
        sec_of_bar += [si] * len(m)

    def S(b, key, default=None):
        sec = sections[sec_of_bar[b]]
        return sec.get(key, spec.get(key, default))

    bpm = spec["bpm"] * tempo_mult
    beats = spec["beats"]
    mode = spec["mode"]
    tonic = spec["tonic"] + (spec.get("hurry_up", 2) if hurry else 0)
    nbars = len(chords)
    eighths_per_bar = beats * 2
    for bi, bar in enumerate(melody):
        tot = sum(ln for _, ln, _ in bar)
        assert abs(tot - eighths_per_bar) < 1e-9, (spec.get("name"), bi, tot, bar)

    sixteenth = 60.0 / bpm / 4.0
    spb = beats * 4
    total_steps = nbars * spb
    n = int(round(total_steps * sixteenth * SR))
    swing = spec.get("swing", 0.0)

    def pos(step):
        st = step + (swing if step % 2 else 0.0)
        return int(round(st * n / total_steps))

    def span(step, steps):
        return pos(step + steps) - pos(step)

    def midi(d, octave=0):
        return tonic + degree_to_semi(mode, d) + 12 * octave

    def note(d, octave=0):
        return midi_hz(midi(d, octave))

    lead = Track(n)
    harm = Track(n)
    bass = Track(n)
    drums = Track(n)
    alarm = Track(n)
    vib_base = spec.get("vibrato", 0.006)

    # ---- Lead -------------------------------------------------------------
    step = 0
    lead_events = []  # (step, steps, deg, bar)
    prev_midi = None
    for b, bar in enumerate(melody):
        duty = S(b, "lead_duty")
        env = dict(S(b, "lead_env", {}))
        gate_def = S(b, "lead_gate", 0.85)
        lvol = S(b, "lead_vol", 1.0)
        loct = S(b, "lead_octave", 0)
        dbl = S(b, "lead_double")
        for deg, ln, flags in bar:
            stf = ln * 2
            steps = int(round(stf))
            assert abs(stf - steps) < 1e-9, (spec.get("name"), b, ln)
            if deg is not None:
                octv = loct + (1 if "^" in flags else 0) - (1 if "v" in flags else 0)
                acc = 1.0 if step % spb == 0 else (0.85 if step % 4 == 0 else 0.72)
                vol = 0.34 * acc * lvol * (1.25 if "!" in flags else 1.0)
                gate = 0.5 if "." in flags else (1.0 if "_" in flags else gate_def)
                if hurry:
                    gate = min(gate, 0.8)
                kw = dict(env)
                if "_" in flags:
                    kw["a"] = 0.0005
                if hurry:
                    kw.setdefault("d", 0.05)
                    kw["s"] = min(kw.get("s", 0.6), 0.45)
                m_now = midi(deg, octv)
                if "~" in flags and prev_midi is not None:
                    kw["bend"] = prev_midi - m_now
                    kw["bend_len"] = 0.06
                elif "!" in flags:
                    kw["bend"] = -1.5
                    kw["bend_len"] = 0.025
                v = vib_base * min(1.0, steps / 8.0) if steps >= 4 else 0.0
                length = int(span(step, steps) * gate)
                lead.add_tone(pos(step), length, midi_hz(m_now), vol, duty=duty, vib=v,
                              vib_rate=spec.get("vib_rate", 5.5), **kw)
                if dbl:
                    lead.add_tone(pos(step), length, midi_hz(m_now + 12 * dbl.get("octave", 1)),
                                  vol * dbl.get("vol", 0.3), duty=dbl.get("duty", 0.125),
                                  detune=dbl.get("detune", 0.003), **env)
                lead_events.append((step, steps, deg, b, octv))
                prev_midi = m_now
            step += steps

    # ---- Harmony ----------------------------------------------------------
    prev_voicing = None
    for b, root in enumerate(chords):
        styles = S(b, "harm", [])
        if isinstance(styles, str):
            styles = [styles]
        hv = S(b, "harm_vol", 1.0)
        triad = [root, root + 2, root + 4]
        base = b * spb
        for style in styles:
            if style == "arp16":
                pat = [0, 1, 2, 1]
                for k in range(spb):
                    d = triad[pat[k % 4]]
                    acc = 1.0 if k % 4 == 0 else 0.7
                    harm.add_tone(pos(base + k), int(span(base + k, 1) * 0.8), note(d, -1),
                                  0.18 * acc * hv, duty=0.125, d=0.03, s=0.4)
            elif style == "sparkle":
                pat = [0, 1, 2, 3, 2, 1]
                for k in range(spb):
                    p = pat[k % 6]
                    d = triad[p] if p < 3 else root + 7
                    acc = 1.0 if k % 4 == 0 else 0.7
                    harm.add_tone(pos(base + k), int(span(base + k, 1) * 0.7), note(d, 0),
                                  0.14 * acc * hv, duty=0.125, d=0.02, s=0.3, decay=0.08)
            elif style == "offbeat":
                for k in range(2, spb, 4):
                    for j, d in enumerate(triad):
                        for t in range(2):
                            st = pos(base + k) + int((j + 3 * t) * 0.012 * SR)
                            harm.add_tone(st, int(0.012 * SR), note(d, -1), 0.20 * hv,
                                          duty=0.25, a=0.001, d=0.0, s=1.0, r=0.002)
            elif style == "stab":
                # Off-beat 8th chip-arp stabs (2 cycles through the triad).
                for k in range(2, spb, 4):
                    for j, d in enumerate(triad):
                        for t in range(2):
                            st = pos(base + k) + int((j + 3 * t) * 0.009 * SR)
                            harm.add_tone(st, int(0.009 * SR), note(d, 0), 0.20 * hv,
                                          duty=0.125, a=0.001, d=0.0, s=1.0, r=0.002)
            elif style == "waltz":
                for beat in (1, 2):
                    st0 = pos(base + beat * 4)
                    L = int(span(base + beat * 4, 3))
                    cyc = int(0.02 * SR)
                    k = 0
                    while k * cyc < L:
                        d = triad[k % 3]
                        harm.add_tone(st0 + k * cyc, cyc, note(d, -1),
                                      0.16 * hv * math.exp(-k * cyc / SR / 0.25),
                                      duty=0.25, a=0.001, d=0.0, s=1.0, r=0.002)
                        k += 1
            elif style == "power":
                for k in range(0, spb, 2):
                    L = int(span(base + k, 2) * 0.6)
                    acc = 1.0 if k % 4 == 0 else 0.75
                    harm.add_tone(pos(base + k), L, note(root, -1), 0.12 * acc * hv, duty=0.5,
                                  d=0.04, s=0.5)
                    harm.add_tone(pos(base + k), L, note(root + 4, -1), 0.10 * acc * hv,
                                  duty=0.5, d=0.04, s=0.5)
            elif style == "chipchord":
                # Sustained chord cycled per 60 Hz frame, re-struck on beats 1 and 3,
                # inversion chosen for the smallest movement from the previous bar.
                cands = [triad, [triad[1], triad[2], triad[0] + 7],
                         [triad[2], triad[0] + 7, triad[1] + 7]]
                if prev_voicing is None:
                    voicing = triad
                else:
                    voicing = min(cands, key=lambda c: abs(c[0] - prev_voicing[0]))
                prev_voicing = voicing
                cyc = SR // 60
                for beat in range(0, beats, 2):
                    st0 = pos(base + beat * 4)
                    L = int(span(base + beat * 4, min(8, spb - beat * 4)) * 0.95)
                    k = 0
                    while k * cyc < L:
                        d = voicing[k % 3]
                        harm.add_tone(st0 + k * cyc, cyc, note(d, -1),
                                      0.16 * hv * math.exp(-k * cyc / SR / 0.45),
                                      duty=0.25, a=0.001, d=0.0, s=1.0, r=0.002)
                        k += 1
            elif style == "thirds":
                pass  # handled below (needs lead events)
    # thirds: a diatonic third below every lead note of a quarter or longer.
    for st, steps, deg, b, octv in lead_events:
        styles = S(b, "harm", [])
        if isinstance(styles, str):
            styles = [styles]
        if "thirds" in styles and steps >= 4:
            env = dict(S(b, "lead_env", {}))
            hv = S(b, "harm_vol", 1.0)
            acc = 1.0 if st % spb == 0 else 0.8
            harm.add_tone(pos(st), int(span(st, steps) * 0.85), note(deg - 2, octv),
                          0.20 * acc * hv, duty=0.25, **env)
    # Generic echo send (section-aware); "echo" harm style is an alias.
    for st, steps, deg, b, octv in lead_events:
        styles = S(b, "harm", [])
        if isinstance(styles, str):
            styles = [styles]
        taps = S(b, "echo")
        if taps is None and "echo" in styles:
            taps = ((3, 0.13), (6, 0.06))
        if not taps:
            continue
        for dl, v in taps:
            length = int(span(st, steps) * 0.85)
            harm.add_tone(pos(st + dl), length, note(deg, octv), v, duty=0.125,
                          vib=vib_base if steps >= 4 else 0.0)

    # ---- Bass -------------------------------------------------------------
    for b, root in enumerate(chords):
        bstyle = S(b, "bass")
        bv = S(b, "bass_vol", 1.0)
        base = b * spb
        nxt = chords[(b + 1) % nbars]
        r0 = note(root, -2)
        fifth = note(root + 4, -2)
        if bstyle == "octave":
            for k in range(0, spb, 2):
                f = r0 if (k // 2) % 2 == 0 else r0 * 2
                bass.add_tone(pos(base + k), int(span(base + k, 2) * 0.8), f, 0.45 * bv,
                              kind="tri", d=0.02, s=0.9)
        elif bstyle == "rootfifth":
            for k in range(0, spb, 4):
                f = r0 if (k // 4) % 2 == 0 else fifth
                bass.add_tone(pos(base + k), int(span(base + k, 4) * 0.85), f, 0.5 * bv,
                              kind="tri", d=0.02, s=0.9)
        elif bstyle == "drone":
            bass.add_tone(pos(base), int(span(base, spb - 6) * 0.95), r0, 0.5 * bv,
                          kind="tri", d=0.3, s=0.7, r=0.08)
            bass.add_tone(pos(base + spb - 4), int(span(base + spb - 4, 4) * 0.8), fifth,
                          0.4 * bv, kind="tri", d=0.05, s=0.8)
        elif bstyle == "waltz":
            bass.add_tone(pos(base), int(span(base, 4) * 0.9), r0, 0.55 * bv, kind="tri",
                          d=0.05, s=0.8)
        elif bstyle == "root8":
            for k in range(0, spb, 2):
                f = r0 if k != spb - 2 else r0 * 2
                bass.add_tone(pos(base + k), int(span(base + k, 2) * 0.7), f, 0.5 * bv,
                              kind="tri", d=0.02, s=0.9)
        elif bstyle == "walk":
            app = nxt - 1 if b % 2 == 0 else nxt + 1
            degs = ([root, root + 2, root + 4, root + 7, root + 4, root + 2, app, app]
                    if beats == 4 else [root, root + 2, root + 4, root + 7, root + 4, app])
            for k8, d in enumerate(degs):
                k = k8 * 2
                bass.add_tone(pos(base + k), int(span(base + k, 2) * 0.75), note(d, -2),
                              0.5 * bv * (1.0 if k8 == 0 else 0.85), kind="tri", d=0.02, s=0.9)
        elif bstyle == "synco":
            ev = ([(0, 3, 0), (3, 1, 0), (4, 2, 0), (6, 2, 1), (8, 3, 0), (11, 1, 0),
                   (12, 2, 0), (14, 2, 1)] if beats == 4 else
                  [(0, 3, 0), (3, 1, 0), (4, 2, 0), (6, 3, 1), (9, 1, 0), (10, 2, 0)])
            for st, L, up in ev:
                bass.add_tone(pos(base + st), int(span(base + st, L) * 0.8), r0 * (2 if up else 1),
                              0.5 * bv * (1.0 if st == 0 else 0.85), kind="tri", d=0.02, s=0.9)

    # ---- Drums ------------------------------------------------------------
    kick_pos = []
    half = spb // 2
    for b in range(nbars):
        kit_name = S(b, "kit", "std")
        if kit_name not in KITS:
            KITS[kit_name] = drum_kit(kit_name)
        kit = KITS[kit_name]
        pats = S(b, "drums_hurry") if hurry and S(b, "drums_hurry") else S(b, "drums")
        pat = pats[b % len(pats)]
        if (b + 1) % 4 == 0:
            fill = S(b, "fill", "k-ssk-SS" if beats == 4 else "t-tT-S")
            fill = (fill + "-" * spb)[: spb - half]
            pat = pat[:half] + fill
        base = b * spb
        dg = S(b, "drum_vol", 1.0)
        if b % 4 == 0 and S(b, "crash", True):
            drums.add_samples(pos(base), kit["c"], 0.8 * dg)
        for k in range(spb):
            c = pat[k % len(pat)]
            gain = (1.0 if c.isupper() else 0.6) * dg
            c = c.lower()
            if hurry and c == "-" and k % 2 == 1:
                c, gain = "h", 0.6 * dg
            if c in kit:
                drums.add_samples(pos(base + k), kit[c], gain)
                if c == "k":
                    kick_pos.append(pos(base + k))
    # Duck the bass under each kick so the kick is not masked.
    L = int(0.04 * SR)
    for p in kick_pos:
        for i in range(L):
            bass.buf[(p + i) % n] *= 0.3 + 0.7 * i / L

    # ---- Hurry alarm: rising chip arpeggio on the last beat of every bar ----
    if hurry:
        for b, root in enumerate(chords):
            base = b * spb
            if (b + 1) % 4 == 0:
                degs = [0, 2, 4, 7, 9, 11, 14, 16][:half]
                start = base + half
            else:
                degs = [0, 2, 4, 7]
                start = base + spb - 4
            for j, d in enumerate(degs):
                st = start + j
                alarm.add_tone(pos(st), int(span(st, 1) * 0.9), note(root + d, 1),
                               0.30 * (1.0 if j == len(degs) - 1 else 0.8), duty=0.125,
                               a=0.001, d=0.03, s=0.5, bend=-2.0, bend_len=0.015)

    # ---- Mix --------------------------------------------------------------
    mel = [0.0] * n
    for t, g in ((lead, 1.0), (harm, 1.0), (bass, 0.85), (alarm, 1.0)):
        for i, v in enumerate(t.buf):
            mel[i] += v * g
    # One-pole low-pass tames aliasing of the naive pulses. Run it twice
    # around the loop so the filter state at the seam is steady.
    k = spec.get("lp", 0.8)
    y = 0.0
    filt = [0.0] * n
    for _ in range(2):
        for i in range(n):
            y += k * (mel[i] - y)
            filt[i] = y
    # Drums join unfiltered, then a soft limiter glues the bus.
    dg = 0.55 * (1.3 if hurry else 1.0)
    out = [0.0] * n
    drive = 1.2
    pre = 0.75
    norm = math.tanh(drive)
    for i in range(n):
        x = (filt[i] + drums.buf[i] * dg) * pre
        out[i] = math.tanh(drive * x) / norm
    return out


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
