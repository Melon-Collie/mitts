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
- **Testing:** GUT v9.6.0 under `addons/gut/`; tests in `tests/unit/` run via the GUT panel or `godot --headless -s addons/gut/gut_cmdln.gd -gexit`
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

**World state layout:** `[peer_id, skater_state_array, ..., puck_position, puck_velocity, puck_carrier_peer_id, goalie0_state[5], goalie1_state[5], score0, score1, phase]`

## Key Files

### Domain (pure GDScript, no engine APIs)

| File | Role |
|------|------|
| `domain/state/game_phase.gd` | `class_name GamePhase`; nested `enum Phase { PLAYING, GOAL_SCORED, FACEOFF_PREP, FACEOFF }` |
| `domain/state/game_state_machine.gd` | RefCounted FSM. Owns phase/timer, scores, player slot registry, icing state; host drives via `tick(delta)`, clients sync via `apply_remote_state(...)` |
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

### Application (orchestration)

| File | Role |
|------|------|
| `game/game_manager.gd` | Autoload orchestrator. Owns the GameStateMachine, maintains the runtime player registry, routes infrastructure events into domain calls, executes domain decisions. Exposes `is_host()` / `is_movement_locked()` for controllers via duck typing. |
| `game/actor_spawner.gd` | Scene instantiation + `add_child` + controller `setup()` calls. Returns raw nodes; GameManager does game-level wiring. |
| `controllers/local_controller.gd` | Local player: input gathering, prediction, reconciliation. Takes `game_state` via setup; calls `InfractionRules.is_offside` directly for client-side ghost prediction. |
| `controllers/remote_controller.gd` | Remote players: server-side input driving, client-side interpolation |
| `controllers/puck_controller.gd` | Puck: emits `puck_picked_up_by` / `puck_released_by_carrier` / `puck_stripped_from` signals (via injected peer_id resolver) for GameManager to consume; handles client prediction + interpolation |
| `controllers/skater_controller.gd` | Base class: state machine, movement, shooting, blade control. Delegates math to domain rules. |
| `controllers/goalie_controller.gd` | Goalie AI: state machine (STANDING/BUTTERFLY/RVH_LEFT/RVH_RIGHT) driving positioning via `GoalieBehaviorRules` |
| `controllers/goalie_body_config.gd` | Data class holding per-state body part positions and rotations |

### Infrastructure (engine integration)

| File | Role |
|------|------|
| `networking/network_manager.gd` | Autoload. RPC definitions, connection management, state broadcast timing |
| `actors/puck.gd` | RigidBody3D: pickup zone, deflection, carrier following (server only). Accepts a `team_resolver: Callable` so it doesn't reach into GameManager for team checks. |
| `actors/skater.gd` | CharacterBody3D: blade/facing/upper-body API, ghost mode toggling |
| `actors/goalie.gd` | Goalie body API: exposes position, rotation, body part config methods |
| `actors/hockey_goal.gd` | Goal mesh + goal sensor Area3D; emits `goal_scored` signal |
| `actors/hockey_rink.gd` | Procedural rink geometry (@tool): walls, corners, ice surface, markings |
| `game/constants.gd` | Engine-facing constants only: collision layers/masks, network port, input/state rates, physics tick. Game-rule constants live in `domain/config/game_rules.gd`. |
| `game/team.gd` | Team object: defended goal, goalie controller, score |
| `game/player_record.gd` | Per-player data: peer_id, slot, team, skater, controller, faceoff_position |
| `networking/buffered_skater_state.gd` | Timestamped SkaterNetworkState for interpolation buffer |
| `networking/buffered_puck_state.gd` | Timestamped PuckNetworkState for interpolation buffer |
| `networking/buffered_goalie_state.gd` | Timestamped GoalieNetworkState for interpolation buffer |
| `networking/goalie_network_state.gd` | Serializable goalie state: position, rotation, state enum, five_hole_openness |
| `networking/skater_network_state.gd` | Serializable skater state: position, velocity, facing, blade, input sequence, is_ghost |
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
- **Goal phase RPC vs world state race:** if world state delivers `GOAL_SCORED` before the reliable `notify_goal` RPC arrives, the carrier client's puck state won't be cleared until the RPC arrives (typically one round-trip later). `on_puck_released_network` is idempotent so it's safe when the RPC does arrive. Low impact in practice.
- **Poke check / body check / catch vs deflect thresholds need multiplayer tuning:** `deflect_min_speed`, `poke_strip_speed`, `poke_carrier_vel_blend`, `body_check_strip_threshold`, `body_check_transfer`, and related exports were set from first principles and need tuning under real network conditions.
- **Active shot-block stance not yet implemented:** passive blocking is done (`BodyBlockArea` applies a dampened billiard reflection on loose pucks). The planned input-driven mode would use the same area with lower dampen and a wider stance for deliberate shot-blocking.
- **Icing ghost duration needs tuning:** `ICING_GHOST_DURATION` (3s) was set as an initial value. May need adjustment based on how punishing icing feels in practice — shorter if too harsh, longer if teams ice with impunity.
- **Icing only detects shots from own half, not dumps:** the icing check requires the last carrier to have been in their own half (z > 0 for team 0, z < 0 for team 1). Poke checks or strips in the neutral zone that send the puck past the goal line won't trigger icing.
