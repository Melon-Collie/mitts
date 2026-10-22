# Goalie rebuild — findings and a proposed design (October 2026)

Status: **agreed design; implementation not started.** The user's decisions
are in §7. In short:
- a new articulated goalie, with skates, toe bridges and real pads on real legs
  (§3.5);
- he reads only what a goalie can see (§3.1);
- a bot-free scoreboard, because the bots are mid-change (§5, Phase 0);
- the old goalie is deleted once the new one plays (§5).

This document answers three things:

- why the goalie got worse when the puck went regulation;
- why he was not good before, either;
- what a goalie built from scratch should look like, and how to get there
  without a month with no working goalie.

Every number below was measured at `7595182` unless it says otherwise. The
before/after puck figures come from re-running the same instruments on a
checkout of `9364468^`.

---

## 1. Where he stands today

### 1.1 The scoreboard

No single number tracks how good the goalie is. Below are the three that
exist, with the old (r = 6.5 cm) puck against the regulation (r = 3.81 cm)
puck.

| Instrument | Old puck | Regulation puck |
|---|---|---|
| Bot-vs-goalie rushes, 63 per tier (`test_bot_vs_goalie_conversion`), goals | HARD 33.3% · NORMAL 30.2% · EASY 22.2% | HARD **38.1%** · NORMAL 31.7% · EASY 22.2% |
| Dot line (6.1 m), held wind-up, perfect aim (`test_goalie_exhaustive_beatability`) | 13 / 288 | **34 / 300** |
| Dot line, cold release, perfect aim | 16 / 288 (July) | **57 / 300** |
| Shot field, SET cells, aimed-point goal share | 2.1% | **6.1%** |
| Field's own best pick against a SET keeper (truth table) | 2 / 20 | **15 / 20** |

The bot-vs-goalie row measures the bots as much as the goalie, and the bots are
changing under it. The scripted rows are the ones to trust: the perfect-aim
sweeps, and the shot field, whose shooters are staged by
`shot_odds_stager.gd`, not bot brains.

Two things stand out:

- **Save percentage against bot rushes is about .62.** NHL is about .905, and
  the star-of-game baseline assumes .800.
