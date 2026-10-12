# Defensive play — stick check, stick tie, board pin

Status: **Phases 1–3 implemented** (v66–v68), playtest pending. Two revisions are
planned, not built:
- **The pin** becomes a locked position contest (*Pin revision*), replacing 3b's
  grip-and-budget pin.
- **The tie** becomes two sticks tied together, off the ice and slowed, held by
  either player (*Tie revision*).

Phase 4 is candidates. Each phase is meant to ship as its own PR, with its own protocol
bump and playtest.

## Decisions banked

- **Stick lifts get their own button** (working name `stick_check`). Q goes back to
  being only the deflect: a raised Q blade still tips airborne pucks but no longer
  hooks shafts. The lift stops depending on the shot loft wheel.
- **Tap lifts, hold ties.** On the stick-check button, a tap is a lift attempt and a
  hold is a stick tie, which only matters against a player without the puck.
- **The tie stays its own action, and its home is the net front** (decided after
  Phase 3), where there are no boards to pin against. The pin owns the wall; the tie
  owns the slot and the crease. Two sticks tied together, off the ice and slowed. It
  holds while either player keeps holding the button and the sticks stay together,
  with no time limit (see *Tie revision*).
- **Ties are pure geometry in v1** (no Weight term until playtested), and **a
  pinning defender's stick stays off the ice** (the pin is a one-for-one trade).
- **The pin is a locked position contest, not a stun** (decided after Phase 3; see
  *Pin revision*):
  - a victim holding Ctrl is braced and cannot be pinned;
  - once a pin connects, neither player's stick plays the puck;
  - both slide along the wall on the direction keys, and the victim is free once
    their body is no longer lined up with the pinner's.
- **The bots learn each verb in the phase that adds it,** not afterwards. Today they
  never block and never stick-lift on defense, so in a lobby that is mostly bots a
  human-only verb barely shows up.

## Why — what defense is today

| verb | state | bots |
|---|---|---|
| body check | closing-velocity impulse, Ctrl commit, stagger and knockdown | yes (PRESSURE, TRACK) |
| poke | stick-on-stick momentum contest | yes (poke jab: aim the blade through the puck) |
| shot block | C, one-knee seal | **never** |
| stick lift | Q held at loft MID or HIGH, carrier only | **never on defense** |
| board play | a position clamp; a check into the wall plays like one in open ice | — |
| stick tie, pin, frozen puck | none | — |

**Why a stick lift wins so little.** `Puck.apply_stick_lift_strip` leaves the puck
moving at the carrier's velocity. At that moment:
- The lifter's own blade is still up, and a raised blade can't touch a grounded puck
  (`PuckReceptionRules.blade_can_interact`). They have to let go of Q and wait for
  the blade to come down.
- The carrier skates on beside the puck, and it moves away from a lifter who is
  beside or behind it.
- The carrier's blade is up for only 0.4 s (`STICK_LIFT_FORCED_LIFT_S`), and their
  re-grab cooldown is 0.5 s (`reattach_cooldown`). After that they pick it back up.

The lift gives the puck up for a moment but rarely wins it.

Two defects found during the survey; Phase 1 fixes both by construction:
- **The resolver never checks the lifter's blade was up.** `StickLiftClaimResolver`
  checks the rewound claimant for ghost and block, but not `blade_up`. The client gate
  is the only thing stopping a grounded-blade lift claim.
- **A victim can lift while their own stick is lifted.** A forcibly lifted blade
  counts as `blade_up`, so during that window the victim can stick-lift an opposing
  carrier.

## Phase 1 — the stick-check button, and lift-and-take

### Input
- **New action `stick_check`.** It is rebindable on both devices and gets a row in the
  controls tab and in `locale/translations.csv`. The existing `stick_lift` action
  keeps its name (it is in saved bindings) and is relabelled "Deflect".
- **Wire.** It takes the two flag bits left in `InputState`: `0x4000` for
  `stick_check_held` and `0x8000` for `stick_check_pressed`.
  - The press gets its own bit for the same reason `stick_lift_pressed` has one:
    `RemoteController` ORs edges across inputs it drops.
  - **After this the u16 flag field is full.** The next input bit grows the record
    from 24 to 25 bytes.
- **Defaults:** F on the keyboard (`save_goal_clip` shares it only during the goal
  cinematic), X on the pad. X was freed when the loft moved to D-pad up/down and the
  ping to D-pad left (pad scheme 2, with a one-time migration of saved binds). The
  UI calls it "Stick Lift"; the tutorial already calls the poke a stick check.

