# Expected threat — valuing the whole ice, not the first shot

Status: **proposed; for review.** Nothing here is built. The CLAUDE.md workflow
applies: once agreed this doc is the plan, and deviations get discussed first.

## Decisions (proposed)

- **The currency becomes threat, not the first shot.** A puck at a spot is worth
  V = P(we score next) − P(they score next), over a horizon set by
  `READ_VALIDITY_TAU_S`. Today it is the odds that our *first* shot from there
  scores (`AIShotValue`). That one number already prices shots, passes, carries
  and turnovers (Scripts/domain/ai/CLAUDE.md → "One currency"), so changing it
  changes the scale of everything at once. That is deliberate: it is the only
  way the compete stays one currency.
- **Two layers, Cervone's split.**
  - The bots' existing live models price the **next event** with full context:
    the shot field, pass lanes, carry safety, the races.
  - A **generated grid** prices **everything after it**: possession of a cell,
    by side, in a few coarse contexts.

  The grid replaces `AIPossessionValue`'s one-man straight-drive projection
  wherever a read needs "what is this spot worth": the carry search's horizon,
  a receiver's spot, a turnover, the dump's meet, the defence's threat reads.
- **Generated from the game, never fitted to an outside league.** As the shot
  field is measured off the live keeper, the grid's transitions are measured off
  the real bots and physics in the duel harness. Shots score at the shot field's
  odds, so no Monte Carlo goal counts are used. A goalie or physics change means
  regenerating, never editing code.
- **A turnover is the other side's threat, signed.** A failed pass or a strip
  lands in their possession at that spot, worth −V_theirs. It is never 0, which
  is what Singh's xT does. Hockey's turnovers start rushes the other way.
- **A shot is not terminal.** A save with a rebound leads to a loose puck at
  wherever the live keeper sends it, raced by both sides; a freeze leads to a
  faceoff at our end's dot; a miss to a loose puck off the boards. That is
  #785's rebound half, and it is what gives a long shot its value.
- **Passes and the cycle come out of the transitions.** A cell's value includes
  every pass the bots actually make from it, so #892 is subsumed, not built
  separately.
- **This lands before #896.** #896 removed the last sliver of long-range odds
  against a set keeper. Under today's model that made long-range ice worth
  exactly 0, and the lone rusher lost the gradient that kept him wide. Under
  threat, long-range ice is worth what it leads to.

## 1. Why

The bots value ice two ways, and both stop at the first shot.

- **In the zone, a spot is its shot.** `AIShotValue` is the odds the first shot
  scores against the measured keeper. Against a set keeper from range that is
  ~0. It is exactly 0 since #896 fixed the far-post read: the shot field's SET
  cells concede nothing from 7.5 m out.
- **Without a shot, a spot is `AIPossessionValue`.** That is one man, one
  straight drive (at most `DRIVE_MAX_M`) or one of three zone entries, against a
  set keeper, with no passes, no rebounds and no second shot.

What that misses, each already an issue:

- **#785** — rebounds, screens and net presence. A point shot is worth its
  rebound, and nothing prices that.
- **#892** — the cycle. A won corner reads ~0 because one man there has no
  shot, though the feed out to the slot is the whole play. The no-dump-with-
  the-numbers rule (`ctx.numbers_up`) is a tactical patch standing in for it.
- **#797** — the defence's threat reads price a drive plus entries per
  candidate, at 2–5× the old read's cost.
- **#836 and #896** — the slow tier goes red whenever the shot field moves,
  because planning rides on slivers of first-shot odds. When the sliver
  vanishes the gradient vanishes, and route choices flip on noise.

The fix those point to is one model: what possession leads to, over the next
few events.

## 2. What the literature does

The parts this plan uses, with where each is described. Primary sources read
were the authors' own code and PDFs on GitHub (socceraction, EPVDemo,
LaurieOnTracking, mplsoccer, NHL_Markov); the rest is from abstracts and
summaries, and is worth reading in full before Step 3.