- **The difficulty ladder is upside down.** HARD concedes the most, before and
  after the puck change. The breakaway ladder test is pended (#836) for exactly
  this.

### 1.2 Why the smaller puck hurt: the body is full of seams sized between the two pucks

The contact test (`SweptDiscOBB`) grows every goalie box by the puck radius, so
a seam passes the puck only if it is wider than 2r. That threshold was 13.0 cm
and is now 7.62 cm. Measured on the live colliders, straight-on, goalie on the
goal line:

| Stance | Mouth covered, old puck | Mouth covered, regulation puck |
|---|---|---|
| READY | 64.5% | 57.8% |
| BUTTERFLY | 70.0% | 64.3% |
| HALF_BUTTERFLY | 68.0% | 61.1% |
| RVH | 62.4% | 56.4% |

Specific seams the old puck could not fit through, and the regulation puck can:

- **Standing five-hole at 0.5 m:** about 11.6 cm wide.
- **Half-butterfly:** a band between the down pad's top (0.28 m) and the
  trunk's bottom (≈0.36 m), open **across the whole glove side**.
- **Butterfly, blocker side at 0.70 m:** open between the torso and the stick
  shaft.
- **Butterfly, glove side over the pad:** open band grew from 14 cm to 19 cm.
- **RVH:** the seam at the post pad's toe went from a 3.6 cm lane to a 12 cm
  lane.
- **Butterfly at the post:** the seal margin fell from about 3 cm to **about
  3 mm**, so any squaring error opens the far post along the ice.

No constant names 0.065. The seams are just left as authored, and the old puck
happened to seal them.

**Arms are not colliders.** Only seven boxes stop the puck: two pads, torso,
head, glove, blocker, and the stick (three shapes). The forearm and upper arm,
which fill the space between the blocker and the chest on a real goalie, are
mesh only. That is a permanent hole (READY, blocker side, about 1.1 m), whatever
the puck's size.

### 1.3 Why he was not good before: the brain is gates layered over primitives

The pure rule files are mostly good physics:

- `GoalieBehaviorRules`, `GoaliePushRules`, `GoalieSaveRules`, `GoalieAnatomy`
- `GoalieStickRules`, `GoalieScreenDepth`, `GoalieTipDepth`, `GoaliePassRead`

They are **primitives**. The doctrine — when each one is asked, with what
inputs, and which one wins — lives in `goalie_controller.gd`. That file has
5,075 lines, 145 functions, 311 fields and 206 tuning vars. Of those vars, 73
only relay a value to a collaborator.

What that produces:

- **Nine places in one tick can change his stance.** Tracking, the shot timer,
  the state update, the position update, the poke step, and two signal handlers.
  There are 8 call sites that enter the butterfly and 5 that commit a slide,
  each with its own gating.
- **Several systems fight over the same quantity.**
  - `_current_depth` is a radius in some states and a perpendicular depth in
    others, with 11 writers.
  - `_current_x` has 13 writers.
  - The lateral target is composed by statement order: arc, then peek, then the
    cross-crease override, then the slapper shade.
- **The same event is handled twice.**
  - Two pass detectors: cross-crease and pass read, with precedence patches
    between them.
  - Two shot-entry paths: release and universal.
- **Patches stand in for missing models.** Examples:
  - `_drop_waits_on_a_stick` and the imminence windows exist because a pass
    fires `puck_released` like a shot.
  - `_holding_seal_for_shot` exists because RVH and VH have no shot reaction.
  - The screen-block drop fires when a delay saturates its tuning cap.
  - The beaten-wide verdict has separate onset and persistence clocks, two
    reaches, a pad-turn segment and a debounce, all to make a latched verdict
    terminate.
  - A depth-floor exemption exists so that two owners stop fighting over
    `_current_depth`.
- **Ownership is contested.** Thirteen `GoalieCreaseClear` fields are written
  by the controller, and the slide's velocity and drop progress are written from
  both sides.
- **He reads the shooter's mind.** The shot belief is sampled from the
  shooter's published `predicted_shot_velocity` — the cursor — 0.05 s stale.
  The staleness makes it beatable, but the input is still telepathy.

Each patch is locally argued and pinned by a test. **The global behaviour is the
precedence order of gates that nothing composes.** That is why tuning one thing
moves three others, and why "better" kept measuring as "less beatable in the
wrong way" (Scripts/controllers/CLAUDE.md, *Beatable realism*).

### 1.4 What the poses look like

These are rendered with `tools/goalie_capture.gd`.

- **The relaxed standing pose stands nearly straight.** The stick hangs out to
  the blocker side rather than in front of the five-hole, and the five-hole
  shows daylight up to the crotch.
- **READY is a better crouch, but its five-hole is open by design.** It is
  23–33 cm raw at pad height, and its comment calls it "a deliberate window".
- **The butterfly is a 90° roll of two boxes.** It has no flare, the knees don't
  close, and the torso is upright and tall.
- **Pads have no reach of their own:** no kick save, extension, stack or
  sprawl. A low save is a stance change or a committed slide.
- **The blocker moves the whole stick.** A blocker save lifts the paddle off the
  ice.
- **RVH and VH are frozen:** no hand reaction while sealed.

---

## 2. Design principle: the goalie is a shape, and the shape is the model

Today, three different things each hold their own idea of how much net the
goalie covers:

1. the colliders;
2. the planner's beliefs: `GoalieAnatomy` numbers, pad half-widths, standing
   pad bands;
3. the bots' model: `AIGoalieModel`, plus a shot field generated by brute force
   because the model could not be trusted.

They drift, and the puck change showed it: the colliders lost 6 points of
coverage and the planner did not notice, because nothing it reads measures
coverage.

**Proposal: one body function, three readers.**

```
GoalieBody.pose(stance_params, limb_targets) -> part boxes (OBBs)
        │
        ├── actor colliders                  (what stops the puck)
        ├── coverage(boxes, puck_pos, r)     (what the planner minimises)
        └── AIGoalieModel                    (what the bots shoot at)
```

**Coverage** is the goal mouth as seen from the puck, minus the silhouette of
every part box grown by the puck's radius. Computed analytically, each box
projects to a convex polygon on the goal plane. Seams, the five-hole, the post
margin and puck size all fall out of it. A 7.6 cm puck finds a 9 cm seam because
the seam is *in the number*, not in someone's memory of the number.

That gives the rebuild one currency, the same way the bots have one currency in
expected goals:

> **Expected goals against** = Σ over shot hypotheses *h*:
> P(*h*) × uncovered fraction of the mouth, from *h*'s release point, for the
> pose he can reach by *h*'s release time plus his reaction budget.

---

## 3. The proposed architecture

One tick runs four layers, on two clocks.

| Layer | Rate | Pure? | Replaces |
|---|---|---|---|
| **Perception** (`GoalieView`) | 120 Hz | no; it is the only reader of live nodes | ~100 scattered `puck.*` / skater reads; `GoalieWorldView` grows into it |
| **Threat model** | 120 Hz | yes | threat filter, prime, read belief, pass read, cross-crease detector, screen delay, tip/backdoor reads |
| **Positional planner** | ~30 Hz | yes | depth solver composition, arc target, the slide triggers, beaten-wide, the RVH-or-overlap choice, recovery, "threat pressing", save selection |
| **Motor + reflex executor** | 120 Hz | stateful, scene-free | the upright mover, slides, the drop and rise, limb reaches; the pose solve |

The puck-handling half (cover, sweep, catch, behind-net play) stays a separate
small state machine. It is built on `GoaliePuckPlay`'s pattern, which is
already the healthy collaborator.

### 3.1 Perception: what he can actually see

The view is filled once per tick and is plain data:

- puck position and velocity;
- each skater's position, velocity, facing, blade position, and a coarse
  shot-motion phase (gliding, loading, releasing);
- screens.

**Decided: no cursor read. He reads only what a goalie can see.**

**The rule: if a remote client could not draw it, the goalie cannot read it.**

- **The view may be filled only from the replicated fields that pose a skater
  on screen:**
  - `position`, `velocity`, `facing`;
  - `upper_body_rotation_y` (the coil);
  - `blade_position`, `top_hand_position`, `blade_side`, `blade_up`;
  - `shot_state` (a raised slapper is visible);
  - `torso_lean`;
  - the puck.
- **It may never read:**
  - `predicted_shot_velocity`;
  - the bots' committed aim (`bot_wrister_aim_dir` and kin);
  - `shot_charge` as a number.

  A wind-up's size reads only as far as the pose draws it.
- **A test holds the rule:** the perception class names no field outside the
  list.

**What that leaves him to read:**
- **Wrist and snap shots:**
  - the line the blade can throw along, given where it sits relative to the
    body;
  - which way the blade is sweeping;
  - which way the hips and shoulders open.
- **Slappers:** the wind-up's plane, from the coil and the facing.
- **Everything:** after release, the puck itself, through the read delay.

**What follows:**
- **The aim shade, the cursor prelean and the belief ring buffer have no
  counterpart.** The goalie's pre-release guess is a distribution over the
  lines the blade can throw. It narrows as the coil and sweep commit, and
  collapses onto the puck's real line after release, through the read delay.
- **Deception becomes a body skill:**
  - opening the hips one way and pulling across;
  - changing the blade's angle late.

  This is how it works on real ice. It also applies equally to humans and
  bots, because both are read through the same drawn pose.
- **The old goalie keeps its cursor read** until it is deleted (§5, Phase 4).
  The decision applies to the new goalie only.

### 3.2 Threat model: what might happen, and when

The threat model turns the view into a small set of **shot hypotheses**. Each
one is a release point, an earliest release time, and a weight:

- the carrier, shooting now;
- the carrier after the move he is making: the lateral drive continued, or the
  cutback;
- each receiver the puck can reach, shooting on reception, weighted by whether
  the receiver is loaded for a one-timer;
- a stick at the net front, redirecting.

Read latency applies to **the view the hypotheses are built from**. That keeps
"he can be wrong, deterministically" exactly as now, without the cursor.

### 3.3 Planner: one evaluation instead of thirty gates

Candidates are a handful of target spots (arc angle × depth) × base stance:

- READY;
- butterfly;
- half-butterfly L/R;
- RVH L/R, on the post.

Each candidate is scored by expected goals against (§2), with the pose he can
reach by each hypothesis's release time. Reachability comes from the motor model
(`GoaliePushRules`, the drop and rise clocks, the slide's ballistic reach).
Today's special cases become ordinary consequences of that score:

- **Depth.** Challenging covers more from the carrier's point of view and less
  against the pass hypothesis. The best depth is wherever the two meet.
- **Butterfly versus stand-up.** The butterfly covers low; standing covers high.
- **Beaten wide.** The far-side hypothesis outscores the near one, and the
  only reachable answer is the slide.
- **Staying down.** The rise costs 0.35 s of pose he can't reach.
- **The overlap.** A sharp-angle shooter in front of the goal line is faced
  with the READY stance, squared to the puck and placed so its post-side pad's
  edge covers the post. It is a spot, not a pose: from the shooter, the short
  side then shows no net. Below the line, or tight to it, the RVH outscores it.
- **Screens.** The release point is hidden, so its weight spreads.

**Commitment comes from physics, not timers.** A slide is ballistic once pushed,
the drop takes about 0.2 s, and the rise about 0.35 s. The planner may only
choose what is reachable from the current motor state, so there is no debounce,
no latched verdict, and no onset-versus-persistence split.

A small switching cost is the one honest hysteresis: changing plans costs a
re-set.

### 3.4 Motor and reflex: the save itself

Once a release is read, after the read delay, each limb intercepts the believed
line inside its own reach envelope and speed:

- glove;
- blocker, with the stick **independent of the blocker**;
- each pad (a kick, an extension, a stack);
- the stick blade.

**Save selection is the planner evaluated at the release instant**, with
time-to-impact as the budget. There is one decision and no separate block or
react chain.

### 3.5 The body: a new goalie model, articulated like a real one

Today's goalie has **no legs**:
- The pads are free-floating boxes, placed per stance from hand-authored tables
  (about 15 of them).
- There are no skates, knees, hips or toe bridges.
- The five-hole is whatever gap two boxes happen to leave.

That is why his poses read wrong, and why a gap can sit unnoticed between the
two pucks' widths. **Replace him with an articulated body**, built in code the
way the skater is (`SkaterBodySkeleton`, `LegIK`, `TwoBoneIK`, `BodyZonePaint`,
the skate assembly in `SkaterMeshBuilder`). Same low-poly faceted art style.

**One build: 6'4" (1.93 m) before skates.**
- Segment lengths come from standard stature ratios (thigh, shin, trunk, arm
  and forearm as fractions of height).
- The skate adds its boot sole and holder underneath.
- The pads are sized to that leg the way real pads are fitted: knee centred on
  the knee stack, the boot over the skate, the thigh rise above the knee.
- Pad designs stay plain, the kit's one `goalie_pads` colour, for now.

**Skeleton.** Each joint has the range a goalie actually has:

| Joints | Notes |
|---|---|
| pelvis, waist, spine, neck, head | |
| hip ×2 | flexion, abduction, **internal rotation**: what the butterfly is made of |
| knee ×2 | |
| ankle ×2 | |
| shoulder ×2, elbow ×2, wrist ×2 | |

**Gear**, each piece strapped to the bone that carries it, so its placement is
a consequence of the pose:

| Gear | Bone | What it is |
|---|---|---|
| **Skates** | foot | the skater's skate assembly, goalie-cut: lower boot, cowling, long flat blade |
| **Leg pads** | shin | Thigh rise over the knee, knee stack, landing block on the inside face (what lands on the ice in the butterfly), outer roll, **boot and toe** over the skate |
| **Toe bridges** | pad toe → skate | The strap that makes the pad rotate with the foot. It is why a butterfly flares the pads, and why the toe seals the post along the ice |
| **Knee pads / thigh guards** | thigh | what fills the five-hole from above when the knees close |
| **Pants** | pelvis | |
| **Chest-and-arm unit** | spine, upper arms, forearms | Shoulder floaters, and **arm sleeves that collide** |
| **Trapper** | glove wrist | cuff, T-trap and pocket, oriented by the wrist rather than one fixed pitch |
| **Blocker** | blocker wrist | board and palm |
| **Stick** | blocker hand, with its own wrist | The stick and the blocker are no longer one rigid assembly: a blocker save no longer lifts the paddle off the ice |
| **Mask** | head | cage, backplate, neck dangler |

Sizes come from the NHL equipment rules where they exist:
- pads 11 in wide, height by leg length;
- blocker 8 × 15 in;
- trapper ≤ 45 in perimeter;
- floater and arm limits.

**Collision hangs off the bones, defined in code.** Each gear piece declares
one or a few boxes in its bone's frame, for example:
- pad: thigh rise plus shin-and-boot;
- skate and toe;
- forearm sleeve.

`GoalieContactDetector` reads that list. Nothing queries the goalie's physics
layers today; the detector reads only box extents and transforms, so the scene
needs no collider nodes. `Goalie.tscn` shrinks to a root, and the colliders are
code, versioned with the poses that move them.

**Poses are joint configurations.** The pose set, built from that skeleton:

| Pose | What the joints do |
|---|---|
| **Ready stance** | Feet wider than the shoulders, knees bent and in, pads on their inside edges. **Stick blade centred in front of the five-hole**, about 30 cm ahead of the skates. Gloves forward at pad-top height, trapper open. Chest over the knees, head over the toes. |
| **Butterfly** | Knees down and together, hips internally rotated, shins and skates flared out. The toe bridges turn the pads out with them, and the landing blocks lie on the ice. Torso tall, hands forward and beside the body, stick in the five-hole. The five-hole is closed by **knees and thighs**, not by overlapping boxes. |
| **Butterfly extension** | **New.** One leg pushes out toward the post, pad face down, toe on the ice. This is the low-corner reach the regulation puck is currently scoring through. |
| **Half-butterfly** | Kept. One knee down, the other leg loaded on its skate. |
| **Kick / skate save** | **New.** A standing leg's quick extension; the skate and toe stop low shots. |
| **RVH** | The post pad flat along the goal line, its toe on the post; the off-post pad standing on its skate. The post is sealed by the pad toe and skate where they really seal it, and the hands stay live. The VH is dropped and the overlap is a spot, not a pose (§3.3, §7). |
| **Paddle-down** | Optional: a jam and wraparound stance. |
| **T-push, shuffle, C-cut, recovery** | Real footwork on real skates. The existing `GoalieFootwork` stroke becomes leg motion instead of a pad offset. |

**The network sends pose parameters, not part transforms.** If the pose is a
pure function of a small parameter vector (stance, the joint targets the
planner and reflexes chose, the limb reach targets), then:
- the wire carries the vector;
- every client rebuilds the identical body;
- client colliders equal host colliders by construction.

Today the host and client poses come from separate tables, and they have
already drifted (§6). This needs a protocol bump; see §7.

**A seam property holds the body honest:**
- For every pose, every gap in the straight-on silhouette is either narrower
  than the puck's diameter or on a list of **intended** windows. Examples of
  intended windows: the five-hole opening during a T-push, short-side high in
  RVH.
- The test fails on any unlisted seam. The next change of puck, pad or pose
  then cannot open a hole silently.

**Seeing it.** A `render-goalie.sh` hook beside `render-poses.sh`:
- every pose from front, side and above, against a recorded baseline;
- plus the **coverage view**: the mouth as the puck sees it, uncovered cells
  painted.

Articulation is the thing a headless test cannot assert.

### 3.6 Difficulty: honest axes only

Tiers differ on four things:

- read latency;
- read sharpness (how stale the view the hypotheses come from is);
- motor speeds (edges, push, drop, limb speed);
- the planner's hypothesis set (an easy goalie doesn't consider the backdoor
  pass until it is thrown).

They never differ on body geometry or depth bias.

A property test asserts the ladder order on the scoreboard (§5, Phase 0).

### 3.7 What the rebuild keeps

| Keep | Why |
|---|---|
| `GoalieNetworkState`'s **accessors** (`is_down`, `post_seal_x_sign`, `hands_read`, `pads_read`) | The bots perceive the goalie through them. The bytes behind them change (§3.5); the questions they answer don't. |
| `GoalieSaveRules` (rebounds), `SweptDiscOBB`, `GoalieContactDetector` | The puck side of the save is sound and has a native port. The detector's input changes from scene shapes to a box list. |
| `GoaliePushRules`, the stick lie and flush roll (`GoalieStickRules`), `TwoBoneIK` / `LegIK` | Grounded and well tested. |
| Skater art infrastructure: skate assembly, `BodyZonePaint`, the faceted mesh toolbox | One art set. |
| Screen occlusion geometry, pass reception, tip geometry | They become threat-model inputs rather than gates. |
| `GoaliePuckPlay`'s doctrine and pattern | Already the healthy collaborator. |
| The **beatability doctrine** (Scripts/controllers/CLAUDE.md) | It becomes the acceptance test: deception pays, the cutback beats the commit, a corner picked outside his reach scores. |

---

## 4. Risks

- **Planner cost.** Evaluating expected goals against for ~20 candidates × ~4
  hypotheses × ~16 projected boxes at 30 Hz is ~40k box projections a second
  per goalie. That is fine natively and borderline in GDScript. The plan has a
  native kernel slot (`native/README.md` pattern) and a GDScript reference.
- **Skeleton cost on the tick.** The skater poses its legs at render rate, but
  the goalie's gear **is** gameplay geometry. On the host, the bone chain that
  carries colliders must be solved on the tick. Only the cosmetic remainder
  (straps, the dangler, the jersey hem) may go to render rate.
- **The bots shoot at the old goalie.** `AIGoalieModel` and the generated shot
  field model the current keeper. The field itself is bot-free (its shooters
  are staged), so it stays a valid measurement. But the bots' play is tuned
  against it, and the bots are mid-change too. So:
  - the goalie work does not gate on the bots;
  - switching the default goalie is the one step that needs a field
    regeneration and a word with the bot work (§5, Phase 3).
- **Shot-field churn.** The fingerprint hashes the **full text** of every
  `goalie_*.gd`, so even a comment edit forces a regeneration. That is why the
  stale comments found during this audit are listed in §8 rather than fixed
  today. New files are needed anyway, so name the new goalie's files outside
  the fingerprint's `goalie_*` glob (e.g. `Scripts/goalie/`) until it becomes
  the default. Then the old keeper's field stays current the whole time.
- **Test churn.** About 61 test files reach into the old controller, about 41
  of them into private members. They stay green while the old goalie stands,
  and are retired with him. The new goalie's tests are written against a
  public seam from the start.
- **Feel and look.** Neither can be judged headless. The body phase is reviewed
  from renders, and every later phase ends with a local playtest.

---

## 5. Phases

The new goalie is a **new actor and brain**, written as new files outside the
shot field's `goalie_*` fingerprint glob (e.g. `Scripts/goalie/`). That keeps
the old keeper's field current while the new one is built. No adapter maps the
old brain onto the new body: the two bodies share no parts, and an adapter
would be thrown away.

**There is no long side-by-side.**
- **Offline:** as soon as the new goalie plays (end of Phase 3), he becomes the
  goalie. Tuning continues on him rather than on a comparison.
- **Online:** the old goalie survives only until the new wire lands
  (Phase 4), so online matches never lose their goalie in the gap. Then the old
  goalie is deleted.

Each phase leaves the suite green and the game playable.

**Phase 0: a bot-free scoreboard.**
- One instrument, run in a few minutes, that drives **either** goalie through
  one interface against **scripted** shooters only. It reuses
  `real_goalie_shot_harness` and `human_wraparound_harness` (both scripted, no
  bot brains). It prints:
  - **Dot line, slot and wide-angle spots:** perfect-aim sweeps (held wind-up
    and cold release) × FLAT/LOW/HIGH.
  - **Scripted plays:**
    - a lateral drive and shot;
    - a deke then elevate;
    - a cross-crease one-timer;
    - a breakaway cutback and walkaround;
    - a wraparound;
    - a rebound put-back.
  - **Coverage per pose:** straight-on, and from the dot and the wide angle.
- The old goalie's numbers go in as the baseline snapshot.
- A tier-order property: the only hard assertion.
- **No targets yet.** The scoreboard records where each goalie stands, and
  targets come once the new one is playable and there is something to tune
  toward.

**Phase 1: the new body, posed statically.**
- Skeleton, gear meshes, bone-hung collision boxes, and the pose set (§3.5).
- `render-goalie.sh` with a recorded baseline, plus the coverage view.
- The seam property.
- **Reviewed from renders with you** before any motion is built on it.

**Phase 2: the motor.**
- Real footwork on real skates: stance, shuffle, T-push, C-cuts.
- The butterfly drop and rise.
- Slides, post integrations, and the recovery.
- Limb reaches: glove, blocker, independent stick, pad extension, kick.
- Timings come from the current grounded numbers (0.20 s drop, 0.35 s rise,
  the push and edge profile), so the new body moves no faster than the old one
  until it is meant to.

**Phase 3: the brain.**
- Perception → threat model → planner → reflex (§3.1–3.4).
- Puck handling: cover, sweep, catch, behind-net play.
- Scored on the Phase 0 scoreboard against the old goalie's baseline.
- **The offline switch:**
  - free play, practice and games against bots use the new goalie;
  - the shot field is regenerated against him;
  - `AIGoalieModel` reads his body and coverage function instead of copied
    constants.

  The bots then shoot at the keeper they face. Coordinate the timing with the
  bot work; don't gate on it.

**Phase 4: online, and the old goalie goes.**
- The pose-parameter wire state (§3.5), with a protocol and replay-format bump.
  Old replays stop loading; agreed.
- Clients rebuild the pose from the parameters.
- Lag compensation (the release rewind poses the goalie from history).
- Then delete the old goalie:
  - the controller and its collaborators;
  - the pose builder;
  - `Goalie.tscn`'s collider nodes;
  - the 60-odd tests that reach into him.
- `Scripts/controllers/CLAUDE.md`'s goalie half is rewritten to the new
  shape.

**After:** tune on the new goalie, offline and online, against the scoreboard
and playtests.
---

## 5a. Progress

| Phase | State |
|---|---|
| 0 — scoreboard | `tests/instruments/ai/test_goalie_scoreboard.gd` (44 s), old goalie's baseline in `tests/instruments/ai/data/goalie_scoreboard.txt`: EASY 71 / NORMAL 63 / HARD 43 goals of 395 scripted shots, tiers in order. Its shooters are puppets that publish the cursor aim; the new goalie needs a shooter that poses a real skater (blade, coil) before Phase 3 |
| 1 — the body | done, reviewed from renders: `Scripts/domain/keeper/`, `Scripts/actors/keeper/` (see its CLAUDE.md); poses and model signed off. Straight-on coverage, regulation puck (`tests/unit/keeper/snapshots/keeper_coverage.txt`): ready 58%, butterfly 68% (old: 58%, 64%); from the dot line at B depth 70% / 82%. The seam property holds every hole a flat puck fits through to its stance's intended windows (`test_keeper_seams.gd`; the renders paint the mouth with them); closing the rest (the blocker-side slit, the extension's five-hole, slits under the toes) traded about a point of straight-on coverage, the blocker now overlapping the hip. Open: the right-catcher mirror, one merged skinned mesh |