### The stick-check state machine
`SkaterStickCheck` is a RefCounted collaborator on `SkaterController`. It exclusively
owns the phase and its timer, and it is driven only by inputs, so reconcile replay
reproduces it. `StickCheckRules.step` is the whole table.

| phase | entered by | lasts | blade | stick plays puck? |
|---|---|---|---|---|
| `IDLE` | — | — | normal | yes |
| `RISE` | `stick_check_pressed`, not carrying, not committed/blocking, not forced up | `RISE_S` 0.06 | rising | no |
| `HOOK` | end of RISE | while held, at least `HOOK_MIN_S` 0.04, at most `HOOK_MAX_S` 0.14 | up; tests opposing shafts every tick | no |
| `DROP` | released inside the hook window | `DROP_S` 0.05 | forced down fast | **yes** — the take |
| `RECOVER` | still held at `HOOK_MAX_S` | `RECOVER_S` 0.22 | up, then down | no |
| `REARM` | end of DROP | `REARM_S` 0.25 | normal | yes; a new press is ignored |

Phase 2 adds `TIE`: still held at the end of the hook (`HOOK_MAX_S`), the stick stays
out; letting go DROPs, and `TIE_MAX_S` 1.5 s ends in RECOVER. Like every other phase it
reads only the button — which stick it ties is the host's (below).

- **A whiff costs something.** The stick is out of play from the press to the drop,
  and the next lift waits for the rearm. Holding the stick up too long costs the
  slow recovery. Today the held-Q lift tests every tick for free.
- **Only the HOOK phase can lift.** `blade_up` keeps meaning "can reach airborne
  pucks". The shaft test in `PuckController._check_interactions` moves from
  `if skater.blade_up` to "this skater is in HOOK". So a raised Q blade and a
  forcibly lifted blade skip the poke and lift nothing, which fixes the victim quirk.
- **`stick_check_phase` joins `SkaterNetworkState`**, packed with its elapsed ticks
  in one u8. Remotes need it for the pose. The resolver needs it to check that the
  claimant was in HOOK at their rewound instant, which closes the missing
  `blade_up` check, and the local reconcile adopts it before replay.

### Lift-and-take
- **The hook's quality scales the victim's forced lift.**
  - `StickCheckRules.hook_quality` = `1 − d / STICK_LIFT_RADIUS`, where `d` is the
    distance from the lifter's blade to the carrier's shaft. A hook square under the
    shaft gets full leverage; one at the rim glances off.
  - The forced lift runs `lerp(LIFT_FORCED_MIN_S 0.4, LIFT_FORCED_MAX_S 0.9, quality)`.
  - The victim's re-grab cooldown becomes forced lift + 0.1 s, so they can't grab it
    back before their blade is down.
- **The lifter takes the puck.** On success:
  - The lifter carries no cooldown at all (`poke_checker_cooldown` is not set).
  - The puck keeps the carrier's velocity, as today.
  - The lifter's blade hooked the shaft near the puck, so letting go brings it down
    on the puck within `DROP_S` and the ordinary proximity pickup takes it. No
    possession is ever awarded.
- **Both detection paths share one rule.** The host's present-time detection (bots and
  the host player) and the client-claim path (`StickLiftClaimResolver`) both call
  `StickCheckRules`. The victim's cosmetic re-lift notify (`notify_puck_stolen`)
  carries the forced-lift duration.

### Bots
PRESSURE chooses between the poke jab and a lift by what the bot can actually see:
- The jab needs a clear blade path to the puck. A carrier shielding the puck with
  their body blocks that path.
- The lift needs blade reach to the shaft, which crosses in front of the body and can
  be reached from behind or beside.
- So the model is reach to the puck, accounting for the body in the way, against reach
  to the shaft segment. A lift is never a dice roll.
- `BotSkillProfile` gets a gate plus a reaction knob, following the pattern of the
  body-check gate.

### Tests
- `StickCheckRules`: the phase table, `hook_quality`, the forced-lift curve.
- A scripted chase grid (approach side × lifter speed): a stick-side lift wins
  possession at a materially higher rate than the current baseline. Record the
  baseline first.
- The claim resolver: rejects a claimant who was not in HOOK at the rewound instant.
  `test_claim_resolver_contract.gd` keeps covering it.
- A raised Q blade and a forcibly lifted blade strip nothing.

## Phase 2 — stick tie

