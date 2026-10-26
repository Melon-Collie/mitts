# Grounding the bots' physical reads

Status: **agreed direction; phases 1 and 2 done; phase 3 in progress (below,
"Phase 3 so far").** The CLAUDE.md workflow
applies: this doc is the plan, deviations get discussed first.

## Why

The bots' rule (`Scripts/domain/ai/CLAUDE.md`, "Evaluators model perception,
never feel") is that every read is a grounded physical model. The test of that
rule this plan works from: **if adding detail or a better understanding makes a
behaviour worse, something else is wrong** — find it and fix it, never back the
detail out. A model that only plays well while it is wrong somewhere else is
two faults holding each other up.

Timing the zone-entry read honestly (the carrier's leaf read when he gets
there, `81d18257`) made breakout rims worthless, and the fault was not the
timing but the entry race it exposed. That prompted an audit of every place a
bot decides on whether a skater can get somewhere, touch something, cover
someone or win a race, against four checks:

- **(a) momentum** — the arrival clock (`AIArrival.time_to_arrive`),
  `AIStrideRamp`, `AILoosePuckChase.reach_meet_time`,
  `AICarrySpace.reach_clearance` — not straight distance, `distance / speed`
  or a fixed metre threshold standing in for "can get there";
- **(b) own build** — the skater's `AISkaterCaps` (`RoleContext.caps_by_peer`,
  memoized per player by `PlayerRegistry`), not league defaults;
- **(c) stick reach** — touching the puck, lane or man by the stick, not the
  body;
- **(d) where they will be** — momentum and the ability to stop or turn, not a
  frozen spot or a constant-velocity drift.

The core physics reads pass: the loose-puck election, the chase's
`_lead_intercept`, the pass lane on the arrival clock (`AILaneReach`), carry
safety. The faults are in the plumbing into them and in the gates and
tie-breaks around them. They fall into six patterns.

## The patterns

### 1. Partial builds into the arrival clock

`time_to_arrive(from, dest, vel, max_speed, accel, lateral_grip)` defaults every
omitted argument to the league reference. Of its 37 calls (audited on
`c2352a3c`): 7 pass no build, 16 pass top speed only, 8 speed and accel, 6 the
full build. So most "per-build" races run the skater's own top speed with league
acceleration and grip. `AIActionScoring.first_arrival` — under every
`arrival_race` — takes no build at all.

| Site | Decides |
|---|---|
| `possession_value.gd:149,180,297,307` | the zone-entry skate, the skate keep, the drive |
| `action_scoring.gd:352` (`first_arrival`) → `possession_value.gd:156`, `carrier_pass_search.gd:565` | the entry race; the bobble race (drops `opponent_caps` it holds) |
| `action_scoring.gd:423,469,486` | the counter-rush race home |
| `threat_assignment.gd:127,203` | man coverage reachability |
| `role_slots.gd:310`, `role_slots_5v5.gd:161,441,445` | slot elections (PRESSURE, CHASE, F1, TRACK_PUCK) |
| `rush_read.gd:228,275,322,369,376,384,437` | the rush read's races and backpressure |
| `loose_puck_chase.gd:209,216,316,569` and the election's league `SHED_ACCEL` (`:439,480,511,524`) | loose-puck races, reach band, containment gate |
| `lane_reach.gd:83` | the lane block's arrival (grip omitted) |
| `carrier_field.gd:508,526` | the drive-in reach (grip omitted) |
| `defenseman.gd:293` | the line-fill race |
| `skater_agent_reception.gd:226,451` | can I reach the stance / the net-facing catch in time |

Also league builds where the build is in hand: `carry_space.gd:571`
(`best_evade_point` on league `MANEUVER_ACCEL`), `rim_pass.gd:134,244`,
`press_read.gd:41,57` (league movement config while `caps.movement` exists),
`action_scoring.gd:393` and `role_slots_5v5.gd:163` (brake-to-set margin at
league top speed), own stick at league reach in `pressure.gd:127`,
`rush_read.gd:333` and `skater_agent_state_machine.gd:3463`, and
`SkaterAgentStickPlay` applying the asking bot's own reach to every other
skater (`skater_agent_stick_play.gd:186-200,254`).

