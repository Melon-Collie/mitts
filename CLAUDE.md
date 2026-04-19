# CLAUDE.md

Context for Claude about the HockeyGame project.

## Workflow

Complex features (AI state machines, new systems, architectural changes) are designed first in Claude.ai chat mode, where the developer can iterate on ideas without implementation pressure. The resulting plan is then handed to Claude Code to implement against the actual codebase. When a session starts with a plan document, treat it as the agreed design — ask clarifying questions before deviating from it.

**Before every commit:** update this file, `README.md`, and `ARCHITECTURE.md`. New files go in the Key Files table. Completed work moves out of Known Issues here. New known issues get added. README's What's In / Planned sections and ARCHITECTURE's Build Status table should reflect current state.

**Never push to `main` without the user testing locally first.** Feature branches (e.g. `claude/*`) may be pushed after committing so the user can pull and test on their machine. For `main`, always stop at commit and wait for explicit confirmation before running `git push`.

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

**Ghost mechanic:** Offsides and icing are enforced via a ghost mode rather than stoppages. Ghost skaters go transparent, can't interact with the puck or other players (collision layers zeroed), and can still move freely. Offsides: skater in offensive zone while puck hasn't crossed the blue line → ghost until they tag up (retreat past the blue line into neutral zone). Puck entering the zone does NOT clear the ghost — sticky per-peer tracking in `_offside_peer_ids` on `GameStateMachine`. Icing: puck shot from own half past opponent goal line → entire team ghosted for `ICING_GHOST_DURATION` (3s) or until the other team picks up the puck. Host computes ghost state in `GameManager._physics_process`; clients predict offsides locally, receive authoritative ghost state (including icing) via world state.

**World state layout:** `[peer_id, skater_state_array, ..., puck_position, puck_velocity, puck_carrier_peer_id, goalie0_state[5], goalie1_state[5], score0, score1, phase, period, time_remaining_secs]`

## Key Files

### Domain (pure GDScript, no engine APIs)

| File | Role |
|------|------|
| `domain/state/game_phase.gd` | `class_name GamePhase`; nested `enum Phase { PLAYING, GOAL_SCORED, FACEOFF_PREP, FACEOFF, END_OF_PERIOD, GAME_OVER }` |
| `domain/state/game_state_machine.gd` | RefCounted FSM. Owns phase/timer, scores, current_period, time_remaining (period clock), player slot registry, icing state, `team_shots[2]`; host drives via `tick(delta)`, clients sync via `apply_remote_state(...)` |
| `domain/state/player_stats.gd` | Per-player stat data object: goals, assists, shots_on_goal, hits. Serializes to/from Array for RPC transport. |
| `domain/config/game_rules.gd` | Game-rule constants: timings, rink geometry, blue/goal line Z, icing duration, faceoff positions, max players, ice friction |
| `domain/rules/phase_rules.gd` | `is_dead_puck_phase`, `is_movement_locked` |
| `domain/rules/player_rules.gd` | Team balancing, fixed team colors (`generate_primary_color` for UI badges; `generate_jersey_color` / `generate_helmet_color` / `generate_pants_color` for skater meshes), faceoff position lookup. Home team (0): Penguins Vegas Gold primary + black secondary. Away team (1): Leafs Blue primary + white secondary. |
| `domain/rules/infraction_rules.gd` | `is_offside`, `check_icing` |
| `domain/rules/puck_collision_rules.gd` | Deflection reflection, body-check/body-block velocity, poke-strip direction, `can_poke_check` eligibility |
| `domain/rules/skater_movement_rules.gd` | Thrust scaling, friction, max-speed clamp with puck-carry penalty, pulse-dash impulse |
| `domain/rules/shot_mechanics.gd` | Wrister / slapper power + direction + elevation; `should_release_on_wall_pin` |
| `domain/rules/goalie_behavior_rules.gd` | Shot detection, defensive zone detection, Buckley depth chart, lateral X target |
| `domain/rules/charge_tracking.gd` | Wrister aim charge accumulation with direction-variance reset |
| `domain/rules/reconciliation_rules.gd` | Thresholds for skater reconcile and puck hard-snap |
| `domain/rules/top_hand_ik.gd` | 1-bone inverse kinematics for the stick's top hand. Given a desired blade target and a fixed stick length, solves (hand, blade) respecting an asymmetric ROM (small forehand / large backhand reach). Two regimes: FAR extends the hand in XZ (ROM-clamped); CLOSE raises the hand's Y so the stick tilts vertically and the blade tucks in near the body. Blade-first feel: blade lands on target when reachable, clips along aim line when not. |
| `domain/rules/bottom_hand_ik.gd` | Reactive IK for the bottom (off-stick) hand. Places the hand exactly on the grip target (`top_hand.lerp(blade, grip_fraction)`) for any blade angle within `bh_release_angle_deg`. When the blade world angle toward the backhand exceeds that threshold, a smoothstep band blends the hand to a shoulder rest — the one-handed backhand look. Release is angle-driven (not reach/ROM), so the hand never gives up during a normal swing regardless of upper body follow speed. Never influences blade or top-hand placement. |
| `domain/rules/two_bone_ik.gd` | Analytical 2-bone IK used to render the arm. Given shoulder, hand, two bone lengths, and a pole hint, returns the elbow position so `|shoulder − elbow| = upper_len` and `|elbow − hand| = forearm_len`. Used for both the top and bottom arms. |

