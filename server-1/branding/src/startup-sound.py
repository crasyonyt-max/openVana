# openVana startup sound — original composition in a late-90s style.
# Usage: startup-sound.py dry.wav, then add the reverb tail:
#   ffmpeg -i dry.wav -af "aecho=0.85:0.6:47|83|131|197|263:0.3|0.24|0.18|0.13|0.09,
#          apad=pad_dur=1.5,afade=t=out:st=7.3:d=1.2,volume=7.5dB" startup.wav
# Warm detuned pad swell + FM bell arpeggio + sub bass, rendered to stereo WAV.
import numpy as np, wave, sys

SR = 44100
DUR = 7.0
N = int(SR * DUR)
t = np.arange(N) / SR

def hz(note):  # MIDI note -> Hz
    return 440.0 * 2 ** ((note - 69) / 12)

def env(start, attack, hold, release, length=N):
    e = np.zeros(length)
    a0 = int(start * SR); a1 = a0 + int(attack * SR)
    h1 = a1 + int(hold * SR); r1 = h1 + int(release * SR)
    a1, h1, r1 = min(a1, length), min(h1, length), min(r1, length)
    e[a0:a1] = np.linspace(0, 1, a1 - a0) ** 2
    e[a1:h1] = 1
    e[h1:r1] = np.exp(-np.linspace(0, 6, r1 - h1))
    return e

def lowpass(x, cutoff):  # one-pole, cutoff may be an array (sweep)
    cutoff = np.broadcast_to(cutoff, x.shape)
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y

BRIGHT = 0.15 + 0.75 * np.clip(t / 2.5, 0, 1) ** 1.5   # pad opens up during the swell

def saw(f, phase=0.0):
    # band-limited sawtooth (no aliasing); upper harmonics fade in with BRIGHT
    out = np.zeros(N)
    for k in range(1, 24):
        if f * k > 7000: break
        out += np.sin(2 * np.pi * (f * k * t + phase * k)) / k * BRIGHT ** ((k - 1) / 3)
    return out * 0.6

L = np.zeros(N); R = np.zeros(N)

# 1) Pad: Ebmaj9 swelling in, then resolving to Abmaj9/Eb, then back to Eb add9
chords = [  # (start, length, notes)
    (0.0, 2.6, [51, 58, 62, 65, 70]),        # Eb Bb D F Bb
    (2.3, 4.7, [51, 56, 60, 63, 67, 70]),    # Eb Ab C Eb G Bb  (Abmaj9/Eb)
]
for start, length, notes in chords:
    e = env(start, 1.1, length - 1.1, 2.5)
    for k, n in enumerate(notes):
        for det, pan in ((-0.11, 0.8), (0.0, 0.5), (0.13, 0.2)):
            v = saw(hz(n + det / 1.0) * (1 + det * 0.003), phase=k * 0.17) * e
            L += v * (1 - pan) * 0.045
            R += v * pan * 0.045

# 2) Sub bass: soft sine on Eb
bass = np.sin(2 * np.pi * hz(39) * t) * env(0.15, 0.8, 3.5, 2.5) * 0.22
L += bass; R += bass

# 3) FM bells: rising arpeggio, then a high sparkle
def bell(start, note, amp, pan, decay=2.6):
    f = hz(note)
    tt = np.clip(t - start, 0, None)
    on = (t >= start).astype(float)
    mod = np.sin(2 * np.pi * f * 3.5 * tt) * 2.2 * np.exp(-tt * 3.0)
    car = np.sin(2 * np.pi * f * tt + mod) * np.exp(-tt * decay)
    attack = np.clip(tt / 0.004, 0, 1)
    v = car * attack * on * amp
    return v * (1 - pan), v * pan

arp = [(0.9, 75, 0.20, 0.30), (1.15, 79, 0.18, 0.60), (1.40, 82, 0.17, 0.40),
       (1.65, 86, 0.15, 0.70), (2.30, 84, 0.20, 0.50), (2.55, 87, 0.15, 0.30),
       (2.80, 91, 0.12, 0.65), (3.05, 94, 0.09, 0.45)]
for s, n, a, p in arp:
    l, r = bell(s, n, a, p); L += l; R += r

# final chime: low + high Eb ringing out
for s, n, a, p, d in [(3.4, 63, 0.16, 0.5, 1.2), (3.4, 75, 0.12, 0.35, 1.0), (3.45, 87, 0.08, 0.65, 1.1)]:
    l, r = bell(s, n, a, p, decay=d); L += l; R += r

# master: gentle fade-out, normalise
fade = np.ones(N); fade[-int(1.2 * SR):] = np.linspace(1, 0, int(1.2 * SR)) ** 2
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * 0.85, R / peak * 0.85

out = np.empty(2 * N, dtype=np.int16)
out[0::2] = (L * 32767).astype(np.int16)
out[1::2] = (R * 32767).astype(np.int16)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(out.tobytes())
