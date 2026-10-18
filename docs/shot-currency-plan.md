# Shot currency — the odds against today's goalie

Status: **agreed design; steps 1–3 done; step 4 waits for hybrid carry**
(`docs/hybrid-carry-plan.md`), so the drive it prices follows a real route. The CLAUDE.md
workflow applies: this doc is the plan, deviations get discussed first.

## Decisions

- **A shot is worth its odds of scoring on today's goalie** — the live
  `GoalieController` this game ships, not an NHL average. Every value the
  carrier ranks (shoot, pass, carry, hold) prices its shot this way, on both
  sides of the blue line.
- **Rebuild on today's goalie.** `claude/goalie-planner-calibration` (July) is
  the map, not code to port: the keeper has changed since (#782's get-up, #784's
  screen peek). Its findings are summarised in §2.
- **The model is generated from the goalie, never hand-copied.** The bots read
  the odds from a table measured off the live `GoalieController`; a goalie change
  means re-running the generator, and no model code changes — new save
  mechanics included. A staleness check fails the suite when the goalie's code
  or tuning has moved since the table was generated.
- **Placement scatter 0.04 rad** for the currency (about the Normal hand): a
  decision is made before the release and the keeper's timing at release varies,
  so a pinhole found at one exact instant is not odds to bank on. It is applied
  at lookup, so changing it needs no re-measurement.
- **First shot only.** Rebounds, screens and tips get no credit here; that is
  #785, after the carrier work. Until then a set keeper reads as a wall from
  range (a clean first shot from 9.5 m out is ~0 against the Hard keeper), and
  the bots work to move him or get in tight before they shoot.
- **A set keeper is one who tracked the carrier in.** Every measured carrier
  skates in to his spot (`shot_odds_stager.gd`). Teleported in tight with the
  keeper reset to his crease, the shooter draws a committed slide and is
  measured against a keeper mid-coil — up to 0.9 odds from 3 m where the
  tracked keeper concedes about 0.4.
- The goalie does not change. Everything below is the bots' model of him.

## 1. Why

What the carrier ranks today is `AIShotValue.for_release`: the public NHL xG
form plus a keeper-displacement term and a body-fill term. Outside the offensive
zone it is replaced by `position_potential`, a separate curve, and the two are
stitched at the blue line through `XG_SLOT_REF`. Every defensive read already
uses the other model, the per-hole geometry (`open_net_danger`, memoised by
`AIDangerField`), so offence and defence price the same shot differently.

