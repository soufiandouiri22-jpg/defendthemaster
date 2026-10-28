#!/usr/bin/env python3
"""Synthesises the game's own interface sounds (the coin, the kill stings) and joins them into one file.

    python3 Tools/ui_sounds.py            # writes Art/Sounds/ui_sounds.wav and each sound alone in Art/Sounds/Preview/
    python3 Tools/ui_sounds.py --upload   # also uploads the joined file and writes src/shared/UiSounds.luau

Every sound is made here from sine waves and noise, so nothing is borrowed. They share one uploaded file because an
account that is not ID-verified may upload only 10 audio files a month; the game plays each from its region.
"""

import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Art" / "Sounds"
MODULE = ROOT / "src" / "shared" / "UiSounds.luau"
RATE = 48000
# Silence between the sounds in the joined file, so a region never catches the next one.
GAP = 0.4
rng = np.random.default_rng(7)


def time(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def decay(t, tau, attack=0.002):
    return np.exp(-t / tau) * np.clip(t / attack, 0, 1)


def noise(t):
    return rng.standard_normal(len(t))


def band(x, low, high):
    sos = signal.butter(4, [low, high], btype="bandpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, cutoff):
    return signal.sosfilt(signal.butter(4, cutoff, fs=RATE, output="sos"), x)


def highpass(x, cutoff):
    return signal.sosfilt(signal.butter(4, cutoff, btype="highpass", fs=RATE, output="sos"), x)


def sweep(t, start, end, tau):
    """A sine falling from `start` Hz to `end` Hz, `tau` seconds per step of e."""
    freq = end + (start - end) * np.exp(-t / tau)
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def tone(t, freq, harmonics=10, bright=1.0):
    """A brassy tone built from its harmonics (no aliasing), `bright` lowering the upper ones less."""
    out = np.zeros_like(t)
    for n in range(1, harmonics + 1):
        if freq * n < RATE / 2.2:
            out += np.sin(2 * np.pi * freq * n * t + n) / n ** (1.6 - 0.6 * bright)
    return out


def bell(t, partials):
    return sum(a * np.sin(2 * np.pi * f * t) * decay(t, tau, 0.001) for f, a, tau in partials)


def reverb(x, seconds=0.9, wet=0.2):
    t = time(seconds)
    tail = lowpass(noise(t), 5000) * np.exp(-t / (seconds / 5))
    tail /= np.sqrt(np.sum(tail**2))
    out = np.concatenate([x, np.zeros(len(t))])
    wet_part = signal.fftconvolve(x, tail)[: len(out)]
    out[: len(wet_part)] += wet * wet_part
    return out


def boom(t, start=110, end=42, tau=0.15):
    return sweep(t, start, end, 0.04) * decay(t, tau, 0.003)


def finish(x, peak=0.9, drive=0.0):
    if drive:
        x = np.tanh(x * drive) / np.tanh(drive)
    loud = np.nonzero(np.abs(x) > np.max(np.abs(x)) * 0.001)[0]
    x = x[: loud[-1] + 1].copy()
    fade = min(len(x), int(0.02 * RATE))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.max(np.abs(x)) * peak


def coin():
    """A coin lands in the purse: two quick clinks."""
    t = time(0.55)
    out = np.zeros_like(t)
    for at, pitch, gain in ((0.0, 1.0, 1.0), (0.07, 1.06, 0.8)):
        s = int(at * RATE)
        u = t[: len(t) - s]
        partials = [(2637 * pitch, 1.0, 0.16), (3951 * pitch * 1.01, 0.6, 0.11), (5274 * pitch * 0.99, 0.4, 0.07),
                    (6644 * pitch, 0.25, 0.045)]
        out[s:] += gain * (bell(u, partials) + 0.3 * highpass(noise(u), 4000) * decay(u, 0.002, 0.0002))
    return finish(reverb(out, 0.5, 0.12), 0.8)


def kill_slain():
    """Tier 1, a kill: a blade's ring over a punch."""
    t = time(0.9)
    ring = bell(t, [(987, 0.8, 0.35), (1568 * 1.003, 1.0, 0.28), (2349, 0.6, 0.2), (3135, 0.4, 0.14),
                    (4186 * 1.01, 0.3, 0.09)])
    hiss = highpass(noise(t), 2500) * decay(t, 0.04, 0.001)
    return finish(reverb(ring + 0.5 * hiss + 0.9 * boom(t, 120, 60, 0.1), 0.9, 0.2), 0.9, 1.4)


def chord(t, notes, attack, tau, bright=1.0):
    env = decay(t, tau, attack)
    return sum(tone(t, f, 12, bright) for f in notes) * env


def kill_big():
    """Tier 2 (first blood, double kill, on fire): a punch and a bright major chord."""
    t = time(1.3)
    brass = lowpass(chord(t, [293.66, 440.0, 587.33, 739.99], 0.025, 0.45), 4200)
    shimmer = bell(t, [(2349.3, 0.3, 0.5), (2960, 0.2, 0.4)]) * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * t))
    return finish(reverb(0.35 * brass + shimmer + 1.2 * boom(t, 120, 50, 0.14), 1.2, 0.28), 0.92, 1.6)


