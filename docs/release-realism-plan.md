# Release realism — where, when and which way the puck can leave the stick

Status: **Phase 1 built for humans, playtest pending** — the wrist shot's load
(*Phase 1*, as built). The hard cone this plan first proposed was dropped for it.
Phases 2–4 are still drafts. Each phase is meant to ship as its own PR with its
own playtest.

## Decisions banked

- **The limits are shared, not bot-only.** Bots release through the same
  `SkaterController` path a human does (`AIController.apply_decision` →
  `_process_input`). Every limit here goes into that path, and the bots then
  *obey* it: their scoring prices it and their execution respects it. There are no
  bot-only gates. This is the "fix the model, not the behavior" rule in
  `Scripts/domain/ai/CLAUDE.md`, applied to the toolkit itself.
- **Which way the puck can go hard is decided by the torso, not a cone.** The
  power a wrist shot can carry is the turn the torso can put into it from where
  the puck sits: full along the tangent at the puck's bearing, nothing straight
  out from the body or back through it, and only as much as the wind-up the hand's
  reach allows. The tangent's sense is the hand. A soft release goes anywhere, so
  the drop pass needs no exception.
- **Wrist shots only.** The slapper always fires the same way on the forehand,
  and the quick pass is deliberately outside how hockey works.
- **The load is a cap, never a setter.** Cursor speed still chooses the power, so
  a touch pass from a full wind-up stays soft.
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

## Phase 1 — the wrist shot's load (as built, humans only)

`WristerLoad` (`Scripts/domain/rules/wrister_load.gd`), solved every aim tick and
at the release by `SkaterController._solve_wrister_load`. In the hips' frame:

- **Alignment:** the shot against the tangent at the puck's bearing. Full within
  `wrister_full_load_arc_deg` (45°) of it, linear to nothing on the line through
  the puck.
- **Coil:** the width of the torso yaws, inside the ±67° twist limit, that keep the
  frozen puck in the hand's reach — `wrister_home_reach_deg` (120°, so the puck drawn back behind the
  back foot is a full load) round the
  hand's home side (stick side for a forehand, off side for a backhand),
  `wrister_away_reach_deg` (30°) round the other. A forehand from straight beside
  the body is the full share. So the crossed-arms forehand (lefty: puck at 3,
  toward 6) and its mirror, a backhand from out on the stick side (puck at 9,
  toward 6), are both weak.
- **The cap:** `min(cursor-speed power, max_wrister_power ×
  lerp(wrister_unloaded_share, 1, alignment × coil))`, × the backhand coefficient.
  With no turn behind it a shot still carries 60% (the arms, wrists and stick
  flex — measured trunk-rotation gains are a few m/s on a 25–33 m/s shot). The
  goalie's predicted shot takes the same cap.
- **The puck is the pinned origin** carried along by any skating since the pin —
  never the blade's contact point, which swings with the torso's wind-up.
- **The pose is the gauge.** The aim pose winds the torso from squared on the aim
  toward the full wind-up by the power it would release with now, and the hips
  turn `wrister_load_hip_share` of the way with it (square hips under a wound
  torso put the hands over the stick-side thigh); the release unwinds it at
  `wrister_release_unwind_speed_deg` and overshoots the way the hand turns.
- **No wire change and no reconcile state:** the load is a pure function of the
  pinned origin, the aim and the frozen facing, all of which the host replays.

Things to watch in the playtest:

- **Facing follows the cursor while carrying**, so the puck tends to settle
  straight in front of the hips — the no-power spot for a shot where you face.
  Hard shots come from across the facing, or straight after pulling the puck
  wide. If straight-ahead shots feel too weak, the lever is what the body faces
  while carrying, not the load.
- **The cursor-sweep hand read is removed.** The load names the hand, so
  `ChargeTracking` keeps only the stroke travel and the variance reset.

Bots are untouched: they commit hand and power, and their scoring does not price
the load. They join in Phase 3.

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

## Phase 3 — bots onto the human toolkit — **draft for review**

Humans now play under two rules bots are exempt from: facing follows travel
(`FacingRules`) and the wrist shot's load
(`WristerLoad`). Both are pure functions of state the bot already has, so the
work is not new physics. It is teaching the bot to play inside them: its
decisions price them and its execution respects them. No bot-only gates.

