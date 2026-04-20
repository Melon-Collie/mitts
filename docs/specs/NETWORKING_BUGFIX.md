# Blade Jitter Audit — Local Player, Client, Under Simulated Lag

## Context

The local player's own blade jitters on clients during movement after the Phase 1 networking refactor. Offline and host playback are smooth. Stack: Godot 4.6, 240 Hz physics, 60 Hz input send, 20 Hz state broadcast.

Developer clarifications:
- Jitter is on the **local player's own skater**, not remote skaters.
- The **skater body is not visibly jittering**, but `NetworkTelemetry` shows a high reconcile rate.
- **Phase 1f was already tried and reverted** — it made jitter worse, not better.
- The developer flagged that the reconcile path "isn't actually replaying, it's just throwing things away after replaying" — confirmed in F8 below; interacts with F0.

Phase 1 state as shipped on this branch:
- **1a** input sequence stamping (superseded by host-timestamp in Phase 4, but semantically equivalent)
- **1b** reliable `notify_carrier_changed` RPC
- **1c** reconcile velocity threshold 0.1 → 0.4 m/s
- **1d** extrapolation on buffer overshoot
- **1e** deferred (needs Phase 4 host timestamps) — done via 4
- **1f** reconcile position smoothing — *reverted* because it worsened the symptom
- Sub-fix: `InputState.delta` now stamped with physics delta

## Primary finding (F0) — Replay loop runs per-tick simulation against a frozen body

`Scripts/controllers/local_controller.gd:129-130`:

```gdscript
for input in _input_history:
    _process_input(input, input.delta)
```

`_process_input` (`skater_controller.gd:210-236`) calls `_apply_movement` → `_apply_facing` → `_apply_state` (which calls `_apply_blade_from_mouse`) → `_apply_upper_body`. Three of these read `skater.global_position` / `skater.global_transform` live:

- `_apply_blade_from_mouse` (lines 752, 760, 802) — IK target in upper-body-local space.
- `_apply_facing` (lines 876-881) — `to_mouse` vector from body to mouse.
- `_apply_upper_body` (lines 854-861) — twist angle computed from `blade_world - skater.global_position`.

**`_apply_movement` (line 917) does not call `move_and_slide`.** The controller is wired with `process_physics_priority = -1` (line 192) specifically so `Skater.move_and_slide` runs *after* the controller returns — once per physics tick, not per `_process_input` call. Consequence during replay:

| Per-iteration effect | Over the replay loop (≈12 iterations at 240 Hz = 50 ms) |
|---|---|
| `skater.velocity` mutated | only the last iteration's velocity survives |
| `skater.global_position` read | **frozen at `server_state.position`** for every iteration |
| `_apply_blade_from_mouse`, `_apply_facing`, `_apply_upper_body` | all evaluate against frozen body |
| Final `blade_position` / `_facing` / `_upper_body_angle` | derived from last input + frozen body |

Order-of-magnitude blade error: at top speed (9 m/s) over a 50 ms replay window, the body should have travelled ~0.45 m. Holding it fixed means blade IK's mouse-local target is off by that amount in world space; IK + twist + facing propagate the error through the per-tick system (≈0.1 m by the time it settles on the blade tip). That's the visible 20 Hz hitch — one bad frame per broadcast.

### Temporal story (matches developer's (a)/(b))

- **Pre-Phase 1a:** `InputState.sequence` was stuck at 0, so the filter `i.sequence > last_processed_sequence` always returned false; `_input_history` drained empty and the replay loop ran zero iterations. Bug latent, invisible.
- **Post-Phase 1a / Phase 4:** filter works correctly; history is retained; replay fires every broadcast. Bug becomes dominant jitter source.

### Why Phase 1f made it worse

Two interacting reasons, both downstream of F0:

1. Because replay doesn't integrate position, `new_error = pre_snap - post_replay` equals the **full snapshot delta** (~100 ms of motion), not true prediction error. 1f was smoothing a delta that was wrong by an order of magnitude — dragging the body backward at 20 Hz cadence.
2. Separately, 1f's `_correction_offset` drain subtracts from `skater.global_position` every physics tick. The same IK callsites (lines 752, 760, 802, 854) read that field live, so the drain became a per-tick blade perturbation *on top of* the 20 Hz F0 pop. A high-frequency wobble stacked on the broadcast-rate hitch.

