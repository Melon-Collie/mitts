# Physicality — the pin on the stick button, and the cross-check

Status: **all three phases built**, playtest pending. Amends
`docs/defensive-play-plan.md` (the pin revision, v74) and adds a new verb. Three
phases, each its own PR and playtest.

## Decisions banked

- **Two buttons, two families.** Ctrl is *impact*: the check, the brace, and now
  the cross-check. The stick button (F / pad X) is *holding on*: the lift, the
  tie, and now the pin. A pin is a tie done with the bodies (a hold, a read,
  both sticks out) and plays like one, not like a hit.
- **The pin moves to the stick button.** Onset needs the stick button held, not
  the commit. Holding the pin is holding the stick button.
- **The cross-check is a chord: Ctrl held, the stick button pressed** (RB held,
  X pressed). Ctrl alone stays the commit and the brace and never shoves by
  accident; F with Ctrl down was dead input, because the commit already has the
  stick. No tap-versus-hold, which would add latency.
- **The cross-check works anywhere on the ice**: net front, board scrambles,
  open ice.
- **Brace still blocks the pin** — *recommended, awaiting confirmation* (Open
  questions 1). A victim holding Ctrl can be hit but not pinned, as today.

## Why

**The pin fights its own button.** Measured on the real controllers and the
real `BoardPinTracker` (the scratch harness, below):

- **A pinner reverses on half a stride.** Holding the pin means holding Ctrl,
  and Ctrl is the commit posture (`commit_stride_mult` 0.5, `commit_grip_mult`
  0.6), so the race in a 0.5 m window is decided by acceleration, and he has
  half the victim's. A perfect pinner (zero lag, full input) holds a one-way
  slide to the 3 s cap but loses to a single reversal ~0.57 s after it. His
  1.4 m/s cap never comes into play. The pin revision's "a checker who reads the
  slide keeps up" does not hold.
- **The bots lose to a straight slide.** `_pinner_mirror` steers proportionally
  to the offset (`PIN_MIRROR_GAIN_M` 0.3) through an exponential read lag, so it
  trails a steady slide and never closes it: a victim who skates one way is free
  in 0.8–1.0 s at every weight pairing tested, with no juke.
- **A hard check can never become a pin.** Into the boards a committed check
  knocks down from 2.77 m/s closing, and a knockdown ends the pin, so "finish the
  check and pin him" can't happen. On a separate button the check lands and a
  held stick button pins after it (below that threshold — see *Not in this
  plan*).

**There is no force without closing speed.** Every body impulse is
`closing × transfer × m_a / (m_a + m_b)`. In front of the net nobody is closing:
two skaters stand and lean, the overlap is split by inverse mass, and two
striding into each other grind to a stalemate decided by thrust. That fight is
real but invisible, and nobody can start it on purpose. Net-front physicality
today is positioning plus the stick tie; moving a man out of position is missing.

## Phase A — the pin on the stick button

### Rules

- **Onset** (`BoardPinTracker._can_pin`): the pinner is in the stick-check `TIE`
  phase (held past the hook, `HOOK_MAX_S` 0.14 s) instead of `hit_committed`.
  Everything else stands: puckless, body contact, driving square into the boards,
  victim unbraced, not knocked down or ghosted, outside his immunity. A tap at the
  wall stays a lift; a hold becomes a pin.
- **Pin before tie.** At the wall with body contact, a stick in `TIE` latches the
  pin. A pinned skater cannot be tied. The tie keeps the slot and the crease, as
  the defensive-play plan intended.
- **Holding it** (`_holds`): the pinner keeps the stick button held
  (`stick_check_held`) instead of `hit_committed`. The other ends are unchanged
  (bodies part, victim off the wall, knockdown, ghost, 3 s cap, stoppage,
  frozen-puck release).
- **Ending it** puts the pinner on the shared stick-check cooldown
  (`STICK_CHECK_COOLDOWN_S`), so a broken pin can't turn straight into a tie. The
  victim keeps `PIN_IMMUNITY_S`.
- **A locked pair has no Ctrl.** The pinned side already loses the commit and
  the stance; the pinner loses Ctrl too (no commit posture, no cross-check). The
  pin is the body contest; nothing stacks on it.
- **The pinner skates upright**, at the ordinary stride and grip. That is the
  point of the move.

### The locked pair touches flat (found while building)

