# Strip odds — one model of whether a defender takes the puck

Status: **agreed design (in chat), measured; building.** The CLAUDE.md workflow
applies: this doc is the plan, deviations get discussed first. (The file keeps
its first name, from when the model was a race.)

## Why

Every read that asks "does the carrier keep the puck" asks the same question:
**if the carrier skates this path, what are the odds a defender strips him of
the puck within it?** Today that question is answered several ways, each with
its own guess at what the defender will choose to do:

| Read | What it assumes the defender does |
|---|---|
| `AICarrySpace.reach_clearance` / `carry_safety` | coasts, then lunges in a fixed window at the end (`CARRY_LUNGE_WINDOW_S`); a man skating with the carry may brake instead (`_stopped_clearance`); a chaser commits the whole way (`_chases`) |
| `AIPossessionValue._line_keep` | past the line, shadows the carrier's current course at his own depth; a crossing picked late is "the lunge's to cover" |
| `AIDefenderProjection` | ahead: holds his gap down to the top of the house; behind: backchecks; forechecker exception in our zone |
| `AIPossessionValue._skate_keep` / `_drive_keep` | the projected defence above, then the lunge model, over a fixed drive length |

The carrier compares the outputs as if they were one currency. They are not, and
the disagreements show up as behaviour (a carrier chasing a lateral cut a
square defender mirrors, `test_nz_carry_keeps_pace` gap 10 m). And none of them
was ever held to what our defenders do: measured, today's carry read predicts
losses worse than guessing the base rate.

## The model

For a carrier's path (the plan being priced: the puck at each point at each time
from now) against each defender (his position and velocity now, his build):

1. **Where he will be: his momentum's line, give or take his push.** His centre
   at `t` is `pos + vel·t`; around it, the odds he is at a spot fall as
   `e^(−push / FAN_SCALE)`, push being the share of his body's push (his thrust
   over the time, `½·A·t²` of ground) he needs to be there. No reaction delay and
   no intent: measured, a defender centred on chasing the puck, on intercepting
   it, or anywhere between predicts where our defenders go worse than his
   momentum does.
2. **What he takes: a strip rate while the puck is within his stick.** Within
   `STRIP_RADIUS_M` of his body the puck is stripped at a rate per second — one
   for a moving puck, one for a standing puck. The odds the puck keeps to the
   path are `exp(−Σ rate · P(he is within the radius of the puck then) · dt)`.
3. **Several defenders: their exposures add** (Spearman's probabilistic
   combine), not the likeliest one alone.

Measured against our defending bots (`test_defender_race_truth.gd`, 1584 runs of
a scripted carrier protecting as a bot does, every defender tracked):

| | value |
|---|---|
| strip radius off his body | 2.0 m (stick, blade and poke; the race's 1.8 m was short) |
| strip rate, moving puck in reach | 4.5 /s |
| strip rate, standing puck in reach | 3.0 /s |
| fan scale | 0.25 of his push |

- Given where he really is, the strip rate reads which runs lose the puck 96% of
  the time (ranking at each loss against a run still in play); it is the
  movement — where he goes — that a model of a defender has to predict.
- From the start alone, the two halves together (nothing refitted) expect 568
  losses against 543 and rank 0.763 — the race with a strip rate 0.751, a
  constant loss rate nothing. Today's carry read scored worse than predicting
  the base rate.
- Left in it, measured: against the momentum line a defender to the side of the
  carrier's path takes the puck about twice as often as read, as does one
  facing a standing carrier, and a carrier cutting away loses it about half as
  often. Every generic movement (momentum, pursuit, interception, blends) ranks
  0.74–0.76; what is missing is what a defender decides (step up, hold the gap,
  angle), which no kinematics sees. A later pass, perhaps something more human
  than a mirror of our defenders' code.

**Measure on fixed paths.** A planner asks "if I take this path, what happens";
a bot carrier's own runs answer only for the paths he chose, which avoid the
danger — fitted to them, the lane in front of a defender reads safe because
nobody who saw him went into it.

**The deke tradeoff, accepted.** Revisit if play shows it.

## What it retires

- `reach_clearance`'s commit window (`maneuver_time`, `CARRY_LUNGE_WINDOW_S` in
  keep reads), `_stopped_clearance`, `_chases`, the escape-speed gate — all
  defender-intent guesses.
- `reach_band_m`, the `band_m` argument on the safety maps and `projected_s`;
  the dwell and transit safety maps as keep reads (the two strip rates).
- `_line_keep`'s shadow and natural crossing; `_skate_keep`'s `DRIVE_MAX_M`
  horizon as a defence rule.
- `AIDefenderProjection` and `AIPossessionValue._project` in keep reads, and
  `AICarrierField.project_opponents` where it feeds a keep read (ply 2,
  `_end_worth`, the wheel, `receiver_drive_in_value`, the feed's catch).
- **`AIDefencePairing`'s pairing and riding** (`pair`, `rides`, `ride_at`) and
  the shared entry cache's key on it: a man skating with his attacker carries on
  that way, and the fan reads it. `collect_attack` (our own skaters, for the pass
  to a man following in) is not a defender model and stays as a helper.
- The race (`AIDefenderRace`), superseded by this.

## What it does not touch

- **Where the defence stands later for the shot model** (blockers and screens
  after an entry) stays on `AIDefenderProjection`, riders included, for its own
  pass; the pairing goes entirely with it.
- **Pass lanes** (`AILaneReach`) stay on the arrival clock for now. A puck in
  flight through a defender's reach is the same question on a faster path; moving
  lanes onto the fan and the moving strip rate is a later step, measured first.
- The arrival clock, the shot odds and the keeper.

## Steps

1. ~~Scripted-carrier mode, protecting, defenders tracked; the instrument.~~
2. ~~Fit and compare: race, overlap, time in reach, entries; momentum,
   pursuit, interception and blends.~~
3. **`AIStripOdds`** (`Scripts/domain/ai/strip_odds.gd`, a leaf): the odds a
   defender is within the radius of a point at a time, a path's expected strips
   and keep, and a dwell's. Unit properties; a truth file
   (`tests/unit/ai/data/strip_odds_truth.txt`, written by the instrument) and a
   default-tier gate scoring the model against it, its ranking and calibration
   as ratchets.
4. **Swap the reads**, one family per commit, the default tier, the entry and
   breakout drills and `test_entry_read_stability.gd` after each:
   `AICarrySpace` core (`carry_safety`, `carry_crossing_keep`,
   `carry_strip_point`) → the carrier's searches (`_rolled_safety`, stand,
   candidates, `_end_worth`, the wheel) → `AIPossessionValue` (`_line_keep`,
   `_skate_keep`, `_drive_keep`) → reception and holds (`catch_clear`,
   `_dwell_keep`, `mid_clear`, protect and seam reads in `carrier.gd`,
   `support.gd`). Benchmarks before and after.
5. **Retire** what the swap leaves unread (list above).
6. **Test audit.** Every pinned behaviour rerun over jittered setups; one that
   holds ~90%+ is pinned, a near tie is not pinned as a pick. Each tagged with
   the doctrine line it encodes; the ones that tie to none go to the user.
   Snapshots re-pinned after it, not before.

## Open questions

- Bots, not humans: every number is measured against our defending bots. A
  human defender will strip, step up and angle differently.
- The defender's decisions (the families left in the model, above).
- Shot-model defender positions at follow-up times; pass lanes on the fan.