## 6. Things found along the way (flagged, not fixed)

- **`PuckAuthorityRules.FRAME_SUBSTEP_M = 0.04`** is commented "< a puck
  radius". That is no longer true: the radius is now 0.0381. If the post and
  frame clamp relies on it, the iron can be tunnelled at one sub-step's travel.
  This is a possible bug outside the goalie.
- **The network stance tables in `GoalieBodyConfigBuilder` have drifted from
  the builder:**
  - COVERING body 0.48 vs 0.54;
  - CATCHING and CATCHING_DOWN heads differ.

  Clients therefore draw a smother about 6 cm lower than the host collides it.
- **SLIDING's push-off pad dips under the ice** at full speed (y ≈ −0.17).
  **COVERING's glove box** also reaches under the ice.
- **`reset_to_crease` leaves fields stale:** `_prev_blade_world_pos`,
  `_puck_velocity_est`, `_prev_arc_target_xz` and `_recovery_needed`. The first
  feeds the blade velocity a poke strips with. Unverified in play.
- **`net_margin = 3.0` also feeds the universal reaction.** A hard wide rim
  within 3.9 m of centre freezes his steering.
- **Dead code:**
  - `GoalieBehaviorRules.target_lateral_x`;
  - `GoalieBehaviorRules.compute_slide_destination`;
  - `_target_x`, which is written but never read.
