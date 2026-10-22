# Net-front battles — the press, and retiring the cross-check

Status: **Phase 0 (measurement) done; nothing built.** Amends the physicality
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
  pressed. `CrossCheckRules.edge_accel` and `drive_accel` are its first terms.
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

## Phase 1 — the press

### The model

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
  `anchor_X` is 1 upright and `PRESS_STANCE_ANCHOR` in the stance — the wider,
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
- **It runs inside the shared contact resolver**, from both bodies' replicated
  state, under the existing aggressor gate, so the host, the local prediction
  and reconcile replay compute the same pair (`Scripts/networking/CLAUDE.md`,
  body-check contact geometry). It is a pure function of that state, replay-safe.
- **Prediction is no worse than contact today.** A local man pressed by a remote
  reads the remote's forward-predicted intent; a change of intent mispredicts for
  a round trip, exactly as a remote skating into him does now. The press adds no
  coupling the tie ruled out: no stick is dragged, and only the bodies the
  resolver already moves are moved.
- **Check a native twin.** `SkaterCollisionRules` has none today; confirm before
  building that the native movement kernel does not duplicate contact.

### Rules

- New `Scripts/domain/rules/press_rules.gd`: `is_pressed`, `drive`, `hold`,
  `pair_accel`. `CrossCheckRules.edge_accel` and `drive_accel` move into it
  (the cross-check calls them from there until Phase 3).
- `SkaterCollisionRules.resolve` takes the press result for the pressed regime;
  the overlap is still separated exactly, so bodies never interpenetrate.

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

## Phase 2 — the press reads

- **The presser leans in.** Committed in contact, the trunk leans into the man
  and the leading shoulder drives (the commit's existing load-up), the legs
  stride against the ice.
- **The anchored man sits.** Braking in the stance in contact shows the stop's
  edges and a low seat, so the man being pressed can see he is held and the
  presser can see why he isn't moving.
- **A sound** for a press that starts moving a man (edges giving).
- Rendered through the pose capture (`press_drive`, `press_anchor`).

## Phase 3 — retire the cross-check

After Phase 1's playtest, and only if the press covers the net front:

- Delete the cross-check: `CrossCheckRules` (its press terms already moved),
  `CrossCheckTracker`, `CrossCheckClaimResolver`, `CrossCheckRead`,
  `SkaterAgentCrossCheck`, the IK pose, the gait layer's shove, the tests, the
  wire's cross-check phase byte (a protocol bump).
- Ctrl + F goes back to being dead input (Ctrl already has the stick).
- `docs/physicality-plan.md` Phase B gains a retired note;
  `docs/gameplay-design.md` replaces the cross-check sentences with the press.

## Docs that change when each phase lands

- `docs/gameplay-design.md` — the physicality paragraph (1, 3).
- `Scripts/ai/CLAUDE.md` — the collaborator table (1, 3).
- `Scripts/domain/ai/DECISIONS.md` — a row for the press read (1).
- `docs/physicality-plan.md` — Phase B retired (3).

## Where it lives

| piece | file |
|---|---|
| press math | new `Scripts/domain/rules/press_rules.gd` |
| contact regime | `Scripts/domain/rules/skater_collision_rules.gd`, `Skater._resolve_player_collisions` |
| bot press and dig-in | a collaborator under `Scripts/ai/` replacing `SkaterAgentCrossCheck` |
| measurement | `tests/instruments/controllers/test_net_front_press.gd` |

## Open questions

1. **Does an uncommitted skater drive at all?** Recommended: at the passive share
   (0.3), so Ctrl is what moves a man and skating into a teammate or an opponent
   does not shove him along. The alternative, full stride for everyone, is
   simpler physics but makes Ctrl meaningless in contact.
2. **Is braking the anchor, or Shift alone?** Recommended: braking. It is
   already the strongest hold, a shuffle keeps it, and "dig in" reads. Shift
   alone then holds only across the blades.
3. **How strong is the anchor?** `PRESS_STANCE_ANCHOR` 1.5 holds an equal man
   with a margin of 3 m/s² and lets 235 lb creep 170 lb. 2.0 (the stance's
   turning grip) makes an anchored man immovable by any build.
4. **Does a press move a man faster than he could skate?** It cannot today (the
   pair shares one stride); confirm that is the feel, rather than a defender
   being able to bulldoze a man to the corner.

## Starting values

| constant | value | why |
|---|---|---|
| `PRESS_STANCE_ANCHOR` | 1.5 | the stance's base over the upright one for the stop's edges; an equal man held with margin, weight deciding at the margin |
| uncommitted drive share | 0.3 | `Skater.hit_passive_transfer_mult`, the same share an uncommitted bump transfers |
| press onset | `min_impulse` (0.6 m/s Δv) | below it a contact cannot stagger, so it is a press |
