"""Fit the one-chance interception read of a carry path (docs/strip-interception-plan.md).

Reads .preview/strip_interception/runs.csv (tests/instruments/ai/test_interception_export.gd):
per run, whether the puck was lost, and each defender's best spare time on the
planned path. The model:

    p(spare) = p_max / (1 + exp(-(spare - s0) / w))     each defender's one chance
    keep     = product over defenders of (1 - p)

Fitted by likelihood on half the runs and scored on the other half, against the
current strip odds' keep along the same path (as it is, and rescaled to its best
level) and a constant. Then, fitted on all: the share lost by best spare against
the fit, by family, and how well each separates the runs that lost the puck
(AUC: the odds a lost run read riskier than a kept one).

    python3 tools/strip_interception_fit.py [runs.csv] [--fit-from other_runs.csv] [--keys]

--fit-from fits on another file's runs and scores this one with it, nothing
refitted (the bot runs, read with the interceptor's curve).

--keys compares what a defender's one chance should fall off with, each fitted
the same way: how early his first chance is (the first sample of the path he
reaches with a quarter second to spare), or how little of his range reaches the
path (the least share of the time to a sample his stick needs) — against a flat
chance whenever he can get there, and the strip read as it is.
"""
import csv
import sys

import numpy as np
from scipy.optimize import minimize


def load(path):
    cols = {k: [] for k in ("run", "family", "lost", "lost_at", "s1", "s2", "cur", "f1", "g1",
                            "g2", "u1", "u2")}
    with open(path) as f:
        for row in csv.DictReader(f):
            cols["run"].append(int(row["run"]))
            cols["family"].append(row["family"])
            cols["lost"].append(int(row["lost"]))
            cols["s1"].append(float(row["s1"]))
            cols["s2"].append(float(row["s2"]) if row["s2"] else np.nan)
            cols["cur"].append(float(row["current"]))
            cols["lost_at"].append(float(row["lost_at"]))
            cols["f1"].append(float(row.get("f1") or -1.0))
            cols["g1"].append(float(row.get("g1") or -1.0))
            cols["g2"].append(float(row["g2"]) if row.get("g2") else np.nan)
            cols["u1"].append(float(row["u1"]) if row.get("u1") else np.nan)
            cols["u2"].append(float(row["u2"]) if row.get("u2") else np.nan)
    return {k: np.array(v) for k, v in cols.items()}


def p_one(spare, p):
    p_max, s0, w = p
    out = p_max / (1.0 + np.exp(np.clip(-(spare - s0) / w, -50.0, 50.0)))
    return np.where(np.isnan(spare), 0.0, out)


def lost_prob(d, p):
    return 1.0 - (1.0 - p_one(d["s1"], p)) * (1.0 - p_one(d["s2"], p))


def loglik(q, lost):
    q = np.clip(q, 1e-9, 1.0 - 1e-9)
    return np.where(lost == 1, np.log(q), np.log(1.0 - q)).sum()


def fit(d, mask):
    sub = {k: v[mask] for k, v in d.items()}

    def nll(x):
        return -loglik(lost_prob(sub, x), sub["lost"])

    best = None
    for start in ([0.9, 0.0, 0.2], [0.7, 0.3, 0.1], [1.0, -0.3, 0.5]):
        r = minimize(nll, start, method="L-BFGS-B",
                     bounds=[(0.01, 1.0), (-3.0, 3.0), (0.01, 3.0)])
        if best is None or r.fun < best.fun:
            best = r
    return tuple(best.x)


def fit_scale(cur, lost):
    """The current strip odds' strips rescaled to their best level."""
    best = (np.inf, 1.0)
    for k in np.geomspace(0.05, 20.0, 120):
        v = -loglik(1.0 - np.exp(-k * cur), lost)
        if v < best[0]:
            best = (v, k)
    return best[1]


