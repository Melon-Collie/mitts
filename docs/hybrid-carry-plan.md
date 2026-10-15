# Hybrid carry — a far destination, the next half-second rolled out

Status: **agreed design; steps 1–4 done.** The CLAUDE.md workflow applies: this
doc is the plan, deviations get discussed first.

## Decisions

- **Hybrid** (agreed in chat): a far DESTINATION picked from a few places worth
  carrying to, and the NEAR move picked among a handful of real skating inputs
  rolled forward through the movement physics players skate on.
- **What is priced is what is skated.** The chosen input is the carrier's
  `move_vector` until the next re-plan; no steering layer re-derives it.
- **Evasion becomes one question** — which input keeps the puck and makes
  progress — so a carrier with open ice ahead skates straight and faces
  forward because nothing beats it, not because a rule says so.
- **Regroup is on trial**: in the menu until the duels and playtests show
  whether it pays.
- **Every tier runs the same code.** Hard is the basis; easier tiers are tuned
  down from it as needed, not given a smaller input set.
- **7 inputs over 0.5 s** to start; the exact set is settled in step 1.
- Shot-currency step 4 (`docs/shot-currency-plan.md`) waits for this: the drive
  that prices a spot outside the zone should follow a route a carrier takes.

## 1. Why

The user's read: the carry candidates have no basis in what the movement system
can do, carriers get stuck at angles, and the avoidance is complicated enough
that a bot skating forward with no one ahead does not reliably face forward.

What the code does today (`AICarrierCarrySearch.search`):

- **Placement**: ~20 spots — 3 forward bearings × 2 radii off the space fan, a
  10-spot rear ring, the slot anchor, two DZ exit walls, post walkouts, the
  directed evasion seam, two wheel exits.
- **Timing**: `AIArrival.time_to_arrive`, a closed-form model. Its own
  calibration test puts it at ±20%, and up to 2–3× off on short diagonal cuts at
  speed — exactly the moves evasion is made of.
- **Execution**: the anchor goes to `AISteering.compute_move_vector` (a
  velocity-matched seek plus a threat repel, board, crease and net forces), and
  six more layers can move a carrier with no defender near him: the blade
  protect offset, the poke-evade cut, the brake check, the deke, the directed
  seam, the retreat ring. The bot prices a spot without knowing how it will get
  there, and the steering then gets there its own way.

The physics is already a pure function: `SkaterMovementRules.apply_movement`
(velocity in, input in, velocity out; no heap, no state) is what every skater
and the network prediction run.

## 2. The design

### Destinations (far)

A small fixed menu, each a place a carry can be FOR:

| destination | where it exists |
|---|---|
| the slot (drive the net) | everywhere — today's slot anchor |
| the wide lane, each side | outside the attacking zone: the boards lane at the attacking blue line; inside it, the half-wall |
| the zone exit, each wall | our defensive zone — today's exit walls |
| the post walkout, each side | behind a goal line — today's walkouts |
| the wheel, each side | 5v5, behind our own goal line — today's wheel |
| regroup | outside the attacking zone: back toward our blue line, the reset when the entry is shut |

Each is priced as today's candidates are (`_score_move_candidate_base` and the
two-ply upgrade: value on arrival × lane × decay × safety − turnover cost, plus
the pass option it opens). With ~4–6 legal destinations instead of ~20 spots
this is cheaper than today's search. The incumbent destination keeps it unless
a challenger beats it by `ACTION_HYSTERESIS_MARGIN_FRAC`, so the plan does not
flicker; the menu is re-priced every compete.

### The near move (rolled out)

Each compete rolls out a fixed set of inputs for **0.5 s** (`EVADE_HORIZON_S`
is 0.4 s, a deke 0.5 s) from the carrier's real velocity and facing, through
`apply_movement` with his own movement config:

