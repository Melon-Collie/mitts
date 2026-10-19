# Physicality — the pin on the stick button, and the cross-check

Status: **design, not built.** Amends `docs/defensive-play-plan.md` (the pin
revision, v74) and adds a new verb. Three phases, each its own PR, protocol bump
and playtest.

## Decisions banked

- **Two buttons, two families.** Ctrl is *impact*: the check, the brace, and now
  the cross-check. The stick button (F / pad X) is *holding on*: the lift, the
  tie, and now the pin. A pin is a tie done with the bodies (a hold, a read,
  both sticks out) and plays like one, not like a hit.
- **The pin moves to the stick button.** Onset needs the stick button held, not
  the commit. Holding the pin is holding the stick button.
- **The cross-check is a Ctrl press.** It fires on the press edge; keep holding
  and it becomes the ordinary commit. No tap-versus-hold, which would add latency.
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

### The escape, re-derived

`PIN_ESCAPE_OFFSET_M` stops being a picked number. It becomes the offset a
reversal opens over `PIN_LAG_BUDGET_S` when the pinner answers it at the
ordinary stride, computed from `SkaterMovementRules`' league config (reverse
skid, the free push under `GRIP_MIN_SPEED`, the drive above it) and the two slide
caps. A test fails if the movement model moves and the offset doesn't. The
design property it must satisfy, asserted on the real controllers:

- a reversal the pinner answers within `PIN_LAG_BUDGET_S` is **held**;
- one he answers `PIN_LAG_BUDGET_S` + a human reaction (0.2 s) late is **lost**;
- a one-way slide against a pinner who matches it is **held** to the cap.

### Bots

- `SkaterAgentBoardPlay` holds `stick_check_held` for a pin instead of
  `hit_held`. `_answer_pin_threat` (the brace) is unchanged.
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

- `d` is the shove direction: the centre axis, shover → victim. `θ` is the angle
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
shover's own Ctrl press, so host and predicting client agree and nothing rolls
back:

| Phase | Entered | Duration | Stick |
|---|---|---|---|
| `EXTEND` | Ctrl press edge, eligible | `PUSH_S` 0.10 | off the ice; **the only phase that can land** |
| `RECOVER` | end of EXTEND | `RECOVER_S` 0.20 | off the ice |
| `REARM` | end of RECOVER | `REARM_S` 0.40 | normal (or the commit's, if still held) |

- **Eligible:** puckless (a carrier's Ctrl is the brace, as today), not knocked
  down, not ghosted, not in a pin, off the rearm. A press while ineligible is
  just the commit.
- **A whiff is real.** The press always throws; with nobody in reach the stick
  is out for `EXTEND + RECOVER` for nothing.
- **A shove breaks a tie the shover is in.** Both hands are on the shaft. It ends
  like any tie end, with both players on the stick-check cooldown.
- **Reach:** the victim's body edge within `REACH_M` (0.55 m, arm extension) of
  the shover's, inside `±CONE_DEG` (50°) of his facing. One landing per press,
  on the nearest eligible opponent. Goalies are never targets.

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

## Wire summary

| Phase | Field | Protocol |
|---|---|---|
| A | none: onset and hold read inputs on the host; `pin_role` unchanged | bump anyway, so mixed builds don't share a lobby |
| B | `cross_check_phase` (u8: phase + elapsed ticks); cross-check claim RPC | bump |
| C | none | — |

## Where the code goes

| What | Where |
|---|---|
| Pin onset and hold on the stick button | `Scripts/game/board_pin_tracker.gd` |
| Locked pair has no Ctrl; pinner upright | `SkaterController._apply_movement` |
| Derived escape offset | `Scripts/domain/rules/board_pin_rules.gd` |
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

## Not in this plan

From the same investigation, separate decisions:

- **Board hits are mass-blind.** `BoardPinRules.backstop_hit_strength` scores a
  hit into the wall as `closing × transfer`, so every weight pairing lands the
  same. The grounded form is `closing × transfer × m_a / m_v` (the wall takes
  the recoil, the victim takes the attacker's impulse); at equal mass it is
  today's number.
- **The board knockdown bar is low** (2.77 m/s closing, unbraced), which caps
  how hard a check can be and still turn into a pin.
- **An uncommitted head-on at full speed** (20 m/s closing) passes the knockdown
  line, against the "never knocks down" comment on `hit_passive_transfer_mult`.

## Open questions

1. **Brace still blocks the pin?** Recommended yes: Ctrl stays the answer to body
   contact. The alternative leaves the escape race as the only answer.
2. **`PUSH_S` and the edge term** are first guesses. If the edges make a
   sideways shove worthless, the playtest says so; the knob is `PUSH_S`, not a
   curve.
3. **Should a cross-check aim** (lean the direction toward the cursor, to push a
   man sideways out of a lane) or always go straight down the centre axis? v1 is
   the centre axis.

## Starting values

| Constant | Value | Why |
|---|---|---|
| `CrossCheckRules.PUSH_S` | 0.10 s | a neutral shove lands in the stagger band and no build pair reaches a knockdown |
| `RECOVER_S` | 0.20 s | the stick back down; the cost of a whiff |
| `REARM_S` | 0.40 s | ~0.7 s press to press |
| `REACH_M` | 0.55 m | arm extension, body edge to body edge |
| `CONE_DEG` | 50° | in front of the chest, where the shaft is |
| `PIN_ESCAPE_OFFSET_M` | derived | Phase A |
