# Possession value — the shot pays for the puck it spends

Status: **Phase A landed** (measurement, no behavior change; §6). Bar form agreed;
the four design decisions are settled in §10.

**Scope.** The in-zone carrier's decision whether a shot is worth releasing
(`AIRoleCarrier._pick_commit_phase`). Both 3v3 and 5v5. Passes, the dump, carry
routing and reception one-timers are out of scope and must not change (§5).

### Decisions banked

- **Bar form.** Possession value enters as the bar a shot must clear to qualify for
  the fire compete. It replaces the fixed `SHOT_MIN_VALUE`. It is **never** added to
  carry candidates, so it decides *whether* to fire and never *where* to carry (§4).
- **Only the shot pays it.** A completed pass keeps possession and a failed one is
  already priced by its lane, so passes keep `PASS_MIN_VALUE` unchanged. The dump
  stays a residual with no bar.
- **Measured, not shaped.** The two numbers the model cannot read off the ice, the
  look rate and post-shot retention, are measured from play. They are not picked.
  #577 sets the same standard for the rebound term.

---

## 1. Symptom

Bots are not patient on offense. With support set and nobody on them, they release
the first look that clears a fixed bar, rather than working the puck for a better
one.

The mirror symptom comes from the same constant and is recorded in
`docs/AUDIT_2026-08_SKATER_REALISM.md` §7 (F6). A clean point shot (~0.02–0.03 xG)
never clears the bar, even with a net-front man there to win the rebound. So the
offensive zone has no shot-volume game, and the D's walk-the-line objective
optimizes for a shot the carrier will never take.

The bar is too loose where the puck is safe and too strict where a lost shot is
cheap. **One fixed number cannot be right in both places, because it does not depend
on either.**

## 2. Root cause

The fire-vs-carry compete in `_pick_commit_phase` has three properties that
together price "release now" too cheaply.

1. **Fire wins ties, and stand-still cannot beat the shot.** Stand-still is
   `shoot_now × safety − cost ≤ shoot_now` (`_best_carry`), so the carrier keeps the
   puck only when a candidate within one planning beat reaches a *strictly* better
   look.
2. **The compete is one-ply.** A carry is worth the shot at its end point. A
   possession is a *sequence* of looks: cycle, re-enter the slot, wait for the
   weak-side man. No candidate represents the second look onward.
   `_best_developing_feed` is the only multi-beat read, and it covers just the
   FINISHER and the breakout outlets.
3. **The shot is the only leg that does not pay for losing the puck.** Carries and
   passes subtract `_turnover_cost` (and `_counter_exposure_cost` in 5v5). The shoot
   leg is raw `score_shoot_value`. The only stand-in for what a release forfeits is
   `SHOT_MIN_VALUE = 0.05`, and its own comment calls it "what a possession is
   worth". It is a constant.

## 3. The model

### 3.1 The comparison

Firing ends the possession unless the puck comes back. Holding keeps it. Let:

- `xG`: the shot's value through the seam (`score_shoot_value`, unchanged).
- `V`: what keeping the puck in the zone is worth from here, in goals (§3.2).
- `P_lose`: the probability we do not regain the puck after a shot that does not
  score (§3.3).
- `C`: the opponent's value at the point where they collect it. This is the same
  `turnover_cost` currency every other leg pays (§3.4).

A goal also ends the possession, which is why `V` is not added on the scoring branch.

```
fire = xG + (1 − xG) · [ (1 − P_lose) · V  −  P_lose · C ]
hold = V
```

`fire ≥ hold` solves to the bar:

```
bar = P_lose · (V + C)  /  (1 − (1 − P_lose) · V + P_lose · C)
```

For small `V` and `C` this is ≈ `P_lose · (V + C)`. It also behaves correctly at the
two extremes:

- **`P_lose → 0`** (we always get it back): the bar goes to 0. A shot costs nothing,
  so any look is worth taking. This is the point-shot-with-traffic case F6 asks for.
- **`V → 0`** (the puck is about to be stripped anyway): the bar goes to
  `P_lose · C`. This is just the honest turnover price, the same one the carry pays.

The bar replaces `SHOT_MIN_VALUE` at the one site that reads it
(`_settle_handicap(best_shot_score, settle_penalty) > SHOT_MIN_VALUE`). Settle doubt
still raises it exactly as it raises today's constant.

### 3.2 `V`: the possession's continuation value

