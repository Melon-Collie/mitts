# Game Flow Plan

## Overview

This spec covers the first pass at "real game" infrastructure: team assignment, goal detection, score tracking, and the post-goal faceoff sequence. The goal is the minimal working loop — puck goes in net → goal is awarded → players reset → puck drops → play resumes. No UI spec is finalized here; HUD work follows separately.

---

## 1. Team Object

A new `Team` class (plain GDScript, extends `RefCounted` implicitly) owns the relationships that currently float around as implicit index correspondence:

```gdscript
class_name Team

var team_id: int = 0                          # 0 or 1 — used for wire serialization only
var defended_goal: HockeyGoal = null          # the net this team protects
var goalie_controller: GoalieController = null
var score: int = 0
```

`game_manager.gd` creates two `Team` instances at world spawn and assigns their `defended_goal` and `goalie_controller` at that time. `PlayerRecord.team` holds a `Team` reference (not an int). The `team_id` int is used only when sending data over RPCs.

**Why not put players on the Team?** `game_manager.players` is already the authoritative dictionary. Querying `players.values().filter(func(r): return r.team == team)` is straightforward and avoids a circular reference.

---

## 2. Team Assignment

### Slots vs. teams are separate concerns

Slot (join order, 0–5) and team are **decoupled**. The slot is a stable identity index; the team is a lobby decision that will eventually come from a UI scene. For now the host auto-balances.

**Auto-balance (placeholder):**
```gdscript
# game_manager.gd
func _assign_team() -> Team:
    var t0_count: int = players.values().filter(func(r): return r.team == teams[0]).size()
    var t1_count: int = players.values().filter(func(r): return r.team == teams[1]).size()
    return teams[0] if t0_count <= t1_count else teams[1]
```

First player → Team 0, second → Team 1, alternating. Pure balancing, no derivation from slot.

**Future UI path:** Lobby passes a `preferred_team_id: int`; `_assign_team()` respects it if the team isn't full, otherwise falls back. No other code changes needed.

`team` is stored on `PlayerRecord` and the `team_id` is included in slot-assignment and sync RPCs so all peers reconstruct the correct Team mapping.

---

## 3. Goal Structure — Two Separate Scene Nodes

Currently `HockeyGoal` is a single `@tool` node that builds **both** nets in one `_rebuild()` pass. We split into **two separate `HockeyGoal` instances** in the scene, one per end.

### Script changes to `hockey_goal.gd`
- Add `@export var facing: int = 1` — `+1` for positive-Z end, `-1` for negative-Z end.
- `_rebuild()` calls `_build_goal(goal_z, facing, ...)` once instead of looping over both ends.
- `goal_z` computed from instance's own exports: `facing * (rink_length / 2.0 - distance_from_end)`.
- Add `goal_scored` signal and goal-mouth `Area3D` (see §4).

### Scene changes (user makes in Godot editor)
Replace the single `HockeyGoal` node with two nodes:
- `GoalTop` (`facing = -1`) — negative-Z end, defended by Team 1
- `GoalBottom` (`facing = +1`) — positive-Z end, defended by Team 0

`game_manager.gd` gets references to these via `get_node()` since they are static scene nodes, not runtime-spawned. References are assigned to `teams[0].defended_goal` and `teams[1].defended_goal` during `_spawn_world()`.

---

## 4. Goal Detection — Area3D on the Goal

Each `HockeyGoal` instance owns a goal-detection `Area3D`, built in `_rebuild()` alongside the posts and netting. Tunneling is not a concern: Jolt handles fast-moving bodies well, the physics tick is 240 Hz, and the net already has physical collision on all sides — the puck can only enter through the front opening.

### Area3D geometry
A `BoxShape3D` placed just inside the goal mouth:
- **Width:** `POST_HALF_WIDTH * 2` (1.83 m)
- **Height:** `NET_HEIGHT` (1.22 m)
- **Depth:** ~0.3 m — shallow enough not to overlap the physical netting behind
- **Position:** centered on the goal mouth, offset half its depth behind the goal line into the net

The Area3D collision mask must be set to detect only the puck's physics layer. The exact layer number will be confirmed at implementation time against the puck scene.

