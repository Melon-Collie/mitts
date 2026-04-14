# Puck Interaction Overhaul Plan

Four interaction scenarios, implemented in order of dependency.

---

## Scope

1. **Deflection direction fix** — use blade face normal instead of blade forward axis
2. **Elevation-aware deflection** — tipped pucks when `is_elevated` is set
3. **Relative-velocity catch vs deflect** — blade moving with puck = catch, blade moving into puck = deflect
4. **Per-skater cooldowns** — replace global `_cooldown_timer` with per-skater dict so two players can race a loose puck fairly
5. **Poke check / strip** — any opposing blade contact while puck is carried strips the puck; direction driven by blade velocities

---

## Design Decisions

### Catch vs Deflect
- Remove the old `pickup_max_speed` / `deflect_min_speed` two-threshold approach
- Keep `pickup_max_speed` (8 m/s) as a hard floor: any puck this slow always catches
- `deflect_min_speed` becomes a **relative velocity** threshold: `(puck_vel - blade_world_vel).length()`
- Moving blade backward with puck (receiving a pass) → low relative velocity → catch
- Stationary blade hit by fast puck → high relative velocity → deflect
- Moving blade into puck → even higher relative velocity → deflect

### Deflection Direction
- Compute blade face normal from the stick shaft: `shaft = (blade_world - shoulder_world).normalized()`; `face_normal = shaft.cross(Vector3.UP)`
- Physical reflection: `reflected = horiz_vel - 2 * dot(horiz_vel, face_normal) * face_normal`
- Blend between raw velocity direction and reflected direction using `deflect_blend` export for arcade feel
- Note: reflection formula is symmetric — `face_normal` and `-face_normal` produce the same result, so handedness doesn't affect it

### Elevation
- `Skater.is_elevated: bool` is the source of truth, set by the controller each physics tick
- On deflect: if `skater.is_elevated`, tilt the outgoing direction upward by `deflect_elevation_angle` degrees while preserving horizontal direction

### Per-Skater Cooldowns
- Replace `_cooldown_timer: float` with `_cooldown_timers: Dictionary` (Skater → float)
- After `release()`: only ex-carrier gets `reattach_cooldown` (0.5 s)
- After `drop()`: only ex-carrier gets `reattach_cooldown`
- After deflect: only deflecting skater gets `deflect_cooldown` (0.3 s)
- After `reset()`: clear all timers
- Cooldown is checked **only for loose-puck pickups/deflects**, not for poke checks (opponents can always attempt to check a carrier)

### Poke Check / Strip
- When an opposing blade enters pickup zone while `carrier != null`:
  - Team check via `PuckCollisionRules.can_poke_check(carrier_team_id, checker_team_id)`, with team ids supplied through `Puck._team_resolver` (injected by `GameManager` at spawn) — no friendly strips
  - `_poke_check(checker_skater)`: compute strip direction, clear carrier, launch puck
- Strip direction:
  - If `checker_blade_vel.length() > 0.5 m/s`: `strip_dir = checker_vel + carrier_vel * poke_carrier_vel_blend`
  - Else: `strip_dir = ex_carrier.global_position - checker_skater.global_position` (push away from checker)
  - Fallback if direction is zero: random XZ
- Cooldowns after strip: ex-carrier gets `reattach_cooldown` (0.5 s), checker gets brief `poke_checker_cooldown` (0.1 s) before they can pick up the loose puck

### Network — Notifying the Victim Client
The ex-carrier client needs a reliable notification that they lost the puck. Pattern mirrors `notify_puck_picked_up`.

- `puck.gd` emits `puck_stripped(ex_carrier: Skater)` before `puck_released`
- `PuckController._on_puck_stripped(ex_carrier)` looks up the carrier's peer_id and calls `NetworkManager.send_puck_stolen(peer_id)` if the carrier is a remote client
- `network_manager.gd` delivers `notify_puck_stolen` reliable RPC to the victim
- Victim calls `GameManager.on_local_player_puck_stolen()` → same carrier-clearing logic as `on_goal_scored`

`puck_released` still emits from `_poke_check` so `PuckController._on_puck_released` handles the host-side `has_puck = false` cleanup (same as shots/drops).

---

## Implementation Steps

