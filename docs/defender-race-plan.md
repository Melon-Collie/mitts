# Defender race — one model of whether a defender gets to the puck

Status: **agreed design (in chat); not built.** The CLAUDE.md workflow applies:
this doc is the plan, deviations get discussed first.

## Why

Every read that asks "does the carrier keep the puck" asks the same question:
**if the puck is at P at time T, does a defender get his stick on it first?**
Today that question is answered several ways, each with its own guess at what
the defender will choose to do:

| Read | What it assumes the defender does |
|---|---|
| `AICarrySpace.reach_clearance` / `carry_safety` | coasts, then lunges in a fixed window at the end (`CARRY_LUNGE_WINDOW_S`); a man skating with the carry may brake instead (`_stopped_clearance`); a chaser commits the whole way (`_chases`) |
| `AIPossessionValue._line_keep` | past the line, shadows the carrier's current course at his own depth; a crossing picked late is "the lunge's to cover" |
| `AIDefenderProjection` | ahead: holds his gap down to the top of the house; behind: backchecks; forechecker exception in our zone |
| `AIPossessionValue._skate_keep` / `_drive_keep` | the projected defence above, then the lunge model, over a fixed drive length |
| `AILaneReach.block` (passes) | momentum through the read, then the arrival clock; graded by the clock's error over his trip |
| `AILoosePuckChase.reach_meet_time` | the arrival clock to the reach band |

The carrier compares the outputs as if they were one currency. They are not, and
the disagreements show up as behaviour: against a square defender at the line,
`_line_keep` reads the lane the carrier is cutting toward as open to a late
choice on every re-plan while the real defender mirrors him
(`test_nz_carry_keeps_pace`, gap 10 m). The keep band added in bfd851ff /
0530a7d2 patches the cliffs these reads have in time; it does not make them
agree.

The pass-lane and loose-puck reads already answer the question as a race on the
arrival clock. This plan puts every keep read on that race.

## Prior work

The model is Spearman's pitch control (MIT Sloan 2017, Liverpool FC): a
player's time to intercept is his current course for a reaction time (0.7 s),
then a straight run at top speed; the gap between his time and the ball's goes
through a logistic with a constant σ ≈ 0.45 s; all opponents are combined
probabilistically. "Pass Evaluation in Women's Olympic Hockey" (2022) carries it
to the rink with a puck model and per-player motion. Neither grows the
uncertainty with how far ahead the read looks; Spearman prices ~1 s passes. Our
reads plan 2–4 s ahead, where what the defender chooses matters more, so the
uncertainty here grows with T.

## The model

For defender *i*, a point *P* the puck is at, at time *T* from now:

1. **His time.** `t_i(P)`: the time for his stick to get to P. He carries on as
   he is for a reaction time `t_react`, then the shared calibrated arrival clock
   (`AIArrival.time_to_arrive_caps`) to within his reach of P
   (`AILaneReach.defender_reach`). The same function `AILaneReach._block_at` uses
   today, on his own build.
2. **The odds he doesn't get it.** `keep_i = grade((t_i(P) − T) / s(T))` with
   `s(T) = σ₀ + k·T`. σ₀ is the near-certain part (the clock's own error, the
   contact); `k·T` is that we don't know what he will choose: the further out the
   collision, the more he can do something else, and the more room the carrier
   has. Closer, the read is surer.
3. **A path.** Along a carry, each defender's odds are his best point on it (the
   lowest keep over the samples, each at its own T).
4. **Several defenders.** Keep = the product of each one's keep (Spearman's
   probabilistic combine), not the worst one alone.

There is no defender intent in it: no lunge window, no shadow, no gap-holding,
no backcheck target, no projected defence. A read that starts later (a follow-up
`t` from now, a second ply, a reception) is the same race with T counted from
now, from the defender's state now: the uncertainty of the wait is in `s(T)`.

**The deke tradeoff, accepted.** In a pure race a defender close to the carrier
covers every lane; a cut beats him only by what his reaction gives up. The deke
evaluator (`AICarrySpace`) still prices beating a man one on one. Revisit if
play shows it.

## What it retires

- `reach_clearance`'s commit window (`maneuver_time`, `CARRY_LUNGE_WINDOW_S` in
  keep reads), `_stopped_clearance`, `_chases`, the escape-speed gate — all
  defender-intent guesses.
- `reach_band_m` and the `band_m` argument on the safety maps (it becomes
  `s(T)`), and `projected_s`.
