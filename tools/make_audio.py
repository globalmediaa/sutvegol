#!/usr/bin/env python3
"""Frikik Kral ses seti — tamamen sentez (telifsiz). Çalıştır: python3 tools/make_audio.py
Çıktı: assets/audio/*.wav (22.05 kHz, mono, 16 bit)."""
import math, os, random, struct, wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = random.Random(42)

def n(dur): return int(dur * SR)
def zeros(dur): return [0.0] * n(dur)

def tone(freq, dur, amp=1.0, harm=(), decay=None, attack=0.004, vib=0.0, vibr=5.0, sweep=None):
    """Sinüs (+ harmonikler). freq sabit ya da sweep=(f0,f1) ile üstel kayma. decay: üstel zaman sabiti."""
    out = []
    ph = 0.0
    N = n(dur)
    for i in range(N):
        t = i / SR
        if sweep:
            f = sweep[0] * (sweep[1] / sweep[0]) ** (t / dur)
        else:
            f = freq
        if vib:
            f *= 1 + vib * math.sin(2 * math.pi * vibr * t)
        ph += 2 * math.pi * f / SR
        v = math.sin(ph)
        for k, a in harm:
            v += a * math.sin(ph * k)
        e = 1.0
        if t < attack: e = t / attack
        if decay: e *= math.exp(-t / decay)
        rel = dur - t
        if rel < 0.01: e *= rel / 0.01
        out.append(v * amp * e)
    return out

def noise(dur, amp=1.0):
    return [rng.uniform(-1, 1) * amp for _ in range(n(dur))]

def lowpass(x, cutoff):
    if callable(cutoff):
        out, y = [], 0.0
        for i, v in enumerate(x):
            c = cutoff(i / SR)
            a = 1 - math.exp(-2 * math.pi * c / SR)
            y += a * (v - y)
            out.append(y)
        return out
    a = 1 - math.exp(-2 * math.pi * cutoff / SR)
    out, y = [], 0.0
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out

def highpass(x, cutoff):
    return [v - l for v, l in zip(x, lowpass(x, cutoff))]

def env(x, points):
    """points: [(t, gain)] doğrusal zarf."""
    out = []
    N = len(x)
    for i, v in enumerate(x):
        t = i / SR
        g = points[-1][1]
        for (t0, g0), (t1, g1) in zip(points, points[1:]):
            if t0 <= t <= t1:
                g = g0 + (g1 - g0) * (t - t0) / max(1e-9, t1 - t0)
                break
        if t < points[0][0]: g = points[0][1]
        out.append(v * g)
    return out

def decay(x, tau, start=0.0):
    return [v * (1.0 if i / SR < start else math.exp(-(i / SR - start) / tau)) for i, v in enumerate(x)]

def mix(*layers):
    """layers: (samples, offset_s, gain)"""
    total = max(len(s) + n(o) for s, o, g in layers)
    out = [0.0] * total
    for s, o, g in layers:
        k = n(o)
        for i, v in enumerate(s):
            out[k + i] += v * g
    return out

def loopify(x, xfade=0.25):
    """Sonu başa çapraz geçirerek dikişsiz döngü."""
    m = n(xfade)
    out = x[:len(x) - m]
    for i in range(m):
        a = i / m
        out[i] = out[i] * a + x[len(x) - m + i] * (1 - a)
    return out

def write(name, x, peak=0.85):
    mx = max(1e-9, max(abs(v) for v in x))
    g = peak / mx
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * g)) * 32767)) for v in x))
    print(f'{name:22s} {len(x)/SR:5.2f}s')

# ---------------------------------------------------------------- efektler

def sfx_kick():
    thump = tone(0, 0.22, sweep=(170, 42), decay=0.07, harm=[(2, 0.3)])
    snap = decay(highpass(lowpass(noise(0.08), 3200), 700), 0.02)
    whoosh = env(lowpass(noise(0.42), lambda t: 350 + 2600 * t), [(0, 0), (0.12, 0.5), (0.3, 1), (0.42, 0)])
    return mix((thump, 0, 1.0), (snap, 0, 0.6), (whoosh, 0.02, 0.45))

def sfx_hit():
    swish = decay(highpass(noise(0.3), 1400), 0.07)
    chime = mix((tone(659, 0.7, decay=0.22, harm=[(2, 0.25)]), 0, 1), (tone(988, 0.7, decay=0.2), 0.05, 0.7), (tone(1319, 0.5, decay=0.15), 0.1, 0.4))
    return mix((swish, 0, 0.6), (chime, 0.02, 0.9))

def sfx_miss():
    thud = tone(0, 0.25, sweep=(130, 55), decay=0.09)
    womp = tone(0, 0.42, sweep=(330, 150), decay=0.16, harm=[(2, 0.4), (3, 0.15)])
    return mix((thud, 0, 1), (womp, 0.03, 0.5))

