# Shot field resolution — measured edges and a grid that reaches the boards

Status: **steps 0–1 done; steps 2–5 agreed, in progress.** Follows `docs/shot-currency-plan.md`; that
doc's decisions (odds against today's goalie, measured not modelled, 0.04 rad
reference scatter applied at lookup) all stand. This one changes how finely the
goalie's open set is measured and how much of the zone is measured at all.

## 1. Why

Two defects show up when the field is drawn over the zone (the bots' read,
`AIShotValue.set_keeper`, sampled every 0.5 m).

**The open set is measured at 7.4 cm and priced as if it were exact.** Each
loft fires 24 aims post to post, and `AIShotOdds.aim_odds` treats each aim's
outcome as true for its whole 7.4 cm band. A gap a few centimetres wide at the
post shows up only if an aim sample happens to land in it, and then counts as a
full band. Around the left faceoff dot:

| spot (x, m out) | odds | what made it |
|---|---|---|
| −6, 4.5 / 6.0 / 7.5 | 0% | all 72 shots saved, or high shots over the net |
| −6, 3.5 | 21% | two goals, the two aims nearest the post |
| −4, 7.5 | 9% | one goal, the aim on the post, LOW |
| −8, 9.5 | 6% | one goal, the aim on the post, LOW |

So the dot reads as a wall and a step either way reads as a shot. The best aim
(`_build`'s `maxf`) then amplifies whichever spots got lucky.

**The band at each post reaches past the post.** Aim 0 sits at `-reach`, where
the puck's edge touches the inside of the post, and its band covers
`[-reach - step/2, -reach + step/2]`. Half of that band is crossings that hit the
post or go wide. A lone goal at the post from about 8.5 m prices at 8.6%, of
which 4.3% comes from crossings that cannot go in. 3,261 of the field's 8,232
loft rows have a goal at a post aim, so this is a systematic lean toward the
posts, in the price and in the pick.

**The grid stops short of the zone.** Spots run x ∈ [−8, 8] and 0.6–15 m out.
`_weigh` clamps any release past that to the edge spot, so the value is held
flat however much worse the shot gets:

| release | bots' read | xG stat |
|---|---|---|
| −8, 0.6 (measured) | 43% | 23% |
| −12, 0.6 (on the boards) | 43% | 17% |
| 2, 15 (measured) | 4.9% | 5.8% |
| 2, 19.3 (blue line) | 4.9% | 5.5% |

The aim and loft are copied too. On the goal line at the boards there is barely
a line past the near post, so 43% is not a shot that exists. The xG stat sinks a
little because `shot_now_at_spread` re-reads scatter at the real range; the bots'
read does not, because `_build` prices each aim at the measured spot's range.

## 2. Decisions proposed

- **Measure the edges, not the samples.** Keep the 24-aim sweep, then bisect
  every transition into or out of a goal down to ~5 mm. Store goal intervals in
  the net's frame and price a crossing by the interval it lands in. The aim
  count stops being the measurement's resolution; it stays as the set of
  candidate aims the pick chooses from.
- **A run of goals that reaches a post ends at the post.** Its outer edge is
  `±reach`, not half a band past it. This falls out of the intervals; it does not
  need its own rule.
- **Measure the zone to the boards and the blue line.** Add spots wide and far
  enough that the clamp only holds for releases off the ice or outside the zone.
  Spots that would put the carrier in the boards are skipped. The reader already
  handles an empty spot (no cells: its bilinear share goes to the neighbours, in
  GDScript and in `native_shot_odds.cpp` alike).
- **Find out whether the sweep misses whole gaps before paying to look.**
  Bisection only sharpens transitions the sweep saw. A gap narrower than 7.4 cm
  between two saves is still invisible. Step 1 measured it: it does not matter
  (§3, step 1).

## 3. Steps

Each step ships with the suite green.

### Step 0 — clip the post bands (no regeneration) (done)

In `AIShotOdds.aim_odds`, the outer band at each end spans only from the post
inward (`[-reach, -reach + step/2]` and its mirror). One function, no data
change; `best_odds` and `shot_now_at_spread` go through it. The truth test's
truth goes through the same function, so both sides move together. Re-bank the
three ratchets in `test_shot_odds_vs_truth.gd` if they move past `BANK_MARGIN`,
and say so in the commit. This removes the phantom half of every post-side goal
today and stands on its own whether or not the rest lands.

### Step 1 — how much does the sweep miss? (instrument) (done)

`tests/instruments/ai/test_open_set_resolution.gd`: the SET cell and a DECOY
cell (the keeper set on a carrier 3 m inward) at 30 spots off the field's grid
(x −8, −6.7, −4, 0, 2.5 × 0.6, 2.5, 4.5, 6.1, 9.5, 15 m out). Per loft it fires
93 aims (every fourth is the field's 24) with their edges bisected twice as the
reference, and prices three readings at the field's 24 candidate aims and
0.04 rad. 17,176 shots, about 8 minutes on four processes.

| reading | mean \|odds − ref\| | worst |
|---|---|---|
| 24-aim bands (today, after step 0) | 0.018 | 0.10 (2.5 m right, 4.5 m out, SET) |
| 24 aims + edges bisected 4× | 0.0002 | 0.009 |

Five cells hold a goal gap the 24-aim sweep never sees (up to 5.5 cm wide), but
none of them is the cell's best shot, so none moves its odds by more than the
0.009 above. **Step 2 adds no probes between saves.**

What the bands got most wrong is the post gap from mid-range against a set
keeper: 0 m, 6.1 m out reads 6.0% as bands and 0.4% measured; −8, 9.5 m reads
2.9% and 0.2%. Those gaps are about a millimetre wide. Bands also read some real
gaps low: −4, 15 m out with the keeper drawn off reads 4.7% as bands and 8.6%
measured.

### Step 2 — goal intervals from the stager

`shot_odds_stager.gd`:

- `open_set` keeps its 24-aim sweep and, per loft, bisects each adjacent pair
  whose outcomes differ in whether they are goals, `REFINE_STEPS` times (4: 7.4 cm
  to under 5 mm). Each probe re-stages the keeper first, as every shot already
  does, so the edges stay order-free
  (`test_shot_field_cells_are_order_free.gd` still holds).
- It returns the three sweep strings plus three interval lists:
  `"-847:-803;312:398"` (millimetres in the net's frame, `""` for none). A run
  touching a post takes `±reach` as that edge.

Both readers of the stager change with it: the field generator and
`test_shot_odds_truth.gd`. The format is additive: the interval lists go in new
columns after the sweeps (field rows 26–28, truth rows after the reads), so
every reader that indexes by column keeps working.

### Step 3 — the grid

`test_generate_shot_field.gd`:

- `SPOT_X` gains ±10 and ±12; `SPOT_FWD` gains 17.5 and 19.5 (the blue line's far
  edge is 19.51 m out).
- A spot whose carrier is not on the ice (`GameRules.clamp_to_rink_inner` with
  a skater's collision radius moves it) emits no cells. With these spots that is
  ±12 in the two or three rows nearest the goal line, where the corners curve in.
- `MAX_ABS_X_M` (passers and deke starts) becomes the same on-ice test. A flat
  11 m lets a passer stand in the corner arc at the goal line.

About 150 spots against today's 90. Wide spots carry fewer feeds and decoys (only the
inward ones fit), so cells grow by roughly 60%.

### Step 4 — read the intervals

`AIShotOdds`:

- `_build` parses each loft's interval list into packed arrays (per cell: a
  start into a flat `PackedFloat32Array` of edges and a count per loft).
- `aim_odds` becomes `Σ ½·[erf((b − aim)/(σ√2)) − erf((a − aim)/(σ√2))]` over the
  loft's goal intervals. `_aim_odds` is still filled per cell × loft × candidate
  aim at build, so the per-query cost does not change.
- `shot_now_at_spread` reads the parsed intervals instead of re-splitting the
  row strings.
- Candidate aims stay `AIM_POINTS` post to post. At σ ≥ 0.2 m a 7.4 cm
  candidate step costs little. Adding each interval's centre as a candidate is a
  possible follow-up, and it changes the blend's shape, so not in this step.

`test_shot_odds_vs_truth.gd` reads truth through the same intervals.
`AIShotOdds.best_odds` takes the intervals instead of the pattern strings.

### Step 5 — regenerate and re-bank

Truth table (~16 min), then the field. Today's full grid is ~1–2 h on four
processes; with ~60% more cells and ~14% more shots per cell (6,941 goal edges
in today's field × 4 probes, against 197,568 sweep shots), expect about
1.85×. Re-bank the truth ratchets. Update `Scripts/domain/ai/CLAUDE.md` → Shot
value (the "spot × how he was beaten" description and where the field ends).

## 4. What it should change

- The ring around the dot stops alternating 0% and 6–9%. A post gap a few
  millimetres wide is priced at a few millimetres.
- Post-side shots lose their phantom half-band, so the pick leans less toward
  the posts.
- The goal line out to the boards and the top of the zone are measured instead
  of copied, so the 43% from the boards goes away (or is confirmed, if the keeper
  really leaves that line).

## 5. Open questions

- **Refinement depth.** 4 bisections gives ~4.6 mm, under the puck's 3.8 cm
  radius by a wide margin. 3 may be enough; step 1 can measure it.
- **Interior gaps.** Settled by step 1: no probes between saves.
- **A row at 0.25 m out.** Releases between the goal line and 0.6 m still clamp
  to the 0.6 row. Inside the crease that does not matter; wide of it, it is a
  sharp-angle shot the field has not seen. Cheap to add with step 3.
- **Per-tier fields.** Still Hard only (`Scripts/domain/ai/CLAUDE.md`); this does
  not change that.