- Probably the dwell / transit safety maps as separate curves: σ₀ per regime if
  the calibration shows a standing puck is stripped more surely than a passing
  one, else one curve.
- `_line_keep`'s shadow and natural crossing; `_skate_keep`'s `DRIVE_MAX_M`
  horizon as a defence rule.
- `AIDefenderProjection` and `AIPossessionValue._project` in keep reads, and
  `AICarrierField.project_opponents` where it feeds a keep read (ply 2,
  `_end_worth`, the wheel, `receiver_drive_in_value`, the feed's catch).

## What it does not touch

- **Who plays the puck.** `AIDefencePairing` (a defender riding his man is not
  in the carrier's race) stays as it is.
- **Where the defence stands later for the shot model.** A shot priced after an
  entry still needs defender positions for blockers and screens. Positions are
  not part of the race; this stays on `AIDefenderProjection` for now and gets its
  own pass.
- The arrival clock, the shot odds and the keeper, which are calibrated on their
  own.

## Calibration — measure first

The model is grounded by fitting it to our real defending bots, as the shot
model is held to the live keeper (`tests/unit/ai/data/shot_odds_truth.txt`).

- **Instrument** `tests/instruments/ai/test_defender_race_truth.gd` on the duel
  harness. The carrier skates a scripted puck path; the defender is the real bot.
  This needs a scripted-carrier mode in `duel_harness.gd`.
- **Stagings.** Defender ahead, beside, behind, 1–20 m off; standing, closing,
  backing off, mirroring, chasing. Carries straight, cut at several angles and
  speeds, and stopped. Passes from release to reception. Each staging jittered
  (±0.5 m, ±10% speed) and repeated.
- **Outcome.** Did the defender get his stick to the puck before the path's
  end, and where and when.
- **Fit.** `t_react`, σ₀, k against the outcomes, by the model's margin at its
  binding point. The fit tests the model's shape too: a residual that trends
  with T means `s(T)` linear in T is wrong, one by staging family means the race
  is missing something. Fit the grade's shape the same way: linear ramp (finite
  support, what `AILaneReach` uses, keeps the prescreens exact) against
  logistic; take the ramp unless the logistic fits clearly better. A
  two-defender set decides product against worst-one.
- **Truth file and gate.** The instrument writes a data file; a default-tier
  test scores the model against it in milliseconds with an error bound as a
  ratchet, as `test_shot_odds_vs_truth.gd` does. The file is regenerated when
  the defender bots change, never hand-edited.

## Steps

1. **Scripted-carrier mode and the instrument.** Measure today's reads against
   the outcomes too, as the baseline.
2. **`AIDefenderRace`** (`Scripts/domain/ai/defender_race.gd`, a leaf beside
   `AIArrival`): `stick_time(pos, vel, caps, point)`, `keep(t_stick, T)`,
   `path_keep(...)`, the defenders' product. Unit properties: keep never falls as
   T shrinks with the defender fixed; a defender with his stick on P at T = 0
   takes it; one out of reach of every point costs nothing; product order-free.
   `AILaneReach._block_at` grades on it, so passes and carries share one curve.
3. **Fit** `t_react`, σ₀, k; truth file and gate.
4. **Swap the reads**, one family per commit, the default tier, the entry and
   breakout drills and `test_entry_read_stability.gd` after each:
   `AICarrySpace` core (`reach_clearance`, `carry_safety`, `carry_crossing_keep`,
   `carry_strip_point`) → the carrier's searches (`_rolled_safety`, stand,
   candidates, `_end_worth`, the wheel) → `AIPossessionValue` (`_line_keep`,
   `_skate_keep`, `_drive_keep`) → reception and holds (`catch_clear`,
   `_dwell_keep`, `mid_clear`, protect and seam reads in `carrier.gd`,
   `support.gd`). Benchmarks before and after: a clock read per point per
   defender replaces a closed-form clearance.
5. **Retire** what the swap leaves unread (list above).
6. **Test audit.** Every pinned behaviour rerun over jittered setups; one that
   holds ~90%+ is pinned, a near tie is not pinned as a pick. Each tagged with
   the doctrine line it encodes; the ones that tie to none go to the user.
   Snapshots re-pinned after it, not before.

## Open questions

- Grade shape and the defenders' combine: decided by the fit.
- Dwell against transit: one curve or σ₀ per regime, decided by the fit.
- Bots, not humans: the fit is against our defending bots. A human defender
  will differ; whether `s(T)` should widen for them is a later question.
- Shot-model defender positions at follow-up times: a second pass.
