#!/usr/bin/env python3
"""Masters sound files to one reference loudness, so a cue played at 0 dB in
code is the same loudness whichever file it is, and the gains in
SoundManager._MIX_DB are the mix.

    python3 tools/normalize_sfx.py Sounds/*.wav Sounds/*.ogg          # report
    python3 tools/normalize_sfx.py --apply Sounds/new_cue.wav         # master

Needs ffmpeg on PATH; standard library only otherwise.

Loudness is the BS.1770 momentary peak (max over 400 ms K-weighted windows),
measured with silence padded around the file. Integrated LUFS is the wrong
meter here: it gates out anything shorter than 400 ms, i.e. most hits.

Where a file's peak would pass CEILING_DBFS at the reference, a lookahead
limiter takes the excess off the transient, up to MAX_LIMIT_DB. A file
needing more stays under the reference by the remainder rather than having
its attack flattened; the report says by how much, and that shortfall
belongs in the file's SoundManager._MIX_DB entry.
"""
import json
import os
import re
import subprocess
import sys

REFERENCE_LUFS_M = -18.0
CEILING_DBFS = -1.0
MAX_LIMIT_DB = 3.0
TOLERANCE_DB = 0.3
_PAD_S = 0.5


def _ffmpeg(*args):
    return subprocess.run(["ffmpeg", "-hide_banner", "-nostats", *args],
                          capture_output=True, text=True)


def measure(path):
    """(momentary-peak LUFS, sample peak dBFS)."""
    af = (f"adelay={int(_PAD_S * 1000)}:all=1,apad=pad_dur={_PAD_S * 2},"
          "ebur128=framelog=verbose:peak=sample")
    err = _ffmpeg("-v", "verbose", "-i", path, "-af", af, "-f", "null", "-").stderr
    momentary = [float(m) for m in re.findall(r"\bM:\s*(-?[\d.]+|-inf)", err) if m != "-inf"]
    peak = re.search(r"Sample peak:\s*\n\s*Peak:\s*(-?[\d.]+|-inf)", err)
    peak_db = float(peak.group(1)) if peak and peak.group(1) != "-inf" else -120.0
    return (max(momentary) if momentary else -120.0), peak_db


def _stream_info(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", path],
                         capture_output=True, text=True).stdout
    return json.loads(out)["streams"][0]


def _render(src, dst, gain_db, limit, info):
    chain = f"volume={gain_db:.3f}dB"
    if limit:
        ceiling = 10 ** ((CEILING_DBFS - 0.3) / 20)
        chain += f",alimiter=limit={ceiling:.5f}:attack=2:release=40:level=0:latency=1"
    codec = info["codec_name"]
    enc = ["-c:a", "libvorbis", "-q:a", "8"] if codec == "vorbis" else ["-c:a", codec]
    res = _ffmpeg("-y", "-i", src, "-af", chain, "-ar", info["sample_rate"],
                  "-ac", str(info["channels"]), *enc, "-map_metadata", "-1", dst)
    if res.returncode != 0:
        raise RuntimeError(res.stderr)


def master(path):
    """Brings `path` to the reference in place. Returns dB of limiting applied."""
    info = _stream_info(path)
    loud, peak = measure(path)
    max_gain = CEILING_DBFS + MAX_LIMIT_DB - peak
    gain = min(REFERENCE_LUFS_M - loud, max_gain)
    limit = peak + gain > CEILING_DBFS
    tmp = path + ".master" + os.path.splitext(path)[1]
    # Limiting costs a little loudness, so a limited file gets make-up passes,
    # each rendered from the untouched source.
    for _ in range(3):
        _render(path, tmp, gain, limit, info)
        out_loud, _ = measure(tmp)
        next_gain = min(gain + REFERENCE_LUFS_M - out_loud, max_gain)
        if abs(out_loud - REFERENCE_LUFS_M) <= TOLERANCE_DB or next_gain - gain < 0.05:
            break
        gain = next_gain
    os.replace(tmp, path)
    return max(0.0, peak + gain - CEILING_DBFS) if limit else 0.0


def main(argv):
    apply = "--apply" in argv
    paths = [a for a in argv if a != "--apply"]
    if not paths:
        print(__doc__)
        return 2
    off = 0
    print(f"{'file':24s} {'LUFS-M':>7s} {'peak':>6s} {'limit':>6s}")
    for path in paths:
        limited = master(path) if apply else 0.0
        loud, peak = measure(path)
        ok = abs(loud - REFERENCE_LUFS_M) <= TOLERANCE_DB
        off += 0 if ok else 1
        print(f"{os.path.basename(path):24s} {loud:7.1f} {peak:6.1f} {limited:6.1f}"
              + ("" if ok else f"   {loud - REFERENCE_LUFS_M:+.1f} dB from reference"))
    return 1 if off and not apply else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