With the pinner upright he still lost every reversal, even read with no lag, and
the harder he drove into the boards the sooner the victim got out (a one-way
slide escaped in 0.83 s at full drive, and was held at none). Two discs touching
off-centre turn "press him into the wall" into "squeeze him along it": the
contact normal tilts with the along-wall offset, and the separation and the
impulse carry an along-wall share. A locked pair now touch along the boards'
normal (`BoardPinRules.locked_contact_axis`, passed to
`SkaterCollisionRules.resolve` by the live resolver and the reconcile replay),
two bodies pressed flat into the glass, and the pin's "bodies part" test
measures the gap along the same normal (`locked_gap`).

### The escape, held by a test

`PIN_ESCAPE_OFFSET_M` stays 0.5 m. Measured on the real controllers once the
pinner is upright and the contact is flat (neutral builds, the pinner driving
into the wall at 0.7 against full along-wall input):

| Pinner reads the reversal | Peak offset | Result |
|---|---|---|
| instantly | 0.27 m | held |
| 0.1 s late | 0.37 m | held |
| 0.2 s late (`PIN_LAG_BUDGET_S`) | 0.47 m | held |
| 0.3 s late | — | escaped |
| one-way slide, no juke | 0.09 m | held to the cap |

Weight moves it the right way: 260 lb pinning 170 lb holds a 0.4 s read; 170 lb
pinning 260 lb loses at 0.2 s.

Deriving the offset from the movement model, as first planned, would mean
picking how much of his stick the pinner spends driving into the wall, so it
would be a picked number in another form. The slow test holds the property
instead, and fails if a movement change breaks it:

- a reversal the pinner answers within `PIN_LAG_BUDGET_S` is **held**;
- one he answers `PIN_LAG_BUDGET_S` + a human reaction (0.2 s) late is **lost**;
- a one-way slide against a pinner who matches it is **held** to the cap,
  however hard he drives into the boards.

### Bots

- `SkaterAgentBoardPlay` holds `stick_check_held` for a pin instead of
  `hit_held`.
- **Reaching for a pin** (`_reach_for_pin`): a bot whose dispatch is driving a
  check into an unbraced man on the wall, within `PIN_REACH_S` of contact
  (`RISE_S` + `HOOK_MAX_S`, so the stick is past the hook when the bodies meet),
  swaps the check for the stick button where the hit will not knock him down
  and the pin is worth holding. A hit that knocks him down stays a hit.
- **The brace answers a stick held out** (`StickCheckRules.is_stick_busy` on the
  checker), not his commit, since that is now what pins.
- **The mirror matches velocity, not just offset.** Feed the man's along-wall
  velocity forward (read through the same `PIN_LAG_BUDGET_S`) and correct the
  offset on top. The pure proportional law has a steady-state trail by
  construction; that trail is the straight-slide escape.

### Tests

- `test_board_pin_tracker.gd`: onset and hold read the stick button; a tap at the
  wall pins nobody; Ctrl alone pins nobody; a pinned skater can't be tied; a pin
  ending puts the pinner on cooldown.
- **The escape race** (the property above), on real `SkaterController`s ticked
  in `Skater._physics_process` order. It costs a couple of seconds, so it goes in
  `tests/slow/game/`.
- **The race sweep becomes an instrument**, `tests/instruments/game/
  test_pin_escape_race.gd`: weight pairings × read lag × juke/no-juke, printing
  how and when each pin ended. It is the scratch harness from the investigation,
  cleaned up.
- `test_bot_board_play.gd`: a bot pinner holds a one-way slide to the cap.

## Phase B — the cross-check

### The model: a stride delivered through the arms

A cross-check is the shaft across the opponent's back in both hands, driven by
the legs. The force runs through the shover's skates, so it is bounded by what
his stride can push. That gives the impulse with one new constant, the push's
duration:

```
J        = m_s × thrust_s × PUSH_S                (the shover's stride, for PUSH_S)
Δv_free  = J / m_v                                (an unresisting victim)
resist   = PUSH_S × ( turn_accel × lateral_grip × posture_grip × stagger_grip × |sin θ|
                    + thrust_v × posture_stride × max(0, intent_v · −d) )
Δv       = max(0, Δv_free − resist)  along d
```