### Rules
- **As built:** the defender's TIE phase is input-driven (held past the hook) and
  carries no target; the host's `StickTieTracker` latches a victim at any tick of
  the TIE phase, not only its first, so a stick held out can find a shaft. The tied
  flag rides the skater flags byte's spare bit 7 rather than a `tied_by` index —
  nothing on a client needs to know who tied whom.
- **Engage.** In the TIE phase, the defender's blade is within
  `TIE_ENGAGE_RADIUS` (= `STICK_LIFT_RADIUS`) of a non-carrying opponent's hand→blade
  shaft, over or under it.
- **Effect on the victim (tied).** Every reception path becomes a deflect through
  the existing `Puck.apply_blade_deflect` path:
  - the catch (`should_receive`), the loose-puck pickup and the provisional pin;
  - the deliberate deflect, which loses its aim: a FLAT redirect damped by
    `TIE_BOBBLE_DAMP`, so the puck dies at the victim's feet, with no RNG;
  - the one-timer connect (`ShotReleaseRules.one_timer_connects`).

  The tied player also can't poke or stick-check, because their stick is occupied.
- **Cost to the defender.** Their stick is spent too: no poke, no interception, no
  reception while tying.
- **Holding it.** This is a cursor duel. The defender keeps their blade within
  `TIE_HOLD_RADIUS` of the victim's shaft. That radius is larger than the engage
  radius (hysteresis), sized to the blade's travel over the interpolation window plus
  IK slack.
- **Breaking it.**
  - the two separate past `TIE_HOLD_RADIUS` (the victim yanks the stick away or skates
    off);
  - the defender releases the button;
  - either player is knocked down;
  - the `TIE_MAX_S` 1.5 s cap runs out, after which a `TIE_COOLDOWN_S` 0.75 s cooldown
    stops the same defender chaining ties on the same victim.

  v1 is pure geometry, with no attribute term (decided: geometry only).

### Netcode
- **Engagement is a claim.** `StickTieClaimResolver` follows the full contract in
  `Scripts/game/CLAUDE.md`:
  - the target's shaft is rewound remote-view, forward-predicted as the lift resolver
    does;
  - the claimant's blade goes through `ClaimantView`;
  - the claim is routed through `DeferredClaimQueue`.
- **Holding is host-present.** The host evaluates it every tick against each side's
  own input stream.
- **Known asymmetry.** The defender sees the victim's blade an interpolation delay
  late, which favours the victim. The hold radius absorbs it, and break-reason
  telemetry measures it before tuning.
- **Wire.** `stick_tied`, bit 7 of the skater flags byte (see *As built*).
  - The victim's client gates its provisional pickup and its one-timer on it.
- **New RPC pair:** `send_stick_tie_claim` / `receive_stick_tie_claim`.

### Bots
- **Defense (MARK and the 5v5 zone coverers):** tie the man they're covering when that
  man is a live target, meaning the carrier has a lane to them or a puck in flight
  will cross their blade. The price is the lane: a tied stick intercepts nothing, so
  the bot compares its chance of intercepting with a free stick against its chance of
  denying the reception by tying.
- **Offense (FINISHER):** a tied bot yanks the blade free when a feed is coming.
- Both get difficulty knobs.

### Tests
- Rules: engage, hold, the break reasons, the cap and cooldown.
- A 14 m/s pass that an untied receiver catches bobbles off a tied one.
- A tied one-timer whiffs, and a tied tip dies flat.
- The resolver passes the contract test.

## Phase 3 — the boards

### 3a. Checks against the boards hit harder
- **The problem.** Stagger and knockdown come from the victim's transfer impulse, and
  the rink clamp then removes their velocity into the wall. So the boards add nothing
  to a hit.
- **The change.** When the victim is within `BACKSTOP_MARGIN` of the boards and the
  contact normal points into them (more than 45° into the wall), the boards take the
  recoil. The impulse used for stagger, knockdown and VFX intensity is the full
  closing speed along the normal, as if the victim were immovable.
- **Where it lives.** `BodyCheckRules.backstop_impulse` is a pure function.
- **Three-party invariant.** The host's contact step, the client's live step and
  replay, and `HitClaimResolver` must all call it with the same inputs
  (`Scripts/networking/CLAUDE.md`, body-check contact geometry). The knockback
  velocity itself doesn't change; the wall already clamps it.

