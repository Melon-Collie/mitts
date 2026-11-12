# Penalties — the NHL ruleset calls fouls

Status: **Phases 1–4 built** (faceoff formations; the calls, the box and
playing short in 5v5; the penalty shot in 3v3; a fight's minors), playtest
pending. Phases 5–6 not started. Where what is built differs from the proposal, *Phase 2 as built*
and the penalty shot's own section say how.
Amends `docs/fighting-plan.md` ("No penalty. Both stay on."), the "Deliberately
out" line of `docs/defensive-play-plan.md`, and the rule-set paragraph of
`docs/gameplay-design.md`. Each phase is its own PR and playtest.

## Decisions banked (from chat, 2026-11-12)

| Question | Answer |
|---|---|
| Where | **The `NHL` rule set only.** `ARCADE` and `OFF` call nothing, as today. |
| The penalized player | **He sits in the box**, and a human watches from a box camera. |
| 5v5 | **A minor puts the team a man short** for its length. |
| 3v3 | **A penalty shot, not a power play.** A 3-on-2 is close to an automatic goal. Manpower never changes for a foul. |
| Fights | **Coincidental minors in 5v5.** Both sit for a minor's length and the teams play 4-on-4. There is one length of penalty; nothing is called a major. **A fight in 3v3 is not penalized**, so 3v3 never uses the box. |
| First calls | **Boarding and interference.** |
| Not called | **Delay of game** (the puck cannot leave the rink) and **charging**. |
| Stick fouls | **Deferred.** Tripping, hooking, slashing and high-sticking need a stick that can foul a body, which no verb does today. |
| The referee | **Deterministic.** A foul is a rule a player can learn and read before he commits; nothing is missed and nothing is rolled. |
| Length | **A minor is a tenth of a period**, the share two minutes is of twenty: 24 s at the default 4-minute period, floored at 15 s (`PENALTY_MINOR_MIN_S`) so a 1-minute period still has a penalty worth killing. |
| The whistle | **The call is delayed** until the offending team has the puck, with no extra attacker (goalies are AI-only and never leave the net). |
| Drawing a call | **Boarding reads the victim's facing 0.3 s before the contact**, so turning your back as the hit arrives draws nothing. |
| Stacked minors | **The floor is three skaters** in 5v5: a third minor is queued until the first ends. |
| First build | **Real calls from the start.** No silent phase that only reports what it would have called. |
| Faceoffs a man short | **A winger takes the draw** when the centre is off the ice, and **both wing spots are always filled**: an empty one costs the draw's scramble, so that side's defenseman steps up into it. He is still a defenseman to the team brain. |
| Which box | **The one on the team's own bench's side of centre.** Benches are assigned by team for the walk-out (`PlayerRules.bench_start_position`); the box follows the same assignment. |

## Why

Mitts calls no penalties, and four decisions were made because of it: the
cross-check was retired as "openly illegal, Mitts calls no penalties", hooking,
holding and interference were left out because "without a penalty system they
cost nothing", fights end with both men staying on, and `NHL` lost its crease
rule "until a real contact-based interference system exists". The `NHL` set is
delayed offside, hybrid icing and two whistles (the cover, the frozen puck), and
every hit in it is legal.

The two fouls in the first set are ones the game already measures and a player
can see coming, and each has a legal way to play the same situation:

- **Boarding.** The contact step already knows the hit's strength, whether the
  victim is on the wall and driven into it (`BoardWallRules`), and how squarely
  he sees the hitter (`BodyBalanceRules.sight`). The legal plays are the ones
  the game already rewards: angle him into the wall from the side, or hold him
  there with the press.
- **Interference.** `HitRules.classify_contact` already separates a check on a
  man with the puck, or just rid of it, from one on a man nowhere near it. The
  third branch is a hit that is rejected for the stat and costs nothing. The
  legal play on a man without the puck is the press, which has no closing speed.

## 1. The fouls (pure, `Scripts/domain/rules/penalty_rules.gd`)

Both are judged from one contact, in the funnel every credited check already
passes through (`HitTracker.on_contact`, fed by the host's own contact step and
by `HitClaimResolver`), so a hosted and a remote hitter meet one rule and the
pair's cooldown dedupes the call as it dedupes the hit.

**Common gates.** The hitter delivered a check (committed, not carrying), the
two are opponents, neither is ghosted or in the box, and play is live
(`PLAYING`). Contact after a whistle is not judged in the first version.

**Boarding** — all of:

- the check landed at full-check strength or more (`HitRules.FULL_CHECK_IMPULSE`,
  the strength that strips and rocks);
- the victim is within `BOARDING_ZONE_M` of the boards (proposed 1.5 m: the
  distance a man is thrown into them, wider than `BACKSTOP_MARGIN_M`) and the hit
  drives him toward them (more than 45° into the wall, the backstop's own test);
- the victim had his back to the hitter: the hitter sat in his rear cone
  (`BOARDING_REAR_COS`, proposed the rear 90°).

His facing is read `BOARDING_TURN_GRACE_S` (proposed 0.3 s) **before** the
contact, from the state buffer the claim resolvers already rewind, so a man who
turns his back as the hit arrives does not draw the call.

**Interference** — all of:

- the check landed at full-check strength or more. A bump, a lean and the press
  never reach it, so a net-front battle is never whistled;
- the victim is not *eligible to be hit*: not the carrier, not within
  `HitRules.JUST_RELEASED_GRACE_S` of losing or releasing the puck, and not in a
  loose-puck battle (the puck loose and within `INTERFERENCE_PUCK_REACH_M` of
  him, proposed 2.0 m).

Boarding outranks interference when one hit is both. A carrier is never called
(he delivers no check), and a fighter is never called for the fight's punches.

**The thresholds are set by playtest.** Each call writes its facts to the F3
overlay (the check's strength, the victim's distance from the wall, the angle he
was hit from, how long since he had the puck), so a call that felt wrong can be
read back and the number moved.

## 2. The call (host-authoritative)

`PenaltyTracker` (`Scripts/game/penalty_tracker.gd`, shaped like
`FightTracker`) judges the contacts and holds the call; `PenaltyLedger`
(`Scripts/domain/state/penalty_ledger.gd`) owns who has been called and who is
serving what.

```
foul judged ──▶ DELAYED ──offending team has the puck──▶ whistle ──▶ assessed at the faceoff
                   │ the fouled team scores first
                   ▼
                waived (the goal stands, nobody sits, no shot is taken)
```

- **Delayed.** The HUD shows the call is coming and against whom. "Has the puck"
  is possession (`GameStateMachine.notify_possession_established`), not a touch:
  a deflection off the offending team keeps play alive.
- **A second foul in the delay** by the same team is assessed too. One by the
  fouled team makes the two coincidental (below).
- **Any other stoppage** in the delay (a goal, an icing, a cover, the horn)
  assesses the call as well: every pending call becomes a minor as the next
  faceoff is placed, which for a horn is the next period's opening one.
- **A goal against a team already short** ends its minor nearest its end, and
  the call pending against it stands.
- **The faceoff** is in the offending team's end, at the dot on the puck's side
  (`GameRules.icing_faceoff_dot`), the geometry icing and the cover already use.
- **The toast** names the foul and the player. `PenaltyRules` returns a locale
  key and the HUD calls `tr()`.

## 3. 5v5: the box

- **Length.** `PenaltyRules.MINOR_PERIOD_SHARE` (0.1) of the match's period
  length, floored at `MINOR_MIN_S`. The penalty clock runs only while the game
  clock does.
- **Going in.** At the whistle the penalized skater skates to his team's
  penalty-box door, not to a faceoff spot, and is hidden on reaching it: the
  period break's skate-off to the bench door, pointed at a different door
  (`PlayerRules.bench_start_position` gets a `penalty_box_position` sibling off
  `ArenaRinksideLayout.PENALTY_BOX_CENTER_Z`). His team's box is the one on its
  bench's side of centre, straight across the ice from the bench.
- **In the box** he has no presence on the ice: no collision, no puck play, no
  place in a faceoff, the AI's snapshot, the offside count, time on ice, the
  camera's targets or the off-screen arrows. That is `Skater.in_box`, which
  each peer sets from the ledger. His controller holds him as a dead-puck
  phase does, the host ghosts him (`is_ghost` already gates contact and puck
  play), the bots' snapshot leaves him out, and each peer hides him.
- **Coming out.** When his time is up he steps out of the door into live play
  and is in it from his first stride. Nothing stops the play for him.
- **A power-play goal** releases the short-handed team's earliest minor. A goal
  while the teams are even (coincidental minors) releases nobody.
- **The floor is three skaters.** A third minor against a team with two in the
  box is queued and starts when the first ends.
- **Icing.** A short-handed team may ice the puck (`InfractionRules`).
- **Carry-over.** Time left at a horn is served from the next period's first
  drop, overtime included.
- **A disconnect** changes nothing: the penalty runs on the slot, and a
  reservation already holds that slot empty. A player who rejoins inside his
  penalty rejoins in the box.

**The box camera.** A local camera at a seated eye height inside the box, its
yaw following the puck, mounted the way `_become_local_spectator` mounts the
`CameraDirector`. It runs on the render clock and opts out of interpolation like
every other player camera. The HUD shows the foul and the time left, large.

**A strip under the scorebug** shows the manpower ("5 ON 4") and the minor
nearest its end, in the ink of the team with the extra man (`HudPenalties`).
The same panel carries the two banners: the delayed call, telling each team
what the raised arm means for it, and the boxed player's own foul and clock.

## 4. Faceoff formations by headcount (Phase 1, as built)

A faceoff spot was a function of the seat, and the centre's seat was what took
the draw, so a team whose centre was off the ice put nobody on the dot. That
was already true of a team holding a reconnect reservation for its centre.

The men a team has on the ice are now **cast** into the faceoff's spots
(`FaceoffFormation.cast`, pure). A spot is named by the seat whose place it is,
so a man cast into a spot stands where `PlayerRules.faceoff_position` puts that
seat, end-zone alignments included. Nobody stands anywhere new.

| Men | Spots filled |
|---|---|
| 5 | the dot, two wings, two D: seat for seat, unchanged |
| 4 | the dot, two wings, one D |
| 3 | the dot, two wings (3v3 at full strength is this, unchanged) |
| 2 | the dot, one wing |

Casting, the same on every machine:

1. **The dot** goes to the lowest seat on the ice. Seats run C, LW, RW, LD, RD,
   so that is the centre, then the left wing, then the right, and a defenseman
   only with no forward left.
2. **Each wing** keeps its own winger if he is on the ice and not taking the
   draw. An open wing is filled by its own side's defenseman; only when he is
   gone too does the other defenseman cross the ice for it.
3. **A defenseman not cast up** keeps his own spot.

- **"The centre" is the draw-taker** wherever the faceoff used to read the seat:
  the reach-derived distance from the dot (`faceoff_center_distance`), the swipe
  capture (`begin_draw_tracking`), the drop's stamp (`mark_draw_drop`) and the
  crouch over the dot (`Skater.is_faceoff_center`).
- **Nothing changed on the wire.** The `on_faceoff_positions` payload already
  names every skater the host placed, and a client knows each one's seat, so it
  runs the same cast to find the draw-taker. Phase 2 keeps a boxed skater out of
  that payload, which keeps him out of the cast.
- **Not touched:** a mid-match seat swap still teleports the swapped player to
  his new seat's own spot (`SlotSwapCoordinator`).

Tests: `test_faceoff_formation.gd` holds the cast over every combination of
seats (one man per spot, the lowest seat on the dot, the wings filled first);
`test_phase_coordinator.gd` holds the placement and the client's read.

## 5. 3v3: the penalty shot (Phase 3, as built)

In 3v3 a foul is called and delayed exactly as in 5v5. What it costs is one
penalty shot, taken by the man who was fouled, a bot included.

**There is no new phase.** The proposal appended a `PENALTY_SHOT` phase; the
shot is built on the faceoff's own two phases instead, because they already
are a set-up followed by a puck waiting to be collected:

| Phase | In a faceoff | In a penalty shot |
|---|---|---|
| `FACEOFF_PREP` | everyone skates to his spot; the countdown | the shooter skates to centre, everyone else to his own bench; the countdown ("PENALTY SHOT IN 2") |
| `FACEOFF` | the puck drops and is live until someone has it | the puck, laid a stride ahead of the shooter, unlocks ("GO!") and waits for him |
| `PLAYING` | play | the shot, with the game clock held (`GameStateMachine.clock_held`) |

So the reliable faceoff-positions payload, the skate-in, the countdown hold and
the pickup that starts play are the faceoff's, unchanged, and nothing a client
does on a phase change had to learn a new phase.

- **Who is in it.** The ledger entry goes from `PENDING` to `SHOT`, carrying
  the fouled man (`victim_peer_id`), and every peer sets two skater flags from
  it: `takes_penalty_shot` on the shooter, `sidelined` on everyone else. A
  sidelined skater's controller holds him as a boxed one is held, in plain
  sight at his bench; his blade is kept off the puck by a pickup cooldown, the
  bots' snapshot leaves him out so a bot shooter sees an empty rink, and a
  local player who is sidelined watches from the broadcast camera.
- **When it starts.** As the next faceoff is placed, as a minor is assessed in
  5v5: the placement finds the shot staged and sets it up in the faceoff's
  place (`PhaseCoordinator._place_penalty_shot`, `FaceoffPlacement`).
- **More than one call.** A call against each team washes the other out, and a
  team called twice in one delay gives up one shot, to the man fouled first.
  If the man fouled has left the match, no shot is taken.
- **The attempt** is `PenaltyShotAttempt`, the running numbers
  `PenaltyShotRules.classify` reads, which the drill now steps too. In a match
  it also ends the shot when the shooter never collects the puck
  (`FACEOFF_TIMEOUT`), when the goalie covers it, and when the puck has left
  the blade and is no longer going at the net (`PenaltyShotRules.shot_is_dead`:
  a save, a post, a puck lost wide). There are no rebounds. The drill keeps
  its old behaviour and lets a saved puck play on.
- **A goal** is the goal line's to call, through the ordinary goal pipeline:
  the shooter is credited, there are no assists (the stoppage cleared the
  chain), and the celebration, the replay and the centre-ice faceoff follow.
- **No goal** whistles the play and faces off in the defending team's end, on
  the puck's side.
- **A penalty shot that misses the net is not an icing**, and the clock does
  not run.
- **A bot taking the shot** was measured in the duel harness at every tier: it
  collects the puck at once, drives the net without tripping the keep-driving
  rules, and shoots from in close (*slow* `test_bot_penalty_shot.gd`). The harness's
  goalie is the static one, so its scoring rate says nothing.

Known gaps: a player who joins while a shot is on is not sidelined until the
next ledger change; and the shot's banner stays up over the play.

## 6. Fights (Phase 4, as built)

Under `NHL` in 5v5 each man who fought sits a minor: both go to the box at the
faceoff after the fight and the teams play 4-on-4. A fight in 3v3 is not
penalized, and neither is one under `ARCADE` (`PenaltyRules.penalizes_fights`).
A challenge that lapses costs nothing, so there is no instigator.

- **Called when the fights are over, not as they start.** The host notes each
  pair as they drop the gloves and calls them all as the fight's stoppage ends
  (`PenaltyTracker.note_fight` / `call_fighters`), so nothing reads as a
  delayed call while they fight. The faceoff placed next assesses them with
  whatever else is pending, and the toast says the minor is assessed rather
  than delayed.
- **A goal never ends a fight's minor** (`PenaltyRules.ends_on_a_goal`). Both
  teams sit a man for it, so neither is short because of it. With a foul's
  minor running as well (4-on-3), a goal against the shorter team ends the
  foul's minor and leaves the fighter where he is.
- **They count toward the floor of three** like any minor, so a fighter whose
  team already has two in the box waits his turn.
- **The faceoff after the fight** is where it was, with four a side.
- **The bots fight as before.** A grudge still sends a bot after a man, and
  nothing prices the minor: it costs both teams the same.

## 7. Bots

The bots learn each rule in the phase that adds it.

- **They do not foul on purpose.** The body-check gate reads the same
  `PenaltyRules` predicates off what the bot can see: a man without the puck is
  pressed, not checked, and a man with his back turned near the wall is held up
  or angled. A bot fouls the way a player does, when the situation changes
  inside its reaction time after it has committed, so `BotSkillProfile`'s
  existing reaction knob is the discipline dial and no new one is needed.
- **A boxed bot** idles until its time is up.
- **A bot takes its own penalty shot.** Whether the carrier's search drives the
  net alone without stalling under `PenaltyShotRules` has to be measured first.
- **A man up and a man down.** A short team already fills its D-zone posts by
  importance and clears the puck (*Phase 2 as built*). What is left for its own
  phase is the shape: a passive box at four and a triangle at three that
  protects the house and pressures only a loose or bobbled puck, where today
  the short team still plays man-on-man below the dots and sends its puck-side
  defenseman to the battle. Design it from how a 5-on-4 plays with the bots as
  they are now.

## Phases

| # | What | Playtest |
|---|---|---|
| 1 | Faceoff formations by headcount, and the draw-taker (**built**) | a faceoff with a seat empty: a lobby started short, or a reservation |
| 2 | `PenaltyRules`, the ledger, the delayed call, the box, short-handed play, the box camera, the scorebug strip, bots that avoid fouls and serve them (5v5) (**built**) | a penalty start to finish |
| 3 | The penalty shot (3v3), bots shooting (**built**) | a foul in 3v3 |
| 4 | Fights' coincidental minors (5v5) (**built**) | a fight under `NHL` |
| 5 | Bots a man up and a man down | 5-on-4 against bots |
| 6 | Stats (`PlayerStats` penalties, power-play and short-handed goals), career columns, Game Pucks | — |

## Phase 2 as built

- **The ledger travels whole, on a reliable RPC**, whenever it changes and to a
  joiner; nothing was added to the snapshot. A client seats the box from it,
  runs its clocks down for display and waits to be told who came out. It has to
  be the reliable channel: a client derives the faceoff cast from the
  `on_faceoff_positions` payload, a boxed skater holds no seat in it, and the
  ledger is sent ahead of that payload (`Scripts/networking/CLAUDE.md`).
- **Bots** let up on a foul through a last pass on the Hit button
  (`SkaterAgentDiscipline` → `AIFoulRead`), not inside each verb's own gate, so
  the press, the board hold and the stand-up are judged by one read. The
  possession they read is the snapshot's, already delayed by the tier's
  reaction, so no new knob was needed. A boxed bot's team brain drops him
  (`exclude_skater`) and plays the roles it has left.
- **A team short in its own end fills the posts by importance.** Measured on
  the 5v5 election as it stood, a team with a defenseman in the box left the
  net front empty and kept both wingers high: the net-front post is the D
  group's, and the forwards' posts were filled first. A D-zone post whose group
  is empty now takes a body from any group at its own priority when the team
  has fewer bodies than posts (`AIRoleSlots5.assign`), so the order is the
  puck-side defenseman, the net front, the slot, the strong wall, and the
  weak-side winger's ice is what goes uncovered. It is still the five-man
  hybrid coverage with a post missing, not a box.
- **The bots know a short-handed team may ice the puck**
  (`TeamBrain.icing_enforced`, off `WorldSnapshot.short_handed_team_id`), so a
  dump or a rim down the ice is no longer priced as a whistle against them.
- **The thresholds are the proposal's**, untested in play: the 1.5 m boarding
  zone, the rear 90°, the 0.3 s turn grace, the 2 m loose-puck reach.

Known gaps, each small enough to leave for the playtest to rank:

- **A recorded replay draws a boxed skater.** Hiding is per peer and live, so a
  goal replay or a `.mreplay` shows him as a ghost standing at his door. Fixing
  it puts `in_box` in the snapshot (the body-state byte has two spare bits).
- **The box camera's seat is unseen.** Its position is derived from the rink's
  numbers and has not been rendered or played.
- **A foul after the whistle** is not judged, and neither is contact in the
  goal celebration.
- **No stat** is kept for a penalty yet (Phase 6), and the replay records no
  event for a call.

## Wire summary

- **Phase 2 (v105):** three reliable RPCs — the call (peer, foul), the penalty
  whistle, and the ledger (`PenaltyLedger.to_wire`). No snapshot or replay
  format change (`docs/protocol-history.md`).
- **Phase 3 (still v105, unreleased):** the ledger's wire gains the fouled
  man and a `SHOT` state, and the penalty whistle says whether it is a shot
  ending without a goal. No phase was added.

## Not in this plan

- **Goalie interference.** It needs a read of a skater's contact with the keeper
  (`Skater.clamp_body_to_goalies` knows when it pushes one off him). It is the
  natural next foul, and it gives `NHL` back what it lost when crease camping
  became `ARCADE`-only.
- **A penalty shot in 5v5** for a foul on a breakaway.
- **Stick fouls.** The candidate is to make a foul the *miss* of a verb that
  already exists: a poke that takes the skates and not the puck is a trip, a
  lift that lands on the hands and not the shaft is a slash or a hook. That adds
  a blade-against-body test and no button, and it puts a price on a stick check
  thrown without looking.
- **A figure seated in the box.** The first version hides the skater at the
  door.

## Open questions

1. **What a penalty shot is worth.** Still unmeasured: it needs the live
   goalie, and the harness that skates a bot through a shot has a static one.
   If shooters score far more often than a 5v5 power play does, a foul costs
   much more in 3v3 than in 5v5. The drill's results card is the quickest read.
2. **Which winger takes the draw.** Built as the left wing before the right
   (the lowest seat). The other reading is the winger on a particular side of
   the dot.
