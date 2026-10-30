#!/usr/bin/env python3
"""Prime hold-to-talk recorder: records until the key is released OR quiet.

Why not plain arecord: the release event can be lost (Hyprland drops a modified
`bindr` when Super comes up before R), and a take that never ends looks like the
feature is broken. This recorder watches the input level instead:

* it records continuously while @USER@ talks;
* it ends on SIGINT/SIGTERM immediately (the release path — prime-ptt-up.sh);
* it ends by itself after ``--silence-ms`` of *post-speech* quiet, so a lost
  release still submits and a mid-sentence pause shorter than that window can
  never cut him off;
* it gives up after ``--no-speech-timeout`` seconds if nothing was said at all.

On exit it writes the finished WAV (proper header), logs one line explaining why
it stopped plus the peak level, and leaves the state file in place for
prime-ptt-up.sh to claim.

``--self-test`` runs the same decision logic over synthetic audio, so the VAD can
be verified without a microphone.
"""
from __future__ import annotations

import argparse
import math
import os
import signal
import sys
import time
import wave

import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16000
BLOCK_MS = 100
BLOCK = SAMPLE_RATE * BLOCK_MS // 1000
QUIET_DB = -55.0
SPEECH_DB = -20.0

_stop = False
_stop_reason = "release"


def _request_stop(_signum, _frame):  # noqa: ANN001
    global _stop, _stop_reason
    _stop = True
    _stop_reason = "signal"


signal.signal(signal.SIGINT, _request_stop)
signal.signal(signal.SIGTERM, _request_stop)


def dbfs(block: np.ndarray) -> float:
    if block.size == 0:
        return -120.0
    rms = float(np.sqrt(np.mean(np.square(block.astype(np.float32)))))
    return 20.0 * math.log10(max(rms, 1e-6) / 32768.0)


def _tone(db: float, blocks: int) -> list[np.ndarray]:
    amplitude = 32768.0 * (10.0 ** (db / 20.0))
    rng = np.random.default_rng(7)
    out = []
    for _ in range(blocks):
        noise = rng.normal(0.0, amplitude, size=(BLOCK, 1))
        out.append(np.clip(noise, -32768, 32767).astype("int16"))
    return out


class _SynthStream:
    """Stands in for sd.InputStream in --self-test: 2s quiet, 3s speech, 4s quiet."""

    def __init__(self) -> None:
        self.blocks = _tone(QUIET_DB, 20) + _tone(SPEECH_DB, 30) + _tone(QUIET_DB, 40)

    def __enter__(self) -> "_SynthStream":
        return self

    def __exit__(self, *_exc) -> bool:
        return False

    def read(self, count: int):
        if self.blocks:
            return self.blocks.pop(0), False
        return np.zeros((count, 1), dtype="int16"), False


def run(args: argparse.Namespace, synth: bool) -> int:
    global _stop_reason

    if not synth and args.state_file:
        # Written here (not by the shell) so the pid in the state file is always
        # the recorder's own — prime-ptt-up.sh sends SIGINT to exactly this pid.
        try:
            with open(args.state_file, "w", encoding="utf-8") as fh:
                fh.write(f"{args.wav}\n{os.getpid()}\n")
        except OSError:
            pass

    frames: list[np.ndarray] = []
    floor_samples: list[float] = []
    floor_db = None
    speech_seen = False
    peak_db = -120.0
    # Audio clock, not wall clock: every block is BLOCK_MS of sound, so timing
    # stays correct even if a callback runs late (and it makes --self-test
    # meaningful, where synthetic blocks arrive far faster than real time).
    t_ms = 0.0
    last_speech_ms = 0.0
    hold_seen = False

    stream = _SynthStream() if synth else sd.InputStream(
        samplerate=SAMPLE_RATE, channels=1, dtype="int16", blocksize=BLOCK
    )
    with stream:
        while not _stop:
            block, _overflowed = stream.read(BLOCK)
            if block.size == 0:
                continue
            frames.append(block.copy())
            t_ms += BLOCK_MS
            level = dbfs(block)
            peak_db = max(peak_db, level)

            # Adaptive floor: the quietest of the first 8 blocks, then only ever
            # nudged (slowly up, instantly down) so a fan cannot raise it.
            if floor_db is None:
                floor_samples.append(level)
                if len(floor_samples) >= 8:
                    floor_db = min(floor_samples)
            else:
                floor_db = min(floor_db + 0.02, max(floor_db, level))

            if floor_db is None:
                last_speech_ms = t_ms
            elif level > min(floor_db + args.speech_margin_db, args.abs_db):
                speech_seen = True
                last_speech_ms = t_ms

            if (
                args.silence_ms > 0
                and speech_seen
                and (t_ms - last_speech_ms) >= args.silence_ms
            ):
                _stop_reason = "silence"
                break
            if (
                args.no_speech_timeout > 0
                and not speech_seen
                and t_ms >= args.no_speech_timeout * 1000.0
            ):
                _stop_reason = "no-speech"
                break
            if t_ms >= args.max_seconds * 1000.0:
                _stop_reason = "max-length"
                break

            if args.hold_file and not hold_seen:
                hold_seen = os.path.exists(args.hold_file)

            # Independent release detection: the repeat-enabled press bind keeps
            # refreshing --hold-file while the key is down. When it stops being
            # refreshed the key is up, whatever Hyprland did with the release
            # event. Skipped entirely if the file never exists (heartbeat
            # unavailable), so this can never end a take by accident.
            if args.hold_file and hold_seen:
                try:
                    age_ms = (time.time() - os.path.getmtime(args.hold_file)) * 1000.0
                except OSError:
                    age_ms = 0.0
                if age_ms >= args.hold_timeout_ms:
                    _stop_reason = "released"
                    break

    if not frames:
        print("[prime-ptt] recorder: no audio captured", file=sys.stderr)
        return 1

    audio = np.concatenate(frames, axis=0)
    if not synth:
        with wave.open(args.wav, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(audio.tobytes())

    seconds = audio.shape[0] / SAMPLE_RATE
    print(
        f"[prime-ptt] recorder: stopped by {_stop_reason} after {seconds:.1f}s, "
        f"peak {peak_db:.1f}dB"
        + ("" if speech_seen else " (no speech)"),
        file=sys.stderr,
    )
    if synth:
        ok = _stop_reason == "silence" and speech_seen
        print("self-test:", "PASS" if ok else f"FAIL (reason={_stop_reason})")
        return 0 if ok else 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--silence-ms", type=int, default=3000, help="0 disables the silence stop")
    ap.add_argument("--max-seconds", type=float, default=150.0)
    ap.add_argument("--speech-margin-db", type=float, default=9.0)
    ap.add_argument(
        "--abs-db",
        type=float,
        default=-35.0,
        help="absolute 'this is sound' floor: caps the adaptive threshold so a "
        "take that STARTS mid-speech still detects speech",
    )
    ap.add_argument(
        "--no-speech-timeout",
        type=float,
        default=8.0,
        help="0 disables (a held take may legitimately start quiet)",
    )
    ap.add_argument(
        "--hold-file",
        default="",
        help="timestamp file refreshed while the key is held; when it goes stale "
        "the take ends (release detection that does not depend on Hyprland's "
        "key-up event reaching the bind)",
    )
    ap.add_argument("--hold-timeout-ms", type=int, default=1000)
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="synthetic audio instead of the microphone (verifies the VAD)",
    )
    args = ap.parse_args()
    return run(args, synth=args.self_test)


if __name__ == "__main__":
    sys.exit(main())
