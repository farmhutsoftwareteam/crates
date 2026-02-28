#!/usr/bin/env python3
"""
Crates — audio analysis script.
Usage: python3 analyze_tracks.py <file1> [file2] ...
Outputs one JSON object per line (NDJSON), one per input file.

Requires: librosa, mutagen, numpy
Install:  pip3 install librosa mutagen
"""

import sys
import json
import os

# ── Camelot wheel ────────────────────────────────────────────────────────────
# Maps common key names (major/minor) → Camelot notation.
# Enharmonic equivalents are collapsed (e.g. Db == C#).
CAMELOT = {
    # Major keys (B = outer ring)
    "C":  "8B",  "G":  "9B",  "D":  "10B", "A":  "11B", "E":  "12B",
    "B":  "1B",  "F#": "2B",  "Gb": "2B",  "Db": "3B",  "C#": "3B",
    "Ab": "4B",  "G#": "4B",  "Eb": "5B",  "D#": "5B",  "Bb": "6B",
    "A#": "6B",  "F":  "7B",
    # Minor keys (A = inner ring)
    "Am": "8A",  "Em": "9A",  "Bm": "10A", "F#m":"11A", "C#m":"12A",
    "Dbm":"12A", "G#m":"1A",  "Abm":"1A",  "Ebm":"2A",  "D#m":"2A",
    "Bbm":"3A",  "A#m":"3A",  "Fm": "4A",  "Cm": "5A",  "Gm": "6A",
    "Dm": "7A",
}

# Krumhansl-Kessler tonal hierarchy profiles
KK_MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
KK_MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
NOTES    = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def detect_key(y, sr):
    """
    Detect musical key using chroma features and KK profiles.
    Returns (camelot, musical_key_string).
    """
    import librosa
    import numpy as np

    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, bins_per_octave=36)
    mean_c = np.mean(chroma, axis=1)
    # Normalise so correlation is meaningful
    mean_c = mean_c - np.mean(mean_c)

    maj = np.array(KK_MAJOR) - np.mean(KK_MAJOR)
    min_ = np.array(KK_MINOR) - np.mean(KK_MINOR)

    best_note, best_mode, best_corr = "C", "major", -1.0
    for i, note in enumerate(NOTES):
        rmaj = np.roll(maj, i)
        rmin = np.roll(min_, i)
        corr_maj = float(np.dot(mean_c, rmaj) /
                         (np.linalg.norm(mean_c) * np.linalg.norm(rmaj) + 1e-9))
        corr_min = float(np.dot(mean_c, rmin) /
                         (np.linalg.norm(mean_c) * np.linalg.norm(rmin) + 1e-9))
        if corr_maj > best_corr:
            best_corr, best_note, best_mode = corr_maj, note, "major"
        if corr_min > best_corr:
            best_corr, best_note, best_mode = corr_min, note, "minor"

    musical_key = best_note if best_mode == "major" else best_note + "m"
    camelot     = CAMELOT.get(musical_key, "—")
    return camelot, musical_key