### Application (orchestration)

| File | Role |
|------|------|
| `game/game_manager.gd` | Autoload orchestrator. Owns the GameStateMachine, wires five collaborators (PlayerRegistry / WorldStateCodec / ShotOnGoalTracker / PhaseCoordinator / SlotSwapCoordinator), routes NetworkManager signals to them, and re-exposes their signals for HUD/Camera/Scoreboard. Exposes `is_host()` / `is_movement_locked()` for controllers via duck typing. Session-lifecycle API consumed by menus: `reset_game()` (host-only rematch, stays in Hockey scene), `return_to_lobby()` (host-only, drops puck, RPCs `send_return_to_lobby_to_all` with a roster built from `PlayerRegistry`, then all peers transition back to `Lobby.tscn`), `exit_to_main_menu()` (tears down + resets NetworkManager + scene-changes to MainMenu). |
| `game/actor_spawner.gd` | Scene instantiation + `add_child` + controller `setup()` calls. Returns raw nodes; GameManager does game-level wiring. |
| `game/player_registry.gd` | RefCounted. Owns `players: Dictionary[int, PlayerRecord]` and the unified local/remote `spawn()`. Provides skater↔peer↔team resolvers used by Puck and PuckController. Emits `player_added` / `player_removed` / `player_joined` / `player_left` for GameManager to relay. |
| `game/world_state_codec.gd` | RefCounted. Encodes/decodes the flat RPC Array for world state (skater/puck/goalie/game_state sections) and the stats wire format. Emits `phase_changed` / `game_over_triggered` / `period_changed` / `clock_updated` / `shots_on_goal_changed` so GameManager can react to authoritative host updates on clients. |
| `game/shot_on_goal_tracker.gd` | RefCounted host-side state machine. Exposes `on_pickup` / `on_shot_started` / `on_goalie_touch` / `on_goal_confirmed` / `on_loose_puck_touched` / `credit_assists` / `tick(delta)` / `reset_all`. Owns `_recent_carriers`, pending-shot timer, and SOG dedup. Emits `shots_on_goal_changed`. Unit-tested in `tests/unit/game/`. |
| `game/hit_tracker.gd` | RefCounted host-side hit crediting. `on_hit(hitter_peer_id, victim_team_id)` validates cross-team contact before incrementing the hitter's stat. Emits `hit_credited` for GameManager to sync stats to clients. |
| `game/phase_coordinator.gd` | RefCounted. Holds phase-entry side effects — puck reset/lock, goalie reset, faceoff teleport — and the host-side goal pipeline (own-goal detection, assist credit, SOG confirmation). Emits `goal_scored` / `score_changed` / `phase_changed` / `period_changed` / `clock_updated` / `game_over` / `stats_need_sync` / `faceoff_positions_ready` / `goal_broadcast_needed`, which GameManager relays to its own signals and to NetworkManager RPCs. |
| `game/slot_swap_coordinator.gd` | RefCounted. Validates mid-game slot swap requests (`request_swap` returns a confirmation payload or `{}`) and applies confirmations (`apply_confirmed_swap` mutates PlayerRecord + teleports). Emits `carrier_swap_needs_drop` when the requesting player holds the puck so GameManager can drop it before the swap. |
| `controllers/local_controller.gd` | Local player: input gathering, prediction, reconciliation. Takes `game_state` via setup; calls `InfractionRules.is_offside` directly for client-side ghost prediction. |
| `controllers/remote_controller.gd` | Remote players: server-side input driving, client-side interpolation |
| `controllers/puck_controller.gd` | Puck: emits `puck_picked_up_by` / `puck_released_by_carrier` / `puck_stripped_from` signals (via injected peer_id resolver) for GameManager to consume; handles client prediction + interpolation |
| `controllers/skater_controller.gd` | Base class: state machine, movement, shooting, blade control. Delegates blade placement to `TopHandIK.solve` with fixed `stick_length` and ROM exports. After every blade placement, calls `_update_bottom_hand()` → `BottomHandIK.solve` to reactively place the off-stick hand. Delegates other math to domain rules. |
| `controllers/goalie_controller.gd` | Goalie AI: state machine (STANDING/BUTTERFLY/RVH_LEFT/RVH_RIGHT) driving positioning via `GoalieBehaviorRules` |
| `controllers/goalie_body_config.gd` | Data class holding per-state body part positions and rotations |

