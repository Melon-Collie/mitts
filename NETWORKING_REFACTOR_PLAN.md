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
**Problem:** When `render_time` overruns the newest snapshot in the buffer (one missed packet is enough), `find_bracket` returns `null` and every caller silently does nothing — the actor freezes until the next packet arrives. In a fast game this is a visible hitch.
**Fix:** When render_time overshoots the newest snapshot, extrapolate using the newest state's velocity for up to a configurable cap (`extrapolation_max_ms`, default 50 ms). Beyond the cap, hold the last known position rather than extrapolating further. Because the state types differ per controller, extrapolation logic lives in each controller (not in `BufferedStateInterpolator`); the shared helper can return a flag or a typed result indicating "past end of buffer" so callers know to extrapolate.

### 1e. No monotonic timestamp guard on buffer appends

**Files:** `Scripts/controllers/remote_controller.gd:39–42`, `Scripts/controllers/puck_controller.gd`, `Scripts/controllers/goalie_controller.gd`
**Problem:** Buffer appends do not check that the incoming timestamp is newer than the current tail. `unreliable_ordered` makes out-of-order delivery unlikely but not impossible under driver quirks.
**Fix:** One-line guard before each append: if the new state's timestamp is ≤ the tail's timestamp, discard it. No structural changes needed.

---

## Phase 2 — Telemetry Overlay

**Goal:** Before simulating bad network conditions, establish a debug overlay that makes network health observable in real time. This is the instrument panel you will use to verify every subsequent phase.

**Approach:** A toggleable in-game overlay (e.g. F3) rendered on a high-priority `CanvasLayer`. All data is gathered passively — no changes to networking logic.

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

**Approach:** A debug-only shim in `NetworkManager` that intercepts outgoing and incoming packets and holds them in a queue for a configurable delay before processing. Configurable via `@export` vars (not behind a build flag — just set to zero in production use):

- `sim_lag_one_way_ms: int = 0` — added delay in each direction (set to 50 for 100ms RTT simulation)
- `sim_packet_loss_pct: float = 0.0` — probability of silently dropping any given packet (0.0–1.0)

Because this runs on loopback, the delay must be applied in both directions independently to properly simulate a realistic network round-trip. The telemetry overlay from Phase 2 should visibly reflect the simulated conditions.

**Review gate:** Before moving to Phase 4, verify with the telemetry overlay that simulated lag produces the expected degradation in buffer depth, reconcile frequency, and starvation events — and that the Phase 1 fixes hold up under those conditions.

---

## Phase 4 — Host Clock Synchronisation

**Goal:** All peers share a common understanding of host time. This replaces input sequence numbers as the primary ordering and reconciliation key, and is the prerequisite for the state buffer and lag compensation.

**Approach:** NTP-style ongoing RTT sampling.

**Protocol (per client):**
1. Client sends a ping to host carrying `client_send_time` (client's local monotonic clock).
2. Host replies with `client_send_time` (echoed) + `host_time_at_receive` + `host_time_at_send`.
3. Client computes:
   - `rtt = client_receive_time - client_send_time`
   - `host_time_offset = host_time_at_receive + (rtt / 2.0) - client_receive_time`
4. Repeat at a low cadence (e.g. every 5 seconds). Maintain a small rolling window of samples (e.g. 8), discard the two highest-RTT outliers, average the rest.
5. Expose `NetworkManager.estimated_host_time() -> float` on all peers.

**Input timestamp migration:**
- `InputState.sequence: int` is replaced with `InputState.host_timestamp: float`.
- `LocalInputGatherer` stamps each input with `NetworkManager.estimated_host_time()` at gather time.
- `SkaterNetworkState.last_processed_sequence` becomes `last_processed_host_timestamp: float`.
- The reconcile filter in `LocalController` filters by timestamp instead of sequence.
- `RemoteController` uses timestamp for input ordering on the host.

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

**Goal:** All interaction detection (puck pickup, poke check, body check, body block, deflection) is moved from Godot physics callbacks (`Area3D` overlaps in `puck.gd`) into the domain layer as pure geometric functions operating on state snapshots. This creates a single code path usable by both real-time host physics and lag-compensated rewind.

**Tunneling:** Interaction checks use **swept sphere** geometry (ray-sphere intersection from previous position to current position), not point-in-sphere. This provides tunneling protection equivalent to CCD for interaction zones. Jolt CCD remains enabled on the puck for wall/rink geometry collisions.

**Domain changes (`Scripts/domain/rules/puck_collision_rules.gd` and new sibling files):**

New pure static functions, e.g.:
- `check_pickup(puck_prev: Vector3, puck_curr: Vector3, blade_pos: Vector3, pickup_radius: float) -> bool`
- `check_poke(puck_prev: Vector3, puck_curr: Vector3, blade_prev: Vector3, blade_curr: Vector3, poke_radius: float) -> bool`
- `check_body_contact(puck_prev: Vector3, puck_curr: Vector3, skater_pos: Vector3, body_radius: float) -> ContactResult`

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
