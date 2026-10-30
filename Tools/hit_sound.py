#!/usr/bin/env python3
"""Synthesises the hit sound every hit plays, for everyone on everything (the owner's picks, 2026-10-29: a dry crunch
that sounds like no weapon in particular), in the two takes he is choosing between, to Art/Sounds/<take>.wav.

    python3 Tools/hit_sound.py                    # writes every take
    python3 Tools/hit_sound.py --upload <take>    # also uploads that take and prints its asset id, for Assets.luau

Made from noise and a falling sine, so nothing is borrowed: a burst of band-passed noise over a thump falling in pitch,
driven into a soft clip.
"""

import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Art" / "Sounds"
RATE = 48000
LENGTH = 0.15
SEED = 21

# Each take: the noise's band (Hz) and how fast it dies away (s), the thump's fall (Hz), and the noise the owner heard,
# the draw of SEED after `before` (the lengths drawn before it, from the eight takes he picked from).
TAKES = {
    # Wide: more grit (take 8).
    "Hit": {
        "band": (500, 6500),
        "decay": 0.034,
        "fall": (160, 60),
        "before": [0.15, 0.12, 0.15, 0.15, 0.15, 0.15, 0.15],
    },
    # Low: deeper (take 3).
    "HitLow": {"band": (400, 4000), "decay": 0.03, "fall": (130, 48), "before": [0.15, 0.12]},
}


def time(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def envelope(x, attack, decay):
    t = np.arange(len(x)) / RATE
    return x * np.minimum(1, t / attack) * np.exp(-t / decay)


def band(x, low, high):
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0
    return np.fft.irfft(spectrum, len(x))


def fall(start, end, seconds, rate):
    t = time(seconds)
    freq = end + (start - end) * np.exp(-t * rate)
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE)


def hit(take):
    rng = np.random.default_rng(SEED)
    for seconds in take["before"]:
        rng.standard_normal(int(RATE * seconds))
    noise = rng.standard_normal(int(RATE * LENGTH))
    grit = 0.8 * envelope(band(noise, *take["band"]), 0.0005, take["decay"])
    thump = 0.8 * envelope(fall(*take["fall"], LENGTH, 25), 0.001, 0.045)
    drive = 4.0
    x = np.tanh((grit + thump) * drive) / np.tanh(drive)
    x = x - np.mean(x)
    tail = int(RATE * 0.004)
    x[-tail:] *= np.linspace(1, 0, tail)
    return x / np.max(np.abs(x)) * 0.9


def raw():
    """HitRaw: the low take sharper and rougher, a crack of high noise on top and driven harder (the owner's pick of
    six, 2026-10-29: "scherper, grauwer"). Its noise: the first draw of seed 99, its crack the third."""
    rng = np.random.default_rng(99)
    noise = rng.standard_normal(int(RATE * LENGTH))
    rng.standard_normal(int(RATE * 0.03))
    crack = rng.standard_normal(int(RATE * 0.03))
    grit = 1.0 * envelope(band(noise, 800, 8000), 0.0003, 0.03)
    thump = 0.8 * envelope(fall(140, 50, LENGTH, 25), 0.0008, 0.04)
    snap = 0.6 * envelope(band(crack, 3000, 12000), 0.0001, 0.005)
    x = grit + thump + np.pad(snap, (0, len(grit) - len(snap)))
    drive = 8.0
    x = np.tanh(x * drive) / np.tanh(drive)
    x = x - np.mean(x)
    tail = int(RATE * 0.004)
    x[-tail:] *= np.linspace(1, 0, tail)
    return x / np.max(np.abs(x)) * 0.9


def write(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
    for name, take in TAKES.items():
        write(OUT / f"{name}.wav", hit(take))
        print(OUT / f"{name}.wav")
    write(OUT / "HitRaw.wav", raw())
    print(OUT / "HitRaw.wav")
    if "--upload" in sys.argv:
        from upload_audio import upload

        name = sys.argv[sys.argv.index("--upload") + 1]
        upload(OUT / f"{name}.wav", f"Defend The Master {name}")