### Step 1 — `skater.gd`: blade velocity + is_elevated
- Add `is_elevated: bool = false`
- Add `blade_world_velocity: Vector3 = Vector3.ZERO` and `_prev_blade_world_pos: Vector3`
- In `_ready()`: initialize `_prev_blade_world_pos = upper_body.to_global(blade.position)` (prevents first-frame garbage velocity)
- In `_physics_process`: compute `blade_world_velocity` from prev/current blade world pos before `move_and_slide()`

### Step 2 — `skater_controller.gd`: sync is_elevated to Skater
- In `_process_input`, after updating `_is_elevated`, add: `skater.is_elevated = _is_elevated`
- This ensures the host's RemoteController keeps the Skater's elevation flag current from received inputs

### Step 3 — `puck.gd`: per-skater cooldowns + catch/deflect + poke check
- Add `puck_stripped(ex_carrier: Skater)` signal
- Add exports: `deflect_elevation_angle: float = 35.0`, `poke_strip_speed: float = 6.0`, `poke_carrier_vel_blend: float = 0.5`, `poke_checker_cooldown: float = 0.1`
- Replace `_cooldown_timer: float` with `_cooldown_timers: Dictionary`
- Add helpers: `_is_on_cooldown(skater)`, `_set_cooldown(skater, duration)`, `_get_skater_from_area(area) -> Skater`
- Rewrite `_on_blade_entered`:
  - carrier != null path: team check → `_poke_check(checker_skater)` (no cooldown gate)
  - carrier == null path: cooldown gate → speed floor check → relative velocity → catch or deflect
- Rewrite `_deflect_off_blade(skater: Skater)`: shaft-perpendicular face normal, physical reflect, deflect_blend lerp, elevation tilt, per-skater cooldown
- Add `_poke_check(checker_skater: Skater)`: capture ex_carrier, compute strip dir, clear carrier, set velocity and cooldowns, emit `puck_stripped` then `puck_released`
- Update `release()`: per-skater cooldown for ex-carrier only
- Update `drop()`: per-skater cooldown for ex-carrier only
- Update `reset()`: `_cooldown_timers.clear()`
- Update `_physics_process`: tick `_cooldown_timers` dict (outside carrier/non-carrier branch so timers tick always)

### Step 4 — `puck_controller.gd`: handle puck_stripped signal
- In `setup()`: connect `puck.puck_stripped.connect(_on_puck_stripped)` (server only)
- Add `_on_puck_stripped(ex_carrier: Skater)`: iterate `GameManager.players`, find matching skater, if `not record.is_local` call `NetworkManager.send_puck_stolen(peer_id)`

### Step 5 — `network_manager.gd`: puck stolen RPC
- Add `send_puck_stolen(victim_peer_id: int)` helper
- Add `@rpc("authority", "reliable") notify_puck_stolen()` → calls `GameManager.on_local_player_puck_stolen()`

### Step 6 — `game_manager.gd`: helpers
- Add `static func get_skater_team(skater: Skater) -> Team` (same pattern as `movement_locked` — static func accessing `GameManager.players`)
- Add `func on_local_player_puck_stolen()`: calls `on_puck_released_network()` + `puck_controller.notify_local_puck_dropped()` on local player (same pattern as carrier-clearing in `on_goal_scored`)

---

## Tunable Exports (new)

| Parameter | Default | Location | Purpose |
|---|---|---|---|
| `deflect_elevation_angle` | 35.0° | `Puck` | Upward angle when tipping a deflection |
| `poke_strip_speed` | 6.0 m/s | `Puck` | Puck speed after a poke check |
| `poke_carrier_vel_blend` | 0.5 | `Puck` | How much the carrier blade vel contributes to strip direction |
| `poke_checker_cooldown` | 0.1 s | `Puck` | Brief delay before checker can pick up the freshly stripped puck |

---

## Files Changed

| File | Change |
|---|---|
| `Scripts/skater.gd` | `is_elevated`, `blade_world_velocity` tracking |
| `Scripts/skater_controller.gd` | Sync `is_elevated` to Skater in `_process_input` |
| `Scripts/puck.gd` | Per-skater cooldowns, relative-velocity catch/deflect, face-normal deflect, elevation, poke check, `puck_stripped` signal |
| `Scripts/puck_controller.gd` | `_on_puck_stripped` handler, RPC dispatch |
| `Scripts/network_manager.gd` | `send_puck_stolen` + `notify_puck_stolen` RPC |
| `Scripts/game_manager.gd` | `get_skater_team()`, `on_local_player_puck_stolen()` |