def auc(q, lost):
    pos = q[lost == 1]
    neg = q[lost == 0]
    if pos.size == 0 or neg.size == 0:
        return float("nan")
    order = np.argsort(np.concatenate([pos, neg]), kind="mergesort")
    ranks = np.empty(order.size)
    ranks[order] = np.arange(1, order.size + 1)
    allv = np.concatenate([pos, neg])
    # Average ranks over ties.
    for v in np.unique(allv):
        tie = allv == v
        if tie.sum() > 1:
            ranks[tie] = ranks[tie].mean()
    return (ranks[:pos.size].sum() - pos.size * (pos.size + 1) / 2.0) / (pos.size * neg.size)


def report(d, p, k, label):
    q = lost_prob(d, p)
    qc = 1.0 - np.exp(-d["cur"])
    qk = 1.0 - np.exp(-k * d["cur"])
    n = len(d["lost"])
    print("\n%s: %d runs, %d lost (%.0f%%)" % (label, n, d["lost"].sum(), 100.0 * d["lost"].mean()))
    print("  log likelihood per run: one chance %.4f, current %.4f, current x %.2f %.4f, constant %.4f"
          % (loglik(q, d["lost"]) / n, loglik(qc, d["lost"]) / n, k, loglik(qk, d["lost"]) / n,
             loglik(np.full(n, d["lost"].mean()), d["lost"]) / n))
    print("  expected lost: one chance %.1f, current %.1f, current x %.2f %.1f"
          % (q.sum(), qc.sum(), k, qk.sum()))
    print("  AUC: one chance %.3f, current %.3f" % (auc(q, d["lost"]), auc(qc, d["lost"])))
    print("  by family (lost / one chance / current):")
    for fam in sorted(set(d["family"])):
        sel = d["family"] == fam
        print("    %-14s %4d of %4d / %6.1f / %6.1f" % (fam, d["lost"][sel].sum(), sel.sum(),
                                                       q[sel].sum(), qc[sel].sum()))
    single = np.isnan(d["s2"])
    print("  one defender, share lost by his best spare time:")
    edges = [-99, -2.0, -1.0, -0.5, -0.25, 0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 99]
    for a, b in zip(edges[:-1], edges[1:]):
        sel = single & (d["s1"] >= a) & (d["s1"] < b)
        if sel.sum() == 0:
            continue
        print("    %6.2f to %6.2f s: %3d of %4d = %.2f   (fit %.2f)" % (
            a, b, d["lost"][sel].sum(), sel.sum(), d["lost"][sel].mean(), q[sel].mean()))


def first_chance_report(d):
    """One defender: the share lost by when he first reaches the planned path with
    no time to spare (f) and with a quarter second (g), and how long after it the
    loss came."""
    single = np.isnan(d["s2"])
    for key, label in (("f1", "no time to spare"), ("g1", "0.25 s to spare")):
        print("  one defender, share lost by his first chance (%s):" % label)
        never = single & (d[key] < 0.0)
        print("    never    : %3d of %4d = %.2f" % (d["lost"][never].sum(), never.sum(),
                                                   d["lost"][never].mean() if never.sum() else 0.0))
        for a in np.arange(0.0, 3.0, 0.5):
            sel = single & (d[key] >= a + 1e-6) & (d[key] < a + 0.5 + 1e-6)
            if sel.sum() == 0:
                continue
            lost = sel & (d["lost"] == 1)
            lag = (d["lost_at"][lost] - d[key][lost]).mean() if lost.sum() else float("nan")
            print("    %.1f-%.1f s: %3d of %4d = %.2f   lost %.2f s after it on average" % (
                a, a + 0.5, d["lost"][sel].sum(), sel.sum(), d["lost"][sel].mean(), lag))


