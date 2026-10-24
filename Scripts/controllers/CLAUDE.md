# Controllers

Scope: `Scripts/controllers/` — the layer that drives actor bodies from
decisions. Controllers use the domain to decide and reach into infrastructure to
execute; they never reach up.

## The goalie

Every match plays the keeper; how he plays is `Scripts/domain/keeper/CLAUDE.md`.
Four files here hold him in the game:

| File | Owns |
|---|---|
| `goalie_controller.gd` | his seat, which every caller, the puck, the wire and the replays address: his node, puck and net, the puck's signals routed to whoever plays him, the host's snapshots and a client's interpolation of them, the reads the shot log takes of him |
| `keeper_controller.gd` | the keeper in that seat: KeeperPositioning at the planner's rate, KeeperMotor at the tick, the node placed on him and his gear's save boxes on its part bodies (`Goalie.set_stand_in` / `seat_save_box`), a shot read and saved (KeeperShotRead, KeeperSave), a glove catch held and covered, a loose puck he can reach covered (KeeperCover); played on the host, posed from the wire on a client and in a replay |
| `goalie_state_machine.gd` | the stance enum the wire carries (`state_enum`) and the bots and the pad sounds read, and its families |
| `goalie_world_view.gd` | one scan of the skaters a tick, shared by every read of them |

The goalie's rules in `Scripts/domain/rules/goalie_*.gd` are pure and shared:
the rebound doctrine (`GoalieSaveRules`), the push kinematics his footwork runs
on (`GoaliePushRules`), where a pass in flight is shot from (`GoaliePassRead`),
and how a body hides a shot from him (`GoalieScreenRules`, which the bots read
to clear or not make a screen in front of their own goalie).

### Delete the copy, don't correct the number

Nothing connects a literal to the collider it was copied from, so every
hand-built replica of the goalie elsewhere — in the bots' model of him, in an
instrument — drifts off the body that actually makes the saves, silently and
without anyone being wrong on purpose. Anything that believes something about
his SHAPE derives it from his own anatomy and gear (`KeeperAnatomy`,
`KeeperGear`), so changing the body moves every reader of it for free.

## Beatable realism

The goalie should look and move like a real goalie while staying deliberately
scorable. **Realism should not produce an unbeatable goalie; it should produce
one who gets beaten the way an NHL goalie gets beaten.** Making him better is
not the failure mode — closing off a way he *ought* to be beatable is, and a
save count alone cannot tell the two apart.

Two traps, both measured on the goalie before him:

- **A goalie who pre-commits cannot be read, and being readable is the game.**
  A change that makes him block or commit earlier tends to measure as *more
  saves* AND *deception ceasing to pay*. Deception paying negatively is the
  tell: a change with that signature is wrong even when the save count
  improves.
- **Blocking concedes the top of the net.** Any path that blocks a shot already
  read as elevated is strictly wrong.

## Difficulty

Goalie tuning is bundled per tier in `GoalieSkillProfile`: the keeper takes its
reads and speeds (`KeeperController._tier`). Whenever the bots' shot model reads
the same quantity, the two must be synced (`AIGoalieModel.set_goalie_profile`)
or the bots score against a goalie they do not face. See the AI MIRROR note in
`goalie_skill_profile.gd`.

## What kills a collaborator extraction

**A collaborator may accept any number of inputs written from outside. It must
exclusively own every field it writes itself.**

A collaborator taking twenty fields its caller writes is healthy; sharing
ownership of one field is not. Once the caller writes a field the collaborator
also writes, the caller has re-derived when to write it — the lifecycle — and
the collaborator's own updater for it is dead from that moment. Measured on the
old goalie's collaborators, the contested fields per collaborator (0, 2, 2, 12)
predicted the methods that died (0, 0, 0, 17 of 27), none of which failed
anything.

The layout that stays healthy: tuning pushed at config time, geometry set once
at setup, its own state owned outright, and an explicit "requests to the
caller" block read after its per-tick entry point, which takes the world as
arguments and clears its own outputs at the top.

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
speed is held off, so W held through a stop stops. Bots shuffle only onto a
one-timer's line, wound up (`InputState.bot_shuffle`): otherwise their brake
keeps steering in the stick, so `AIController.apply_decision` drops it under
the brake below the gate (`AIBotMechanics.braked_stick`), and `AICarryRollout`
prices a BRAKE as that stop. The glide is the stance with a joint-space
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
consumer reads the result and never stores the reference: a client's goalie
interpolation fills one `GoalieNetworkState` (`GoalieController._scratch_state`)
and poses him from it, so one instance serves every render of him.

Where two consumers can interleave, give each its own scratch instead of sharing
one — `RemoteController` keeps `_sample_bracket` separate from `_scratch_bracket`
so a reconcile-time sample cannot clobber the live render bracket. Document the
"consume before the next call" lifetime at the returning function, since that is
the one thing a caller can get wrong.

## Hot path

Everything here runs at 120 Hz × actor count, and reconcile replay re-runs the
per-tick body once per replayed input. Cosmetic-only work belongs in `_process`,
not `_physics_process`. See CLAUDE.md → *Hot-path discipline*.
