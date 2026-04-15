# CLAUDE.md

Context for Claude about the HockeyGame project.

## Workflow

Complex features (AI state machines, new systems, architectural changes) are designed first in Claude.ai chat mode, where the developer can iterate on ideas without implementation pressure. The resulting plan is then handed to Claude Code to implement against the actual codebase. When a session starts with a plan document, treat it as the agreed design — ask clarifying questions before deviating from it.

**Before every commit:** update this file, `README.md`, and `ARCHITECTURE.md`. New files go in the Key Files table. Completed work moves out of Known Issues here. New known issues get added. README's What's In / Planned sections and ARCHITECTURE's Build Status table should reflect current state.

**Scene files (`.tscn`) are edited by the user, not Claude.** Godot's scene format is error-prone to edit as text — node unique IDs, sub-resource references, and property ordering can silently break the scene. When a task requires scene changes, describe exactly what to add or modify and let the user make the edits in the Godot editor.

## What This Is

A 3v3 arcade hockey game built in Godot 4.6.2 (GDScript, 3D). Online multiplayer — one player per machine, each with their own camera and local simulation. Prioritizes feel over realism: deep stickhandling, multiple shot types, satisfying puck physics.

## Tech Stack

- **Engine:** Godot 4.6.2 (Jolt Physics)
- **Language:** GDScript
- **Physics tick:** 240 Hz
- **Testing:** GUT v9.6.0 under `addons/gut/`; tests in `tests/unit/` run via the GUT panel. The headless CLI command (`godot --headless -s addons/gut/gut_cmdln.gd -gexit`) does not work in this environment — always run tests via the GUT panel in the Godot editor.
- **CI:** `.github/workflows/test.yml` runs GUT on every push and PR; `deploy.yml`'s export job gates on tests passing
- **Deployment:** GitHub Actions → Windows export → GitHub Releases (tag: `latest`, updates on every push to main)

## Layer Architecture

The codebase is split into three layers; dependencies always flow downward:

- **Domain** (`Scripts/domain/`) — pure GDScript, no engine APIs. Rule classes (static methods), the game state machine (RefCounted), enums, and game-rule constants. Fully unit-testable without Godot.
- **Application** — `GameManager` (autoload orchestrator), controllers, `ActorSpawner`. Use the domain to make decisions; reach into infrastructure to execute them.
- **Infrastructure** — actor nodes (Skater, Puck, Goalie), `NetworkManager`, UI. The Godot-side glue.

Lower layers never reach up: actors take their collaborators via `setup()` (e.g. `Puck.set_team_resolver(Callable)`, controllers take a `game_state: Node` exposing `is_host()` / `is_movement_locked()`). Upward communication is by signals that the orchestrator listens to (e.g. `PuckController.puck_picked_up_by(peer_id)`).

## Networking Architecture

Authoritative host model. The host runs all physics. Clients predict locally and reconcile against server state. See `ARCHITECTURE.md` for full detail.

**Rates:** inputs 60 Hz unreliable (client → host); world state 20 Hz unreliable (host → clients); events reliable RPCs.

**Skaters:** `LocalController` predicts + reconciles (reset + replay on error). `RemoteController` drives from input on host, interpolates buffered snapshots (100ms delay) on clients.

**Puck:** three client-side modes — local carrier (pinned to blade), trajectory prediction (Jolt runs client-side after release, soft-reconciled each broadcast), interpolation (100ms buffer, position only). `_carrier_peer_id` is managed exclusively by reliable RPCs, never by world state, to avoid unreliable ordering conflicts.

**Goalies:** AI runs on host only. Clients interpolate via `BufferedGoalieState` (100ms delay). `tracking_speed` is the master difficulty knob — lower = more positional lag = easier to beat.

**Game flow:** `GamePhase` FSM lives in `GameStateMachine` (domain `RefCounted`). Host-driven: `PLAYING → GOAL_SCORED → FACEOFF_PREP → FACEOFF → PLAYING`. Dead-puck phases gate all movement via `_game_state.is_movement_locked()` injected into controllers at `setup()` time. `LocalController.reconcile` is blocked during locked phases — `on_faceoff_positions` RPC is authoritative for faceoff positions.

