# CLAUDE.md

Context for Claude about the Mitts project.

## Workflow

Complex features (AI state machines, new systems, architectural changes) are designed first in Claude.ai chat mode, where the developer can iterate on ideas without implementation pressure. The resulting plan is then handed to Claude Code to implement against the actual codebase. When a session starts with a plan document, treat it as the agreed design — ask clarifying questions before deviating from it.

**Before every commit:** update Known Issues in this file. When a feature ships to players, update README's What's In / Planned. When a build stage completes, update ARCHITECTURE's Build Status table.

**Never push to `main` without the user testing locally first.** Feature branches (e.g. `claude/*`) may be pushed after committing so the user can pull and test on their machine. For `main`, always stop at commit and wait for explicit confirmation before running `git push`.

**Scene files (`.tscn`) and resource files (`.tres`) are edited by the user, not Claude.** Godot's text formats are error-prone to edit — node unique IDs, sub-resource references, and property ordering can silently break them. Describe the change and let the user make it in the Godot editor.

**You cannot run the game or the test suite.** The GUT panel runs in the Godot editor; the headless CLI does not work in this environment. After touching domain code, note which test files cover the affected area and ask the user to run them. For gameplay or networking changes, describe what to test in a local session and wait for the user to verify.

## What This Is

A 3v3 arcade hockey game built in Godot 4.6.2 (GDScript, 3D). Online multiplayer — one player per machine, each with their own camera and local simulation. Prioritizes feel over realism: deep stickhandling, multiple shot types, satisfying puck physics.

## Tech Stack

- **Engine:** Godot 4.6.2 (Jolt Physics)
- **Language:** GDScript
- **Physics tick:** 240 Hz
- **Testing:** GUT v9.6.0 under `addons/gut/`; tests in `tests/unit/` (rules/, state/, game/). Run via GUT panel in the Godot editor.
- **CI:** `.github/workflows/test.yml` runs GUT on every push and PR; `deploy.yml`'s export job gates on tests passing.
- **Deployment:** GitHub Actions → Windows + Linux export → GitHub Releases (tag: `latest`)

## Layer Architecture

The codebase is split into three layers; dependencies always flow downward:

- **Domain** (`Scripts/domain/`) — pure GDScript, no engine APIs. Rule classes (static methods), the game state machine (RefCounted), enums, and game-rule constants. Fully unit-testable without Godot.
- **Application** — `GameManager` (autoload orchestrator), controllers, `ActorSpawner`, and six RefCounted collaborators. Use the domain to make decisions; reach into infrastructure to execute them.
- **Infrastructure** — actor nodes (Skater, Puck, Goalie), `NetworkManager`, UI. The Godot-side glue.

Lower layers never reach up: actors take their collaborators via `setup()` (e.g. `Puck.set_team_resolver(Callable)`); controllers take a `game_state: Node` exposing `is_host()` / `is_movement_locked()`). Upward communication is by signals that the orchestrator listens to.

## Autoloads

Initialized in this order: `PlayerPrefs` → `Constants` → `BuildInfo` → `NetworkManager` → `NetworkSimManager` (`network_sim.gd`, no class_name) → `GameManager`. `NetworkManager._ready()` is a no-op; the menu drives initialization.

## Confusing Boundaries

**`GameStateMachine` vs `PhaseCoordinator` vs `GameManager`:** `GameStateMachine` is a domain `RefCounted` — pure state, no signals, no engine refs, lives on both host and client. `PhaseCoordinator` owns phase-entry side effects (puck lock, goalie reset, faceoff teleport) and the goal pipeline; emits signals upward. `GameManager` wires everything together and is the only one that touches `NetworkManager`.

**`constants.gd` vs `game_rules.gd`:** `constants.gd` (autoload) holds engine-facing values: collision layers/masks, network port, input/state rates, physics tick. `game_rules.gd` (domain) holds game-rule values: rink geometry, icing duration, faceoff positions, ice friction.

**`WorldStateCodec`** is not a pure codec — it also emits `phase_changed` / `game_over_triggered` / `period_changed` / `clock_updated` / `shots_on_goal_changed` / `queue_depth_feedback` when decoding. GameManager connects to these so it can react to authoritative host updates on clients.

**`StateBufferManager`** lives in `Scripts/game/`, not `Scripts/networking/`. Host-only pre-allocated ring buffers (720 slots = 3s at 240 Hz) for all actors. Owned by GameManager; WorldStateCodec reads `latest_*()` for broadcasts; lag-comp rewinds use `get_state_at()`.

**`GameManager` wires six collaborators:** `PlayerRegistry`, `WorldStateCodec`, `ShotOnGoalTracker`, `HitTracker`, `PhaseCoordinator`, `SlotSwapCoordinator`. Documentation that says "five" is stale.

