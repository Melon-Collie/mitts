# Possession floor — what keeping the puck is worth

Status: **steps 0–4 landed; steps 5–6 open, and host AI cost open (§6).** The CLAUDE.md workflow applies: this
doc is the plan, deviations get discussed first. Supersedes an earlier
data-driven draft: no external data, no generator, no generated file.

## Decisions

- **Possession of a spot is worth the better of two reads**: the best play the
  defence allows right now (today's `AIPossessionValue`, unchanged), and the
  **continuation**, what keeping the puck there is worth over the rest of the
  possession. Max, never sum: the live read already sees the defence, the
  continuation does not.
- **The continuation is a floor plus a slot bonus:**

  ```
  C(spot) = floor(a) + bonus(spot)
  bonus(spot) = SLOT_BONUS · min(1, mouth(spot) / mouth(SLOT_REF_M))   in their zone, else 0
  ```

  `a` is how far up the ice the spot is toward the attacking goal; the floor is
  piecewise linear, bending at the blue lines, and flat across the attacking
  zone. `mouth(spot)` is the angle the net mouth covers seen from the spot (the
  opening between the posts): what a shooter sees, growing as he gets closer
  and squarer, 0 behind the goal line. The bonus plateaus at `SLOT_BONUS` from
  `SLOT_REF_M` straight out and in, so it marks the slot without spiking at the
  crease, where the live shot read already does the work.
- **No shot field in the continuation.** The set-keeper cells are each one
  staged keeper, priced at their best aim under a narrow scatter, so they read
  close to all-or-nothing (83% next to 0% a cell over) and inherit every hole in
  the grid. That is the right input for aiming now against the keeper in front
  of you, which is the live read's job; it is the wrong answer to what a shot
  from here is worth on average. The bonus is the smooth, goalie-free stand-in.
- **Seven feel tunables, not measurements.** The floor's four anchors,
  `SLOT_BONUS`, `SLOT_REF_M` and `REBOUND_RECOVER_SHARE` (§2.3) are judgment
  about how the game should play: what possession is worth before anything
  specific is on. They live with the other feel tunables (`DECISIONS.md` §7) and
  are tuned in playtests. Starting values in §2.1.
- **Why so few numbers is enough:** an exploratory fit of a full possession
  model showed that a floor by position plus a shot-shaped term reproduces about
  97% of its variation, and little else is in it. The decision-relevant facts are
  the floor itself (possession in their zone is worth something everywhere,
  roughly the same everywhere), its gentle rise through the neutral zone, its
  sign in our own end, and the slot's premium.
- **The continuation is independent of the goalie.** Neither term reads him, so
  killing one shot location cannot collapse a behavior: the live read loses that
  shot, the continuation does not move.
- **The opponent's continuation is the same function from his end.** A turnover
  costs his C at the loss spot: negative deep in his own end (losing it there is
  nearly free, and that is the forecheck's value), and carrying his slot bonus
  in ours (losing it in our slot costs more than on the wall).
- **A read that goes stale decays toward the continuation, not toward zero**
  (§2.4). This is the counter to the stand-still trap.
- **3v3 and 5v5 share the same values.**
- **Numbers-up stays out of scope.** The floor is even-strength. The live read
  pricing the pass option on a rush is separate work, and the `numbers_up`
  no-dump rule stays until it lands. This plan is the fix for #892 (a won
  corner priced at ~0) and the possession half of #785.

## 1. Why

The trigger: a bug let some point shots beat the goalie. Fixing it made point
shots worth ~0, and the bots stopped entering the zone. Nothing else was holding
the zone's value up.

`AIPossessionValue` prices a spot as the best of the shot from it, one straight
drive in, and three entry spots: the **first shot** the side can get to. It is
one man, it ignores passes, and it stops at the first shot; in the zone
`AICarrierField._regime_value` is "pure odds, no possession floor", and rebounds
are not in the shot field (#785). So keeping the puck is never worth anything in
itself, and every decision that depends on possession inherits that:

- **Cycling.** Below the dots, on the half-wall and behind the net, the shot is
  worth ~0, so those spots are worth only the pass option they open. Retaining
  possession never competes with forcing a low-odds play.
- **Dump and chase.** A won race behind their goal line is worth 0 on its own,
  which is why `AICarrierDumpSearch` dead-reckons a feed to our support to give
  the dump any value.
- **Entries.** An entry is worth the shot or the drive from one of three spots,
  so a controlled wall entry with no drive lane is worth almost nothing. The
  workarounds around this: the entry continuation
  (`docs/zone-entry-currency-plan.md`), and the rule that a straight carry
  across the line is not credited from outside.

The floor gives all three what they are missing, through the one read every
consumer already uses.

## 2. The design

### 2.1 The floor and the slot bonus

`a` = `pos.z · signf(goal.z)`: metres toward the attacking goal (their goal line
at +26.65, their blue line at +7.29, ours at −7.29, our goal line at −26.65).
The floor is linear between the anchors and flat past each goal line. The bonus
applies only in their zone (`AIActionScoring.in_offensive_zone`).

| tunable | what | starting value |
|---|---|---|
| `FLOOR_OWN_GOAL_LINE` | floor at a = −26.65 | −0.012 |
| `FLOOR_OWN_BLUE_LINE` | floor at a = −7.29 | 0.004 |
| `FLOOR_THEIR_BLUE_LINE` | floor at a = +7.29 | 0.023 |
| `FLOOR_THEIR_GOAL_LINE` | floor at a = +26.65 | 0.021 |
| `SLOT_BONUS` | the bonus's plateau | 0.05 |
| `SLOT_REF_M` | metres straight out where the plateau starts | 6.0 |

What those say: possession in our own end is worth slightly less than nothing
(a turnover there is expensive); it rises through the neutral zone, about 0.13
points per metre; possession in their zone is worth about 2% anywhere, plus a
premium for how much net it sees. No lateral term in the floor: the bonus
carries middle-versus-wall.

The mouth angle from (x across, y out from the goal line), posts at ±0.915
(`GameRules.NET_HALF_WIDTH`):

```
mouth = acos( ((−0.915 − x)(0.915 − x) + y²) / (|(−0.915 − x, −y)| · |(0.915 − x, −y)|) )   for y > 0, else 0
```

At the starting values:

| spot | mouth | C |
|---|---|---|
| slot, 4–6 m out | 17–26° (plateau) | 7.1% |
| 10 m out, centred | 10.5° | 5.2% |
| top of the circle | 6.4° | 4.1% |
| point, centred | 5.5° | 3.9% |
| half-wall | 4.4° | 3.5% |
| low corner | 1.6° | 2.6% |
| behind their net | 0° | 2.1% |
| just outside their line, centred | — | 2.3% |
| neutral zone, centre | — | 1.4% |
| behind our net | — | −1.2% |

Both terms are pure functions of position, so the whole continuation is a leaf
(§3, step 1).

### 2.2 The live continuation

The floor is the value of a possession the carrier keeps. The live read knows
how likely he is to keep it and where it goes if he does not:

```
base(spot) = keep · C(spot) − (1 − keep) · C_opp(strip)
```

- `keep`: the carrier's **evadability**, the odds he can keep the puck at all,
  in whatever direction: `reach_clearance` at the max-clearance seam
  (`AICarrySpace.best_evade_point`) over `EVADE_HORIZON_S`, through
  `clearance_to_safety`. It is the read `AIRoleCarrier._pick_fire_phase`
  already makes as `_phase_current_safety` for the hold's keep odds. **Not** the
  drive's keep (`carry_safety` / `_skate_keep`): that prices one play, skating
  at the net through whoever is in the slot, and reads ~0 at the point whenever
  a D stands in the middle, which is the drive being closed, not the puck being
  lost. The continuation is the value of playing on in any direction; the drive
  is one of the live reads it is maxed against.
- At a spot other than where the carrier stands now (a carry candidate's end,
  an entry, a receiver's spot), the same read there: the seam from that spot at
  the arrival velocity, against the defence projected to the arrival time
  (`AITrajectory.predict_at`, as `_drive` already projects it). A stand-still
  candidate over the equal horizon (§2.4, 3) reads it against the defence at the
  horizon's end, which is where a defender closing on a carrier who waits
  shows up.
- `strip`: the puck's spot (`AICarrierField.puck_pos_at`). The evade read has
  no path, so a puck he cannot keep is lost where he holds it. `C_opp` is the
  same function for the other side there: his floor, and his slot bonus when the
  spot is in our zone.
- Pinned on the boards, the seam search loses half its envelope
  (`board_gap_m`) and `keep` collapses, as it should: a wall-pinned carrier is
  about to lose it.

`C_opp` is the static function, never the other side's live read, so there is
no recursion.

### 2.3 Where it plugs in

- **`AIPossessionValue.at`** (both sides, every consumer): the result becomes
  the better of today's reads and `base`, each read decayed as in §2.4. Because
  this is the one read of possession for both sides, the turnover cost
  (`AICarrierField.turnover_cost` → `_theirs.at`), the dump's "ours at the
  meet" (`possession_at`), the receiver's spot, the horizon leaf
  (`horizon_value`) and the defence's `threat_of_carrier` all change with it.
- **`AICarrierField._regime_value`** in the zone: `max(shoot_s, base)`. The zone
  plan rejected a possession floor in the zone because the old potential map
  was on another scale and won everywhere; this one is in the shot currency, and
  `SLOT_BONUS` is sized to sit below a real chance from the slot (§2.6).
- **The shot gets rebound credit.** First contact alone makes keeping the puck
  (~2%) beat every shot from range, so the bots would never shoot from the
  point. A shot that is saved or missed still leaves a puck in their zone:

  ```
  shot = p + (1 − p) · REBOUND_RECOVER_SHARE · FLOOR_THEIR_GOAL_LINE
  ```

  `p` is first contact as today. `REBOUND_RECOVER_SHARE` (feel tunable, start
  0.3) is how often our side gets that puck back, credited at the zone's floor,
  not at a shot. It can later be measured instead of chosen (§5).
- **Values can now be negative.** `at()` starts its max at 0.0 today, and the
  carry search's exact ceiling prunes and the entries' empty-ice bound assume
  non-negative values. Audit those before wiring (step 0); clamping at 0 would
  discard the own-end and forecheck information the floor adds.

### 2.4 Time: why the bots will not stand still

The trap: when the decay on a forward move is bigger than the value it gains,
standing still wins. With the multiplicative `delay_discount` (τ = 6 s) it binds
in the neutral zone: the floor rises about 0.13 points per metre, while the
decay on ~1.3% of possession costs about 0.2 points per second. At speed the
move wins; from a standstill, where a metre or two takes about a second, it
loses.

Three things counter it:

1. **The floor has no clock.** It is a value of position, so it never pays
   anyone to wait.
2. **Decay toward the baseline.** `delay_discount` stands for a read going
   stale. A stale read is not worth zero: it reverts to what possession of that
   spot is worth without the specific look. So every discounted read decays
   toward the base of the spot it values:

   ```
   value(read at t) = base(spot) + max(0, read − base(spot)) · exp(−t / τ)
   ```

   The floor's gain from moving forward is never discounted; only the premium
   of a specific open look is. An entry read at t decays toward `base` at the
   entry spot, a drive toward `base` where it ends.
3. **Every candidate is priced over the same horizon.** Standing still is a
   move that lasts the horizon and ends where it started, with the defence
   projected forward like any other move. The carry search already does this
   outside the zone ("standing still outside pays the step's decay like every
   move"); keep it inside the zone too once `base` is there. Compared at equal
   horizons, decay cancels out of the stand-still comparison.

### 2.5 The blue line

The bonus gives their blue line a step: centred, 2.3% just outside and 3.9% just
inside; on the wall, about +1.2 points. That is the pull into the zone the floor
alone lacks, strongest in the middle. The live entry and drive reads, and the
defence closing on a carrier who hovers (his `keep` falls, which the
equal-horizon rule of §2.4 makes count), do the rest. If bots still hover at the
line in testing, raise the step through `SLOT_BONUS` or `SLOT_REF_M` before
reaching for anything new, and never a gate.

### 2.6 The slot plateau and holding the puck

Holding the puck in the slot is worth the plateau (about 7%) times `keep`. Where
the live shot reads less than that, against a set keeper with no opening, the
carrier keeps it: looks for the pass, the deke, the keeper moving. Some of that
is the point; too much is a carrier parked in the slot. Two things bound it:
the defence closing on him lowers `keep` over the equal horizon, and
`SLOT_BONUS` should stay below what a live slot shot usually reads. Step 5's
shot mix and slot-hold time say which side of that line it is on.

### 2.7 What it should make removable

Each is a workaround for the missing continuation; delete one at a time, with
step 5's measurements before and after:

- the entry continuation special case (`docs/zone-entry-currency-plan.md` §2.2);
- "a straight carry across the line is not credited from outside";
- possibly the giveaway bars (`SHOT_MIN_VALUE`, `PASS_MIN_VALUE`): keeping the
  puck now has a real worth for a giveaway to beat.

Stays: the dump's dead-reckoned feed to our support (it is the live,
defence-aware half, and now competes with the floor instead of standing in for
it), and the `numbers_up` rule (out of scope, see Decisions).

### 2.8 Shooting against keeping, worked

The two sides of the carrier's compete (`_pick_commit_phase`: fire if the shot
beats the best carry, pass or hold, ties fire) are priced by different models
after this plan. The shot is the live shot field, unchanged but for its rebound
credit; keeping the puck is the continuation, at the live keep odds:

```
shoot = p + (1 − p) · REBOUND_RECOVER_SHARE · FLOOR_THEIR_GOAL_LINE
keep  = keep_odds · C(spot) − (1 − keep_odds) · C_opp(strip)
```

`p` is first contact from the live read. A carry candidate that moves somewhere
better is worth the larger of the live read and `keep` where it ends, any shot it
sets up decaying toward that spot's base (§2.4). At the starting values, with
illustrative keep odds:

| | point, centred | slot, 5 m out |
|---|---|---|
| C | 3.9% | 7.1% |
| keep odds (assumed) | 0.9, little pressure | 0.6, pressured |
| C_opp where it is lost | about +0.4% (his end, inside his line) | about −0.8% (deep in his end) |
| keeping is worth | about 3.5% | about 4.6% |
| shoots when live first contact exceeds | about 2.9% | about 4.0% |

From the point the bot shoots only when the live read finds a real chance, and
otherwise works the puck; in the slot under pressure the bar is low. Until step
6 tests removing it, `SHOT_MIN_VALUE` (0.05) also applies after the settle
handicap, so the point shot above cannot qualify yet whatever the comparison
says. With the continuation in, the comparison does that bar's job, which is
why §2.7 lists the bar as possibly removable.

## 3. Steps

### Step 0 — non-negative audit

Find every reader that assumes possession values are ≥ 0: `AIPossessionValue.at`
and `entry_at` (the 0.0 start, the `_open_worth` bound), the carry search's exact
ceiling prunes, the giveaway bars' arithmetic, `turnover_cost`'s consumers.
Make each correct for negative values. Its own commit, no behavior change on
today's (non-negative) values; the suite must stay green.

### Step 1 — the floor leaf

`Scripts/domain/ai/possession_floor.gd` (`AIPossessionFloor`): engine-free,
static, reads `GameRules` for the lines and the posts. `floor_at(pos, goal)`,
`slot_bonus(pos, goal)`, `continuation(pos, goal)` (their sum). The six
position tunables as consts there (`REBOUND_RECOVER_SHARE` lives with the shot
pricing, step 3). Tests (`tests/unit/ai/test_possession_floor.gd`): the floor at
the anchors, linear between them, flat past the goal lines; the bonus 0 outside
their zone and behind the goal line, at its plateau inside `SLOT_REF_M`
straight out, falling with distance and with angle; left/right symmetric; and
the frame flip (the same spot read for the other goal).

### Step 2 — the live read

In `AIPossessionValue`: `C` and `base` as §2.1–2.2, the max with today's reads,
every discounted read decaying toward its spot's base as §2.4 (2). In
`AICarrierField._regime_value`: `max(shoot_s, base)` in the zone.
`test_possession_value.gd` gains: a puck below their goal line, on empty ice, is
worth about the floor; behind our net, below zero; a turnover deep in their end
costs almost nothing, and one in our slot costs more than one on our wall.

### Step 3 — rebound credit

The shot term of §2.3 wherever the carrier prices a shot (the value seam's
callers in the compete), with `REBOUND_RECOVER_SHARE`. Watch the shot mix in
step 5: too low and the bots stop shooting from the point; too high and they
throw everything at a set goalie.

### Step 4 — the stand-still horizon in the zone

As §2.4 (3), in `carrier_carry_search.gd`.

### Step 5 — measure

- **The regression that started this**: with point first-contact odds forced to
  0, bots still enter the zone (the entry drill's entry rate within a ratchet
  of normal).
- **No stand-still**: a lone carrier on empty ice anywhere outside the zone
  never picks standing still; and at their blue line with a defender closing,
  he enters or moves the puck rather than hovering (§2.5).
- **Cycle retention** (new instrument): time in possession below the dots, and
  the share of those possessions ending in a shot.
- **Shot mix** (new instrument or a stat off `shot_events`): share of shots
  from the point against the slot.
- **Slot holds** (§2.6): how long a carrier with the puck in the slot keeps it
  before shooting, passing or losing it.
- **Dump recovery rate** (new instrument).
- The existing `test_nz_entry_drill.gd` and `test_breakout_drill.gd`, before and
  after.

### Step 6 — remove the workarounds

§2.7, one per commit, each with step 5's numbers.

## 4. What players should see

Bots that hold the puck low and cycle it instead of throwing it at a set goalie
from the point, but still put pucks on net for rebounds; that dump it in when
the line is clogged; that take the zone along the wall under control; and that
never park at the blue line waiting.

## 5. Open questions

- **Measuring the rebound share.** `REBOUND_RECOVER_SHARE` is a property of the
  goalie and the puck, not of play, so it can be measured: the shot field's
  stager already fires shots at the live keeper; recording where saves and
  misses leave the puck, and which side's nearest body is first to it on the
  arrival clock, turns the tunable into a measurement that regenerates with the
  shot field.
- **Checking the floor.** Possession logs from human games (the `shot_events`
  pipeline is the natural home) can test the floor's shape later: how often
  possessions from each part of the ice end in a goal, and against which side.
  Data the game owns.
- **3v3.** The shared floor is the decision; 3v3's open ice may make possession
  worth more everywhere. Human logs are the way to see it.
- **Starting values.** The floor's four were read off an exploratory fit and
  rounded; the slot bonus's two are new judgment. All of them stand as
  judgment. Replace them freely.
- **The shot field's own shape.** The set-keeper cells read close to
  all-or-nothing (§Decisions). That is out of this plan's scope, but worth
  checking against real outcomes: `shot_events` records xG and goals, and the
  two should agree on average.

## 6. As built (steps 0–4)

- **A read that does not come off leaves the continuation where he stands**
  (`AIPossessionValue._taken`): an entry raced and lost, a skate or a drive
  stripped. Priced as zero, a lost race read above a negative continuation, so
  possession behind our own net could never read below nothing.
- **The rebound is credited on the odds of reaching the net**, before the lane
  and the release contest (`score_shoot_value`'s `rebound`), so a blocked shot
  earns none.
- **The keep odds are the seam's own safety**, read by `AIEvadeRead.evade_safety`
  under exact bounds (~45 µs a read in traffic against ~190 µs for the full
  sweep), and held to `best_evade_point` by `test_evade_safety.gd`.
- **Host AI cost is up.** `benchmarks/` (GDScript fallback, this container),
  AI µs per second of play, before → after: ozone-cycle 3v3 322k → 347k, 5v5
  299k → 457k; nz-rush 3v3 200k → 367k, 5v5 206k → 488k; loose-neutral 3v3
  185k → 346k, 5v5 365k → 497k. Per call, the possession read is 1.5–3×: every
  read adds a keep read, and an entry a defender stands on is no longer pruned
  on its dead live worth, since it still carries the zone's floor. The options
  are a decision, not an implementation detail: read each entry's and each
  drive's end continuation as kept (their race and keep odds already price
  getting there with the puck), memoize the keep read across the defence's
  candidate pushes, or port the sweep to `native/`.

