# Possession value — the shot pays for the puck it spends

Status: **proposed**. Nothing landed. Bar form agreed; the open questions in §10
are still open.

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
  carrier already perceives. `current_safety` (`_phase_current_safety`) is the
  probability of keeping the puck over `AICarrySpace.EVADE_HORIZON_S` at the
  best-clearance seam. That is the "can I keep it at all" read, so a charger I can
  dance out of does not count as danger. Under constant hazard,
  `h = −ln(safety) / EVADE_HORIZON_S`.
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
| Cognition gates | No tier-scaled constant enters the model. If Easy should differ, the allowed lever is input removal: Easy does not see `V` and keeps the fixed bar (§10 Q3) |

The `SHOT_MIN_VALUE` comment states a second job: stopping a **contained** carrier
from trading the puck for a point shot. A contained carrier has low safety, so high
`h`, small `V` and a *looser* bar. This is the one place the new model could move in
the wrong direction. §8 pins it with a fixture, and if it fails the fallback is to
keep 0.05 as a floor (§10 Q2).

## 6. Measurement — Phase A, no behavior change

Two quantities (`r` and `P_lose`) and a before/after scorecard need a measurement
that does not yet exist.

**The instrument:** `AIOzPossessionTracker`, a debug tally modelled on
`AIBreakoutEpisodeTracker` (episodes, outcome classes, nothing reads it back into a
decision).

- **An episode** starts when the puck is established in the offensive zone under our
  possession.
- **It ends on:** puck leaves the zone, opponent establishes possession, whistle, or
  goal.
- **It records:** duration; each shot attempt with its seam `xG` at release and its
  outcome (goal / saved / missed / blocked / whistle); and, for each non-goal shot,
  who controls the puck next inside a short window (us / them / whistle → faceoff
  result).

**Where it runs:**

- **Bot sims, now.** Report-only scenarios on the duel harness, alongside
  `benchmarks/test_breakout_harness.gd`, for a 3v3 and a 5v5 roster. This gives
  `r = Σ xG / Σ OZ seconds` and `P_lose` per team size immediately.
- **Real play, later.** `shot_events` already logs `x`, `z`, `outcome` and the release
  context #577 needs, but not what happened next. A `next_control` column
  (`'ours' | 'theirs' | 'whistle'`) is one new migration plus the logging site. This is
  the source #577 is waiting on, so both plans gain from it (§10 Q4).

**The scorecard**, recorded before Phase B and re-run after each phase:

- OZ possession seconds per game
- shot attempts per OZ minute
- mean xG per attempt
- point shots with and without a net-front man
- **goals per OZ possession** (the real success criterion; patience that does not
  move it is cosmetic)

**Gate:** compare the measured `r` and `P_lose` against §3.2's implied numbers before
writing Phase B. A large disagreement is a finding to discuss, not a constant to
fudge.

## 7. Phases

| Phase | Content | Behavior change |
|---|---|---|
| **A** | Tracker + harness scenarios + baseline scorecard. Optional `next_control` migration. | none |
| **B** | `AIPossessionValue` (pure, static, engine-free). `h` from `current_safety`, measured constant `r` and `P_lose` per team size, `C` from `turnover_cost`. Replaces `SHOT_MIN_VALUE` at the one call site. | yes; playtest |
| **C** | Per-shot `P_lose`: net-front race + outcome mix by save surface. | yes; playtest |
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
3. A contained carrier at the point does **not** fire a clean point shot. This is the
   `SHOT_MIN_VALUE` comment's original job; if it fails, see §10 Q2.
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
  bots. If they are bad at cycling, `r` is low and patience understates itself. Real
  play data (§6, `next_control`) corrects this once it exists.

## 10. Open questions

1. **Phase A data source:** bot sims only for now, or also add the `next_control`
   column to `shot_events` so real play starts accumulating (and #577 gains the same
   data)?
2. **The contained carrier:** if fixture 3 fails, keep `0.05` as a floor under the new
   bar, or treat it as evidence that `h` should read containment differently?
3. **Tiers:** should Easy keep the fixed bar (input removal), or run the same model
   and differ only through its existing knobs?
4. **Phase B shipping:** is a constant-`P_lose` Phase B worth a playtest on its own, or
   should B and C land together, so the point-shot half of F6 arrives with the
   patience half?
