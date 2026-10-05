"""Procedural sound effects and menu music for the game.

Everything is synthesised from noise and oscillators, so the sounds are
original and can be regenerated: `python3 tools/gen_audio.py`.
Writes 16-bit WAV files to audio/ (Ogg for the long loops, via ffmpeg).
"""
import os
import subprocess
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def noise(dur, sr=SR):
    return rng.standard_normal(int(dur * sr))


def shape(sig, lo=0.0, hi=None, tilt=0.0, sr=SR):
    """Band-limit a signal in the frequency domain (circular, so loops stay seamless)."""
    spec = np.fft.rfft(sig)
    f = np.fft.rfftfreq(len(sig), 1 / sr)
    gain = np.ones_like(f)
    if lo > 0:
        gain *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    if hi is not None:
        gain *= 1 / (1 + (f / hi) ** 4)
    if tilt:
        gain *= (np.maximum(f, 20) / 1000.0) ** tilt
    return np.fft.irfft(spec * gain, len(sig))


def env(n, attack, decay, sr=SR):
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def norm(sig, peak=0.9):
    m = np.max(np.abs(sig))
    return sig * (peak / m) if m > 0 else sig


def fade(sig, fin=0.005, fout=0.02, sr=SR):
    sig = sig.copy()
    a, b = int(fin * sr), int(fout * sr)
    if a:
        sig[:a] *= np.linspace(0, 1, a)
    if b:
        sig[-b:] *= np.linspace(1, 0, b)
    return sig


def write(name, sig, sr=SR, ogg=False):
    data = (np.clip(sig, -1, 1) * 32767).astype(np.int16)
    channels = 1 if data.ndim == 1 else data.shape[1]
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    if ogg:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                        os.path.join(OUT, name + ".ogg")], check=True)
        os.remove(path)


def thump(freq0, freq1, dur, decay):
    t = t_axis(dur)
    f = freq1 + (freq0 - freq1) * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.001, decay)


def kick(power):
    dur = 0.35
    body = thump(220 if power else 180, 70 if power else 90, dur, 0.09 if power else 0.06)
    snap = shape(noise(dur), 1500, 7000) * env(int(dur * SR), 0.0005, 0.012 if power else 0.008)
    leather = shape(noise(dur), 400, 1800) * env(int(dur * SR), 0.001, 0.03)
    return fade(norm(body * 1.0 + snap * (0.9 if power else 0.5) + leather * 0.4, 0.95 if power else 0.7))


def tackle():
    dur = 0.4
    body = thump(140, 55, dur, 0.08)
    scuff = shape(noise(dur), 300, 3000) * env(int(dur * SR), 0.005, 0.08)
    boot = shape(noise(dur), 2000, 6000) * env(int(dur * SR), 0.0005, 0.01)
    return fade(norm(body + scuff * 0.6 + boot * 0.4, 0.85))


def slide():
    dur = 0.6
    n = int(dur * SR)
    t = t_axis(dur)
    grass = shape(noise(dur), 800, 5000) * (np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7)
    rustle = grass * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 23 * t)))
    return fade(norm(rustle * env(n, 0.04, 0.35), 0.7), 0.01, 0.08)


def whistle(blasts):
    """blasts: list of (start, length) in seconds."""
    total = max(s + l for s, l in blasts) + 0.15
    out = np.zeros(int(total * SR))
    for start, length in blasts:
        t = t_axis(length)
        trill = 1 + 0.035 * np.sign(np.sin(2 * np.pi * 34 * t))  # pea rattle
        f = 2900 * trill
        ph = 2 * np.pi * np.cumsum(f) / SR
        tone = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
        breath = shape(noise(length), 2000, 6000) * 0.12
        e = np.clip(t / 0.02, 0, 1) * np.clip((length - t) / 0.04, 0, 1)
        i = int(start * SR)
        out[i:i + len(t)] += (tone + breath) * e
    return fade(norm(out, 0.6))


def net():
    dur = 0.7
    n = int(dur * SR)
    swish = shape(noise(dur), 1200, 7000) * env(n, 0.01, 0.15)
    rattle = shape(noise(dur), 200, 900) * env(n, 0.005, 0.25) * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * t_axis(dur)))
    return fade(norm(swish * 0.7 + rattle, 0.8))