## Networking Invariants

These are non-obvious constraints that cause subtle bugs if violated. Rates and wire format are in `ARCHITECTURE.md`.

**`_carrier_peer_id` is managed exclusively by reliable RPCs, never by world state.** Unreliable packet ordering conflicts with locally-predicted carrier transitions.

**`rtt_ms` in pickup, shot, and hit claims is the raw unaveraged latest sample** (`latest_rtt_ms` from `ClockSync`), not the smoothed average. Rewind depth must track the actual current round-trip.

**Pickup claim rewind uses separate timestamps for blade and puck.** `blade_timestamp` rewinds the skater snapshot; `puck_timestamp` rewinds the puck path. They diverge when the puck was released under lag.

**Trajectory prediction exits on post contact and puck-goalie contact**, not only on carrier-change RPCs. Both controllers call `end_trajectory_prediction()` directly on the relevant physics signal.

**Goalie state transitions and shot reactions are sent via reliable RPCs** (`state_transitioned`, `shot_reaction_started` on `GoalieController`). Clients play a local `_client_reaction_timer` from the RPC payload. Do not rely on interpolation alone for goalie reactions.

**Reconcile saves and restores only narrow shot-state fields** (`_state`, follow-through timers, one-timer window). Visual and charge fields come from replay output. Server authority on shot state: if `server_state.shot_state` differs after replay, server wins — `_state` and `_charge_distance` are overwritten.

**Mouse position is seeded from the first replayed input at replay start and the last at replay end.** Wrister-aim charge accumulation is a function of sweep distance; both endpoints must match for deterministic replay across reconcile.

**Board collision is clamped in the reconcile replay loop** via `GameRules.clamp_to_rink_inner` after each `global_position += velocity * delta` step. Without this, board-bounce divergence triggers a feedback loop of reconciles.

**Blade and top-hand positions on remote skaters are extrapolated from the body velocity field**, not from derived position deltas. Dividing position deltas by client receive-time gaps amplifies jitter into visible blade jumps.

**Body check impulse is injected into the reconcile replay at the matching `host_timestamp`**, so replay reproduces the post-collision trajectory without oscillation.

**`LocalController.reconcile` is blocked during dead-puck phases.** `on_faceoff_positions` RPC is the authoritative source of skater positions during locked phases.

**Client inputs are delayed `INPUT_DELAY_FRAMES = 2` physics ticks (≈8ms) before being applied**, then stamped with `estimated_host_time()` at apply-time. This keeps the reconcile echo cursor and RemoteController sort order correct on the host.

**The pending input queue is drained on both `is_movement_locked()` and `is_input_blocked()` phases.** Both gates must be checked — draining only on movement-locked leaves stale inputs from input-blocked phases (shot cancel, etc.) flooding through when the phase lifts.

**Trajectory prediction uses a three-zone response, not a single hard snap.** Each broadcast computes `latency_corrected.position = state.position + state.velocity * rtt_s` (full-RTT forward correction) then compares the distance to two thresholds (`trajectory_soft_blend_threshold` = 0.3 m, `trajectory_hard_snap_threshold` = 1.5 m): below 0.3 m — soft position blend (`position_correction_blend` = 0.1) plus velocity blend; 0.3–1.5 m — velocity-only blend, no position change; above 1.5 m — hard snap both position and velocity and clear the state buffer. This eliminates the visible pop that previously occurred at exactly 1.5 m.

**Body check impulse uses `body_check_impulse_applied(impulse)`, not `body_checked_player`.** `Skater` emits `body_check_impulse_applied` with the complete velocity delta from `_resolve_player_collisions()` — both attacker rebound and victim transfer. `LocalController` connects to this signal and injects the complete delta into reconcile replay at the matching `host_timestamp`. The old `body_checked_player` signal only captured attacker rebound, causing consistent under-correction.

**`ClockSync` does pure NTP only — do not add queue-depth feedback to it.** The clock offset (`_offset`) is computed from ping/pong samples alone: collect up to 8 samples, drop the 2 highest-RTT outliers, average the rest, EMA-smooth (α=0.3) after `is_ready`. `estimated_host_time()` adds a monotone floor so time never goes backward. Do not nudge `_offset` for any other reason (buffer depth, queue length, etc.) — any unbounded integrator on the clock drifts without limit and makes the offset display useless. On same-machine sessions the offset will be approximately equal to the time between host start and client connection (e.g. +1.3 s if the client connected 1.3 s after the host started) — this is correct after the session-relative timestamp change. The important invariant is that the offset is **stable** (not drifting over time); ongoing drift is a code bug. Buffer depth is managed separately: the client receive buffer via `_adapt_interpolation_delay()` in each controller; the host input queue self-stabilises once the NTP clock is accurate.