- straight at the destination;
- soft left / right (±30°) and hard left / right (±75°) of it;
- brake (the hockey stop — today's brake check);
- cut back (away from the destination, facing kept — skating backward).

An input's endpoint is scored by what it leaves him: the destination's value
re-priced from the endpoint (its velocity carried into the rest of the route),
or the shot from the endpoint if that is worth more, × the keep odds over the
ROLLED path (`carry_safety` along its samples, not a straight segment) − the
turnover cost at its strip point. The best input's value is the carry's value
in the fire compete; its direction is the carrier's `move_vector` until the
next compete; facing follows it (backward on the cut back).

Re-planned at the carrier's compete cadence (20 Hz on Hard, 10 on Normal) over
a 0.5 s horizon: a receding horizon, so an input is never held longer than the
horizon it was priced over.

### What the rollout must model

- **Facing**: thrust depends on the stick's angle to facing. The rollout turns
  facing toward the input at the bot's own facing rate (`AISkaterCaps` already
  carries it), as the cursor-driven facing does.
- **Boards and net**: `integrate_forward` has no clamps. An input whose path
  leaves the rink or enters the cage is pruned (or clamped, if pruning leaves a
  carrier on the boards with nothing — decided in step 1 against the duels).
- **The config**: `AISkaterCaps` gains a copy of the skater's
  `MovementConfig`. A copy, because the main thread writes stagger into the
  controller's cached one every tick while the AI worker reads.
- **The crease**: today a steering force; it becomes a pruned input.

### What it replaces

| today | after |
|---|---|
| forward fan (6 spots) and rear ring (10) | the rolled inputs |
| the directed evasion seam (candidate and cut) | the hard-cut inputs |
| `time_to_arrive` for the near move | the rollout itself |
| seek + threat repel for the carrier | the chosen input |
| facing: route / retreat / goal rules | facing follows the input (the O-zone square-to-goalie rule stays, it is about the shot) |

Kept: the blade protect offset (the blade, not the body), board play's pin
answer, the offside guard, the shot holds, the protect-side stickhandle.

## 3. Steps

Each step ships with the suite green, `test_bot_duels.gd` and the slow
`test_real_rush_sim.gd` passing, and the AI benchmarks compared before/after.

### Step 1 — the rollout

`AICarryRollout` (domain/ai): rolls the input set from a state and fills a
caller-owned result (endpoint, velocity, path samples, legal). The config copy
in `AISkaterCaps`. A calibration test drives the real `SkaterController` with
each input and holds the rollout's endpoint to it within a few centimetres — the
test that makes "what is priced is what is skated" true rather than claimed.
A micro-bench row; a 120 Hz rollout of 7 inputs is ~420 `apply_movement` calls,
so this step also measures whether a coarser sub-step (60 Hz) holds the
calibration, and uses the native kernel when it is built.

**Done.** `AICarryRollout` (`Scripts/domain/ai/carry_rollout.gd`), held to the
live controller by `test_carry_rollout.gd` to float noise, with and without the
puck: from rest, in stride, crossing the destination line, into the boards, at
the cage. It runs the controller's own order, which matters: the facing step
reads the velocity before the body's containment strips it. The carrier's board
shield (facing turned along the wall) is modelled; other bodies, the goalie's
footprint and the shot and knockdown states are not.

Cost, per carrier, all seven moves: 1.4 ms at the live 120 Hz step, 0.37 ms at
30 Hz (`STEP_TICKS` 4), which drifts ~6 cm and 0.3 m/s from the live path —
bounded by a test. The containment and the board shield are skipped exactly when
nothing in reach of the horizon touches the boards or a cage, which is most of
the ice. A native kernel can make the full-rate step affordable later.

### Step 2 — destinations

The long-range candidates move into a destination menu with hysteresis; the
near move is still today's anchor steering, aimed at the destination. Mostly a
refactor: the duels and rush sims should not move much.

**Done**, with one change of order. `AICarrierDestinations` holds the menu and
the hysteresis; every destination is priced in full by today's candidate
scoring, and only the chosen one competes as an anchor. Regroup wins where it
should (a set stand-up line past centre, nothing to pass to — the snapshot's one
moved row). The near candidates still orient on the slot: oriented on the
destination, they lost the entry. A destination is priced as one straight carry
all the way, so a defender anywhere on that line zeroes the forward ones and
regroup wins, and a fan pointed back at regroup has no entry candidate — the
carrier stood still short of the blue line with room to enter. Orienting the
near move on the destination moves to step 3, where the rollout's seven inputs
still cover every direction.

### Step 3 — the near move

Rollouts toward the destination, scored; the chosen input drives the carrier;
facing follows it. The forward fan, rear ring, seam candidate and the carrier's
threat repel are deleted. This is the step that changes how carriers skate, and
the one to playtest.