### Signal
```gdscript
signal goal_scored  # emitted by HockeyGoal, on host only
```

`_on_goal_area_body_entered(body)` checks `if body is Puck` before emitting.

`game_manager.gd` connects on the host during `_spawn_world()`, after assigning goals to teams:
```gdscript
for team: Team in teams:
    team.defended_goal.goal_scored.connect(func(): _on_goal_scored(_other_team(team)))
```

`_phase == PLAYING` guard lives in `_on_goal_scored()` so a puck rattling in the net during a dead puck can't score twice.

**Own goals count.** No carrier check required.

---

## 5. Score Tracking

Score lives on each `Team` object:
```gdscript
scoring_team.score += 1
```

No separate `score` array on `game_manager`. To read scores for broadcast: `teams[0].score`, `teams[1].score`.

---

## 6. Game Phase State Machine

```gdscript
enum GamePhase {
    PLAYING,         # normal gameplay
    GOAL_SCORED,     # goal animation window — shooting/pickup locked
    FACEOFF_PREP,    # players teleporting, puck resetting
    FACEOFF,         # puck live at center dot, waiting for pickup or timeout
}
var _phase: GamePhase = GamePhase.PLAYING
var _phase_timer: float = 0.0
```

**Phase transitions:**
```
PLAYING      → GOAL_SCORED   (on goal detection)
GOAL_SCORED  → FACEOFF_PREP  (after GOAL_PAUSE_DURATION — host teleports players, resets puck)
FACEOFF_PREP → FACEOFF       (after FACEOFF_PREP_DURATION)
FACEOFF      → PLAYING       (on puck pickup via puck.puck_picked_up signal, or after FACEOFF_TIMEOUT)
```

**Tunable durations (constants.gd):**
```gdscript
const GOAL_PAUSE_DURATION: float   = 2.0   # celebration freeze
const FACEOFF_PREP_DURATION: float = 0.5   # teleport settle time
const FACEOFF_TIMEOUT: float       = 10.0  # fallback if nobody picks up puck
```

`_phase` is read by other systems via `GameManager._phase`. If direct access feels too loose, a `get_phase() -> GamePhase` getter can be added later.

---

## 7. Input & Puck Locking

**During `GOAL_SCORED` and `FACEOFF_PREP`:**
- `LocalController` ignores shooting and puck interaction. Movement input also ignored — skaters coast to a stop via existing friction.
- `Puck` gains `pickup_locked: bool`, set by `game_manager.gd`, checked inside `_on_blade_entered` before pickup.

**During `FACEOFF`:**
- Movement input is fully live — players need to skate to the dot.
- Puck pickup is live.
- Shooting remains locked until the puck is held (existing "no puck" states handle this naturally).
- `FACEOFF → PLAYING` fires on the first `puck.puck_picked_up` signal received on the host.

---

## 8. Networking

### Goal event (reliable RPC, host → all clients)
```gdscript
@rpc("authority", "reliable")
func notify_goal(scoring_team_id: int, score0: int, score1: int) -> void
```
Clients → `GameManager.on_goal_scored(scoring_team_id, score0, score1)`:
1. Update `teams[0].score` and `teams[1].score`.
2. Transition `_phase` to `GOAL_SCORED`, start timer.

Host also calls `on_goal_scored()` locally (scores are already updated; RPC carries them as correction).

### Phase + score in world state
Three values appended at the end of every broadcast:
```
[..., teams[0].score, teams[1].score, phase_int]
```
Late-joining clients catch up immediately. Clients overwrite local score and phase from every broadcast.

### Faceoff teleport (reliable RPC, host → all clients)
```gdscript
@rpc("authority", "reliable")
func notify_faceoff_positions(positions: Array) -> void
```
`positions` is `[peer_id, x, y, z, ...]`. Clients snap their local skater to the matching position. Remote skaters reconcile to the new positions naturally via world state.

Fired when transitioning `GOAL_SCORED → FACEOFF_PREP`, after the host has already applied the teleport.

### Team in existing RPCs
`assign_player_slot` and `sync_existing_players` must include `team_id` so joining clients can reconstruct `PlayerRecord.team` correctly:
- `assign_player_slot(slot, team_id)` — updated signature
- `sync_existing_players` payload: `[peer_id, slot, team_id, ...]` per player

