# Networking Refactor Plan

A phased plan for fixing known networking bugs, adding observability tooling, and eventually introducing a host-authoritative state buffer with lag compensation.

## Collaboration Style

This refactor touches core networking architecture. Every phase is implemented **one step at a time**, with the developer reviewing each architectural decision and each code change before moving on. Claude Code should:

- Present the specific change and its rationale before making it
- Wait for explicit approval before editing files
- Flag any deviation from this plan immediately and ask before proceeding
- Never batch multiple phases into a single session without confirmation

---

## Phase 1 — Bug Fixes

These are targeted, self-contained fixes. Each should be reviewed and tested individually before moving to the next.

### 1a. Input sequence never incremented

**File:** `Scripts/controllers/local_controller.gd` — add `_next_sequence: int`, stamp `_current_input.sequence` immediately after `_gatherer.gather()` and before storing it in `_input_history`.
**Problem:** `InputState.sequence` defaults to `0` and is never incremented. Every input is sent with `sequence = 0`. The reconcile filter in `local_controller.gd:68` — `i.sequence > server_state.last_processed_sequence` — uses this to determine which inputs to replay after a reconcile. With all sequences at 0, the filter evaluates `0 > 0` (false) on every reconcile, so the entire input history is discarded and no replay happens.
**Fix:** Maintain a monotonically incrementing counter (e.g. `_next_sequence: int`) and stamp each `InputState` before it is pushed to the history buffer and sent to the host.

### 1b. Reliable carrier change notification to non-carrier clients

**Files:** `Scripts/networking/network_manager.gd`, `Scripts/game/game_manager.gd`, `Scripts/controllers/puck_controller.gd`
**Problem:** The carrier's own machine receives a reliable RPC (`notify_puck_picked_up`) when it picks up the puck. All *other* clients only learn the carrier changed via `carrier_peer_id` embedded in the 20 Hz unreliable world state broadcast. A dropped packet means those clients never see the transition and keep the puck in interpolation or trajectory-prediction mode instead of rendering it pinned to a blade.
**Fix:** Add a reliable RPC broadcast (`notify_carrier_changed(new_carrier_peer_id: int)`) that the host sends to all peers (including non-carriers) whenever the carrier changes. `GameManager._on_server_puck_picked_up_by` and `_on_server_puck_released_by_carrier` are the two callsites. For the **carrier**, the existing `notify_local_pickup` path is unchanged. For **all other clients**, the new RPC handler calls a new `PuckController.notify_remote_carrier_changed(new_carrier_peer_id: int)` method that clears `_predicting_trajectory` and calls `puck.set_client_prediction_mode(false)` — exiting trajectory prediction without pinning to any blade. The world state `carrier_peer_id` field becomes a soft-reconcile fallback rather than the primary notification mechanism.

### 1c. Velocity reconcile threshold too tight

**File:** `Scripts/controllers/local_controller.gd:5`
**Problem:** `reconcile_velocity_threshold = 0.1 m/s`. At max speed ~9 m/s that is ~1% tolerance. At 240 Hz physics with any floating-point drift, this trips on nearly every world state broadcast, causing continuous reset+replay churn that wastes CPU and can cause visible jitter.
**Fix:** Bump to `0.4 m/s` (midpoint of the 0.3–0.5 reasonable range). This is an `@export` so it can be tuned in the editor without a code change. The position threshold (`0.05 m`) is fine as-is.

### 1d. No extrapolation on interpolation buffer starvation

**Files:** `Scripts/networking/buffered_state_interpolator.gd`, `Scripts/controllers/remote_controller.gd`, `Scripts/controllers/puck_controller.gd`, `Scripts/controllers/goalie_controller.gd`
**Problem:** `find_bracket` returns null when the buffer has fewer than 2 entries; callers early-return and hold whatever position was last applied. When render_time merely overshoots the newest snapshot, `find_bracket` already returns `(newest, newest, 1.0)` so callers hold the newest known position. Both cases result in a visible hold for fast-moving actors; extrapolating with the newest state's velocity (up to the cap) makes the hold period seamless.
**Fix:** When render_time overshoots the newest snapshot, extrapolate using the newest state's velocity for up to a configurable cap (`extrapolation_max_ms`, default 50 ms). Beyond the cap, hold the last known position rather than extrapolating further. Because the state types differ per controller, extrapolation logic lives in each controller (not in `BufferedStateInterpolator`); the shared helper can return a flag or a typed result indicating "past end of buffer" so callers know to extrapolate.

### 1e. No monotonic timestamp guard on buffer appends

