# Release realism — where, when and which way the puck can leave the stick

Status: **Phases 1, 3 and 4 built and playtested; Phase 2 not needed.** The
wrist shot's load (*Phase 1*), the bots onto it (*Phase 3*) and the keeper's
body in the bots' shot model (*Phase 4*). The hard cone this plan first proposed
was dropped for the load.

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
| where the puck leaves | wherever the blade sat at the press, frozen | the same since Phase 3; before it, one of three lateral offsets eased there *during the frozen hold* at a 60 m/s on-axis aim budget no human has |

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

## Phase 1 — the wrist shot's load (as built)

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
- **Arms:** the arms push the blade away from the hands: full on any shot out
  from the body or up to `wrister_arm_full_past_tangent_deg` (45°) past the
  tangent toward it, linear to nothing on the line back through the body.
- **The cap:** `min(cursor-speed power, max_wrister_power ×
  (wrister_unloaded_share × arms + (1 − wrister_unloaded_share) × alignment ×
  coil))`, × the backhand coefficient. With no turn behind it a shot out from the
  body still carries 60% (the arms, wrists and stick flex — measured
  trunk-rotation gains are a few m/s on a 25–33 m/s shot); one back through the
  body carries nothing, which leaves a puck in front as a drop pass. The goalie's
  predicted shot takes the same cap.
- **The finish follows the load.** The hips turn and the stick swings onto the
  shot line by the load's share of the way (`ShotMechanics.finish_line`); an
  arms-only shot holds the hips and pushes the stick through where the puck sat.
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

Bots play under the same load since Phase 3.

## Phase 2 — a release clock (not needed)

**Not built, and not needed for now.** The question it answers, what stops a
full-power wrister coming off the stick in 50 ms, is answered by the load: a puck
out of the pocket fires at a share of its pace, so a full-power release means
getting it there first, and that pull costs real time for humans and bots alike
(the blade's travel, round the body when it must go round, the turn when the turn
is what loads it). Playtested with that, no further clock was wanted. The design
below stays as the record if one ever is.

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

## Phase 3 — bots onto the human toolkit (as built)

Phase 1 put humans under two rules bots were exempt from: facing follows
travel (`FacingRules`) and the wrist shot's load (`WristerLoad`). Both are pure
functions of state the bot already has, so the work was not new physics. It was
teaching the bot to play inside them: its decisions price them and its execution
respects them. No bot-only gates.

**The finding that shaped it.** A bot carried and pre-aimed with the puck about
1.3 m straight out on the line to its target (`CARRY_BLADE_AIM_FORWARD_M`). A
shot or pass fired at that target runs radial to the body, which the load scores
as zero: switching the cap on alone would have capped nearly every centred shot
and forward pass at 60% (about 19.8 m/s), below the 20 m/s pass target
(`PASS_TARGET_CLOSING_M_S`). So the bot had to carry and release like a player
who loads the puck, not just have the rule switched on.

### 3a. Facing (as built)

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

### 3b. Carry and release with the puck loaded (as built)

- **One rule for both.** The controller applies `WristerLoad` to bots exactly as
  to humans: the hand and the cap come from where the puck sits at the press.
  `RELEASE_SAMPLE_FRACS`, `bot_wrister_origin_offset`, `bot_wrister_backhand` and
  the 60 m/s on-axis ease are gone.
- **The bot's load configs are its body's.** `AISkaterCaps` carries the
  controller's `WristerLoad.Config`, `FacingRules.Config` and unloaded share, so
  the bot prices and executes under the numbers its body fires with.
- **The pocket.** `WristerPocket` (pure; `test_wrister_pocket.gd`) names where to
  hold the puck so a release toward an aim loads best: the aim turned a quarter
  turn either way and an eighth either side of each, each read in the frame the
  body will face with the cursor there (`FacingRules`). At speed that is beside
  the stick hip; at rest the body turns side-on with the puck in front.
- **Carrying to it.** While a shot look dominates, the fire-tracking carry holds
  the puck at the shoot-now sweep's winning hold (below), so the press usually
  finds it already there. Pre-aim for a shot, a charged pass or a dump-in / rim
  carries the puck to its hold and presses once the live load reaches the share
  it was priced at (`_load_ready`, 0.05 slack, the old 0.5 s timeout as the
  backstop). The pull goes around the front of the body when the straight line
  to the hold would run through the skater (`BladeRoute`), and is priced on
  that route. A hold behind the body is swung round to at the bot's arc rate,
  on the hold's own reach, and priced at that swing's time. A charged release
  fires along its committed aim from wherever the puck sits, so it waits on
  neither the aim nor the body. (Every bot release is charged now; the Aim-B2
  reach-cone commit went with the one-tick quick release.)