### 3b. The pin (as built in v68 — to be replaced by the *Pin revision*)
- **Onset (host-authoritative, `Skater._check_board_pin`).**
  - The defender is committed (`hit_committed`, not carrying) and touching an
    opponent. Carrier or not, it doesn't matter.
  - The victim's disc is within `PIN_WALL_MARGIN` 0.25 m of the boards, and the
    contact is within 45° of square into them.
  - The defender drives into the wall: velocity of at least `PIN_DRIVE_MIN_M_S` 1 m/s,
    or move intent of at least `PIN_DRIVE_MIN_INTENT` 0.5, along the outward normal.
  - The victim is not inside `PIN_IMMUNITY_S` 1.0 s of their last pin.
- **State (`SkaterBoardPin`).** A grip timer of `PIN_GRIP_S` 0.15 s that the host
  refreshes every tick the defender still drives, and decays everywhere else like
  `stagger_timer`. The 2 s cap (`PIN_MAX_S`) and the escape drain sit on a host-only
  budget. `pin_strength` = m_defender / (m_defender + m_victim). The wall normal is
  derived from the victim's position and never goes on the wire.
- **Effect on the victim.** A GDScript post-step after the movement kernel (the
  kernels have C++ ports held by parity tests, and the pin is not part of them) bleeds their
  along-wall speed at `PIN_HOLD_DECEL_M_S2` 14 m/s² × strength (more than a stride
  can push); stance and check commit are off. A pinned carrier keeps the stick, and a
  pinned non-carrier can still play the puck. The defender's commit keeps their own
  stick off the ice.
- **Escape.** The budget drains at `1 + escape_drive · (1 − pin_strength) ·
  PIN_ESCAPE_RATE`, where `escape_drive` is the victim's move intent along the wall.
  Pushing flat out roughly halves the pin; it never wins it outright.
- **Netcode.** `pin_timer` (u8 at 0.01 s) and `pin_strength` (u8) on
  `SkaterNetworkState`. The victim's own client re-derives the pin through reconcile
  like stagger. Remote renders and the host rewind apply the same
  `BoardPinRules.forward_correction` to the forward prediction (render == rewind).
- **Bots** (`apply_board_play`). A bot whose man is pinned and still in contact keeps
  driving while a teammate's arrival time at the puck beats the time left on the pin
  ("pin and support"). A pinned bot pushes along the wall, away from the nearest
  opponent.
- **Not built:** the `GaitPinLayer` pose.

### 3c. Frozen puck
- **As built.** The whistle follows the goalie-freeze stoppage (its own signal,
  RPC and toast, `_whistle_and_faceoff` at `nearest_faceoff_dot`) instead of a new
  `FaceoffReason`, which belongs to the domain-flagged icing/offside stoppages. In
  ARCADE a puck still carried by the pinned skater is left to the existing
  wall-squeeze release; only a loose one squirts.
- **The rule.** `FrozenPuckRules` (pure) accumulates time while all of these hold:
  - the puck is loose, or carried by a pinned skater;
  - it is within `FROZEN_BOARD_MARGIN` of the boards and slower than `FROZEN_SPEED`;
  - a pinned skater's disc is within `FROZEN_REACH` of it.

  Moving more than `FROZEN_SLOP` from its anchor resets the count.
- **NHL.** At `FROZEN_PUCK_S` ≈ 2.0 s there is a whistle and a faceoff at
  `GameRules.nearest_faceoff_dot(puck_xz)` (see *As built*).
- **ARCADE.** At the same threshold the pin ends and the puck squirts along the wall,
  away from the pinned body, at `FROZEN_SQUIRT_SPEED`.
- **To verify:** how it interacts with delayed offside and with the icing tag-up in
  the stoppage pipeline (`PhaseCoordinator`).

### Tests
- `BoardPinRules`: the onset gates, the strength, the escape drain, the immunity.
- Integration:
  - a pin under `integrate_forward` (forward-predict parity);
  - a backstop hit staggers longer than the same closing speed in open ice;
  - parity of the three-party hit geometry with the backstop;
  - the frozen puck whistles in NHL and squirts in ARCADE.

## Pin revision — a locked position contest (planned)

### Why
3b's pin is a stun with a timer. The victim can't move along the wall at all, and
pushing as hard as they can only halves the pin, so escaping it is mashing, not winning
it. Meanwhile a pinned carrier keeps full control of the puck, so the pin rarely wins the
puck either.

**What's taught.** The pin is the last step of the checking progression (Hockey Canada:
angling, then stick check, then body contact, then body check). The cues:
- "stick on puck, body on body", then "eliminate their hands with body contact";
- "pressure on both hips … seal the player to the boards".