`V` must not be "the best option I have right now". Those options already compete
against fire directly, so a bar built from them only restates the compete. What the
one-ply compete cannot see is that a possession produces looks **repeatedly**, until
it is lost. Model that as a constant-hazard process, the same form `delay_discount`
already uses:

```
V = r · ∫ exp(−(h + 1/τ) · t) dt  =  r / (h + 1/τ)
```

- **`r`: the rate at which a sustained in-zone possession produces value, in xG per
  second.** This is the one number that cannot be read off the ice. It is
  **measured** (§6), and it stands in the same relation to `V` as `XG_SLOT_REF`
  stands to `position_potential`.
- **`h`: the hazard of losing the puck, per second.** It is read from what the
  carrier already perceives. The possession is lost only if **every** way of keeping
  it fails, so `h` reads the carrier's **best retention option**, not where he stands:
  the higher of `current_safety` (`_phase_current_safety`, the best-clearance seam
  over `AICarrySpace.EVADE_HORIZON_S`) and the safety of the best route the carry
  search already scored, with the retreat ring included. A charger I can dance out of
  does not count as danger, and neither does a container I can peel away from. Under
  constant hazard, `h = −ln(safety) / EVADE_HORIZON_S`.
- **`τ = READ_VALIDITY_TAU_S`**: the existing read-validity discount, so `V` is
  bounded by `r · τ` even when `h → 0`. No new patience dial is introduced, and τ
  stays the one place "how much do I trust the future" is set.

Worked numbers at τ = 4.5 s (1/τ = 0.22):

| safety | h (1/s) | V / r (s) |
|---|---|---|
| 0.95 | 0.13 | 2.9 |
| 0.80 | 0.56 | 1.3 |
| 0.50 | 1.73 | 0.51 |
| 0.20 | 4.0 | 0.24 |

A safe carrier's possession is worth about 12× a nearly stripped one's. That is the
behavior the symptom asks for: work it when you can keep it, release when you can't.

**Implied calibration, as a sanity check rather than a target.** Today's bar is 0.05.
If `P_lose ≈ 0.7` (assumed here, not measured) and `C ≈ 0`, that implies `V ≈ 0.07`.
At safety 0.95 that gives `r ≈ 0.024 xG/s`. If the measured `r` is wildly different,
either the constant was far off or the model is. §6's gate exists to find out which.

**Later refinement, out of scope for the first pass:** a state-dependent `r` that
rises when teammates hold dangerous spots. It would come from the per-teammate spot
values `_candidate_pass_option` already caches, normalized against the measured mean.
It is deferred because it needs a reference mean that only exists once Phase A has
run.

### 3.3 `P_lose`: what happens after a shot that does not score

Three outcomes, each with its own retention:

- **Whistle** (glove catch, smother, puck out of play): an offensive-zone faceoff. We
  keep the puck with the faceoff win rate.
- **Live puck near the net** (pad, stick or blocker rebound, block): a race to where
  it lands, our nearest body against theirs.
- **Wide or high miss** (rims around the boards): a race along the rim.

**Phase B** uses the measured aggregate, one number per team size, from §6.
**Phase C** makes it per-shot. The live-puck share becomes a race between our net
front and theirs, reusing the chase election's arrival machinery
(`time_to_arrive` / `chase_recovery`). The outcome mix by save surface is taken from
the measured destinations in `tests/unit/ai/test_goalie_rebound_destination.gd`. That
is the step that makes "a net-front man makes the point shot affordable" emerge
rather than be asserted.

**Not this plan:** the *value* of a rebound put-back. That is #577's second-chance
term, which raises `xG`. This plan prices *retention*, which lowers the bar. The two
compose, and #577's rule applies to both: fit from logged shots, never re-derive from
geometry.

### 3.4 `C`: the opponent's value at the collection point

