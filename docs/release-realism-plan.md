# Release realism — where, when and which way the puck can leave the stick

Status: **draft for review.** No code yet. Each phase is meant to ship as its own
PR with its own playtest. Phases 1 and 2 change the human toolkit, so each needs
a protocol bump.

## Decisions banked

- **The limits are shared, not bot-only.** Bots release through the same
  `SkaterController` path a human does (`AIController.apply_decision` →
  `_process_input`). Every limit here goes into that path, and the bots then
  *obey* it: their scoring prices it and their execution respects it. There are no
  bot-only gates. This is the "fix the model, not the behavior" rule in
  `Scripts/domain/ai/CLAUDE.md`, applied to the toolkit itself.
- **Release direction is a hard cone around the body's facing.** Aim outside it
  and the puck leaves along the cone's edge. No power taper, and no waiting for the
  body to turn.
- **The wrister blade stays frozen through the wind-up.** That feel is settled.
  Power keeps coming from cursor speed. Whatever limits how fast a full-power shot
  comes off the stick has to work *with* a frozen blade, so the dormant
  blade-travel gate (`wrister_travel_cap_t`) is not the lever.
- **Point-blank is fixed in the bot model only.** The physics holes that let a
  blade beside the pads score stay as they are (see *Flagged, not in scope*).

## Why — what the toolkit allows today

| | human | bot |
|---|---|---|
| release direction | anything, including straight behind; backhand ×0.75, dodged by sweeping the forehand way | prices zero turn cost anywhere within ±157° of facing (`_facing_rotation_time`); commits with no turn inside 132° (Aim-B2); every pass fires as a forehand |
| time to full power | ~50 ms: the cursor-speed EMA saturates in about six ticks on a fast flick | a fixed 125 ms (`BOT_WRISTER_CHARGE_TICKS`), plus a 0–0.24 s timing hold; always full power |
| after a catch | a full-power release can fire on the first carrying tick | same |
| where the puck leaves | wherever the blade sat at the press, frozen | one of three lateral offsets (`RELEASE_SAMPLE_FRACS` 0 / +1 / −1 × ~0.88 m), then eased there *during the frozen hold* at the 60 m/s on-axis aim budget, which no human can do |

The last row is a straight bot advantage. `_apply_wrister_aim_blade` gives a bot a
`hold_target`, and `SkaterIKCoordinator`'s `WRISTER_AIM` branch moves the blade
toward it with on-axis motion uncapped to 60 m/s. A human's blade cannot move
during that state at all.

The point-blank drive follows from two things:
- **The ranking value rises all the way into the crease.** `AIShotValue` is
  log-distance xG, floored at 0.5 m, plus the displacement term, and the keeper's
  body is not in it.
- **The only goalie limit, `release_ahead_of_goalie`, clamps depth only, and only
  in scoring.** A carry closer to the net always wins, until that clamp flattens
  the value 0.4 m in front of the predicted keeper. There fire wins the tie. The
  ±0.88 m lateral sample is then scored as a doorstep shot. Execution eases the
  blade out to that offset from a body that has skated another `v × 0.135 s`, so
  the real release can sit beside the pads.

## Phase 1 — the release cone (shared)

### Rule

New pure rule `domain/rules/release_cone.gd` (`ReleaseCone`). It takes:
- a release direction (world XZ);
- the skater's facing (`Skater.get_facing()`: the same replicated frame the reach
  cone is built on, and frozen during `WRISTER_AIM`);
- handedness.

It returns the direction clamped into the cone. The cone is asymmetric:

| side | half-angle (start) | why |
|---|---|---|
| stick side | 105° | a forehand sweep finishes well out to the side, with the torso open |
| off side | 80° | across the body is a backhand or a cut-across forehand, and neither reaches as far round |

Both values are feel tunables on `SkaterController` (plain `var`), not constants
in the rule. They go through `apply_attributes` untouched in v1; whether Agility or
torso twist should widen them is a later question.

### Where it applies

- `ShotMechanics.release_wrister`, both branches (charged wrister and quick pass),
  through one call site in `_release_wrister` / `_fire_quick_pass`. Applied to the
  final direction, so a bot's committed `bot_wrister_aim_dir` is clamped exactly
  like a human's cursor line.
- **The slapper: at the press, where its direction is locked** (`_enter_slapper_charge`).
  The one-timer zone already sits on the stick side, so in practice this only
  bites on a deliberately behind-the-body slap.
- **The goalie's read.** `predicted_shot_velocity` is re-solved every aim tick. It
  must clamp too, or the goalie pre-leans toward a line the puck can't take.