Post-F0 fix, reason 1 collapses (prediction error becomes small) and 1f's 48-frame drain feels roughly correct — but likely still bikeshed-able. Keep 1f as a render-only offset in future if ever reintroduced (see remediation step 5).

## Secondary findings

### F1 — Host discards 11/12 inputs per batch but acks all 12

`remote_controller.gd:25-32, 34-45`. Host keeps only the newest input from each 12-input batch, applies it across 4 physics ticks, and writes `last_processed_host_timestamp = _latest_input.host_timestamp`. Client reconcile filter drops the 11 unsimulated inputs. Server state diverges from client prediction → reconciles keep firing. F0 is what *produces* visible jitter; F1 is what keeps F0 firing at 20 Hz.

### F2 — Replay starts from `server_state.facing`

`local_controller.gd:125`. Facing is deterministic from mouse history; seeding replay with server's facing (computed from stale mouse) diverges from the client's local trajectory. Post-F0, this becomes the next accuracy wedge.

### F3 — Non-deterministic replay: live mouse read

`skater_controller.gd:340-341` `_state_wrister_aim` reads `get_viewport().get_mouse_position()` directly rather than from `input.mouse_world_pos`. Replay uses live mouse whenever wrister-aim is entered in the unacknowledged window.

### F4 — `just_pressed` re-fires on host

`input_state.gd:7-14`, `local_input_gatherer.gd:39-42`. Host's `_latest_input` persists `shoot_pressed` / `slap_pressed` / `elevation_up` / `elevation_down` across 4 physics ticks; host can fire state transitions up to 4× per client press.

### F5 — Remote skater apply-order

`remote_controller.gd:93-109` — `set_blade_position` (line 100) runs before `set_upper_body_rotation` (line 101) and `set_facing` (line 102). The comment at line 97 acknowledges hand→blade order but not the body-rotation dependency. If `set_blade_position` uses the upper-body transform to orient the shaft mesh, it orients against the *previous* tick's rotation, then parent rotates under it — one-tick mis-orientation on every broadcast for remote skaters. Not the current reported symptom (that's on the local player), but a latent bug worth verifying and fixing in a follow-up.

### F6 — Dead Euler lerp of `state.rotation`

`remote_controller.gd:81, 95`. Host never writes `skater.rotation.x/z`, so the lerp is effectively zero on two axes; `set_facing` overrides `rotation.y` at line 102. Field is wire-transmitted but dead on arrival. Cleanup: drop from `SkaterNetworkState`.

### F7 — Extrapolation rejoin pop (Phase 1d polish)

`remote_controller.gd:64-75`. Velocity extrapolation caps at 50 ms but there's no soft-reconcile when fresh snapshots resume. Separate from the current symptom; defer.

### F8 — Reconcile save/restore neutralizes replay for 13 fields

`local_controller.gd:105-148`. The reconcile path saves 13 controller fields into `pre_*` locals *before* replay and unconditionally restores them *after* replay:

- Visual state: `_facing`, `_upper_body_angle`, `_lower_body_lag` (also pushed to skater at lines 146-148 via `set_facing` / `set_upper_body_rotation` / `set_lower_body_lag`).
- State machine: `_state`, `_shot_dir`, `_follow_through_timer`, `_follow_through_is_slapper`, `_locked_slapper_dir`, `_one_timer_window_timer`, `_charge_distance`, `_slapper_charge_timer`.
- Bookkeeping: `_prev_mouse_screen_pos`, `_prev_blade_dir`.

Replay mutates all of these via `_process_input`, then the restore discards the mutations. In effect, replay's only surviving outputs are `skater.velocity` (last input wins) and the post-replay blade/top_hand placement (which in current code is immediately overwritten by `_apply_blade_from_mouse(_current_input, 0.0)` at line 152). Everything else reverts to pre-reconcile values.

The comment at 108-110 justifies this as protection against replay leaking shot-state transitions, but the list is far broader than that concern requires — `_facing` / `_upper_body_angle` / `_lower_body_lag` have no reason to be in the list.

**Interaction with F0:** the save/restore is currently *masking* F0's effect on most fields. `pre_*` values happen to be approximately correct (they're the client's own prediction from the previous tick), so restoring them hides the fact that replay itself would have produced garbage. When F0 is fixed with kinematic integration, replay's output becomes legitimately correct; the restore then just throws away correct values and replaces them with values from one tick ago. That's mostly harmless (one-tick staleness is below perception) but it means:

1. **F0 fix is sufficient for the visible jitter.** Blade and top_hand aren't in the save list, so they benefit directly from integrated-body replay.
2. **F8 cleanup becomes a follow-up, not a blocker.** After F0 lands, the correct move is to trim the save/restore list to just the narrow set of state-machine fields that genuinely need protection (probably `_state` and the shot-completion timers, if anything — and only when they'd transition past a terminal state). Leaving it as-is is safe.
3. **Tempting false fix to avoid:** removing the save/restore *without* the F0 kinematic integration would expose the frozen-body replay corruption on all 13 fields, not just blade. Don't untangle these in the wrong order.

## Remediation sequence

Each step is land-and-measure. Stop after whichever brings `blade_jump_per_sec` within ~1.5× of offline baseline.

### 1. Integrate body position per replay tick (F0 — the fix)

**File:** `Scripts/controllers/local_controller.gd`.

At the replay loop (currently lines 129-130), add kinematic integration after each `_process_input`:

```gdscript
for input in _input_history:
    _process_input(input, input.delta)
    # Replay advances body kinematically so blade tracking, facing drift, and
    # upper-body twist see the same trajectory they saw in real time. Collisions
    # aren't re-run (too expensive and the ~50 ms replay window rarely crosses
    # walls); the next move_and_slide() nudges out any residual overlap.
    skater.global_position += skater.velocity * input.delta
```

This fix:
- Makes `_apply_blade_from_mouse`, `_apply_facing`, and `_apply_upper_body` evaluate against a moving body each replayed iteration — same trajectory they saw live.
- Shrinks `new_error = pre_snap - post_replay` from the full snapshot delta to true prediction drift (near zero in the common case).
- Restores the original intent of 1f smoothing if 1f is ever reintroduced — the correction offset would now reflect real error.

Why not `move_and_slide` per iteration:
- Cost: `move_and_slide` applies floor-snap and runs collision response. Running it ~12× per reconcile per physics tick is expensive.
- Double-application: resolved velocity from the original tick is already baked into `skater.velocity`; re-colliding would push further.
- Accuracy: 50 ms replay window × ~9 m/s = < 0.5 m — rarely crosses rink geometry. If collision-accurate replay becomes necessary later (e.g. puck-handling near walls), revisit with `PhysicsServer3D.body_test_motion`, which runs collision queries without committing the move.

Side effect: if Phase 1f is reintroduced later, `correction_frames = 48` was sized for the old regime (full snapshot delta). With tiny deltas, 48 frames will feel sluggish — retune.

Y-axis note: kinematic integration ignores floor-snap. Skaters are floor-constrained (`velocity.y ≈ 0` in steady state). If drift ever shows up, zero `skater.global_position.y` change explicitly during replay.

### 2. Queue all inputs on the host (F1)

**File:** `Scripts/controllers/remote_controller.gd`.

Replace the single `_latest_input` slot with a queue:
- `receive_input_batch` appends every input with `host_timestamp > last_processed_host_timestamp`, sorted by timestamp, deduplicated.
- `_drive_from_input` pops and processes at most one per physics tick; writes `last_processed_host_timestamp` only to the timestamp of the last input *actually simulated*.
- When queue empties, hold the latest-applied input as fallback without advancing `last_processed_host_timestamp`.

Expected: `reconcile_per_sec` drops toward offline baseline; F0 rarely triggers anyway after this.

### 3. Stabilize replay starting facing (F2)

**File:** `Scripts/controllers/local_controller.gd`. Drop `_facing = server_state.facing` at line 125 — keep `pre_facing` as the replay-start facing. Only meaningful after step 1 (replay actually converges now) and step 2 (history is complete).

### 4. Determinism cleanup (F3)

**File:** `Scripts/controllers/skater_controller.gd:340-341`. Replace `get_viewport().get_mouse_position()` with screen-space derived from `input.mouse_world_pos`, or add `mouse_screen_pos: Vector2` to `InputState`.

### 5. `just_pressed` normalization (F4)

Host consumes each `just_pressed` flag once per input; falls out naturally from step 2.

### 6. Phase 1f reintroduction — render-only (optional)

Only if visible snaps remain after steps 1–5. Apply the drain to a **cosmetic visual parent** or camera, not to `skater.global_position`, so IK math keeps reading the authoritative physics position.

### 7. Trim reconcile save/restore (F8)

**File:** `Scripts/controllers/local_controller.gd`. Once F0 (step 1) is verified smooth, the save/restore list can shrink. Default target: keep only `_state` and shot-completion timers (`_follow_through_timer`, `_follow_through_is_slapper`, `_one_timer_window_timer`) — the narrow set where replay-induced transitions genuinely need guarding. Drop `_facing` / `_upper_body_angle` / `_lower_body_lag` save/restore; let replay's now-correct output stand. Do **not** attempt before step 1 — doing so would expose F0's corruption on those fields. Measure `blade_jump_per_sec` / `reconcile_per_sec` before and after this trim; no regression expected.

### 8. Remote apply-order and cleanup (F5, F6, F7)

Separate follow-up commit. Reorder `_apply_state_to_skater` so rotations finalize before `set_blade_position`. Drop dead `state.rotation` field. Revisit 1d extrapolation rejoin.

## Verification

`NetworkTelemetry` counters already exist at `local_controller.gd:74, 154, 156`. Capture 30 s samples per preset.

| Metric | Target after step 1 | Target after step 2 |
|---|---|---|
| `blade_jump_per_sec` | within ~1.5× offline baseline | unchanged (already fixed) |
| `blade_reconcile_mag_avg` | drops sharply | drops further |
| `reconcile_per_sec` | unchanged (still firing) | drops toward offline baseline |

Procedure:
1. **Baseline** — offline + host → reference numbers.
2. **Pre-fix, client under `NetworkSimManager` Fair/Bad** — capture; expect high `blade_*` and `reconcile_per_sec`. Visually confirm 20 Hz blade hitch while skating straight + sweeping cursor.
3. **After step 1** — same test, blade should track smoothly with no periodic hitch. `blade_*` counters drop. `reconcile_per_sec` still high (F1 unaddressed).
4. **After step 2** — `reconcile_per_sec` drops, blade counters further reduced.
5. **Regressions to confirm no change on:**
   - Host-side local player (reconcile never runs for them — they're authority).
   - Remote skaters' visuals (fix 1 touches only `LocalController.reconcile`).
   - Reconcile-stressed cases: rapid direction changes, wall collisions, body checks.
6. **Deferred test:** no unit test today covers reconcile replay. Adding one in `tests/unit/game/` that feeds a known `_input_history` + `server_state` and asserts `skater.global_position` + `blade_position` after reconcile match the same inputs applied to a moving body is worth considering. Low priority — a visual-timing bug is easier to verify by repro than by assertion.

Stop condition: client `blade_jump_per_sec` within ~1.5× offline baseline across Fair + Bad presets, carrying and not carrying the puck.

## Execution workflow

Copy this file to the developer's local machine. Open a Claude Code session in the `hockey-game` repo on branch `claude/fix-blade-jitter-jMbCW`. Paste the plan in as context and execute **one step at a time**, stopping between steps to measure.

Suggested prompt template for each step:

> Read `<plan file path>`. Implement **step N only**. Do not touch anything outside the files listed for that step. After the edit, stop and wait — I will pull, run the game with `NetworkSimManager` on Fair/Bad presets, and capture `NetworkTelemetry` numbers before approving step N+1.

Why one at a time:
- Step 1 is the fix for the visible symptom. Verifying it resolves the jitter before moving on confirms F0 was correctly diagnosed.
- Step 2 is a separate diagnosis (F1 — reconcile frequency). Landing it on top of an unverified step 1 makes attribution impossible.
- Step 7 (F8 save/restore trim) is explicitly ordered after step 1 because trimming first would expose the F0 bug on more fields.

Scene files (`.tscn`) shouldn't need edits for any step — per `CLAUDE.md`, those are the developer's to edit in the Godot editor. If a step's plan calls for a scene change, flag it back and let the developer apply it.

## Critical files

- `Scripts/controllers/local_controller.gd` — reconcile / replay loop (F0 fix site, step 1).
- `Scripts/controllers/remote_controller.gd` — host-side input dedup (step 2); remote apply-order (F5).
- `Scripts/controllers/skater_controller.gd` — `_process_input`, `_apply_blade_from_mouse` (748-819), `_apply_movement` (no `move_and_slide`), wrister-aim determinism (340-351).
- `Scripts/input/input_state.gd`, `Scripts/input/local_input_gatherer.gd` — wire format, just_pressed semantics.
- `Scripts/networking/skater_network_state.gd` — dead `rotation` field (F6) can be dropped in follow-up.
- `NETWORKING_REFACTOR_PLAN.md` — Phase 1a/1d/1f spec; 1f needs render-only reimplementation if ever revisited.