**`facing` in `SkaterNetworkState` is `Vector2` (XZ packed as XY), not `Vector3`.** Both `WorldStateCodec` and `BufferedStateInterpolator.lerp_facing` use the same compass convention: extract angle via `atan2(x, y)` (bearing from +Z/forward axis) and reconstruct with `Vector2(sin, cos)`. Do not pass a `Vector3` facing direction to `lerp_facing`. `RemoteController` and `StateBufferManager` use `BufferedStateInterpolator.hermite_angle` for C1-continuous facing and upper-body rotation interpolation, driven by `facing_angular_velocity` and `upper_body_angular_velocity` fields on `SkaterNetworkState` (encoded as s16, scale `PI * 10` rad/s, at wire offsets 27–28 and 29–30 of the 37-byte skater block).

**All interpolators use host-capture timestamps, not client arrival time.** `apply_network_state` / `apply_state` on `RemoteController`, `PuckController`, and `GoalieController` each take a `host_ts: float` parameter (decoded from the world-state header) and buffer it as the snapshot timestamp. `render_time = NetworkManager.estimated_host_time() - interpolation_delay`. Using client arrival time instead causes same-frame world-state packets to silently clobber each other and decouples the render timeline from the simulation timeline.

## Where New Code Goes

| Task | Location |
|------|----------|
| New game rule or geometry constant | `domain/config/game_rules.gd` |
| New pure stateless math or rule | New file in `domain/rules/` + GUT test |
| New per-player stat | `PlayerStats` → wire format → `WorldStateCodec` |
| New RPC | `NetworkManager` (define) → emit a signal → `GameManager._wire_network_signals()` (connect) |
| New phase-entry side effect | `PhaseCoordinator` |
| New controller behavior | Method on `SkaterController`; `GameManager` calls it, never pokes internals directly |

## Code Conventions

**Strong typing everywhere.** Typed arrays (`Array[BufferedPuckState]`), typed function signatures, typed variables. Never leave a type annotation off when it can be provided. Prefer `var state: PuckNetworkState` over `var state`.

**Godot naming conventions.** `snake_case` for variables and functions, `PascalCase` for class names, `SCREAMING_SNAKE_CASE` for constants.

**Separation of concerns.** Physics bodies (`Puck`, `Skater`) expose a clean API. Controllers drive them. `GameManager` owns spawning and world state. `NetworkManager` owns RPCs. Don't reach across these boundaries casually.

**Network API uses typed objects, not raw arrays.** Functions accept `SkaterNetworkState` / `PuckNetworkState` directly. Serialization happens only at the RPC boundary.

**Get it working, then tune numbers.** Use `@export` on tunable parameters so values can be adjusted in the editor. Don't prematurely optimize or bikeshed on constants before the mechanic runs.

**Don't shy away from complexity when it improves feel.** This project already has full client-side prediction with input replay, buffered interpolation, and puck trajectory prediction with reconciliation. If adding a complex system will make the game feel meaningfully better to play, it's worth doing — think it through carefully first, then implement it properly.

## Launch Modes

All start paths go through `MainMenu.tscn`. `NetworkManager._ready()` does nothing — the menu calls `start_offline()`, `start_host()`, or `start_client(ip)` directly. These set up ENet but defer world spawning. `Hockey.tscn`'s root node runs `game_scene.gd`, whose `_ready()` calls `NetworkManager.on_game_scene_ready()`, which emits `host_ready` on hosts; `GameManager` listens and calls `on_host_started`. Client world spawn is triggered by the `client_connected` signal from `_on_connected_to_server()`.

NetworkManager → GameManager communication is signal-based: every RPC / ENet callback emits a typed signal, and GameManager wires all connections once in `_ready()` via `_wire_network_signals()`. The only downward data flow is `NetworkManager.set_world_state_provider(Callable)`.

## Distribution

Playtester builds ship via GitHub Releases (`latest` tag). `deploy.yml` computes `VERSION=0.1.<git rev-list --count HEAD>`, rewrites the placeholder `"dev"` in `Scripts/game/build_info.gd` to that string before export, and publishes with the version as the release name. The main menu's `UpdateChecker` polls the GitHub API on startup and prompts re-download when stale. No in-game patching — Steam (SteamPipe) is the long-term plan. Don't add an in-game downloader/launcher before Steam.

## Known Issues / Planned Work