**Controller API pattern:** `GameManager` calls `controller.teleport_to(pos)` and `controller.on_puck_released_network()` — never touches skater internals directly. Add methods to `SkaterController` rather than poking internals from `GameManager`.

**Ghost mechanic:** Offsides and icing are enforced via a ghost mode rather than stoppages. Ghost skaters go transparent, can't interact with the puck or other players (collision layers zeroed), and can still move freely. Offsides: skater in offensive zone while puck hasn't crossed the blue line → ghost until they retreat or puck enters the zone. Icing: puck shot from own half past opponent goal line → entire team ghosted for `ICING_GHOST_DURATION` (3s) or until the other team picks up the puck. Host computes ghost state in `GameManager._physics_process`; clients predict offsides locally, receive authoritative ghost state (including icing) via world state.

**World state layout:** `[peer_id, skater_state_array, ..., puck_position, puck_velocity, puck_carrier_peer_id, goalie0_state[5], goalie1_state[5], score0, score1, phase, period, time_remaining_secs]`

## Key Files

### Domain (pure GDScript, no engine APIs)

| File | Role |
|------|------|
| `domain/state/game_phase.gd` | `class_name GamePhase`; nested `enum Phase { PLAYING, GOAL_SCORED, FACEOFF_PREP, FACEOFF, END_OF_PERIOD, GAME_OVER }` |
| `domain/state/game_state_machine.gd` | RefCounted FSM. Owns phase/timer, scores, current_period, time_remaining (period clock), player slot registry, icing state; host drives via `tick(delta)`, clients sync via `apply_remote_state(...)` |
| `domain/config/game_rules.gd` | Game-rule constants: timings, rink geometry, blue/goal line Z, icing duration, faceoff positions, max players, ice friction |
| `domain/rules/phase_rules.gd` | `is_dead_puck_phase`, `is_movement_locked` |
| `domain/rules/player_rules.gd` | Team balancing, HSV color generation, faceoff position lookup |
| `domain/rules/infraction_rules.gd` | `is_offside`, `check_icing` |
| `domain/rules/puck_collision_rules.gd` | Deflection reflection, body-check/body-block velocity, poke-strip direction, `can_poke_check` eligibility |
| `domain/rules/skater_movement_rules.gd` | Thrust scaling, friction, max-speed clamp with puck-carry penalty |
| `domain/rules/shot_mechanics.gd` | Wrister / slapper power + direction + elevation; `should_release_on_wall_pin` |
| `domain/rules/goalie_behavior_rules.gd` | Shot detection, defensive zone detection, Buckley depth chart, lateral X target |
| `domain/rules/charge_tracking.gd` | Wrister aim charge accumulation with direction-variance reset |
| `domain/rules/reconciliation_rules.gd` | Thresholds for skater reconcile and puck hard-snap |
| `domain/rules/top_hand_ik.gd` | 1-bone inverse kinematics for the stick's top hand. Given a desired blade target and a fixed stick length, solves (hand, blade) respecting an asymmetric ROM (small forehand / large backhand reach). Two regimes: FAR extends the hand in XZ (ROM-clamped); CLOSE raises the hand's Y so the stick tilts vertically and the blade tucks in near the body. Blade-first feel: blade lands on target when reachable, clips along aim line when not. |
| `domain/rules/two_bone_ik.gd` | Analytical 2-bone IK used to render the arm. Given shoulder, hand, two bone lengths, and a pole hint, returns the elbow position so `|shoulder − elbow| = upper_len` and `|elbow − hand| = forearm_len`. |

### Application (orchestration)