def analyze_with_librosa(path):
    import librosa
    import numpy as np

    # Load up to 3 minutes for speed; full file if short
    y, sr = librosa.load(path, mono=True, sr=None, duration=180)

    # ── BPM ──────────────────────────────────────────────────────────────────
    # librosa 0.11+ may return tempo as a 1-element ndarray
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    tempo_val = tempo.item() if hasattr(tempo, "item") else float(tempo)
    bpm = round(float(tempo_val), 1)

    # ── Key ──────────────────────────────────────────────────────────────────
    camelot_key, musical_key = detect_key(y, sr)

    # ── Energy (RMS → 0-10 scale) ─────────────────────────────────────────
    rms = librosa.feature.rms(y=y)[0]
    rms_mean = float(np.mean(rms))
    # Typical RMS for loud music: ~0.10-0.20; normalise to 0-10
    energy = min(10.0, max(0.0, rms_mean / 0.12 * 10.0))
    energy = round(energy, 2)

    # ── Loudness (dBFS) ──────────────────────────────────────────────────────
    loudness_db = round(float(librosa.amplitude_to_db(np.array([rms_mean]))[0]), 1)

    # ── Danceability (beat strength regularity) ───────────────────────────
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    if len(beat_frames) > 0:
        valid = beat_frames[beat_frames < len(onset_env)]
        beat_strengths = onset_env[valid] if len(valid) > 0 else np.array([0.0])
    else:
        beat_strengths = np.array([0.0])
    max_onset = float(np.max(onset_env)) if len(onset_env) > 0 else 1.0
    danceability = round(
        min(10.0, float(np.mean(beat_strengths)) / (max_onset + 1e-9) * 10.0), 2
    )

    # ── Tempo stability (low CV of inter-beat intervals = stable) ────────
    if len(beat_frames) > 1:
        ioi  = np.diff(beat_frames.astype(float))
        cv   = float(np.std(ioi)) / (float(np.mean(ioi)) + 1e-9)
        tempo_stability = round(max(0.0, 1.0 - min(1.0, cv)), 3)
    else:
        tempo_stability = 0.0

    # ── Onset rate (percussive events per second) ─────────────────────────
    onsets      = librosa.onset.onset_detect(y=y, sr=sr)
    duration_s  = len(y) / sr
    onset_rate  = round(len(onsets) / duration_s if duration_s > 0 else 0.0, 2)

    # ── Spectral contrast (brightness / punch) ────────────────────────────
    spec_contrast = librosa.feature.spectral_contrast(y=y, sr=sr)
    spectral_contrast = round(float(np.mean(spec_contrast)), 2)

    return {
        "bpm":               bpm,
        "camelot_key":       camelot_key,
        "musical_key":       musical_key,
        "energy":            energy,
        "danceability":      danceability,
        "loudness_db":       loudness_db,
        "tempo_stability":   tempo_stability,
        "onset_rate":        onset_rate,
        "spectral_contrast": spectral_contrast,
        "analyser":          "librosa",
    }


def analyze_with_mutagen(path):
    """Fallback: reads tags only — no audio analysis."""
    from mutagen import File as MutagenFile

    bpm         = None
    camelot_key = None
    musical_key = None

    audio = MutagenFile(path, easy=False)
    if audio is not None:
        tags = audio.tags
        if tags:
            for key in ("TBPM", "BPM", "bpm"):
                if key in tags:
                    try:
                        raw = str(tags[key])
                        bpm = int(float(raw.split("\n")[0]))
                    except Exception:
                        pass
                    break
            for key in ("TKEY", "KEY", "initialkey", "key"):
                if key in tags:
                    raw_key = str(tags[key]).split("\n")[0].strip()
                    if raw_key:
                        musical_key = raw_key
                        camelot_key = CAMELOT.get(raw_key, raw_key)
                    break

    return {
        "bpm":               bpm,
        "camelot_key":       camelot_key,
        "musical_key":       musical_key,
        "energy":            None,
        "danceability":      None,
        "loudness_db":       None,
        "tempo_stability":   None,
        "onset_rate":        None,
        "spectral_contrast": None,
        "analyser":          "mutagen",
    }


def analyze(path):
    try:
        return analyze_with_librosa(path)
    except ImportError:
        pass  # librosa not installed

    try:
        return analyze_with_mutagen(path)
    except ImportError:
        return {
            "bpm": None, "camelot_key": None, "musical_key": None,
            "energy": None, "danceability": None, "loudness_db": None,
            "tempo_stability": None, "onset_rate": None,
            "spectral_contrast": None, "analyser": "none",
        }


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit(0)

    for path in paths:
        try:
            result = analyze(path)
            result["path"]  = path
            result["error"] = None
        except Exception as exc:
            result = {
                "path": path, "error": str(exc),
                "bpm": None, "camelot_key": None, "musical_key": None,
                "energy": None, "danceability": None, "loudness_db": None,
                "tempo_stability": None, "onset_rate": None,
                "spectral_contrast": None, "analyser": "error",
            }
        print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