- **A pass holds the puck where it is** when that already carries the feed's
  pace, else goes to the pocket for it (`_lock_pass_hold`). A backhand pass's
  power is committed over the backhand coefficient so it leaves at the solved
  pace.
- **The wind-up is drawn on the load's hand.** The poke-avoidance side flip went
  with it: the frozen blade never drew the puck into a defender's stick.

### 3c. Pricing in the same currency (as built)

- **Shots: a hold sweep.** The shoot-now eval prices up to four holds — the puck
  where it is, the best-loaded pocket, and a reach out to either side of the
  shot line — each at the pace its load allows, from where the pull puts the
  release, with the pull's time in the goalie's budget. The side reaches are
  the old lateral relocations (the pull-across, the backhand tuck), now at the
  load's honest pace rather than a flat backhand coefficient. A pull costs the
  blade's travel, or the body's turn onto the cursor when the turn is what loads
  the puck (a forehand pulled beside the stick hip is loaded before the body
  moves). The as-is hold is scored first and ties keep it. The tip read fires
  from the faster of the as-is hold and the pocket.
- **Each hold is priced at its keep** (`AIShotHolds.price_keep`): the odds the
  puck survives the route the blade walks to it (`BladeRoute` to a hold in
  front, around the body to one behind) and the charge there, against every
  opponent's reachable stick. A stick sweeps its own reach faster than a pull
  crosses it, so a route dragging the puck nearer a man is read where it passes
  him closest as a puck parked there. Without it a trailing backchecker stripped
  HARD at +25° in `test_real_rush_sim.gd`: the two side holds near-tied, the bot
  flipped between them, and the pull across ran the puck through his body and
  his stick. The pull now also goes round the front.
- **Passes:** the launch-pace solve is capped at the pocket's share
  (`_pass_launch_cap`), on both the scored and the fired pass.
- **Not priced yet:** a pass's pull time (the back-wedge rotation charge,
  `_facing_rotation_time`, still stands in for it there, though a charged pass
  no longer turns for its aim), and the rim and dump-in pace ladders (still
  searched up to the full wrister). The bot pulls to the pocket for them at
  execution, so the pace holds; only the time is unpriced.
- **Carry candidates' shots** on arrival are held where the sweep would hold
  them: the best pocket for the line at the arrival pace, or the line's other
  side when a stick covers the pocket, at that hold's pace and keep, plus any
  pull the carry is too short to make (`AIShotHolds.solve_arrival`). The keep
  discounts the shot only, never the spot's position value, and the hold is
  not solved where the shot is not what the spot is priced by (outside the
  zone, from outside it, at a keeper home). The carrier's own drive-in credit
  reads the same way. Teammates' shots keep the full-pace read: their hands
  are not modelled.
- **Measured** (Phase 4 carries it on). Point-blank
  conversion against the live keeper (`test_bot_vs_goalie_conversion.gd`, 63
  rushes per goalie tier) went from HARD 6% / NORMAL 19% / EASY 33% to 51% /
  41% / 40%. The side holds are now really pulled to before the press (mean
  release-to-keeper 0.42 → 0.88 m) where the old offset was mostly never
  delivered, and every release outside a down keeper's pad edge scored (13 of
  13). Without the side reaches (as-is and pocket only) it is 16% / 17.5% / 13%.
  Either way the goalie-tier ladder flattens. This is Phase 4's problem, now
  with the release the bot really takes.

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

## Phase 4 — point-blank, in the bot model (as built)

The aim is that driving into a set keeper stops being the optimum, without a
positional gate. Two pieces:

1. **Score the executed release.** Phase 3 does this: a side hold is pulled to
   before the press and priced from there, at its load's pace, so a release
   beside the pads is one the bot really skates and stickhandles to rather than
   one eased out during the frozen hold. The depth-only `release_ahead_of_goalie`
   stays as the degenerate-geometry guard it is documented as.