def crowd_bed(dur, sr):
    """Murmuring stadium: many babbling voices = formant-ish band noise with slow swells."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    base = shape(rng.standard_normal(n), 150, 2500, -0.3, sr)
    voices = np.zeros(n)
    for _ in range(14):
        centre = rng.uniform(350, 1400)
        band = shape(rng.standard_normal(n), centre * 0.7, centre * 1.4, 0, sr)
        rate = rng.integers(1, 6)  # whole cycles per loop keeps it seamless
        voices += band * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t / dur + rng.uniform(0, 6.28)))
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * 2 * t / dur)
    return (norm(base, 1) * 0.6 + norm(voices, 1) * 0.5) * swell


def crowd_loop():
    sr = 22050
    return norm(crowd_bed(8.0, sr), 0.5), sr


def cheer():
    dur = 3.2
    n = int(dur * SR)
    t = t_axis(dur)
    roar = shape(noise(dur), 300, 4000, -0.2)
    vowels = np.zeros(n)
    for centre in (600, 900, 1200, 2400):
        vowels += shape(noise(dur), centre * 0.85, centre * 1.15)
    e = np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 0.9, 0) / 1.1)
    claps = np.zeros(n)
    for _ in range(160):
        i = int(rng.uniform(0.2, dur - 0.1) * SR)
        c = shape(noise(0.03), 1000, 5000)
        claps[i:i + len(c)] += c * np.exp(-np.arange(len(c)) / (0.004 * SR))
    return fade(norm((norm(roar, 1) + norm(vowels, 1) * 0.7 + norm(claps, 1) * 0.25 * (t > 0.5)) * e, 0.9), 0.02, 0.4)


def ooh():
    """Near miss: the crowd's rising-then-falling 'oooh'."""
    dur = 1.8
    n = int(dur * SR)
    t = t_axis(dur)
    out = np.zeros(n)
    # Many voices singing an /u/ vowel with slightly different pitches.
    for _ in range(40):
        f0 = rng.uniform(140, 320)
        glide = f0 * (1 + 0.18 * np.sin(np.pi * np.clip(t / dur, 0, 1))) * (1 + 0.01 * rng.standard_normal())
        ph = 2 * np.pi * np.cumsum(glide) / SR + rng.uniform(0, 6.28)
        out += sum(np.sin(k * ph) / k ** 1.5 for k in range(1, 6))
    vowel = shape(out, 200, 900)
    air = shape(noise(dur), 300, 1500) * 0.3
    e = np.clip(t / 0.18, 0, 1) * np.clip((dur - t) / 0.7, 0, 1)
    return fade(norm((norm(vowel, 1) + air) * e, 0.75))


def click():
    dur = 0.06
    t = t_axis(dur)
    tone = np.sin(2 * np.pi * 1800 * t) * env(len(t), 0.0005, 0.012)
    return fade(norm(tone + shape(noise(dur), 3000, 8000) * env(len(t), 0.0003, 0.004) * 0.4, 0.5), 0.0005, 0.01)


def whoosh(reverse=False):
    dur = 0.55
    t = t_axis(dur)
    f = 300 + 2600 * (t / dur) ** 1.5
    sig = np.zeros(len(t))
    # Sweep a resonant band through noise in short blocks.
    blk = 512
    src = noise(dur)
    for i in range(0, len(t), blk):
        seg = src[i:i + blk]
        sig[i:i + blk] = shape(np.pad(seg, (0, blk - len(seg))), f[i] * 0.7, f[i] * 1.3)[:len(seg)]
    tone = np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR) * 0.15
    e = np.sin(np.pi * t / dur) ** 1.3
    out = norm((sig + tone) * e, 0.6)
    return fade(out[::-1] if reverse else out, 0.005, 0.03)


def chime(notes, step=0.09):
    """Short ascending UI chime (success / unlock)."""
    total = step * len(notes) + 0.5
    out = np.zeros(int(total * SR))
    for k, midi in enumerate(notes):
        f = 440 * 2 ** ((midi - 69) / 12)
        t = t_axis(0.5)
        tone = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * env(len(t), 0.003, 0.18)
        i = int(k * step * SR)
        out[i:i + len(t)] += tone
    return fade(norm(out, 0.5))