def key_chance(x, p, never=None):
    """A defender's chance falling off with `x`: p_max / (1 + exp((x - x0) / w)),
    none where `never` (no first chance) or no defender."""
    p_max, x0, w = p
    out = p_max / (1.0 + np.exp(np.clip((x - x0) / w, -50.0, 50.0)))
    out = np.where(np.isnan(x), 0.0, out)
    if never is not None:
        out = np.where(never, 0.0, out)
    return out


def key_lost(d, key, p):
    if key == "time":
        a = key_chance(d["g1"], p, d["g1"] < 0.0)
        b = key_chance(d["g2"], p, ~(d["g2"] >= 0.0))
    elif key == "share":
        a = key_chance(d["u1"], p)
        b = key_chance(d["u2"], p)
    else:  # flat: p_max whenever he has a first chance
        a = np.where(d["g1"] >= 0.0, p[0], 0.0)
        b = np.where(d["g2"] >= 0.0, p[0], 0.0)
    return 1.0 - (1.0 - a) * (1.0 - b)


def fit_key(d, key, mask):
    sub = {k: v[mask] for k, v in d.items()}

    def nll(x):
        return -loglik(key_lost(sub, key, x), sub["lost"])

    starts = {"time": ([0.9, 1.0, 0.3], [0.9, 2.0, 0.5], [0.7, 0.5, 0.1]),
              "share": ([0.9, 0.5, 0.1], [0.9, 0.8, 0.2], [0.7, 0.3, 0.05]),
              "flat": ([0.8, 0.0, 1.0],)}[key]
    bounds = {"time": [(0.01, 1.0), (-1.0, 5.0), (0.01, 3.0)],
              "share": [(0.01, 1.0), (-0.5, 2.0), (0.005, 2.0)],
              "flat": [(0.01, 1.0), (0.0, 0.0), (1.0, 1.0)]}[key]
    best = None
    for start in starts:
        r = minimize(nll, start, method="L-BFGS-B", bounds=bounds)
        if best is None or r.fun < best.fun:
            best = r
    return tuple(best.x)


def keys_report(d):
    n = len(d["lost"])
    print("%d runs, %d lost (%.0f%%)" % (n, d["lost"].sum(), 100.0 * d["lost"].mean()))
    halves = [d["run"] % 2 == 0, d["run"] % 2 == 1]
    ll = {"time": 0.0, "share": 0.0, "flat": 0.0, "strip read": 0.0}
    print("held out (fit on one half, scored on the other), log likelihood per run:")
    for fit_mask, test_mask in ((halves[0], halves[1]), (halves[1], halves[0])):
        sub = {k: v[test_mask] for k, v in d.items()}
        for key in ("time", "share", "flat"):
            p = fit_key(d, key, fit_mask)
            ll[key] += loglik(key_lost(sub, key, p), sub["lost"])
        ll["strip read"] += loglik(1.0 - np.exp(-sub["cur"]), sub["lost"])
    for name, v in ll.items():
        print("  %-11s %.4f" % (name, v / n))
    everything = np.ones_like(d["lost"], bool)
    fits = {key: fit_key(d, key, everything) for key in ("time", "share", "flat")}
    print("fitted on all:")
    print("  time : p_max %.2f, falls to half at a first chance %.2f s in, over %.2f s" % fits["time"])
    print("  share: p_max %.2f, falls to half at %.2f of his range, over %.2f" % fits["share"])
    print("  flat : p_max %.2f" % fits["flat"][0])
    q_cur = 1.0 - np.exp(-d["cur"])
    print("AUC: time %.3f, share %.3f, flat %.3f, strip read %.3f" % (
        auc(key_lost(d, "time", fits["time"]), d["lost"]),
        auc(key_lost(d, "share", fits["share"]), d["lost"]),
        auc(key_lost(d, "flat", fits["flat"]), d["lost"]), auc(q_cur, d["lost"])))
    print("expected lost: time %.1f, share %.1f, flat %.1f, strip read %.1f" % (
        key_lost(d, "time", fits["time"]).sum(), key_lost(d, "share", fits["share"]).sum(),
        key_lost(d, "flat", fits["flat"]).sum(), q_cur.sum()))
    single = np.isnan(d["s2"])
    print("one defender, share lost by his first chance (fit: time):")
    never = single & (d["g1"] < 0.0)
    print("    never    : %3d of %4d = %.2f" % (d["lost"][never].sum(), never.sum(),
                                               d["lost"][never].mean() if never.sum() else 0.0))
    for a in np.arange(0.0, 3.0, 0.25):
        sel = single & (d["g1"] >= a + 1e-6) & (d["g1"] < a + 0.25 + 1e-6)
        if sel.sum():
            print("    %.2f-%.2f s: %3d of %4d = %.2f   (fit %.2f)" % (
                a, a + 0.25, d["lost"][sel].sum(), sel.sum(), d["lost"][sel].mean(),
                key_chance(np.array([a + 0.125]), fits["time"])[0]))
    print("one defender, share lost by the least share of his range that reaches the path (fit: share):")
    for a, b in zip([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.25],
                    [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.25, 99.0]):
        sel = single & (d["u1"] >= a) & (d["u1"] < b)
        if sel.sum():
            print("    %.2f-%.2f: %3d of %4d = %.2f   (fit %.2f)" % (
                a, min(b, 9.99), d["lost"][sel].sum(), sel.sum(), d["lost"][sel].mean(),
                key_chance(np.array([(a + min(b, 2.0)) / 2]), fits["share"])[0]))