def sfx_roll():
    x = lowpass(noise(0.55), 520)
    x = [v * (0.7 + 0.3 * math.sin(2 * math.pi * 13 * i / SR)) for i, v in enumerate(x)]
    return env(x, [(0, 0), (0.05, 1), (0.4, 0.8), (0.55, 0)])

def sfx_king_start():
    riser = env(lowpass(noise(0.7), lambda t: 250 + 6000 * (t / 0.7) ** 2), [(0, 0), (0.6, 1), (0.7, 0)])
    rise = tone(0, 0.7, sweep=(220, 880), attack=0.05, harm=[(2, 0.3)])
    rise = env(rise, [(0, 0), (0.5, 0.8), (0.7, 0)])
    chord = mix(*[(tone(f, 1.1, decay=0.35, harm=[(2, 0.3), (3, 0.1)]), 0, 1) for f in (523, 659, 784, 1046)])
    pops = zeros(1.2)
    for _ in range(18):
        at = rng.uniform(0.6, 1.5)
        p = decay(lowpass(noise(0.03), 2500), 0.006)
        pops = mix((pops, 0, 1), (p, min(at, 1.15), 0.5))
    return mix((riser, 0, 0.5), (rise, 0, 0.35), (chord, 0.62, 0.9), (pops, 0, 0.6))

def sfx_king_hit():
    notes = [(1046, 0), (1318, 0.06), (1568, 0.12), (2093, 0.18)]
    arp = mix(*[(tone(f, 0.5, decay=0.14, harm=[(2, 0.2)]), o, 1) for f, o in notes])
    spark = tone(2637, 0.3, decay=0.06)
    return mix((arp, 0, 1), (spark, 0.2, 0.4))

def sfx_king_end():
    fall = tone(0, 0.55, sweep=(880, 200), decay=0.3, harm=[(2, 0.25)])
    puff = decay(lowpass(noise(0.4), 1200), 0.08)
    return mix((fall, 0, 0.9), (puff, 0.05, 0.6))

def sfx_gameover():
    def note(f, dur, off): return (tone(f, dur, decay=dur * 0.9, harm=[(2, 0.35), (3, 0.15)], vib=0.004, vibr=6), off, 1)
    seq = mix(note(440, 0.32, 0), note(349, 0.32, 0.28), note(294, 0.9, 0.56))
    thud = tone(0, 0.5, sweep=(90, 40), decay=0.18)
    return mix((seq, 0, 0.9), (thud, 0.56, 0.7))

def sfx_count_end():
    return mix((tone(1320, 0.6, decay=0.16, harm=[(2, 0.3)]), 0, 1), (tone(2640, 0.4, decay=0.1), 0, 0.3))

def sfx_splash():
    ignite = env(lowpass(noise(0.8), lambda t: 200 + 4500 * (t / 0.8)), [(0, 0), (0.45, 1), (0.8, 0)])
    boom = tone(0, 0.9, sweep=(75, 45), decay=0.3, harm=[(2, 0.2)])
    shimmer = mix((tone(1760, 0.9, decay=0.3), 0, 1), (tone(2217, 0.9, decay=0.25), 0.04, 0.7), (tone(2637, 0.7, decay=0.2), 0.08, 0.5))
    return mix((ignite, 0, 0.7), (boom, 0.42, 1.0), (shimmer, 0.48, 0.45))

def sfx_stage_up():
    brass = [(2, 0.45), (3, 0.25), (4, 0.12)]
    seq = mix(
        (tone(392, 0.16, decay=0.3, harm=brass), 0.0, 1),
        (tone(523, 0.16, decay=0.3, harm=brass), 0.14, 1),
        (tone(659, 0.16, decay=0.3, harm=brass), 0.28, 1),
        (tone(784, 0.8, decay=0.45, harm=brass, vib=0.003, vibr=5.5), 0.42, 1.1),
        (tone(1046, 0.8, decay=0.4, harm=[(2, 0.2)]), 0.46, 0.5),
    )
    swell = env(lowpass(noise(1.3), 900), [(0, 0), (0.5, 0.6), (1.0, 0.4), (1.3, 0)])
    return mix((seq, 0, 1), (swell, 0, 0.25))

def king_loop():
    dur = 4.0
    rumble = lowpass(noise(dur), 230)
    crackle = zeros(dur)
    for _ in range(95):
        at = rng.uniform(0, dur - 0.05)
        p = decay(lowpass(noise(0.025), rng.uniform(1500, 4000)), 0.004)
        crackle = mix((crackle, 0, 1), (p, at, rng.uniform(0.3, 1.0)))
    shimmer = [math.sin(2 * math.pi * 3520 * i / SR) * (0.5 + 0.5 * math.sin(2 * math.pi * 0.7 * i / SR)) for i in range(n(dur))]
    x = mix((rumble, 0, 0.5), (crackle, 0, 0.7), (shimmer, 0, 0.06))
    return loopify(x, 0.3)

