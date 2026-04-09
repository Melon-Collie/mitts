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
  2. **Trajectory prediction** — integrate velocity with `Constants.ICE_FRICTION` after local release, reconcile against server when error exceeds threshold
  3. **Interpolation** — buffer server snapshots, interpolate (all other cases)
- Carrier transitions via reliable RPCs: pickup is server → specific client; release is predicted immediately on client, then RPC to server
- `_carrier_peer_id` on clients is managed exclusively by `notify_local_pickup/release`, never by world state, to avoid unreliable packet ordering conflicts

**Goalies:**
- `GoalieController` AI runs on host only (gated by `is_server`). Clients receive state via world broadcast and interpolate with a 100ms delay using `BufferedGoalieState` — same pattern as remote skaters.
- Serialized fields: position (x, z), rotation_y, state enum, five_hole_openness. Clients reconstruct body configs locally from those values.
- Seven body parts: LeftPad, RightPad, Body, Head, Glove, Blocker, Stick. Sizes: pads 0.28×0.84×0.15m, body 0.40×0.60×0.25m, head 0.22×0.22×0.20m, glove 0.25×0.25×0.15m, blocker 0.20×0.30×0.10m, stick 0.50×0.04×0.04m.
- RVH state selection uses goalie-local X (`(puck.x - goal_center_x) * -_direction_sign`) so both goalies pick the correct post despite having opposite world-space rotations. RVH root targets `net_half_width - 0.88` so the post pad outer edge (pad center 0.46 + half-height 0.42) lands flush with the post.

**World state layout:** `[peer_id, skater_state_array, ..., puck_position, puck_velocity, puck_carrier_peer_id, goalie0_state[5], goalie1_state[5]]`

## Key Files

| File | Role |
|------|------|
| `game_manager.gd` | Spawning, world state serialization/application, puck release handling |
| `network_manager.gd` | RPC definitions, connection management, state broadcast timing |
| `local_controller.gd` | Local player: input gathering, prediction, reconciliation |
| `remote_controller.gd` | Remote players: server-side input driving, client-side interpolation |
| `puck_controller.gd` | Puck: server signals, state serialization, client prediction and interpolation |
| `skater_controller.gd` | Base class: full state machine, movement, shooting, blade control |
| `puck.gd` | Physics body: pickup zone, deflection, carrier following (server only) |
| `skater.gd` | Physics body: blade/facing/upper-body API |
| `goalie.gd` | Goalie body API: exposes position, rotation, and body part config methods |
| `goalie_controller.gd` | Goalie AI: state machine (STANDING/BUTTERFLY/RVH_LEFT/RVH_RIGHT), Buckley depth, lateral positioning, shot detection |
| `goalie_body_config.gd` | Data class holding per-state body part positions and rotations |
| `constants.gd` | Shared constants: network rates, physics tick, ICE_FRICTION, rink geometry |
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

- **Ice friction not applied correctly:** `hockey_rink.gd` uses `col.set_meta("physics_material_override", phys_mat)` on a `CollisionShape3D`, which does nothing. The physics material needs to be set on a dedicated child `StaticBody3D` for the ice surface. `Constants.ICE_FRICTION = 0.01` is the intended value and is already used in puck trajectory prediction.
- **Clients keep stale remote skaters on disconnect:** when a non-host player leaves, the host cleans up but has no mechanism to notify other clients. Low priority for 1v1, matters for 3v3.