**Fix:** one `AIArrival` entry point that takes an `AISkaterCaps` (null is the
league build), and an optional caps array on `first_arrival` / `arrival_race`.
Every call site above passes the build it has.

**Done (phase 1):** `AIArrival.time_to_arrive_caps`; `first_arrival` /
`arrival_race` take caps; the loose-puck reads (`path_intercept_time`,
`reach_meet_time`, `puck_comes_to_reach`, the containment gate) and
`AILaneReach.block` take the full build; `AIPossessionValue` races each
defender's build and times its man on `man_caps`, which the carrier's leaf, its
receivers and the outlet and breakout stations pass; `AIRimPass.meet_time`
takes the receiver's caps; `best_evade_point` the carrier's thrust;
`AIPressRead` each body's movement config; PRESSURE's pass stand and the chase's
goal-side shade the bot's own reach; `SkaterAgentStickPlay` each skater's reach.
Every direct `time_to_arrive` call now passes speed, thrust and grip.

**Carried on:** the brake-to-set margins at league top speed went with the
counter-cover rework (phase 2, below). Still open: the DZONE cover envelope at
league reach (`AIRushRead.cover_envelope_m`, a shared static; phase 4) and the
defence's threat reads (`threat_of_carrier`, `threat_of_feed`), whose callers
hold positions without peers, so they still time the man on the league build
(phase 3, with the entry read they share).

### 2. Depth comparisons standing in for "somebody is home"

- `last_man_discipline.gd:177` `has_support_behind` — any teammate a
  centimetre deeper, at the far boards or skating up-ice at full speed, ghosts
  included. Gates the body-check commit (`pressure.gd:30`), the last-man lunge
  bound (`pressure.gd:83`), D1's step-up (`rush_d.gd:509`) and the numbers half
  of `may_hold_forward_stand`. **High.**
- `rush_read.gd:269` — a teammate counts INSIDE by radial distance alone, even
  skating up-ice; feeds `numbers`, rush-D posture and the 2-on-1 dive.
- `loose_puck_chase.gd:566-568` containment ("a mate 2 m goal-side in Z");
  `defenseman.gd:282-285` `_pinch_is_covered`.

**Fix:** each is a race, as `_attacker_behind` already reads attackers
(`race_depth_to_net`): can this teammate be goal-side of the play in time.

