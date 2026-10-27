"""Fit the race-margin read of the strip against our defending bots.

Reads .preview/strip_race/stretches.csv (tests/instruments/ai/test_strip_race_export.gd):
every 0.1 s stretch of the saved runs with each defender's race margin to the
puck's spot (how much sooner than the puck his stick can be within the strip
radius, read from the run's start). The model:

    strips in a stretch = dt * rate * sum over defenders of g(margin)
    g(m) = 1 / (1 + exp(-(m - m0) / s))

rate split by whether the puck stands. Fitted by survival likelihood, on half the
runs and scored on the other half, against the current strip odds (as they are
and rescaled to their best level) and a constant rate. Then, fitted on all: the
losses it expects by how far ahead, the ranking the truth gate scores, and the
loss rate by margin with no shape assumed.

    python3 tools/strip_race_fit.py [.preview/strip_race/stretches.csv]
"""
import csv
import sys

import numpy as np

BANDS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.01]
M0S = np.arange(-1.5, 2.01, 0.05)
SCALES = np.array([0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0, 1.5])
RATES = np.geomspace(0.05, 12.0, 60)


def load(path):
    cols = {k: [] for k in ("run", "family", "t", "dt", "stand", "lost", "watched", "cur", "m1", "m2")}
    with open(path) as f:
        for row in csv.DictReader(f):
            cols["run"].append(int(row["run"]))
            cols["family"].append(row["family"])
            cols["t"].append(float(row["t"]))
            cols["dt"].append(float(row["dt"]))
            cols["stand"].append(int(row["stand"]))
            cols["lost"].append(int(row["lost"]))
            cols["watched"].append(float(row["watched_to"]))
            cols["cur"].append(float(row["current"]))
            cols["m1"].append(float(row["m1"]))
            cols["m2"].append(float(row["m2"]) if row["m2"] else np.nan)
    d = {k: np.array(v) for k, v in cols.items()}
    return d


def g(m, m0, s):
    out = 1.0 / (1.0 + np.exp(-(m - m0) / s))
    return np.where(np.isnan(m), 0.0, out)


def loglik(lam, lost):
    lam = np.maximum(lam, 1e-12)
    return np.where(lost == 1, np.log1p(-np.exp(-lam)), -lam).sum()


def best_rate(x, lost):
    """The rate r maximising the likelihood of strips r * x, and that likelihood."""
    if x.size == 0:
        return 0.0, 0.0
    lls = [loglik(r * x, lost) for r in RATES]
    i = int(np.argmax(lls))
    return RATES[i], lls[i]


def fit_race(d, mask):
    best = (-np.inf, None)
    mv = mask & (d["stand"] == 0)
    st = mask & (d["stand"] == 1)
    for m0 in M0S:
        for s in SCALES:
            cover = d["dt"] * (g(d["m1"], m0, s) + g(d["m2"], m0, s))
            rm, llm = best_rate(cover[mv], d["lost"][mv])
            rs, lls = best_rate(cover[st], d["lost"][st])
            if llm + lls > best[0]:
                best = (llm + lls, (m0, s, rm, rs))
    return best[1]


def race_lambda(d, p):
    m0, s, rm, rs = p
    cover = d["dt"] * (g(d["m1"], m0, s) + g(d["m2"], m0, s))
    return cover * np.where(d["stand"] == 1, rs, rm)


def ranking(d, lam):
    """The truth gate's ranking: at each loss, the run that lost read riskier up to
    then than each run still in play."""
    runs = np.unique(d["run"])
    cum = {}
    lost_at = {}
    watched = {}
    for r in runs:
        idx = np.where(d["run"] == r)[0]
        cum[r] = (d["t"][idx], np.cumsum(lam[idx]))
        watched[r] = d["watched"][idx[0]]
        if d["lost"][idx].any():
            lost_at[r] = d["t"][idx][d["lost"][idx] == 1][0]

    def risk_at(r, t):
        ts, c = cum[r]
        k = np.searchsorted(ts, t + 1e-4) - 1
        return c[k] if k >= 0 else 0.0

    conc = 0.0
    pairs = 0.0
    for a, ta in lost_at.items():
        ra = cum[a][1][-1]
        for b in runs:
            if b == a or watched[b] <= ta:
                continue
            rb = risk_at(b, ta)
            pairs += 1
            conc += 1.0 if ra > rb else (0.5 if ra == rb else 0.0)
    return conc / pairs