- `d` is the shove direction: the shover's aim (*Aimed*, below). `θ` is the angle
  between `d` and the victim's blades (his facing, `rotation.y` — the axis the
  movement model strides along).
- **Weight matters both ways, from mass alone.** Heavy on light shoves harder;
  light on heavy barely moves him.
- **Pushed along his blades he slides; across them his edges hold.** This is the
  edge the movement model already turns with (`turn_accel × lateral_grip`), and
  the loaded stance doubles it (`stance_grip_mult` 2.0), so getting low and
  turning your skates across the push is the anchor. A screener facing the point
  is shoved from behind along his blades, toward the point and out of the
  goalie's eyes, which is the real net-front battle.
- **Pushing back counts.** A victim driving into the shover subtracts his own
  stride over the same window. Leaning into him nearly cancels a shove, so the
  shove pays against a man who isn't set against it: a read, not a spam button.
- **No recoil on the shover.** His skates are what pushed; he is the one set.
- **The boards need no special case.** A victim shoved into the wall takes the
  same Δv, so the same stagger; the rink clamp stops the travel.

At `PUSH_S` 0.1 and league thrust (10.5 m/s²), a neutral shove along the blades
lands **1.05 m/s**: about 0.6 s of stagger and 1–1.5 m of slide if he doesn't fight
it. Heavy on light (1.28 / 0.79) is 1.70, light on heavy 0.65. Across the blades
upright the edges take 0.9 m/s of it; in the stance 1.8.

### Effects

- **Stagger, never a knockdown on its own.** Δv goes through
  `BodyCheckRules.stagger_seconds_from_impulse`, the same ladder as a check.
  Across the legal build range it stays under `knockdown_impulse` (1.8) by
  construction, and a test holds that against the live constants rather than
  clamping.