**Files:** `Scripts/controllers/remote_controller.gd:39–42`, `Scripts/controllers/puck_controller.gd`, `Scripts/controllers/goalie_controller.gd`
**Problem:** Buffer appends do not check that the incoming timestamp is newer than the current tail. `unreliable_ordered` makes out-of-order delivery unlikely but not impossible under driver quirks.
**Note:** The buffers currently timestamp entries with `_current_time` — a local accumulator that always increases. With local timestamps a late-arriving packet gets a newer timestamp than the one before it, so this guard would never fire. **The actual fix belongs in Phase 4**, once world state packets carry host-supplied timestamps that can genuinely arrive out of order. This entry exists to document the gap; implementation is deferred.

---

## Phase 2 — Telemetry Overlay

**Goal:** Before simulating bad network conditions, establish a debug overlay that makes network health observable in real time. This is the instrument panel you will use to verify every subsequent phase.

**Approach:** A toggleable in-game overlay (e.g. F3) rendered on a high-priority `CanvasLayer`. Data requires minimal instrumentation additions (counters only) to controllers — no changes to networking or movement logic. Telemetry data is aggregated in a lightweight `NetworkTelemetry` autoload (or a `RefCounted` owned by `GameManager`); controllers call into it with narrow methods like `NetworkTelemetry.record_reconcile(delta_m: float)`, keeping observation decoupled from the systems being observed.

**Suggested metrics:**

| Metric | Source |
|--------|--------|
| Estimated RTT (ms) | Measured in Phase 4 clock sync; placeholder until then |
| World state recv rate (Hz) | Count broadcasts received per second on client |
| Input send rate (Hz) | Count inputs dispatched per second on client |
| Reconcile frequency (per sec) | Count reconcile triggers in `LocalController` |
| Reconcile magnitude (avg m) | Position delta at reconcile trigger |
| Interpolation buffer depth | `_state_buffer.size()` on `RemoteController` / `PuckController` |
| Buffer starvation events | Count of ticks where `find_bracket` returned null (pre-fix) or extrapolation fired (post-fix) |
| Input sequence gaps | Gaps in sequence numbers seen by host (requires Phase 1a first) |
| Carrier state mismatches | Count of ticks where world-state `carrier_peer_id` disagrees with local carrier belief |

The exact set of metrics is decided during implementation — this is a starting point for review.

---

## Phase 3 — Simulated Lag

**Goal:** Allow the developer to test all subsequent phases locally as if running on real ping, without needing a second machine.

**Approach:** A new autoload singleton `NetworkSimManager` (`Scripts/networking/network_sim.gd`) owns a pending-packet queue and processes it each frame. `NetworkManager` wraps its send sites to route through the sim when enabled. Because the delay is applied independently at each receive site, both directions of the loopback are delayed separately, properly simulating a realistic round-trip.

**New file — `Scripts/networking/network_sim.gd`:**

```gdscript
class_name NetworkSimManager
extends Node
# Autoload singleton.

var enabled: bool = false
var delay_ms: float = 0.0   # one-way; set to 50 for ~100 ms RTT simulation
var jitter_ms: float = 0.0  # +/- uniform jitter added to each packet
var loss_pct: float = 0.0   # 0–100; unreliable packets only

class PendingPacket:
    var fire_time: float
    var callable: Callable
    var args: Array

var _pending: Array[PendingPacket] = []

func send(c: Callable, args: Array, reliable: bool) -> void:
    if not enabled:
        c.callv(args); return
    if not reliable and randf() * 100.0 < loss_pct:
        return  # dropped
    var jitter := randf_range(-jitter_ms, jitter_ms)
    var d := maxf((delay_ms + jitter) / 1000.0, 0.0)
    if d <= 0.0:
        c.callv(args); return
    var p := PendingPacket.new()
    p.fire_time = Time.get_ticks_msec() / 1000.0 + d
    p.callable = c
    p.args = args
    _pending.append(p)

func _process(_delta: float) -> void:
    if _pending.is_empty(): return
    _pending.sort_custom(func(a, b): return a.fire_time < b.fire_time)
    var now := Time.get_ticks_msec() / 1000.0
    while not _pending.is_empty() and _pending[0].fire_time <= now:
        var p: PendingPacket = _pending.pop_front()
        p.callable.callv(p.args)
```

**`NetworkManager` integration:** At each receive site, wrap the payload dispatch through `NetworkSimManager.send`. Example for world state:

```gdscript
@rpc("authority", "unreliable_ordered")
func receive_world_state(state: Array) -> void:
    if is_host: return
    NetworkSimManager.send(world_state_received.emit, [state], false)
```

Same pattern for `receive_input` on the host side (`reliable: false`). Reliable RPCs pass `true` for the `reliable` flag so packet loss is never simulated for them.

With `NetworkSimManager.enabled = false`, the only overhead is a single bool check per RPC — no allocations, no timers.