### Infrastructure (engine integration)

| File | Role |
|------|------|
| `networking/network_manager.gd` | Autoload. RPC definitions, connection management, state broadcast timing |
| `actors/puck.gd` | RigidBody3D: pickup zone, deflection, carrier following (server only). Accepts a `team_resolver: Callable` so it doesn't reach into GameManager for team checks. |
| `actors/skater.gd` | CharacterBody3D: blade/top-hand/bottom-hand/facing/upper-body API, ghost mode toggling. `shoulder` Marker3D anchors the top hand on the opposite side from the blade (right-shoulder for a left-handed shooter); `bottom_shoulder` mirrors it on the blade side (left-shoulder for a lefty). `top_hand` and `bottom_hand` Marker3Ds are the moving IK outputs; created programmatically on `_ready` if not present in the scene. Four arm meshes (`UpperArmMesh` / `ForearmMesh` / `BottomUpperArmMesh` / `BottomForearmMesh`) are auto-created the same way and positioned each tick by `update_arm_mesh()` / `update_bottom_arm_mesh()` via `TwoBoneIK.solve_elbow` (bottom arm uses a mirrored pole). `set_player_color(primary, secondary, is_local)` sets explicit `material_override` on all meshes: primary → jersey/blade/all four arm meshes; secondary → legs (`LowerBodyMesh`) + helmet (`DirectionIndicator`); fixed brown → stick shaft. All meshes except the ring are included in ghost-mode transparency. A flat procedural ring mesh (gray, 50% alpha) sits at global Y=0.05 under the skater's feet — only visible on the local player (`is_local=true` in `set_player_color`). |
| `actors/goalie.gd` | Goalie body API: exposes position, rotation, body part config methods |
| `actors/hockey_goal.gd` | Goal mesh + goal sensor Area3D; emits `goal_scored` signal |
| `actors/hockey_rink.gd` | Procedural rink geometry (@tool): walls, corners, ice surface, markings |
| `game/constants.gd` | Engine-facing constants only: collision layers/masks, network port, input/state rates, physics tick. Game-rule constants live in `domain/config/game_rules.gd`. |
| `game/build_info.gd` | Autoload. Holds `VERSION` (baked in by `deploy.yml` at export time; stays `"dev"` in the editor), `RELEASE_TAG`, and `REPO` — all read by `UpdateChecker`. |
| `game/team.gd` | Team object: defended goal, goalie controller |
| `game/player_record.gd` | Per-player data: peer_id, slot, team, skater, controller, faceoff_position, is_left_handed, stats (PlayerStats) |
| `networking/buffered_skater_state.gd` | Timestamped SkaterNetworkState for interpolation buffer |
| `networking/buffered_puck_state.gd` | Timestamped PuckNetworkState for interpolation buffer |
| `networking/buffered_goalie_state.gd` | Timestamped GoalieNetworkState for interpolation buffer |
| `networking/buffered_state_interpolator.gd` | Shared bracket-search + stale-trim helpers used by the three interpolating controllers. |
| `networking/goalie_network_state.gd` | Serializable goalie state: position, rotation, state enum, five_hole_openness |
| `networking/skater_network_state.gd` | Serializable skater state: position, velocity, facing, blade, top_hand, input sequence, is_ghost |
| `networking/puck_network_state.gd` | Serializable puck state: position, velocity, carrier peer ID |
| `input/input_state.gd` | InputState data object: all per-tick input fields (move, mouse, shoot, brake, elevation, etc.) |
| `input/local_input_gatherer.gd` | Populates InputState from local hardware; accumulates just_pressed between ticks |
| `ui/game_camera.gd` | Per-player camera: frames player+puck via zoom, then shifts toward attacking zone using available slack. Ozone zoom (min_height→ozone_min_height) when local player is in the attacked zone. Bias smoothed by possession changes and movement direction. Wired via `LocalController.set_goal_context`. |
| `ui/hud.gd` | Scorebug HUD: three-column dark panel top-left — teams+scores (away top, home bottom with colored badges) | shots-on-goal (away/SHOTS/home) | period+clock. Phase banner (GOAL!, FACEOFF, etc.) is a separate centered panel below. Small dim `v{BuildInfo.VERSION}` tag bottom-right. Game menu (`_game_menu`, CanvasLayer 20) opened with ESC: Resume, Change Position, Rematch (host), Return to Lobby (host), Report Bug, Disconnect, Exit Game. Host-only buttons are built via the `_add_host_button(vbox, text, handler)` helper so game-over and ESC menus stay in sync. "Change Position" toggles a `SlotGridPanel` on a separate CanvasLayer 21 (styled dark panel, centered, above the menu). ESC is layered: closes slot grid first if open, then closes the menu. `_set_menu_open(bool)` controls visibility + input blocking. Receives scores/phase/period/clock/SOG via GameManager signals; polls `skater.is_elevated` each frame. |
| `ui/slot_grid_panel.gd` | Stateless `Control` subclass. Renders a 2×3 team/slot grid; emits `slot_selected(team_id, slot)`. Away (team 1) on top, Home (team 0) on bottom — matches rink perspective. Refreshed by caller via `refresh(roster, local_peer_id)`. Occupied slots show player name and are disabled; empty slots are enabled. Used by HUD game menu and (future) lobby. |
| `ui/scoreboard.gd` | Tab-toggle scoreboard overlay (CanvasLayer). Builds per-player table: Player | G | A | PTS | SOG | HITS, colored by team. Auto-shows on game over. Updates via `GameManager.stats_updated`. |
| `ui/main_menu.gd` | Main menu: shoots left/right toggle + host/join/offline buttons + IP input, calls `NetworkManager.start_*()`, transitions to `Hockey.tscn`. Shows `v{BuildInfo.VERSION}` as a dim label at the bottom of the vbox, followed by an `UpdateChecker` that only reveals itself on mismatch. |
| `ui/lobby_manager.gd` | `class_name LobbyManager`. Attached to `Lobby.tscn`. Builds the lobby UI (team/slot grid via `SlotGridPanel`, host-only settings for periods/duration/OT, Back + Start buttons) in code. Host owns `_lobby_slots` and auto-balances new joiners. On `_ready`, if `NetworkManager.pending_lobby_roster` is non-empty (client join-in-progress OR host/clients returning from a finished game), rebuilds from that; otherwise the host seeds itself at team 0 slot 0. Slot swaps go through the host via `NetworkManager.slot_swap_requested/confirmed`. Start sends game config via `NetworkManager.send_game_start` and pushes `pending_lobby_slots` for `GameManager` to consume on the Hockey scene. Back calls `GameManager.exit_to_main_menu()`. |
| `ui/update_checker.gd` | `class_name UpdateChecker extends Label`. On `_ready`, if `BuildInfo.VERSION != "dev"`, HTTPRequests the GitHub Releases API (`BuildInfo.REPO`, `BuildInfo.RELEASE_TAG`), compares the release `name` to the local version, and reveals itself with an "Update available" message when stale. Fails silently on network/parse errors. 5 s timeout. |
| `game/game_scene.gd` | Hockey scene init: calls `NetworkManager.on_game_scene_ready()` in `_ready()` to trigger world spawn |

