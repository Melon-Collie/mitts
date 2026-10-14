# Shot currency — the odds against today's goalie

Status: **agreed design, not started.** The CLAUDE.md workflow applies: this doc
is the plan, deviations get discussed first.

## Decisions

- **A shot is worth its odds of scoring on today's goalie** — the live
  `GoalieController` this game ships, not an NHL average. Every value the
  carrier ranks (shoot, pass, carry, hold) prices its shot this way, on both
  sides of the blue line.
- **Rebuild on today's goalie.** `claude/goalie-planner-calibration` (July) is
  the map, not code to port: the keeper has changed since (#782's get-up, #784's
  screen peek). Its findings are summarised in §2.
- **First shot only.** Rebounds, screens and tips get no credit here; that is
  #785, after the carrier work. Until then a set keeper reads as close to a
  wall, and the bots work to move him before they shoot.
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

A checked-in **truth table**: live goal rates over a grid of spots × keeper
states, measured through `real_goalie_shot_harness.gd`, both `best` and
`picked`. Keeper states sweep phase, not just the two extremes: set; caught by
a lateral relocation of 1, 2 and 4 m with the shot released at several delays;
mid-drop; down. Generating it costs minutes, so it lives in `tests/instruments/`
and is re-run when the goalie changes; the table itself is checked in.

A unit test then holds the model against the table cheaply, with no live goalie:
per-cell error under a bound, and concordance at least what the per-hole model
scores today. The bound starts loose and tightens as step 2 lands.

### Step 2 — make the per-hole model true

Fix the model against the table, missing perception first:

1. the stick's real surface (paddle and shaft, not just the blade);
2. the hand cover at the pose he actually holds;
3. phase: the drop's low-seal hump, lateral commitment, the held-windup lean;
4. the planner's pick, until `picked` ≈ `best`.

This changes the defensive reads too (they use the same model), so their
absolute bars — `NET_FRONT_DANGER_BAR` 0.5, `LANE_PLAY_DANGER_BAR` 0.5,
`SHOT_RECEPTION_SCORE_GATE` 0.30 — are re-derived here, not left at values
measured against the old surface.

### Step 3 — switch the currency

`AIShotValue.for_release` stays the one entry point; its body becomes the
per-hole model at the predicted keeper state. Consequences:

- `SHOT_MIN_VALUE` / `PASS_MIN_VALUE` become bars on real odds and are re-set.
- `tip_ev` is already on the per-hole scale, so the unit mismatch in the shoot
  compete goes away.
- `XGBaseline` leaves the bots entirely; it stays for whatever the post-game
  stat decides (open question below).
- Cost: the per-hole model is dearer than the seam (`score_shoot` ~55 µs vs a
  whole carry candidate ~180 µs). Measure with `benchmarks/` before and after;
  the predicted keeper varies per candidate, so the memo cannot simply be
  reused.

### Step 4 — one currency over the whole ice

Outside the zone a spot is worth the odds of the shot you reach by driving in
from it — `receiver_drive_in_value`'s machinery, already used for pass
receivers — discounted by time and by the odds of keeping the puck that far.
`position_potential`, `potential_realization_discount`, `entry_value` and
`XG_SLOT_REF` go, and with them the stitch at the blue line.

## 5. What players should see

Fewer shots at a set keeper, especially from range. More lateral puck movement
before the shot, more backdoor feeds, more drives at a keeper who is moving.
Fewer total shots until #785 gives rebounds their value.

## 6. Open questions

- Does the post-game xG stat (`AIActionScoring.expected_goals`) move to the same
  model? It is deliberately shooter-blind and separate today; decide when step 3
  lands.
- Does the reference execution for the currency come from the Hard hand, or a
  separate league-reference constant? Decide in step 1, from what the table
  shows.