**The finding that shapes it.** A bot carries and pre-aims with the puck about
1.3 m straight out on the line to its target (`CARRY_BLADE_AIM_FORWARD_M`; the
carry ring points at the goal, the route or the shot aim). A shot or pass fired
at that target runs radial to the body, which the load scores as zero:
switching the cap on as bots play today caps nearly every centred shot and
forward pass at 60% (about 19.8 m/s). That is below the 20 m/s pass target
(`PASS_TARGET_CLOSING_M_S`), and every shot is priced at a pace it would not
reach. So the bot has to carry and release like a player who loads the puck,
not just have the rule switched on.

### 3a. Facing (as built, playtest pending)

- **One rule, one home.** The facing target is `FacingRules`, a pure domain rule
  (tests: `test_facing_rules.gd`). `SkaterPoseCoordinator` calls it for every
  skater — the bot exemption is gone — and so does the bot test harness
  (`duel_harness.gd`), which used to model facing as "always toward the cursor".
  The tunables live on `SkaterController.facing_rules`.
- **What the bot code turned out to need.** The full bot suite (duels, rushes,
  defensive routing, coverage, board play) passes with the harness skating under
  the real rule. The assumptions the map flagged mostly hold:
  - the Aim-B2 commit cone reads actual facing, so an aim within 132° of the
    travel commits at once, and an aim behind sends the cursor past the 120°
    travel cone, which turns the body round to it;
  - O-ZONE SQUARE still points the cursor at the goalie; at speed the hips follow
    the travel while the torso turns up to 67° to the net, which is the real
    shooter's posture.
- **The one-timer wait holds the stance.** Skating onto the feed line, the body
  faces its travel, so the square-up gate would wait out its 0.2 s backstop and
  the slap snap would whip the body round. The bot now opens up as a human does:
  the stance, which squares to the cursor below 3 m/s.
- **Left for the slap-shot pass:** the slapper's entry snap itself.

### 3b. Carry and release with the puck loaded

- **The carry pocket.** When a shot or pass is in prospect, the carry cursor holds
  the puck on the hand's home side (out beside or behind the stick-side hip for a
  forehand), not out on the target line. Getting it there is a real stickhandle at
  the bot's blade speed.
- **The release is whatever the puck's position gives.** The bot presses from
  where the puck is, with the hand and the cap the load names. `RELEASE_SAMPLE_FRACS`,
  `bot_wrister_origin_offset`, the 60 m/s on-axis easing and `bot_wrister_backhand`
  all go; the controller applies `WristerLoad` to bots exactly as to humans.
- **This is the old Phase 3** (bots release from where the puck is) with a reason
  for where the puck should be.

### 3c. Pricing in the same currency

- **Shots:** the shoot-now sweep prices candidate releases at the load-capped pace
  for that puck bearing and aim, plus the pull's real time. That pace drives the
  flight time, the goalie read, the rung choice and the value, so a centred
  stand-still rip is priced as the 60% shot it is.
- **Passes:** the pass pace solve is capped the same way. A feed the bot cannot
  load (a forward pass with the puck straight out) is a slower pass, which the
  lane model already punishes, or it is worth pulling the puck to the pocket first.
- **Carry candidates and teammates' shots** keep the full-pace read for now:
  they are projections a beat ahead, and the pocket is where the carry will put
  the puck.

### Order and tests

3a first (the load's frame is the facing), then 3b and 3c together, since a
release the bot cannot price is worse than the exemption. Each ships with its own
playtest.

- **Facing:** the state-machine suites that pin the cone, ARC, FACE and the
  one-timer square-up move; `test_facing_follows_travel.gd` gains a bot case.
- **Load:** `test_role_carrier.gd`'s release sampling and pass pace, the duel
  and bot-vs-goalie harnesses, and the shot-sim calibrations
  (`test_shot_sim.gd`, `test_rush_sim.gd`, xG calibration) will move. Those are
  pinned measurements: re-pin only once the new numbers are confirmed as the
  intended ones.

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

1. **Phase 2: does the load still need a clock?** The load already makes the
   position of the puck cost time (pulling it wide). Whether a wind-up clock or a
   reception settle is still wanted waits on the Phase 1 playtest.
2. **Bot movement.** The request also mentioned how bots *move*. Nothing here
   touches locomotion.

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