### VFX

| File | Role |
|------|------|
| `vfx/puck_vfx.gd` | `PuckVFX` (Node3D child of Puck): GPUParticles3D ribbon trail (pale-blue, `trail_enabled`); position-delta velocity works for free and carrier-pinned states. Detects wall/poke impacts by normalized velocity dot product < −0.25 and triggers a small ice burst. |
| `vfx/skater_vfx.gd` | `SkaterVFX` (Node3D child of Skater): ice spray (burst on `delta_vel > 8 m/s²`), skate trails (continuous flat marks, 2.5s fade), speed lines (streaks behind skater above 5.5 m/s), body check burst (connected to `body_checked_player` signal — fires at victim position), OmniLight shot charge glow (tracks `skater.shot_charge`, 0–1 normalized, blue light at blade). Teleport guard (1 m threshold) suppresses false effects from reconcile and faceoffs. |
| `vfx/goal_vfx.gd` | `GoalVFX` (Node3D child of HockeyGoal): gold GPUParticles3D one-shot burst + OmniLight3D flash that Tweens back to zero. Created at the end of `HockeyGoal._rebuild()` (not `_ready()`) since `_rebuild()` frees all children. `celebrate()` is called from `GameManager.on_goal_scored()` on all peers. |

### Tests

| File | Role |
|------|------|
| `tests/unit/rules/` | GUT tests for each rule class — ~130 tests covering domain logic |
| `tests/unit/state/` | GUT tests for `GameStateMachine` — phase transitions, icing, ghost computation |
| `tests/unit/game/` | GUT tests for application-layer collaborators: `ShotOnGoalTracker` (pending-shot FSM, assists, SOG dedup), `WorldStateCodec` (stats round-trip), `SlotSwapCoordinator` (request validation). |

