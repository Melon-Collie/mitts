# Defensive play — stick check, stick tie, board pin

Status: **Phase 1 implemented** (v66), playtest pending. Phases 2–4 proposed. Each
phase is meant to ship as its own PR, with its own protocol bump and playtest.

## Decisions banked

- **Stick lifts get their own button** (working name `stick_check`). Q goes back to
  being only the deflect: a raised Q blade still tips airborne pucks but no longer
  hooks shafts. The lift stops depending on the shot loft wheel.
- **Tap lifts, hold ties.** On the stick-check button, a tap is a lift attempt and a
  hold is a stick tie, which only matters against a player without the puck.
- **A tie denies all reception.** Any puck that reaches a tied blade bobbles: no catch,
  no one-timer, no tip.
- **Only a committed checker (Ctrl) pins.** Driving an opponent into the boards while
  committed pins them.
- **The frozen-puck whistle is NHL-only.** In ARCADE, a trapped puck squirts free at
  the same threshold instead.
- **A lift's sequence follows the lifter's button alone, never whether the hook
  landed.** Online, the host settles a landing only when the lift claim resolves,
  after it has already run the lifter's inputs past the hook, so any branch on the
  outcome disagrees with the client for that window and refuses the lifter's own
  pickup. Input-driven, host and client step identical phases and nothing rolls
  back.
- **Defaults: F on the keyboard, X on the pad.** The pad's loft moved to D-pad
  up/down and the ping to D-pad left to free it (pad scheme 2).
- **Ties are pure geometry in v1** (no Weight term until playtested), and **a
  pinning defender's stick stays off the ice** (the pin is a one-for-one trade).
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

(Phase 2 adds `TIE`: still held at the end of the hook with a non-carrier's shaft in
reach.)

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
- **Engage.** At the end of HOOK, with the button held, the lifter's blade is within
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
- **Wire.** `tied_by` (s8 slot index, −1 for none) on `SkaterNetworkState`. The
  defender's side is the reverse lookup.
  - The victim's client gates its provisional pickup on it.
  - Whether the client's one-timer prediction needs the gate too is an item to verify
    against the release-seed path.
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

### 3b. The pin
- **Onset (host-authoritative).**
  - The defender is committed (`hit_committed`) and touching an opponent's disc.
    Carrier or not, it doesn't matter.
  - The victim's disc is within `PIN_WALL_MARGIN` ≈ 0.25 m of the boards.
  - The defender's drive (velocity or move intent along the inward wall normal) is at
    least `PIN_DRIVE_MIN`.
  - The victim is not inside `PIN_IMMUNITY_S` 1.0 s of their last pin.
- **State on the victim.**
  - `pin_timer`, capped at `PIN_MAX_S` 2.0 s, and `pinned_by`.
  - The wall normal is derived from the victim's position
    (`GameRules.clamp_to_rink_inner`), so it never goes on the wire.
  - `pin_strength` = m_defender / (m_defender + m_victim), which is the Weight
    attribute through mass.
- **Effect on the victim.** It lives in `SkaterMovementRules`, so `integrate_forward`
  reproduces it:
  - their speed along the wall bleeds off in proportion to `pin_strength`;
  - their stride along the wall is scaled by (1 − `pin_strength`);
  - stance and check commit are off.

  A pinned carrier keeps the stick, the board-shield facing and the existing
  wall-squeeze release. A pinned non-carrier can still play the puck.
- **The defender.** Holding Ctrl and driving in maintains the pin; letting go of
  either ends it. The commit keeps their stick off the ice, and that is the bargain: a
  one-for-one trade that frees your partner to dig the puck out (decided).
- **Escape.**
  - The timer drains at `1 + escape_drive · (1 − pin_strength) · PIN_ESCAPE_RATE`.
    Driving along the wall, and especially reversing against the slide, gets out
    faster.
  - The pin also ends if the defender is knocked down, at the cap, or when the
    defender's drive falls below the minimum.
- **Netcode.**
  - `pin_timer` (u8, quantized) and `pinned_by` (s8) go on `SkaterNetworkState`.
  - Both are fed to `integrate_forward` on the render and on the rewind, following
    `stagger_timer` exactly. A pin applied as a raw velocity clamp would break the
    shared render clock (`Scripts/networking/CLAUDE.md`, the discontinuous-velocity
    rule).
  - The victim's own client snaps and re-derives the pin through reconcile, like
    stagger.
- **Bots.**
  - The checker holds the pin while a teammate's arrival time at the puck is less than
    the time left on the pin ("pin and support"). The chase election already sends
    the teammate to the puck.
  - A pinned bot works to escape.
- **Pose.** Optionally, `GaitPinLayer` (victim chest to the glass, defender driving a
  shoulder in). It is cosmetic only, and checked with `render-poses.sh`.

### 3c. Frozen puck
- **The rule.** `FrozenPuckRules` (pure) accumulates time while all of these hold:
  - the puck is loose, or carried by a pinned skater;
  - it is within `FROZEN_BOARD_MARGIN` of the boards and slower than `FROZEN_SPEED`;
  - a pinned skater's disc is within `FROZEN_REACH` of it.

  Moving more than `FROZEN_SLOP` from its anchor resets the count.
- **NHL.** At `FROZEN_PUCK_S` ≈ 2.0 s there is a whistle, with a new
  `FaceoffReason.FROZEN` at `GameRules.nearest_faceoff_dot(puck_xz)`.
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
| 2 | — | `tied_by` s8 | `send/receive_stick_tie_claim` |
| 3 | — | `pin_timer` u8, `pinned_by` s8 | — |

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
| `Scripts/domain/rules/board_pin_rules.gd` | pin onset, strength, escape drain |
| `Scripts/domain/rules/frozen_puck_rules.gd` | the frozen-puck accumulator |
| `Scripts/controllers/skater_stick_check.gd` | the per-skater phase and its timer |
| `Scripts/game/stick_tie_claim_resolver.gd` | the tie claim |
| `Scripts/game/defensive_contact_tracker.gd` | host-side tie maintenance and pin onset; owns the pairs outright |

## Docs that change when each phase lands

- `docs/gameplay-design.md`: the Physicality paragraph.
- `Scripts/game/CLAUDE.md`: the resolver list ("four claim signals").
- `Scripts/networking/CLAUDE.md`: "the four blade/hit claim RPCs".
- `Scripts/domain/ai/CLAUDE.md`: the defensive verbs. The physical verbs are a role's
  "extras".
- The tutorial step for the new button.
- The controls-tab labels.

## Open questions

None outstanding. The KBM default, tie strength and the pinning defender's stick
were settled before Phase 1 (see *Decisions banked*).

## Starting values

| name | value | note |
|---|---|---|
| `RISE_S` | 0.06 | blade up from the ice |
| `HOOK_MIN_S` / `HOOK_MAX_S` | 0.04 / 0.14 | window in which a hook can land |
| `DROP_S` | 0.05 | blade back down on release |
| `RECOVER_S` | 0.22 | the price of holding the stick up too long |
| `REARM_S` | 0.25 | before the next lift |
| `FORCED_LIFT_MIN_S` / `MAX_S` | 0.4 / 0.9 | victim's forced lift by hook quality |
| `TIE_MAX_S` / `TIE_COOLDOWN_S` | 1.5 / 0.75 | |
| `TIE_HOLD_RADIUS` | engage + blade travel over the interp window + IK slack | derive, don't pick |
| `PIN_WALL_MARGIN` | 0.25 m | |
| `PIN_MAX_S` / `PIN_IMMUNITY_S` | 2.0 / 1.0 | |
| `FROZEN_PUCK_S` | 2.0 | |