**Done (phase 2), `has_support_behind`:** two questions, both races on each
body's arrival clock, ghosts never counting. *Is anybody home if he beats me?*
(`has_support_behind(ctx, ap)`, the check commit and the step-ups) — a teammate
reaches a point of the threat's run at our net, past us, before the threat does.
*Am I the body to pick up the man behind?* (`_mate_better_placed`, folded into
`_attacker_behind`, the stations' hold) — a teammate takes a bigger lead on that
man's run than we can, ties to the lower peer id, so exactly one body draws him;
our carrier is never a candidate. The rest of this pattern
(`home_layer_behind_me`, `rush_read.gd:269`, the containment gate,
`_pinch_is_covered`) is phase 4.

### 3. Fixed distances standing in for reach or a contest

- `skater_agent_state_machine.gd:2045,2250` — a charged shot or pass is
  cancelled if any opponent's body is within 2 m in the forward half-plane
  (`BOT_WRISTER_BAIL_RADIUS_M`): a still defender at 1.9 m kills a release the
  compete priced clean; a charger at 4 m and 9 m/s does not. **High.**
- `carry_space.gd:698-741` `carry_lane_clearance` — a multiplier on every carry
  candidate: a flat 1.8 m radius, a linear ramp (a shaped curve), defenders at
  constant velocity, no reaction, ramp, build or stop, stacked on
  `carry_safety`. **High.**
- `skater_agent_state_machine.gd:1512-1521` "contested" loose puck by any body
  within 2 m; `skater_agent_board_play.gd:279` 2.5 m pin-threat pre-filter;
  `body_check.gd:71` 6 m range; `finisher.gd:239` one-timer ready within 1.5 m at
  any speed; `skater_agent_state_machine.gd:1882,1904` the swing side's 2.5 m
  measured from a blade with a body-sized constant.

**Fix:** reach against time — `reach_clearance` for "can he touch it", the
arrival clock against the charge or flight time left.

**Done (phase 2), `carry_lane_clearance`:** deleted. `carry_safety` already
prices every carry on the reach model (the crossing band, the transit and dwell
samples, each defender's build); the one read it had no safety for, the rest of
a rolled move's trip to its destination (`_end_worth`), reads `carry_safety`.

### 4. Targets frozen where they are, or drifted at constant velocity

- `skater_agent_reception.gd:350-358`, `skater_agent_one_timer.gd:172-181` —
  whose feed it is: teammates drifted at constant velocity, raw distance to the
  puck's straight line; a rim comes to nobody, and the one-timer man's line
  goes INF mid-windup. **High.**
- `threat_assignment.gd:126-128` (anchor from the man's frozen spot,
  `team_brain.gd:320`) and its `1/(1+t)` reachability (a shaped curve).
  **High/medium.**
- `role_slots.gd:310`, `role_slots_5v5.gd:441-445` race to the puck's frozen
  spot; CHASE can disagree with `AILoosePuckChase.elect`, which walks its path.
- Receiver stations read lanes with defenders frozen and the league pass speed —
  `breakout.gd:82-85`, `outlet.gd:91-94`, `breakout_center.gd:36-43`,
  `high_slot.gd:50-70`, `support.gd:102`, `finisher.gd:220-222`,
  `defenseman.gd:141-143` — while the carrier prices the same lanes with
  velocities, the accurate model and blades (`carrier_pass_search.gd:432`).
  Receivers stand in lanes the passer reads closed.
- `defensive_verbs.gd:215,250`, `forecheck.gd:122,176` — `threat_of_feed` with
  the receiver's velocity zero.
- `rush_read.gd:314-323` backpressure to a frozen 0.3 s lead, to the body;
  `rush_d.gd:548-557`, `track.gd:159-176` the man picked by his lead's x;
  `pin_threat_read.gd:35` constant closing speed; `skater_agent_reception.gd:391`
  `read_shot` from the bot's current spot; `skater_agent_stick_play.gd:110` the
  jab with no lead.

**Fix:** the momentum-projected or path-walked target the core reads already
use (`AILoosePuckChase` walks, `AICarrierField.project_opponents`, the
receiver's skating point on the arrival clock).

**Done (phase 2), receiver stations:** `AIRoleReads.collect_feed_defence` /
`feed_origin` / `feed_speed` / `feed_lane` give every station the carrier's own
read — his release point, the defence and its blades carried to the release on
their velocities and builds, the accurate lane model, his launch
(`test_a_station_reads_the_feed_its_carrier_reads` holds the mirror). The
outlets price a spot as the passer prices the feed (`AIRoleReads.feed_ev`:
completion × our possession − interception × theirs at the loss point), by
possession alone while no lane is open (`AIFeedStationPick`); the 0.15 floor on
dead lanes is gone. Shot lanes from a station (`high_slot.gd`, the point) are
still read off a frozen defence: phase 4.

### 5. Momentum or burst left out

- `body_check.gd:77-87` — the checker as a projectile already at top speed
  (`intercept_time` without his velocity); impact predicted at top speed.
  **High.**
- `last_man_discipline.gd:222-225` `settable_stand_depth` — no carrier burst
  (`approach_speed_cap` without `threat_vmax`/`threat_accel`, which
  `set_advance_cap` passes), and no bound at all for a carrier not closing.
  **High/medium.**
- `action_scoring.gd:411,534` `fill_counter_cover_etas` and its fallback —
  straight distance over league top speed; `:537-539` the carrier's own
  recovery over his top speed; `counter_time` (`:472,489-492`) carries at top
  speed from the start, the outlet from rest, the feed at league wrister speed.
  SUPPORT's last-man check (`6c0b88e4`) runs on these.
- `finisher.gd:78-86` reactive tip: chases any 12 m/s path crossing its z inside
  2 s, with no arrival check or reach. `defenseman.gd:260-265` pinch race to the
  carrier's body, escape at `depth / out_speed`.
- `shot_block_read.gd:108`, `press_read.gd:41,57` best-case `½·a·t²` with no
  reaction or speed cap.
- `skater_agent_board_play.gd:184-192` support race by `distance / speed`
  (doc'd as deliberately momentum-blind; still a fixed-speed race).

**Done (phase 2):** the counter-rush race — each teammate's time to stand set
at the counter point is his arrival on his build and momentum plus his own brake
from top speed (`AIArrival.set_margin_s`, which RUSH_D1's feasibility deadline
also charges per body); the carrier recovers from a standstill at the
candidate; the collector carries on from the pace he collects at; an outlet is
home once both his run (on his momentum) and the collector's hardest feed are,
and the collector never feeds himself. `settable_stand_depth` takes the man on
a loose puck (`loose_puck_driver`), who bursts on his build the moment we
commit, so a still puck binds too. Still open from this pattern: the body
check, the reactive tip, the pinch race, `shot_block_read`, `press_read`'s
best case and the board-play support race (phase 4).

### 6. The zone-entry picture

The worst instance, all patterns at once. Its own section below.

## Zone entry

### Done

- `98d6d1a8` — the carry search reads the incumbent move two steps deep, as
  deep as its challengers.
- `81d18257` — the zone-entry leaf (`AICarrierField.horizon_value`) is read
  when its man gets there: arrival time and velocity into
  `AIPossessionValue.at`, its discount of the trip divided back out. The carry's
  moves and destinations and `receiver_drive_in_value` (a receiver's drive
  starting when the feed reaches him) read it so. Entry drill: carried
  24 → 29 of 30, passes before entry 23 → 7 (backward 17 → 5). Breakout level.
- `c2352a3c` — property tests for both.

### Stashed (`stash@{0}` in the working session; re-apply as described)

Two more timings, consistent with the above, are in (phase 3):

1. **The receiver read on the carry's clock.** `AICarrierPassSearch._pass_ev`
   reads his possession when the carry's first step is, or when he has the puck
   if later, where his skating has him then (`_possession_on_clock`); his shot
   off the feed (`AICarrierField.feed_shot_at`) and his drive in at the catch.
   A bobble credits his drive or possession once regathered, not the shot.
2. **Turnover costs read when the loss happens.**
   `AICarrierField.turnover_cost(loss_point, loss_prob, loss_s = 0.0)` reads
   `_theirs.at(loss_point, loss_s)`. Times: a pass's release poke 0; its lane
   loss at `AIPuckLane.traverse_time(origin.distance_to(loss_point), pass_speed)`
   (a public wrapper on `_friction_traverse_time`), capped at the flight; the
   miss at the flight; the reception strip at flight + settle. A rolled move's
   strip at `_strip_t` (set by `_rolled_safety`: the leg's start plus the
   strip's share of it); a straight candidate's at `local_time` × the strip's
   share of the path; the wheel's by `AICarrierWheel._leg_share`;
   `_drive_loss_cost(..., loss_s)` relative to the drive's start, as the drive's
   value is discounted.

### What is wrong with the entry read (`AIPossessionValue`)

1. **First there vetoes the entry.** `arrival_race` is the loose-puck rule —
   first to it gets it — applied to a carried puck. A defender who gets to an
   entry first must still stop the carrier; the entry drill's carriers beat a
   defender set at his line almost every time.
2. **One defender covers all three entries.** Each entry races every defender
   independently, so two defenders standing at their line zero every
   neutral-zone spot.
3. **A defender near the line is charged three times** — in the entry's own
   worth (the drive from it is stripped by him), the race, and the skate keep's
   end sample when the carrier starts within `DRIVE_MAX_M`.
4. **Entry worth is priced against the defence as it stands now**, cached per
   fill — a forechecker deep in our end never matters, a defender at his line who
   will have backed into his slot always does — and the drive from the entry
   starts from rest, not at the pace he enters with.
5. **Three fixed entry points.** A carrier crosses anywhere along the line.
6. **The value changes model at the line.** Just outside, a spot is worth our
   possession (entries to come, drives); just inside, only its shot, plus one
   straight drive when reached from outside (the entry continuation). The
   defence reads the same carrier in the zone as the better of his shot and his
   possession (`threat_of_carrier`): two currencies for one spot.
7. **Standing still reads the current spot now, from rest**
   (`AICarrierCarrySearch.search`'s stand), while every move is read on arrival.
8. **Two models of where a defender will be** — `AIPossessionValue` drifts
   defenders at constant velocity; `AICarrierField.project_opponents` lets a
   defender backing off ahead stop.
9. An in-zone receiver's entry credit (`AICarrierField.entry_value`, start =
   flight) discounts the flight twice: in the read and in the pass benefit.
10. The leaf credits entries a carrier may not take while a teammate owes a
    tag-up (`zone_entry_blocked`); the drive-in checks, `horizon_value` does not.

The defence (`threat_of_carrier`, `threat_of_feed`), the outlet and breakout
stations already read possession on arrival, so every change here moves how they
judge a threat too.

### The rebuild

- **The entry is a contest at the line, not a race to a spot** (option 2,
  agreed). The carrier chooses his side late; a defender who has got there
  first must cover that last move — his reaction, lateral push and stick reach
  against the carrier's lateral grip and pace — read against the defence as it
  will be when the carrier arrives. The line is continuous, not three points.
  Every input is a physical quantity already in the build.
- Each defender is charged once; the entry's follow-up (shot, drive) starts at
  the carrier's entry pace, against the defence then.
- **One leaf on both sides of the line**: possession everywhere, the read the
  defence already uses.
- The stand is read as a move that stays; one projection model for the defence.
- Then the stash, items 9 and 10.

Measured at each step on the rim and feed fixtures, the entry and breakout
drills (`tests/instruments/ai/test_nz_entry_drill.gd`,
`test_breakout_drill.gd`), the slow tier and the benchmarks.

### Phase 3 so far

In the working tree of the commit that adds this section:

- **The entry is a contest at the line** (`AIPossessionValue._line_keep`): no
  race veto. A defender inside his line shadows where the carrier is heading
  (his natural crossing), on the carrier→net line at his own depth, if he can
  get there before the carrier commits, then has the carry-arrival lunge to
  cover the crossing actually taken; one outside the line is projected. Five
  crossings along the line, not three spots.
- **Each defender charged once**: the skate, the line and the drive keep the
  puck at the worst of the three (the `carry_safety` convention).
- **One projection model** (`AIDefenderProjection.at`, which
  `AICarrierField.project_opponents` now calls): a man ahead who is standing up
  or backing off holds his gap, giving ground down the carrier's line as the
  carrier gains it, down to the top of his house — except a forechecker in the
  carrier's own zone, who holds his ice; one stepping up carries on until level
  with the carrier; one behind the play backchecks to the top of his house on
  the arrival clock. His
  velocity is projected with him (`AIDefenderProjection.vel_then`), so the reach reads see a
  backchecker skating home, not his old heading.
- **The entry's follow-up against the defence as it will be**: priced at
  `FOLLOW_UP_TIMES` (0, 1, 2, 4 s) and read between them.
- **One leaf on both sides of the line**: the carrier's value of a spot is the
  better of his shot there and our play on from it
  (`AIPossessionValue.play_on`, no second keeper read for the shot), so the
  surface no longer changes model at the line. In-zone entries count only ahead
  of the man (no curl back up into a defender who is projected to stop).
- Items 9 and 10: the in-zone receiver entry credit is gone (one leaf covers
  it); no entry is ours before an owed tag-up is made (`_tag_up_time`).
- Not yet: the stash re-applied, the threat reads on man caps, the stand timed.

- **The defence read in numbers** (`AIDefencePairing`): each defender is paired
  to the attacker he gets goal-side of soonest — the puck's holder always, then
  the men level with or ahead of the puck — and one paired to a man other than
  the holder rides him through the read; the rest play the puck.
- **The men inside the line are the line contest's alone**: the skate to the
  line is priced against the men outside it. Charged through the skate's reach
  read as well, the same set defence cost a man near the line more than one
  further back, so the puck went back to whoever was furthest from it.

**Where it stands.** Default tier green (re-pinned: carrier, role_breakout,
counter_rush snapshots; fixtures corrected where they leaned on the old race).
Entry drill: 30 of 30 carried with 4 passes at phase 2; 27 carried, 20 passes
(12 backward) now, the 3-on-2s near clean (15 of 15 carried, 3 passes) and the
passing left in the 3-on-3s. Breakout 17 of 20 exits in 2.67 s (2.92 at phase 2).

**What the 3-on-3 passing is.** Traced decision by decision: against an even,
set defence every neutral-zone option reads 0.03–0.05 — the first shot an entry
gets — and what separates them is the time discount, so a feed that arrives in
half a second beats a carry step priced a second out, backward or forward. The
read counts only that first shot, so gaining the zone is worth little more than
staying out of it. Open: what a real carrier is carrying in FOR at even
strength, and whether the open man's credit (agreed, not yet built) is still
wanted now that the 3-on-2s carry.

### The temporal audit

Every read checked for the world being sampled at a different moment from the
event it prices, or two competing options priced at different moments. Found,
ranked within each layer; [x] done.

**Evaluators and the carrier's compete**
- [x] Defenders "ahead" of a carrier judged by depth alone: a man level in z but
  in the middle read as beaten by a wide carrier, so a step either way flipped
  the in-zone value 0.35 → 0.04. Now goal-side along the carrier's line to the
  net (`AIDefenderProjection.at`).
- [x] `AICarrierField.project_opponents` passed the attack's sign as the goal's
  depth, so the carrier's backcheckers skated for the far blue line.
- [ ] `project_opponents` projects positions but hands the reach reads current
  velocities (ply-2 `_rolled_safety`, the carry-on, the wheel's second leg,
  `receiver_drive_in_value`): a man projected to a stop still moves at 6 m/s.
- [ ] A defender backing off ahead is projected to stop dead within ~0.7 s and
  stand: a wall at every follow-up time, the main cliff in time.
- [ ] Inside `carry_safety` the puck moves at a uniform `dist/T` and the
  mid-sample is the midpoint at T/2, while T ramps: from rest the pursuit time
  is ~28% short.
- [x] The keep bands (0.5–1 m) were narrow against reach growing ~10 m/s per
  second of horizon, so reads were cliff-shaped in time. `reach_clearance`
  reports the binding man's arrival-clock error in ground (`reach_band_m`: his
  commit window at the speed he is closing with as it ends, plus a projected
  trip at his speed then) and the safety maps widen to it. Entry read 1 s
  prediction error 0.44 → 0.37, local spread 0.11 → 0.12. Open: against a
  square defender at the line the flatter read lets the carrier chase a lateral
  cut the defender mirrors (`test_nz_carry_keeps_pace` gap 10 m).
- [ ] `delay_discount` charged on reads whose defence is already projected to
  that time (entries, drives, the counter cost): time paid twice.
- [ ] Stand-still outside the zone reads the defence now while every move reads
  it at 1 s; its safety over 0.4 s against the moves' 1 s.
- [ ] A destination reached from a move's end keeps its straight-carry value;
  the wheel prices its play-on at 0 s after a ~3 s trip.
- [ ] The developing-feed hold: priced as if fired now, the wait uncharged, a
  different pass model from `_pass_ev`, the spot never converging.
- [ ] The pass clock leaves out the windup and the facing rotation.
- [ ] Shoot-now holds that need a pull read the defence and keeper at the
  windup only.
- [ ] The pass option values receivers and lanes frozen now for a release ≥1 s
  later (the 0.8 haircut stands in for it).
- [ ] `score_pass_value` uses one defender array for the flight and the catch;
  `threat_of_feed` / `_shot_defender_terms` read lanes with no velocities.
- [ ] `at()` reads the shot from the spot now and the drive later.
- [ ] The pairing is frozen at t = 0; a priced man's own rider follows his
  straight line rather than the read's skate.
- [ ] Counter exposure ignores when the loss happens.
- [ ] `AIDefenderProjection.at` classifies against the drive's start, not where it is.
- [ ] Loose-puck walk treats its 3 s end as settled; goalie re-square from rest.

**Off-puck roles and the brain**
- [ ] SUPPORT / TRAILER / OUTLET / BREAKOUT incumbents are fixed ice points while
  their candidates ride the carrier (the PRESSURE bug again).
- [ ] `backpressure_s` races a tracker to a fixed hip, not the moving one.
- [ ] Threat partition: men read now, defenders timed into the future; danger
  read at the man's spot with no flight; the house incumbent never re-raced.
- [ ] `cover_man_target` prices a candidate standing, publishes a ride.
- [ ] Recovery INSIDE tests (`rush_read`, `home_layer_behind_me`) are positions,
  not races.
- [ ] Receiver stations priced as if the receiver were there already.
- [ ] MARK's memo bases are not upper bounds but drive an exact prune.
- [ ] Defensive receiver leads a fixed 0.3 s, not the feed's flight.

**The agent layer**
- [ ] Counters count calls, not ticks: a late AI batch stretches charges, slew,
  lag filters; the puck lead for input latency is one tick of two.
- [ ] The jab window stretches on slower tiers (Easy pokes longer than Hard).
- [ ] The engagement cooldown reads the debounced carrier for the bot's own
  strip.
- [ ] The stick tie reads the man where he is, not where his skating takes him.
- [ ] The 2-on-1 dive commits on current geometry.
- [ ] Board play and the stand-up have no perception lag, despite their docs.
- [ ] The one-timer feed clock is capped and frictionless.
- [ ] `gives_with` uses the puck's velocity now, not at the gate.
- [ ] Pass pace committed at charge tick 0, before the windup brake.

### Open

- **Phase 2 findings, to re-measure after this rebuild.** With the receiver
  stations on the passer's read, the breakout drill's exits slowed (18 of 20 in
  2.17 s → 2.92 s): an outlet who has the puck now often feeds across to the
  other winger, whom the new read stands where the lane really is open, rather
  than carrying out — the passer prices that feed above the carry, which is
  this section's possession read. And two 2-on-1s in
  `test_advantage_scenarios.gd` fail: with his feeds read honestly the
  finisher's tip station wins, he cuts across into the slot at ~9 m/s, and the
  carrier feeds him a pass that arrives too hard to catch (the passer prices
  the bobble and still rates it 0.685), and a shot from 12.06 m against the
  12 m bound. The reception half is phase 4's "whose feed it is".
- `tests/slow/ai/test_nz_turnover_recovery.gd` contains 14 of 36 since
  `81d18257` (floor 16): the carrier beats a caught-flat defender more often.
  Re-measure after the rebuild and pattern 2 before touching the floor — the
  defender's support and race reads are on this list too.
- One of the 30 entry starts still feeds back from 3.3 m short of the line at
  pace.

## Phases

1. **Plumbing** (pattern 1): the full-build arrival entry point, caps-aware
   `first_arrival` / `arrival_race`, every partial call routed through it,
   `SkaterAgentStickPlay` looking up each skater's own reach. Mechanical; what
   every later phase stands on.
2. **Shared helpers with many dependents**: `has_support_behind` as a race;
   `carry_lane_clearance` folded into the reach model; the receiver stations'
   lane read made the passer's; the counter-rush cover on the arrival clock;
   `settable_stand_depth` with the carrier's burst.
3. **The zone-entry rebuild** above.
4. **The agent-layer gates**: the release bail, the contested loose puck,
   whose feed it is, the body check, the pin threat, the stick tie, and the rest
   of patterns 3–5.

Each phase: the default and slow tiers, the entry and breakout drills, the
benchmarks before and after, snapshot moves reviewed and named in the commit.
A behaviour that gets worse is a finding, not a reason to back the change out.