## Code Conventions

**Strong typing everywhere.** Typed arrays (`Array[BufferedPuckState]`), typed function signatures, typed variables. Never leave a type annotation off when it can be provided. Prefer `var state: PuckNetworkState` over `var state`.

**Godot naming conventions.** `snake_case` for variables and functions, `PascalCase` for class names, `SCREAMING_SNAKE_CASE` for constants.

**Separation of concerns.** Physics bodies (`Puck`, `Skater`) expose a clean API. Controllers drive them. `GameManager` owns spawning and world state. `NetworkManager` owns RPCs. Don't reach across these boundaries casually.

**Network API uses typed objects, not raw arrays.** Functions accept `SkaterNetworkState` / `PuckNetworkState` directly. Serialization to/from arrays happens only at the RPC boundary.

**Get it working, then tune numbers.** Implement the mechanic correctly first. Use `@export` on tunable parameters so values can be adjusted in the editor. Don't prematurely optimize or bikeshed on constants before the thing actually runs.

**Don't shy away from complexity when it improves feel.** This project already has full client-side prediction with input replay, buffered interpolation, and puck trajectory prediction with reconciliation. If adding a complex system will make the game feel meaningfully better to play, it's worth doing — think it through carefully first, then implement it properly.

## Launch Modes

All start paths go through `MainMenu.tscn`. `NetworkManager._ready()` does nothing — the menu calls `start_offline()`, `start_host()`, or `start_client(ip)` directly. These set up ENet but defer world spawning. `Hockey.tscn`'s root node runs `game_scene.gd`, whose `_ready()` calls `NetworkManager.on_game_scene_ready()`, which emits the `host_ready` signal on hosts (GameManager listens and calls `on_host_started`). Client world spawn is triggered by the `client_connected` signal from `_on_connected_to_server()`.

NetworkManager → GameManager communication is signal-based: every RPC / ENet callback emits a typed signal, and GameManager wires all connections once in `_ready()` via `_wire_network_signals()`. The only downward data flow is `NetworkManager.set_world_state_provider(Callable)`, which GameManager uses to hand the world-state getter to the broadcast loop — matching the `puck.set_team_resolver` / `puck_controller.set_peer_id_resolver` pattern.

## Distribution

