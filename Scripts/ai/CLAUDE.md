# Bot agents — structure

Scope: `Scripts/ai/` — the nodes that turn a role decision into inputs. The
design rules those decisions are built from (evaluators, difficulty axes,
determinism, grounded models) live in `Scripts/domain/ai/CLAUDE.md`; read that
one before changing what a bot *decides*, and this one before changing how the
agent is *wired*.

## How an agent is put together

`SkaterAgent` owns the `InputState` scratch buffer and the `AIController` glue.
`SkaterAgentStateMachine` owns identity, transitions, and per-state behaviour,
and follows the same dispatch + `match` + per-state-handler shape as
`Scripts/controllers/skater_state_machine.gd`, so a reader of one can read the
other.

Self-contained jobs live in collaborators the state machine holds, each
`SkaterAgentShotBlock`-shaped: identity at `setup`, the bot's knobs and state
passed per call, and only its own fields written.

| collaborator | owns |
|---|---|
| `SkaterAgentSteering` | body steering to an anchor: the field, brake-pivot, arrival brake, stance carve |
| `SkaterAgentStickPlay` | the jab / lift reach-in, the tie and its pull, the stick-check button |
| `SkaterAgentStandUp` | meeting a carrier about to skate into us with Ctrl held, so the contact is our check |
| `SkaterAgentBoardPlay` | reaching for and holding a pin, the pinned slide, a carrier's answer to a square checker |
| `SkaterAgentShotBlock` | the shot block and the 2-on-1 dive |
| `SkaterAgentPress` | the press on a screen we are leaned on, a screener digging in against a defender on him, and a carrier putting his body into a man who stands him up |
| `SkaterAgentReception` | reading an incoming feed: is it ours, the blade gate, the squared or wall-kill stance, and whether it is a shot reception |
| `SkaterAgentOneTimer` | the ready finisher's settle anchor on the feed line, the slapper zone, the feed's remaining flight, the press square-up |

The state machine never writes a collaborator's fields, and no collaborator
names the state machine (`test_agent_collaborator_seams.gd`). A new
self-contained job is a new collaborator, not more state-machine fields.

Adding a behaviour is four steps:

1. Append a `State` enum value.
2. Add a `match` arm in `dispatch()`.
3. Write the `_state_<name>` handler.
4. Decide where the transition into it happens — usually a check inside
   `_state_carry`.

| from | to | when |
|---|---|---|
| OFF_PUCK | CHASE_PUCK | a loose puck this bot may play (`_should_chase_loose_puck`), or a pass released its way |
| OFF_PUCK, CHASE_PUCK | CARRY | it picks up the puck |
| OFF_PUCK | ONE_TIMER_PRESSED | a ready one-timer man's feed is released on his line or reaches his zone (`_is_one_timer_ready`, `SkaterAgentOneTimer.line_anchor`, `_puck_in_one_timer_zone`) |
| CHASE_PUCK | ONE_TIMER_PRESSED | a ready one-timer man's feed reaches his zone, or a feed he is chasing is worth redirecting (`_try_shot_reception`) |
| CHASE_PUCK | OFF_PUCK | the chase ends, or the bot is out of play |
| CARRY | SHOOT_PRESSED, PASS_PRESSED | the carrier's committed intent is ready to release (a rim releases through PASS_PRESSED) |
| any press state | CARRY | the release fires, or the press bails |
| CARRY, any press state | `_post_puck_lost_state` | the puck is gone: CHASE_PUCK for the nearest teammate to a loose puck, else OFF_PUCK |

After dispatch, `SkaterAgent.tick` runs five per-tick passes that may overwrite
the dispatched input: the stick lift, the stand-up (`apply_stand_up`, ahead of
the board play so a check it starts at the wall can become a pin), board play
(`apply_board_play`), the shot
block (`SkaterAgentShotBlock`) and the press (`SkaterAgentPress`). The offside brake (`apply_offside_guard`)
runs after all of them as the last write to the move, so no writer — the rolled
carry inside dispatch, the pinned slide after it — can carry a bot over the line
(`test_agent_offside_guard.gd`).

### The dispatch throttle

