"""Draw the entry drill's decision moments (tests/instruments/ai/test_entry_decision_maps.gd).

Each moment is one PNG: the defenders' coverage (the odds one of them is within
his stick of each spot, AIStripOdds) 0.3 s, 1 s and 2 s on, with where each
defender really was then, the carrier and his mates, and what the carrier
decided. Our team attacks up the page.

    python3 tools/decision_maps.py [.preview/decision_maps/moments.jsonl]
"""
import json
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

BLUE_LINE_Z = 7.29
RINK_HALF_WIDTH = 13.0


def draw(moment, path):
    half_x, z_near, z_far, step = moment["grid"]
    fig, axes = plt.subplots(1, len(moment["ahead"]), figsize=(5.2 * len(moment["ahead"]), 7.2))
    cid, cx, cz, cvx, cvz = moment["carrier"]
    for j, ahead in enumerate(moment["ahead"]):
        ax = axes[j]
        cov = np.clip(np.array(moment["coverage"][j]), 0.0, 1.0)
        # Rows run from the near end (z_near) to the far end; y = -z puts the attack up.
        ax.imshow(cov, extent=(-half_x, half_x, -z_near, -z_far), origin="lower",
                  cmap="Reds", vmin=0.0, vmax=1.0, aspect="equal")
        for z, style in ((-BLUE_LINE_Z, "b-"), (0.0, "r--"), (BLUE_LINE_Z, "b-")):
            ax.plot([-RINK_HALF_WIDTH, RINK_HALF_WIDTH], [-z, -z], style, lw=1.5, alpha=0.6)
        for dx, dz, dvx, dvz in moment["defenders"]:
            ax.plot(dx, -dz, "o", color="darkred", ms=9)
            ax.arrow(dx, -dz, dvx * 0.5, -dvz * 0.5, color="darkred", width=0.08, head_width=0.5)
        for ax_x, ax_z in moment["actual"][j]:
            ax.plot(ax_x, -ax_z, "x", color="black", ms=11, mew=2.5)
        for pid, mx, mz in moment["mates"]:
            ring = pid == moment["pass_to"]
            ax.plot(mx, -mz, "o", color="royalblue", ms=9, mfc="none" if not ring else "royalblue")
        ax.plot(cx, -cz, "o", color="black", ms=10)
        ax.arrow(cx, -cz, cvx * 0.5, -cvz * 0.5, color="black", width=0.08, head_width=0.5)
        tx, tz = moment["carry_to"]
        if abs(tx) + abs(tz) > 0.01:
            ax.plot(tx, -tz, "*", color="limegreen", ms=16, mec="black")
        ax.set_xlim(-half_x, half_x)
        ax.set_ylim(-z_near, -z_far)
        ax.set_title("%.1f s on: coverage, x = where they really were" % ahead, fontsize=10)
    fig.suptitle("play %d at %.1f s: %s   (carry %.3f, pass %.3f to %d)" % (
        moment["run"], moment["t"], moment["decision"], moment["carry"], moment["pass"],
        moment["pass_to"]), fontsize=12)
    fig.text(0.5, 0.01, "red shade: odds a defender's stick is within 2 m of that spot then; "
             "dots and arrows: now and 0.5 s of velocity; black = carrier, blue = mates "
             "(filled: pass target), star = carry target", ha="center", fontsize=9)
    fig.tight_layout(rect=(0, 0.03, 1, 0.95))
    fig.savefig(path, dpi=80)
    plt.close(fig)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else ".preview/decision_maps/moments.jsonl"
    out_dir = os.path.dirname(src)
    with open(src) as f:
        moments = [json.loads(line) for line in f if line.strip()]
    for k, m in enumerate(moments):
        draw(m, os.path.join(out_dir, "moment_%02d_play%d_%.1fs.png" % (k, m["run"], m["t"])))
    print("drew %d moments into %s" % (len(moments), out_dir))


if __name__ == "__main__":
    main()