---

## 9. PlayerRecord — Team and Faceoff Position

```gdscript
var team: Team = null
var faceoff_position: Vector3 = Vector3.ZERO
```

`team` is a `Team` reference set by the host via `_assign_team()`. `faceoff_position` is set before each faceoff teleport and doubles as the initial spawn position — `SKATER_START_POSITIONS` is removed.

---

## 10. Faceoff Positions

Center ice faceoff for game start and all goals (v1 only uses center ice).

```gdscript
# constants.gd — indexed by slot
const CENTER_FACEOFF_POSITIONS: Array[Vector3] = [
    Vector3( 0.0, 1.0,  1.5),   # slot 0 — Team 0 center
    Vector3( 0.0, 1.0, -1.5),   # slot 1 — Team 1 center
    Vector3(-5.0, 1.0,  3.0),   # slot 2 — Team 0 left wing
    Vector3(-5.0, 1.0, -3.0),   # slot 3 — Team 1 left wing
    Vector3( 5.0, 1.0,  3.0),   # slot 4 — Team 0 right wing
    Vector3( 5.0, 1.0, -3.0),   # slot 5 — Team 1 right wing
]
```

> **Note:** Slot-indexed positions assume balanced team assignment. If future team selection allows stacking, positions will need to be computed dynamically from (team, role) instead.

Puck resets via `puck.reset()` (already zeroes velocity and re-centers) during `FACEOFF_PREP`.

---

## 11. Goalie Reset

`GoalieController` gets `reset_to_crease()` — snaps to crease center, resets state to `STANDING`, clears `_tracked_puck_position`. Called by `game_manager.gd` on both goalie controllers during `FACEOFF_PREP`.

---

## 12. HUD (deferred)

Requires `CanvasLayer` / `Label` nodes added by the user in the Godot editor. The data layer is fully implemented by this spec.

`game_manager.gd` emits:
```gdscript
signal goal_scored(scoring_team: Team)
signal score_changed(team: Team)
signal phase_changed(new_phase: GamePhase)
```

---

## 13. Files to Touch

| File | Change |
|------|--------|
| `team.gd` | **New file.** `team_id`, `defended_goal`, `goalie_controller`, `score` |
| `hockey_goal.gd` | Add `facing` export, build one goal per instance, compute `goal_z` from self, add `goal_scored` signal and goal-mouth `Area3D` in `_rebuild()` |
| `constants.gd` | Add `GOAL_PAUSE_DURATION`, `FACEOFF_PREP_DURATION`, `FACEOFF_TIMEOUT`, `CENTER_FACEOFF_POSITIONS`; remove `SKATER_START_POSITIONS` |
| `player_record.gd` | Add `team: Team`, `faceoff_position: Vector3` |
| `game_manager.gd` | Add `teams` array, `Team` creation in `_spawn_world()`, `_assign_team()`, goal signal connections, `_phase` FSM, faceoff logic, signals |
| `network_manager.gd` | Add `notify_goal`, `notify_faceoff_positions` RPCs; add `team_id` to slot/sync payloads; append score+phase to world state |
| `puck.gd` | Add `pickup_locked: bool`, checked in `_on_blade_entered` |
| `goalie_controller.gd` | Add `reset_to_crease()` |
| `local_controller.gd` | Gate all input during `GOAL_SCORED` and `FACEOFF_PREP`; movement live during `FACEOFF` |

**Scene changes (user makes in Godot editor):**
- Replace single `HockeyGoal` with two instances: `GoalTop` (`facing = -1`) and `GoalBottom` (`facing = +1`).

---

## Open Questions

1. **End-zone faceoffs?** (icing, offsides) — out of scope for v1; all stoppages go to center ice.
2. **Winning condition / period clock?** — not addressed; score increments indefinitely for now.
3. **Real faceoff mechanic?** (contested puck drop) — timeout covers the simple case; can layer on later without architectural changes.
4. **Goal credited to scorer?** — out of scope for v1; `_on_goal_scored` could accept `scorer_peer_id` later.