def kill_huge():
    """Tier 3 (triple kill, shutdown, unstoppable): a deep boom, a crash and a full chord."""
    t = time(1.8)
    brass = lowpass(chord(t, [164.81, 246.94, 329.63, 415.30, 493.88], 0.04, 0.75), 3800)
    crash = band(noise(t), 3000, 11000) * decay(t, 0.45, 0.004)
    return finish(reverb(0.3 * brass + 0.35 * crash + 1.4 * boom(t, 100, 40, 0.25), 1.4, 0.32), 0.95, 1.8)


def kill_legend():
    """Tier 4 (wipeout, legend): a stab, then a rising, sustained chord over the deepest boom."""
    t = time(2.4)
    stab = lowpass(chord(t, [261.63, 329.63, 392.0, 523.25], 0.015, 0.12), 4000)
    rise = int(0.24 * RATE)
    held = np.zeros_like(t)
    u = t[: len(t) - rise]
    held[rise:] = lowpass(chord(u, [146.83, 293.66, 369.99, 440.0, 587.33, 739.99], 0.05, 1.0, 1.2), 4500)
    crash = band(noise(t), 3000, 11000) * decay(t, 0.6, 0.004)
    sparkle = np.zeros_like(t)
    for i, f in enumerate((1174.66, 1479.98, 1760.0, 2349.32)):
        s = rise + int(i * 0.07 * RATE)
        sparkle[s:] += bell(t[: len(t) - s], [(f, 0.35, 0.3)])
    out = 0.3 * stab + 0.3 * held + 0.35 * crash + sparkle + 1.5 * boom(t, 95, 36, 0.3)
    out[rise:] += 0.9 * boom(u, 110, 45, 0.2)
    return finish(reverb(out, 1.6, 0.34), 0.95, 1.8)


def death():
    """You are slain: a dull boom and a dark chord sinking away."""
    t = time(1.6)
    fall = 1 - 0.06 * (1 - np.exp(-t / 0.5))
    notes = [110.0, 130.81, 164.81, 220.0]
    dark = sum(np.sin(2 * np.pi * np.cumsum(f * fall) / RATE * n) / n**1.5 for f in notes for n in range(1, 7))
    dark = lowpass(dark * decay(t, 0.6, 0.03), 900)
    return finish(reverb(0.6 * dark + 1.3 * boom(t, 90, 32, 0.3), 1.4, 0.3), 0.9, 1.5)


SOUNDS = {
    "Coin": coin,
    "KillSlain": kill_slain,
    "KillBig": kill_big,
    "KillHuge": kill_huge,
    "KillLegend": kill_legend,
    "Death": death,
}


def write(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def build():
    parts, regions, at = [], {}, 0.0
    for name, make in SOUNDS.items():
        x = make()
        write(OUT / "Preview" / f"{name}.wav", x)
        regions[name] = (round(at, 4), round(len(x) / RATE, 4))
        parts += [x, np.zeros(int(GAP * RATE))]
        at += len(x) / RATE + GAP
    joined = OUT / "ui_sounds.wav"
    write(joined, np.concatenate(parts))
    return joined, regions


def module(asset, regions):
    lines = [
        "-- Generated by Tools/ui_sounds.py; do not edit by hand.",
        "-- Asset: the game's own interface sounds in one uploaded file. Regions: where each sits in it (start, length).",
        "return {",
        f'\t["Asset"] = "{asset}",',
        '\t["Regions"] = {',
    ]
    lines += [f'\t\t["{name}"] = {{ {start}, {length} }},' for name, (start, length) in regions.items()]
    lines += ["\t},", "}", ""]
    MODULE.write_text("\n".join(lines))


if __name__ == "__main__":
    joined, regions = build()
    for name, (start, length) in regions.items():
        print(f"{name:12} {start:7.3f} {length:5.2f}")
    print(joined)
    if "--upload" in sys.argv:
        from upload_audio import upload

        asset = upload(joined, "Defend The Master interface sounds")
        module(asset, regions)
        print(MODULE)