This is `AIActionScoring.turnover_cost` at the expected collection point (near their
goal line for a save, along the rim for a miss), in the in-zone xG unit the carrier
already selects via `in_offensive_zone`. It is small in practice, because a puck
collected at their own goal line is far from our net. It is included so the shot leg
pays in the same currency as the carry and pass legs ("one currency across the
carrier's compete"). If Phase A shows it is negligible everywhere, it may be dropped
with the measurement cited.

## 4. Why a bar, and not value on both sides

The symmetric alternative adds `(1 − P_lose)(1 − xG) · V` to the shot and `V` to every
carry candidate. On paper it is the same decision. In practice, carry candidates that
carry `V` are ranked against each other by it, and `V` is largest where safety is
highest. Safety is highest on the perimeter.

That is the failure the retired `OZ_POSSESSION_VALUE` floor produced: the carrier
orbited the perimeter, because the possession term rewarded safe ice over dangerous
ice. As a bar, `V` only ever appears on the fire side of one comparison, so carry
routing stays purely xG-driven, exactly as it is today.

## 5. Interactions — what must NOT change

| Site | Effect |
|---|---|
| `PASS_MIN_VALUE`, pass scoring | none |
| Dump residual (`retention_hopeless`) | none: it reads `raw_carry_score` and `fire_score > -INF`; the dump still runs only when no release qualifies |
| Carry routing, `_best_carry` | none: `V` never enters a candidate |
| Developing-feed hold | none: still competes against fire directly |
| Settle doubt | applied to the shot against the new bar, exactly as today |
| Ping-shoot (`PING_SHOOT_EV_MULT`) | none: still scales `shoot_score` before the bar test |
| Fire hysteresis | none |
| Reception one-timers | none: they do not pass through this bar |
| Shoot-for-tip | qualifies against the same bar; Phase C's lower `P_lose` with a man on the shot line helps it, which is correct |
| Difficulty tiers | Every tier runs the same model; tiers differ only through their existing knobs (§10, decision 3) |

The `SHOT_MIN_VALUE` comment states a second job: stopping a **contained** carrier
from trading the puck for a point shot. Read off where he stands, a contained carrier
has low safety, so high `h`, small `V` and a *looser* bar: the wrong direction. That
is why `h` reads the best retention option (§3.2). A contained carrier with the
retreat ring open still keeps the puck by peeling out, so his `V` stays high and the
point shot stays barred. §8 pins this with fixture 3. If it still fails, there is no
fallback floor: that is a missing perception, and it comes back as a finding (§10,
decision 2).

## 6. Measurement — Phase A, no behavior change

Status: **landed.** Two quantities (`r` and `P_lose`) and a before/after scorecard,
from two sources, because no single one can measure both.

### `r` — bot sims

**The instrument:** `AIOzPossessionTracker` (`Scripts/domain/ai/`), a tally modelled
on `AIBreakoutEpisodeTracker`. Nothing reads it back into a decision.

- **An episode** is one stretch of *controlled* zone possession. It starts when our
  carrier has the puck established in the zone (2 m past the blue line). Loose time
  inside it (a pass in flight, a bobble) still counts.
- **It ends on:** our shot, an opponent carrying it in the zone, the puck leaving
  the zone, or a stoppage. **It ends at the shot** whatever happens after, so
  `r = Σ xG / Σ episode seconds` measures the rate of xG per second of holding the
  puck. It does not depend on how often the puck comes back, which is `P_lose`'s
  job.
- **It records:** seconds, each shot's xG, and shots from beyond the tops of the
  circles split by whether a teammate stood in the net-front box
  (`AIZoneCoverage`'s box).

**The harness:** `benchmarks/test_oz_possession_harness.gd`, on the duel harness
(real decisions, real movement), for 3v3 and 5v5 at Hard and Normal. Three staged
attacks per size (zone entry, low cycle, point or high slot), 12 jitters × 2
mirrors, one episode per trial, 15 s limit. Shot xG is the shooter's own seam value
at release, the currency the bar will be compared in.

**What the sims cannot give is `P_lose`.** The duel harness has no net and no
keeper behavior: a released shot slides on to the end boards. The two real-goalie
harnesses stop at the first contact or fire one shot per run. None models a save
followed by the next possession, so any retention number from them would be an
artifact.

### `P_lose` — logged play

`shot_events.next_control` (`'ours' | 'theirs' | 'whistle'`, null for a goal or an
unresolved shot) is resolved host-side by `ShotOnGoalTracker`. The answer is
whichever comes first: the next ESTABLISHED possession (`PossessionTracker`, so a
touch is not control), a later shot by either team (a put-back never establishes
first), or a stoppage. It is a stored-row column only. Clients never post shot rows,
so it stays off the wire and `PROTOCOL_VERSION` is unchanged. Migration
`20261012000100_shot_events_next_control.sql`. #577 is waiting on the same data.

`P_lose` per shot is then `theirs` plus the lost share of `whistle`. That share is
the faceoff loss rate, a separate draw this column does not record.

### Baseline (2026-10-12)

| row | episodes | ends: shot / turnover / exit | mean episode | shots | `r` (xG/s) | xG/shot | long-range shots (net-front / clear) |
|---|---|---|---|---|---|---|---|
| 3v3 Hard | 69 | 16 / 37 / 16 | 1.6 s | 16 | 0.042 | 0.29 | 0 / 1 |
| 3v3 Normal | 71 | 22 / 38 / 11 | 1.7 s | 22 | 0.055 | 0.31 | 1 / 1 |
| 5v5 Hard | 72 | 21 / 38 / 13 | 1.4 s | 21 | 0.028 | 0.14 | 1 / 4 |
| 5v5 Normal | 72 | 34 / 30 / 8 | 1.7 s | 34 | 0.042 | 0.15 | 1 / 7 |

How to read it:

- **Against the gate.** The measured `r` is 0.028–0.055, against the 0.024 that
  today's `SHOT_MIN_VALUE` implies (§3.2, at safety 0.95). That is the same order of
  magnitude, 1.2–2.3× higher. A higher `r` means a higher bar, so the measurement
  points the same way as the symptom: today's bar is somewhat too loose. It is not a
  disagreement large enough to question the model.
- **Noise.** 16–34 shots per row. `r` varies 0.005–0.12 across scenarios, and the
  zone-entry rush dominates it (xG/shot 0.3 in 3v3). The rows are a ballpark, not a
  fit. Phase B should not take a second significant figure from them.
- **Harness bias, both ways.** Episodes are short (1.4–1.7 s) and half end in a
  turnover. The duel harness has no body contact and a fixed release pace, so its
  possessions die faster than real ones. That inflates `h`, which does not enter `r`
  directly, but it also cuts short the slow cycles that produce low-xG looks. The
  static keeper never moves, which may flatter xG/shot.
- **The point shot barely exists.** 5–8 long-range shots per 5v5 row, almost none
  with a net-front man. That is F6's symptom, measured.

**The scorecard**, re-run after each phase: the harness rows above, plus from logged
play once `next_control` has accumulated: retention after shots, and shots with and
without a net-front man. Goals per OZ possession needs real goals, so it is a
playtest and logged-play number. In the sims, xG per episode stands in for it.

**Gate before Phase B:** passed for `r` (see above). `P_lose` has no measurement
until logged games accumulate. Phase B either waits for it or starts from a stated
prior; that is a decision for the user (§10).

## 7. Phases

| Phase | Content | Behavior change |
|---|---|---|
| **A** *(landed)* | Tracker + harness scenarios + baseline scorecard. `next_control` migration and logging. | none |
| **B** | `AIPossessionValue` (pure, static, engine-free). `h` from the best retention option, `r` per team size from the sims, `P_lose` from logged play (or a stated prior until it accumulates), `C` from `turnover_cost`. Replaces `SHOT_MIN_VALUE` at the one call site. | yes; **playtested on its own** |
| **C** | Per-shot `P_lose`: net-front race + outcome mix by save surface. | yes; separate playtest |
| **D** *(optional)* | State-dependent `r` from cached teammate spot values. | yes |

### Where the code goes

- **New file `Scripts/domain/ai/possession_value.gd`** (`class_name AIPossessionValue`):
  `hazard_from_safety`, `continuation_value`, `shot_bar`, and later `retention_prob`.
  It reads `AIActionScoring` (for `delay_discount`'s τ and `turnover_cost`) and is
  never read by it, the same direction `AICarrySpace` keeps. Add it to
  `test_scoring_split_stays_acyclic.gd`'s coverage.
- **`action_scoring.gd` does not grow.** It is grandfathered at 4458 in
  `test_no_god_class_growth.gd`.
- **`carrier.gd`** is grandfathered at 3916 and sits at 3914. The call-site change is
  a few lines; moving the `SHOT_MIN_VALUE` block's explanation into the new file and
  `Scripts/domain/ai/CLAUDE.md` should make it net-negative. If it doesn't, bump the
  entry deliberately and say why in the commit.
- **Measured constants** live in `AIPossessionValue` with their provenance (harness
  name, run, sample size), to the standard `AIShotValue.DISPLACEMENT_LOGIT_PER_M`
  sets.
- **Hot-path cost:** Phase B is a `log`, a few multiplies and one `turnover_cost` per
  pick, all allocation-free. Phase C adds a race per pick and **runs the benchmarks**
  before/after per the AI perf rule.

### Documentation updated when it lands

- `Scripts/domain/ai/CLAUDE.md` → "One currency across the carrier's compete": the
  giveaway-bars paragraph, and the dump bullet's mention of `SHOT_MIN_VALUE`.
- `AUDIT_2026-08_SKATER_REALISM.md` F6: link this plan as the bar half of the fix,
  and #577 as the rebound half.
- `tests/unit/rules/test_role_carrier.gd` comments at lines 1137, 1354 and 2602, which
  cite the constant.

## 8. Tests

**Unit (`AIPossessionValue`):**

- `shot_bar` matches the closed form in §3.1 and reduces to `P_lose · (V + C)` for
  small inputs.
- The bar is monotone increasing in `V`, `P_lose` and `C`.
- `V` is monotone increasing in safety, and bounded by `r · τ` as safety → 1.
- `P_lose = 0` gives a bar of 0, and `V = 0` gives `P_lose · C`.

**Carrier fixtures (`test_role_carrier.gd`), each a pair that differs in one fact:**

1. A mid-range look with support set and no pressure **holds**; the same look with a
   forechecker closing **fires**.
2. A doorstep look **fires** with `V` at its ceiling, so obvious chances stay instant.
3. A contained carrier at the point with the retreat ring open does **not** fire a
   clean point shot. This is the `SHOT_MIN_VALUE` comment's original job, held by the
   best-retention-option read (§5).
4. *(Phase C)* A point shot with a net-front teammate **fires**; the same shot with
   nobody there **holds**. This is F6's behavioral acceptance criterion.

**Calibration/aggregate:** the Phase A scorecard, re-run after each phase. Goals per
OZ possession must not fall. Shots per OZ minute should fall at mid-range and rise at
the point with traffic. The shot-opportunity audit
(`test_shot_opportunity_audit.gd`) is deliberately decoupled from
`SHOT_MIN_VALUE` and should not move.

## 9. Risks

- **Dithering.** If `V` reads high, nothing qualifies and the carrier never fires.
  Two things bound it: `V ≤ r · τ`, and fire-wins-ties still holds against the carry.
  Fixture 2 guards the obvious chance. Watch the scorecard for OZ possessions that end
  in a strip with zero attempts.
- **The constant-hazard assumption.** `safety` is a 0.4 s read extrapolated to a
  multi-second hazard. It is the same assumption `delay_discount` already makes, and
  the error is in the safe direction: pressure tends to build, so the true `V` under
  pressure is lower still. It is a modelling choice to know about, not a bug.
- **Bots training on bots.** A sim-measured `r` is the rate the bots manage against
  bots. If they are bad at cycling, `r` is low and patience understates itself.
  Logged play cannot correct it yet: `shot_events` records shots, not possession
  time. Sampling `AIOzPossessionTracker` live from `GameManager`, the way the
  breakout tracker is, would.

- **Phase B's fixed `P_lose` moves point shots uniformly.** Until Phase C, retention
  does not depend on traffic, so if the measured `P_lose` comes in below the implied
  0.7, point shots get cheaper *with or without* a net-front man. The scorecard splits
  point shots by net-front presence so the B playtest can tell this apart from the
  patience change.

## 10. Decisions

Settled before implementation, with the reasoning, so a later reader can tell a
decision from an accident.

1. **Data: sims for `r`, logged play for `P_lose`.** `r` calibrates from bot sims
   because they exist today. `P_lose` cannot: Phase A found that no harness models a
   save followed by the next possession (§6). So `next_control` is the only source,
   not a later refinement. Real data only accumulates from the day it ships, which is
   why it went in during Phase A. #577 is blocked on the same data, so the column
   pays twice.
2. **Contained carrier: fix the read, no floor.** A `0.05` floor under the new bar is
   exactly the corrective gate the AI doctrine forbids. It would keep the old constant
   alive to cover a model that is not seeing something. What the model was missing is
   that a contained carrier keeps the puck by peeling out, so `h` reads the best
   retention option (§3.2). If fixture 3 still fails with that read, it is reported
   as a finding, not patched.
3. **Tiers: one model for every tier.** Keeping the fixed bar for Easy would preserve
   `SHOT_MIN_VALUE` as a second code path for one tier. It would also deny Easy the
   readable half of the change: shooting with traffic, holding with support. Easy
   already has a selectivity dial (settle doubt) and a conversion dial (shot aim
   error). If Easy turns out too patient, the lever is input removal (Easy does not
   perceive `V`), added then with a reason.
4. **Ship B on its own, then C.** B is the patience change that was asked for. A
   playtest of B alone can attribute what it shows; a combined B+C playtest could not
   say which half made the zone feel different. The risk is noted in §9: a fixed
   `P_lose` moves point shots uniformly until C. The scorecard is split to catch it.
