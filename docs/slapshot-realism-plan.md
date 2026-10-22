# Slapshot realism — the stance, the fake and the one-timer

Status: **Phases 1–4 built, awaiting playtest.** Decisions below were agreed in
chat; phases are ordered so each one can be played on its own.

As built, Phase 1 differs from the design below:
- The one-timer circle's radius stays `slapper_zone_radius` (0.5 m); only its
  centre moved onto the strike spot. Deriving the radius from the blade is left
  for Phase 5, where the contact model lives.
- A feed caught in the circle is pinned at the strike spot, not where this
  machine's puck happens to be, so host and client pin the same point.
- The hips pivot into the stance at a steady `slapper_stance_turn_deg_s` (450°/s,
  a 90° set-up in a fifth of a second) rather than the facing drag's ease, whose
  tail made a large turn take over half a second.
- The set-up also ends once the puck has stopped closing on the spot
  (`SLAPPER_SETUP_SETTLED_*`): on some builds the blade's reach and the carry's
  own offset stop it short of the spot's tolerance.
- The wind-up apex and the wide base were set against reference photos of
  Ovechkin's one-timer load and Karlsson's wind-up, and Ovechkin's flatter
  backswing was chosen because it reads from above: both hands up in front of
  the chest, the top hand beside the head toward the stick-side shoulder, the
  shaft running back over that shoulder at about 40°, feet spread across the
  line (`slapper_load_width_m`) and barely staggered. The width is given back
  as the kick drives: held through it, both legs reached it dead straight and
  the back leg had nothing left to extend.
- The stick swings as one piece (`Skater._swing_rigid`). The dressed blade was
  solved fresh each frame from the shaft's bearing and spun ~20° a frame
  through the downswing as the blade crossed over the hands; through the swing
  the blade and the shaft's roll are now the ones the swing started with,
  turned by the one rotation that takes the starting hosel line onto the
  current one, in the shoulders' frame. Anchored rather than carried frame to
  frame, which drifted ~150° round the loop. Both slapper poses are now held
  in the shoulders' frame through the release, so neither the world-hold on a
  torso turn nor the pose bridge leaves the stick behind as the shoulders come
  through. `test_the_stick_does_not_roll_through_the_swing` measures it, and
  the strip tool has `slapshot` / `slapdown` scenarios to watch it.
- `ShotMechanics.slapper_aim_dir` is now unused, but it stays: that file is in
  the shot field's fingerprint, and deleting it would force a regeneration
  while the goalie is changing elsewhere.
- Side-on, a shooter's chest faces the stick side of the shot line, so a feed
  from the off-stick side arrives behind him (a right shot on the left circle
  takes it from his right, as Ovechkin does). The bot settle still
  places its circle on any feed line; Phase 6 should price that, and Phase 5's
  contact model already makes such a feed cost pace.

## Decisions banked

- **The puck never moves on its own.** Pressing the slapshot does not put the
  puck anywhere; the blade takes it to the strike spot, at the dangle's own
  speed, and the backswing starts once it is there. Nothing teleports, on the
  press or on a cancel.
