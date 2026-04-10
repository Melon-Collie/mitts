# CLAUDE.md

Context for Claude about the HockeyGame project.

## Workflow

Complex features (AI state machines, new systems, architectural changes) are designed first in Claude.ai chat mode, where the developer can iterate on ideas without implementation pressure. The resulting plan is then handed to Claude Code to implement against the actual codebase. When a session starts with a plan document, treat it as the agreed design — ask clarifying questions before deviating from it.

**Before every commit:** update this file, `README.md`, and `ARCHITECTURE.md`. New files go in the Key Files table. Completed work moves out of Known Issues (both here and in ARCHITECTURE.md). New known issues get added. README's What's In / Planned sections and ARCHITECTURE's Build Status table should reflect current state.

**Scene files (`.tscn`) are edited by the user, not Claude.** Godot's scene format is error-prone to edit as text — node unique IDs, sub-resource references, and property ordering can silently break the scene. When a task requires scene changes, describe exactly what to add or modify and let the user make the edits in the Godot editor.

## What This Is

A 3v3 arcade hockey game built in Godot 4.6.2 (GDScript, 3D). Online multiplayer — one player per machine, each with their own camera and local simulation. Prioritizes feel over realism: deep stickhandling, multiple shot types, satisfying puck physics.

## Tech Stack

- **Engine:** Godot 4.6.2 (Jolt Physics)
- **Language:** GDScript
- **Physics tick:** 240 Hz
- **Deployment:** GitHub Actions → Windows export → GitHub Releases (tag: `latest`, updates on every push to main)

## Networking Architecture

Authoritative host model. The host runs all physics. Clients predict locally and reconcile against server state.

**Rates:**
- Input sends (client → host): 60 Hz, unreliable
- State broadcasts (host → clients): 20 Hz, unreliable
- Events (pickup notification, release, spawn, sync): reliable RPCs

**Skaters:**
- `LocalController` — runs physics locally every frame, stores input history, reconciles against server state (reset + replay unconfirmed inputs) when position/velocity error exceeds threshold
- `RemoteController` — on the host: drives simulation from latest received input. On clients: interpolates between buffered `BufferedSkaterState` snapshots with a 100ms delay

**Puck:**
- `PuckController` operates in three client-side modes:
  1. **Local carrier** — pin puck to local blade position each frame (no lag)
  2. **Trajectory prediction** — after local release, puck is unfrozen (`freeze = false`) and Jolt runs client-side physics. Board bounces are handled correctly by the engine. Each 20Hz server broadcast: soft-correct velocity toward server state; nudge position only when velocities agree (avoids fighting Jolt during bounces where velocities briefly oppose); hard-snap on extreme divergence. Exit when `carrier_peer_id != -1` in world state, then refreeze and return to interpolation.
  3. **Interpolation** — buffer server snapshots, interpolate with 100ms delay (all other cases). Position only — velocity is not applied to the frozen body.
- Carrier transitions via reliable RPCs: pickup is server → specific client; release is predicted immediately on client, then RPC to server; poke check strip is server → victim client (`notify_puck_stolen`)
- `_carrier_peer_id` on clients is managed exclusively by `notify_local_pickup/release/puck_stolen`, never by world state, to avoid unreliable packet ordering conflicts
- **Puck interactions (server-side, `puck.gd`):** relative-velocity catch vs deflect — `(puck_vel - blade_world_vel).length()` vs `deflect_min_speed`; deflect direction = contact normal (blade-to-puck, billiard ball style) reflected with `deflect_blend`; elevation tipping via `skater.is_elevated`; poke check strips on any opposing blade contact while carried; per-skater `_cooldown_timers` dict so ex-carrier has a disadvantage but the other player can pick up immediately