| File | Role |
|------|------|
| `game/game_manager.gd` | Autoload orchestrator. Owns the GameStateMachine, maintains the runtime player registry, routes infrastructure events into domain calls, executes domain decisions. Exposes `is_host()` / `is_movement_locked()` for controllers via duck typing. |
| `game/actor_spawner.gd` | Scene instantiation + `add_child` + controller `setup()` calls. Returns raw nodes; GameManager does game-level wiring. |
| `controllers/local_controller.gd` | Local player: input gathering, prediction, reconciliation. Takes `game_state` via setup; calls `InfractionRules.is_offside` directly for client-side ghost prediction. |
| `controllers/remote_controller.gd` | Remote players: server-side input driving, client-side interpolation |
| `controllers/puck_controller.gd` | Puck: emits `puck_picked_up_by` / `puck_released_by_carrier` / `puck_stripped_from` signals (via injected peer_id resolver) for GameManager to consume; handles client prediction + interpolation |
| `controllers/skater_controller.gd` | Base class: state machine, movement, shooting, blade control. Delegates blade placement to `TopHandIK.solve` with fixed `stick_length` and ROM exports. Delegates other math to domain rules. |
| `controllers/goalie_controller.gd` | Goalie AI: state machine (STANDING/BUTTERFLY/RVH_LEFT/RVH_RIGHT) driving positioning via `GoalieBehaviorRules` |
| `controllers/goalie_body_config.gd` | Data class holding per-state body part positions and rotations |

### Infrastructure (engine integration)

| File | Role |
|------|------|
| `networking/network_manager.gd` | Autoload. RPC definitions, connection management, state broadcast timing |
| `actors/puck.gd` | RigidBody3D: pickup zone, deflection, carrier following (server only). Accepts a `team_resolver: Callable` so it doesn't reach into GameManager for team checks. |
| `actors/skater.gd` | CharacterBody3D: blade/top-hand/facing/upper-body API, ghost mode toggling. `shoulder` Marker3D anchors the top hand on the opposite side from the blade (right-shoulder for a left-handed shooter). `top_hand` Marker3D is the moving IK output; created programmatically on `_ready` if not present in the scene. Two arm meshes (`UpperArmMesh` / `ForearmMesh`) are auto-created the same way and positioned each tick by `update_arm_mesh()` via `TwoBoneIK.solve_elbow`. Arm meshes are included in ghost-mode transparency. |
| `actors/goalie.gd` | Goalie body API: exposes position, rotation, body part config methods |
| `actors/hockey_goal.gd` | Goal mesh + goal sensor Area3D; emits `goal_scored` signal |
| `actors/hockey_rink.gd` | Procedural rink geometry (@tool): walls, corners, ice surface, markings |
| `game/constants.gd` | Engine-facing constants only: collision layers/masks, network port, input/state rates, physics tick. Game-rule constants live in `domain/config/game_rules.gd`. |
| `game/team.gd` | Team object: defended goal, goalie controller |
| `game/player_record.gd` | Per-player data: peer_id, slot, team, skater, controller, faceoff_position |
| `networking/buffered_skater_state.gd` | Timestamped SkaterNetworkState for interpolation buffer |
| `networking/buffered_puck_state.gd` | Timestamped PuckNetworkState for interpolation buffer |
| `networking/buffered_goalie_state.gd` | Timestamped GoalieNetworkState for interpolation buffer |
| `networking/goalie_network_state.gd` | Serializable goalie state: position, rotation, state enum, five_hole_openness |
| `networking/skater_network_state.gd` | Serializable skater state: position, velocity, facing, blade, top_hand, input sequence, is_ghost |
| `networking/puck_network_state.gd` | Serializable puck state: position, velocity, carrier peer ID |
| `input/input_state.gd` | InputState data object: all per-tick input fields (move, mouse, shoot, brake, elevation, etc.) |
| `input/local_input_gatherer.gd` | Populates InputState from local hardware; accumulates just_pressed between ticks |
| `ui/game_camera.gd` | Per-player camera: weighted anchor (player, puck, mouse, attacking goal), zoom, rink clamping |
| `ui/hud.gd` | Scorebug HUD: receives scores via `score_changed(score_0, score_1)` signal payload; polls `skater.is_elevated` each frame |
| `ui/main_menu.gd` | Main menu: host/join/offline buttons + IP input, calls `NetworkManager.start_*()`, transitions to `Hockey.tscn` |
| `game/game_scene.gd` | Hockey scene init: calls `NetworkManager.on_game_scene_ready()` in `_ready()` to trigger world spawn |

