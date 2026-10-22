# Goalie rebuild — findings and a proposed design (October 2026)

Status: **proposal, not agreed.** Open questions for the user are in §7. Nothing
here is implemented yet.

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
| **Positional planner** | ~30 Hz | yes | depth solver composition, arc target, the slide triggers, beaten-wide, the RVH/VH/overlap choice, recovery, "threat pressing", save selection |
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

**Open question (§7 Q2):** whether he keeps reading the shooter's cursor. The
honest alternative is reading the **blade**:

- a wrist shot's line is constrained by where the blade is and which way it
  sweeps;
- a slapper's line is the wind-up's plane.

Those are cues a real goalie reads, and the bots and humans give them away
equally.

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
- post-integrated (RVH, VH, or the new overlap).

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

### 3.5 The body: one parametric pose solve

Replace about 15 hand-authored stance tables with one solve. Its inputs:

- stance width;
- knee bend and hip height;
- trunk lean;
- butterfly flare;
- per-limb hand targets;
- stick blade target;
- post contact (which pad, which face).

The pose set I'd teach:

| Pose | What changes vs today |
|---|---|
| **Ready stance** | Wider and lower. Pads on their inside edges with the knees in. **Stick blade centred in front of the five-hole**, about 30 cm ahead of the skates. Gloves forward of the body at pad-top height, glove open to the shooter. Chest over the knees. |
| **Butterfly** | Knees together, so the five-hole is closed by the body rather than by overlapping boxes. Pads flared with toe-out. Torso tall. Hands forward and beside the body. Stick in the five-hole. |
| **Butterfly extension / pad save** | **New.** One pad pushes out toward the post. This is the low-corner reach the regulation puck is currently scoring through. |
| **Half-butterfly** | Kept, with the down pad's top sealed against the trunk. |
| **Kick / skate save** | **New.** A standing low-reach save. |
| **RVH / VH / overlap** | Overlap is **new**: standing, pad against the post, for a sharp-angle shot threat that is still mobile. All three keep **live hands**. |
| **Paddle-down** | Promoted from a cosmetic sweep to a real jam and wraparound stance (open question; optional). |

**Arms collide.** Each forearm and upper arm becomes a box.

A **seam property** holds the body honest:

- for every pose, every gap in the straight-on silhouette is either narrower
  than the puck's diameter or on a list of **intended** windows (the read five-hole while moving, short-side high in RVH);
- the test fails on any unlisted seam, so the next change of the puck or the
  pads cannot open a hole silently.

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
| `GoalieNetworkState` and the wire, unless §7 Q4 says otherwise | Clients, replay, and the bots' perception all read it. New stances append to the enum. |
| `GoalieSaveRules` (rebounds), `SweptDiscOBB`, `GoalieContactDetector` | The puck side of the save is sound and has a native port. |
| `GoaliePushRules`, the stick lie and flush roll (`GoalieStickRules`), the two-bone arm IK | Grounded and well tested. |
| Screen occlusion geometry, pass reception, tip geometry | They become threat-model inputs rather than gates. |
| `GoaliePuckPlay`'s doctrine and pattern | Already the healthy collaborator. |
| The **beatability doctrine** (Scripts/controllers/CLAUDE.md) | It becomes the acceptance test: deception pays, the cutback beats the commit, a corner picked outside his reach scores. |

---

## 4. Risks

- **Planner cost.** Evaluating expected goals against for ~20 candidates × ~4
  hypotheses × 9 projected boxes at 30 Hz is ~22k box projections a second per
  goalie. That is fine natively and borderline in GDScript. The plan has a
  native kernel slot (`native/README.md` pattern) and a GDScript reference.
- **The bots have to follow.** `AIGoalieModel` and the generated shot field
  model *this* goalie. Every phase that changes him ends in a field
  regeneration (about 25–35 min on 4 shards), and the bots' pick quality moves
  with it.
- **Shot-field churn.** The fingerprint hashes the **full text** of every
  `goalie_*.gd`, so even a comment edit forces a regeneration. That is why the
  stale comments found during this audit are listed in §8 rather than fixed
  today. During the rebuild, regenerate at phase ends, not per commit.
- **Test churn.** About 61 test files reach into the controller, about 41 of
  them into private members. Doctrine tests that pin *how* he does something
  (`_current_depth` after N ticks) will not survive. Tests that pin *what
  happens* (the seal holds through a shot; deception pays) should, rewritten
  against a public tick seam.