Measured against the live goalie (`tests/instruments/ai/test_model_vs_baseline.gd`,
the bot's own planned shot, 16 per cell, 32 cells):

| keeper | live | per-hole model | XGBaseline (the seam's base) |
|---|---|---|---|
| set, squared | 0.00 in every cell | 0.15–0.94 in tight | 0.05–0.40 |
| caught moving (settled 4 m to the side) | ~1.0 through the middle | ~1.0 | 0.05–0.40 |
| concordance (orders two cells like the goalie) | — | 92% | 68% |

So what decides a goal here is the keeper's STATE, which the seam barely reads,
and the per-hole model orders spots right but gets the set keeper badly wrong.
Backdoor feeds show the cost: the seam prices them at 0.02–0.03 where the
per-hole model reads 0.2–1.0 (`tests/instruments/tmp` probe, 12–18 m/s feeds).

## 2. What is known about today's keeper

From the July branch and `test_goalie_exhaustive_beatability.gd`:

- **He is beatable for the right reasons**: a clean set wrister from the dot
  line and point shots are saved; low through the pads mid-drop and a deke that
  commits him laterally then goes high are goals.
- **The stick is most of the wall.** With all three stick colliders off, a sweep
  goes from 2.8% to 20.9%. The planner models only the blade; the paddle and
  shaft are invisible to it.
- **High is the only way through a set keeper from the dot line** (15 of 16
  goals). From 3 m nothing scores at any legal speed — angle compression funnels
  every aim through the blade's fixed band.
- **The planner's hand cover is over-stated.** READY hands parked high make the
  model read the top corners as guarded, so it picks FLAT, which is exactly what
  this keeper stops best.
- **It models his position, not his phase.** The mid-drop low seal is a hump
  (closed standing, open mid-rotation, closed sealed); the planner's is a
  monotone decay. And it reads `goalie_down` as of now, so it cannot plan the
  deke that will put him down.
- **A held windup commits him** and opens a low glove-side seam (9.7% vs 5.6%
  cold). Bots fire charged wristers, so the bot's release is the held one.

Rebounds: 94% of dot-line shots leave a live puck. That is #785's.

## 3. What "the odds" means

`P(goal)` for a release at a spot, against the keeper in the state he will be
in at release (position, lateral motion, drop phase, hands), when the shooter
fires the best shot available to him from there with **reference execution**
(the league-default release dispersion — the currency prices the chance, not the
shooter, #699; a shakier hand misses more of the same shots).

Two live numbers per cell, and the model has to match both:

- **best** — the best shot in the bot's repertoire (aim × loft × pace) fired
  through the real charged-wrister release. This is the odds.
- **picked** — the shot the planner actually chooses (`best_shot_aim` /
  `best_shot_loft`). The gap between the two is planner error and is fixed in
  step 2; shipping a currency the execution cannot cash would be a lie.

## 4. Steps

Each step ships with the suite green and is measured against step 1's table.

### Step 1 — the target

`tests/unit/ai/data/shot_odds_truth.txt`, a checked-in **truth table** written
by `tests/instruments/ai/test_shot_odds_truth.gd` through
`real_goalie_shot_harness.gd`. Per cell (20 release spots × 6 keeper states) it
records:

- the keeper's replicated read at DECISION time — what the bot sees;
- the goalie's open set: FLAT / LOW / HIGH, each fired clean at 24 aims post to
  post through the bot's own release (charged wrister publishing its aim; a
  one-timer leaves cold). The release is deterministic, so this is the open set
  itself, and the odds for any shooter are it spread by his placement scatter;
- the shot the planner picks from that read, and what it did.

Keeper states: SET (settled, square); a feed from 3 m and from 6 m across, each
one-timed and caught-then-charged; and a 2 m deke onto the spot before the
charge. A held windup no longer drops today's keeper (it did in July), so there
is no down state yet; a save that leaves him down is #785's rebound case.
Regenerating costs ~16 minutes and is done when the goalie changes.

`tests/unit/ai/test_shot_odds_vs_truth.gd` holds the model against the table
with no live goalie: the per-hole model fed exactly the carrier's shoot-now
read, against the measured odds at the same placement scatter. Two ratchets —
mean |model − truth| and concordance — bank as step 2 improves them. It also
reports how much of the best odds the planner's own pick keeps.

### Step 2 — generate the shot field from the goalie

The hand-built reaction model (`open_net_danger`'s cover race, and the mirrored
constants it needs — `GLOVE_EXTENSION_M`, `GOALIE_BUTTERFLY_DROP_S`,
`FIVE_GAP_M`, `PAD_SPLAY_HALF_M`, …) is what makes every goalie change a model
edit, so it is replaced, not repaired. One generator measures two tables off the
live goalie, in step 1's form (the open set per cell: FLAT / LOW / HIGH × 24
aims through the bot's own release):

- **SHOT** — release spot × the keeper state the bot sees NOW: set; caught off
  his square (offset from the arc-square, lateral velocity, stance, depth, and
  how square he faces the release), sampled by the states feeds and dekes leave
  him in and by decoy carriers that draw him across, in or out (#787). Queried with the live read: shooting
  from the carry, or what a carry candidate arrives at.
- **FEED** — receiver spot × the pass: how far the keeper must travel between
  the passer's square and the receiver's (geometry, `goalie_arc_match_x`), the
  flight time, and one-timer vs catch-and-charge. Queried at the passer's
  decision, the keeper assumed square on the passer. What he manages over the
  flight is the goalie's own answer, so `predict_goalie_pos` leaves the feed path.

It is emitted as a generated GDScript file of constants
(`Scripts/domain/ai/generated/`), because the domain layer cannot load files.
`AIShotOdds` queries it: bilinear over spots, a kernel over the continuous state,
stance matched exactly. The odds are the best aim's goal fraction under the
reference scatter; the planner aims at that same aim, so execution and value
cannot disagree.

Checks: the generator stamps a fingerprint of the goalie's sources and tuning,
and a unit test fails when it no longer matches (regenerate). Step 1's table is
the held-out set — its feed distances and speeds are not the field's — and
`test_shot_odds_vs_truth.gd` moves from the per-hole model to the field.

Built small first (a coarse grid, checked against the held-out table), then the
full grid: ~1–2 hours on four processes, run when the goalie changes.

The defensive reads move with it in step 3, so their absolute bars —
`NET_FRONT_DANGER_BAR` 0.5, `LANE_PLAY_DANGER_BAR` 0.5,
`SHOT_RECEPTION_SCORE_GATE` 0.30 — are re-derived there.

### Step 3 — switch the currency (done)

`AIShotValue` is the one shot model (`now`, `set_keeper`, `feed`, `deflection`,
`now_at_spread`); its body is the field (`AIShotOdds`). Every read moved to it:
the carrier's compete, the threat surfaces and coverage reads, a pass's worth to
either side (`score_pass_value`), tips (a deflection is a one-timer feed whose
line is not picked) and the post-game xG stat (the field at the shot's context
spread). The hole-geometry model, its planner and the `AIDangerField` memo are
deleted; with no keeper replicated the bot shoots flat at the middle.

- The absolute bars are probabilities and kept their values on the field's
  calibrated odds: `SHOT_MIN_VALUE` 0.05 / `PASS_MIN_VALUE` 0.02 (giveaway),
  the 0.5 "more likely than not" net-front and lane-play bars (a feed in the
  house reads ~0.95-1.0, a perimeter one ~0-0.1), and the 0.30 reception gate.
- Known gaps: keeper depth is not a feature and a keeper stranded past the post
  reads as his most-beaten measured cell rather than an empty net (#787); one
  field for every goalie tier (#786); odds priced at the league blade loft
  (#788); a position the carrier reaches is priced in the keeper's live stance
  only for a shot before he could stand up (`AIGoalieModel.GOALIE_RECOVERY_S`),
  upright after it — when he chooses to rise is not modelled (#792).

### Step 4 — one currency over the whole ice (done for the carrier)

Outside the zone a spot is worth the odds of the shot you reach by driving in
from it — `receiver_drive_in_value`'s machinery, already used for pass
receivers — discounted by time and by the odds of keeping the puck that far.
`position_potential`, `potential_realization_discount`, `entry_value` and
`XG_SLOT_REF` go, and with them the stitch at the blue line.

**As built: search, then a plain leaf.** Pricing a neutral-zone spot as a drive
to the net does not work: straight routes to fixed entries swing between ~0.1
and ~0.4 on whether the line passes the forechecker, and over a 25 m trip the
defence is a guess. So the carrier searches forward instead — a second carry
step from its best first moves (`docs/hybrid-carry-plan.md`, "Then") — and only
values a spot where its search stops: `AICarrierField.horizon_value`, the best
zone entry's worth (shot or drive-in) × the skate's decay × the race to it. The
race is what makes the leaf honest against the searched lines; without it the
carrier stalls at the line, because staying outside reads better than crossing
into the defence. The forward-pressure toll went with it: a patch for the carry
not seeing past its first second. Every carrier-side value and cost is now in
odds; `entry_value` is gone.

Measured on the entry drill (`tests/instruments/ai/test_nz_entry_drill.gd`:
three attackers from their own half against a defence standing up at its
line, 30 starts): carried entries 21 → 26, turnovers
5 → 4, passes before entry 67 → 27, backward 32 → 9; time stalled at the line
about level. The breakout drill under a two-man forecheck
(`tests/instruments/ai/test_breakout_drill.gd`) was level (11 exits of 20,
9 turnovers).

Those runs flew every pass at a flat 15 m/s, without a saucer's loft, and
caught under a flat 22 m/s. The duel harness now flies a pass at the pace its
bot committed to, lofts the saucer, and catches by the puck's own rule; most of
the breakout's turnovers were that harness. On it, with the lane reading the
forechecker's stick: entries 25 carried of 30, 3 turnovers, 43 passes (18
backward); breakouts 19 exits of 20, 1 turnover.

**What a spot is worth, for either side.** The leaf the search stops at, the
opponent's value of a puck we lose, and the dump's resting spot are one read,
`AIPossessionValue`: in the zone the better of the shot and one straight drive
in (kept as far as the carry-safety read allows), outside it the best entry
(its shot or drive) × the skate there × the race to it. `XG_SLOT_REF` is gone.
On the entry drill: carried entries 25 → 27, turnovers 3 → 2, passes before
entry 43 → 24 (backward 18 → 8); the breakout drill is level (18 exits of 20,
1 turnover). Its cost was the dump search, a residual that priced each landing's
possession (~0.3 ms each, a few ms when it ran); the dump-in has since been cut —
rare, poor in results, and a worker spike when it searched.

The off-ball readers read it too: the defence prices a man by his threat on it
(`threat_of_carrier` / `threat_of_feed`), and the outlet and breakout roles stand
where the lane × our possession of the spot is best. `position_potential` is
gone.

## 5. What players should see

Fewer shots at a set keeper, especially from range. More lateral puck movement
before the shot, more backdoor feeds, more drives at a keeper who is moving.
Fewer total shots until #785 gives rebounds their value.

## 6. Open questions

- ~~Does the post-game xG stat move to the same model?~~ Yes (step 3): the
  field's odds at the shot's context spread, plus the first-contact leak.