# ---------------------------------------------------------------- ambiyanslar

def slow_mod(dur, rate, depth, base=1.0):
    ph = rng.uniform(0, 6.28)
    return [base + depth * math.sin(2 * math.pi * rate * i / SR + ph) for i in range(n(dur))]

def amb_street(dur=24.0):
    wind = lowpass(noise(dur), 300)
    m = slow_mod(dur, 0.13, 0.35, 0.65)
    wind = [v * g for v, g in zip(wind, m)]
    cars = zeros(dur)
    for at in (3.5, 14.0):
        span = 3.2
        car = lowpass(noise(span), lambda t: 500 + 900 * math.sin(math.pi * t / span))
        car = env(car, [(0, 0), (span * 0.5, 1), (span, 0)])
        cars = mix((cars, 0, 1), (car, at, 0.7))
    horn = tone(415, 0.35, decay=0.4, harm=[(2, 0.5), (3, 0.3)])
    bark = mix((tone(0, 0.12, sweep=(500, 300), decay=0.05, harm=[(2, 0.5)]), 0, 1), (tone(0, 0.12, sweep=(520, 300), decay=0.05, harm=[(2, 0.5)]), 0.18, 0.8))
    x = mix((wind, 0, 1), (cars, 0, 0.6), (horn, 19.5, 0.12), (bark, 8.7, 0.08))
    return loopify(x, 1.5)

def amb_cage(dur=24.0):
    hum = mix((tone(100, dur, attack=0.5, harm=[(2, 0.35), (3, 0.12)]), 0, 1))
    flutter = slow_mod(dur, 0.9, 0.08, 1.0)
    hum = [v * g for v, g in zip(hum, flutter)]
    wind = lowpass(noise(dur), 380)
    wind = [v * g for v, g in zip(wind, slow_mod(dur, 0.09, 0.3, 0.5))]
    crick = zeros(dur)
    for _ in range(26):
        at = rng.uniform(0, dur - 1.2)
        train = zeros(1.0)
        for k in range(14):
            chirp = tone(rng.uniform(4000, 4400), 0.02, decay=0.008)
            train = mix((train, 0, 1), (chirp, k * 0.055, 1))
        crick = mix((crick, 0, 1), (train, at, rng.uniform(0.2, 0.5)))
    x = mix((hum, 0, 0.35), (wind, 0, 0.9), (crick, 0, 0.35))
    return loopify(x, 1.5)

def amb_stadium(dur=24.0):
    low = lowpass(noise(dur), 850)
    low = [v * g for v, g in zip(low, slow_mod(dur, 0.17, 0.25, 0.8))]
    high = highpass(lowpass(noise(dur), 2600), 700)
    high = [v * g for v, g in zip(high, slow_mod(dur, 0.23, 0.3, 0.6))]
    swells = zeros(dur)
    for at in (5.0, 16.5):
        sw = env(lowpass(noise(3.0), 1500), [(0, 0), (1.4, 1), (3.0, 0)])
        swells = mix((swells, 0, 1), (sw, at, 0.9))
    whistle = tone(2400, 0.45, decay=0.5, vib=0.02, vibr=30, harm=[(2, 0.2)])
    drum = zeros(2.0)
    for k in range(6):
        drum = mix((drum, 0, 1), (tone(0, 0.2, sweep=(140, 60), decay=0.08), k * 0.3, 1))
    x = mix((low, 0, 1), (high, 0, 0.5), (swells, 0, 0.7), (whistle, 11.0, 0.08), (drum, 20.0, 0.12))
    return loopify(x, 1.5)

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('sfx_kick.wav', sfx_kick())
    write('sfx_hit.wav', sfx_hit())
    write('sfx_miss.wav', sfx_miss())
    write('sfx_roll.wav', sfx_roll(), 0.6)
    write('sfx_king_start.wav', sfx_king_start())
    write('sfx_king_hit.wav', sfx_king_hit())
    write('sfx_king_end.wav', sfx_king_end())
    write('sfx_gameover.wav', sfx_gameover())
    write('sfx_count_end.wav', sfx_count_end())
    write('sfx_splash.wav', sfx_splash())
    write('sfx_stage_up.wav', sfx_stage_up())
    write('king_loop.wav', king_loop(), 0.5)
    write('amb_street.wav', amb_street(), 0.55)
    write('amb_cage.wav', amb_cage(), 0.5)
    write('amb_stadium.wav', amb_stadium(), 0.6)