**Review gate:** Before moving to Phase 4, verify with the telemetry overlay that simulated lag produces the expected degradation in buffer depth, reconcile frequency, and starvation events — and that the Phase 1 fixes hold up under those conditions.

---

## Phase 4 — Host Clock Synchronisation

**Goal:** All peers share a common understanding of host time. This replaces input sequence numbers as the primary ordering and reconciliation key, and is the prerequisite for the state buffer and lag compensation.

**Approach:** NTP-style ongoing RTT sampling.

**Protocol (per client):**
1. On connect, immediately fire N rapid pings (e.g. 3 pings, 0.5s apart) to establish a baseline quickly.
2. Host replies to each ping with `client_send_time` (echoed) + `host_time_at_receive` + `host_time_at_send`.
3. Client computes per sample:
   - `rtt = client_receive_time - client_send_time`
   - `host_time_offset = host_time_at_receive + (rtt / 2.0) - client_receive_time`
4. Once all N initial responses arrive, compute the initial estimate and mark the clock as **ready**. Switch to a slow ongoing cadence (e.g. every 5 seconds) for drift correction. Maintain a small rolling window of samples (e.g. 8), discard the two highest-RTT outliers, average the rest.
5. Expose `NetworkManager.estimated_host_time() -> float` on all peers. Returns invalid / asserts until clock is ready.

**Bootstrap:** The rapid initial pings run during the lobby phase, so the clock is settled before the game starts. `LocalInputGatherer` does not stamp host timestamps until the clock is marked ready.

**Join-in-progress:** When a client joins a game already in progress there is no lobby phase to absorb the warm-up window. Options include showing a brief loading screen until the initial pings complete (~1.5s), or spawning the player immediately with `_host_time_offset = 0.0` and accepting some reconcile weirdness until the baseline arrives. **Decision deferred to implementation** — evaluate which feels better in practice.

**Input timestamp migration:**
- `InputState.sequence: int` is replaced with `InputState.host_timestamp: float`.
- `LocalInputGatherer` stamps each input with `NetworkManager.estimated_host_time()` at gather time.
- `SkaterNetworkState.last_processed_sequence` becomes `last_processed_host_timestamp: float`.
- The reconcile filter in `LocalController` filters by timestamp instead of sequence.
- `RemoteController` uses timestamp for input ordering on the host.
- **Monotonic guard (from 1e):** Now that state packets carry host-supplied timestamps, add the one-line guard to buffer appends — if `new_state.host_timestamp ≤ buffer.back().host_timestamp`, discard. This is where 1e becomes meaningful.

**Wire format note:** Replacing `last_processed_sequence: int` with `last_processed_host_timestamp: float` in `SkaterNetworkState` is a breaking wire format change — old and new builds cannot interoperate. Expected for early development; note in release changelog.

**Review gates:**
- Telemetry overlay shows stable RTT estimate and low variance across samples.
- Under simulated lag (Phase 3), the offset estimate stays accurate.
- Input replay works correctly after a reconcile (validates Phase 1a fix in the new system).

---

## Phase 5 — StateBufferManager

**Goal:** The host maintains a rolling, high-fidelity history of all actor states. This is the foundation for lag compensation and replaces direct actor queries in the world state broadcast.

**New class:** `StateBufferManager` (application layer, `Scripts/game/state_buffer_manager.gd`). Instantiated and owned by `GameManager`.

**Capture (host only, every physics tick at 240 Hz):**
- Snapshot all skaters, the puck, and both goalies into compact state objects.
- State objects are the existing network state types (`SkaterNetworkState`, `PuckNetworkState`, `GoalieNetworkState`) extended with a `host_timestamp: float` field.
- Append to a per-actor rolling buffer. Trim entries older than a configurable window (`buffer_duration_secs`, default 3.0).

**Memory estimate:** ~155 values × 720 frames (3 s at 240 Hz) ≈ 450 KB. Well within budget.

**Allocation strategy:** Use a pre-allocated ring buffer per actor — a fixed-size Array of state objects created once at startup. Each tick overwrites the current slot and advances a write pointer rather than appending new objects, avoiding per-tick allocation and GC pressure. This is the canonical pattern in game networking: Quake III Arena uses exactly this approach (`PACKET_BACKUP = 32` slots, single `Hunk_Alloc` at startup, writes indexed via `nextSnapshotEntities % numSnapshotEntities` — see `sv_snapshot.c`). References for implementation:
- Quake III Arena source (`sv_snapshot.c`, MIT): https://github.com/id-Software/Quake-III-Arena/blob/master/code/server/sv_snapshot.c
- Fabien Sanglard's Quake 3 network model walkthrough: https://fabiensanglard.net/quake3/network.php
- Glenn Fiedler — Snapshot Interpolation: https://gafferongames.com/post/snapshot_interpolation/
- Valve — Latency Compensating Methods: https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization

**WorldStateCodec integration:**
- `WorldStateCodec` currently reads actor state by calling into live scene nodes.
- After this phase, it reads from `StateBufferManager.latest_state()` instead.
- This is a refactor of the data path only — wire format and RPC structure are unchanged.

**Query API (used by lag compensation in Phase 7):**
- `get_state_at(host_timestamp: float) -> WorldSnapshot` — interpolates between the two bracketing entries.
- `WorldSnapshot` is a flat struct holding all actor states at a point in time.

**Review gates:**
- Telemetry overlay shows buffer depth and trim cadence.
- World state broadcasts are bit-identical to pre-refactor (no behaviour change, only data-path change).
- Memory usage is profiled and confirmed within budget.

---

## Phase 6 — Interaction Logic Refactor

**Goal:** All interaction detection (puck pickup, poke check, body check, body block, deflection, and goalie contact) is moved from Godot physics callbacks (`Area3D` overlaps in `puck.gd`) into the domain layer as pure geometric functions operating on state snapshots. This creates a single consistent code path for all interactions. Player interactions are additionally usable by lag-compensated rewind (Phase 7); goalie contact is host-only AI with no client claims, so it benefits from the consistency and testability but is not lag-compensated.

**Tunneling:** Interaction checks use **swept sphere** geometry (ray-sphere intersection from previous position to current position), not point-in-sphere. This provides tunneling protection equivalent to CCD for interaction zones. Jolt CCD remains enabled on the puck for wall/rink geometry collisions.

**Domain changes (`Scripts/domain/rules/puck_collision_rules.gd` and new sibling files):**

New pure static functions, e.g.:
- `check_pickup(puck_prev: Vector3, puck_curr: Vector3, blade_pos: Vector3, pickup_radius: float) -> bool`
- `check_poke(puck_prev: Vector3, puck_curr: Vector3, blade_prev: Vector3, blade_curr: Vector3, poke_radius: float) -> bool`
- `check_body_contact(puck_prev: Vector3, puck_curr: Vector3, skater_pos: Vector3, body_radius: float) -> ContactResult`
- `check_goalie_contact(puck_prev: Vector3, puck_curr: Vector3, goalie_body_positions: Array[Vector3], contact_radius: float) -> bool`

All take state values (positions, velocities) — no scene node references. All are unit-testable.

**Host integration:**
- `PuckController._physics_process` (or a new `InteractionSystem`) runs these checks each tick against the latest `StateBufferManager` entry.
- Results emit the same signals as the current Area3D path (`puck_picked_up_by`, etc.) so `GameManager` wiring is unchanged.
- `Area3D` nodes are removed from `puck.gd` (scene edit by developer).

**Review gates:**
- All existing interaction unit tests pass.
- New unit tests cover swept sphere edge cases (high speed, tangential pass, near-miss).
- Behaviour in play matches pre-refactor (use telemetry to compare reconcile rates and carrier events).

---

## Phase 7 — Lag Compensation

**Goal:** Clients can send timestamped interaction claims. The host verifies against the state buffer at the client's send time and accepts or overrides accordingly.

**Claim types:** puck pickup, poke check, body check, body block, deflection (the same set targeted in Phase 6).

**Protocol:**
1. Client detects a potential interaction locally (using the same domain functions from Phase 6).
2. Client sends a reliable RPC claim: `{ type, host_timestamp, relevant_state_snapshot }`.
3. Host receives claim, looks up `StateBufferManager.get_state_at(host_timestamp - rtt_compensation)`.
4. Runs the appropriate Phase 6 domain check against the rewound state.
5. If the check passes: host applies the interaction authoritatively (same path as if it had detected it itself).
6. If the check fails: host ignores the claim; its own real-time detection remains authoritative.

**RTT compensation:** The host adjusts the rewind timestamp by half the measured RTT for that client, so it rewinds to approximately what the client *saw* when they acted.

**Anti-abuse guard:** Claims are only accepted within a configurable time window (`max_claim_age_ms`, default = 200 ms). Claims outside this window are silently dropped.

**Review gates:**
- Under simulated lag (Phase 3), pickup and poke check interactions feel responsive at the client without host disagreement.
- Telemetry shows claim accept/reject rate.
- Stress test: high packet loss + high latency should not allow false claim acceptance.

---

## Dependency Graph

```
Phase 1 (Bug Fixes)
    └── Phase 2 (Telemetry)
            └── Phase 3 (Simulated Lag)
                    └── Phase 4 (Host Clock Sync)
                            └── Phase 5 (StateBufferManager)
                                    └── Phase 6 (Interaction Refactor)
                                            └── Phase 7 (Lag Compensation)
```

Each phase gates the next. Do not begin a phase until the previous one has been reviewed, tested under simulated conditions, and explicitly signed off.