2. **Let the seam see the keeper's body in tight.** The public xG form is fitted on
   shots whose doorstep share is mostly rebounds and displaced keepers, so its
   point-blank value is mostly *those*. That is why it reads ~0.8 from 0.9 m.
   Against a set, square keeper the open mouth from that spot is nearly nil.
   `AIShotValue.body_logit` adds that geometry to the seam:
   - **The term:** `ln(open / open from the slot distance on the same bearing)`,
     never positive, in the same `ln(available width)` currency as
     `POST_SEAL_LOGIT`. The public form's angle term already prices how much
     more of an oblique mouth he covers, so the reference is per bearing and the
     term is only the closing in.
   - **`open`** is the share of the mouth his silhouette leaves, projected from
     the puck onto the goal line at six heights: his structure and hands
     (`GoalieAnatomy`) in whichever one stance, standing READY or down, leaves
     this look the least, and only up to the height the SHOOTER's own steepest
     rung arrives at, at his pace (his blade curve's ladder, the league M92 one
     when the build is unknown). So nobody roofs the doorstep, and over the
     butterfly pad is open in tight exactly as `docs/elevation-rework-plan.md`
     designs it.
   - **The keeper it reads:** the displacement term's, off his square by the
     deficit, at the depth the shot's predicted keeper is (`score_shoot_value`
     passes it), else at the depth a set keeper holds for that puck
     (`AIGoalieModel.set_goalie_depth`, the planner's own depth solve). So a
     set keeper shuts the doorstep, a keeper backed into his crease does not,
     and a keeper beaten off his square in tight concedes it.
   - **At range nothing changes:** the term is zero and the seam is the public
     form plus displacement exactly.
   - **Measured** (`test_bot_vs_goalie_conversion.gd`, 63 rushes a tier):

     | | conversion H / N / E | shots from 0–3 m | drive-in value vs actual | flyby value vs actual |
     |---|---|---|---|---|
     | Phase 3 | 51 / 41 / 40% | 63 of 63 | 0.59 vs 0% | 0.61 vs 64% |
     | body term | 41 / 43 / 35% | 54 of 63 | 0.36 vs 10% | 0.50 vs 47% |
     | + shooter's own rung, one stance | 25 / 51 / 40% | 58 of 63 | 0.40 vs 0% | 0.53 vs 30% |
     | + real M92 default ladder | 37 / 35 / 40% | 5 of 63 | 0.18 vs 14% | 0.19 vs 39% |
     | + main's goalie changes | 54 / 43 / 40% | 4 of 63 | 0.20 vs 29% | 0.21 vs 57% |
     | + the pull goes round the front | 46 / 35 / 35% | 6 of 63 | 0.20 vs 14% | 0.19 vs 50% |
     | + behind-the-body swing, carry priced on the hold | 38 / 37 / 29% | 8 of 63 | 0.27 vs 13% | 0.20 vs 42% |

     The harness bots never get caps applied, so before the last row they
     priced their own shots on a 24° ladder no stick has. On the real one they
     shoot from 3–7 m, not the crease, and releases outside a down keeper's pads
     no longer score (0 of 8). The model now under-prices the flyby, and
     main's goalie changes widened that (0.21 vs 57%). A pull across that
     goes round the body instead of through it takes longer, so the keeper
     follows more of them (the last row).
   - **Left open:** the pull wide in tight still beats this keeper about half the
     time, and the model now prices that honestly. And the planner predicts a
     keeper backing in on the rush backflow while the straight-rush trace
     (`test_real_rush_sim.gd`) shows the live one coming out to meet the carrier.
   - **The displacement term stays.** A keeper beaten wide still opens the net,
     which is exactly the lateral cut the model is meant to reward.

A deke-the-goalie read (fake, then cut across) is the natural follow-on. It is
not in this plan.

### Tests

- A carrier fixture: a breakaway on a set keeper fires before the crease, or cuts,
  and does not carry to within the jam distance.
- The existing breakaway and cutback fixtures stay green
  (`test_goalie_breakaway_ladder.gd`, `test_human_wraparound.gd` for the
  goalie side).

## Open questions

1. **Bot movement.** The request also mentioned how bots *move*. Nothing here
   touches locomotion.

## Flagged, not in scope

These are left for issues.
- **The blade's exclusion circle around a standing goalie (0.50 m) is narrower
  than his pad span (0.56 m).** A blade can sit inside the outer pad column.
- **A puck released inside a goalie box is pushed out along the minimum-penetration
  axis** (`swept_disc_obb.gd`). For a 0.2 m-deep pad that can be the net side.
  This is inferred from the code and not reproduced.
- **`Puck.release` sets velocity to `direction × power` exactly.** The skater's
  own velocity is folded in before it, for wrist shots and quick passes
  (`docs/release-momentum-plan.md`); slapshots and one-timers do not inherit it
  yet.
- **The goalie's poke reaches 0.25 m** (audit F11). He has no in-tight answer to a
  carrier on his doorstep beyond the block.
