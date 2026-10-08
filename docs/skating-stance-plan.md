# Skating stance — Shift becomes agility, sprint and stamina go

Status: PROPOSED — design agreed in chat 2026-10-08, nothing implemented.
Treat this as the agreed design; ask before deviating from it.

One-line summary: **Space is only the hockey stop. Shift is a low, loaded
stance that buys turning grip with speed. Sprint and stamina are deleted, and
top speed rises to where sprint used to take you. The check commit and the
stagger lose their stamina costs and pay in grip instead.**

## 1. Why

**Sprint is mostly vestigial since the skating rework.** Its designed cost,
`sprint_turn_multiplier`, scales the *facing* drag in
`SkaterPoseCoordinator.apply_facing` — how fast the body yaws toward the
cursor. The path a skater actually travels turns in
`SkaterMovementRules.apply_movement` at radius v²/(turn_accel·grip), which
sprint never touches except by being faster. What is left is "hold Shift for
+14% top speed until the pool empties", and the momentum model already makes
speed something you build and manage. Measured on the current numbers:

| Run | Time |
|---|---|
| 0 → 9 m/s cruise cap, no sprint | ~2.0 s |
| 0 → ~10.3 m/s sprint cap, sprinting | ~2.15 s, against a ~2.2 s pool off-puck and ~1.4 s carrying |
| 9 → ~10.3 m/s, sprinting | ~0.5 s |
| 0 → 10.3 m/s, no sprint thrust bump | ~2.75 s |

So from a standstill, sprint top speed is reached just as the pool runs out,
and never with the puck.

**The brake turn is ambiguous by construction.** WASD names fixed screen
directions, but `tight_turn_weight` decides between turning and stopping from
the angle between the stick and the current travel. Heading up the screen with
Space held: Space+D tight-turns but fades into a stop once within 30° of
right, so the turn ends by braking unless you release Space in that window;
Space+W+D gets ~15° of turn before the stop blend starts; Space+S+D is a pure
stop. The end of a turn (Space held, stick along travel) is the same input as
the most basic stop (holding W going up and hitting Space), so no rule on one
tick of input can tell them apart. Moving the cut to a button that never
brakes removes the ambiguity without adding state.

**Nothing makes a skater elusive.** Edge work (the brake turn) bleeds speed
and reverses direction; there is no way to be shiftier at the cost of
something.

**Rejected alternatives**, so they are not re-proposed:

- *A tap edge-push / dash on Shift.* An earlier 8-way dash on Shift was
  removed: it did not read as hockey, and it forced itself into direction
  changes. An edge push is the same thing with a hockey coat of paint.
- *Latching the Space turn* (Space pressed with the stick to the side latches
  "turn" until released, so the turn ends in a glide). It works, but needs a
  replicated latch bit, a tiebreak for a stick dead behind, and still leaves
  the cut and the stance as two overlapping grip mechanics.

## 2. The design

### 2.1 Space is the hockey stop, and only that

With the brake held, every stick direction is a stop: `stop_decel`, no turn.
`tight_turn_multiplier`, `tight_turn_decel`, `tight_turn_align_angle`,
`TIGHT_TURN_TAPER` and `tight_turn_weight` are deleted. The stick still
matters to the *gait*: it picks which side the stop is skated to, as now.

### 2.2 Shift is the loaded stance

While Shift is held (and no check is committed — §2.5), the skater drops into a
low stance. Three things change, all in `apply_movement`:

1. **Grip goes up.** Turn authority is `turn_accel · lateral_grip ·
   stance_grip_mult`. The turn still ends at the stick direction (the per-tick
   turn is already clamped to `steer_abs`), so a cut finishes in a glide,
   never a stop.
2. **Using the extra grip costs speed, in proportion.** Let `a_used` be the
   centripetal acceleration actually applied this tick (`turn_applied / dt ·
   speed`) and `a_0 = turn_accel · lateral_grip` the normal-grip capacity. The
   stance bleeds `stance_scrape · max(a_used − a_0, 0)` m/s² — the skid of an
   edge dug harder than a clean carve. Turning inside normal grip stays free,
   so crossovers in the stance still carry speed; a gentle weave costs
   nothing; a full-lock cut costs the most. As the skater lines up with the
   stick, `a_used` falls and the bleed vanishes on its own.