def main():
    args = [a for a in sys.argv[1:]]
    fit_from = None
    if "--fit-from" in args:
        i = args.index("--fit-from")
        fit_from = args[i + 1]
        del args[i:i + 2]
    keys = "--keys" in args
    if keys:
        args.remove("--keys")
    d = load(args[0] if args else ".preview/strip_interception/runs.csv")
    if keys:
        keys_report(d)
        return
    if fit_from:
        src = load(fit_from)
        everything = np.ones_like(src["lost"], bool)
        p = fit(src, everything)
        k = fit_scale(src["cur"], src["lost"])
        print("fitted on %s: p_max %.2f, s0 %.2f s, w %.2f s; current rescaled x %.2f" % (
            fit_from, p[0], p[1], p[2], k))
        report(d, p, k, "scored, nothing refitted")
        return
    n = len(d["lost"])
    halves = [d["run"] % 2 == 0, d["run"] % 2 == 1]
    ll = {"one chance": 0.0, "current": 0.0, "current rescaled": 0.0, "constant": 0.0}
    print("held out (fit on one half of the runs, scored on the other), log likelihood per run:")
    for fit_mask, test_mask in ((halves[0], halves[1]), (halves[1], halves[0])):
        p = fit(d, fit_mask)
        k = fit_scale(d["cur"][fit_mask], d["lost"][fit_mask])
        print("  fit on a half: p_max %.2f, s0 %.2f s, w %.2f s; current x %.2f" % (p + (k,)))
        lost = d["lost"][test_mask]
        sub = {kk: v[test_mask] for kk, v in d.items()}
        ll["one chance"] += loglik(lost_prob(sub, p), lost)
        ll["current"] += loglik(1.0 - np.exp(-sub["cur"]), lost)
        ll["current rescaled"] += loglik(1.0 - np.exp(-k * sub["cur"]), lost)
        ll["constant"] += loglik(np.full(lost.size, d["lost"][fit_mask].mean()), lost)
    for name, v in ll.items():
        print("  %-17s %.4f" % (name, v / n))
    everything = np.ones_like(d["lost"], bool)
    p = fit(d, everything)
    k = fit_scale(d["cur"], d["lost"])
    print("\nfitted on all: p_max %.2f, s0 %.2f s, w %.2f s" % p)
    report(d, p, k, "fitted on all")
    first_chance_report(d)


if __name__ == "__main__":
    main()
