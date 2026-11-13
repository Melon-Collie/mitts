# Net-front battles — the press, and retiring the cross-check

Status: **all five phases built** (the press, the bots' press and dig-in, the
press's poses and scrape, the cross-check retired, Phase 4's rework of who
pushes and who holds, which supersedes Phase 1's controls and table, and
Phase 5's hold on the boards, which retires the pin), playtest pending. Amends the physicality
paragraph of `docs/gameplay-design.md` and Phase B of
`docs/physicality-plan.md` (the cross-check). The stick half of the battle is
`docs/defensive-play-plan.md`'s tie; the crease itself (jams, stuffs, wraps)
is `docs/net-play-plan.md`. Each phase is its own PR and playtest.

## Decisions banked

- **The cross-check goes.** It is openly illegal, Mitts called no penalties when
  this was decided (`docs/penalties-plan.md` has since added them), and
  a burst shove is not how a net-front battle plays: it is a sustained
  contest of leverage. It stays until the press has been played, as the
  fallback, then retires (Phase 3).
- **A net-front battle is two layers, and they compose.** Stick on stick is
  the tie (unchanged). Body on body is the **press**: who gives ground when
  two bodies are pressed together. A defender ties the stick and presses the
  body at once; neither layer gates the other. The lean does not live inside
  the tie: a tied pair is often a stick's length apart, and a forward who frees
  his stick should not free his body with it.
- **The press uses buttons that exist.** Ctrl in contact drives, Space digs in
  (the stop's edges), Shift deepens the stance's base. F stays the sticks. No
  chord, no new action.
- **The press is the cross-check's model run continuously.** What the
  cross-check priced over one 0.1 s push (the pusher's stride on the man's mass,
  less what his edges and his own stride hold) is priced every tick a pair is
  pressed.
- **Decided with the user:** an uncommitted body drives at the passive share,
  braking is the anchor (Shift alone holds only across the blades), the anchor
  is sized for weight to decide at the margin, and a press moves a man no faster
  than its winner skates.
- **The bots learn the press in the phase that adds it** (the rule from
  `docs/defensive-play-plan.md`).

## Why — what a press does today

`tests/instruments/controllers/test_net_front_press.gd` stands two real
`SkaterController`s in contact at a standstill and ticks them in the live order
for two seconds: the attacker skates into the man, who faces up ice. Selected
rows (201 lb each unless noted; "gave" is how far the man was moved along the
push, metres):

| case | man | attacker | gave 1 s | gave 2 s | man's speed at 2 s |
|---|---|---|---|---|---|
| from behind | does nothing | skates in | 2.28 | 7.39 | 5.85 |
| from behind | does nothing | skates in, Ctrl | 1.11 | 4.19 | 3.77 |
| from behind | Shift | skates in, Ctrl | 1.11 | 4.19 | 3.77 |
| from the side | does nothing | skates in, Ctrl | 1.11 | 4.19 | 3.77 |
| from the side | Shift | skates in, Ctrl | 1.11 | 4.19 | 3.77 |
| from behind | skates back into him | skates in, Ctrl | -0.72 | -2.37 | -2.07 |
| from behind | skates back into him | skates in | 0.25 | 0.76 | 0.23 |
| from behind | Space | skates in, Ctrl | 0.06 | 0.12 | 0.04 |
| from the side | Space | skates in, Ctrl | 0.06 | 0.12 | 0.04 |
| from behind, 170 lb man, 235 lb attacker | Space | skates in | 0.89 | 3.08 | 2.34 |
| from behind | does nothing | cross-check | 0.75 | 1.22 | 0.29 |
| from behind | Space | cross-check | 0.06 | 0.06 | 0.00 |
| from the side | does nothing | cross-check | 0.03 | 0.03 | 0.00 |

No row staggers or floors anyone except the cross-check, whose stagger is 0.6 s.

### The contest is already Newtonian

Contact splits the overlap by inverse mass and shares closing momentum
(`SkaterCollisionRules`), so a pressed pair moves as one body. Each body's
movement step is a mass-independent acceleration — thrust 10.5 m/s², the stop
9 m/s² (`SkaterMovementRules.apply_movement`) — so the pair accelerates at

```
a_pair = (m_A·a_A + m_M·a_M) / (m_A + m_M)
```

which is two bodies pushing on each other: a force contest in which weight
counts linearly. Every row above follows from it: Ctrl's half stride against a
stop (5.25 against 9) stalls, an uncommitted stride (10.5) beats it by 1.5, and
235 lb at 10.5 against 170 lb at 9 nets 2.3 m/s². Nothing new is needed to make
weight matter. What is wrong is what goes into it.

### What goes into it is wrong four ways

- **Committing makes you a worse pusher.** Ctrl's stride penalty
  (`commit_stride_mult` 0.5) is the cost of skating loaded on a shoulder at
  speed, and it applies in contact too, so leaning into a man moves him half as
  far as skating into him.
- **The stance anchors nothing.** Shift scales the stride down (0.6) and the
  turning grip up, and the stop ignores posture, so getting low and wide makes
  you no harder to move.
- **Nothing resists a push across the blades.** A standing man shoved from the
  side slides exactly as far as one shoved from behind; above a walking pace
  the movement model takes the travel as where the blades point, and nothing in
  contact reads where they actually do.
- **The stop is near-absolute.** Space alone holds an equal man to 0.12 m in two
  seconds, from any side, upright or not — and with it, against a stopped man
  the cross-check moves him 6 cm.

And the cross-check buys less than skating in: 1.2 m from behind against a man
who does nothing, nothing from the side, nothing against a stop. Its one unique
effect is the stagger.

## Phase 1 — the press (built)

### As built

- **It lives in the movement step, not the resolver.** Each body's
  `SkaterController._apply_press` lays the pair's acceleration along the
  normal over what `_apply_movement` did along it, from the velocity the tick
  started with; both bodies lay the same one from the same replicated state, so
  the pair moves as one with no stored history. The resolver still separates the
  overlap and lands any check, so there is no regime switch: a press is any
  contact both bodies drive into, at any closing speed.
- **The partner is the nearest body within `PressRules.CONTACT_SLACK_M`.** A
  third body on the pair is not modelled. Knocked-down, ghosted and pinned
  bodies, planted shot states and contact-suspended phases press nothing.
- **What a partner reads of a body** is published on its `Skater`: the movement
  config and base thrust of its build (`press_cfg`, `press_thrust`), and its
  stance and stagger mirrored every tick (`in_stance`, `stagger_left`).
- **The stride's power limit and the glide's friction** go into the drive and the
  hold. Without them a man who does nothing reached 10 m/s in 2 s; with them,
  6 m/s.
- **`STANCE_ANCHOR` is 1.3, not 1.5.** The builds' mass multiplier is
  compressed (235 lb is 1.095) and heavier builds have less thrust and stop, so
  at 1.5 no build moved any anchored man. 1.3 keeps the ladder the starting
  value was chosen for.
- **The cross-check is untouched**; its terms did not move into `PressRules`,
  which has its own.
- **The bots' read** (`AIPressRead`) prices the press over `READ_S` (1 s) at
  `STEP_IN_M` (0.3 m) of the man. A planted man reads as standing on his edges:
  the domain does not name shot states. The loose-puck race stays the
  cross-check's, because committing would lift the bot's stick off the puck.

What it does on the live rig (`tests/instruments/controllers/test_net_front_press.gd`,
two seconds, 201 lb each unless noted):

| man | attacker | gave 2 s (m) |
|---|---|---|
| does nothing, from behind | skates in | 2.31 |
| does nothing, from behind | skates in, Ctrl | 7.46 |
| skates back into him | skates in, Ctrl | 5.66 |
| skates back into him | skates in | 0.00 |
| Space | skates in, Ctrl | 1.12 |
| Space + Shift | skates in, Ctrl | 0.00 |
| Space, from the side | skates in, Ctrl | 0.97 |
| does nothing, from the side | skates in, Ctrl | 0.62 |
| Shift, from the side | skates in, Ctrl | 0.00 |
| 170 lb, Space + Shift | 235 lb, Ctrl | 0.33 |
| 235 lb, Space + Shift | 170 lb, Ctrl | 0.00 |

### The model (as designed)

A pair is **pressed** while their discs overlap and the closing impulse would
leave each body's Δv under `BodyCheckRules.Config.min_impulse` (0.6 m/s, a bump
that inflicts nothing). Above it the contact is a check, as today; the press
never applies an impulse, so it never staggers.

For each body X, along the normal toward the other body:

```
drive_X = thrust_X × stride_X × stagger_thrust_X × max(0, intent_X · n_X)
hold_X  = braking:  stop_decel_X × anchor_X × stagger_grip_X
          else:     turn_accel_X × lateral_grip_X × posture_grip_X × stagger_grip_X × |sin θ_X|
```

- `stride_X` is 1 committed (the commit's stride penalty is lifted in contact:
  Ctrl is driving), `stance_stride_mult` in the stance, and
  `hit_passive_transfer_mult` (0.3) upright and uncommitted — skating into a
  man without putting your body into it slides off him, as an uncommitted bump
  does today.
- `θ_X` is the angle between the normal and X's blades (his facing). Across
  them the edges bite; along them they glide. This is the cross-check's
  `|sin θ|` term.
- Braking is the stop: the blades turned across, so it holds from any side.
  `anchor_X` is 1 upright and `PressRules.STANCE_ANCHOR` in the stance — the wider,
  lower base takes more edge before it slides. A shuffle is braking, so a
  screener stepping sideways to stay in the lane keeps his anchor.

The net push along the normal is `F = m_A·drive_A − m_M·drive_M`. The body
being pushed resists with up to `m·hold` and never more (edges hold, they do
not push back), so:

```
a_pair = sign(F) × max(0, |F| − m_pushed·hold_pushed) / (m_A + m_M)
```

along the normal, replacing both bodies' own movement along it for that tick;
across the normal each keeps his own. It is continuous in every input — a man
is moved slowly just past his hold, never snapped.

### What it does, at the starting values (equal weights)

| man | pushed by Ctrl from behind | from the side |
|---|---|---|
| does nothing | 5.25 m/s² (carried) | 0.75 (creeps) |
| Shift | 5.25 | holds |
| Space | 0.75 (creeps) | 0.75 |
| Space + Shift | holds (margin 3 m/s²) | holds |
| Space + Shift, at full stagger | 1.2 (moved) | 1.2 |

- 235 lb on an anchored 170 lb man creeps him (0.4 m/s²); 170 lb on an anchored
  235 lb man is held. Weight decides at the margin, not outright.
- A check that rocks or staggers a screener and a press after it moves him:
  the stagger cuts his grip. That is the legal answer the cross-check was
  standing in for.
- Skating into a man uncommitted carries him only if he does nothing.

### Networking

- **Everything it reads replicates already:** velocity, facing, `move_intent`,
  `brake_intent`, `stance_active` and `hit_committed` (intent byte bits 5 and
  6), the stagger timer. No wire change.
- **It runs in each body's movement step**, from both bodies' replicated
  state, so the host, the local prediction and reconcile replay compute the same
  pair; a client reads the partner where the host had him, live and in replay
  (`LocalController._find_press_partner`, `Scripts/networking/CLAUDE.md`). Every
  body's intent is wire-quantized first, so the host's raw stick and a client's
  decoded one drive the same push.
- **Prediction is no worse than contact today.** A local man pressed by a remote
  reads the remote's forward-predicted intent; a change of intent mispredicts for
  a round trip, exactly as a remote skating into him does now. The press adds no
  coupling the tie ruled out: no stick is dragged, and only the bodies the
  resolver already moves are moved.
- **No native twin.** The press runs in GDScript after the (native or not)
  movement kernel, which does not model contact.

### Rules

- `Scripts/domain/rules/press_rules.gd`: `drive`, `hold`, `pressing`,
  `pair_accel`, laid by `SkaterController._apply_press` (see *As built*).
- The contact resolver is unchanged: it still separates the overlap exactly, so
  bodies never interpenetrate.

### Bots

- **A screener digs in.** A bot screening its goalie (and any bot holding a spot
  at the net front) brakes in the stance when a defender is on it, and shuffles
  to stay on the shooter's line. This replaces `SkaterAgentCrossCheck`'s
  screener set.
- **A coverer presses.** The net-front defender commits into the man it covers
  to move him off the goalie's sightline, aimed across it, priced on the press:
  how far `pair_accel` moves him in the time before the shot. It ties his stick
  when a feed is coming, as today. Both at once is the taught play.
- **The loose-puck race** the cross-check also answered becomes a body race:
  a bot already on the man presses him off the line to the puck.
- Easy bots do none of it, as now. A bot holding a press follows the man through
  the same reaction lag as the tie (`TIE_LAG_BUDGET_S`).

### Tests

- `test_press_rules.gd` (properties): the hold never pushes; `pair_accel` is
  continuous and monotone in each mass, drive and hold; across the blades holds
  more than along them; braking holds from any side; the stance anchors more
  than upright; a stagger loses the press; symmetric in which body's resolver
  runs.
- The instrument's rows become a snapshot (`tests/unit/rules/snapshots/`) of the
  live-rig press table at the reference cases, so a tuning move shows its rows.
- A contact test: a press applies no impulse and staggers nobody; a check at
  the onset speed still does.

## Phase 2 — the press reads (built)

### As built

- **`GaitPressLayer`**, beside the pin layer and on its pattern, from
  replicated state on every machine: touching a body, the one committed and
  skating into him (`hit_committed`, his intent within 60° of the man) DRIVES —
  feet set in a lunge, the stick-side foot back (`press_drive_split_deg`), sat
  into it, the trunk leaned into the man (`press_drive_lean_deg` on top of the
  commit's own lean); the one braking slow ANCHORS — sat deeper and wider than
  his stance (`press_anchor_stance`, `press_anchor_width_m`) and leaned back into
  the push (`press_anchor_lean_deg`, enough to stand his stance's fold up). A
  man who does nothing gets no pose: he is carried. The blend is a spring
  (`EaseRules`). `test_gait_press_layer.gd` holds the roles and their direction.
- **The scrape:** a dug-in body counts as a stop for the skate scrape at the
  share his press pose is on, so he is silent held and scrapes as he is shoved,
  louder the faster (`SkaterSkatingCoordinator.scrape_stop_weight`). No new cue.
- **The tiles:** `press_drive`, `press_carried`, `press_side` in
  `tools/pose_capture_runner.gd`, which gained a `partner` key: a second skater
  in the away kit, in contact, holding his own input.

### As designed

- **The presser leans in.** Committed in contact, the trunk leans into the man
  and the leading shoulder drives (the commit's existing load-up), the legs
  stride against the ice.
- **The anchored man sits.** Braking in the stance in contact shows the stop's
  edges and a low seat, so the man being pressed can see he is held and the
  presser can see why he isn't moving.
- **A sound** for a press that starts moving a man (edges giving).
- Rendered through the pose capture (`press_drive`, `press_anchor`).

## Phase 3 — retire the cross-check

- Delete the cross-check: `CrossCheckRules` (its press terms already moved),
  `CrossCheckTracker`, `CrossCheckClaimResolver`, `CrossCheckRead`,
  `SkaterAgentCrossCheck`, the IK pose, the gait layer's shove, the tests, the
  wire's cross-check phase byte (a protocol bump).
- Ctrl + F goes back to being dead input (Ctrl already has the stick).
- `docs/physicality-plan.md` Phase B gains a retired note;
  `docs/gameplay-design.md` replaces the cross-check sentences with the press.

As built (v88, replay format 19): the screen's two reads the press still needs
(`hides_release`, `clears_screen`) moved out of `CrossCheckRead` into
`AIScreenRead` (`Scripts/domain/ai/screen_read.gd`) before it went. The pad's
aim stick no longer holds its aim while RB is down; with nothing to throw, a
released stick eases back to the carry rest as it does without RB.

Every machine reads a press partner at the tick's start: the host from what his
skater latched at the end of the last tick, so controller order never changes a
press; a client from its buffered sample at the input's stamp, in its live step
and its replay alike, counting him touching within the travel its timing
allows (`PressRules.touching`, `LocalController.PRESS_READ_TIMING_S`). A
carried man reaches 6 m/s, where a client a tick off with the bare slack lost
him on most ticks (`test_press_reads_one_instant.gd`).

## Phase 4 — in the battle or out of it (built)

Supersedes Phase 1's controls, its table and its open-question decisions 1–4.

Why: measured on the live rig the press was all or nothing. A man who did
nothing was carried 7.5 m in two seconds at close to skating pace; a man
holding Space + Shift could not be moved at all; a man who leaned back into
the push, the natural answer, was carried 5.7 m; and Shift alone did nothing
from behind. Nothing rewarded getting to the spot first.

### Decided with the user

- **Ctrl is the battle.** Both players hold it. Only an engaged body pushes
  with his whole stride or holds his ground; a body not holding it is moved.
- **Ctrl + skating into him pushes; Ctrl + Space holds.** Space without Ctrl is
  the ordinary brake and holds little.
- **Shift is nothing here.** Getting low is not an answer to being pushed.
- **Position matters more.**
- **A fresh Ctrl press on a man you are touching is a shove**, with a stagger.
- **Engaging costs the stick**, as the commit always has: a screener holding
  his spot cannot tip or receive until he lets go of Ctrl.

### Rules (`PressRules`)

- **The drive:** an engaged body's whole stride, an unengaged one's passive
  share (0.3), nothing braking. It is scaled by how squarely he faces the man
  (`SIDE_ON_SHARE`, 0.4 side-on or with his back to him, up to 1 chest-on), so
  the man who is square behind the other has the push; and it fades to nothing
  as the pair reaches a walking pace (`MAX_SPEED_M_S`, 1.5 m/s).
- **The hold:** an engaged body braking has set his edges (`SET_ANCHOR`), from
  any side. Set, they hold an equal man's drive; once the pair is sliding, or
  while he is staggered, they have broken loose and hold `LOOSE_SHARE` (0.6) of
  that, which an equal drive overcomes. So the man set first holds, a man
  caught sliding is moved until he pushes back to stall it, and nothing has to
  be remembered between ticks: it is static against sliding friction, read off
  the pair's own speed. An unengaged brake holds `PASSIVE_BRAKE_SHARE`.
- **The shove** is the timed check thrown into a man already leaned on
  (`CheckDriveRules.kick_dv`, `docs/hit-outcomes-plan.md` Phase 5): it kicks
  him back and staggers him, which breaks his set, on the drive's cooldown.
- The posture the stance names is read as unengaged; across-the-blades grip is
  gone from the press.

### What it does (live rig, 201 lb each unless noted, `test_net_front_press.gd`)

| the man | pushed chest-on from behind, 1 s | 2 s |
|---|---|---|
| not engaged, does nothing | 1.00 m | 2.36 m, at 1.4 m/s |
| not engaged, braking | 0.77 | 1.81 |
| not engaged, in the stance | 1.00 | 2.36 |
| not engaged, pushed side-on | 0.57 | 1.61 |
| engaged, pushing back with his back to him | 0.57 | 1.35 |
| engaged, pushing back chest to chest | 0.00 | 0.00 |
| engaged and set | 0.00 | 0.00 |
| engaged and set, shoved first | 0.51 | 0.96, staggered 0.55 s |
| 170 lb engaged and set, 235 lb pushing | 0.04 | 0.09 |
| 235 lb engaged and set, 170 lb pushing | 0.00 | 0.00 |

### Bots

- **A screener digs in with Ctrl and the brake**, when an engaged opponent is
  on him, and not while his stick is up for a tip, which Ctrl would take off
  the ice (`SkaterAgentPress._dig_in`).
- **A coverer prices the walking pace and the shove**
  (`AIPressRead.displacement_m`, `PressRules.displacement`): with his drive in
  hand the press opens with a shove, so the man is read staggered and his set
  broken; with it spent, a set man is not worth pressing.

### Pose

`GaitPressLayer` draws the dig-in only on an engaged body braking, sat deeper
than the commit's own crouch (`press_anchor_stance`).

### Networking

Nothing new on the wire: engagement is `hit_committed`, the brake and the
intent are the intent byte, and the pair's speed is both bodies' own. The
shove is the timed check's kick, already replicated. No protocol change beyond
v100.

### Tests

- `test_press_rules.gd`: only an engaged body sets his edges, from any side;
  loose edges hold less; the stance is an unengaged body; chest-on pushes
  hardest; the drive fades out at a walk.
- `test_press.gd` (live rig): the properties above, the stall chest to chest,
  weight at the margin, a shove breaking a set man loose.
- `tests/slow/controllers/test_press_table.gd`: the table, re-pinned.
- `test_bot_press.gd`: the dig-in's controls and when it keeps the stick; a
  set man pressed only with a shove to open it.

## Phase 5 — the boards (built)

Retires the pin on the stick button (`docs/physicality-plan.md` Phase A,
`docs/defensive-play-plan.md`'s pin): its tracker, its locked pair, its slide
caps, its pose and its two wire fields are gone (protocol v101).

### Decided with the user

- **The boards work the way the press does.** No button of their own: a man is
  pinned by an engaged body with leverage on his open-ice side.
- **He gets out by moving against the push.**
- **A held carrier keeps the puck** until a stick or a shove takes it.

### Rules (`BoardWallRules`)

- **The squeeze.** A press acts along the line between the bodies, so on its
  own a man pressed into the wall would skate off along it. Pressed into the
  boards (his edge within `SQUEEZE_MARGIN_M` of them, the push within 45° of
  the wall's normal), his speed along the wall is cut each tick by
  `SQUEEZE_GRIP` × the acceleration the pair's drives press him in with, on
  his own mass: the holder's drive less his own back into the holder. It is
  friction: it takes speed toward rest and never reverses it.
- **Why it is over 1** (1.1): he is gripped on two faces, the glass and the
  man. At 1 an equal man square on him exactly cancels his stride, and any
  slip off square lets him go; over about 1.2 an equal man pushing back on the
  diagonal, the only one a keyboard has, could never unload it.
- **What follows from the press's own rules.** Only an engaged holder drives
  with his whole stride, so only Ctrl holds a man. The drive is scaled by how
  squarely each faces the other, so the held man pushes back hardest turned
  to face the holder. A shove staggers the holder, whose drive falls with the
  stagger's thrust penalty, and the squeeze with it. A carrier's Ctrl is the
  brace and throws no drive, so a held carrier cannot shove.
- **The frozen puck** (`FrozenPuckRules.held_on_boards`,
  `GameManager._check_frozen_puck`): a slow puck at the boards, loose or on
  his stick, with a held skater on it for `FROZEN_S`.

### What it does (live rig, 1 s, the holder engaged and square, `test_press.gd`)

| the man on the boards | slid along the wall |
|---|---|
| equal, skating along it, not engaged | 0.02 m (4.1 m in open ice) |
| equal, the holder not engaged | over 3 m |
| equal, engaged, facing him, pushing back and along | 0.04 |
| the same, opened with a shove | 0.56, and 0.31 off the wall |
| 235 lb held by 170 lb, pushing back and along | 0.73 |
| 170 lb held by 235 lb, pushing back and along | 0.00 |
| 170 lb held by 235 lb, opened with a shove | 0.29 |

### Bots (`SkaterAgentBoardPlay`)

- **Hold:** leaned on a man at the wall who carries the puck or stands over
  it, from his open-ice side, where it is worth it (support that beats theirs
  to the puck, or our own end, never as the last man back): Ctrl and the
  stick toward him, which follows him along the wall.
- **Held:** Ctrl, back into the man and out along the wall in equal parts,
  letting the button up for a tick whenever the drive has re-armed so the next
  press is a shove.
- **Carrying at the wall with an engaged checker coming square:** out of his
  line along the boards if that beats him there, else the brace
  (`AIPinThreatRead`).

### Networking

Nothing on the wire. The squeeze reads what the press reads (both bodies'
mass, posture, intent, facing, stagger) and the rink's own geometry, in
`SkaterController._apply_press`, so both bodies, every machine and the
reconcile lay the same hold. The pin's `pin_role` and `pin_strength` leave the
skater block (v101).

### Tests

- `test_board_wall_rules.gd`: the backstop, the squeeze (only into the wall,
  only a net push, growing with it), the grip as friction, `held_on_boards`,
  the frozen count.
- `test_press.gd` (live rig): an engaged man holds an equal on the boards and
  not in open ice; an unengaged one holds nobody; a shove gets him off the
  wall; weight decides who is held.
- `test_bot_board_play.gd`: the hold and when it is worth it, the push back,
  the repeat shove, the carrier's answer.

## Docs that change when each phase lands

- `docs/gameplay-design.md` — the physicality paragraph (1, 3).
- `Scripts/ai/CLAUDE.md` — the collaborator table (1, 3).
- `Scripts/domain/ai/DECISIONS.md` — a row for the press read (1).
- `docs/physicality-plan.md` — Phase B retired (3).

## Where it lives

| piece | file |
|---|---|
| press math | `Scripts/domain/rules/press_rules.gd` |
| the pair's motion | `SkaterController._apply_press`, `_find_press_partner` (`LocalController`'s on a client), `Skater._latch_press_read` |
| bot press and dig-in | `Scripts/ai/skater_agent_press.gd`, `Scripts/domain/ai/press_read.gd`, `Scripts/domain/ai/screen_read.gd` |
| live-rig tests | `tests/harness/press_harness.gd`, `tests/unit/controllers/test_press.gd`, *slow* `tests/slow/controllers/test_press_table.gd` |
| measurement | `tests/instruments/controllers/test_net_front_press.gd` |

## Open questions (decided for Phase 1)

1. **Does an uncommitted skater drive at all?** Decided: at the passive share
   (0.3), so Ctrl is what moves a man and skating into a teammate or an opponent
   does not shove him along. The alternative, full stride for everyone, is
   simpler physics but makes Ctrl meaningless in contact.
2. **Is braking the anchor, or Shift alone?** Decided: braking. It is
   already the strongest hold, a shuffle keeps it, and "dig in" reads. Shift
   alone then holds only across the blades.
3. **How strong is the anchor?** Decided: weight decides at the margin
   (`STANCE_ANCHOR` 1.3, see *As built*).
4. **Does a press move a man faster than he could skate?** Decided: no. The pair
   shares one stride, capped at the winner's top speed and power-limited.

## Starting values

| constant | value | why |
|---|---|---|
| `PressRules.STANCE_ANCHOR` | 1.3 | the stance's base over the upright one for the stop's edges; an equal man held, weight deciding at the margin (1.5 as designed; see *As built*) |
| uncommitted drive share | 0.3 | `Skater.hit_passive_transfer_mult`, the same share an uncommitted bump transfers |
| press onset | `min_impulse` (0.6 m/s Δv) | below it a contact cannot stagger, so it is a press |