| model | value of a state | turnover | context | source |
|---|---|---|---|---|
| xT (Singh 2018) | `xT(z) = s(z)·g(z) + m(z)·Σ T(z→z′)·xT(z′)`; 16×12 grid, fixed-point or linear solve | leaks to 0 | location only | karun.in/blog/expected-threat.html; socceraction `xthreat.py` |
| VAEP (Decroos et al. 2019) | P(score in next 10 actions) − P(concede) | signed, automatic | last 3 actions | arXiv 1802.07127 |
| EPV, basketball (Cervone et al. 2014/16) | E[points] given full tracking; macro events (pass, shot, turnover) by competing hazards on full context, a coarse 70-state Markov chain after | 0 (possessions alternate) | full for the next event, coarse after | JASA 111(514) |
| EPV, soccer (Fernández, Bornn, Cervone 2021) | E[G], G = ±1 next goal; Σ over pass, drive, shot of P(action)·E[G \| action], each with success and failure branches | signed, priced at the failure spot | full tracking | arXiv 2011.09426 |
| Static EPV grid × pitch control (Shaw; Spearman's OBSO) | `EPV_grid(target) × P_control(target)`: a static grid made live by a physics control model | — | live control only | LaurieOnTracking |
| NHL Markov game (Routley & Schulte 2015) | undiscounted next-goal value; on-policy transition frequencies; value iteration | signed (Q_home − Q_away) | score, manpower, period, action history; zone only | UAI 2015 |
| THoR (Schuckers & Curro 2013) | P(goal for/against within 20 s) | signed | event type | Sloan 2013 |

Lessons taken:

1. **Signed value, or turnovers are free.** Every model that handles them well
   prices conceding. A zero-leak xT values a blind cross-ice pass at our own
   line as a mere loss of threat.
2. **Rich context for the next event, coarse values after it.** Cervone's split
   is the documented compromise; Shaw's grid × control is its cheapest form.
   Defender positions never enter the grid state, which would explode it; they
   enter through the live models that price the next event.
3. **Smooth with the model, not with counts.** Replace realized goals with the
   cell's mean xG (mplsoccer). Here that is the shot field itself: the grid
   never counts goals.
4. **Keep the horizon local.** Undiscounted next-goal values drift toward a
   baseline and compress the differences. Soccer and hockey practice uses
   10–20 s or a few actions.
5. **On-policy, regenerated.** Transitions are what the players actually do
   (Routley & Schulte, Liu & Schulte). Once the bots act on V their play
   changes, so V is regenerated a few rounds until it settles (generalized
   policy iteration).
6. **Sport-native cells beat a plain rectangle.** Respect the blue lines as
   gates and make cells finer where values change fast.
7. **Nobody has published xT from a simulator.** This is new ground, and the
   Monte Carlo truth in Step 1 exists to keep it honest.

## 3. The model

### 3.1 State

A state is the puck's cell, who has it, and a coarse context.

- **Cell.**
  - Team-relative rink coordinates: our end to theirs.
  - Cut on the blue lines and goal lines, so no cell straddles a gate.
  - About 1.5 m in their zone (finer in the house) and about 3 m in the neutral
    zone and our end.
  - Unfolded across x in their zone, because the keeper is left-catching and
    the shot field is asymmetric. Folded elsewhere.
  - Behind each goal line, its own cells.
  - Roughly 400 cells a side.
- **Possession.**
  - Ours: a carrier settled.
  - Theirs: the same, mirrored.
  - Loose: a puck nobody holds, priced through the race at its spot rather than
    as a state of its own (§3.3).
- **Context**, two buckets for v1:
  - *rush*: the attack has the numbers between the puck and the net
    (`AIRushRead`'s count, the read `numbers_up` already uses);
  - *set*: it does not.

  The keeper's state is not in the grid: the shot field prices him live at the
  next event.
- **Mode.** One grid for 3v3 and one for 5v5. Spacing and turnover rates differ
  too much to share.

### 3.2 Transitions — measured, not fitted

Each state's next **macro event** is sampled in the duel harness: the real bot
carrier and his teammates against a real defence and the live keeper
(`goalie_provider`), from many seeded stagings of the state. A sample runs
until the first of these:

- a shot is released;
- a pass is caught;
- the puck goes loose (a strip, a bobble, a missed pass, a dump);
- the carrier crosses into another cell and holds it for a settle;
- `MACRO_MAX_S` passes.

Recorded per sample: the event, where it ended, and how long it took.

- **Stagings come from self-play.** Positions are drawn from full duel-harness
  games, binned by state, so the defence a cell sees is the defence it
  meets in play, not a canonical one.
- **Shots are not rolled for goals.** A shot from the sample's release, against
  the keeper's state at release, scores at the shot field's odds. Its other
  outcomes come from the **rebound field** (§3.4).
- **On-policy.** The transitions are what today's bots do. That is the point:
  the value of a spot to *these* bots, not to an optimal player. Max-over-actions
  values are optimistic, because a static grid has no defensive reaction.

### 3.3 Solve

With P the measured macro-transition kernel, a transition's duration Δt and
`τ = READ_VALIDITY_TAU_S`:

```
V_ours(s) = Σ_e P(e | s) · e^{−Δt_e/τ} · value(e)

value(shot)       = g + Σ_r P(r | shot) · V_loose(r)      g: the shot field's odds
value(cell move)  = V_ours(s′)
value(pass)       = V_ours(receiver's cell)
value(loose at r) = V_loose(r) = p_r · V_ours(r) − (1 − p_r) · V_ours(mirror(r))
                                 p_r: our side first to it, the race at r
value(timeout)    = V_ours(s)   (resampled; contributes only through the decay)
```

The system is linear. It is solved by a direct linear solve of about 1,600
unknowns (two possession sides, two contexts, about 400 cells), or by value
iteration from 0, which converges because the decay is below 1.

V_theirs is V_ours mirrored, so one solve prices both sides, and a turnover's
cost is −V_ours(mirror(cell)), the negative of the other side's value at that
spot.

Values are smoothed only through what feeds them: the shot field's odds, and a
kernel over neighbouring stagings when a cell is thin. Goals are never counted.

### 3.4 The rebound field

This is a second measurement off the live keeper, beside the shot field: per
shot cell and keeper state, where a saved shot goes and how fast. There are
four outcomes:
- **caught or covered** → a faceoff at their end;
- **rebound** → the puck's spot and speed after first contact;
- **wide or high** → off the boards or behind the net;
- **blocked**, from the duel samples.

`real_goalie_shot_harness.gd`'s `fire_tracking_rebound` already marches a
saved puck on and reads where it ends up. The generator runs it over the shot
field's cells.

A loose puck after the shot is priced by the race at its spot, as every loose
puck is (§3.3).

This half of #785 needs no new model: the keeper's own contact physics already
decides where a rebound goes. Screens and tips stay out of v1.

### 3.5 Live use: grid × the next event

No read looks up the grid raw. Each action is priced as its live outcomes ×
the grid after them, Shaw's grid × control. This is the shape the carrier
already has, with `AIPossessionValue` swapped for the grid:

- **Carry or move:** the rolled path's keep odds × V at its end, plus the strip
  odds × V_loose at the strip point. The carry search's horizon leaf becomes V,
  so a carry that stops outside the zone is worth its cell, not its
  straight-line entry.
- **Pass:** lane × catch × V at the receiver's cell (or his shot off the feed,
  if better), plus the failure branches priced at their spots. They are already
  priced there today, just on the wrong scale.
- **Shot:** the shot field's odds, plus the rebound field × V_loose. A point
  shot now has a price.
- **Dump:** the race at the meet × V_loose there. The `numbers_up` rule should
  stop binding and can then go.
- **Defence:** `threat_of_carrier` becomes V at the man's cell, shaded by the
  live shot and race reads. That is one grid lookup in place of a drive and
  three entries (#797).

## 4. Steps

Each step ships with the suite green and is measured against Step 1's table.

### Step 1 — the truth

An instrument plays full duel-harness possessions from staged states across
the ice (both modes, both contexts) and records the Monte Carlo next-goal value
within the horizon: signed, discounted, goals scored by the shot field's odds.
The truth is written to `tests/unit/ai/data/threat_truth.txt`, as
`shot_odds_truth.txt` is for the shot field.

`test_threat_vs_truth.gd` then scores two things against the truth: today's
`AIPossessionValue` and `AIShotValue` as the baseline, and every later model
against the same table. The bounds are ratchets on error and concordance.

This also answers, before anything is built, how wrong today's model is and
where.

### Step 2 — the rebound field

Generate the rebound field off the live keeper, with its own fingerprint check
beside `test_shot_field_is_current.gd`. Nothing reads it yet.

### Step 3 — generate the grid

Build the macro sampler, the solve, and `generated/threat_grid_data.gd`.
Shard it like the shot field (`.claude/hooks/generate-threat-grid.sh`).

Hold it against Step 1's truth and against the properties in §5. Nothing reads
it yet.

### Step 4 — switch the currency

`AIPossessionValue` reads the grid with the §3.5 live layer. The value seam
takes the rebound continuation, and turnovers price −V(mirror).

What else changes:
- The giveaway bars (`SHOT_MIN_VALUE`, `PASS_MIN_VALUE`) and the defence's
  absolute bars are re-derived on the new scale.
- Snapshots are re-pinned as reviewed deltas.

The slow tier is the acceptance test, including #836's three pended checks.
#896 is rebased onto this branch and its field regenerated.

### Step 5 — regenerate on the new policy

Re-run Step 3 with the bots now acting on V, and repeat until the grid moves
less than the Step 1 error between rounds. Expect two or three rounds.

Then retire what V subsumes, each removal measured:
- the `numbers_up` dump rule;
- `DRIVE_MAX_M`'s projection;
- the developing-feed hold's private pricing.

## 5. Tests

- **Properties** (unit tier, against the generated grid):
  - V lies in [−1, 1].
  - V_theirs is exactly V_ours mirrored.
  - V rises along the centre line toward their net.
  - The house beats the point at the same distance from the wall.
  - A turnover at our blue line costs more than one at theirs.
  - Rush beats set in every cell.
  - The solve converges, and it reproduces itself from its own output.
- **Truth ratchets:** `test_threat_vs_truth.gd`, as above.
- **Fingerprint:** the grid goes stale with the keeper, the physics and the
  shot field, as the shot field does. It is *not* fingerprinted on bot code,
  which changes weekly; policy drift is caught by the truth ratchets instead.
- **Behaviour (slow tier):**
  - A lone rusher still shoots.
  - A 2-on-1 is not dumped in.
  - A won corner is cycled, not thrown away.
  - A point shot is taken with a man at the net.

## 6. Open questions

1. **The unit.** Signed next-goal, as proposed, or our scoring odds alone, with
   a turnover priced separately as today? The first is what the literature
   converges on and is simpler to keep honest. It rescales every bar.
2. **The horizon.** Is `READ_VALIDITY_TAU_S` (6 s) right, or should it be the
   10–20 s the soccer and hockey models use? The delay discount's existing
   bounds (2.8–6.3 s) were set for a one-step read, not for this.
3. **Context buckets.** Is rush/set enough for v1? A "recent shot" flag (the
   flurry that Routley & Schulte's history captures) is the next candidate.
4. **Generation budget.** The shot field takes 1–2 hours on four cores. The
   macro sampler is likely a few hours, on a schedule like the shot field's:
   when the keeper or physics change, plus the Step 5 rounds.
5. **Tiers.** Measured against the Hard keeper only, as the shot field is.
   Per-tier fields are the shot field's planned fix too.
6. **Real games.** The `shot_events` table (`tools/goalie_shot_events_audit.sql`)
   holds shots from real matches. It is a check on the shot half only; there is
   no carry or pass log to check transitions against.