- **Goalie reactive saves not yet implemented:** glove saves, shoulder/body saves, and stick poke coverage are planned. The stick is currently disabled (`stick_enabled = false` on `goalie.gd`) — it can be re-enabled once it has proper positional behavior.
- **Top-hand ROM values are first-principles baselines:** `rom_forehand_angle_max_deg` (90°), `rom_backhand_angle_max_deg` (120°), `rom_forehand_reach_max` (0.45 m), `rom_backhand_reach_max` (0.70 m), `stick_length` (1.30 m, shaft-only butt-to-heel), `blade_length` (0.30 m), `shoulder_offset` (0.22 m) are anatomical defaults and will need playtest tuning. `upper_body_twist_ratio = 0.8` rotates the torso with the blade angle, effectively shrinking the angular demand on the top hand.
- **Stick / blade geometry split:** The IK rigid rod is the *shaft* only (hand → blade heel). The blade mesh is offset forward by `blade_length * 0.5` so the mesh center is mid-blade. `Skater.get_blade_contact_global()` returns mid-blade world position. If the mesh length changes in `Scenes/Skater.tscn`, keep `blade_length` in sync so the contact point and pickup zone stay at mid-blade.
- **IK tuning knobs:** `hand_y_max` (0.30 m) caps hand rise in the CLOSE regime. Arm bone lengths (`upper_arm_length = 0.44`, `forearm_length = 0.46`) must sum to more than `sqrt(drop² + rom_backhand_reach_max²)` (≈ 0.87 m at current drop) to avoid visible arm stretch at full backhand extension. `bottom_hand_grip_fraction` (0.25) and `bh_release_angle_deg` (67°) / `bh_release_angle_band_deg` (15°) control where the bottom hand grips and when it releases to a one-handed rest pose.
- **Shot release snapback (host-side Jolt bug):** `puck.release()` fires from the previous frame's pinned position rather than the current blade position, combined with a Jolt freeze→unfreeze transition artifact. Causes a 1-frame snap at release visible on the host, unrelated to networking. Deferred to a dedicated shot mechanics pass.
- **Reconcile replay skips skater-vs-skater collisions:** `LocalController.reconcile` replays inputs through movement code but does not re-run `move_and_slide` for player-player collisions. A body-check that occurs during the replay window is injected as a velocity impulse at the matching `host_timestamp` (via `body_check_impulse_applied`), which approximates the post-collision trajectory. Full re-simulation would require running all skater bodies through Jolt together in the replay loop — expensive and likely to introduce its own divergence. The impulse injection approach is the correct trade-off; do not attempt to add full collision replay without a careful design pass.
- **Input batch size is partially adaptive:** The 1-second loss-rate measurement window is fairly noisy on marginal connections (~40 samples at 40 Hz); a sliding window rather than a resetting one would improve accuracy.
- **`SkaterController` is too large (~1073 lines):** The state machine, shot charging/release, blade IK calls, arm mesh updates, and body check handling should be split across a `SkaterShotStateMachine` and a `SkaterIKCoordinator`, leaving `SkaterController` as a thin coordinator. Needs care because `LocalController` and `RemoteController` inherit from it.
- **`WorldStateCodec` is a leaky abstraction:** It emits `phase_changed`, `game_over_triggered`, `clock_updated`, and other game-state signals from inside `decode_world_state`. A codec should decode into typed objects; a separate dispatcher should emit signals. The current design makes it hard to follow where `phase_changed` originates.
- **Reconcile replay doesn't skip non-movement inputs:** Every unconfirmed input replays through the full `_process_input` pipeline — state machine dispatch, IK solve, aiming update. At 100 ms RTT (~24 inputs) this is fine. At 500 ms on bad WiFi (~120 inputs) it becomes noticeable. Inputs that can't affect position/velocity (dead-phase frames, menu-only inputs) could be detected and short-circuited in the replay loop.
- **No integration test for the game loop:** The domain layer is well-tested but nothing covers faceoff → play → goal → reset end-to-end. This is the code path that silently breaks when `PhaseCoordinator` or `GameStateMachine` is refactored.
- **Uniform rendering should move to UV-mapped texture painting:** The current system applies solid colors via `material_override` and stamps numbers/stripes as overlay `QuadMesh` nodes. The right approach is UV-unwrapped meshes (jersey, pants, gloves, socks) with a single painted `ImageTexture` per mesh — `Image.fill_rect` for stripe bands, glyph stamping for name/number, all composited into one atlas at spawn time. Prerequisites: UV-unwrap the skater meshes in Blender so each face (back panel, front panel, sleeves, etc.) has a predictable UV island; define matching UV region constants in `JerseyTextureGenerator`; replace `set_player_color` / `set_jersey_stripes` with a single `paint_and_apply_textures` call. Eliminates all overlay quad nodes and z-fighting.
