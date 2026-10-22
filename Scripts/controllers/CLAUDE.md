# Controllers

Scope: `Scripts/controllers/` — the layer that drives actor bodies from
decisions. Controllers use the domain to decide and reach into infrastructure to
execute; they never reach up. Goalie *math* is pure and lives in
`Scripts/domain/rules/goalie_*.gd`; the doctrine below governs both halves.

## Goalie subsystem map

| File | Owns |
|---|---|
| `goalie_controller.gd` | the tick, state transitions, tuning `@export`s |
| `goalie_state_machine.gd` | stance transitions |
| `goalie_body_config_builder.gd` | pose solve into a shared scratch config |
| `goalie_shot_reaction.gd` | the read pipeline (delays, belief, convergence) |
| `goalie_puck_play.gd` | behind-net trip decision, geometry, phase |
| `goalie_crease_clear.gd` | loose-puck sweep / cover |
| `goalie_slide_behavior.gd` | committed slides and post seals |
| `goalie_footwork.gd` | upright footwork: shuffle stroke, T-push, edge stop (pad steps over the eased stance) |
| `goalie_world_view.gd` | the perception surface |
| `domain/rules/goalie_behavior_rules.gd` | reads, depth, races (pure) |
| `domain/rules/goalie_push_rules.gd` | the upright push: accelerate, cruise, stop on the spot (pure) |
| `domain/rules/goalie_save_selection.gd` | block-or-react, as one question |
| `domain/rules/goalie_pass_read.gd` | where a pass in flight will be shot from |
| `domain/rules/goalie_screen_depth.gd` | room to see around a screen |
| `domain/rules/goalie_tip_depth.gd` | challenge depth against a net-front stick |
| `domain/rules/goalie_save_rules.gd` | rebound doctrine |
| `domain/rules/goalie_depth_solver.gd` | depth constraint composition |
| `domain/rules/goalie_stick_rules.gd` | stick geometry and coverage |

### Filter the puck, not the man

The threat the goalie squares to used to be low-passed as a whole — one lerp over
the blended puck/carrier position. A first-order filter has a **permanent**
steady-state error against a constant-velocity target: it settles at trailing by
`speed / k` and no amount of run-up closes it. So the filter charged the
carrier's real translation a trail proportional to his speed — measured at 0.20 s
of it beyond `chest_track_far_distance`, i.e. 1.6 m behind an 8 m/s skate.

That trail then entered the SQUARING error a second time, because the body
rotates toward the tracked threat rather than toward the puck. The two lags
compound, contributing about equally at 8 m, and together left him 26° off square
against a shooter crossing at 8 m/s — with the pads, glove, blocker and five-hole
all posed in that rotated frame.

The fix is that jitter and signal are **separable**, and only one of them needed
filtering. A carrier's BODY does not teleport; it is the smooth part and
low-passing it buys nothing. What wiggles is the puck's OFFSET from him (±1.5 m
of dangle) and the velocity estimate built from it. So the offset and the puck
lead stay inside the filter at exactly their old time constants and the body
rides through raw. Steady state is unchanged — once the offset converges the
blend reproduces the old one exactly — which is why `GoalieBehaviorRules
.compute_threat_position` is fed a jitter-filtered puck rather than re-derived.

Two things that bite:

- **The puck lead must stay inside the filter.** It is built from a raw per-tick
  position difference, so unfiltered it hands the goalie precisely the dangle
  spikes the filter exists to reject.
- **Removing the trail leaves the LEAD unopposed.** `carrier_velocity_lead_time`
  was cancelling the trail in tight (0.12 s of lead against a 0.125 s trail) and
  losing to it at range. With the trail gone the lead is net anticipation
  everywhere — he now plays *ahead* of a moving carrier by that much, which is a
  deliberate, beatable-by-cutback property rather than an accident, but it is a
  different quantity from what the number was chosen for.

`test_goalie_tracking_lag.gd` holds it, and asserts structural properties — trail
proportional to speed, the compounding — rather than pinned numbers, so replacing
a filter with a rate limit fails it rather than passing quietly.

### Delete the copy, don't correct the number

Nothing connects a literal to the collider it was copied from, so every
hand-built replica of the keeper in the planner — pad splay, glove reach, torso
size, the depth chart, the band harness — drifts off the body that actually makes
the saves, silently and without anyone being wrong on purpose. `GoalieAnatomy`
(his dimensions) and `GoalieStickRules` (his stick, split out because the blade
also owns an aim solve) are the single source: anything the planner believes
about the keeper's SHAPE derives from them, so changing the body moves the
planner for free.

### The stick's angle is not a pose choice

Shaft, paddle and blade are one rigid piece hanging a fixed distance below the
wrist, and the lie (117°) is the angle between paddle and blade in the plane of
the blade's FACE. Two things follow, and every stance obeys both:

- **The roll is fixed.** Only the paddle leaning the lie's complement sideways
  (`GoalieStickRules.FLUSH_ROLL_DEG`, top toward the blocker side) lays the
  blade's length flush on the ice. Any other roll rests it on its heel or toe,
  the thing every goalie coach says not to do. Never apply the lie about the
  blade's long axis: that is a loft, and the forward tilt already owns loft.
- **The forward tilt follows the hand.** Once the hand is placed, the tilt that
  lands the blade on the ice is decided (`tilt_for_blade_on_ice`), and it opens
  the blade's face by the same angle. The last step of
  `GoalieBodyConfigBuilder.build` is the only writer of `blocker_rot.x`, so every
  modifier that moved the hand — sweeps, lunge, prelean, elevated reach — gets a
  stick that follows it.

Upright, the stance picks the tilt (`UPRIGHT_TILT_DEG`, the blade a foot out in
front of the skates) and the hand height follows (`upright_wrist_y`). Down, the
hand sits just above the pads, so the paddle lays well forward and the face
opens with it — a face square to the shooter and a blade flush on the ice put
the hand at one height, and the butterfly's is lower.

### The hands are held out, and the elbows hang

A hand posed nearer the shoulder than the arm allows can only be drawn by
folding the elbow into the body. So the pose builder places the glove at the
depth that gives a real bend for the stance (`GoalieAnatomy.hand_depth_for_bend`,
from the same arm lengths `Goalie` draws with), and the blocker where the stick
puts it: paddle rolled in, blade out in front of the five-hole — upright at the
upright wrist height, down just above the pad tops. The elevated reach
extends from the hand's rest depth, not from a fixed one.

The elbow is not aimed with a pole. A fixed "down" hint is wrong for a hand held
out in front and below, because down projects to down-and-behind, into his
chest. `TwoBoneIK.solve_elbow_hanging` lets it hang: the lowest elbow the bones
allow that stays out of the trunk — never inside the shoulder, and back past it
only once it is out beside the body, which is where a butterfly blocker's elbow
goes. `test_goalie_arm_rig.gd` holds both.

## What kills a collaborator extraction

**A collaborator may accept any number of inputs written from outside. It must
exclusively own every field it writes itself.**

Measured across the goalie's own collaborators — contested means a field both the
collaborator and the controller assign:

| collaborator | caller-written fields | contested | methods that died |
|---|---|---|---|
| `goalie_puck_play` | 20 | 0 | 0 of 11 |
| `goalie_shot_reaction` | 7 | 2 | 0 of 10 |
| `goalie_slide_behavior` | 13 | 2 | 0 of 13 |
| `goalie_crease_clear` | 37 | 12 | 17 of 27 |

`GoaliePuckPlay` takes the most caller-written fields of any of them and is
perfectly healthy, so "the caller writes to it" is not the problem. Sharing
ownership of one field is. Once the controller writes `_clear.cover_cooldown_timer`
it has re-derived when to write it — the lifecycle — and the collaborator's own
`tick_cover_cooldown` is redundant from that moment. Twelve contested fields
produced seventeen unreachable methods, none of which failed anything.

Copy `GoaliePuckPlay`'s field layout: tuning pushed at config time, geometry set
once at setup, trip state owned outright, and an explicit "requests to the
controller" block read after `advance()`. One per-tick entry point that takes the
world as arguments and clears its own outputs at the top.

## Depth is the A/B/C/D ladder, and it is not compressed inward

The Buckley zones are *situational*, not a distance chart. A is ~2 ft outside the
crease top — challenge a rush, a breakaway, or a clean look and force the shooter
to beat you. B is heels at the crease top, where most shots are faced. C is the
middle of the blue paint, held when a lateral play is live. D is on the post or
tracking behind the net.

At these shot speeds a slot shot leaves almost no lateral reaction window (~0.04 m
of travel in flight), so **cutting the angle by challenging is what makes the
save, not reflexes** — depth pulled inward to look safer is a goalie who cannot
make the save he is standing there to make. The "play conservative on a lateral
threat" read is produced dynamically by the lateral tracking cap and the backdoor
depth cap, never baked into a distance curve.

The anchors are real geometry: the NHL crease top is ~4.5 ft ≈ 1.37 m, which is
`CreaseRules.STRAIGHT_DEPTH`. Depth is gated on a real rink landmark (goal line →
blue line) rather than a tuned distance, because geometry alone would park him at
the challenge ceiling for a puck at the far blue line, where the net subtends
almost nothing.

## Beatable realism

The goalie should look and move like a real goalie while staying deliberately
scorable. **Realism should not produce an unbeatable goalie; it should produce
one who gets beaten the way an NHL goalie gets beaten.** Making him better is
not the failure mode — closing off a way he *ought* to be beatable is, and a
save count alone cannot tell the two apart.

Two recurring traps, both measured:

- **A goalie who pre-commits cannot be read, and being readable is the game.**
  Every change that made him block or commit earlier has measured as *more saves*
  AND *deception ceasing to pay*. Deception paying negatively is the tell. If a
  change produces that signature, it is wrong even when the save count improves.
  Three separate changes have produced it: removing the `not _reaction.reacting`
  gate on the block branch (dot-line beatability 16/288 → 25/288, a cold five-hole
  window opening from nothing to 17 cm, wrong-height deception falling to 4/14
  against a 6/14 baseline); counting `WRISTER_AIM` as a shot declaration in the
  block-or-react launch clock (4/14 across all three deception arms, against 6/14
  telegraphed and 11/14 wrong-height under the read); and the tip doctrine in
  `GoalieSaveSelection`.
- **Blocking concedes the top of the net.** Any path that blocks a shot already
  read as elevated is strictly wrong. The block model has no `impact_y`.

**The seal is a commitment with an END, and arriving is what ends it.** The
verdict clears once `tuck_point_travel` is inside a puck's radius, so the reach
that term subtracts must be the one the SEAL uses — `_seal_cover_radius()`, the
distance from the seal spot to the tuck point — or he lands somewhere his own
arrival test still calls short and nothing can ever clear it. The tolerance is
not slack: an exact `<= 0` cleared only when the knee-shuffle's arc target
happened to lie past the seal spot, and a seal landing millimetres inside it
held him down for good. That reach follows the STANCE (standing
`pad_local_offset`, sealed `_seal_cover_radius()`) and is carried in
`BeatenWideConfig.cover_radius`, deliberately separate from `reach_half_width`:
one is arrival, the other is the point of no return, and sharing a number ties
the threshold that clears a beat to the threshold that decides one. Measured,
widening both at once cost 3 bot goals in 63 by declining seals he used to push
into.

Nothing may fight the seal's depth either. `min_challenge_depth` already exempts
COILING and SLIDING, but those are the states that get him TO the seal and
BUTTERFLY is the one he sits in once there — flooring him there lifts him off a
`post_seal_depth` the slide spent half a second reaching, which re-opens the beat
and commits the same slide again forever.

The shape of that failure is worth recognising: a stance loop at a fixed period
whose slide has NO lateral leg means two owners are fighting over
`_current_depth`. `test_goalie_held_puck_slide_loop.gd` holds all of it.

**A shot released from the post seal keeps him in it until it resolves.**
RVH and VH are entered only while no shot is in flight, and they are left the
same way: a puck on net released while he is sealed holds the stance, exits and
post swaps alike, until it is picked up, touches him or a post, the boards or
the net, or is no longer on net (`_holding_seal_for_shot`). Standing up
mid-flight swings the post pad into the puck's path, and a moving pad strikes the
puck with its own speed. While sealed he starts no shot reaction at all, which is
why the hold is its own flag and not the reaction's.
`tests/slow/ai/test_goalie_holds_the_seal_through_a_shot.gd` holds it.

**Down, the pad covers the post only if it points there.** The arrival test
measures the post spot against the sealing pad as a segment turned however far
his body is from the seal's own facing (`BeatenWideConfig.pad_turn_rad`). A
butterfly still turned from an earlier push the other way has its post-side pad
swung out from the line, and a wrap slides in behind it; a radius that ignored
the turn called him sealed. Sitting on the seal spot turned wrong still coils,
because the coil is what turns the pad onto the post.

**The coil turns him toward the post he seals, not the way he travels.** A cut
across the crease leaves him tracking the carrier, outside the seal spot, so he
reaches it by moving back toward the middle; turning that way pointed the
sealing pad at the other post. `GoalieSlideBehavior.facing_dir` carries the post
side, `dir` the travel.

The one sanctioned commit is the **beaten-wide post seal** — and it is sanctioned
because it is not a prediction. Its gate is positional (the puck is already past
his standing sealing reach on the side it went), so it fires on an accomplished
fact rather than a guess about intent, and the goalie pushes into the seal off
the drop as one motion instead of landing square and re-deciding. Onset needs the
puck genuinely moving across; *persistence* deliberately drops that term, because
a puck that settles wide has not un-beaten him. Pulling it back inside the
sealing reach is what un-commits him, and baiting that commit is the counter.

### Getting up is a race, and it is not a radius