3. **Straight-line drive goes down.** Choppy strides: the along-travel stride
   is scaled by `stance_stride_mult`, and the stride stops adding at
   `max_speed · stance_max_speed_mult`. Over-cap speed is preserved, as it is
   everywhere in the model (the stride stops adding, nothing clamps down), so
   dropping into the stance at full speed and cutting carries no penalty for
   *entering* it. Below `GRIP_MIN_SPEED` the free push sideways is scaled by
   `stance_shuffle_mult` (net-front shuffles, a defender mirroring).

Releasing Shift to stand up and stride is therefore a change of pace: shake in
the stance, come out of it to accelerate. Letting go is part of the skill.

Heading up the screen, Shift held:

| Keys | Result |
|---|---|
| A | hard left cut, out of it gliding left |
| W+A | sharp 45° cut left, then glide |
| S+A | 135° cutback left with a skid — the escape |
| S | skid to a stop, then push back down (as in normal steering) |
| Space, any keys | hockey stop |

**Calibration anchor.** `stance_scrape` is fixed so that a full-lock stance cut
at top speed bleeds what today's tight turn does: with `stance_grip_mult` 2.0,
the excess at full lock is `a_0` (9 m/s²), so `stance_scrape = 3.0 / 9.0 ≈
0.33` reproduces `tight_turn_decel`'s 3 m/s². The current tight turn therefore
survives as the extreme of the stance, not as a separate mechanic.

### 2.3 Sprint is deleted; top speed rises to the sprint ceiling

Each build's `max_speed` becomes what its sprint ceiling was:
`_base_max_speed · speed_mult() · sprint_ceiling_mult()` (≈ 9.6–10.5 m/s across
builds, the 20–25 mph burst band the sprint ceiling is grounded to). The
burner/plodder spread and the skate-profile gear lean survive unchanged in
shape. Thrust is left alone to start, so top speed takes ~2.75 s to build from
a standstill; revisit only if playtesting says so.

`sprint_carry_penalty_bypass` goes with sprint, so a carrier always pays
`carry_speed_mult()`. A chaser now gains on a carrier at top speed (≈ 10.26 vs
≈ 9.83 m/s for a neutral build). That is correct hockey, but it removes "a fast
carrier can separate" — see §6.

### 2.4 Stamina is deleted

`StaminaRules`, the pool, the exhaustion lockout, the stamina ring and the
Weight-flavoured metabolism tables all go. If the stance turns out to be
held always and needs a budget, that is a later decision (§6), not a reason
to keep the pool now.

### 2.5 Check commit pays in skating, not stamina

Ctrl still commits: full transfer, stick off the ice, no poke / reception /
pickup. The stamina drain is replaced by:

- **Grip down** — `commit_grip_mult` (< 1). Loaded on a shoulder, the skater
  is not on his edges.
- **Stride down** — `commit_stride_mult` (< 1).

`hit_active` becomes `hit_held` (no stamina gate). `hit_turn_multiplier` and
`sprint_turn_multiplier` are deleted along with their facing-drag terms.

This reverses the reasoning in the current `hit_turn_multiplier` comment
("penalising the attempt rather than the miss is backwards"). That reasoning
leaned on stamina to bound how long a commit is held, and on sprint's turn
cost to bound full-speed homing; both are gone. The cost now lands where the
counter-play is: a commit loaded early is visible and cannot follow a carrier
who drops into the stance and cuts, while a commit thrown late costs almost
nothing.

**The stance and the commit are mutually exclusive, and the commit wins.**
`stance_active = stance_held and not hit_active`. The commit is the deliberate
press, and being caught upright is its whole cost.

### 2.6 A stagger costs grip, not stamina

The stamina bite (`incremental_stamina_drain`, `stagger_max_stamina_drain`) is
deleted. The stagger keeps its thrust penalty and adds a grip penalty of the
same shape: `grip_mult = 1 − stagger_max_grip_penalty · frac`, with `frac` the
same remaining-timer fraction `BodyCheckRules.thrust_mult` uses. A thrust
penalty alone barely registers on a skater already at speed (the stride is
power-limited there and the glide is long); off his edges, a rattled skater
cannot cut — he cannot use the stance to shake anyone until it wears off.
`stagger_timer` is already replicated and already applied in
`integrate_forward`, so this adds no wire state.

### 2.7 Grip composes in one place

```
effective_grip = lateral_grip
               × (stance_grip_mult if stance_active
                  else commit_grip_mult if hit_active
                  else 1.0)
               × stagger_grip_mult(stagger_timer)
```