- **Feel.** None of this can be judged headless. Every phase ends with a local
  playtest.

---

## 5. Phases

Each phase leaves the suite green and the game playable.

**Phase 0: one scoreboard.**
- One instrument, run in a few minutes, that prints:
  - the bot-vs-goalie rush conversion per tier;
  - the dot-line perfect-aim sweep (held and cold);
  - a SET-cell battery at ~10 spots × FLAT/LOW/HIGH;
  - the straight-on coverage per stance.
- A snapshot of those numbers, plus the tier-order property.
- Targets agreed with the user (§7 Q3).

**Phase 1: the body.**
- `GoalieBody.pose()` as one parametric solve producing the existing part
  boxes, plus arm boxes.
- The coverage function, and the seam property.
- The new ready stance and butterfly.
- The existing controller drives it through a thin adapter, so the brain is
  unchanged.
- This alone should recover most of the puck regression, and it is
  independently shippable.
- **Needs the user** for any new collider nodes in `Goalie.tscn` (§7 Q1).

**Phase 2: the new brain, beside the old one.**
- `GoalieBrain` (perception → threat → planner → motor) behind a selector in
  `ActorSpawner`, with the same public API (§1.3 of the controller map: `setup`,
  `reset_to_crease`, `fill_state`, `stance()`, …).
- The scoreboard runs both brains.
- The old controller is untouched, so it stays a working fallback.

**Phase 3: saves.**
- The reflex executor: independent stick, pad extension, kick, live hands in
  RVH/VH, overlap.

**Phase 4: the bots follow.**
- `AIGoalieModel` reads `GoalieBody` and the coverage function instead of
  copied constants.
- Shot field regenerated.
- #836's pended tests revisited.

**Phase 5: delete the old controller.**
- Doctrine tests rewritten against the public seam or deleted with the
  behaviour they pinned.
- `Scripts/controllers/CLAUDE.md`'s goalie half rewritten to the new shape.

---

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

## 7. Open questions for the user

1. **How deep does "ground up" go?** Brain only, or brain and body: poses,
   collider set, arm colliders? New collider *nodes* in `Goalie.tscn` are yours
   to make in the editor. Alternatively, the arm boxes can be code-defined
   shapes the contact detector reads, with no scene change.
2. **The cursor read.** Keep reading the shooter's published aim (stale), or
   read only what a goalie can see (blade, body, wind-up)?
3. **Targets.** What should HARD's save percentage be against bot rushes, and
   overall? NHL is about .905; today's rush number is about .62. Should
   EASY / NORMAL / HARD sit at fixed gaps?
4. **The wire.** Is a protocol and replay-format bump acceptable? Old replays
   would stop loading.
5. **Side by side or in place?** Phase 2 assumes the new brain lives beside the
   old one until it wins on the scoreboard and in your playtest. The
   alternative is replacing in place: faster, but with no fallback.

---

## 8. Stale comments to fix during the rebuild

Any edit to a goalie file forces a shot-field regeneration (§4), so these ride
the first phase that touches each file.

| Where | Stale text | Actually |
|---|---|---|
| `goalie_controller.gd:4555` | "converged after one `read_lag`" | uses `read_converge_time` |
| `goalie_controller.gd:3577` | "BUTTERFLY uses compute_slide_destination" | uses `target_arc_position` |
| `goalie_controller.gd:247` | "outer pad reach 0.88" | 0.84 |
| `goalie_controller.gd:806`, `goalie_body_config_builder.gd:53` | READY body height "0.96" | 0.98 |
| `goalie_controller.gd:876` | "carrier.gd duplicates the enum values" | it reads `GoalieNetworkState` |
| `goalie_controller.gd` header | "tuning `@export`s" | 0 `@export`s remain |
| `goalie_body_config_builder.gd:399` | "0.52 × 0.72 torso box" | 0.62 |
| `goalie.gd:371` | "body 0.40 in butterfly" | 0.64 |
| `goalie_behavior_rules.gd:1285` | blade "0.07 m tall" | 0.089 |
| `goalie_crease_clear.gd:209` | doc for a reach-race function | the function no longer exists |

`Scripts/controllers/CLAUDE.md` (the subsystem map) and `ARCHITECTURE.md:143`
(the tracking-lag paragraph) are not fingerprinted, and were corrected alongside
this plan.
