# Zone Entry Currency — Design Doc

Status: **draft for review**. Nothing here is implemented. Per the CLAUDE.md
workflow, this doc is the plan; deviations get discussed first.

## 1. The problem

Playtest: bots take the zone, then drop the puck back to a trailer. The pass
back out of the zone was a valve bug (fixed: `_zone_taken` keys on the puck).
But the bots still *want* that pass. In the repro scene (carrier at speed up
the left wall ~3 m short of the line, a defender gapping him at 2.5 m, the
trailer 5 m behind in the middle) the drop scores **0.47** against **0.39**
for carrying, and entering the zone earns nothing in that number.

Two things in the value model make the blue line invisible:

- **Outside the zone, value is `position_potential`**: closeness × projected
  goal-mouth width × release openness, on a 0–1 scale, discounted by travel to
  the slot ring (`potential_realization_discount`). It is smooth across the
  whole rink (~2%/m), so crossing the line with control is worth what any
  other metre is worth. The angle term also rates the middle above the wall
  (0.71 vs 0.63 at the line), so a trailer 5 m back in the middle is worth as
  much as the carrier on the wall at the line.
- **The regime is keyed on the carrier's BODY** (`_score_at`'s `from_pos`).
  While he is outside, every spot is priced on the potential map, including
  in-zone spots. Once his body crosses, everything is priced in xG
  (`AIShotValue`), and the same carry drops from ~0.4 to ~0.14. The two scales
  are never compared inside one eval (CLAUDE.md: "the two scales never need to
  be compared"), which is true. But it means an out-of-zone carrier cannot
  see what entering is worth in the currency it will be judged in one tick
  later.

## 2. What does NOT work, and why

**Price in-zone candidates in xG while the carrier is still outside** (the
first idea floated). The out-of-zone candidates would stay on the potential
scale (~0.4–0.6) and the in-zone ones would drop to xG (~0.02–0.14), so every
in-zone option would lose to staying out. Bots would stop entering. Mixing
the scales inside one compete is exactly what the current split avoids. The
fix has to put both sides in **one unit**.

## 3. Proposal: give `position_potential` its unit

`position_potential` already *has* a unit; it just isn't written down. By its
own construction it is 1.0 exactly when the carrier is **at the slot ring
(`SLOT_RADIUS_M`), square to the net, release uncontested**. That is the spot
`potential_realization_discount` measures the remaining travel to. So a value
of `p` means "a fraction `p` of a clean slot look, cashed after the
realization delay".

The conversion is therefore a measurement, not a tunable:

```
XG_SLOT_REF = AIShotValue.for_release(slot ring, head-on, set keeper, SHOT)
value_out(pos) = position_potential(pos) × realization(pos) × XG_SLOT_REF
```

`XG_SLOT_REF` is computed from the live xG model at static init, never typed
in (the model docs put a clean mid-slot look at ~0.12). It moves if the shot
model moves, which is the point: the out-of-zone map stays denominated in
whatever the in-zone currency says a slot look is worth.

With one unit on both sides, the regime can be keyed on the **candidate
spot** instead of the carrier's body:

- spot in the zone → xG (as now for an in-zone carrier);
- spot outside → `value_out`.

That removes the currency switch at the carrier's body. An out-of-zone
carrier now prices "carry across the line" in the same xG it will be judged
in next tick. A trailer's drive-in that reaches the zone is priced in xG too.

Rough check at the blue-line centre: `0.71 × 0.66 × 0.12 ≈ 0.056` out of zone,
against ~0.02 for the xG of standing just inside and ~0.14 for the best
in-zone carry from there. Same order of magnitude, not a 3x step.

## 4. Every consumer has to move together

A uniform rescale of one side of a compete is a silent re-weighting. These
read `position_potential` today and must all convert in the same change:

| site | what it prices | why it must convert |
|---|---|---|
| `AIRoleCarrier._score_at` (+ its hot-path skip) | carry candidates, pass receivers, drive-in | the change itself |
| `AIRoleCarrier._best_carry` stand-still | holding ground out of zone | same compete |
| `AIActionScoring.threat_surface_shoot` / `threat_surface_pass` | the opponent's value at a loss point (turnover cost) | benefit scaled but cost not = NZ turnovers suddenly ~8x dearer than anything they risk |
| `AIRoleCarrier._best_dump` gain, `solve_dump_in` ceiling | dump-in recovery value | dump-vs-carry exactness (the realization telescoping in `_best_dump`) |
| `AIRoleBreakout`, `AIRoleOutlet` | off-puck spot choice | argmax over spots only, so a uniform scale is a no-op there; verify, don't convert blindly |

## 5. Consequences to expect (and measure)

- **The giveaway bars start to bind outside the zone.** `PASS_MIN_VALUE`
  (0.02) and `SHOT_MIN_VALUE` (0.05) are xG-scaled. On the potential scale
  (~0.4) they were irrelevant out of zone; on `value_out` (~0.03–0.07) a
  marginal neutral-zone pass now has to clear a real bar. That is arguably
  correct (one currency, one bar), and it pushes toward carrying. But it is a
  behavior change across the whole neutral zone and breakout, not just at the
  line.
- **Settle doubt starts to bite outside the zone** for the same reason.
- **Hysteresis is proportional**, so it is unaffected. `retention_hopeless`
  reads signs, so it is unaffected.
- **Hot path:** in-zone candidates and receivers from an out-of-zone carrier
  now run `score_shoot_value` where the skip used to return potential. That
  is a bounded number of candidates near the line, but it is a hot-path change,
  so the benchmarks run before and after.

## 6. Measurements before merging

1. **The entry fixture** (from this investigation: carrier on the wall, trailer
   in the middle, gaps 2.5–8 m, bodies 1–4.5 m short of the line). Report
   carry vs drop at each cell, before and after. Success: the drop wins only
   where the trailer is genuinely the better play (carrier covered, trailer
   with a real lane), not across the board.
2. **Rush sims** (`test_rush_sim.gd`, `test_real_rush_sim.gd`): controlled
   entry rate, dump-in share, passes per entry.
3. **Breakout and NZ fixtures** in `test_role_carrier.gd`, `test_role_breakout.gd`:
   expect movement where the bars now bind; review each case rather than
   re-pin blindly.
4. **Benchmarks** (`-gdir=res://benchmarks`): per-tick p95/max, carrier eval cost.
5. A local playtest, since entries are a feel thing a fixture can't fully judge.

## 7. Open questions for you

1. **The unit.** Is "a clean slot look against a set keeper" the right
   anchor for potential's 1.0? It's what the function's construction says,
   but the alternative is anchoring at the blue line itself (value_out at the
   line = best in-zone carry from there), which is continuous by construction
   but needs a lookahead, not a constant.
2. **Bars binding in the neutral zone.** Accept it as part of the change (my
   recommendation: one currency should mean one bar), or keep the bars
   zone-only for now and revisit?
3. **Scope.** Both 3v3 and 5v5 at once (the code is shared; splitting would
   need a gate), or 3v3 first because that's the default mode?