The DECISION is throttled; the blade is not. Outside the press states the full
dispatch runs every `_dispatch_period_ticks` (60 Hz Hard, 20 Hz Normal, ~13 Hz
Easy). Skipped ticks reuse the cached move vector and the brake / stance / hit /
stick-lift flags, but re-derive the blade target from CURRENT perception — the
chase reception aim, the off-puck ready stance, jab and tie aims, and the carry
cursor — so a catchable feed never transits a blade that only re-aims on
dispatch ticks. Anything that re-derives on skipped ticks may only READ
dispatch-throttled state. The press states (SHOOT / PASS / ONE_TIMER) always
run full-rate: charge timing and pre-aim convergence are tick-sensitive. Every
counter sized in physics ticks (jab windows, pre-aim wait, the
role-argmax cooldown) advances by the dispatch span, never by 1, or its
wall-clock duration stretches with the tier.

**Off-puck behaviour does not live here.** Each `TeamBrain` slot maps to a role
module returning a `RoleDecision` (target position and velocity, optional aim
override, check commit, the man it covers); the state machine only consumes it.
`CARRIER` is the exception — `_state_carry` dispatches the carrier directly and
reads its public fields, because it needs its own steering rules (hold vs. drift
during pre-aim) and its own press transitions.

## How the brain hands out work

`TeamBrain` is one per team, ticked on the host's AI worker thread at the head
of each batch (`AICoordinator._worker_loop`: tick → `build_view` → every bot's
decide) at ~6 Hz. Each tick it publishes a blackboard the agents read: `state`
(the `AIPossessionState` shape), `slot_assignments` (peer id →
`AIRoleSlots.Slot`), `threat_assignments` (the man-on-threat partition) and
`threat_shoot_base_by_opp`, `rush_read` (the shared transition-defence
perception), the one-timer readiness and the ping directives, plus
`coverage_downgraded` for instrumentation.

**Nothing is locked or sticky.** Every slot is re-elected each tick by a
momentum-aware soonest-to-arrive race; roles "stick" only because the body
already in the right place keeps winning, and hysteresis damps the ties.