- **No puck strip.** A shove doesn't fire `body_checked_player`. A shoved
  carrier keeps the puck and loses his footing (the stagger's thrust and grip);
  the lift and the pin are the strips.
- **Stacking with a check:** a press on the way into a closing hit lands both.
  The velocities add; the stagger takes the max (extend, never shorten), so the
  hit is not doubled.
- **Not a hit stat.** `HitRules` keeps crediting checks only.

### Input and phases

`CrossCheckRules` is a pure phase machine like `StickCheckRules`, stepped from the
shover's own chord, so host and predicting client agree and nothing rolls
back:

| Phase | Entered | Duration | Stick |
|---|---|---|---|
| `THROW` | stick-button press with Ctrl held, eligible | `LOAD_S` 0.12 drawn in, then `PUSH_S` 0.10 out | off the ice; **only the push, past the load, can land** |
| `RECOVER` | end of THROW | `RECOVER_S` 0.20 | off the ice |
| `REARM` | end of RECOVER | `REARM_S` 0.40 | normal (or the commit's, if still held) |

- **Eligible:** puckless (a carrier's Ctrl is the brace, as today), not knocked
  down, not ghosted, not in a pin, off the rearm. A chord while ineligible is
  just the commit; the stick-button press with Ctrl down never starts a lift.
- **A whiff is real.** The press always throws; with nobody in reach the stick
  is out for `EXTEND + RECOVER` for nothing.
- **A shove breaks a tie the shover is in.** Both hands are on the shaft. It ends
  like any tie end, with both players on the stick-check cooldown.
- **Reach:** the victim's body meets the shaft: his body edge within `REACH_M`
  (0.55 m, arm extension) of the shover's along the aim, and across it no
  further than the hands' half-span plus his radius. One landing per press, on
  the nearest eligible opponent. Goalies are never targets.

### Netcode

Read `Scripts/networking/CLAUDE.md` first; this follows the stick lift's shape.

- **The phase is input-driven and replicated.** `cross_check_phase` joins
  `SkaterNetworkState`, packed with its elapsed ticks in one u8 like
  `stick_check_phase` (remotes need it for the pose, the resolver to check
  `EXTEND` at the rewound instant). Protocol bump.
- **Landing is the host's call.** It uses present-time detection for shovers the
  host simulates (bots, the host player) and a new `CrossCheckClaimResolver` for
  remote clients. It follows the whole claim contract in `Scripts/game/
  CLAUDE.md`: `claim_is_fresh`, `ClaimantView`, the bounded `interp_delay_ms`,
  shover at self-view time and victim at remote-view time, through
  `DeferredClaimQueue`, idempotent (one landing per press, keyed on the press
  stamp).
- **The victim's resistance is read at host present**, on the body the host owns.
  A client victim gets the Δv and the stagger through the snapshot, snapped and
  replayed like any stagger.
- **The shover predicts only cosmetics.** No recoil means nothing of his body to
  reconcile. His screen gets a provisional knockback pulse on the victim
  (`RemoteController.start_knockback_lead`, Lever B) so the shove reads at once.
- New RPC → `NetworkManager` (define) → signal → `GameManager._wire_network_
  signals()`.

### Pose and feedback

- **Pose the hands, not the blade** (`Scripts/controllers/CLAUDE.md`): both hands
  forward at chest height, shaft level, punched out over `EXTEND` and drawn back
  over `RECOVER`. The legs get a short drive: a `GaitLayer` under the check
  commit, which wins if Ctrl is still held.
- **Render it** with a `tools/pose_capture.gd` entry (wind and extension) and
  `render-poses.sh`; a held stick that looks wrong passes every assertion.
- **Impact feedback** reuses `SkaterVFX`'s throttled burst and thud, scaled by Δv.
  A new cue, if wanted, goes through `tools/normalize_sfx.py` and
  `SoundManager._MIX_DB`.

### Tests

- `test_cross_check_rules.gd`: the phase table; eligibility; reach and cone; the
  Δv model's properties (monotone in shover mass and inverse victim mass; along
  the blades beats across; the stance resists more than upright; pushing back
  resists; never negative).
- **No legal build pair knocks down on a standstill shove**, against the live
  `PlayerAttributes` range and `knockdown_impulse`.
- A shove landed on two real skaters moves the victim and staggers him, and
  doesn't strip a carrier; a whiff costs the stick for `EXTEND + RECOVER`.
- `CrossCheckClaimResolver`: rejects a claimant not in `EXTEND` at the rewound
  instant, out of reach or cone, against a teammate, ghost or goalie;
  `test_claim_resolver_contract.gd` covers it.
- `test_no_god_class_growth.gd`: `skater_controller.gd` is grandfathered, so the
  phase machine and its glue live in a collaborator, not the controller.

### As built (v78)

- **The chord needs no new input.** It is `hit_held` and `stick_check_pressed`
  in one input, both already on the record, so the input stays 24 B. Bots press
  it the same way.
- **The pad holds its aim while Hit (RB) is down.** X takes the right thumb off the
  aim stick, and a released stick otherwise eases the cursor back to its rest
  in about 0.1 s; with Hit held the stick is off the ice, so there is nothing to
  rest for (`LocalInputGatherer._update_pad_cursor`, after RT's hold).
- **Facings are vectors.** `in_reach` and `victim_dv` take `Skater.get_facing()`
  (and the snapshot's `facing`), not a yaw.
- **The feedback broadcast carries the victim, the Δv and the direction**, not
  the shover. Its hardness is the stagger ladder's 0..1 (`BodyCheckRules
  .intensity` of the Δv): the check's burst (`SkaterVFX.fire_impact_burst`), the
  check's thud at the quiet end of its range (`SkaterVFX.shove_volume_db`), and
  the knockback lead (`RemoteController.start_knockback_lead` now takes that
  0..1 rather than a check force). A shove the victim held lands none of it.
- **The pose squares the chest.** The upper body twists after the blade, which
  for a shaft across the chest swung it round to point ahead; while the pose is
  on, the twist target eases to square (`CrossCheckRules.pose_weight`, shared by
  the hand pose and the twist). The grip widens to 0.40 of the stick so the
  hands straddle the chest. Rendered as `cross_check_mid` / `cross_check_full`
  in `tools/pose_capture_runner.gd`.
- **The leg drive** (follow-up) rides `GaitCheckLayer`, the layer that already
  delivers a check with the legs: while the arms are out the stride plants, the
  base widens and the trunk leans into the push, on the check drive's own
  tunables. The trunk's inertia filter mutes the lean over a push this short
  (about 2° six ticks in), so it reads as a push, not a lunge.
- **The replay event** (follow-up): the host records a `cross_check` event (the
  Δv and direction) and `ReplayEventReplayer` plays its burst and thud at the same
  hardness as live (`SkaterVFX.shove_intensity`). Unknown kinds were already
  skipped, so the file format is unchanged.

### Aimed (decided after Phase C)

The cross-check goes where it is aimed, so a defender beside a screener can push
him sideways off the goalie's eyes rather than only straight away.

- **The shaft pushes along its own normal.** It is a bar square across the
  chest, so it pushes square out from the chest wherever on it the man sits,
  not along the line between the two centres. The chest turns to the cursor on
  the press, as far as it twists off the hips (`upper_body_max_twist_deg`, 67°):
  `CrossCheckRules.aim_dir`. That aim is both the push direction and the axis of
  the reach.
- **The reach is the bar's footprint**, not a cone: `REACH_M` deep along the aim,
  and across it the shaft between the hands (`HALF_SPAN_M`, from the pose's own
  `GRIP_FRACTION` on a league stick) plus his radius.
- **The aim is latched on the press** (`SkaterCrossCheck.aim`) and held for the
  throw, so where the cursor goes after doesn't steer it. Host and predicting
  client latch it off the same input.
- **No wire change.** The host lands every shove from its own latched aim, and
  the claim rewind reads it off the host-only snapshot field
  (`SkaterNetworkState.cross_check_aim`). Remotes see the aim as the chest's
  turn, which already rides the wire in the upper-body rotation; the leg
  drive's lean follows the chest.
- **Bots aim.** A coverer tries the push square across the goalie's sightline
  (`AICrossCheckRead.off_sightline_dir`) and turned 30° and 60° either side,
  because a push along a man's blades moves him furthest and one across them
  least. He presses the first aim that clears the screen. On a loose puck he
  tries away from it the same way. The press carries the aim on the cursor, as
  a human's does. A screener's set reads whether a defender could reach him at
  any aim the defender can turn to.

## Phase C — bots cross-check

Grounded per `Scripts/domain/ai/CLAUDE.md`; the checklist is
`Scripts/domain/ai/DECISIONS.md` §8.

- **The predictor is the resolver's own function.** A bot prices a shove through
  `CrossCheckRules.victim_dv`, the way `AIBodyCheck` shares
  `SkaterCollisionRules.victim_kick`, so a model change moves both in one edit.
- **Net front, defending (MARK on the screener):** shove when moving the man
  buys the goalie back what he costs: the sight cap (`GoalieScreenDepth`) and
  the tip line (`GoalieTipDepth`) re-priced with him displaced by the predicted
  slide, against the cost of the stick off the ice for `EXTEND + RECOVER` while a
  pass to him is live.
- **Net front, attacking:** with a defender in reach behind him, a bot screener
  sets against the shove: blades across it, or pushing back, whichever his
  facing allows. It's the same `resist` term read the other way.
- **Board scrambles:** shove the man between you and a loose puck when the
  predicted slide wins the race to it (`_team_arrival_s`).
- **Tier knob:** `check_aggression` gates it, as it gates the check and the pin.
  Easy never shoves.

### As built

- `AICrossCheckRead` (domain) and `SkaterAgentCrossCheck` (the last post-dispatch
  pass, after the stick lift, board play and shot block, so a stick or a body
  they took throws nothing). Bots press the chord only from an idle phase, Ctrl
  for that one tick, and let go after it.
- **How far a shove moves him** is the drift over the read-and-redirect delay
  (`AICarrySpace.EVADE_REACTION_S`) plus the stop his own stride makes against
  it, at the thrust the shove's stagger leaves him. A neutral shove along the
  blades moves a man about 0.23 m, so a net-front shove only pays against a
  screen near the edge of the goalie's sightline, or a man turned so the push
  runs along his blades.
- **The race counts the stagger.** The arrival clock sheds a sideways kick in a
  few hundredths of a second; what turns a race is the stride the stagger
  leaves him, so his post-shove arrival runs on `staggered_thrust`.
- **No tip term.** The goalie only counts a net-front stick as a tip threat when
  no defender can get to it, so a man our coverer is already on is not one; the
  screen is the cost a shove buys back.
- **The screener's set rides `protects_the_puck`** (answering a physical threat
  to what we hold), not `check_aggression`.

## Wire summary

| Phase | Field | Protocol |
|---|---|---|
| A | none: onset and hold read inputs on the host; `pin_role` unchanged | none: no wire, RPC or range change (`build_info.gd`'s rules); mixed builds are refused by the Steam BuildID check |
| B | `cross_check_phase` (u8: phase + elapsed ticks); the claim RPC and the landed broadcast | v78 (main took v77 for stick settling); replay format 17 |
| C | none | — |

## Where the code goes

| What | Where |
|---|---|
| Pin onset and hold on the stick button | `Scripts/game/board_pin_tracker.gd` |
| Locked pair has no Ctrl; pinner upright | `SkaterController._apply_movement` |
| Flat contact, locked gap | `Scripts/domain/rules/board_pin_rules.gd`, `skater_collision_rules.gd`; `Skater._resolve_player_collisions`, `LocalController`'s replay |
| The escape race | `tests/harness/pin_race_harness.gd` |
| Bot pin button, velocity-matched mirror | `Scripts/ai/skater_agent_board_play.gd` |
| Cross-check phases, reach, Δv model | new `Scripts/domain/rules/cross_check_rules.gd` |
| Phase stepping and pose seam | a new `SkaterController` collaborator |
| Host present-time landing | new `Scripts/game/cross_check_tracker.gd` |
| Client claims | new `Scripts/game/cross_check_claim_resolver.gd` |
| Wire | `SkaterNetworkState`, `WorldStateCodec`, `build_info.gd` |
| Bot decisions | MARK / net-front roles + a post-dispatch pass beside `apply_board_play` |

## Docs that change when each phase lands

- `docs/gameplay-design.md`: the physicality and boards paragraphs (A, B).
- `docs/defensive-play-plan.md`: *Decisions banked* and the pin revision point
  here (A).
- `Scripts/ai/CLAUDE.md` (the defensive verbs) and `Scripts/domain/ai/
  DECISIONS.md` (rows for the pin button, the cross-check) (A, C).
- The tutorial: the pin moves from the body-check step to the stick-lift step,
  the cross-check joins the body-check step; `locale/translations.csv` rows (A, B).

## Follow-ups from the same investigation (built)

- **Board hits count weight.** `BoardPinRules.backstop_hit_strength` scores a hit
  into the wall as the attacker's whole delivered impulse on the victim's mass:
  `closing × transfer × m_a / m_v` (the wall takes the recoil, the victim takes
  the attacker's impulse). At equal mass it is the old number.
- **Knockdown reads the body's own Δv, on the boards too** (decided with the
  user). The stagger and the puck strip read the wall-backed strength above; the
  knockdown reads only how far his body was driven, because the wall stops the
  moving. `Skater.body_check_received` now carries both (the impulse for the
  knockdown and the recoil, `stagger_strength` for the stagger). A committed
  check into the boards knocks down from the open-ice bar (about 5.5 m/s closing
  at equal mass, not 2.77), so a hard check rattles and strips him and F can
  pin him after. The bots' pin reach compares the collision's own
  `victim_kick` with the knockdown line accordingly.
- **The uncommitted head-on** knocks down only with both near top speed
  (about 18.5 m/s closing at equal mass): that is the physics, and the comment
  on `hit_passive_transfer_mult` now says so rather than "never".

## Open questions

1. **Brace still blocks the pin?** Recommended yes: Ctrl stays the answer to body
   contact. The alternative leaves the escape race as the only answer.
2. **`PUSH_S` and the edge term** are first guesses. If the edges make a
   sideways shove worthless, the playtest says so; the knob is `PUSH_S`, not a
   curve.
3. ~~**Should a cross-check aim?**~~ Yes (decided with the user): see *Aimed*.

## Starting values

| Constant | Value | Why |
|---|---|---|
| `CrossCheckRules.LOAD_S` | 0.12 s | the shaft drawn in to the chest before the push: the tell |
| `CrossCheckRules.PUSH_S` | 0.10 s | a neutral shove lands in the stagger band and no build pair reaches a knockdown |
| `RECOVER_S` | 0.20 s | the stick back down; the cost of a whiff |
| `REARM_S` | 0.40 s | ~0.8 s press to press |
| `REACH_M` | 0.55 m | arm extension, body edge to body edge |
| `GRIP_FRACTION` | 0.40 | the pose's bottom hand down the shaft; its half-span (0.26 m on a league stick) is the shaft's reach across |
| `PIN_ESCAPE_OFFSET_M` | 0.5 m (unchanged) | held by `tests/slow/game/test_pin_escape_race.gd` |