# --- Menu music ---------------------------------------------------------------

def music():
    """Upbeat anime-sports menu loop: 8 bars at 140 bpm in D major (I-V-vi-IV)."""
    sr = 32000
    bpm = 140
    beat = 60 / bpm
    bars = 8
    n = int(bars * 4 * beat * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    chords = [[62, 66, 69], [69, 73, 76], [71, 74, 78], [67, 71, 74]] * 2  # D A Bm G
    roots = [38, 45, 47, 43] * 2

    def note(midi, start, length, kind, vol):
        i0, i1 = int(start * sr), min(int((start + length) * sr), n)
        tt = np.arange(i1 - i0) / sr
        f = 440 * 2 ** ((midi - 69) / 12)
        if kind == "saw":
            w = sum(np.sin(2 * np.pi * f * k * tt) / k for k in range(1, 9))
            e = np.clip(tt / 0.02, 0, 1) * np.clip((length - tt) / 0.05, 0, 1)
        elif kind == "bass":
            w = np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(4 * np.pi * f * tt)
            e = np.clip(tt / 0.005, 0, 1) * np.exp(-tt / 0.35)
        else:  # pluck lead
            w = np.sign(np.sin(2 * np.pi * f * tt)) * 0.5 + np.sin(2 * np.pi * f * tt)
            e = np.clip(tt / 0.003, 0, 1) * np.exp(-tt / 0.12)
        out[i0:i1] += w * e * vol

    for b in range(bars):
        s = b * 4 * beat
        for m in chords[b]:
            note(m - 12, s, 4 * beat, "saw", 0.06)
        for q in range(8):
            note(roots[b], s + q * beat / 2, beat / 2, "bass", 0.35 if q % 2 == 0 else 0.22)
        arp = chords[b] + [chords[b][0] + 12]
        pattern = [0, 1, 2, 3, 2, 1, 2, 3] if b < 4 else [3, 2, 1, 0, 1, 2, 3, 2]
        for q in range(8):
            note(arp[pattern[q]] + 12, s + q * beat / 2, beat / 2, "pluck", 0.12)
    out = shape(out, 40, 6000, 0, sr)
    # Drums.
    for k in range(bars * 4):
        s = int(k * beat * sr)
        kd = np.sin(2 * np.pi * np.cumsum(50 + 120 * np.exp(-np.arange(int(0.25 * sr)) / sr / 0.03)) / sr)
        kd *= np.exp(-np.arange(len(kd)) / sr / 0.12)
        out[s:s + len(kd)] += kd * 0.5
        if k % 2 == 1:
            sn = shape(rng.standard_normal(int(0.2 * sr)), 1200, 8000, 0, sr) * np.exp(-np.arange(int(0.2 * sr)) / sr / 0.06)
            out[s:s + len(sn)] += sn * 0.18
        for h in range(2):
            hs = s + int(h * beat / 2 * sr)
            hh = shape(rng.standard_normal(int(0.05 * sr)), 7000, None, 0, sr) * np.exp(-np.arange(int(0.05 * sr)) / sr / 0.012)
            out[hs:hs + len(hh)] += hh * (0.06 if h else 0.035)
    return norm(out, 0.8), sr


def main():
    os.makedirs(OUT, exist_ok=True)
    write("kick", kick(False))
    write("kick_power", kick(True))
    write("tackle", tackle())
    write("slide", slide())
    write("whistle", whistle([(0, 0.28)]))
    write("whistle_long", whistle([(0, 0.9)]))
    write("whistle_final", whistle([(0, 0.35), (0.5, 0.35), (1.0, 1.1)]))
    write("whistle_foul", whistle([(0, 0.18), (0.26, 0.45)]))
    write("net", net())
    write("cheer", cheer())
    write("ooh", ooh())
    write("click", click())
    write("vision_on", whoosh())
    write("vision_off", whoosh(True))
    write("success", chime([74, 78, 81, 86]))
    crowd, sr = crowd_loop()
    write("crowd_loop", crowd, sr, ogg=True)
    mus, sr = music()
    write("menu_music", mus, sr, ogg=True)


if __name__ == "__main__":
    main()