**Goalies:**
- `GoalieController` AI runs on host only (gated by `is_server`). Clients receive state via world broadcast and interpolate with a 100ms delay using `BufferedGoalieState` — same pattern as remote skaters.
- Serialized fields: position (x, z), rotation_y, state enum, five_hole_openness. Clients reconstruct body configs locally from those values.
- Seven body parts: LeftPad, RightPad, Body, Head, Glove, Blocker, Stick. Sizes: pads 0.28×0.84×0.15m, body 0.40×0.60×0.25m, head 0.22×0.22×0.20m, glove 0.25×0.25×0.15m, blocker 0.20×0.30×0.10m, stick 0.50×0.04×0.04m. The Stick is disabled by default (`@export stick_enabled: bool = false` on `Goalie`; `_ready()` sets collision_layer and visibility accordingly).
- RVH state selection uses goalie-local X (`(puck.x - goal_center_x) * -_direction_sign`) so both goalies pick the correct post despite having opposite world-space rotations. RVH root targets `net_half_width - 0.88` so the post pad outer edge (pad center 0.46 + half-height 0.42) lands flush with the post. RVH triggers via `_is_puck_in_defensive_zone()` — behind goal line OR within `zone_post_z` at angle ≥ `rvh_early_angle`.
- **Tracking lag:** `_tracked_puck_position` lerps toward the real puck at `tracking_speed` (default 6.0) each frame. All positional logic — depth, lateral target, facing, and state transitions — reads from `_tracked_puck_position`. Shot detection (`_on_puck_released`) reads the real puck position and velocity. `tracking_speed` is the master difficulty knob: lower = more lag, easier to beat.

**Game flow:**
- `GamePhase` FSM (host-driven): `PLAYING → GOAL_SCORED → FACEOFF_PREP → FACEOFF → PLAYING`
- Phase changes travel two ways: reliable RPC (`notify_goal`) for immediate effect + world state as a correction channel. Score and phase are the last three elements of every world state broadcast.
- Dead-puck phases (`GOAL_SCORED`, `FACEOFF_PREP`) gate all movement via `GameManager.movement_locked()`. Both `LocalController._physics_process` and `RemoteController._drive_from_input` check this every frame — killing velocity and (on local) draining `_input_history` — so no stale input can contaminate server state or replay on phase lift.
- `LocalController.reconcile` is also blocked during locked phases: `on_faceoff_positions` (reliable RPC) is the authoritative source of faceoff positions; world state snapshots may lag behind and would fight it.
- Controller API pattern: `GameManager` calls `controller.teleport_to(pos)` and `controller.on_puck_released_network()` — it does not touch `skater` fields or read `has_puck` directly. Add methods to `SkaterController` (override in `LocalController` if needed) rather than poking internals from `GameManager`.
- `Team` objects (two, created at startup) own `defended_goal`, `goalie_controller`, and `score`. Used by reference everywhere; `team_id: int` only for wire serialization.
- Two `HockeyGoal` scene instances (`facing=+1` and `facing=-1`). Each has an `Area3D` goal sensor (`collision_mask=8`) that emits `goal_scored` when the puck (`collision_layer=8`) enters. Host only: signals connected in `_connect_goal_signals()`.

**World state layout:** `[peer_id, skater_state_array, ..., puck_position, puck_velocity, puck_carrier_peer_id, goalie0_state[5], goalie1_state[5], score0, score1, phase]`

## Key Files

| File | Role |
|------|------|
| `game_manager.gd` | Spawning, world state serialization/application, game phase FSM, puck release handling |
| `network_manager.gd` | RPC definitions, connection management, state broadcast timing |
| `local_controller.gd` | Local player: input gathering, prediction, reconciliation |
| `remote_controller.gd` | Remote players: server-side input driving, client-side interpolation |
| `puck_controller.gd` | Puck: server signals, state serialization, client prediction and interpolation |
| `skater_controller.gd` | Base class: full state machine, movement, shooting, blade control, teleport API |
| `puck.gd` | Physics body: pickup zone, deflection, carrier following (server only) |
| `skater.gd` | Physics body: blade/facing/upper-body API |
| `goalie.gd` | Goalie body API: exposes position, rotation, and body part config methods |
| `goalie_controller.gd` | Goalie AI: state machine (STANDING/BUTTERFLY/RVH_LEFT/RVH_RIGHT), Buckley depth, lateral positioning, shot detection |
| `goalie_body_config.gd` | Data class holding per-state body part positions and rotations |
| `team.gd` | Team object: defended goal, goalie controller, score |
| `player_record.gd` | Per-player data: peer_id, slot, team, skater, controller, faceoff_position |
| `constants.gd` | Shared constants: network rates, physics tick, ICE_FRICTION, rink geometry, faceoff positions |
| `buffered_skater_state.gd` | Timestamped SkaterNetworkState for interpolation buffer |
| `buffered_puck_state.gd` | Timestamped PuckNetworkState for interpolation buffer |
| `buffered_goalie_state.gd` | Timestamped GoalieNetworkState for interpolation buffer |
| `goalie_network_state.gd` | Serializable goalie state: position, rotation, state enum, five_hole_openness |