`_is_threat_pressing` decides whether he holds the butterfly, and its first
clause is `_recovery_loses_the_crossing_race()`: recovering costs
`recovery_duration` of tracking nothing, so hold once the threat's own lateral
travel through that window beats his standing reach. It reads the CARRIER's
translation rather than the puck, like `_lateral_tracking_cap` and for the same
reason — a dangler's blade beats `t_push_speed` and a goalie does not move for
it, so both share `_threat_lateral_speed_x()`.

Two failures bracket it, both measured, and either is easy to re-introduce:

- **A radius.** "A hostile carrier within N metres → hold" has no term for
  whether anything is happening, so a carrier who merely STOPS in tight pins him
  down forever — 5 s and counting, frozen at whatever depth he dropped at, since
  an idle butterfly never re-solves depth either. It also contradicted the launch
  clock beside it, which prices an undeclared carrier as no time pressure at all.
  Its stated justification was rebounds, which it never covered: it required a
  carrier, and a loose rebound has none.
- **Nothing at all.** Delete the clause and he stands up INTO a walkaround,
  caught mid-recovery at the goal line — the walkaround opens 2 of 7 aim points
  with the race, 2 of 7 with the old radius, and 5 of 7 with neither.

`should_hold_seal` does not cover this on its own: the seal question asks whether
a SHOT can beat him, and a walkaround is not a shot yet.

A LOOSE puck is in the race only while an opponent can reach it before he is
back up (`_seen_contest_time` against `recovery_duration`). A rebound steered to
the corner keeps its pace to the boards, so reading its slide alone held him
down 3.7-5 s with nobody near it; a puck no stick can play during the rise is
not a shot he can be caught standing up into. `test_goalie_rebound_rise.gd`
holds it.

### He stops on his spot, and every race prices the stop

The upright mover brakes on the lead edge into its target
(`GoaliePushRules.braking_speed_cap`, at `lateral_accel` ×
`GOALIE_EDGE_STOP_DECEL_RATIO`) instead of halting dead on it. The cap is read
against the target's own motion, so tracking a moving threat costs no lag; only
a spot that stops makes him stop.

A goalie is not covering a one-timer until he is set square to it, so every
re-square race — cross-crease, backdoor depth, beaten-wide onset, the pass read
— asks `GoaliePushRules.set_reach` (push, cruise and stop), and the bots read
his repositioning the same way (`AIGoalieModel._goalie_set_reach`, and
`goalie_push_progress` for where he is at a release). Pricing a race on a push
that never stops tells the planner he arrives sooner than the mover can
deliver. The cost is real and deliberate: a short push to a fixed spot takes
about 1.25× as long.

The SAVE push is the other kind (`GoaliePushRules.cruise_reach`, through
`goalie_lateral_reach`): a pad moving through a shot's line stops the puck
whether or not it could stop there. Charging a save the stop made a squared
keeper read as beaten by shots he kills.

The footwork the legs show during those moves (`GoalieFootwork`) is laid over
the pads as a per-tick step the actor does not ease: a stroke's cadence is
faster than `part_lerp_speed`, which would smooth it to a fifth of its size.
`test_goalie_footwork.gd` holds the stroke, the turn and the overlay.

### The committed slide is a retreat, and its budget is depth

`_post_edge_reach` puts the body at `net_half_width − pad_edge · cos(slide
rotation)` = **0.154 m** off centre, because a butterfly pad lies 0.84 m along
the ice and the seal is the pad's outer EDGE on the post, not the body on it.
So a slide's lateral leg is centimetres by construction; measured over a full
beaten-wide seal from 0.78 m of challenge radius, it travels 0.08 m sideways and
1.20 m in depth, and takes ~0.48 s to settle into an idle butterfly.

Two things follow that are easy to get backwards:

- **"He commits too far out" describes the symptom, not the cause.** A commit
  baited earlier is beaten no more than a late one, because the extra time is
  time he spends finishing the retreat — which is what the live log's
  `goalie_radius` column is really reporting when it correlates with conversion.
- **The seal answers a puck that keeps going, not one that comes back across.**
  A carrier who continues to the side the puck was pulled to finds him sealed and
  facing the post; one who cuts back into the space he left catches him
  re-committing the other way, and that is the move that scores.

`test_human_wraparound.gd` holds all of it, and the same file records the two
things the instrument does NOT reproduce (it starts from a fully settled keeper,
and it never reaches the 1.30–1.60 m radius band the live log holds).

**A rebound gets a push to square, not a seal.** Down after the save, with a
shooter on a loose puck, he pushes once the knee shuffle would lose the race
to the release (`knee_shuffle_speed · backdoor_release_time`), to where he is
square to the puck and at the depth he is at — the slide with `hold_depth`, not
clamped to the seal band, which is where a body sits with its pad on a post.
A carried puck still gets the seal. A quick put-back beats him mid-push.
`test_goalie_rebound_push.gd` holds it.

**The goalie can be WRONG, deterministically.** His committed belief about where
a shot is going is the aim he read `read_lag` seconds ago, sampled from the
shooter's published `predicted_shot_velocity`, converging onto the true line over
`read_converge_time` once the puck is in flight. This is not RNG and must not
become RNG — both teams field identical goalies and it has to read that way. The
error is a pure function of what the SHOOTER did with their aim: a stable aim
through the wind-up means the stale sample EQUALS the truth, so a telegraphed
shot is read exactly as well as before, while a late swing against the grain
beats him by exactly the amount the shooter moved the aim. Repeatable, symmetric,
attributable. What falls out with no extra authoring: a long shot converges
before it arrives and is read correctly; an in-tight one does not and beats him;
a screen costs ACCURACY as well as tempo, because there is nothing to converge
with while the puck is hidden; and a deflection resets the read, so a tip in
tight beats him while a tip from distance does not.

**Being unset is DIRECTIONAL, and that is the point.** Momentum he cannot cancel
plus an open trail leg means: shoot against his motion and he cannot get back,
shoot with it and he over-slides. Both are counter-playable, and neither makes a
*set* goalie harder to beat. Loading the cost of being unset onto read latency
instead is the wrong model — latency is not directional — which is why
`move_read_speed_delay` is deliberately small.

**The prime is a permission to move, not a save buff.** The quiet-eye prearm and
the slot-proximity prime only make the limbs START moving; the cold arm read
outlasts a slot shot's flight, so uncredited the goalie never moves at all. The
flat reach-speed cap still bounds how much net he covers, so a corner picked out
of that reach beats him — "pick a corner, don't face a statue" is the in-tight
window this exists to create. A quick-release snap FROM RANGE never earns the
windup prime, which is the real "quick release beats the read" edge.

**The taught response to a clean windup is GET SET — square, stopped, at depth —
not retreat.** Backing in concedes angle exactly when the goalie has his best
look, and a windup is MORE read time, which is why slapshots convert lower than
snap shots. Being set emerges rather than being applied: the charging carrier
glides, so the arc target goes stationary and the movement converges. No depth
concession is applied to a windup; screened windups are handled by the blocking
drop, not by depth.