**Built.** The seven moves replace the forward fan, the
rear ring and the seam candidate; the agent skates the winning stick directly.
Changes from the design above:

- **The horizon is one second, not half.** From a standstill with a checker
  three metres off, every move is inside his reach for half a second, so the
  search could only choose where to lose the puck — forward, into him. What a cut
  buys shows in the half-second after. A second also needed the 30 Hz step's
  drift bound widened to ~20 cm.
- **A destination across a cage is skated at the arrival clock's waypoint round
  it** (`AIArrival.cage_waypoint`); aimed straight, the wheel slid along the
  cage.
- The remaining route from a move's end is priced by the lane and the decay
  only, not by its safety: beyond the horizon the next re-plan sees the defence.

Measured: default and slow tiers green; the bot duels and rush sims pass. The
micro-bench is higher, not lower: carrier compete ~3.1 ms (step 1: 2.5), the
rollout 0.76 ms of it.

The carrier found the off-centre lanes round the rush defence, which this step
answered on the defence side rather than by blunting the carrier: the race reads
a carrier's speed turned onto the line, the chase election counts a feed's own
reach band, our pass in flight is not a rush, and the defender goes to depth
before width (`Scripts/domain/ai/CLAUDE.md`, "Pace enters through the stride
ramp"). `test_nz_turnover_recovery` now contains 19 of 36 with 1 of 9 winnable
races lost; zone coverage's uncovered-share ceiling was widened to 2.5 (#791).

### Step 4 — the maneuvers

The brake check is already an input. The deke (fake then cut) becomes a
two-segment input; the poke-evade cut becomes the hard-cut input it already is.
Each is deleted only once the duels show the rolled version keeps the puck as
well — `test_bot_duels.gd` is the gate, measured, not assumed.

**Brake check: deleted.** `prefers_brake_check` and the poke-evade's brake
window are gone; when a stick comes in and the carry's rolled move is BRAKE,
the evade stands down so the rolled stop plays. Measured over three carrier
duels plus sixteen checkers charging across the carrier's lane: the hand-coded
check fired once (the pincer), and every other duel is unchanged — kept 19 of
19, strips equal; the pincer now cuts instead and gains 6.5 m to 3.3.

**Poke-evade cut: deleted**, and with it the directed seam it latched
(`best_evade_point_toward`, the carrier's `evade_seam_world`) and the poke
trigger scan, which then only served the deke — the deke carries its own gates.
What is left of `SkaterAgentPokeEvade` is the deke. Same duels: kept 19 of 19
both ways, strips 189 → 143, ground gained 274 → 291 m; where the cut fired,
the rolled carry or the deke now plays.

**Deke: deleted, not folded.** Built as designed — two rolled moves, a fake
square across the line then a 45° cut, priced against the container bitten
(he reads the fake, then accelerates toward it until the cut, and reads the
cut only from then) — it failed the gate: strips 143 → 293, ground 291 →
246 m. Measuring why: in the duels the defender does not bite. At the cut he
has drifted *away* from the fake side (mean −0.21 m, −0.87 m/s along it, where
the model said +0.12 m, +1.57 m/s); the old deke read was safe because it
checked the cut only half a second out with almost no redirect for him. What
the old deke did deliver was its stance cut — with the stance off it lost
(232 strips) — and the rolled carry with no deke at all keeps the puck as well
as the old deke did (139 strips, 294 m). So `SkaterAgentPokeEvade`, the
carrier's deke read and `deke_cut_side` are gone, and the rolled moves are
the carrier's only answer to pressure. They never hold the stance (#794).
Easy's `protects_the_puck` now gates only the blade's protect blend.

### Then

Shot-currency step 4 (the drive-in priced along the rolled route), and pricing
the carrier two deep: the rolled endpoints are the nodes, so the second ply is a
handful of cheap leaves rather than a beam.

## 4. What players should see

Carriers skate where they mean to go and face it. Fewer stalls at an angle;
cuts that a real skater could make at that speed; a carrier with open ice
straightens out and accelerates. Evasion reads as one move, not a twitch from
one layer followed by another.

## 5. Open questions

- Whether the formations should hand the carrier a destination (the lane the
  formation wants him in). Not in this plan; revisit once the menu has played.