- **Ladder inversion:** HARD concedes more than NORMAL on the rush instrument,
  before and after the puck change.

---

## 7. Decisions

| Question | Decision |
|---|---|
| Scope | Brain and body, with a new articulated model (§3.5) |
| Bots as a yardstick | No. The scoreboard is scripted (§5, Phase 0) |
| The read | No cursor. He reads only what a goalie can see (§3.1) |
| Targets | None yet. The scoreboard records, and targets come later |
| Wire | Change it freely. Old replays may stop loading |
| The old goalie | Delete him. Switch offline first, online once the wire lands (§5) |
| Build | One goalie, 6'4" (1.93 m) before skates |
| Pad graphics | Plain for now. Painted designs are later work |
| VH | Dropped: the RVH is the post stance |
| Overlap | Not a pose: the READY stance placed on the post, squared to the shooter (§3.3) |

---

## 8. Stale comments

Corrected alongside this plan, since stale documentation is fixed on the spot:
- the controller header ("tuning exports … for editor access");
- the READY chest height (0.96 → 0.98) in the controller and the pose builder;
- the convergence clock (`read_converge_time`, not `read_lag`);
- the dead `compute_slide_destination` reference;
- the `carrier.gd` enum-duplication claim;
- `goalie.gd`'s butterfly body height;
- the blade height in `goalie_behavior_rules.gd`;
- `goalie_crease_clear.gd`'s orphaned reach-race doc and empty trailing header;
- `ARCHITECTURE.md`'s tracking paragraph;
- the `Scripts/controllers/CLAUDE.md` subsystem map.

The shot field was regenerated for the fingerprint change.

**One left as a flag, because it is not just a comment.**
`goalie_controller.gd`'s `post_seal_inset = 0.38` is documented as "outer pad
reach 0.88 − 0.50 body inset". The pad reach is now 0.84, which would make the
inset 0.34. Either the number or its derivation is stale, and picking one moves
the post-seal spot. That is a behaviour change for the rebuild to settle, not a
comment fix.