Facing (the body's yaw toward the cursor) is unaffected by all of it.

## 3. Starting values

Feel tunables, hand-picked as starting points — tune on ice, not here.

| Tunable | Start | Note |
|---|---|---|
| `stance_grip_mult` | 2.0 | inherits `tight_turn_multiplier` |
| `stance_scrape` | 0.33 | calibration anchor, §2.2 |
| `stance_stride_mult` | 0.6 | |
| `stance_max_speed_mult` | 0.85 | ~8.7 m/s neutral |
| `stance_shuffle_mult` | 1.2 | below `GRIP_MIN_SPEED` only |
| `commit_grip_mult` | 0.6 | |
| `commit_stride_mult` | 0.5 | |
| `stagger_max_grip_penalty` | 0.4 | |

## 4. What it touches

### 4.1 Movement model (domain + native)

- `SkaterMovementRules.apply_movement` / `MovementConfig` / `integrate_forward`:
  §2.1–2.7. `sprint_active` parameters become `stance_active` plus
  `hit_active`; `integrate_forward` scales grip by the stagger the same way it
  already scales thrust.
- `native/src/native_skater_movement.cpp` mirrors all of it.
  `test_native_movement_parity.gd` must fuzz stance, commit and stagger.
- `StaminaRules` deleted with `test_stamina_rules.gd`.
- `BodyCheckRules`: the stamina bite deleted, the grip multiplier added.

### 4.2 Controller

- `SkaterController`: sprint/stamina tunables, `stamina`, `_sprint_locked`,
  `sprint_active` deleted; `stance_active` resolved from input with the commit
  exclusion; `hit_active` ungated.
- `apply_attributes`: `max_speed` folds in `sprint_ceiling_mult()` (§2.3);
  stamina scaling deleted.
- `SkaterPoseCoordinator.apply_facing`: both facing-drag multipliers deleted.
- `LocalController` reconcile: the stamina / lockout snap at replay start goes.

### 4.3 Wire (one protocol bump)

- `InputState`: flag bit `0x010` `sprint_held` → `stance_held` (same bit).
- `SkaterNetworkState` / `WorldStateCodec`: `stamina` u8 removed (offsets after
  it shift); flags bit 7 `sprint_locked` freed; intent bit 5 `sprint_active` →
  `stance_active` (remotes need it for the gait and for forward prediction).
- `BuildInfo.PROTOCOL_VERSION` 64 → 65, with a row in
  `docs/protocol-history.md`.
- `ReplayFileWriter.FORMAT_VERSION` bump, since replays carry the skater codec;
  old `.mreplay` files are rejected by the reader's existing version check.
- Lag-comp: `LagCompRewind.forward_predict_skater` and
  `RemoteController.sample_state_at` call `integrate_forward`; they pass the
  stance and commit bits from the snapshot so render == rewind holds.

### 4.4 Gait and pose

- `LocomotionRules.classify`: brake → `stop = 1`. The `tight` weight is driven
  by the stance instead — the excess-grip share of the turn (`(a_used − a_0) /
  a_0`, clamped) — and its side by the steer sign, as now.
- A stance overlay as a `GaitLayer` at the `FLOOR` stage: a crouch floor while
  held. The check commit's layer sits above it, and since the two are mutually
  exclusive, no suppression factor is needed.
- `NativeSkaterGait` mirrors the classify change — change both or neither;
  `test_native_gait_parity.gd` drives the stance.
- The sprint stride / stance / lean gains (`sprint_stride_gain`,
  `sprint_stance_gain`, `sprint_lean_deg`) are deleted.
- Render the change: add a held stance cut to `tools/pose_capture.gd`'s pose
  list and record a new `render-poses.sh` baseline.

### 4.5 Bots

Phase 1 (bots never hold the stance yet):

- `BotSprintRules` and `test_bot_sprint_rules.gd` deleted; the agent's sprint
  resolution, `_cached_sprint_held`, and `RoleDecision.sprint_override` go.
- `AISkaterCaps.sprint_speed_mult` / `LEAGUE_SPRINT_SPEED_MULT` deleted. Race
  speed becomes `max_speed`, which now *is* the old sprint ceiling, so race
  pricing barely moves — it only loses its stamina gating, which makes it
  simpler and no less true.
- `AIBodyCheck`'s commit decision loses its stamina reasoning; the grip cost is
  what it now weighs.
- Goalie behind-net puck play assumes the forechecker at a flat 11 m/s
  (`GoaliePuckPlay.opponent_speed`), still above the fastest new top speed
  (~10.5 m/s), so it stays conservative and needs only its comment reworded.
- The bots' pivot and arrival brakes are already stops, so Space losing the
  tight turn costs them nothing.
- Expect calibration tests to move (pass lead, rush read, loose-puck chase,
  carrier, track, coverage readiness, duel harness). Recalibrate them against
  the model; do not loosen assertions to pass.

Phase 3 (bots learn the stance): a grounded rule, not a curve — hold the
stance when the turn the steering target demands at the current speed exceeds
normal-grip capacity (`v² / r_needed > turn_accel · grip`), and for
low-speed mirroring. Design it against `Scripts/domain/ai/CLAUDE.md`.

### 4.6 UI, input and tutorial

- Input map action `sprint` → `stance` in `project.godot`; `PlayerPrefs` must
  migrate a saved `sprint` rebind to `stance` on load, or players lose it.
- `controls_tab.gd` label → a `tr()` key in `locale/translations.csv`.
- Stamina ring removed: `SkaterHUDCoordinator`, `IceRingField`, and the ice
  shader uniform `test_ice_shader_uniform_contract.gd` pins.
- Tutorial: the sprint step and the tight-turn teaching become one stance step;
  bump `PlayerPrefs.TUTORIAL_COURSE_VERSION` if the course is restructured.

### 4.7 Documentation, updated with the code

`docs/gameplay-design.md` (skating, sprint, physicality, stagger paragraphs and
"where the numbers live"), `Scripts/domain/state/CLAUDE.md` (sprint & carry,
metabolism), `Scripts/controllers/CLAUDE.md` (the attributes one-liner),
`Scripts/networking/CLAUDE.md` (stamina mentions), `Scripts/domain/ai/CLAUDE.md`
(sprint-aware caps). `docs/attributes-v4-plan.md` is a historical record; it
gets a one-line pointer here rather than an edit.

## 5. Order of work

One feature branch, one protocol bump, commits in this order:

1. Movement model and native port (§4.1), with movement tests and parity.
2. Controller, attributes, wire, replay format (§4.2–4.3).
3. Bots phase 1 (§4.5), with calibration tests recalibrated.
4. Gait and pose (§4.4), with gait parity and a pose render.
5. UI, input map, tutorial, docs (§4.6–4.7).

Then local testing. Phase 3 (bots use the stance) follows separately, after
the stance numbers have settled.

### Tests that hold it

- Brake with any stick direction is a pure stop: no heading change.
- A stance cut ends at the stick direction in a glide; speed is not stopped.
- A full-lock stance cut at top speed bleeds `tight_turn_decel`'s 3 m/s²
  (the calibration anchor); a turn inside normal grip bleeds nothing.
- Entering the stance over the stance cap preserves speed.
- Commit and stance are exclusive and the commit wins.
- Stagger reduces grip with the same decay shape as thrust.
- Per-build `max_speed` equals the old `base · speed_mult · sprint_ceiling_mult`.
- Codec and input round-trips with the new bits; native parity for movement
  and gait.

### What to test locally

- Weave and cut in the stance against a defender at the blue line: does it
  read as elusive, and does releasing to stride feel like a change of pace?
- Is the stance held all the time in the zone? (§6)
- Hockey stop with every key combination: always a clean stop.
- A committed check against a stance carrier: does an early commit get beaten
  and a late one land?
- Getting hit: is the grip loss felt, and too long or too short?
- Top-speed rushes: does ~2.75 s to full speed feel right, and can a
  backchecker catch a carrier?

## 6. Open questions

1. **Gamepad binding.** Sprint is on L3. A held stance on a stick click while
   steering with that stick is awkward, and every face, shoulder and stick
   button is taken. Swap it with the hit (LB), or move something else?
2. **Stance held always in the zone.** The stride and cap costs bind less in
   tight quarters. If playtesting shows it is never released, candidates are a
   slower first step out of the stance or a time budget — decide on evidence.
3. **Low-speed turning.** `max_turn_rate` (6 rad/s) caps turning below
   ~3 m/s, so the stance's grip gain fades out there. Raise the cap in the
   stance?
4. **Carrier separation.** Without the sprint bypass a carrier never
   outruns an equal chaser. Accept it, or raise `CARRY_BASE`?
5. **Weight loses its metabolism lever.** Lean's compensation was fast
   recovery; it keeps its agility edge, which the stance's grip multiplier
   amplifies. Check the corner budgets `test_player_attributes.gd` pins before
   adding anything.