- **Not the nudge (Q).** It is a self-pass that keeps the skater's own momentum,
  not a release.
- **Dumps.** These are charged wristers, so they are covered by the first bullet.

### Human feedback

The shot puck going along the cone's edge has to be legible, or it reads as a bug.
If an aim indicator is on screen during `WRISTER_AIM`, it draws the clamped line.
Otherwise this is a playtest question (see *Open questions*).

### Bots

- **Pricing.** `_facing_rotation_time` charges turn time for any receiver outside
  the RELEASE cone, not the 157° reach cone. That turns behind-the-body passes
  into the slow plays they are, without a separate gate.
- **Commit.** The Aim-B2 cone becomes the release cone less its margin. Past it,
  the bot turns at its real facing rate before pressing. The ~1 s timeout no longer
  fires a pass the cone would clamp: it re-plans instead.
- **Hand.** A pass on the off side is flagged backhand (`bot_wrister_backhand`),
  so it pays the backhand coefficient like a human's does.

### Netcode

Facing and handedness are replicated, and the host replays the release input, so
the clamp is a pure function of state both sides already agree on. There is no
wire field. It still needs a protocol bump: a mixed-version lobby would disagree
on where every edge-of-cone release goes.

### Tests

- `ReleaseCone` unit test: inside passes through, the edges clamp, the mirror for
  left-handed is exact, and a degenerate zero direction is handled.
- A controller test: a human quick pass aimed straight back leaves along the
  stick-side edge, and the goalie's predicted line equals the released one.
- Carrier tests: no committed pass leaves outside the cone, and a receiver behind
  the carrier prices its turn.

## Phase 2 — release load (shared) — **needs a decision**

What should stop a full-power wrister coming off the stick in 50 ms? It has to
work with a frozen blade. Two candidates; they compose rather than compete.

### 2a. Coil load (recommended first)

The torso already coils toward the cursor during `WRISTER_AIM`. The idea is to
make the power ceiling follow time spent loading:

    ceiling_t = lerp(snap_floor_t, 1.0, clamp(time_in_aim / load_time, 0, 1))
    power_t   = min(speed_power_t, ceiling_t)

- **`snap_floor_t`.** A quick snap still comes off hard, just not full. It starts
  around 0.6 of the band.
- **`load_time`.** About 0.3 s at neutral Shot. It is a **Shot** lever, which is
  what `Scripts/controllers/CLAUDE.md` says Shot means: "what a charge buys you,
  and how fast you can charge it".
- **What it replaces.** It takes the place of the dormant blade-travel gate in
  `WristerConfig`, `full_stroke_travel` and `travel_cap_floor`. The dead mechanism
  goes, rather than sitting beside a second one.
- **Why it composes well.**
  - It is visible: the coil on screen is the load.
  - The clock is input-driven and deterministic, which matters for netcode below.
  - A goalie who reads a long wind-up already gets the benefit
    (`Scripts/controllers/CLAUDE.md`: "a quick-release snap FROM RANGE never earns
    the windup prime").

### 2b. Reception settle

A puck that has just arrived on the blade is not under control yet. The idea is a
power ceiling (and the same ceiling on the quick pass's flat power) that recovers
over a settle time sized by the puck's speed **in the receiver's frame** at the
catch. That is the same quantity the reception model already decides catches by.
- A soft feed settles almost at once.
- A hard pass costs up to ~0.25 s.
- **The one-timer slapper is exempt.** Catching and releasing in one motion is the
  skill shot it exists to be.

The netcode cost is real. Clients don't predict pickups, so the client learns of
the catch a trip late. The ceiling therefore has to be keyed off the host's pickup
time and the relative speed, both carried on the pickup grant, and evaluated in
input-stamp time. Read `Scripts/networking/CLAUDE.md` before building it.

### Bots

`bot_wrister_power_t` stops being a constant 1.0, and `BOT_WRISTER_CHARGE_TICKS`
stops being fixed.
- The bot commits a charge duration and gets the power the ceiling allows, like a
  human.
- The value model already charges the goalie's push over "carry + charge + flight".
  It needs pace to move flight time too, and then it picks between a quick snap
  and a loaded wrister by value, not by a rule.
- In practice: a quick release where the keeper is moving, and a loaded shot where
  he is set and the shooter has room.

### Tests

- A unit test on the ceiling curve (floor at zero load, full at `load_time`, Shot
  scaling).
- A reconcile test: the load clock is saved and restored with the wrister swing
  state, or replay inflates it the way `slapper_charge_timer` once did.
- The shot-outcome sim (`test_shot_sim.gd`) re-run, with the change in bot goal
  rate reported.

## Phase 3 — bots release from where the puck is

- **Retire `RELEASE_SAMPLE_FRACS` and the bot-only hold-target easing.** The bot
  presses with the blade wherever it is, as a human does, and the frozen hold
  holds that spot.
- **Relocating the puck becomes a carry-phase move.** Shoot-now prices "release
  from here" and a continuous set of pulls across the reach arc (finer than three,
  refined around the best). Each pull costs the blade's real travel time at the
  bot's dangle caps (`blade_speed`, `max_blade_accel`: the same arrive law the
  IK runs).