**Two brains, two cadences.** Team 1's natural tick runs half a period out of
phase with team 0's so the two computes never land in the same batch — a late
worker batch costs bot quality (the batch's decisions are skipped), and two
brain ticks stacking is a recurring spike for free. Possession events
force-retick BOTH brains together, so the phase offset has to be re-applied at
every forced-tick accumulator reset, not just at construction.

Agents are phase-staggered for the same reason. Each bot's dispatch and
role-argmax counters start at a per-peer phase (`_stagger_cadence_phases`), and
every re-arm adds a small per-peer skew, because a possession flip zeroes many
bots' counters on the same tick and identical periods would keep them in
lockstep forever. Real bot peers only: tests pin tick-exact behaviour off phase
0.

**The agents do not read the live brain.** `TeamBrain.build_view()` freezes the
blackboard into a `TeamBrainView` after each tick, on the worker, sequenced
before any decide; dispatch reads that — `TeamStrategyView` (domain-side, so the
roles that consume it do not reach up a layer) is the interface both
implement. It is refilled, never reallocated, and the main thread never touches
it, which is why no mutex is needed. Writes the host raises against a brain are
queued and drained on the main thread only while the worker is idle
(`AICoordinator._drain_brain_commands`). Unit tests hand the live brain in
directly, which is legal because `TeamBrain` *is a* `TeamStrategyView`.

## The blade cursor leaves the agent untouched

`SkaterAgent.tick` returns the state machine's blade cursor as-is. Its slew — the
bot's real Hands blade speed — is the one motion limit on it, exactly the limit a
human's blade plays under. Like the controller's cap, it is relative to the
skater: the cursor rides the body and slews across it, so skating at speed
never eats the blade's own. A second smoothing stage in the agent is a trap:
straight-line world blending chord-cuts the state machine's shaped cursor paths
(the arc, the reach-cone clamp, the front route) across the body on big flips,
and can trip the pose IK gate's facing freeze.

**A carried puck never goes through the skater.** A reach to a spot in front of
the body (the carry cursor, and pre-aim's pull to a charged release's hold) walks
`BladeRoute`: straight when that line clears the body, else the shortest way that
stays a body-plus-puck radius off it, around the side the skater faces. A spot
behind the body is a turn-around and keeps the arc; a swing to a charged
release's hold walks the hold's own reach and lands on it, where other targets
stay on the aim ring. The shot-hold pricing (`AIShotHolds`) measures the pull on
the same route, and times the swing at the bot's arc rate, so what the carrier
prices is the path the cursor walks.

## Reception doctrine

**A feed is a reception, not a race.** The catch is decided by blade
squareness plus the puck's speed *in the receiver's frame*, so squaring on the
line is what collects it and stopping is a wait rather than a technique. Bots
receive in stride by default and brake only when arriving early enough to carry
the blade past the meet, or when their own skating is what carries a feed past
the bobble line (`SkaterAgentReception.gives_with`) — a feed already past it on
its own bobbles however they skate.

**The stance rides the receiver's own skating.** The meet is a rendezvous, so a
receiver driving into the feed stands where his skating takes him, a stance off
the puck's path *in his frame* (the face is square across the shaft), and only
that correction needs the flight's time. He never steers onto the puck's own
line, which turns the hips to it before contact. The net-forward catch of a shot
reception stands him behind the catch point, so it is only taken when he gets
there first; one driving past it takes the feed in stride. Whose feed it is
reads the same way: each teammate where his own skating has him when the puck
reaches his level (`SkaterAgentReception.skating_point`), so a forward driving
onto a feed is its man however far off its line he is now.

**A feed is a puck that was sent, and who sent it is all a bot knows.** A fast
loose puck reads as one (`RECEIVE_TRIGGER_PUCK_SPEED_M_S`), and so does a
teammate's release at any pace while it slides
(`WorldSnapshot.loose_puck_released_by`, kept until any stick, body or goalie
touches it): the teammate nearest its line goes to it (`incoming_pass`), and
squares up to it where its real path reaches him (`read_pass`). Whom the passer
meant is never published: the bots read what a human watching the play would
see, the passer and the puck, and nothing a human cannot. The shot-aware
reception and the one-timer plan on the puck's line without its friction, so
they keep the fast trigger.

Against the boards the read inverts: the blade goes ON the glass and the body
stands rink-side, because a blade out on the puck's line leaves exactly the gap a
rim squirts through.

**The one-timer is what a staged finisher is for.** With the seam open to a ready
one-timer man, the carrier feeds him rather than holding the carry; and a
cross-seam feed that arrives while the keeper is still on the passer's side is
one-timed (`_try_shot_reception`), not caught and turned — turning hands the
keeper the time the pass took from him. `test_one_timer_chain.gd` holds both.

**Wound up, the one-timer man only glides, pivots and shuffles**, so he presses
once that is enough to set before the feed arrives (`SkaterAgentOneTimer
.time_to_set`): the hips into the stance at their pivot rate, the circle onto
the pass's line on the glide he carries and a shuffle. Until then he skates to
the line; a feed that will arrive before he could set, and before a wind-up
could open the window, he catches instead, and stays given up on it until
someone has the puck again (`_one_timer_spent`): re-committing on the next tick
leaves him neither swinging nor squared to catch. The passer feeds him on his
tape, the zone his stance sets for the net, when he can set for it in the
feed's flight (`AIPassLead.feed_point`, on the same `SlapperRules.time_to_set`
he presses on), and at his body to catch when he cannot. He leads the swing against the
feed's pull (`swing_for`), so the shot lands where he aimed it.
`test_bot_one_timer_loop.gd` drives the real controller through it.

## Chase doctrine

**Chasing a carrier is angled, not straight-line.** The intercept is shaded one
stick-reach toward our own net so the approach arrives on the inside lane and the
carrier's only escape is outside; a straight-line chase lets them cut to the
middle. Loose pucks get the raw intercept — there is no carrier to angle off.

## Who may play the puck

"Can this skater legally touch the puck right now?" is
`WorldSnapshot.is_out_of_play(peer_id)` — a ghost, or a skater owing an NHL
delayed-offside tag-up (`tag_up_peers`, whose touch would whistle the play).
Don't read `is_ghost` alone for it: under NHL nobody is ghosted for offside.
The bot answer to being out of play is the tag-up override in
`_state_off_puck`; a carrier with a teammate out of play holds the puck short
of the blue line (`offside_brake` on the puck), since carrying it in is an
immediate whistle. The coverage reads in `defensive_verbs.gd` and `role_reads.gd` still read
`is_ghost` on purpose — an NHL offside skater is physically on the ice.

A teammate owing a tag-up is a TEAM state, not a personal one: until the whole team
is out, nobody may enter (`offside_brake`'s `hold_line` keeps the line shut
even once the puck is in), and the carrier keeps its carries, feeds and
rims out of the zone (`RoleContext.zone_entry_blocked`). The brake runs on
every tick, decided or not — a throttled bot still moves on its cached vector.
An out-of-play bot is also never the elected loose-puck chaser: it would refuse
the chase while nobody else was sent.