### Tests

| File | Role |
|------|------|
| `tests/unit/rules/` | GUT tests for each rule class — ~130 tests covering domain logic |
| `tests/unit/state/` | GUT tests for `GameStateMachine` — phase transitions, icing, ghost computation |

## Code Conventions

**Strong typing everywhere.** Typed arrays (`Array[BufferedPuckState]`), typed function signatures, typed variables. Never leave a type annotation off when it can be provided. Prefer `var state: PuckNetworkState` over `var state`.

**Godot naming conventions.** `snake_case` for variables and functions, `PascalCase` for class names, `SCREAMING_SNAKE_CASE` for constants.

**Separation of concerns.** Physics bodies (`Puck`, `Skater`) expose a clean API. Controllers drive them. `GameManager` owns spawning and world state. `NetworkManager` owns RPCs. Don't reach across these boundaries casually.

**Network API uses typed objects, not raw arrays.** Functions accept `SkaterNetworkState` / `PuckNetworkState` directly. Serialization to/from arrays happens only at the RPC boundary.

**Get it working, then tune numbers.** Implement the mechanic correctly first. Use `@export` on tunable parameters so values can be adjusted in the editor. Don't prematurely optimize or bikeshed on constants before the thing actually runs.

**Don't shy away from complexity when it improves feel.** This project already has full client-side prediction with input replay, buffered interpolation, and puck trajectory prediction with reconciliation. If adding a complex system will make the game feel meaningfully better to play, it's worth doing — think it through carefully first, then implement it properly.

## Launch Modes

All start paths go through `MainMenu.tscn`. `NetworkManager._ready()` does nothing — the menu calls `start_offline()`, `start_host()`, or `start_client(ip)` directly. These set up ENet but defer world spawning. `Hockey.tscn`'s root node runs `game_scene.gd`, whose `_ready()` calls `NetworkManager.on_game_scene_ready()`, which triggers `GameManager.on_host_started()` on the host side. Client world spawn is triggered by `_on_connected_to_server()` as before.

## Known Issues / Planned Work

