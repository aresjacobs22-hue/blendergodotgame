#!/usr/bin/env python3
"""
Synthesizes every sound in ACHROMA from scratch (no samples, no downloads).

Outputs (all mono Ogg Vorbis, ready to upload to Roblox):
  assets/audio/ACHROMA_SFX.ogg        one "audio atlas" holding every sound effect
  assets/audio/ACHROMA_AMBIENCE.ogg   a second atlas: each night's ambience loop and chase music
  assets/audio/ACHROMA_MUSICBOX.ogg   wind-down music box for the menu / intermission
and the Luau table describing where each effect lives inside the atlas:
  src/ReplicatedStorage/Shared/SoundAtlas.luau

The atlas lets the whole game run on 3 uploaded audio assets instead of ~30,
using Sound.PlaybackRegion / LoopRegion to play slices of one file.

Requirements: python3, numpy, ffmpeg (with libvorbis).
Usage:  python3 tools/generate_audio.py
"""

import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
ATLAS_LUAU = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "SoundAtlas.luau")

rng = np.random.default_rng(1337)


# ----------------------------------------------------------------------------
# DSP helpers
# ----------------------------------------------------------------------------

def secs(n):
    return np.arange(n) / SR


def samples(dur):
    return int(round(dur * SR))


def noise(n):
    return rng.standard_normal(n)


def _response(f, lo=None, hi=None, order=2, peaks=()):
    H = np.ones_like(f)
    fs = np.maximum(f, 1e-6)
    if hi:
        H *= 1.0 / np.sqrt(1.0 + (fs / hi) ** (2 * order))
    if lo:
        H *= 1.0 / np.sqrt(1.0 + (lo / fs) ** (2 * order))
    if peaks:
        P = np.zeros_like(f)
        for fc, q, gain in peaks:
            P += gain / np.sqrt(1.0 + (q * (fs / fc - fc / fs)) ** 2)
        H *= P
    return H


def filt(x, lo=None, hi=None, order=2, peaks=(), circular=False):
    """Zero-phase FFT filter. circular=True keeps loops seamless; otherwise pads."""
    n = len(x)
    pad = 0 if circular else samples(0.5)
    xp = np.concatenate([x, np.zeros(pad)])
    X = np.fft.rfft(xp)
    f = np.fft.rfftfreq(len(xp), 1.0 / SR)
    y = np.fft.irfft(X * _response(f, lo, hi, order, peaks), len(xp))
    return y[:n]


