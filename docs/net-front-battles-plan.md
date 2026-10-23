# Net-front battles — the press, and retiring the cross-check

Status: **all three phases built** (the press, the bots' press and dig-in, the
press's poses and scrape, the cross-check retired), playtest pending. Amends the physicality
paragraph of `docs/gameplay-design.md` and Phase B of
`docs/physicality-plan.md` (the cross-check). The stick half of the battle is
`docs/defensive-play-plan.md`'s tie; the crease itself (jams, stuffs, wraps)
is `docs/net-play-plan.md`. Each phase is its own PR and playtest.

## Decisions banked

- **The cross-check goes.** It is openly illegal, Mitts calls no penalties, and
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