- **RVH early trigger:** `_is_puck_in_defensive_zone()` fires RVH when the puck is within `zone_post_z` of the goal line at a horizontal angle ≥ `rvh_early_angle` (default 60°), matching the Buckley chart's corner zones. Tune `rvh_early_angle` if transition feels too early or late.
- **Goalie reactive saves not yet implemented:** glove saves, shoulder/body saves, and stick poke coverage are all planned. The stick is currently disabled (`stick_enabled = false`) — it can be re-enabled once it has proper positional behavior rather than acting as a static seal.
- **Poke check / body check / catch vs deflect thresholds need multiplayer tuning:** `deflect_min_speed`, `poke_strip_speed`, `poke_carrier_vel_blend`, `body_check_strip_threshold`, `body_check_transfer`, and related exports were set from first principles and need tuning under real network conditions.
- **Icing ghost duration needs tuning:** `ICING_GHOST_DURATION` (3s) was set as an initial value. May need adjustment based on how punishing icing feels in practice — shorter if too harsh, longer if teams ice with impunity.
- **Hybrid icing race uses goal line as reference point:** `check_icing_for_loose_puck` compares each team's closest player's distance to `±GOAL_LINE_Z`. In the real NHL the race ends at the defensive-zone faceoff dot, not the goal line — if the feel is off (too easy or too hard to wave off icing), consider adding a `ZONE_FACEOFF_DOT_Z` constant and using that as the reference instead.
- **Slapper blade pose ignores stick_length:** uses a fixed offset (`slapper_blade_x`, `slapper_blade_z`) from the shoulder, so the stick during a slapper wind-up may not match `stick_length` exactly. The hand snaps to the shoulder during slapper pose; the visible stick may read slightly short/long. Tune those values (or route through IK) once the baseline feels right.
- **Handedness flip untested:** `is_left_handed` exports on Skater switch the shoulder anchor between +X and −X, and the IK uses `blade_side_sign` throughout. Only the lefty pose has been verified in play; a righty skater should mirror correctly per GUT tests, but confirm in scene before setting a mix of handedness. Also: `ShotMechanics.release_wrister`'s backhand detection still uses `shoulder.x` as its threshold, which has moved to the opposite side of the body — if the forehand/backhand boundary feels off, switch detection to body centerline (`blade.x * blade_side_sign < 0`).
- **Top-hand ROM values are first-principles baselines:** `rom_forehand_angle_max_deg` (90°), `rom_backhand_angle_max_deg` (120°), `rom_forehand_reach_max` (0.45 m), `rom_backhand_reach_max` (0.70 m), `stick_length` (1.30 m, shaft-only butt-to-heel), `blade_length` (0.30 m), `shoulder_offset` (0.22 m) are anatomical defaults and will need playtest tuning. Note that the forehand (cross-body) reach is sized so the top hand can reach the opposite hip (~0.44 m from the top-hand shoulder), matching a comfortable real-life stickhandling position. Upper-body twist (`upper_body_twist_ratio = 0.5`) rotates the torso toward the blade direction and effectively shrinks the angular demand on the hand — so the forehand angular ROM interacts with the twist.
- **Stick / blade geometry split:** The IK rigid rod is the *shaft* only (hand → blade heel). The `Blade` Marker3D sits at the heel; the blade mesh is offset forward by `blade_length * 0.5` in `Scenes/Skater.tscn` so the mesh center is mid-blade. The puck's pickup sphere is also offset forward to center on mid-blade, and `Skater.get_blade_contact_global()` returns the mid-blade world position where the puck plays (used by `Puck` and `PuckController` for carry pinning). If the mesh length is changed in the scene, keep `blade_length` in sync so the contact point and pickup zone stay at mid-blade.
- **Phase 2 IK tuning knobs:** `hand_y_max` (0.30 m) caps how high the hand rises in the CLOSE regime — with default stick_length the minimum horizontal stick reach is ≈0.36 m. Lower `hand_y_max` widens the min reach; raise it to let the blade tuck in tighter. Arm bone lengths (`upper_arm_length = 0.33`, `forearm_length = 0.37`) should sum to ≈ `rom_backhand_reach_max` so the hand is always within arm reach; a shorter sum will make the arm stretch visually when the hand is at full backhand extension. `arm_pole_local = (0.2, −1, 0)` leans the elbow downward and slightly outward — tune X/Y ratio if the elbow pokes into the torso or flares too wide.
- **Shoulder-to-hand drop causes arm stretch at max backhand:** `shoulder_height` (0.5 m upper-body-local) positions the arm's anchor up on the torso; `hand_rest_y` (0.0) sits at waist. Vertical drop at rest ≈ 0.5 m. At max backhand extension (horizontal hand displacement = `rom_backhand_reach_max` = 0.7 m), shoulder-to-hand distance reaches ≈ 0.86 m, exceeding the 0.70 m arm reach — the `upper_arm_mesh` / `forearm_mesh` visibly stretch ~23%. Three ways to reduce: lower `shoulder_height` toward `hand_rest_y`; raise the arm bone lengths; or cap `rom_backhand_reach_max` closer to `sqrt(arm_sum² − drop²)` (≈ 0.49 m at defaults).
- **Wall-clamp hand retraction:** when `clamp_blade_to_walls` pulls the blade back, the controller applies the same XZ offset to `top_hand` so `|blade − hand|` stays at `stick_horiz`. Keeps the stick from visibly compressing against walls. Wall-pin puck auto-release (based on squeeze magnitude) is unaffected.
