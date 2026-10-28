"""Score the pass lane reads against the worst-case interceptor's runs.

Reads .preview/pass_truth/runs.csv (tests/instruments/ai/test_pass_truth.gd): per
run the pass kind (flat, saucer, rim), whether it got through (complete), was
taken (intercepted) or neither (incomplete), whether the receiver still had it a
second after the catch, and the reads the bots price it with: the flat accurate
lane, the saucer's, the rim's race, the one-chance strip read along the puck's
own path, and the defender's best and first spare time on that path.

For each kind: the losses on the lane (not complete) against the losses each read
expects, how well each read ranks the lost passes over the completed ones (AUC),
and the share lost by the defender's best spare time — the set margin, if a
pass has one.

    python3 tools/pass_truth_fit.py [runs.csv ...]

Several files (one per interceptor set margin) are tabled side by side.
"""
import csv
import sys

import numpy as np


def load(path):
    rows = list(csv.DictReader(open(path)))
    d = {k: np.array([r[k] for r in rows]) for k in ("kind", "outcome")}
    for k in ("kept", "lane_flat", "lane_saucer", "rim_race", "path_keep", "best_spare",
              "first_spare", "t_out", "flight_s"):
        d[k] = np.array([float(r[k]) for r in rows])
    return d


def auc(risk, lost):
    pos = risk[lost]
    neg = risk[~lost]
    if pos.size == 0 or neg.size == 0:
        return float("nan")
    allv = np.concatenate([pos, neg])
    order = np.argsort(allv, kind="mergesort")
    ranks = np.empty(allv.size)
    ranks[order] = np.arange(1, allv.size + 1)
    for v in np.unique(allv):
        tie = allv == v
        if tie.sum() > 1:
            ranks[tie] = ranks[tie].mean()
    return (ranks[:pos.size].sum() - pos.size * (pos.size + 1) / 2.0) / (pos.size * neg.size)


def report(path):
    d = load(path)
    print("== %s: %d runs" % (path, len(d["kind"])))
    for kind, own in (("flat", "lane_flat"), ("saucer", "lane_saucer"), ("rim", "rim_race")):
        sel = d["kind"] == kind
        if not sel.any():
            continue
        out = d["outcome"][sel]
        lost = out != "complete"
        n = sel.sum()
        kept = d["kept"][sel]
        caught = kept >= 0
        print("  %-6s %4d runs: complete %3d, intercepted %3d, incomplete %3d | kept a second after the catch %d of %d"
              % (kind, n, (out == "complete").sum(), (out == "intercepted").sum(),
                 (out == "incomplete").sum(), (kept[caught] == 1).sum(), caught.sum()))
        for name, read in ((own, d[own][sel]), ("path_keep", d["path_keep"][sel])):
            print("    %-11s expects %6.1f lost of %3d (AUC %.3f)" % (
                name, (1.0 - read).sum(), lost.sum(), auc(1.0 - read, lost)))
        print("    share lost (not complete) by the defender's best spare time on the puck's path:")
        edges = [-99, -0.5, -0.25, 0.0, 0.1, 0.25, 0.5, 1.0, 99]
        line = "     "
        for a, b in zip(edges[:-1], edges[1:]):
            s2 = d["best_spare"][sel]
            m = (s2 >= a) & (s2 < b)
            if m.sum():
                line += " %s..%s: %d/%d" % (a if a > -99 else "", b if b < 99 else "", lost[m].sum(),
                                           m.sum())
        print(line)


def main():
    paths = sys.argv[1:] or [".preview/pass_truth/runs.csv"]
    for p in paths:
        report(p)


if __name__ == "__main__":
    main()
