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
| OFF_PUCK, CHASE_PUCK | ONE_TIMER_PRESSED | a staged finisher's feed arrives (`_try_shot_reception`) |
| CHASE_PUCK | OFF_PUCK | the chase ends, or the bot is out of play |
| CARRY | SHOOT_PRESSED, PASS_PRESSED | the carrier's committed intent is ready to release (a dump releases through PASS_PRESSED) |
| any press state | CARRY | the release fires, or the press bails |
| CARRY, any press state | `_post_puck_lost_state` | the puck is gone: CHASE_PUCK for the nearest teammate to a loose puck, else OFF_PUCK |

After dispatch, `SkaterAgent.tick` runs three per-tick passes that may overwrite
the dispatched input: the stick lift, board play (`apply_board_play`) and the
shot block (`SkaterAgentShotBlock`).

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

**The agents do not read the live brain.** `TeamBrain.build_view()` freezes the
blackboard into a `TeamBrainView` after each tick, on the worker, sequenced
before any decide; dispatch reads that — `TeamStrategyView` is the interface both
implement. It is refilled, never reallocated, and the main thread never touches
it, which is why no mutex is needed. Writes the host raises against a brain are
queued and drained on the main thread only while the worker is idle
(`AICoordinator._drain_brain_commands`). Unit tests hand the live brain in
directly, which is legal because `TeamBrain` *is a* `TeamStrategyView`.

## The blade cursor leaves the agent untouched

`SkaterAgent.tick` returns the state machine's blade cursor as-is. Its slew — the
bot's real Hands blade speed — is the one motion limit on it, exactly the limit a
human's blade plays under. A second smoothing stage in the agent is a trap:
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

**A fast loose puck is a reception, not a race.** The catch is decided by blade
squareness plus the puck's speed *in the receiver's frame*, so squaring on the
line is what collects it and stopping is a wait rather than a technique. Bots
receive in stride by default and brake only when arriving early enough to carry
the blade past the meet, or when their own closing speed would stack over the
catch ceiling.

Against the boards the read inverts: the blade goes ON the glass and the body
stands rink-side, because a blade out on the puck's line leaves exactly the gap a
rim squirts through.

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
immediate whistle. The coverage reads in `role_helpers.gd` still read
`is_ghost` on purpose — an NHL offside skater is physically on the ice.

A teammate owing a tag-up is a TEAM state, not a personal one: until the whole team
is out, nobody may enter (`offside_brake`'s `hold_line` keeps the line shut
even once the puck is in), and the carrier keeps its carries, feeds and
dump-ins out of the zone (`RoleContext.zone_entry_blocked`). The brake runs on
every tick, decided or not — a throttled bot still moves on its cached vector.
An out-of-play bot is also never the elected loose-puck chaser: it would refuse
the chase while nobody else was sent.