def by_band(d, lam, mask=None):
    mask = np.ones_like(d["lost"], bool) if mask is None else mask
    out = []
    for a, b in zip(BANDS[:-1], BANDS[1:]):
        sel = mask & (d["t"] >= a) & (d["t"] < b)
        out.append("%.1f-%.1f s %d/%.1f" % (a, min(b, 3.0), d["lost"][sel].sum(), lam[sel].sum()))
    return "  ".join(out)


def main():
    d = load(sys.argv[1] if len(sys.argv) > 1 else ".preview/strip_race/stretches.csv")
    n_runs = len(np.unique(d["run"]))
    print("%d stretches of %d runs, %d losses" % (len(d["t"]), n_runs, d["lost"].sum()))

    print("\nheld out (fit on one half of the runs, scored on the other), log likelihood per run:")
    halves = [d["run"] % 2 == 0, d["run"] % 2 == 1]
    tot = {"constant": 0.0, "current": 0.0, "current rescaled": 0.0, "race margin": 0.0}
    for fit_mask, test_mask in ((halves[0], halves[1]), (halves[1], halves[0])):
        c, _ = best_rate(d["dt"][fit_mask], d["lost"][fit_mask])
        tot["constant"] += loglik(c * d["dt"][test_mask], d["lost"][test_mask])
        tot["current"] += loglik(d["cur"][test_mask], d["lost"][test_mask])
        k, _ = best_rate(d["cur"][fit_mask], d["lost"][fit_mask])
        tot["current rescaled"] += loglik(k * d["cur"][test_mask], d["lost"][test_mask])
        p = fit_race(d, fit_mask)
        tot["race margin"] += loglik(race_lambda(d, p)[test_mask], d["lost"][test_mask])
        print("  fit on a half: race margin m0 %.2f s, s %.2f s, rates moving %.2f, standing %.2f /s"
              % p)
    for name, ll in tot.items():
        print("  %-17s %.4f" % (name, ll / n_runs))

    p = fit_race(d, np.ones_like(d["lost"], bool))
    lam = race_lambda(d, p)
    k, _ = best_rate(d["cur"], d["lost"])
    print("\nfitted on all: m0 %.2f s, s %.2f s, rates moving %.2f, standing %.2f /s" % p)
    print("\nlosses by how far ahead (lost/expected):")
    print("  current          " + by_band(d, d["cur"]))
    print("  current x %.2f    " % k + by_band(d, k * d["cur"]))
    print("  race margin      " + by_band(d, lam))
    print("\nby family (lost / current / race margin):")
    for fam in sorted(set(d["family"])):
        sel = d["family"] == fam
        print("  %-14s %4d / %6.1f / %6.1f" % (fam, d["lost"][sel].sum(), d["cur"][sel].sum(),
                                               lam[sel].sum()))
    print("\nranking: current %.3f, race margin %.3f" % (ranking(d, d["cur"]), ranking(d, lam)))

    print("\nloss rate by margin, one defender, puck moving, no shape assumed:")
    single = np.isnan(d["m2"]) & (d["stand"] == 0)
    edges = [-9, -1.5, -1.0, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 9]
    for a, b in zip(edges[:-1], edges[1:]):
        sel = single & (d["m1"] >= a) & (d["m1"] < b)
        expo = d["dt"][sel].sum()
        ev = d["lost"][sel].sum()
        fit = (p[2] * g(np.array([(max(a, -3) + min(b, 3)) / 2]), p[0], p[1]))[0]
        print("  %5.2f to %5.2f s: %3d losses in %6.1f s = %.2f /s   (fit %.2f)" % (
            a, b, ev, expo, ev / expo if expo > 0 else 0.0, fit))


if __name__ == "__main__":
    main()