def svf(x, fc, q=2.0, mode="bp"):
    """Chamberlin state-variable filter with time-varying cutoff (fc may be an array)."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    f = 2.0 * np.sin(np.pi * np.clip(fc, 20.0, SR / 6.5) / SR)
    damp = 1.0 / q
    low = band = 0.0
    out = np.empty(n)
    for i in range(n):
        low += f[i] * band
        high = x[i] - low - damp * band
        band += f[i] * high
        out[i] = band if mode == "bp" else (low if mode == "lp" else high)
    return out


def fftconv(a, b):
    n = len(a) + len(b) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)[:n]


def reverb(x, decay=2.0, mix=0.35, damp=4000.0, predelay=0.015, tail=True):
    n_ir = samples(decay)
    t = secs(n_ir)
    ir = noise(n_ir) * np.exp(-t * 6.9 / decay)
    ir = filt(ir, hi=damp, circular=True)
    ir[: samples(predelay)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    wet = fftconv(x, ir)
    if not tail:
        wet = wet[: len(x)]
    out = np.zeros(len(wet))
    out[: len(x)] += x * (1.0 - mix)
    out += wet * mix * 0.9
    return out


def drive(x, amount):
    return np.tanh(amount * x) / np.tanh(amount)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-12
    return x * (peak / m)


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    a, b = samples(fin), samples(fout)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def env_exp(n, tau, attack=0.002):
    t = secs(n)
    e = np.exp(-t / tau)
    a = samples(attack)
    if a:
        e[:a] *= np.linspace(0, 1, a)
    return e


def osc_phase(freq):
    """Integrate an instantaneous-frequency array into phase (radians)."""
    return 2 * np.pi * np.cumsum(freq) / SR


def saw(phase):
    return 2.0 * ((phase / (2 * np.pi)) % 1.0) - 1.0


def smooth_noise(n, rate_hz, circular=False):
    """Band-limited random wiggle in [-1, 1]."""
    x = filt(noise(n), hi=rate_hz, order=4, circular=circular)
    return x / (np.max(np.abs(x)) + 1e-12)


def place(dst, src, at):
    """Mix src into dst starting at sample index `at` (clips at the end)."""
    end = min(len(dst), at + len(src))
    if end > at:
        dst[at:end] += src[: end - at]


def place_wrapped(dst, src, at):
    """Mix src into a loop buffer, wrapping around the end (seamless loops)."""
    idx = (np.arange(len(src)) + at) % len(dst)
    np.add.at(dst, idx, src)


def make_loop_seamless(x, xfade):
    """Crossfade the tail beyond the loop length into the head."""
    n = len(x) - xfade
    out = x[:n].copy()
    ramp = np.linspace(0, 1, xfade)
    out[:xfade] = x[:xfade] * ramp + x[n:] * (1 - ramp)
    return out


# ----------------------------------------------------------------------------
# Building blocks
# ----------------------------------------------------------------------------

def thud(dur=0.35, f_start=75.0, f_end=38.0, tau=0.09, click=0.35, crack=0.0):
    n = samples(dur)
    t = secs(n)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.04)
    body = np.sin(osc_phase(f)) * env_exp(n, tau)
    hit = filt(noise(n), hi=900) * env_exp(n, 0.018) * click
    out = body + hit
    if crack > 0:
        c = filt(noise(n), lo=2500) * env_exp(n, 0.004)
        place(out, c * crack, samples(0.025))
    return fade(out, 0.0005, 0.02)


def metal_hit(base, ratios, dur, tau, detune=0.002):
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for i, r in enumerate(ratios):
        f = base * r * (1 + rng.uniform(-detune, detune))
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (tau / (1 + 0.35 * i))) / (1 + 0.5 * i)
    out += filt(noise(n), lo=2000) * env_exp(n, 0.006) * 0.6
    return out


def scream_voice(dur, p_start, p_peak, p_end, harsh=1.0, seed_shift=0.0):
    n = samples(dur)
    t = secs(n)
    rise = np.clip(t / 0.22, 0, 1)
    fall = np.clip((t - dur * 0.62) / (dur * 0.38), 0, 1)
    pitch = p_start + (p_peak - p_start) * (1 - (1 - rise) ** 3)
    pitch = pitch * (1 - fall) + p_end * fall
    pitch = pitch * (1 + 0.035 * np.sin(2 * np.pi * (6.5 + seed_shift) * t) + 0.05 * smooth_noise(n, 18))
    out = np.zeros(n)
    for k, det in enumerate([0.0, 0.013, -0.019, 0.031, -0.041]):
        out += saw(osc_phase(pitch * (1 + det)) + rng.uniform(0, 6.28)) / (1 + 0.3 * k)
    breath = svf(noise(n), pitch * 2.6, q=3.0) * 1.4
    out = out + breath
    out = filt(out, lo=180, peaks=((850, 4, 1.0), (1500, 5, 0.9), (2700, 6, 0.75), (3800, 5, 0.4), (5000, 1.2, 0.2)))
    ring = np.sin(2 * np.pi * 1373 * t)
    out = out * (1 - 0.35 * harsh) + out * ring * 0.35 * harsh
    env = np.minimum(1, t / 0.025) * (1 - fall ** 1.5)
    return drive(normalize(out * env), 3.5 * harsh + 1)


# ----------------------------------------------------------------------------
# Sounds
# ----------------------------------------------------------------------------

def snd_heartbeat():
    lub = thud(0.32, 68, 42, 0.07, click=0.15)
    dub = thud(0.30, 58, 36, 0.06, click=0.1) * 0.7
    out = np.zeros(samples(0.75))
    place(out, lub, 0)
    place(out, dub, samples(0.24))
    out = filt(out, hi=220)
    return normalize(out, 0.95)


def snd_breath_loop():
    dur = 3.6
    n = samples(dur + 0.4)
    t = secs(n)
    out = np.zeros(n)
    cycle = dur / 2
    for k in range(3):
        start = k * cycle
        ins_n, exh_n = samples(cycle * 0.42), samples(cycle * 0.5)
        ins = svf(noise(ins_n), np.linspace(1500, 2300, ins_n), q=1.6) * np.sin(np.linspace(0, np.pi, ins_n)) ** 1.5
        exh = svf(noise(exh_n), np.linspace(1100, 650, exh_n), q=1.4) * np.sin(np.linspace(0, np.pi, exh_n)) ** 1.2
        place(out, ins * 0.6, samples(start))
        place(out, exh * 1.0, samples(start + cycle * 0.46))
    out = filt(out, lo=250, hi=5000)
    out = make_loop_seamless(out, samples(0.4))
    return normalize(out, 0.7)


def snd_monster_growl_loop():
    dur = 6.0
    n = samples(dur)
    t = secs(n)
    wobble = 7 * np.sin(2 * np.pi * t / dur) + 5 * smooth_noise(n, 6, circular=True)
    f0 = 52 + wobble
    # force an integer number of cycles so the loop has no click
    total = np.sum(f0) / SR
    f0 = f0 + (round(total) - total) / dur
    voice = saw(osc_phase(f0))
    fry_rate = round(24 * dur) / dur
    fry = (0.5 + 0.5 * np.sin(2 * np.pi * fry_rate * t)) ** 3
    voice = voice * (0.35 + 0.65 * fry)
    voice = filt(voice, lo=60, hi=1600, peaks=((320, 3, 1.0), (720, 4, 0.8), (1250, 5, 0.4)), circular=True)
    breath_env = np.clip(np.sin(2 * np.pi * 2 * t / dur), 0, 1) ** 1.5
    breath = filt(noise(n), lo=250, hi=2400, peaks=((600, 2, 1), (1400, 3, 0.6)), circular=True) * breath_env
    sub = np.sin(2 * np.pi * round(36 * dur) / dur * t) * 0.35
    out = normalize(voice) + normalize(breath) * 0.45 + sub
    out = drive(normalize(out), 2.6)
    return normalize(out, 0.85)


def snd_monster_scream():
    a = scream_voice(2.6, 380, 980, 260, harsh=1.0)
    b = scream_voice(2.6, 300, 760, 210, harsh=0.8, seed_shift=1.7) * 0.8
    n = len(a)
    t = secs(n)
    roar = saw(osc_phase(np.linspace(95, 60, n))) * np.exp(-t / 1.2)
    roar = filt(roar, hi=700) * 0.9
    out = a + b + roar
    out = reverb(out, decay=1.4, mix=0.22, damp=5000)
    return normalize(drive(normalize(out), 1.8), 0.97)


def snd_jumpscare():
    dur = 2.3
    n = samples(dur)
    t = secs(n)
    impact = thud(1.0, 90, 28, 0.35, click=1.0, crack=1.0)
    burst = noise(n) * env_exp(n, 0.12, attack=0.0005)
    s1 = scream_voice(dur, 900, 1500, 600, harsh=1.0)
    s2 = scream_voice(dur, 700, 1150, 420, harsh=1.0, seed_shift=2.3)
    screech = np.zeros(n)
    for f in (2450, 2731, 3120, 3555):
        screech += np.sin(osc_phase(f * (1 + 0.04 * np.sin(2 * np.pi * 11 * t))))
    screech *= np.exp(-t / 0.9) * 0.35
    out = np.zeros(n)
    place(out, impact * 1.4, 0)
    out += burst * 0.6 + s1 + s2 * 0.8 + screech
    out = drive(normalize(out), 4.0)
    out *= np.minimum(1, (dur - t) / 0.35)
    return normalize(out, 0.99)


def snd_monster_step():
    out = thud(0.45, 70, 34, 0.11, click=0.55, crack=0.5)
    out = reverb(out, decay=0.7, mix=0.2, damp=2500)
    return normalize(out, 0.95)


def snd_monster_clicks():
    dur = 1.3
    n = samples(dur)
    out = np.zeros(n)
    pos = 0.0
    while pos < dur - 0.05:
        f = rng.uniform(1800, 3600)
        cn = samples(0.012)
        c = np.sin(2 * np.pi * f * secs(cn)) * env_exp(cn, 0.0025, attack=0.0002)
        c += filt(noise(cn), lo=3000) * env_exp(cn, 0.0015) * 0.5
        place(out, c * rng.uniform(0.4, 1.0), samples(pos))
        pos += rng.choice([0.018, 0.024, 0.031, 0.045, 0.06, 0.11])
    env = np.sin(np.linspace(0, np.pi, n)) ** 0.5
    out = reverb(out * env, decay=0.8, mix=0.25, damp=7000)
    return normalize(out, 0.85)


def creak(dur, rate_lo, rate_hi, res=((280, 18), (640, 22), (1350, 25), (2450, 20))):
    n = samples(dur)
    t = secs(n)
    wig = (smooth_noise(n, 3) + 1) / 2
    rate = rate_lo + (rate_hi - rate_lo) * wig
    phase = np.cumsum(rate) / SR
    ticks = np.diff(np.floor(phase), prepend=0) > 0
    exc = ticks.astype(float) * rng.uniform(0.5, 1.0, n)
    exc += noise(n) * 0.02
    out = np.zeros(n)
    for fc, q in res:
        out += filt(exc, peaks=((fc * rng.uniform(0.97, 1.03), q, 1.0),))
    env = np.sin(np.linspace(0, np.pi, n)) ** 0.6
    return drive(normalize(out * env), 1.5)


def snd_stinger_creak():
    out = creak(2.4, 18, 85)
    out = reverb(out, decay=2.2, mix=0.4, damp=3000)
    return normalize(out, 0.8)


def snd_stinger_bang():
    n = samples(0.5)
    hit = filt(noise(n), hi=900) * env_exp(n, 0.05) + thud(0.5, 60, 30, 0.12, click=0.8)
    out = reverb(hit, decay=3.0, mix=0.7, damp=1600, predelay=0.04)
    out = filt(out, hi=1400)
    return normalize(out, 0.9)


def snd_stinger_whisper():
    dur = 2.8
    n = samples(dur)
    out = np.zeros(n)
    pos = 0.15
    vowels = [(700, 1200), (400, 2000), (300, 2300), (600, 900), (500, 1700)]
    while pos < dur - 0.35:
        syl = rng.uniform(0.12, 0.3)
        sn = samples(syl)
        f1, f2 = vowels[rng.integers(len(vowels))]
        g1, g2 = vowels[rng.integers(len(vowels))]
        src = noise(sn)
        v = svf(src, np.linspace(f1, g1, sn), q=6) + svf(src, np.linspace(f2, g2, sn), q=8) * 0.8
        v *= np.sin(np.linspace(0, np.pi, sn)) ** 1.3
        if rng.random() < 0.35:
            sib_n = samples(rng.uniform(0.06, 0.14))
            sib = filt(noise(sib_n), lo=4500, hi=9000) * np.sin(np.linspace(0, np.pi, sib_n)) * 0.8
            place(out, sib, samples(pos))
            pos += sib_n / SR * 0.7
        place(out, v, samples(pos))
        pos += syl + rng.uniform(0.02, 0.12)
    out = filt(out, lo=700, hi=8000)
    out = reverb(out, decay=1.6, mix=0.35, damp=6000)
    return normalize(out, 0.75)


def snd_stinger_scrape():
    dur = 3.0
    n = samples(dur)
    t = secs(n)
    pressure = np.clip((smooth_noise(n, 4) + 1) / 2, 0, 1) ** 1.5
    slip = (0.5 + 0.5 * np.sign(np.sin(osc_phase(35 + 25 * smooth_noise(n, 2))))) * 0.6 + 0.4
    exc = noise(n) * pressure * slip
    out = filt(exc, peaks=((523, 60, 1.0), (1187, 70, 0.8), (1873, 70, 0.9), (2711, 80, 0.7), (3907, 80, 0.5), (5120, 60, 0.3)))
    out += filt(exc, lo=1500, hi=6000) * 0.08
    env = np.minimum(1, t / 0.3) * np.minimum(1, (dur - t) / 0.6)
    out = reverb(out * env, decay=2.5, mix=0.45, damp=4500)
    return normalize(drive(normalize(out), 1.6), 0.75)


def snd_stinger_distant_scream():
    s = scream_voice(1.8, 500, 820, 300, harsh=0.5, seed_shift=0.9)
    s = filt(s, lo=250, hi=1300)
    out = reverb(s, decay=3.2, mix=0.75, damp=1500, predelay=0.05)
    return normalize(out, 0.7)


def snd_stinger_knock():
    out = np.zeros(samples(1.0))
    for i, gap in enumerate([0.0, 0.27, 0.52]):
        kn = samples(0.15)
        k = np.sin(2 * np.pi * 175 * secs(kn)) * env_exp(kn, 0.04) + filt(noise(kn), lo=400, hi=1800) * env_exp(kn, 0.02) * 0.7
        place(out, k * (1.0 if i < 2 else 1.25), samples(gap))
    out = reverb(out, decay=1.8, mix=0.4, damp=2500)
    return normalize(out, 0.85)


def snd_stinger_footsteps():
    out = np.zeros(samples(2.6))
    pos, gap, amp = 0.0, 0.38, 0.5
    for i in range(7):
        step = thud(0.3, rng.uniform(85, 110), 45, 0.05, click=0.9)
        place(out, step * amp, samples(pos))
        pos += gap
        gap *= 0.88
        amp = min(1.0, amp * 1.25) if i < 4 else amp * 0.6
    out = filt(out, hi=2200)
    out = reverb(out, decay=1.5, mix=0.4, damp=2500)
    return normalize(out, 0.85)


def snd_key_pickup():
    hit = metal_hit(330, [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166], 3.0, 1.6, detune=0.004)
    n = len(hit)
    t = secs(n)
    hit *= 1 - 0.02 * t  # sags very slightly flat... uneasy
    out = reverb(hit, decay=2.5, mix=0.35, damp=6000)
    return normalize(out, 0.8)


def snd_keypad_beep():
    n = samples(0.1)
    t = secs(n)
    out = (np.sin(2 * np.pi * 1400 * t) + 0.25 * np.sin(2 * np.pi * 2800 * t)) * env_exp(n, 0.05, attack=0.002)
    return normalize(fade(out), 0.6)


def snd_keypad_error():
    out = np.zeros(samples(0.5))
    for at in (0.0, 0.2):
        n = samples(0.16)
        t = secs(n)
        b = np.sign(np.sin(2 * np.pi * 170 * t)) * 0.6 + np.sin(2 * np.pi * 340 * t) * 0.4
        place(out, fade(filt(b, hi=2500), 0.003, 0.02), samples(at))
    return normalize(out, 0.7)


def snd_unlock():
    clunk = thud(0.4, 140, 70, 0.06, click=1.0, crack=0.6)
    latch = metal_hit(900, [1.0, 2.4, 4.1], 0.25, 0.05)
    chime = metal_hit(440, [1.0, 1.5, 2.0, 3.0], 1.6, 0.9) * 0.4
    out = np.zeros(samples(2.0))
    place(out, clunk, 0)
    place(out, latch * 0.6, samples(0.12))
    place(out, chime, samples(0.3))
    out = reverb(out, decay=1.5, mix=0.3)
    return normalize(out, 0.85)


def snd_door_open():
    out = creak(1.3, 40, 140, res=((350, 20), (820, 25), (1700, 25), (3100, 18)))
    out = reverb(out, decay=1.0, mix=0.25, damp=4000)
    return normalize(out, 0.75)


def snd_door_slam():
    n = samples(0.5)
    hit = filt(noise(n), hi=1600) * env_exp(n, 0.04) + thud(0.5, 85, 40, 0.1, click=1.0, crack=0.8)
    rattle = metal_hit(260, [1.0, 2.1, 3.3], 0.5, 0.12) * 0.15
    place(hit, rattle, samples(0.02))
    out = reverb(hit, decay=1.6, mix=0.35, damp=3000)
    return normalize(drive(normalize(out), 1.5), 0.95)


def snd_locker():
    clank = metal_hit(310, [1.0, 2.76, 5.40, 8.93], 0.7, 0.18)
    out = reverb(clank, decay=0.9, mix=0.25, damp=5000)
    return normalize(out, 0.8)


def snd_flashlight_click():
    out = np.zeros(samples(0.09))
    for at in (0.0, 0.035):
        cn = samples(0.006)
        place(out, filt(noise(cn), lo=2500) * env_exp(cn, 0.0012), samples(at))
    return normalize(out, 0.6)


def snd_battery():
    n = samples(0.45)
    t = secs(n)
    zap = np.sin(osc_phase(np.linspace(300, 2200, n))) * env_exp(n, 0.12) * 0.5
    zap += filt(noise(n), lo=3000) * env_exp(n, 0.05) * 0.3
    out = snd_flashlight_click()
    full = np.zeros(n)
    place(full, out, 0)
    full += zap
    return normalize(full, 0.7)


def snd_static_burst():
    dur = 1.1
    n = samples(dur)
    t = secs(n)
    gate = (smooth_noise(n, 40) > -0.2).astype(float) * 0.7 + 0.3
    crackle = (rng.random(n) < 0.004).astype(float) * rng.uniform(-1, 1, n) * 3
    out = filt(noise(n) * gate + crackle, lo=300, hi=6000)
    out += np.sin(2 * np.pi * 50 * t) * 0.2
    out *= np.minimum(1, t / 0.01) * np.minimum(1, (dur - t) / 0.25)
    return normalize(out, 0.75)


def snd_light_buzz_loop():
    dur = 2.0
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for h in range(1, 12):
        out += np.sin(2 * np.pi * 120 * h * t + rng.uniform(0, 6.28)) / h ** 1.1
    out = np.sign(out) * np.abs(out) ** 0.7
    crack = np.zeros(n)
    for _ in range(6):
        cn = samples(rng.uniform(0.01, 0.05))
        place_wrapped(crack, filt(noise(cn), lo=1500) * rng.uniform(0.5, 1.2), rng.integers(n))
    out = filt(out + crack, lo=90, hi=5000, circular=True)
    return normalize(out, 0.6)


def snd_escape():
    dur = 6.0
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for f in (220.0, 261.63, 329.63, 493.88, 440.0, 659.25):
        for det in (-0.003, 0.003):
            out += np.sin(2 * np.pi * f * (1 + det) * t) * (1 + 0.3 * np.sin(2 * np.pi * 0.3 * t))
    out *= np.minimum(1, t / 2.5) ** 2 * np.minimum(1, (dur - t) / 1.5)
    wash = filt(noise(n), lo=2000, hi=9000) * (t / dur) ** 2 * 0.2
    out = normalize(out) + wash
    out = reverb(out, decay=3.5, mix=0.5, damp=7000)
    return normalize(out, 0.75)


def snd_ambient_drone():
    D = 60.0
    n = samples(D)
    t = secs(n)

    def q(freq):
        return round(freq * D) / D

    def lfo(cycles):
        return np.sin(2 * np.pi * cycles * t / D + rng.uniform(0, 2 * np.pi))

    out = np.zeros(n)
    for f0, amp in [(41.2, 0.5), (41.45, 0.4), (55.0, 0.32), (58.27, 0.22), (82.4, 0.12), (87.31, 0.08), (116.54, 0.05)]:
        a = amp * (0.6 + 0.4 * lfo(int(rng.integers(1, 4))))
        out += a * np.sin(2 * np.pi * q(f0) * t + rng.uniform(0, 6.28))

    # metallic groan: FM pair, swelling twice per loop
    groan = np.sin(2 * np.pi * q(110.0) * t + 5.0 * np.sin(2 * np.pi * 3 * t / D) + 1.4 * np.sin(2 * np.pi * q(163.7) * t))
    out += groan * 0.09 * np.clip(lfo(2), 0, 1) ** 3

    wind = filt(noise(n), lo=60, hi=650, circular=True)
    wind = wind / np.max(np.abs(wind)) * (0.5 + 0.5 * lfo(3)) ** 2
    out += wind * 0.35

    hiss = filt(noise(n), lo=2500, hi=6500, circular=True)
    out += hiss / np.max(np.abs(hiss)) * 0.025 * (0.5 + 0.5 * lfo(5))

    whistle = np.sin(2 * np.pi * q(1760.0) * t + 3 * np.sin(2 * np.pi * 4 * t / D))
    out += whistle * 0.012 * np.clip(lfo(1), 0, 1) ** 4

    # distant events baked into the loop (wrapped so they never click)
    events = [
        (7.0, filt(creak(2.4, 12, 50), hi=1800) * 0.25),
        (19.5, filt(snd_stinger_bang(), hi=900) * 0.22),
        (33.0, filt(snd_stinger_scrape(), hi=2500) * 0.18),
        (46.0, filt(snd_stinger_knock(), hi=1500) * 0.15),
    ]
    for at, ev in events:
        place_wrapped(out, reverb(ev, decay=2.5, mix=0.6, damp=1500), samples(at))

    out = filt(out, lo=28, circular=True)
    return normalize(out, 0.8)


def snd_music_box():
    beat = 0.5
    # original lullaby in A minor (midi note, beats)
    phrase_a = [(76, 2), (74, 1), (72, 2), (71, 1), (69, 2), (72, 1), (71, 3),
                (76, 2), (74, 1), (72, 2), (71, 1), (68, 2), (71, 1), (69, 3)]
    phrase_b = [(72, 1), (76, 1), (81, 1), (80, 2), (76, 1), (77, 1), (76, 1), (74, 1), (76, 3),
                (72, 1), (69, 1), (72, 1), (71, 2), (68, 1), (69, 1), (64, 1), (68, 1), (69, 3)]
    bass = [57, 52, 57, 52, 57, 52, 56, 57, 57, 52, 50, 52, 57, 52, 52, 45]
    melody = phrase_a + phrase_b
    notes = []
    for rep in range(2):
        pos = 0.0
        for m, b in melody:
            notes.append((rep, pos, m, 1.0))
            pos += b
        for i, m in enumerate(bass):
            notes.append((rep, i * 3.0, m, 0.45))
    total_beats = 48.0
    # second pass winds down: tempo stretches like a dying spring
    def beat_to_time(rep, b):
        if rep == 0:
            return b * beat
        x = b / total_beats
        return total_beats * beat + beat * (b + 2.5 * x ** 2.5 * total_beats / 6.0)

    length = beat_to_time(1, total_beats) + 4.0
    n = samples(length)
    out = np.zeros(n)
    for rep, b, m, vel in notes:
        start = beat_to_time(rep, b)
        f = 440.0 * 2 ** ((m - 69) / 12.0)
        if rep == 1:
            f *= 2 ** (-0.6 * (b / total_beats) ** 2 / 12.0)  # sags flat as it winds down
        nn = samples(2.5)
        tt = secs(nn)
        tine = (np.sin(2 * np.pi * f * tt) * np.exp(-tt / 1.1)
                + 0.35 * np.sin(2 * np.pi * f * 3.01 * tt) * np.exp(-tt / 0.25)
                + 0.12 * np.sin(2 * np.pi * f * 6.2 * tt) * np.exp(-tt / 0.08))
        tine += filt(noise(nn), lo=3000) * np.exp(-tt / 0.004) * 0.15
        place(out, tine * vel * rng.uniform(0.85, 1.0), samples(start))
    # tape wow: read buffer at a wobbling rate
    t = secs(n)
    rate = 1.0 + 0.004 * np.sin(2 * np.pi * 0.55 * t) + 0.002 * smooth_noise(n, 3)
    read = np.clip(np.cumsum(rate) - rate[0], 0, n - 1)
    out = np.interp(read, np.arange(n), out)
    out = filt(out, lo=150, hi=7000)
    out = reverb(out, decay=3.0, mix=0.35, damp=5000)
    hiss = filt(noise(len(out)), lo=3000, hi=9000) * 0.01
    return normalize(fade(out + hiss, 0.01, 1.5), 0.7)



# ---- night 2-5 monsters, objectives, menu -----------------------------------

def snd_crawler_loop():
    dur = 4.0
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    pos = 0.0
    while pos < dur:
        cn = samples(0.01)
        c = np.sin(2 * np.pi * rng.uniform(1500, 4200) * secs(cn)) * env_exp(cn, 0.0018, attack=0.0001)
        place_wrapped(out, c * rng.uniform(0.3, 1.0), samples(pos))
        pos += rng.uniform(0.012, 0.05)
    hiss = filt(noise(n), lo=2500, hi=7000, circular=True)
    hiss = hiss / np.max(np.abs(hiss)) * (0.5 + 0.5 * np.sin(2 * np.pi * 2 * t / dur)) ** 2 * 0.3
    low = filt(noise(n), lo=80, hi=300, circular=True)
    out = normalize(out) + hiss + low / np.max(np.abs(low)) * 0.25
    return normalize(out, 0.75)


def snd_listener_loop():
    dur = 5.0
    n = samples(dur)
    t = secs(n)
    clicks = np.zeros(n)
    for _ in range(10):
        at = rng.uniform(0, dur)
        for j in range(int(rng.integers(3, 7))):
            cn = samples(0.02)
            c = filt(noise(cn), lo=900, hi=3000) * env_exp(cn, 0.004, attack=0.0002)
            place_wrapped(clicks, c, samples(at + j * 0.045))
    breath_env = np.clip(np.sin(2 * np.pi * t / dur), 0, 1) ** 1.2
    rasp = filt(noise(n), lo=200, hi=1600, peaks=((500, 3, 1), (1100, 4, 0.7)), circular=True) * breath_env
    am = 0.6 + 0.4 * np.sin(2 * np.pi * round(30 * dur) / dur * t)
    out = normalize(clicks) * 0.8 + normalize(rasp * am) * 0.6
    return normalize(out, 0.75)


def snd_amalgam_loop():
    dur = 6.0
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for base, amt in [(38, 1.0), (61, 0.7), (93, 0.5)]:
        wob = 5 * np.sin(2 * np.pi * int(rng.integers(1, 3)) * t / dur + rng.uniform(0, 6)) + 3 * smooth_noise(n, 5, circular=True)
        f0 = base + wob
        total = np.sum(f0) / SR
        f0 = f0 + (round(total) - total) / dur
        v = saw(osc_phase(f0))
        fry = (0.5 + 0.5 * np.sin(2 * np.pi * round(rng.uniform(18, 30) * dur) / dur * t)) ** 3
        v = filt(v * (0.3 + 0.7 * fry), lo=40, hi=1400, peaks=((300, 3, 1), (650, 4, 0.7)), circular=True)
        out += normalize(v) * amt
    return normalize(drive(normalize(out), 2.8), 0.85)


def snd_crawler_screech():
    s = scream_voice(1.8, 900, 2200, 700, harsh=1.0, seed_shift=0.4)
    out = reverb(s, decay=1.0, mix=0.2, damp=7000)
    return normalize(out, 0.95)


def snd_listener_shriek():
    a = scream_voice(2.4, 1400, 3200, 900, harsh=1.0, seed_shift=1.1)
    b = scream_voice(2.4, 1000, 2600, 700, harsh=0.7, seed_shift=2.2) * 0.6
    out = reverb(a + b, decay=2.0, mix=0.35, damp=7000)
    return normalize(drive(normalize(out), 1.5), 0.95)


def snd_amalgam_roar():
    dur = 3.6
    voices = [scream_voice(dur, p0, p1, p2, harsh=h, seed_shift=sh) for (p0, p1, p2, h, sh) in [
        (120, 260, 90, 0.6, 0.1), (200, 420, 150, 0.8, 1.3), (380, 820, 260, 1.0, 2.7)]]
    n = len(voices[0])
    t = secs(n)
    sub = np.sin(osc_phase(np.linspace(55, 32, n))) * np.exp(-t / 1.5)
    out = voices[0] + voices[1] * 0.8 + voices[2] * 0.6 + sub * 0.8
    out = reverb(out, decay=2.4, mix=0.3, damp=3000)
    return normalize(drive(normalize(out), 2.2), 0.97)


def snd_statue_grind():
    dur = 1.6
    n = samples(dur)
    t = secs(n)
    slip = 0.5 + 0.5 * np.sign(np.sin(osc_phase(18 + 10 * smooth_noise(n, 3))))
    out = filt(noise(n) * (0.4 + 0.6 * slip), lo=60, hi=1200, peaks=((140, 3, 1.0), (380, 4, 0.7), (900, 5, 0.4)))
    out *= np.minimum(1, t / 0.05) * np.minimum(1, (dur - t) / 0.4)
    out = reverb(out, decay=1.2, mix=0.3, damp=2000)
    return normalize(drive(normalize(out), 1.8), 0.9)


def snd_clock_chime():
    hit = metal_hit(196, [0.5, 1.0, 1.19, 1.5, 2.0, 2.51, 3.0], 4.5, 2.6, detune=0.003)
    return normalize(reverb(hit, decay=3.0, mix=0.4, damp=4000), 0.85)


def snd_generator_start():
    dur = 3.2
    n = samples(dur)
    t = secs(n)
    crank = np.zeros(n)
    for at in (0.0, 0.35, 0.7):
        place(crank, thud(0.3, 120, 60, 0.06, click=0.8) * 0.8, samples(at))
    rate = np.clip((t - 1.0) / 1.2, 0, 1)
    pulses = (np.sin(osc_phase(18 + 32 * rate)) > 0.6).astype(float)
    engine = filt(pulses + noise(n) * 0.1, lo=60, hi=900, peaks=((120, 3, 1), (240, 4, 0.6))) * np.clip((t - 1.0) / 0.3, 0, 1)
    out = (crank + normalize(engine) * 0.9) * np.minimum(1, (dur - t) / 0.2)
    return normalize(drive(normalize(out), 1.6), 0.9)


def snd_generator_loop():
    dur = 2.0
    n = samples(dur)
    t = secs(n)
    pulses = (np.sin(2 * np.pi * round(50 * dur) / dur * t) > 0.5).astype(float) - 0.3
    hum = sum(np.sin(2 * np.pi * round(h * 60 * dur) / dur * t) / h for h in range(1, 6))
    out = filt(pulses * 0.7 + hum * 0.3 + noise(n) * 0.05, lo=50, hi=1500, circular=True)
    return normalize(out, 0.6)


def snd_power_up():
    dur = 2.2
    n = samples(dur)
    t = secs(n)
    sweep = np.sin(osc_phase(60 + 600 * (t / dur) ** 2)) * np.minimum(1, t / 0.3)
    buzz = np.sign(np.sin(2 * np.pi * 120 * t)) * 0.2 * np.clip((t - 0.5) / 1.2, 0, 1)
    thunk = np.zeros(n)
    place(thunk, thud(0.5, 90, 40, 0.15, click=1.0), samples(1.7))
    out = (sweep * 0.6 + buzz) * np.clip((1.75 - t) * 8, 0, 1) + thunk
    return normalize(reverb(out, decay=1.5, mix=0.3), 0.85)


def snd_page_pickup():
    n = samples(0.9)
    t = secs(n)
    rustle = filt(noise(n), lo=1500, hi=9000) * (smooth_noise(n, 25) > 0).astype(float) * np.exp(-t / 0.3)
    whisper = snd_stinger_whisper()[: samples(1.6)] * 0.5
    out = np.zeros(samples(2.0))
    place(out, rustle, 0)
    place(out, whisper, samples(0.3))
    return normalize(out, 0.75)


def snd_heart_pulse_loop():
    n = samples(1.6)
    out = np.zeros(n)
    place(out, thud(0.5, 55, 30, 0.12, click=0.25), 0)
    place(out, thud(0.45, 48, 28, 0.1, click=0.15) * 0.7, samples(0.28))
    return normalize(filt(out, hi=300), 0.9)


def snd_heart_shatter():
    out = np.zeros(samples(3.0))
    for _ in range(40):
        cn = samples(rng.uniform(0.05, 0.3))
        g = np.sin(2 * np.pi * rng.uniform(2000, 7000) * secs(cn)) * env_exp(cn, rng.uniform(0.02, 0.1))
        place(out, g * rng.uniform(0.2, 0.6), samples(rng.uniform(0, 0.6)))
    place(out, thud(1.2, 70, 25, 0.4, click=1.0, crack=1.0) * 1.3, 0)
    bn = samples(0.4)
    place(out, filt(noise(bn), lo=500) * env_exp(bn, 0.08) * 0.8, 0)
    out = reverb(out, decay=2.5, mix=0.4, damp=6000)
    return normalize(drive(normalize(out), 1.5), 0.95)


def snd_alarm_beep():
    out = np.zeros(samples(1.4))
    for f, at in ((880, 0.0), (660, 0.35)):
        bn = samples(0.3)
        tt = secs(bn)
        b = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sign(np.sin(2 * np.pi * f * tt))) * np.minimum(1, tt / 0.01) * np.minimum(1, (0.3 - tt) / 0.03)
        place(out, b, samples(at))
    out = reverb(filt(out, lo=300, hi=4000), decay=1.8, mix=0.5, damp=3000)
    return normalize(out, 0.7)


def snd_drip():
    n = samples(0.05)
    blip = np.sin(osc_phase(np.linspace(900, 2400, n))) * env_exp(n, 0.012)
    return normalize(reverb(blip, decay=1.5, mix=0.55, damp=5000), 0.7)


def snd_night_intro():
    dur = 3.5
    n = samples(dur)
    t = secs(n)
    swell = filt(noise(n), lo=100, hi=3000) * (t / dur) ** 3 * 0.6
    drone = (np.sin(2 * np.pi * 55 * t) * 0.3 + np.sin(2 * np.pi * 58.3 * t) * 0.25) * (t / dur) ** 2
    out = (swell + drone) * np.clip((2.95 - t) * 20, 0, 1)
    boom = np.zeros(n)
    place(boom, thud(1.8, 60, 22, 0.6, click=1.0, crack=0.5) * 1.3, samples(2.9))
    out = reverb(out + boom, decay=3.0, mix=0.35, damp=3000)
    return normalize(out, 0.92)


def snd_menu_hover():
    n = samples(0.07)
    t = secs(n)
    out = np.sin(2 * np.pi * 1200 * t) * env_exp(n, 0.015) + filt(noise(n), lo=3000) * env_exp(n, 0.004) * 0.3
    return normalize(fade(out), 0.4)


def snd_menu_select():
    full = np.zeros(samples(1.3))
    place(full, thud(0.5, 110, 50, 0.08, click=0.6), 0)
    place(full, metal_hit(330, [1.0, 2.0, 3.01], 1.2, 0.5) * 0.3, samples(0.02))
    return normalize(reverb(full, decay=1.4, mix=0.3), 0.7)


def snd_blink():
    n = samples(0.4)
    t = secs(n)
    out = thud(0.4, 70, 40, 0.07, click=0.2) + filt(noise(n), lo=200, hi=1500) * np.exp(-t / 0.1) * 0.3
    return normalize(out, 0.8)


# ---- events, curses, throwables, hiding ------------------------------------

def snd_glass_shatter():
    dur = 1.6
    n = samples(dur)
    out = np.zeros(n)
    burst = filt(noise(n), lo=2500, hi=12000) * env_exp(n, 0.05, attack=0.0005)
    place(out, burst * 0.9, 0)
    for _ in range(26):
        f = rng.uniform(2200, 7500)
        h = metal_hit(f, [1.0, 1.47, 2.09, 2.83], rng.uniform(0.15, 0.5), rng.uniform(0.03, 0.12), detune=0.01)
        place(out, h * rng.uniform(0.15, 0.5), samples(rng.uniform(0.0, 0.9) ** 2))
    out = reverb(out, decay=1.1, mix=0.25, damp=9000)
    return normalize(out, 0.9)


def snd_bottle_whoosh():
    dur = 0.55
    n = samples(dur)
    t = secs(n)
    x = filt(noise(n), lo=400, hi=4000)
    sweep = svf(x, np.linspace(600, 2600, n), q=3.0)
    env = np.sin(np.linspace(0, np.pi, n)) ** 2
    return normalize(sweep * env, 0.6)


def snd_phone_ring_loop():
    # an old bell phone: a burst of rapid strikes, then a pause (loops)
    dur = 3.2
    n = samples(dur)
    out = np.zeros(n)
    pos = 0.0
    while pos < 1.3:
        h = metal_hit(1180, [1.0, 1.71, 2.42, 3.38], 0.12, 0.05, detune=0.003)
        h2 = metal_hit(1395, [1.0, 1.66, 2.51], 0.12, 0.05, detune=0.003)
        place(out, h * 0.8, samples(pos))
        place(out, h2 * 0.7, samples(pos + 0.02))
        pos += 1.0 / 22.0
    out = filt(out, lo=500, hi=7000)
    out = reverb(out, decay=0.8, mix=0.25, damp=6000, tail=False)
    return normalize(out, 0.8)


def snd_phone_pickup():
    out = np.zeros(samples(0.5))
    place(out, thud(0.25, 400, 180, 0.03, click=1.0), 0)
    place(out, metal_hit(900, [1.0, 2.3], 0.2, 0.04) * 0.3, samples(0.05))
    place(out, filt(noise(samples(0.2)), lo=800, hi=3000) * env_exp(samples(0.2), 0.05) * 0.3, samples(0.12))
    return normalize(out, 0.7)


def formant_voice(dur, pitch, vowels, rate=6.0, rough=0.3):
    n = samples(dur)
    t = secs(n)
    f0 = pitch * (1 + 0.06 * smooth_noise(n, 3) + 0.02 * np.sin(2 * np.pi * 5.5 * t))
    src = saw(osc_phase(f0)) * (1 - rough) + noise(n) * rough
    seg = max(1, int(dur * rate))
    f1 = np.interp(t, np.linspace(0, dur, seg), [vowels[i % len(vowels)][0] for i in range(seg)])
    f2 = np.interp(t, np.linspace(0, dur, seg), [vowels[i % len(vowels)][1] for i in range(seg)])
    out = svf(src, f1, q=5) + svf(src, f2, q=7) * 0.7
    amp = np.clip((smooth_noise(n, rate * 1.4) + 0.6), 0, 1.4)
    return out * amp


def snd_phone_voice():
    vowels = [(700, 1150), (350, 2000), (450, 900), (600, 1700), (300, 2300), (500, 1000)]
    v = formant_voice(3.4, 92, [vowels[i] for i in rng.integers(0, len(vowels), 24)], rate=7, rough=0.35)
    n = len(v)
    t = secs(n)
    v = filt(v, lo=320, hi=3200)
    v = drive(normalize(v), 3.0)
    crackle = (rng.random(n) < 0.003).astype(float) * rng.uniform(-1, 1, n) * 0.8
    hiss = filt(noise(n), lo=1500, hi=4000) * 0.06
    out = v * 0.8 + crackle + hiss
    out *= np.minimum(1, t / 0.05) * np.minimum(1, (len(t) / SR - t) / 0.3)
    return normalize(out, 0.75)


def snd_power_down():
    dur = 2.6
    n = samples(dur)
    t = secs(n)
    f = 120 * np.exp(-t / 0.9) + 25
    hum = np.zeros(n)
    for h in range(1, 7):
        hum += np.sin(osc_phase(f * h)) / h
    hum *= np.exp(-t / 1.1)
    out = np.zeros(n)
    place(out, thud(0.5, 90, 40, 0.1, click=1.0, crack=0.5), 0)
    out += hum * 0.8
    out = reverb(out, decay=1.8, mix=0.35, damp=3000, tail=False)
    return normalize(out, 0.85)


def snd_wall_shift():
    dur = 3.4
    n = samples(dur)
    t = secs(n)
    rumble = filt(noise(n), hi=160, order=4) * 3
    grind = filt(noise(n) * (0.5 + 0.5 * (smooth_noise(n, 9) > 0)), peaks=((210, 8, 1.0), (470, 10, 0.7), (980, 12, 0.4)))
    env = np.minimum(1, t / 0.4) * np.minimum(1, (dur - 0.4 - t) / 0.3).clip(0, 1)
    out = (rumble + grind * 0.8) * env
    place(out, thud(0.6, 70, 32, 0.16, click=1.0, crack=0.6) * 1.2, samples(dur - 0.5))
    out = reverb(out, decay=2.0, mix=0.3, damp=2500, tail=False)
    return normalize(drive(normalize(out), 1.4), 0.9)


def snd_doors_slam():
    out = np.zeros(samples(3.0))
    pos = 0.0
    for i in range(6):
        place(out, snd_door_slam() * rng.uniform(0.5, 1.0) * (1 if i == 0 else 0.8), samples(pos))
        pos += rng.uniform(0.08, 0.35)
    return normalize(out, 0.95)


def snd_gasp():
    dur = 0.9
    n = samples(dur)
    t = secs(n)
    ins = svf(noise(n), np.linspace(1700, 2600, n), q=1.8) * np.exp(-((t - 0.18) / 0.12) ** 2)
    voice = formant_voice(0.5, 210, [(800, 1300), (600, 1100)], rate=3, rough=0.6)
    out = ins * 1.2
    place(out, voice * np.linspace(1, 0, len(voice)) * 0.5, samples(0.08))
    out = filt(out, lo=200, hi=6000)
    return normalize(out, 0.8)


def snd_breath_hold():
    dur = 0.8
    n = samples(dur)
    t = secs(n)
    ins = svf(noise(n), np.linspace(1300, 2400, n), q=1.6) * np.sin(np.linspace(0, np.pi, n)) ** 1.2
    return normalize(filt(ins, lo=300, hi=5000) * np.minimum(1, (dur - t) / 0.05), 0.55)


def snd_curse_sting():
    dur = 4.5
    n = samples(dur)
    t = secs(n)
    boom = thud(2.5, 60, 24, 0.7, click=0.6, crack=0.4)
    cluster = np.zeros(n)
    for f in (110.0, 116.5, 155.6, 164.8, 233.1):
        cluster += saw(osc_phase(np.full(n, f) * (1 + 0.003 * np.sin(2 * np.pi * 0.7 * t))))
    cluster = filt(cluster, hi=1800) * np.minimum(1, t / 0.05) * np.exp(-t / 1.8)
    swell_n = samples(1.2)
    swell = filt(noise(swell_n), lo=3000, hi=10000) * np.linspace(0, 1, swell_n) ** 3
    out = np.zeros(n)
    place(out, swell * 0.4, 0)
    place(out, boom * 1.2, samples(1.2))
    place(out, cluster * 0.35, samples(1.2))
    out = reverb(out, decay=3.0, mix=0.45, damp=4000, tail=False)
    return normalize(out, 0.9)


def snd_event_sting():
    dur = 2.6
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    place(out, thud(1.2, 70, 30, 0.35, click=0.8, crack=0.5), 0)
    screech = np.zeros(n)
    for f in (1840, 2071, 2603):
        screech += np.sin(osc_phase(f * (1 - 0.15 * t / dur) * (1 + 0.02 * np.sin(2 * np.pi * 9 * t))))
    out += screech * np.exp(-t / 0.8) * 0.18
    out = reverb(out, decay=2.4, mix=0.45, damp=5000, tail=False)
    return normalize(out, 0.85)


def snd_floor_creak():
    out = creak(1.4, 25, 110, res=((190, 14), (430, 18), (900, 20), (1700, 16)))
    return normalize(reverb(out, decay=1.4, mix=0.35, damp=2500), 0.75)


def snd_clock_tick():
    out = np.zeros(samples(2.0))
    for i in range(4):
        cn = samples(0.05)
        tick = metal_hit(2600 if i % 2 == 0 else 2100, [1.0, 2.7], 0.05, 0.008) + filt(noise(cn), lo=2000) * env_exp(cn, 0.004) * 0.5
        place(out, tick, samples(i * 0.5))
    return normalize(reverb(out, decay=1.2, mix=0.3, damp=6000), 0.6)


def snd_gurney():
    dur = 2.6
    n = samples(dur)
    out = np.zeros(n)
    pos = 0.0
    while pos < dur - 0.3:
        sq_n = samples(0.14)
        tt = secs(sq_n)
        sq = np.sin(osc_phase(np.linspace(1500, 2100, sq_n) * (1 + 0.04 * np.sin(2 * np.pi * 40 * tt)))) * np.sin(np.linspace(0, np.pi, sq_n))
        place(out, sq * 0.5, samples(pos))
        pos += 0.32
    out += filt(noise(n), lo=200, hi=1200) * 0.05
    for _ in range(10):
        place(out, metal_hit(rng.uniform(600, 1500), [1.0, 2.6], 0.1, 0.02) * 0.2, samples(rng.uniform(0, dur - 0.2)))
    return normalize(reverb(out, decay=1.6, mix=0.4, damp=5000), 0.7)


def snd_monitor_flatline():
    dur = 3.0
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for at in (0.0, 0.75):
        bn = samples(0.12)
        place(out, np.sin(2 * np.pi * 980 * secs(bn)) * np.sin(np.linspace(0, np.pi, bn)) ** 0.2, samples(at))
    tone = np.sin(2 * np.pi * 980 * t) * (t > 1.5) * np.minimum(1, (dur - t) / 0.2)
    out += tone * 0.8
    return normalize(reverb(out, decay=1.0, mix=0.3, damp=6000), 0.55)


def snd_intercom():
    dur = 3.4
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for at, f in ((0.0, 784.0), (0.45, 622.3)):
        cn = samples(1.2)
        ct = secs(cn)
        chime = (np.sin(2 * np.pi * f * ct) + 0.3 * np.sin(2 * np.pi * f * 2.01 * ct)) * np.exp(-ct / 0.5)
        place(out, chime * 0.6, samples(at))
    voice = formant_voice(1.6, 120, [(650, 1100), (400, 1900), (500, 1000)], rate=6, rough=0.3)
    voice = drive(normalize(filt(voice, lo=400, hi=3000)), 2.5) * 0.5
    place(out, voice, samples(1.5))
    out += filt(noise(n), lo=1000, hi=4000) * 0.04
    return normalize(reverb(out, decay=2.6, mix=0.55, damp=3500), 0.65)


def snd_pipe_groan():
    dur = 3.2
    n = samples(dur)
    t = secs(n)
    f = 58 + 9 * smooth_noise(n, 1.5)
    body = np.sin(osc_phase(f) + 3.0 * np.sin(osc_phase(f * 2.71)))
    body = filt(body, lo=40, hi=900, peaks=((180, 6, 1.0), (390, 8, 0.7)))
    env = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    out = reverb(body * env, decay=2.8, mix=0.5, damp=1800)
    return normalize(out, 0.75)


def snd_splash():
    dur = 1.2
    n = samples(dur)
    out = filt(noise(n), lo=300, hi=3500) * env_exp(n, 0.12)
    for _ in range(8):
        bn = samples(0.08)
        bt = secs(bn)
        bub = np.sin(osc_phase(np.linspace(rng.uniform(500, 900), rng.uniform(1200, 2000), bn))) * np.sin(np.linspace(0, np.pi, bn))
        place(out, bub * 0.3, samples(rng.uniform(0.05, 0.8)))
    return normalize(reverb(out, decay=1.6, mix=0.45, damp=4000), 0.75)


def snd_marble_steps():
    out = np.zeros(samples(2.6))
    pos = 0.0
    for i in range(6):
        cn = samples(0.15)
        step = filt(noise(cn), lo=900, hi=5000) * env_exp(cn, 0.012) + thud(0.15, 220, 150, 0.02, click=0.6) * 0.4
        place(out, step * (0.5 + 0.1 * i), samples(pos))
        pos += 0.42
    out = reverb(out, decay=3.8, mix=0.65, damp=4000, predelay=0.05)
    return normalize(out, 0.7)


def choir(chord, dur, vowel=(700, 1150, 2600), vib=5.0):
    n = samples(dur)
    t = secs(n)
    out = np.zeros(n)
    for m in chord:
        f = 440.0 * 2 ** ((m - 69) / 12.0)
        for det in (-0.004, 0.0, 0.005):
            out += saw(osc_phase(f * (1 + det) * (1 + 0.006 * np.sin(2 * np.pi * vib * t + rng.uniform(0, 6.28)))))
    out = filt(out, lo=120, peaks=((vowel[0], 5, 1.0), (vowel[1], 6, 0.6), (vowel[2], 7, 0.3), (5000, 1, 0.05)))
    return out


def snd_choir_hum():
    dur = 5.0
    out = choir([57, 60, 64, 65], dur, vowel=(400, 900, 2300), vib=4.5)
    n = len(out)
    out *= np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return normalize(reverb(out, decay=3.5, mix=0.55, damp=5000), 0.6)


def snd_reverse_whisper():
    w = snd_stinger_whisper()[::-1].copy()
    return normalize(reverb(w, decay=2.0, mix=0.5, damp=5000), 0.65)


def snd_deep_boom():
    out = thud(3.0, 55, 22, 0.9, click=0.4, crack=0.3)
    out = reverb(out, decay=4.0, mix=0.5, damp=900)
    return normalize(out, 0.9)


def snd_locker_bang():
    out = np.zeros(samples(1.8))
    for i in range(3):
        place(out, metal_hit(240, [1.0, 2.76, 5.4, 8.93], 0.5, 0.12) * 0.9, samples(i * 0.38))
        place(out, thud(0.3, 110, 60, 0.05, click=1.0) * 0.6, samples(i * 0.38))
    return normalize(reverb(out, decay=1.2, mix=0.3, damp=4000), 0.9)


def snd_rage_sting():
    dur = 3.5
    a = scream_voice(dur * 0.8, 260, 640, 180, harsh=1.0, seed_shift=0.4)
    out = np.zeros(samples(dur))
    place(out, thud(1.5, 60, 26, 0.5, click=1.0, crack=1.0), 0)
    place(out, a * 0.8, samples(0.15))
    out = reverb(out, decay=2.5, mix=0.4, damp=4000, tail=False)
    return normalize(drive(normalize(out), 2.0), 0.95)


# ---- per-night ambience and chase music (the ambience atlas) ----------------

def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def tone(kind, m, dur, decay=None, cutoff=2400.0, detune=0.004):
    n = samples(dur)
    t = secs(n)
    f = mtof(m)
    if kind == "saw":
        x = saw(osc_phase(np.full(n, f))) + saw(osc_phase(np.full(n, f * (1 + detune))))
    elif kind == "square":
        x = np.sign(np.sin(2 * np.pi * f * t)) * 0.6
    elif kind == "piano":
        x = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.003 * t) * np.exp(-t / 0.4)
             + 0.25 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t / 0.2))
    else:
        x = np.sin(2 * np.pi * f * t)
    env = np.minimum(1, t / 0.004)
    if decay:
        env = env * np.exp(-t / decay)
    env = env * np.minimum(1, (dur - t) / 0.01).clip(0, 1)
    out = x * env
    if kind in ("saw", "square"):
        out = filt(out, hi=cutoff)
    return out


def kick(pitch=1.0):
    return thud(0.4, 130 * pitch, 42 * pitch, 0.1, click=0.6)


def snare(tone_hz=190):
    n = samples(0.28)
    out = filt(noise(n), lo=900, hi=7000) * env_exp(n, 0.07)
    place(out, thud(0.2, tone_hz * 1.3, tone_hz, 0.04, click=0.2) * 0.5, 0)
    return out


def hat(length=0.05):
    n = samples(length)
    return filt(noise(n), lo=6500) * env_exp(n, length * 0.3)


def sequence(bpm, bars, events):
    """events: list of (beat, sound array, gain). Returns a seamless loop."""
    beat = 60.0 / bpm
    L = samples(bars * 4 * beat)
    out = np.zeros(L)
    for b, x, g in events:
        place_wrapped(out, x * g, int(samples(b * beat)) % L)
    return out


def chase_house():
    bpm, bars = 120, 8
    ev = []
    for b in range(bars * 4):
        ev.append((b, kick(0.9), 0.9 if b % 2 == 0 else 0.5))
        ev.append((b + 0.5, hat(0.03), 0.25))
        ev.append((b, tone("piano", 33 if (b // 4) % 2 == 0 else 34, 0.5, decay=0.3), 0.6))
        ev.append((b + 0.5, tone("piano", 45, 0.4, decay=0.2), 0.35))
    for bar in range(bars):
        ev.append((bar * 4, tone("saw", 57, 4 * 0.5 + 0.2, cutoff=900), 0.18))
        ev.append((bar * 4, tone("saw", 58, 4 * 0.5 + 0.2, cutoff=900), 0.16))
    motif = [76, 74, 72, 71, 69, 68]
    for i, m in enumerate(motif):
        ev.append((16 + i * 0.75, tone("piano", m, 1.0, decay=0.6) * 0.5, 0.35))
    out = sequence(bpm, bars, ev)
    return normalize(reverb(out, decay=1.2, mix=0.2, damp=6000, tail=False), 0.85)


def chase_ward():
    bpm, bars = 140, 8
    ev = []
    for b in range(bars * 4):
        ev.append((b, kick(), 1.0))
        if b % 2 == 1:
            ev.append((b, snare(), 0.7))
        for q in (0, 0.25, 0.5, 0.75):
            ev.append((b + q, tone("saw", 29, 0.12, decay=0.08, cutoff=700), 0.45))
        ev.append((b + 0.5, hat(), 0.3))
    for bar in range(bars):
        for i in range(4):
            m = 77 if i % 2 == 0 else 71
            ev.append((bar * 4 + i, tone("square", m, 0.35, decay=0.25, cutoff=3500), 0.18))
        if bar % 2 == 1:
            ev.append((bar * 4 + 3.5, metal_hit(1300, [1.0, 2.4, 3.9], 0.8, 0.3), 0.25))
    out = sequence(bpm, bars, ev)
    return normalize(drive(normalize(out), 1.6), 0.85)


def chase_sewer():
    bpm, bars = 96, 6
    ev = []
    for b in range(bars * 4):
        ev.append((b, thud(0.6, 95, 38, 0.18, click=0.8), 0.9 if b % 2 == 0 else 0.6))
        ev.append((b + 0.75, thud(0.4, 140, 70, 0.08, click=0.4), 0.35))
    for bar in range(bars):
        ev.append((bar * 4, tone("saw", 26 if bar % 3 != 2 else 27, 4 * 60 / bpm, cutoff=500, detune=0.008), 0.5))
        ev.append((bar * 4 + 2, tone("saw", 38, 1.2, decay=0.8, cutoff=900), 0.25))
        for _ in range(2):
            ev.append((bar * 4 + rng.uniform(0, 4), tone("sine", int(rng.integers(84, 96)), 0.25, decay=0.06), 0.15))
    out = sequence(bpm, bars, ev)
    return normalize(reverb(out, decay=2.0, mix=0.3, damp=3000, tail=False), 0.85)


def chase_atrium():
    bpm, bars = 108, 7
    beat = 60.0 / bpm
    ev = []
    for b in range(bars * 4):
        ev.append((b, thud(0.8, 90, 50, 0.25, click=0.5), 0.8 if b % 4 == 0 else 0.45))
    chords = [[48, 51, 55, 60], [49, 52, 56, 61], [48, 51, 55, 59], [47, 50, 55, 58]]
    for bar in range(bars):
        c = chords[bar % len(chords)]
        ev.append((bar * 4, choir(c, beat * 3.5, vowel=(700, 1150, 2600)) * 0.25, 1.0))
        trem_n = samples(beat * 4)
        tt = secs(trem_n)
        strings = tone("saw", c[-1] + 12, beat * 4, cutoff=3000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (bpm / 60 * 4) * tt)))
        ev.append((bar * 4, strings, 0.12))
    out = sequence(bpm, bars, ev)
    return normalize(reverb(out, decay=2.6, mix=0.35, damp=5000, tail=False), 0.85)


def chase_void():
    bpm, bars = 150, 10
    ev = []
    for b in range(bars * 4):
        ev.append((b, kick(0.8), 1.0))
        if b % 2 == 1:
            n = samples(0.3)
            ev.append((b, drive(filt(noise(n), lo=400, hi=5000) * env_exp(n, 0.09), 4), 0.6))
        for q in (0, 0.25, 0.5, 0.75):
            m = 27 if (b * 4 + int(q * 4)) % 8 != 6 else 39
            ev.append((b + q, drive(tone("saw", m, 0.13, decay=0.09, cutoff=900), 3), 0.35))
    for bar in range(0, bars, 2):
        sw_n = samples(60 / bpm * 4)
        ev.append((bar * 4 + 4, filt(noise(sw_n), lo=1500, hi=9000) * np.linspace(0, 1, sw_n) ** 3, 0.25))
    out = sequence(bpm, bars, ev)
    return normalize(drive(normalize(out), 1.5), 0.85)


def ambience_loop(dur, layers, events):
    n = samples(dur)
    out = np.zeros(n)
    for x in layers:
        out += x
    for at, ev in events:
        place_wrapped(out, ev, samples(at))
    return normalize(filt(out, lo=25, circular=True), 0.8)


def amb_lfo(n, dur, cycles):
    t = secs(n)
    return np.sin(2 * np.pi * cycles * t / dur + rng.uniform(0, 6.28))


def amb_house():
    D = 40.0
    n = samples(D)
    room = filt(noise(n), hi=180, order=3, circular=True)
    room = room / np.max(np.abs(room)) * 0.25
    wind = filt(noise(n), lo=200, hi=900, circular=True)
    wind = wind / np.max(np.abs(wind)) * (0.5 + 0.5 * amb_lfo(n, D, 3)) ** 2 * 0.3
    ticks = np.zeros(n)
    for i in range(int(D)):
        place_wrapped(ticks, metal_hit(2400, [1.0, 2.7], 0.05, 0.008) * 0.05, samples(i + 0.0))
    events = [(5, reverb(creak(2.2, 15, 60), decay=2, mix=0.5, damp=1800) * 0.25),
              (17, filt(snd_stinger_bang(), hi=700) * 0.18),
              (26, snd_floor_creak() * 0.3),
              (34, filt(snd_stinger_footsteps(), hi=900) * 0.12)]
    return ambience_loop(D, [room, wind, ticks], events)


def amb_ward():
    D = 40.0
    n = samples(D)
    t = secs(n)
    hum = np.zeros(n)
    for h in range(1, 9):
        hum += np.sin(2 * np.pi * 60 * h * t) / h ** 1.3
    hum *= 0.08 * (0.8 + 0.2 * amb_lfo(n, D, 7))
    vent = filt(noise(n), lo=150, hi=1800, circular=True)
    vent = vent / np.max(np.abs(vent)) * 0.18
    events = []
    for k in range(6):
        beep = tone("square", 81, 0.25, decay=0.2, cutoff=3000) * 0.08
        events.append((k * 6.5 + 1, reverb(beep, decay=2.0, mix=0.6, damp=2500)))
    events.append((12, snd_monitor_flatline() * 0.12))
    events.append((24, snd_gurney() * 0.18))
    events.append((33, snd_intercom() * 0.2))
    return ambience_loop(D, [hum, vent], events)


def amb_sewer():
    D = 40.0
    n = samples(D)
    flow = filt(noise(n), lo=250, hi=1300, circular=True)
    flow = flow / np.max(np.abs(flow)) * (0.6 + 0.4 * smooth_noise(n, 2, circular=True)) * 0.3
    rumble = filt(noise(n), hi=90, order=4, circular=True)
    rumble = rumble / np.max(np.abs(rumble)) * 0.35
    events = []
    for _ in range(26):
        plink_n = samples(0.15)
        f = rng.uniform(900, 2200)
        plink = np.sin(osc_phase(np.linspace(f, f * 1.6, plink_n))) * env_exp(plink_n, 0.03)
        events.append((rng.uniform(0, D), reverb(plink, decay=1.8, mix=0.6, damp=4000) * rng.uniform(0.05, 0.15)))
    events.append((9, snd_pipe_groan() * 0.25))
    events.append((28, snd_pipe_groan() * 0.2))
    events.append((20, snd_splash() * 0.12))
    return ambience_loop(D, [flow, rumble], events)


def amb_atrium():
    D = 40.0
    n = samples(D)
    air = filt(noise(n), lo=80, hi=500, circular=True)
    air = air / np.max(np.abs(air)) * (0.5 + 0.5 * amb_lfo(n, D, 2)) * 0.22
    whistle = np.sin(2 * np.pi * round(880 * D) / D * secs(n)) * np.clip(amb_lfo(n, D, 1), 0, 1) ** 4 * 0.02
    events = [(4, snd_marble_steps() * 0.2), (19, snd_choir_hum() * 0.22), (31, snd_marble_steps() * 0.15),
              (26, filt(snd_statue_grind(), hi=1500) * 0.1)]
    return ambience_loop(D, [air, whistle], events)


def amb_void():
    D = 40.0
    n = samples(D)
    t = secs(n)
    drone = np.zeros(n)
    for f0, a in ((30.0, 0.5), (30.6, 0.4), (45.0, 0.2), (60.25, 0.08)):
        drone += a * np.sin(2 * np.pi * round(f0 * D) / D * t + rng.uniform(0, 6))
    drone *= 0.7
    events = []
    k = 0.0
    while k < D:
        events.append((k, filt(snd_heartbeat(), hi=160) * 0.25))
        k += 2.6
    events += [(6, snd_reverse_whisper() * 0.18), (21, snd_reverse_whisper() * 0.14), (14, snd_deep_boom() * 0.25),
               (30, reverb(scream_voice(1.6, 300, 500, 200, harsh=0.3), decay=3, mix=0.85, damp=900) * 0.08)]
    return ambience_loop(D, [drone], events)


AMBIENCE = [
    ("Ambience_house", amb_house, True),
    ("Ambience_ward", amb_ward, True),
    ("Ambience_sewer", amb_sewer, True),
    ("Ambience_atrium", amb_atrium, True),
    ("Ambience_void", amb_void, True),
    ("Chase_house", chase_house, True),
    ("Chase_ward", chase_ward, True),
    ("Chase_sewer", chase_sewer, True),
    ("Chase_atrium", chase_atrium, True),
    ("Chase_void", chase_void, True),
]


# ----------------------------------------------------------------------------
# Atlas + output
# ----------------------------------------------------------------------------

# name -> (generator, looped)
SFX = [
    ("Heartbeat", snd_heartbeat, False),
    ("BreathLoop", snd_breath_loop, True),
    ("MonsterGrowlLoop", snd_monster_growl_loop, True),
    ("MonsterScream", snd_monster_scream, False),
    ("Jumpscare", snd_jumpscare, False),
    ("MonsterStep", snd_monster_step, False),
    ("MonsterClicks", snd_monster_clicks, False),
    ("StingerCreak", snd_stinger_creak, False),
    ("StingerBang", snd_stinger_bang, False),
    ("StingerWhisper", snd_stinger_whisper, False),
    ("StingerScrape", snd_stinger_scrape, False),
    ("StingerDistantScream", snd_stinger_distant_scream, False),
    ("StingerKnock", snd_stinger_knock, False),
    ("StingerFootsteps", snd_stinger_footsteps, False),
    ("KeyPickup", snd_key_pickup, False),
    ("KeypadBeep", snd_keypad_beep, False),
    ("KeypadError", snd_keypad_error, False),
    ("Unlock", snd_unlock, False),
    ("DoorOpen", snd_door_open, False),
    ("DoorSlam", snd_door_slam, False),
    ("Locker", snd_locker, False),
    ("FlashlightClick", snd_flashlight_click, False),
    ("Battery", snd_battery, False),
    ("StaticBurst", snd_static_burst, False),
    ("LightBuzzLoop", snd_light_buzz_loop, True),
    ("Escape", snd_escape, False),
    ("CrawlerLoop", snd_crawler_loop, True),
    ("ListenerLoop", snd_listener_loop, True),
    ("AmalgamLoop", snd_amalgam_loop, True),
    ("CrawlerScreech", snd_crawler_screech, False),
    ("ListenerShriek", snd_listener_shriek, False),
    ("AmalgamRoar", snd_amalgam_roar, False),
    ("StatueGrind", snd_statue_grind, False),
    ("ClockChime", snd_clock_chime, False),
    ("GeneratorStart", snd_generator_start, False),
    ("GeneratorLoop", snd_generator_loop, True),
    ("PowerUp", snd_power_up, False),
    ("PagePickup", snd_page_pickup, False),
    ("HeartPulseLoop", snd_heart_pulse_loop, True),
    ("HeartShatter", snd_heart_shatter, False),
    ("AlarmBeep", snd_alarm_beep, False),
    ("Drip", snd_drip, False),
    ("NightIntro", snd_night_intro, False),
    ("MenuHover", snd_menu_hover, False),
    ("MenuSelect", snd_menu_select, False),
    ("Blink", snd_blink, False),
    ("GlassShatter", snd_glass_shatter, False),
    ("BottleWhoosh", snd_bottle_whoosh, False),
    ("PhoneRingLoop", snd_phone_ring_loop, True),
    ("PhonePickup", snd_phone_pickup, False),
    ("PhoneVoice", snd_phone_voice, False),
    ("PowerDown", snd_power_down, False),
    ("WallShift", snd_wall_shift, False),
    ("DoorsSlam", snd_doors_slam, False),
    ("Gasp", snd_gasp, False),
    ("BreathHold", snd_breath_hold, False),
    ("CurseSting", snd_curse_sting, False),
    ("EventSting", snd_event_sting, False),
    ("FloorCreak", snd_floor_creak, False),
    ("ClockTick", snd_clock_tick, False),
    ("Gurney", snd_gurney, False),
    ("MonitorFlatline", snd_monitor_flatline, False),
    ("Intercom", snd_intercom, False),
    ("PipeGroan", snd_pipe_groan, False),
    ("Splash", snd_splash, False),
    ("MarbleSteps", snd_marble_steps, False),
    ("ChoirHum", snd_choir_hum, False),
    ("ReverseWhisper", snd_reverse_whisper, False),
    ("DeepBoom", snd_deep_boom, False),
    ("LockerBang", snd_locker_bang, False),
    ("RageSting", snd_rage_sting, False),
]

GAP = 0.35  # silence between atlas entries so slices never bleed


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode_ogg(x, out_path):
    tmp = out_path + ".tmp.wav"
    write_wav(tmp, x)
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", tmp,
         "-c:a", "libvorbis", "-q:a", "6", out_path],
        check=True,
    )
    os.remove(tmp)


def build_atlas(entries, out_name):
    regions = []
    chunks = [np.zeros(samples(GAP))]
    cursor = GAP
    for name, gen, looped in entries:
        x = gen()
        if not looped:
            x = fade(x, 0.0005, 0.03)
        dur = len(x) / SR
        regions.append((name, cursor, dur, looped))
        chunks.append(x)
        chunks.append(np.zeros(samples(GAP)))
        cursor += dur + GAP
        print(f"  {name:22s} {dur:6.2f}s  @ {regions[-1][1]:7.3f}s")
    atlas = np.concatenate(chunks)
    encode_ogg(atlas, os.path.join(AUDIO_DIR, out_name))
    print(f"{out_name}: {len(atlas) / SR:.1f}s")
    return regions


def main():
    os.makedirs(AUDIO_DIR, exist_ok=True)
    only = sys.argv[1:]
    sfx = build_atlas(SFX, "ACHROMA_SFX.ogg")
    amb = build_atlas(AMBIENCE, "ACHROMA_AMBIENCE.ogg")
    if "--no-musicbox" not in only:
        encode_ogg(snd_music_box(), os.path.join(AUDIO_DIR, "ACHROMA_MUSICBOX.ogg"))
        print("music box done")

    lines = [
        "--!strict",
        "-- AUTO-GENERATED by tools/generate_audio.py. Do not edit by hand.",
        "-- Where every sound lives inside the uploaded files (seconds):",
        "--   file SFX       assets/audio/ACHROMA_SFX.ogg       every sound effect",
        "--   file Ambience  assets/audio/ACHROMA_AMBIENCE.ogg  each night's background and chase music",
        "",
        "export type Region = { start: number, duration: number, looped: boolean, file: string }",
        "",
        "local SoundAtlas: { [string]: Region } = {",
    ]
    for file, regions in (("SFX", sfx), ("Ambience", amb)):
        for name, start, dur, looped in regions:
            lines.append(f"\t{name} = {{ start = {start:.4f}, duration = {dur:.4f}, looped = {'true' if looped else 'false'}, file = \"{file}\" }},")
    lines += ["}", "", "return SoundAtlas", ""]
    with open(ATLAS_LUAU, "w") as f:
        f.write("\n".join(lines))
    print(f"wrote {os.path.relpath(ATLAS_LUAU, ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