**The one depth term a screen earns is room to see around it.** At challenge
depth he is already tight to a slot or top-of-the-crease screen, which is where
a peek works best: the sightline pivots about the release, so a head move close
to the body swings the line past it. What blinds him is a body ON him, inside
the peek's reach of his own eyes. `GoalieScreenDepth.sight_cap` gives up exactly
the room that takes, and nothing for a screen he could not see around from
anywhere (that release is the blocking drop's). The peek holds the side it chose
on a dead-on screen (`_peek_side`); left to the sign of a perpendicular near
zero it flipped every tick. `test_goalie_screen_room.gd` holds both.

**The peek is seen, and it is the eyes the reads use.** On his feet the pose
leans the trunk from the hips by exactly the roll that carries his head to
`_eye_offset_x` (`GoalieAnatomy.roll_for_head_shift`); the head rides every lean,
footwork's included. Only the roll goes on the wire, so the network pose
rebuilds the head and the trunk's hip pivot from it. Never put the head
somewhere the sightline is not: a peek you cannot see is one a shooter cannot
read. `test_goalie_screen_peek_pose.gd` holds it.

**A tip is covered by where he stands, never by a reaction or a pre-commit.**
Its flight from a net-front blade is shorter than his read, and he is frozen
on the shot until it is touched, so there is no race to run. `GoalieTipDepth`
holds him on the tip's line (`r · sin θ <= butterfly half-width`) for a stick
he could not react to. From the point this costs nothing: the direct shot is
a reaction save at any depth, so A's extra angle only sold the redirect. A
stick on the shooter's line needs nothing, since challenging covers it. A
BLOCK on tip risk is the pre-commit trap above and stays out.
`test_goalie_tip_threat.gd` holds it.

**A pass is not a shot while a stick can still take it.** Passes fire
`puck_released` like any shot, so a feed whose line runs on at the net reads as
a low shot, and a goalie who drops for it hands the receiver the top of the net.
Two rules keep him up until going down is clearly the answer:

- **The leg drop waits on a stick ahead** (`_drop_waits_on_a_stick`) while the
  puck, once past that blade, still leaves the drop its time before the goal
  line (`GoaliePassRead.can_wait_out`). Only the drop: he has been on the line
  since the release, and a puck that slides past untouched is the line he
  already read. A doorstep stick leaves no such time, so a shot through it drops
  him exactly as before — the tip doctrine above is untouched.
- **The pass read's drop-and-slide answers a one-timer, and waits for one** — a
  receiver loaded before the feed (`SkaterStateMachine.state_loads_one_timer`).
  One who is not has to catch it and shoot again, which is a save made standing,
  so he walks to square on his feet and keeps reading; a late load is still
  answered. The cross-crease fork's pads-first branch asks the same thing.

A caught puck also ends the old shot's drop: the freeze outlives the catch by
its clear delay, and the carrier is the block-or-react question's from then on.
`test_goalie_pass_is_not_a_shot.gd` holds all of it.

**Three low-save shapes, picked off the converged read.** On a pad face he
stays standing. Wide of one standing pad, inside a flat pad's reach and low
enough for it, he goes to the HALF-butterfly: that pad down, the other leg
loaded on its skate. The five-hole, a rising shot, or a read that hasn't
converged get the full butterfly. The half's cost is the up-leg side, so a man
alive there sends him full. Its payoff is the loaded leg: a slide from it
skips the coil, he moves at shuffle pace instead of knee-shuffling, and the
rise is half as long. The full butterfly has two poses of its own: the square
BLOCK sits tall with the hands tucked, and every other drop leans out with
the hands ready. The half states ride the wire as `state_enum` values (v60).
The bot shot model does NOT read them as down (`GoalieNetworkState.is_down`):
the down pad measures flat through the replicated pads, and the up leg keeps a
standing leg's drop and the arm's reach.
`test_goalie_half_butterfly.gd` holds it.

**`elevated_threshold` forks the LEGS, not the hands.** Under it he drops, and
flat the pads are 0.28 m tall, so a corner shot at 0.3-0.6 m clears them wide
of the trunk. The hands take every shot read over the flat pad top, after the
arm read. Left to the legs alone, that band was the one way a set keeper lost
clean shots from range. The hand aims where the
believed line crosses HIS plane, not the goal line: from an angle he stands out
on the shooter's line, and the goal-line x sends the blocker, and the stick on
it, past the puck. `test_goalie_hands_over_the_pad.gd` holds both, and that the
arm read still loses in tight.

## Behind-net puck play — the doctrine

**"Stop it, leave it, get back."** The goalie leaves his net ONLY to trap a rim
behind it. He never carries and never passes: the misplay-prone tiers of real
puck handling are deliberately absent, because an AI turnover behind the net is
the most frustrating failure a goalie can produce. A pure stop has no turnover
mode — the only failure available is a bad GO decision, which is exactly what the
races pin.

Everything about the decision is deliberately conservative:

- the forechecker is modelled at **FULL SPRINT from the first instant** (no
  reaction delay, no acceleration ramp) — the fastest opponent physics allows, so
  the pressure clock always UNDER-estimates the time available;
- the goalie's clock counts the **WHOLE trip** — out, the stop beat, and the
  return to his post — before pressure arrives, not just the touch;
- an opponent near the net front **vetoes outright**;
- the race is **re-run every tick** of the trip with a stricter margin (abort
  hysteresis), so a conservative goalie visibly bails early rather than ever
  getting caught out;
- the trip routes around the post via a waypoint — never through the net.

Only the HARD tier plays the puck at all (`puck_play_go_margin` is INF below it);
timid puck play is a real weaker-goalie trait.

## Difficulty

Goalie tuning is bundled per tier in `GoalieSkillProfile`. HARD leaves every
value at the controller's authored default, so HARD is the authored goalie by
construction.

Whenever the bots' shot model reads the same quantity as a goalie knob, the two
must be synced (`AIGoalieModel.set_goalie_profile`) or the bots score against a
goalie they do not face. See the AI MIRROR note in `goalie_skill_profile.gd`.

**On a breakaway the ladder lives on the cutback, and comes from the push.**
Every tier seals the walk-around (0 of 7 aim points). Cutting back across opens
EASY 5, NORMAL 3, HARD 3: a race to re-commit, where depth sets how far he has
to come back and the tiered butterfly push (`slide_push_speed_mps`, softer the
weaker the goalie, like every other movement speed) sets how fast. His edges
(`lateral_accel_mps2`) move it too, because he brakes onto his spot and a weaker
edge sets him there later. The read latencies, the drop time, the five-hole and
the poke do not touch it; the toe-out moves it by one. Depth cuts the wrong way —
a goalie who challenges the rush harder is easier to beat back across — and the
push is what keeps the ladder the right way up.

Pulling `depth_base_m` in is not free — it concedes the centre-lane rush from
5 m, which is what challenge depth exists for. `test_goalie_breakaway_ladder.gd`
holds both halves so neither can be improved quietly at the other's expense, and
Hard's 1.30 m base is the taught B position, heels at the crease top — a rink
landmark rather than a tuning number.

## SkaterController

`SkaterController` delegates to seven `RefCounted` collaborators —
`SkaterAimingBehavior`, `SkaterIKCoordinator`, `SkaterPoseCoordinator`,
`SkaterShotPoseCoordinator`, `SkaterSkatingCoordinator`, `SkaterStickCheck`,
and `SkaterSettleGate` (the settle lock a hard catch leaves; its deadline
contract is in `Scripts/networking/CLAUDE.md`). `GameManager` calls
methods on the controller and never pokes collaborator internals.

**Attributes, one line each.** Skating splits three ways: top speed rides the
skate profile alone (size never buys it), first-step burst and agility ride
height and weight, so a small player is explosive and shifty without owning the
top gear, and a heavy build feels it in the TURN rather than being glued to the
ice. No build
tracks the cursor more precisely ("your hands are you"). The blade caps derive
from lever geometry instead: the long lever sweeps but cannot cut back, the
short lever is the scalpel. Shot power means "what a charge buys you, and how
fast you can charge it", never the uncharged snap. Full detail lives in
`Scripts/domain/state/CLAUDE.md`.

`apply_attributes` is **idempotent**: it captures baseline values on first call
and recomputes from those baselines every time, so repeated applies (the
free-play picker) never compound. Config objects built from `@export`s are cached
here and rebuilt on apply — do not restore per-tick rebuilds for live tuning,
which is not a workflow on this project.

## The gait publishes channels; it never writes body rotations

`SkaterSkatingCoordinator` is the whole procedural gait — no animation clips,
everything derived from replicated velocity plus the intent byte, so it costs
zero network state and a wire-fed remote animates identically to a
locally-simulated one. It runs at RENDER rate (`Skater._process`,
visibility-gated) and is guarded by `not is_replaying` so reconcile replay never
over-spins the phase — which also means it can own no timer, and is why the
celebration window is aged by its callers at physics rate instead.

**It writes leg swing, the ankles' give-back, edge loads and the crouch drop directly
onto `Skater`, and never a torso or lower-body rotation.** The crouch lowers the
visible body only — it is render-rate, and the hands and blade hang from the
gameplay frame — except in the held poses (block, faceoff set, knockdown), whose
layers hand the frame their drop by their weight (`GaitPose.frame_share`)
because those hands are posed in a frame that went down with the body. Everything rotational
is *published* as a field for `SkaterPoseCoordinator` to sum into one write:
`trunk_pitch_add` / `trunk_roll_add` (torso texture), `stop_yaw_offset` (hockey
stop), `travel_align_yaw` (hip-to-travel alignment, which the pivot also drives
while engaged), `shot_hip_yaw` (shot coil and uncoil), and `pivot_hold`
(authority, which fades the generic facing-lag pump out of the sum). Two writers
tracking one rotation on different clocks is a wobble, not a pose — hence one
summing site rather than five writers. The trunk texture in particular goes onto
the cosmetic torso, helmet and shoulder BONES, never onto the `UpperBody` node,
whose rotation carries the blade markers and is therefore gameplay geometry.

### The legs skate a state, and the state is the physics' decision

`SkaterLocomotion` owns the locomotion half: glide, stride, crossover, carve,
backward, shuffle, skid, tight turn and stop. Which one is not re-guessed from
how the stick happens to point; it is what the movement model is doing
(`LocomotionRules`, a pure function of velocity, move intent, brake, facing and
the measured turn — all derived from replicated state). Two quantities decide
it: whether the skater is **driving** (the stick's component along travel,
which is what the physics thrusts by; against travel it is a skid) and how much
of the edge's grip the travel's curve is **using** (centripetal acceleration
over the league's `turn_accel`, not the build's own grip, so the same curve at
the same speed reads the same on every build). How hard the legs stride is the
speed over the BODY's full pace (`gait_full_speed` × leg length), never the
build's top speed: the picture comes from height and weight, not from stats. Driving straight is a stride, driving
through a turn a crossover, coasting straight a glide, coasting round a turn a
carve. A stick held straight across travel turns the skater with no thrust, so
it is carved, never crossed over. Each state owns its legs outright while it
holds weight; nothing fades against anything else.

Things the split alone would get wrong, handled where noted:

- **Crossovers commit, corrections do not.** A steering tap at speed does curve
  the travel, but skaters correct a line on their edges and cross over only
  through a held turn. The crossover eases in slower than anything else, and
  SIGNED — taps alternating sides have to pass through zero, so they cancel —
  and the part of a turn not yet committed is skated as a carve.
  `test_body_chain.gd` holds both halves and the coasting carve.
- **The weights say whether, not how hard.** From half the thrust
  (`LocomotionRules.DRIVE_FULL`, a stick 60° off travel) the legs are pushing;
  how hard is the stroke's amplitude, which follows the measured acceleration.
  A linear split made a 45° arc half carve.
- **A turn's inside is the curve, never the stick.** `turning` is signed by
  the way the travel curves, and the classifier takes the side from it. Once
  the travel has come round to a held key the stick lands on alternate sides
  of it tick to tick, and a pose keyed to that swapped its legs every frame.
  The carve and the tight turn ease signed like the crossover, so a reversal
  slides the legs through centre. Their lead is along travel, so the legs
  carry it by travel's share of the hips' forward axis, never its sign: with
  the cursor ahead and the momentum swung behind, travel crosses the hips and
  a sign swaps the skates in a frame. `test_gait_turn_continuity.gd` holds both.
- **The cadence is the stroking states' own.** The stride phase advances at the
  stroking states' rate averaged over them alone, so a crossover sharing the
  mix with a carve fades in amplitude, never in tempo.
- **Speed sets the tempo, and acceleration quickens it.** The speed law
  saturates at a cruising ceiling. Driving hard steps faster at any speed
  (`accel_cadence_rate` × `effort`), past that ceiling, because each push gives
  only so much. A start is quick short steps that lengthen into the stride as
  the acceleration tapers off. A floor that fades with speed alone cannot draw
  that: the physics reaches its fade in ~0.4 s, and the cruise tempo takes
  over while the skater is still gaining speed. `test_gait_step_events.gd`
  holds the shape.
- **The glide is the remainder.**
- **The weights ease on springs, not lags** (`EaseRules`, critically damped,
  ω = `OMEGA_PER_RATE` × the blend speed): the mix, effort, the loaded stance
  and the stroke's intensity, and the stance layer's blend. A lag answers a
  change of state at full rate on its first frame, and every leg target is a
  blend of those weights, so the body stepped in a corner on every change of
  state: the crouch dropped at ~4 m/s from rest the tick a stop began. The
  shuffle keeps its lag: its step is laid from the base closed, where a quick
  onset costs nothing and a slow one lets the planted skate slide
  (`test_shuffle_steps.gd`). `tests/instruments/actors/test_body_smoothness.gd`
  measures the per-frame jerk of every bone through each transition.

The legs are solved from where the ankles go (`LegIK`): `GaitPose.seed_legs`
places each ankle from the stroke's joints on the stance, lays on the states
authored as where their skates go, and solves the leg to it; the layers lay
their joint offsets on that. Every state but the glide is authored that way
(`SkaterLocomotion.authored`): the stride (`_stride_path`, out and back from
under the hips, toe turned out; from low speed, out of a V, since the blade lies
along a track that the body's speed lays back), the crossover (`_crossover_path`, the stride's
phase law with its own landings: the outside skate lands crossed over and
pushes back out, the inside one pushes under the body, so they cross every
step), the carve and the tight turn (both down, the inside skate leading), the
hockey stop (`_stop_path`, both planted wide along travel with the hips sitting
back of them, turned square across it), the skid (`_skid_path`, a snowplow),
backward C-cuts (`_ccut_path`, out and ahead and back in) and the side-step
(`_shuffle_path`, step-together in any direction: a side-stepping blade cannot
glide, so each skate holds its place on the ice while the hips pass over it,
and the cycle is laid over the ground, one `shuffle_step_distance` a cycle;
`_sense_step` steps only for the shuffle itself (the brake with a stick, slow:
`SkaterMovementRules.is_shuffle`) and, let go, holds the step through its
settle to rest; an unbraked push from rest, any way, is a start and never a
step, `test_shuffle_steps.gd`).

**The shuffle is a chord, and nothing about it is on the wire.** The movement
model reads the brake and the stick it already has: at or below
`SHUFFLE_MAX_SPEED` the brake with a stick drives the body toward the stick at
`shuffle_speed` (on the stop's own edges, at `stop_decel`, so a stop slows
straight into it), and above it the brake is the stop and the stick is ignored.
The local input is shaped before it is recorded (`ShuffleStepShaper`): a shuffle
let go of holds its stick until the step-together closes and brakes to rest
there, and a stick already driving along the travel when the brake goes on at
speed is held off, so W held through a stop stops. Bots never shuffle: their
brake keeps steering in the stick, so `AIController.apply_decision` drops it
under the brake below the gate (`AIBotMechanics.braked_stick`), and
`AICarryRollout` prices a BRAKE as that stop. The glide is the stance with a joint-space
edge sway and, out of a turn, a light inside knee; as it comes still it stands on
the ice like the authored states (`SkaterLocomotion.on_ice`, `1 − glide × speed`)
on soft knees (`rest_stance`), so a standing skater's lean settles over two
planted blades instead of rolling one off the ice — no knee change can put a
blade back down there (`test_blades_stand_on_the_ice.gd`, the stop from the
side). The reach sit still follows `authored`, the strokes' own share, and each
stroke's reach counts by its weight in it, so nothing switches on as a state
fades. Three things make them stand on the ice:

- **They sit as low as their pushes need.** A leg can only reach so far out at
  the hip height it is at, so the crouch moves, by the authored share, toward
  the one that lets the furthest skate reach the ice (`GaitPose.reach_hip`,
  capped at `stride_sit_max_deg`). The reach eases in near full stretch rather
  than halting the knee mid-swing, depth first so a target too deep to stand on
  never stands the leg straight under the hip. Driving hard reads deeper and
  wider than cruising for that reason, not by a separate tunable. Every one of
  those corrections moves by the authored share, so none switches on.
- **They are authored on the ice, not on the hips.** The hips pitch with the
  lower body and tip with the balance lean about the ice under the body, so
  their targets are turned through that tilt (`GaitPose.ice`, `lean`): the
  skate stays where it was put and the body goes over it, so a turn's bank
  puts both blades on their edges. The stop and skid scrape along with the
  body instead (`SkaterLocomotion.sliding`): they keep their place under the
  hips and the lean only lays them level, or a stop's lean would pull the hips
  off its front skate.
- **They aim the runner, not the ankle.** Their blades lie flat along their length
  on whatever edge the leg rolls them to (the ankle's level give-back), and an
  edge raises a runner toward its ankle, so the ankle comes down by what the
  edge takes off and the leg is solved again.

A layer that widens the base does it the same way: `GaitLayer.stance_width`
is an ankle offset the solve reaches on the ice, so the loaded stance widens a
stroke's path rather than rolling the solved legs off it.

### Overlays are layers, and the order is the priority

Everything the gait lays on the stroke — the faceoff stance, the loaded skating
stance (Shift), the shot loads and kick, the check commit and drive, the board
pin, the press (a driver's lunge into the man, a dug-in man sat back into it),
the stick lift, the celebration bounce, the stagger, the block and the
knockdown — is a `GaitLayer`
(`Scripts/controllers/gait/`). The coordinator runs them lowest priority first
over the locomotion pose in a `GaitPose`, one stage at a time:

| Stage | Composition | Why it sits there |
|---|---|---|
| `HOLD` | max with the pivot's | how much the layer sets the feet |
| `FLOOR` | max over the stance and the width | a floor, so order cannot matter |
| `LEGS` | additive on the joints | before the knee solve: the fore-aft compensation must see it |
| `TRUNK` | additive texture; sinks; `wobble` | `wobble` skips the trunk inertia filter |
| `OVERRIDE` | lerp owned channels to the layer's pose | last, so it takes everything beneath |

The override is what makes the priority real. It lerps the channels it owns
toward its own pose by its weight, so the stroke and every additive layer below
it fade with no layer knowing about another. The block owns the legs, the drop
and the ankles, and unplants its kneeling leg; the knockdown, last, owns the
legs, the drop, the plants (the blade contact seat, `Scripts/actors/CLAUDE.md`),
the mohawk yaw, the edges, the trunk and the wobble — and through the get-up
it owns the kneel too, solving each thigh so a foot pivot never goes under
the ice. **A layer never suppresses another with a
`(1 − other.weight)` factor** — if one must win, it is an override above the
other. `test_gait_layers.gd` holds the order and the knockdown's mask.

A layer reads replicated state only and writes only the pose and its own
published fields (`GaitFaceoffLayer.blend`, `GaitShotLayer.hip_yaw`). Its clock
lives in `advance` (render rate, so no timer gameplay reads), which also
reports whether the layer contributes this pass: an idle layer's stages are
never called, so `advance` may answer false only when every stage would leave
the pose untouched (to within the shared 0.001 blend floor).

The upper-body overlays (the shot coil, the follow-through blade, the
celebration's raised stick, the block's torso lean) are not layers: they move
the gameplay frame and the blade, so they stay in the pose coordinators at
physics rate.

### A change of who poses the stick is eased, not cut

The tracked IK, the slapper's wind-up, the follow-throughs and the shot block
each place the hand and blade from their own geometry, and none starts where the
last left off — a change of owner moved the stick up to 1.8 m in a tick.
`SkaterPoseBridge` runs after the tick's last write: on a change of owner it
holds the stick last drawn and eases the new owner's pose in from it (0.15 s;
0.05 s into a follow-through, which is the shot's own whip). It advances on live
ticks only — reconcile treats the live tick as the truth, and a bridge advanced
through a replay would play its ease twice — and its effect rides the hand and
blade the wire already carries. The same rule shapes the rest of the
hand-offs: a whip's attack takes `whip_attack_time` however long its finish, the
celebration's stick and fist pump ease in and out over `CELEBRATION_EASE_S`,
and the slapper and block take their pose from the lean and twist they find
rather than zeroing them first.

**The stride's hand pump is drawn, never posed.** Both hands on, the stroke
swings the top hand across the body (`SkaterIKCoordinator._stride_pump`), the
stick pivoting about its blade. It is an offset on `Skater.drawn_top_hand()`,
which the arm, the stick and the bottom hand are drawn to; the `TopHand` marker
every claim reads never takes it.

### The gait's numeric core is native

Where the extension is built, `NativeSkaterGait` runs `SkaterLocomotion`, the
alignment and pivot read, the reach sit and `GaitPose`'s stance and leg solve;
the coordinator reads the hips' tilt off the skater, runs the layers over the
pose the port loads into `GaitPose`, and publishes. The GDScript is the
reference and the fallback: change `skater_locomotion.gd`, `_align_to_travel`,
the reach sit or `GaitPose.solve_stance` / `seed_legs` / `seed_trunk` and the
port changes with it, or `test_native_gait_parity.gd` fails. A layer must read
only what `load_native_legs` / `load_native_trunk` fill — the leg solve's own
state (`GaitPose.leg_l`, `_gripping`) and `_locomotion`'s fields stay stale on
the native path, as does every alignment and pivot field but the published
ones (`travel_align_yaw`, `pivot_hold`).

### Pose the hand, not the blade

The tracked path is blade-first: the cursor names a blade position and
`TopHandIK` solves the hand as a consequence. A **held** pose that wants the
blade in tight cannot be authored that way, and the check commit is the worked
example.

`TopHandIK` has two regimes. Inside the stick's resting horizontal reach it goes
CLOSE, which pins the hand's XZ **at the shoulder marker** and varies only its
height — the blade's authored distance stops mattering entirely, and past the
`hand_y_max` ceiling the blade overshoots along the aim line instead of landing
where it was put. Meanwhile the rendered arm roots at the shoulder the trunk
texture has MOVED (`SkaterArmRig._textured_shoulder`), which a lean and a
load-up carry ~0.16 m forward. Put together, the arm roots in FRONT of its own
hand: the shoulder→hand chord points down and back, a mostly-downward elbow pole
projects forward off such a chord, and the forearm folds behind the upper arm.

So a held pose authors the **hand** — where the player actually holds the stick
— and derives the blade one `solve_stick_length()` along the intended bearing.
Authoring both ends over-constrains a rigid stick, and `enforce_rigid_stick`
only shortens an over-long span; an under-long pair draws a visibly short stick.
`test_commit_grip_choke.gd` holds all of it, including the fold direction.

### The top hand is solved where the arm is

The tracked path's ROM (`TopHandIK`) is a disc about the shoulder with the hand
a fixed drop below it, and `SkaterIKCoordinator._solve_top_hand` solves it
where the drawn arm actually is. Three things decide "where", each found as a
hand the drawn arm could not reach or barely extended toward:

- **The shoulder is the trunk's** (`arm_shoulder`). The skeleton folds the
  trunk before it twists (`Scripts/actors/CLAUDE.md`, *One skeleton, one
  chain*) and `UpperBody` twists first, so a skating fold with a backhand twist
  carries the drawn shoulder ~5 cm off the frame's marker, and a hand solved
  off the marker stretched the arm to 1.03 of itself.
  `SkaterSpineRig.shoulder_in_frame` copies the rig's order from tick state
  alone, because the blade it places is gameplay: the hips are taken square to
  the facing (their yaw carries the render-rate gait); where it matters the
  twist is pinned at the spine's limit anyway.
- **The frame is level** (`_level_tilt`): `UpperBody`'s yaw without its pitch
  and roll. A shoulder flexes the arm forward as the trunk leans; solved in the
  leaned frame the disc tipped with the chest, and reaching ahead at a 36°
  skating lean the fully extended arm hung 82° below horizontal. Level, it
  reaches out at the upright angle (~46°) and the lean buys reach by carrying
  the shoulder forward and down. The hand heights hang off the trunk's shoulder
  before the faceoff address folds it (`_level_config`).
- **The cursor's target is projected by that same solve.** Projected at the
  upright blade height while the solve ran at the leaned one, the target sat
  inside the rim and the hand was drawn back to it: 0.24 m of a 0.39 m rim in
  every direction.

The reach lean measures the hand the same way, and the host's claim clamp
bounds the result (`TopHandIK.full_reach`, the trunk at its deepest fold).

**A carrier keeps both hands on the stick.** An empty stick reaches one-handed
to the rim when there is a puck to reach for (`ReachPurposeRules`) and rests in
both hands, where a carry would, when there is not; with the puck the blade stops where the bottom hand could no longer
hold the shaft (`TopHandIK.two_hand_reach`, from the bottom shoulder read the
way `arm_shoulder` reads the top one) and, on the backhand, at the angle past
which it lets go (`bh_release_angle_deg`, `_carry_backhand_stop`) — the puck
magnetises to the blade, so a one-handed carry was reach no defender could
answer. Both are tick state; the drawn bottom hand reads the render-rate trunk
and is what the limit is measured to keep on the shaft. They are laid on the
cursor's TARGET, not on the blade the speed cap draws, so a pickup at the rim
brings the stick in at the dangle's pace instead of in one tick.
`test_top_hand_reaches_its_rim.gd` holds all of it.

"Hold the shaft" means a glove's width below the top hand
(`SkaterIKCoordinator._glove_spacing`, the drawn fist's width), never on it.
The bottom arm only just reaches the top hand once the stick is held out, so
never let that floor go to zero: the grip slides up until one fist is drawn
inside the other, and the reach it buys a carrier (out to ~1.85 m) is reach
no two hands have. With it the stick comes in until both hands fit (a carry
reaches ~1.3 m ahead, ~0.95 m wide), and an empty stick past that lets the
bottom hand go. `test_gloves_never_stack.gd` measures the drawn fists.

Because the blade stops there, a skating carrier's hips pivot there too: its
`FacingRules` config (`carry_facing_rules`, also the bots' `AISkaterCaps` copy)
has the backhand stop as its backhand edge, so sweeping the puck round the
backhand turns the skater onto the other line with it on the forehand, about
113° off the new line and far inside its edge. A pivot under way commits
(`FacingRules.Config.pivot_commit_rad`): the hips' turn toward the cursor, past
where the line would hold them, eases the edge a few degrees, or a cursor held
on the stop flips the pivot on noise and the hips sit between the lines. Capped,
because a body still turning onto the line from a cursor squared beside it
reads the same way. `test_facing_follows_travel.gd` holds all of it.

On the forehand the stop is the two-hand reach, ~145° off facing on every
build, short of the 157° pivot edge. Hips held on the line through a sweep round
the forehand park the puck at the stop until the pivot whips it on (~840°/s of
hips): a release and a repush, two taps. So the carrier's hips yield: past
`carry_forehand_yield_deg` (110°) round the forehand,
`FacingRules.yield_on_forehand` turns where the body heads this tick on toward
the cursor until it is back there. It is laid on the turn, after the rule's
target and its drag (never on the target, which may lie the other way of the
facing), so it only ever turns the hips toward the puck, and the turn's wind-up
still bounds it. Yielding well inside the stop is what spreads the turn over
the sweep. The pose coordinator, `AICarryRollout._face`, the native rollout and
the duel harness all lay it on. `test_carry_hips_yield.gd` holds it.

**A pose the trunk texture cannot express does not belong in the gait.** The
texture is one pitch and one roll for the whole shell, so it is symmetric by
construction: any "drop a shoulder" written as roll raises the other shoulder by
exactly as much. The check-commit load-up is therefore split — the gait keeps the
lean and the crouch, and the per-side shoulder geometry lives in
`CheckStanceRules`, eased at PHYSICS rate on the skater
(`Skater._update_commit_stance`) because the loaded blade position reads it and
the blade goes on the wire. Anything else asymmetric belongs on that side of the
line too, not as a new trunk channel.

## The faceoff pose is two poses, and neither is a stride

`FACEOFF_PREP` is one phase but three different things happen in it, and the
bugs all came from treating it as one.

**The walk-in is skating.** While `begin_approach`'s glide is live the skater is
covering ground, so `is_faceoff_ready()` is false and the gait plays an ordinary
stride — a floored crouch and staggered feet laid over a running stride read as
a limp. The ready stance eases in as the glide hands back. It is not physical,
though: skater contact is off while movement is locked
(`Skater.contact_suspended_provider`, fed `is_movement_locked` at setup), so
a glide crossing the centre neither checks him into the drop nor shoves him off
the dot. The countdown waits for the last glide to land
(`PhaseCoordinator.last_prep_preroll`).

**Set at the dot is two stances, not one.** The players lined up behind the dot
hold a ready stance. The centre taking the draw holds an *address*: knees well
past the skating sit, a base splayed wide under him, feet split fore/aft, chest
folded down over the dot, hands apart on the shaft. `Skater.is_faceoff_center`
selects between the two, and it is *derived* on every peer from the C slot
rather than replicated — every machine already knows every player's slot, and a
cosmetic bit is not worth a wire byte.

The address is spread across the collaborators that own its parts, and the parts
are not independent:

- **The crouch, the splay and the foot split are gait channels**
  (`GaitFaceoffLayer`), floored over the speed-driven envelope. The
  splay costs each leg a cosine of vertical span, which the body pays as extra
  drop.
- **The chest fold rides the trunk TEXTURE**, not the torso lean — the lean
  rotates the `UpperBody` node the blade markers hang from, and the blade-first
  IK answers a pitched frame by standing the shaft on end. Bones are mesh only,
  so the chest reads folded while the stick keeps its address. The arm roots
  ride the texture too (`SkaterArmRig._textured_shoulder`), which is what lets
  the fold go deep without tearing the arms off the shoulders.
- **Both ankles flatten** (`SkaterLegRig.set_ankle_flatten`). A sit this deep
  folds the shin far enough back to stand the blades on their heels, and the
  splay puts them on their outside edges; the ankles give the whole chain back.
  A level boot then hangs its blade below the FOOT pivot rather than keeping its
  sole planted, so the crouch owes `GaitPose.FOOT_FWD`'s vertical share on top.
- **The hands are solved off the FOLDED shoulder**
  (`SkaterIKCoordinator.address_shoulder`), because that is where the arms are
  rooted. This is the one that bites: solved off the marker, the hands land a
  third of a metre behind the shoulder they hang from, and a two-bone IK can
  only answer that by putting the elbow in front of the wrist. The arm reads as
  bending backwards, and no amount of pole tuning fixes it.
- **The stick is choked** for the draw (`Skater.faceoff_choke_m`, sized off the
  build's own stick like the check commit's). The hand rides one stick-length up
  from a blade on the dot, so at full length a body folded this far has to hold
  it at shoulder height with the arm shut. A real centre grips well down the
  shaft, and the shaft keeps its length — `SkaterStickRig` gives back out of the
  butt whatever the grip takes.
- **The top hand's ceiling comes down** (`_address_hand_ceiling`). `TopHandIK`
  answers a puck inside the stick's reach by RAISING the hand and steepening the
  shaft; that is a carry in tight, not an address. The ceiling binds only
  through the countdown — the ease releases it at the drop, so the draw sweep
  itself is unaffected.
- **The bottom hand slides down the shaft** on the same ease
  (`_grip_fraction`) — the short lever a draw is won with.
- **The reach lean stands down** (`SkaterPoseCoordinator._address_share`). It
  measures the hand's reach off the shoulder MARKER, and the address carries the
  hands forward with the chest — so left alone it reads that carry as a reach
  and leans the torso a second time for it, deepening the fold past the authored
  one and handing the blade IK a pitched frame to solve the address in.
- **The dot is laid out from the ADDRESS, not from a standing body**
  (`faceoff_center_distance`): the fold's carry plus the shaft's span at the
  crouched hand height and the choked length. It runs at the whistle, before the
  pose exists, so every term is derived — the drop from
  `SkaterSkatingCoordinator.faceoff_address_drop`, with the live crouch netted
  out so a skater caught mid-stride doesn't get a different dot. The fraction is
  deliberately just PAST 1.0: at the shaft's natural projection the hand comes
  off the body toward the dot (`TopHandIK`'s FAR regime) and the arms open,
  while short of it the hand rides its ceiling and they fold shut.

**Nothing dispatches the state machine while movement is locked**, so no state
can clear itself there — `SHOT_BLOCKING` used to hold its planted legs and wide
block cylinder from the whistle to the drop, because its own exit lives in
`_state_shot_blocking`. The teleport at the head of every approach is where a
locked phase gets cleaned up (`_reset_to_skating_state`), and it has to publish
`skater.current_shot_state` itself for the same reason.

**Every path that poses the body publishes the lower body's yaw**
(`SkaterPoseCoordinator.apply_lower_body_yaw`). The two locked-phase paths
replace `apply_facing` wholesale, and one that skips this leaves the hips frozen
at the last yaw anyone wrote — which is how skaters spent whole countdowns still
turned down the line they skated in on.

## Build once, fill scratch

A per-tick collaborator that produces a compound result should own ONE
long-lived scratch instance and fill it, rather than returning a fresh
`Dictionary` / `Array` / `RefCounted` per call. It is safe exactly when the
consumer reads the result and never stores the reference: `GoalieBodyConfig` is
read and lerped into the parts by `Goalie.apply_body_config`, so one instance
serves both goalies forever and keeps ~150 lines of `Vector3` literals off the
heap per goalie per physics tick.

Where two consumers can interleave, give each its own scratch instead of sharing
one — `RemoteController` keeps `_sample_bracket` separate from `_scratch_bracket`
so a reconcile-time sample cannot clobber the live render bracket. Document the
"consume before the next call" lifetime at the returning function, since that is
the one thing a caller can get wrong.

## Hot path

Everything here runs at 120 Hz × actor count, and reconcile replay re-runs the
per-tick body once per replayed input. Cosmetic-only work belongs in `_process`,
not `_physics_process`. See CLAUDE.md → *Hot-path discipline*.