It is held by position, from the inside, hips on hips. It breaks when the victim's hips
get past the pinner's. Its purpose is to separate the player from the puck, or hold
them until support arrives: one player makes contact, the other picks up the puck. The
taught escape is to accept the contact and roll off. Don't pin as the last player back.
Officials whistle once nobody can play the puck and the battle has stopped going
anywhere.

**What other games do.** EA NHL (NHL 10 onward; still "Board Pin" on Triangle in NHL 25)
locks both players into a pin from a dedicated button. Neither stick plays the puck.
Each side kicks it with the bumpers, a teammate pokes it out, and it becomes a scrum.
Players credited it with making the dump-and-forecheck game work. The complaints were
penalties for hitting a player on the wall when you meant to pin him, and that a pinned
player can't be hit.

So the redesign keeps EA's "both sticks out, support decides it". It resolves the pin
by movement on both sides instead of a canned state, which keeps both players in
control the whole time.

### Rules
- **Onset.** Everything in 3b still applies: committed, in contact, victim within
  `PIN_WALL_MARGIN`, square to and driving into the wall, outside immunity. One new
  gate:
  - **the victim is not braced.** A victim holding Ctrl (`hit_committed`, carrying or
    not) can't be pinned. Ctrl is already both sides of contact: the victim's commit
    cuts the impulse it takes (`body_check_brace_resistance`). Bracing is not free,
    because the COMMIT posture costs grip and stride, so a carrier who skates the whole
    wall braced skates it worse.
- **Locked.** Once a pin connects, both players are locked:
  - **Neither stick plays the puck.** No catch, pickup, provisional pin, poke, lift,
    tie or shot. This is the same gate `stick_tied` and `is_stick_busy` already sit on.
  - **A pinned carrier loses the puck.** It is released at their own velocity and
    sits loose at both players' feet. Whichever side's support gets there first wins
    it; otherwise the frozen-puck rule (3c) decides.
  - **The victim's stance and commit are off.** The pinner must keep holding Ctrl.
- **The contest.** Both players slide along the wall on their direction keys.
  - **Along-wall speed is capped for both.**
    - The victim's cap is `PIN_SLIDE_VICTIM_M_S` × 2·(1 − `pin_strength`), so a
      heavier pinner slows them and a lighter one doesn't.
    - The pinner's cap is `PIN_SLIDE_PINNER_M_S`, higher than the victim's, so a
      pinner who reads the victim correctly can always keep up.
  - **Escape:** the victim's along-wall offset from the pinner,
    |(p_victim − p_pinner) · wall tangent|, passes `PIN_ESCAPE_OFFSET_M`. Either side
    counts, so a pinner who over-commits to a fake frees the victim the other way.
    The victim wins by changing direction faster than the pinner reads it, or by a
    weight edge. The pinner wins by reading the slide and not over-chasing.
  - **Movement away from the wall** is the bodies' business, as today: the clamp and
    the pinner's body hold the victim in.
- **Ends.**
  - the escape offset is reached;
  - the pinner lets go of Ctrl, or their body separates from the victim by more than
    `PIN_SEPARATION_M` beyond contact;
  - either player is knocked down;
  - a stoppage, or the ARCADE squirt;
  - the cap `PIN_MAX_S`, raised to 3.0 s so that, with the puck trapped, the 2.0 s
    frozen whistle lands first.

  Every end starts the victim's `PIN_IMMUNITY_S` 1.0 s.
- **Retired from 3b:** the grip timer refreshed by drive, the 14 m/s² along-wall
  bleed, and the escape-drain budget.

### Latency is the design constraint
The pinner sees the victim late: the victim's upload, the interpolation delay
(75 ms), the pinner's download, and then the pinner's own reaction. Before the
pinner's answer reaches the host, add their upload. A reversal therefore buys the
victim an along-wall head start of about 2 × v_victim × D. Here D is the pinner's
whole reaction-plus-network delay, budgeted at 0.4 s: 0.25 s human reaction plus
0.15 s network.

- **The rule:** `PIN_ESCAPE_OFFSET_M` ≥ 2 × `PIN_SLIDE_VICTIM_M_S` (at equal weight)
  × 0.4 s. One reversal read with ordinary lag doesn't free the victim on its own;
  two chained, or a reversal the pinner misreads, does.
- **A test holds this inequality**, so retuning either number can't hand the contest
  to ping.
- **Break-reason telemetry** (escape, release, cap, frozen) measures it in play
  before any number moves.