- **The winning pull is executed by the carry cursor.** The press is gated on the
  blade having arrived (within `AIM_CONVERGED_DIST_M`).
- **What that fixes:**
  - The release point stops being one of three spots and becomes a continuum.
  - The time a human would spend pulling the puck wide, the bot now spends too.
  - The release the bot scores is the release it executes. That last point is half
    of Phase 4.
- **`_shot_sample_offset` and `bot_wrister_origin_offset` go.** The input field is
  on the wire, so removing it needs a protocol bump; it can share Phase 2's.

### Tests

- A carrier test: a committed shot's executed release equals its scored release.
- A state-machine test: no blade motion during `WRISTER_AIM` for a bot.
- A timing test: a pull of 0.8 m delays the press by the arrive-law time, not by a
  constant.

## Phase 4 — point-blank, in the bot model

The aim is that driving into a set keeper stops being the optimum, without a
positional gate. Two pieces:

1. **Score the executed release.** Phase 3 does this. After it, the lateral
   offset that let a scored doorstep become a release beside the pads no longer
   exists. The depth-only `release_ahead_of_goalie` stays as the degenerate-
   geometry guard it is documented as.
2. **Let the seam see the keeper's body in tight.** The public xG form is fitted on
   shots whose doorstep share is mostly rebounds and displaced keepers, so its
   point-blank value is mostly *those*. That is why it reads ~0.8 from 0.9 m.
   Against a set, square keeper the open mouth from that spot is nearly nil. The
   seam already has the honest geometry: the tangent-cone cover in
   `open_net_danger`, built on `GoalieAnatomy`.
   - **Proposed:** a term that takes over from the distance curve as the keeper's
     body fills the mouth, in the same `ln(available width)` currency
     `POST_SEAL_LOGIT` already uses.
   - **Measured, not guessed:** the in-tight rows of the calibration table in
     `test_ai_action_scoring.gd`, and the shot sim, before and after.
   - **The displacement term stays.** A keeper beaten wide still opens the net,
     which is exactly the lateral cut the model is meant to reward.

If that lands, the drive ends earlier, in a release from the slot or a lateral
cut, because both now out-value walking into the pads. A deke-the-goalie read
(fake, then cut across) is the natural follow-on. It is not in this plan.

### Tests

- A carrier fixture: a breakaway on a set keeper fires before the crease, or cuts,
  and does not carry to within the jam distance.
- The existing breakaway and cutback fixtures stay green
  (`test_goalie_breakaway_ladder.gd`, `test_human_wraparound.gd` for the
  goalie side).

## Open questions

1. **Phase 2: coil load, reception settle, or both?** Coil load is cheaper and
   deterministic. Settle is the more physical answer to "they shoot the instant
   they catch it", but it has the netcode cost above.
2. **Cone numbers.** 105° stick side and 80° off side are a starting point to
   playtest, not a measurement.
3. **Feedback at the edge.** Is the clamped aim line enough, or should an aim past
   the cone also tint the cursor?
4. **Drop passes.** A hard cone forbids passing straight back. Is the nudge (Q)
   enough of a drop pass, or does the quick pass need a soft backward exception?
5. **Movement.** The request also mentioned how bots *move*. Nothing in this plan
   touches locomotion. What specifically looks wrong: speed, turning, stopping, or
   lines?

## Flagged, not in scope

These are left for issues.
- **The blade's exclusion circle around a standing goalie (0.50 m) is narrower
  than his pad span (0.56 m).** A blade can sit inside the outer pad column.
- **A puck released inside a goalie box is pushed out along the minimum-penetration
  axis** (`swept_disc_obb.gd`). For a 0.2 m-deep pad that can be the net side.
  This is inferred from the code and not reproduced.
- **`Puck.release` sets velocity to `direction × power` exactly.** The skater's
  own velocity is not inherited.
- **The goalie's poke reaches 0.25 m** (audit F11). He has no in-tight answer to a
  carrier on his doorstep beyond the block.