Playtester builds ship via GitHub Releases (`latest` tag). `deploy.yml` computes `VERSION=0.1.<git rev-list --count HEAD>`, rewrites the placeholder `"dev"` in `Scripts/game/build_info.gd` to that string before export, and publishes with the version as the release name. The main menu's `UpdateChecker` label polls the GitHub API on startup and prompts re-download when stale. No in-game patching — Steam (SteamPipe binary-delta) is the long-term plan; this plumbing is intentionally small so it can come out when that lands. Don't add an in-game downloader/launcher before Steam.

## Known Issues / Planned Work

- **Goalie reactive saves not yet implemented:** glove saves, shoulder/body saves, and stick poke coverage are all planned. The stick is currently disabled (`stick_enabled = false`) — it can be re-enabled once it has proper positional behavior rather than acting as a static seal.
- **Top-hand ROM values are first-principles baselines:** `rom_forehand_angle_max_deg` (90°), `rom_backhand_angle_max_deg` (120°), `rom_forehand_reach_max` (0.45 m), `rom_backhand_reach_max` (0.70 m), `stick_length` (1.30 m, shaft-only butt-to-heel), `blade_length` (0.30 m), `shoulder_offset` (0.22 m) are anatomical defaults and will need playtest tuning. Note that the forehand (cross-body) reach is sized so the top hand can reach the opposite hip (~0.44 m from the top-hand shoulder), matching a comfortable real-life stickhandling position. Upper-body twist (`upper_body_twist_ratio = 0.8`) rotates the torso with the blade angle, effectively shrinking the angular demand on the hand — so the forehand angular ROM interacts with the twist.
- **Stick / blade geometry split:** The IK rigid rod is the *shaft* only (hand → blade heel). The `Blade` Marker3D sits at the heel; the blade mesh is offset forward by `blade_length * 0.5` in `Scenes/Skater.tscn` so the mesh center is mid-blade. The puck's pickup sphere is also offset forward to center on mid-blade, and `Skater.get_blade_contact_global()` returns the mid-blade world position where the puck plays (used by `Puck` and `PuckController` for carry pinning). If the mesh length is changed in the scene, keep `blade_length` in sync so the contact point and pickup zone stay at mid-blade.
- **Phase 2 IK tuning knobs:** `hand_y_max` (0.30 m) caps how high the hand rises in the CLOSE regime — with default stick_length the minimum horizontal stick reach is ≈0.36 m. Lower `hand_y_max` widens the min reach; raise it to let the blade tuck in tighter. Arm bone lengths (`upper_arm_length = 0.44`, `forearm_length = 0.46`) must sum to more than `sqrt(drop² + rom_backhand_reach_max²)` (≈ 0.87 m at current drop) to avoid visible arm stretch at full backhand extension. `arm_pole_local = (0.2, −1, 0)` leans the elbow downward and slightly outward — tune X/Y ratio if the elbow pokes into the torso or flares too wide.
- **Arm stretch at max backhand:** drop = `shoulder_height − hand_rest_y` = 0.52 m. If `hand_rest_y` is tuned further, verify `sqrt(drop² + rom_backhand_reach_max²)` stays under `upper_arm_length + forearm_length` (currently 0.90 m). Max safe XZ reach at current drop ≈ 0.735 m, clearing `rom_backhand_reach_max` (0.70 m).
- **Wall-clamp hand retraction:** when `clamp_blade_to_walls` pulls the blade back, the controller applies the same XZ offset to `top_hand` so `|blade − hand|` stays at `stick_horiz`. Keeps the stick from visibly compressing against walls. Wall-pin puck auto-release (based on squeeze magnitude) is unaffected.
- **Bottom-hand IK tuning:** `bottom_hand_grip_fraction` (0.25) and `bh_release_angle_band_deg` (15°) are the key tuning knobs. The grip fraction controls how far down the shaft the bottom hand sits (0 = top hand position, 1 = blade heel). The release angle (`bh_release_angle_deg = 67°`) is matched to `upper_body_max_twist_deg` — the hand holds on through any angle the body can track. The band controls how quickly it transitions to the one-handed rest pose past that limit — widen for an earlier fade, narrow for a sharper release. Bottom arm rendering uses `upper_arm_length` / `forearm_length` with a mirrored pole (`-arm_pole_local.x`).