### Netcode
- **Wire.** `pin_partner` (s8 slot, −1 none) plus a role bit (pinner or pinned) on
  both locked players. These replace `pin_timer` and `pin_strength`: strength
  derives from the two skaters' weights, and the offset from their positions.
  The cap's elapsed time is host-only.
- **Prediction.** Each client predicts its own locked movement, a speed cap read off
  replicated state, so the only snaps are onset and end, through reconcile like
  stagger.
- **Remotes.** Remote renders and the host rewind apply the same cap to the
  forward prediction (render == rewind), replacing
  `BoardPinRules.forward_correction`'s bleed.
- **Host authority.** Onset, the escape test and every end are host-present.
- **Native kernels.** The cap stays a post-step outside them, as in 3b.

### Bots
- **When to pin** (the taught doctrine, as a grounded read):
  - pin when your support's arrival time at the puck beats the opponents' support;
  - in your own end, pin to kill the play when a whistle is worth more than the
    puck;
  - don't pin as the last skater back.
- **Pinner.** Mirror the victim's along-wall velocity, read through the bot's
  `BotSkillProfile` reaction delay, plus a correction toward zero offset.
- **Pinned.** Reverse when the pinner commits to the slide (its along-wall velocity
  matches the bot's own). It is a deterministic read of the pinner, not a timer or
  RNG.
- **Bracing.** A carrier bot at the wall braces when a committed checker is closing
  square on it. It is gated per difficulty, like the other physical verbs.

### Pose
`GaitPinLayer` for both players: victim chest to the glass, pinner driving a shoulder
in, both sticks off the puck. A pin you can't see reads as a bug, so this ships with
the revision, not after it. Check it with `render-poses.sh`.

### Tests
- `BoardPinRules`:
  - the brace gate;
  - the slide caps by strength;
  - the escape offset on both sides;
  - every end reason;
  - the latency inequality.
- **Integration:**
  - a pinned carrier's puck goes loose;
  - neither locked stick catches a pass;
  - a scripted reversal escapes a lagged mirror only when chained;
  - the frozen whistle beats the cap.
- The existing render == rewind forward-prediction parity, with the cap.

### Later
- **The puck kick.** While locked, directional input nudges the puck along the wall,
  EA's version of a pinned player playing it with their skates.

## Tie revision — two sticks tied together (planned)

### Why
As built, the tie takes away the result, not the stick. The victim's blade moves
exactly as they steer it, but catches, pokes and one-timers quietly don't register.
That is control that lies to you, in the one place Mitts most wants the player to feel
in control: their hands. The only escape is distance, and a tie near the hands can't be
broken at all.

The revision makes the tie a physical state both players can see and both can fight:
two sticks tied together, off the ice. Its home is the net front: a defender ties up a
forward's stick so a pass across or a point shot can't be tipped or one-timed. That's
the play a pin can't make, because there's no wall behind the forward.

### The mechanic
- **Initiate.** Hold the stick-check button (past the hook, the TIE phase) while your
  stick touches the stick of an opponent who doesn't have the puck. "Touching" means
  stick against stick: segment to segment, top hand to blade on both, within
  `TIE_CONTACT_M`.
- **Tied.** Both players are tied up together:
  - **both sticks lift off the ice** (`blade_held_up` reads `stick_tied`), so neither
    can catch, pick up, poke, lift or tip. A grounded puck passes under a raised
    blade; an airborne one that hits it dies flat (the existing bobble);
  - **both sticks are slowed.** Each blade chases its own cursor at
    `TIE_BLADE_SPEED_M_S` instead of `max_blade_speed`. Sticks pushing against each
    other move slowly, so pulling free takes a deliberate pull, not a flick.
- **Either player can keep it going.** The tie holds while at least one of the two is
  holding the stick-check button and the sticks stay within `TIE_SEPARATION_M`.
  - The victim holding on is a real choice: a forward who ties up the defender's
    stick, so it's out of the play when a pass goes to a teammate.
- **It ends** when neither player is holding, or when the sticks pull apart past
  `TIE_SEPARATION_M`. It also ends on a knockdown or a stoppage, and if the victim
  gains the puck.
  - There is no time limit.
  - After it ends, the same pair can't re-tie for `TIE_COOLDOWN_S` 0.75 s.
- **Escaping a holder** is a contest at equal speed. Both sticks are capped the same,
  so a gap opens only when the holder misreads where the escaper is pulling. Once a
  gap opens it never closes while the escaper keeps going, so a few good jukes add up.
  A holder who reads well keeps the tie.
- **The input phase machine stays input-only.** The tie is no longer the TIE phase's
  state. `stick_tied` is set on BOTH players and is what raises, slows and busies the
  stick. The initiator letting go walks their phase out to DROP/REARM as usual, while
  `stick_tied` keeps their stick up if the victim is still holding. A tied player
  can't start a new lift (`stick_taken` already includes `stick_tied`).
- **Retired from Phase 2:** `TIE_MAX_S`, the blade→shaft hold radius, and
  "tied" meaning the victim alone.

### Netcode
- **Onset is a claim**, as today (`StickTieClaimResolver`): the victim's stick is
  rewound to what the initiator saw (`remote_view_time`), and the initiator's own
  stick is taken at self-view. Only the geometry changes, from blade→shaft to
  stick↔stick. Bots and the host's own player engage host-present in
  `StickTieTracker`.
- **Holding is host-present.** Every tick, the tracker reads both players' held flags
  from their inputs (a host-only `stick_check_held` on the skater, not replicated)
  and the distance between the two sticks.
- **The separation allowance is sized to the lag.** It covers a juke read late
  because of the network: about 0.2 s, the interpolation delay plus a typical trip.
  It does not cover a late human reaction, because reading a juke is the skill.
  - The rule: `TIE_SEPARATION_M` ≥ `TIE_CONTACT_M` + 2 × `TIE_BLADE_SPEED_M_S` × 0.2 s.
  - A test holds the inequality.
- **Your own stick is predicted exactly while tied.** The slow cap is a function of
  your own input plus the replicated `stick_tied` bit, so nothing in your blade's path
  depends on the other player's late input. The only snaps are at the edges, through
  the blade's existing reconcile adoption:
  - at onset, your client learns the cap one round trip late, so your blade snaps
    back by however far it moved at full speed in that window;
  - at the end, your blade feels sticky for one round trip.

  A true coupling, where one stick drags the other, is ruled out: your own stick would
  mispredict every tick.
- **Drawing it.** Each screen sees contact slightly differently, so the rig draws the
  two blades meeting at a shared contact point, bent within the allowance and lifted.
  The gameplay blade markers are untouched.
  - A remote finds the pair from replicated state: tied opponents nearest each
    other. If that ever proves ambiguous, add a partner slot (s8) on the wire.
- **Feedback.** A stick-on-stick clack on latch and on break.
- **Wire.** `stick_tied` (flags bit 7) is now set on both players. There is no other
  field change.

### Bots
- **Defense.** The net-front defender (MARK, the 5v5 zone coverers) ties the man in
  front when a pass or a point shot is live, and holds while it stays live. Their
  existing comparison, intercept with a free stick versus deny by tying, stays.
- **Offense.**
  - A tied forward who is the likely target of a pass works free: a juke read off
    the pass in flight or the carrier's lane to them, timed to its arrival.
  - A tied forward who is not the target holds on, keeping the defender's stick out
    of the play.

### Tests
- Rules:
  - stick↔stick contact geometry;
  - the end conditions (both released, separation, knockdown, stoppage);
  - either player's hold keeps it;
  - the cooldown;
  - the separation inequality.
- Both blades raised, slowed and busy; a pass to either player passes under or dies.
- Prediction: a tied client's own blade path matches the host's under the cap.
- The claim resolver keeps passing the contract test.
- The remote pair lookup.

## Phase 4 — candidates, not committed

- **Bots block shots.** The C verb has never been used by a bot.
- **Dive / sprawl poke.** The last-ditch full extension on a 2-on-1 or a breakaway,
  paid for with a knockdown. It needs an input; Y is the one pad face button left
  free.
- **Net-front box-out.** The pin's sustained-contact model in open ice, moving a
  screener out of the goalie's sightline. It would feed the goalie's screen read.
- **Deliberately out:** hooking, holding and interference. Without a penalty system
  they cost nothing, and the game has none.

## Wire summary

| phase | input | `SkaterNetworkState` | RPC |
|---|---|---|---|
| 1 | `0x4000` held, `0x8000` pressed (u16 full) | `stick_check_phase` u8 | `notify_puck_stolen` + forced-lift duration |
| 2 | — | `stick_tied`, flags bit 7 | `send/receive_stick_tie_claim` |
| 3 | — | `pin_timer` u8, `pin_strength` u8 | `notify_puck_frozen_called` |
| pin revision | — | `pin_partner` s8 + role bit, replacing `pin_timer` / `pin_strength` | — |

Each phase bumps `BuildInfo.PROTOCOL_VERSION` and gets an entry in
`docs/protocol-history.md`.

## Where the code goes

Every call site is in a file far past the 800-line ratchet:
- `skater.gd` 2712 lines
- `skater_controller.gd` 3341
- `puck_controller.gd` 1547
- `game_manager.gd` 5603
- `skater_agent_state_machine.gd` 6073

So new logic lives in new files, and the grandfathered files get the calls. Where one
must still grow, its ratchet entry is bumped in the same diff.

| new file | owns |
|---|---|
| `Scripts/domain/rules/stick_check_rules.gd` | the phase table, `hook_quality`, the forced-lift curve, tie engage/hold/break |
| `Scripts/domain/rules/board_pin_rules.gd` | pin onset, strength, escape (the revision: brace gate, slide caps, escape offset) |
| `Scripts/domain/rules/frozen_puck_rules.gd` | the frozen-puck accumulator |
| `Scripts/controllers/skater_stick_check.gd` | the per-skater phase and its timer |
| `Scripts/game/stick_tie_claim_resolver.gd` | the tie claim |
| `Scripts/game/stick_tie_tracker.gd` | host-side tie latch, hold and break; the only writer of `stick_tied` |
| `Scripts/controllers/skater_board_pin.gd` | the victim's pin state (the revision moves it onto both locked players) |

## Docs that change when each phase lands

- `docs/gameplay-design.md`: the Physicality paragraph.
- `Scripts/game/CLAUDE.md`: the resolver list ("four claim signals").
- `Scripts/networking/CLAUDE.md`: "the four blade/hit claim RPCs".
- `Scripts/domain/ai/CLAUDE.md`: the defensive verbs. The physical verbs are a role's
  "extras".
- The tutorial step for the new button.
- The controls-tab labels.

## Open questions

- **Is the tie gated to the net-front zone, or allowed anywhere?** Its job is the
  net front, but nothing yet stops it elsewhere: a winger tied up at the blue line
  when a cross-ice pass comes. A zone gate makes the purpose explicit. Leaving it
  open lets the cost (the defender's own stick is out of play too) keep it rare.
- **Can a stick that is forced up by a lift be tied?** The proposal is no: a lift
  held through to the TIE phase would otherwise tie the player it just lifted,
  which wastes the lifter's own take.
- **The pin and tie revisions' numbers** (below) are starting values, held to their latency
  inequalities, and tuned from break-reason telemetry.

## Starting values

| name | value | note |
|---|---|---|
| `RISE_S` | 0.06 | blade up from the ice |
| `HOOK_MIN_S` / `HOOK_MAX_S` | 0.04 / 0.14 | window in which a hook can land |
| `DROP_S` | 0.05 | blade back down on release |
| `RECOVER_S` | 0.22 | the price of holding the stick up too long |
| `REARM_S` | 0.25 | before the next lift |
| `FORCED_LIFT_MIN_S` / `MAX_S` | 0.4 / 0.9 | victim's forced lift by hook quality |
| `TIE_MAX_S` / `TIE_COOLDOWN_S` | 1.5 / 0.75 | the revision drops the cap and keeps the cooldown |
| `TIE_CONTACT_M` | 0.08 | stick to stick, shaft thickness plus IK slack |
| `TIE_BLADE_SPEED_M_S` | 1.5 | both blades while tied (free: 10) |
| `TIE_SEPARATION_M` | 0.7 | ≥ 0.08 + 2 × 1.5 × 0.2 s |
| `TIE_HOLD_RADIUS` | engage + blade travel over the interp window + IK slack | derive, don't pick |
| `PIN_WALL_MARGIN` | 0.25 m | |
| `PIN_MAX_S` / `PIN_IMMUNITY_S` | 2.0 / 1.0 | the revision raises the cap to 3.0 |
| `PIN_SLIDE_VICTIM_M_S` | 0.6 | at equal weight; × 2·(1 − strength) |
| `PIN_SLIDE_PINNER_M_S` | 0.9 | above the victim's, so a correct read keeps up |
| `PIN_ESCAPE_OFFSET_M` | 0.5 | ≥ 2 × 0.6 × 0.4 s; a hip's width at the 0.35 m body radius |
| `PIN_SEPARATION_M` | 0.15 | beyond contact |
| `FROZEN_PUCK_S` | 2.0 | |