- **The slapshot is taken side-on.** The hips turn so the front shoulder (the
  top hand's, on the off-stick side) points down the shot line, feet wide, the puck in front of the
  body off the front foot. The turn runs at the facing rule's own rate, never a
  one-tick snap.
- **One strike spot, derived from the body.** The puck's pin during the
  wind-up, the blade's contact in the downswing and the one-timer circle are one
  point, computed from the build's shoulder, arm and stick. Today they are three
  hand-set copies that disagree.
- **The fake stays, and it costs the stick coming down.** Cancelling a
  backswing is a real fake slapshot. It locks every on-puck action for as long
  as it takes the stick to come back down to the puck, which grows with how high
  it went. A press inside the lock is queued, as the settle lock already does.
- **The aim is live through the backswing**, inside an arc about the stance
  line, and locks when the button goes (the downswing). Moving it further means
  setting the feet again.
- **Loaded, you glide.** In every slap state: no stride, weak edges, momentum
  kept (no extra drag). The puckless one-timer wind-up may shuffle (Space + key)
  to line up on a feed; it may not skate.
- **The pass's pace feeds the one-timer.** The blade strikes a moving puck, so
  the outgoing shot is that contact: a feed coming at the swing adds pace, one
  from behind costs it, and the feed's cross-line speed is partly kept, so a
  one-timer pulls with the pass.
- **The goalie is out of scope.** Another line of work is changing it. Nothing
  here edits goalie code; what changes for the goalie's reads is listed under
  *Handed to the goalie work*.
- **Bots keep one-timers only.** A carried slapshot for bots (audit F8) is not
  in this plan.

## Why — what the toolkit does today

| | today | the problem |
|---|---|---|
| press with the puck | `_enter_slapper_charge` pins the puck to a fixed skater-local spot (±1.0, −0.4) via `enter_slapshot_pinning`; `Skater._carry_target_raw` returns it unsmoothed | the puck jumps to the forehand in one tick |
| facing at the press | snapped to the cursor in one tick | the body whips; `release-realism-plan.md` left this for "the slap-shot pass" |
| the stance | hips face the target, torso twisted 80° on top (`slapper_wind_up_twist_deg`), hips coil 16° | a front-on stance with the shoulders wrenched round, not a side-on one |
| cancel | LMB returns to carry on the tick (`_state_slapper_charge_with_puck`), the pin drops and the puck returns to the blade | a free fake: the goalie reads `SLAPPER_CHARGE_WITH_PUCK` as a planted, declared shot and shades to its aim, and the cancel costs nothing |
| aim | locked at the press (`locked_slapper_dir`) | no adjustment once the press is made |
| moving with the puck | locomotion suppressed and `_apply_slapper_velocity_drag` stops the skater | a skater who comes in at speed plants |
| moving loaded for a one-timer | full skating | striding and cutting with the stick cocked, and chasing the circle onto the puck |
| the strike spot | `slapper_zone_offset_x/_z` (skater-relative), `slapper_blade_x/_z` (shoulder-relative), `BOT_ONE_TIMER_ZONE_OFFSET_*` (a mirror) | three hand-set copies of one point, already disagreeing by the shoulder's offset |
| one-timer power | the wind-up's power × a ±10 % centre bonus | the feed's own pace and direction never enter |

## Where the code goes

`SkaterController` is over the file-size limit already, so the new geometry
and contact math do not go there. A pure rule, `Scripts/domain/rules/
slapper_rules.gd` + GUT test, owns:

- `strike_spot_local(build geometry)` — the strike spot in the hips' frame;
- `stance_facing(aim_dir, handedness)` — the hips' facing for a shot line;
- `clamp_aim(aim_dir, stance_line, arc)` — the live aim's arc;
- `recover_time(wind_up_t)` — how long the stick takes to come down;
- `one_timer_contact(...)` — the outgoing shot off a moving puck (Phase 5).

The controller calls them; the state machine keeps its eight states. The shot
state enum is full at 8 on the wire (`skater_state_machine.gd`), so every new
phase below lives inside an existing state, told apart by a timer that is
already saved and restored through reconcile or by one added beside it.

## Phase 1 — set-up, side-on stance, one strike spot

### The strike spot

The point the blade meets the ice at the bottom of the swing, in the hips'
frame: in front of the body, a little toward the front foot. Its distance out
comes from the build — the top hand at the swing's low point, the arm and the
stick at its lie — through the same `TopHandIK` reach solve the carry uses, so
a tall skater on a long stick strikes further out. Its radius (the one-timer
circle) is half the blade length plus how far the blade sweeps across that
point in the leniency window at the downswing's speed.

Everything reads it: the pin (`enter_slapshot_pinning` takes it rather than
tunables), the downswing's contact in `SkaterShotPoseCoordinator.
apply_slapper_follow_through`, the zone the one-timer tests against
(`set_slapper_zone`), the ice-shader circle, and the bot settle
(`SkaterAgentOneTimer`, which stops mirroring constants and asks the rule).
`slapper_zone_offset_*` and `slapper_blade_x/_z` go away.

### The stance

`stance_facing` turns the hips so the top hand's shoulder points down the
shot line. The angle the hips open to is a tunable (`slapper_stance_open_deg`,
starting at 90° — coaching's "perpendicular"), to be settled on a render. The
torso's wind-up twist shrinks to a shoulder coil on top of open hips; the leg
layer (`GaitShotLayer`) loads the back leg in the backswing and kicks onto the
front leg in the finish as it does now, with the feet now across the line.

### Set-up: the blade takes the puck there

The slap press with the puck enters `SLAPPER_CHARGE_WITH_PUCK` in a **set-up**
phase:

- the hips turn toward `stance_facing(aim)` at `FacingRules.turn_rate`, the
  aim following the cursor freely;
- the blade's target is the strike spot, carried by the normal carry IK at the
  normal blade speed cap, so the puck rides the blade there as in any carry;
- the charge timer does not run.

Set-up ends when the hips are within a tolerance of the stance and the puck is
within a tolerance of the spot. The puck is pinned **where it is then**, in the
hips' frame, so even a loose tolerance never jumps it. A puck already in front
on the forehand finishes set-up in a few ticks; one on the backhand is dragged
across, which is what a slapshot off a backhand carry really costs.

Telling set-up from the backswing: `slapper_charge_timer` stays at 0 through
set-up and a `slapper_setup_done` flag (saved/restored with the other charge
fields in `LocalController.reconcile`) marks the hand-off. Remotes need
nothing: the pose rides the hand and blade the wire carries, and the gait's
load reads `shot_charge`, which is 0 until the backswing starts.

The puckless one-timer press has no set-up (no puck to move): the hips turn to
the stance at the turn rate and the backswing starts at once.

### Tests

- `test_slapper_rules.gd`: the strike spot grows with stick and arm length;
  `stance_facing` puts the front shoulder on the line for both hands.
- One strike spot: the pin, the downswing's contact pose and the zone land on
  the same point for every build (replaces `test_bot_mirrors`'s zone check).
- No teleport: from a backhand carry, the puck's per-tick step through the
  press and set-up never exceeds the blade speed cap's step.
- No snap: the facing's per-tick turn through the press stays inside the
  facing rule's rate.
- Render: `render-poses.sh` wind-up and follow-through poses re-recorded after
  the user has looked at them.

## Phase 2 — the fake costs the stick coming down

As built, this differs from the design below:
- Through the recovery the puck is held at a fixed world offset from the
  skater (`SkaterController.fake_puck_offset`), re-pinned each tick, rather
  than at its pin in the hips' frame: the hips turn back out of the side-on
  stance as soon as the slapshot is called off, and a hips-frame pin swung the
  puck round with them.
- Every way a carried slapshot is called off pays it: the wrister button, the
  button let go during the set-up (the floor, `slapper_recover_min_s`), and a
  caught one-timer held past its window.
- Reconcile does not let the host's lagged wind-up re-arm a slapshot the client
  has called off while its recovery runs (`Scripts/networking/CLAUDE.md`).
- The strip tool's `slapfake` scenario shows the stick coming down.

LMB during a slap charge still cancels, but the cancel now:

1. returns to `SKATING_WITH_PUCK` with the puck held where it is: the pin stays
   on through the lock, and the blade comes down to the carry pose whose pin is
   that spot, so when the lock ends and the carry takes the puck back, nothing
   moves;
2. arms the settle lock for `recover_time(wind_up_t)` from the cancel input's
   own stamp. That deadline is derived from the input on both sides, so unlike a
   catch's settle it needs no grant and no wire — host and client process the
   same cancel input at the same stamp. `SkaterSettleGate` gains a local arm that
   skips the grant's notice window;
3. eases the blade down to the puck over the same time, through
   `SkaterPoseBridge` with that duration rather than its fixed 0.15 s.

`recover_time` is a feel tunable: about 0.1 s from a barely-started backswing to
about 0.45 s from the top. A press inside it queues and fires on unlock, as a
settle does; the cancelling LMB press itself is consumed, so a fake followed by
a shot is two presses.

A cancelled **puckless** one-timer wind-up gets the same blade ease with no lock
to arm: the raised blade cannot take a pass until it is back on the ice
(the blade-plane gate already refuses it), so the cost is emergent.

### Tests

- The lock's length grows with wind-up, and a press inside it fires on the
  first unlocked input.
- Reconcile: a client cancelling under latency locks the same inputs as the
  host (a sibling of the settle lock's reconcile test).
- No teleport on cancel: the puck does not move through the lock or on the
  tick the carry takes it back.

## Phase 3 — live aim

As built, this differs from the design below: with a puck pinned, the aim runs
from the puck itself rather than the strike spot (the two differ by the set-up's
tolerance), and a feed caught in the puckless wind-up latches the stance line
the same way the set-up's end does. Bots needed no change: they already commit
their direction every tick of the press.

Through the backswing the aim is the strike spot → cursor, clamped by
`clamp_aim` to ±`slapper_aim_arc_deg` (starting at 20°) about the stance line
the set-up settled on. It locks into `locked_slapper_dir` on the release edge,
which is what the downswing, the retention hold and every release path already
fire. The shoulder coil and `predicted_shot_velocity` follow the live aim each
tick, so anything reading the predicted shot sees the aim move.

During set-up the aim is free and the hips chase it. In the puckless one-timer
wind-up there is no puck pinned, so the hips keep turning toward
`stance_facing(aim)` at the glide's turn rate: pointing at the net opens the
body side-on and brings the circle round in front of you.

Bots keep committing their direction (`bot_slapper_aim_dir`), now per tick.

Reconcile: the aim is a function of each input's cursor and the stance line,
so replay re-derives it. The stance line is set once at the end of set-up and
saved/restored with the charge fields.

### Tests

- The aim follows the cursor inside the arc and holds at its edge outside it.
- The shot leaves along the aim at the release edge, not at the press.
- Replay reproduces the locked direction.

## Phase 4 — loaded, you glide

As built, this differs from the design below:
- No edge-grip cut: with no stick reaching the kernel the edges never turn the
  skater, so there is nothing for it to cut.
- The puckless wind-up keeps the brake, so a shooter can stop to set for a feed
  as well as step-together onto its line.
- The glide's intent (no stick, and the brake only where it is allowed) is
  published as the replicated `move_intent` / `brake_intent`, so the gait and
  every peer's forward prediction skate the glide with no wire change.

In `SLAPPER_CHARGE_WITH_PUCK`, `SLAPPER_CHARGE_WITHOUT_PUCK` and
`ONE_TIMER_RETENTION`:

- no stride thrust (zero stick into the movement kernel);
- edge grip cut to `slapper_glide_grip_mult`, so the travel can bend gently
  but not cut;
- ordinary glide friction only: `_apply_slapper_velocity_drag` is removed;
- in `SLAPPER_CHARGE_WITHOUT_PUCK` only, the shuffle chord works as it does
  standing (`SkaterMovementRules.is_shuffle`, under `SHUFFLE_MAX_SPEED`), so a
  shooter can step onto a feed's line.

The movement kernel has a C++ port held by parity tests, so the glide config
gets its own native instance the way `_native_block_move` does.

### Tests

- A skater entering a slap charge at speed keeps it to within glide friction.
- Stick input during a charge adds no thrust; the turn is bounded by the cut
  grip.
- The puckless wind-up shuffles; the with-puck charge does not.

## Phase 5 — the pass's pace feeds the one-timer

The contact is the blade's, so it uses the blade's contact model: the same
normal/tangential decomposition `PuckCollisionRules.deflect_velocity` runs for
every deflect, in the frame of a blade moving at swing speed `B` along the shot
line `d`.

With `u` the feed's velocity in the shooter's frame (the frame reception reads),
`u_n = u·d` and `u_t` its part across the line:

- along the line: `B(1 + e) − e·u_n`. A still puck gives `B(1 + e)`, which is the
  slapper's power `P` today, so `B = P / (1 + e)`, and a feed coming at the swing
  (`u_n < 0`) adds `e·|u_n|`;
- across the line: `κ·u_t`, the face's grip on the glance. The shot leaves off
  the aim by `atan(κ·|u_t| / along)`, toward the way the pass was going;
- `e` is the blade's restitution at that closing speed, read from the deflect
  model rather than a new constant; `κ` is a new tunable for a squared,
  driven face (starting near 0.2; 0 turns the pull off);
- the result is capped at the puck's max speed, and the ±10 % centre bonus stays
  on top.

**A caught feed is a moving puck only on the beat.** A feed that attaches during
the charge is caught by the zone, not stopped by the player; the transfer is
full if the swing commits within `one_timer_leniency_time` of the catch and fades
to none by the end of the window, measured off `one_timer_window_timer`, which
is already synced. A one-timer held on the blade becomes a quick slapshot.

**The wire.** The leniency redirect reads the shooter's puck view, which it
already has. The caught path needs the feed's velocity at the catch, which only
the host knows exactly, so it rides the pickup grant beside the settle deadline
(`PICKED_UP.arg` / `notify_puck_picked_up`) — a `PROTOCOL_VERSION` bump and a
`docs/protocol-history.md` row. Read `Scripts/networking/CLAUDE.md` before
building it.

### Tests

- `test_slapper_rules.gd`: a still puck reproduces today's power; a feed at the
  swing adds pace, one from behind loses it; the pull grows with cross speed and
  is zero at `κ = 0`.
- The caught path's transfer fades with how long the puck sat.
- Host and client fire the same caught one-timer (the grant carries the feed).

## Phase 6 — bots onto it

- `SkaterAgentOneTimer` places the derived strike spot on the feed line, and
  `ONE_TIMER_SQUARE_UP_MAX_RAD` (which exists only because the press snaps the
  body round) is replaced by pricing the stance turn.
- With movement cut to a glide in the wind-up, bots must arrive on the line
  before they press, or shuffle onto it. `test_skater_agent_one_timer.gd` and
  `test_one_timer_chain.gd` tell whether the timing still lands.
- Feed choice prices the pace transfer: the passer's speed choice
  (`AIPuckLane.PASS_TARGET_CLOSING_M_S` steps) gains a reason to go hard to a
  one-timer.
- The shot field's one-timer cells (`AIShotOdds`, generated by
  `tests/instruments/ai/test_generate_shot_field.gd`) are re-measured, since the
  one-timer's pace and pull change.

## Handed to the goalie work

None of this edits goalie code. Things the goalie line of work should know:

- `SLAPPER_CHARGE_WITH_PUCK` now includes the set-up, before the charge runs.
  `_reading_planted_windup` and the block-or-react `declared` test read the
  state, so they fire through set-up too.
- "Planted" stops being true: the shooter glides at constant velocity, so the
  shot comes from a point that moves, predictably.
- The aim moves through the backswing; `predicted_shot_velocity` follows it each
  tick, so the aim shade follows without change.
- One-timers carry more pace on hard feeds and pull with the pass.

## Docs to update as phases land

`docs/gameplay-design.md` (the slapshot bullet), `ARCHITECTURE.md` (the state
table, *Slapper aim is LOCKED at the press*, *One-timer*),
`Scripts/networking/CLAUDE.md` (the grant's new field, the cancel's local lock).

## Open questions

- The stance's open angle and the aim arc are starting numbers for a render and
  a playtest.
- Whether the pull (`κ`) feels like skill or like noise; it can be set to 0
  without touching the rest of Phase 5.