## Code Conventions

**Strong typing everywhere.** Typed arrays (`Array[BufferedPuckState]`), typed function signatures, typed variables. Never leave a type annotation off when it can be provided. Prefer `var state: PuckNetworkState` over `var state`.

**Godot naming conventions.** `snake_case` for variables and functions, `PascalCase` for class names, `SCREAMING_SNAKE_CASE` for constants.

**Separation of concerns.** Physics bodies (`Puck`, `Skater`) expose a clean API. Controllers drive them. `GameManager` owns spawning and world state. `NetworkManager` owns RPCs. Don't reach across these boundaries casually.

**Network API uses typed objects, not raw arrays.** Functions accept `SkaterNetworkState` / `PuckNetworkState` directly. Serialization to/from arrays happens only at the RPC boundary.

**Get it working, then tune numbers.** Implement the mechanic correctly first. Use `@export` on tunable parameters so values can be adjusted in the editor. Don't prematurely optimize or bikeshed on constants before the thing actually runs.

**Don't shy away from complexity when it improves feel.** This project already has full client-side prediction with input replay, buffered interpolation, and puck trajectory prediction with reconciliation. If adding a complex system will make the game feel meaningfully better to play, it's worth doing — think it through carefully first, then implement it properly.

## Launch Modes

`network_manager.gd` `_ready()` branches on command line args:
- **No args** — offline mode: `is_host = true`, no ENet peer, single player
- **`--host`** — starts ENet server on `Constants.PORT` (7777 UDP), port must be forwarded for public play
- **`--connect <ip>`** — connects as client to the given IP; times out after `CONNECT_TIMEOUT` (10s) with `push_error` + quit

## Known Issues / Planned Work

- **RVH early trigger:** `_is_puck_in_defensive_zone()` fires RVH when the puck is within `zone_post_z` of the goal line at a horizontal angle ≥ `rvh_early_angle` (default 60°), matching the Buckley chart's corner zones. Tune `rvh_early_angle` if transition feels too early or late.
- **Clients keep stale remote skaters on disconnect:** when a non-host player leaves, the host cleans up but has no mechanism to notify other clients. Low priority for 1v1, matters for 3v3.
- **Goalie reactive saves not yet implemented:** glove saves, shoulder/body saves, and stick poke coverage are all planned. The stick is currently disabled (`stick_enabled = false`) — it can be re-enabled once it has proper positional behavior rather than acting as a static seal.
- **Goal phase RPC vs world state race:** if world state delivers `GOAL_SCORED` before the reliable `notify_goal` RPC arrives, the carrier client's puck state won't be cleared until the RPC arrives (typically one round-trip later). `on_puck_released_network` is idempotent so it's safe when the RPC does arrive. Low impact in practice.
- **No HUD for score/phase yet:** score and phase are tracked and networked but nothing displays them in-game.
- **Poke check / catch vs deflect thresholds need multiplayer tuning:** `deflect_min_speed` (relative velocity), `poke_strip_speed`, `poke_carrier_vel_blend`, and `poke_checker_cooldown` were set from first principles and need tuning under real network conditions with two players.
- **Client puck collides with skater bodies during prediction:** the puck is unfrozen during trajectory prediction, so Jolt may briefly detect collisions with player bodies (layer 1). Shot blocking will be reworked as a deliberate server-authoritative interaction; for now, any errant local collision is corrected by reconciliation.
