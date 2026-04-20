# Netcode Improvements

Planned improvements that take the networking from correct to excellent.
None of these fix bugs — the game works without them. They improve
responsiveness, stability under bad connections, bandwidth efficiency, and
competitive fairness.

Apply fixes in `NETCODE_FIXES.md` first. Each improvement here notes its
dependencies.

## Collaboration Style

Same as previous networking plans: present the specific change and rationale
before editing any file. Wait for explicit approval before proceeding.

---

## Improvement 1 — Input Queue Depth Feedback Loop

**Files:** `Scripts/game/world_state_codec.gd`, `Scripts/controllers/remote_controller.gd`,
`Scripts/networking/clock_sync.gd`, `Scripts/networking/network_manager.gd`

**Problem:** `ClockSync` calibrates `_offset` from 3 initial pings, then refines
every 5 seconds. Between refinements the client's `estimated_host_time()` can drift.
There is currently no feedback from the host telling the client whether its inputs
are arriving early, on time, or late. A slow drift of 1ms/s is imperceptible in
telemetry and goes uncorrected until the next ping — and the ping average may not
catch it either if the drift is consistent.

The ground truth is the host's input queue depth for each peer. A deep queue means
the client is running fast (inputs arriving early); a depth of 0 with fallback
firings means the client is running slow.

**Plan:**

1. Include per-peer input queue depth in the world state broadcast. One byte per
   skater added to the skater section of the wire array. The host reads it from
   `RemoteController.get_queue_depth()` (already exists) at encode time.

2. On the client, `WorldStateCodec.decode_world_state` extracts the depth for the
   local peer and calls a new `NetworkManager.on_queue_depth_received(depth: int)`.

3. `NetworkManager` passes this to `ClockSync` which applies a small nudge:
   ```gdscript
   const TARGET_DEPTH: int = 2
   const NUDGE_RATE: float = 0.0005  # 0.5ms per correction step
   func apply_queue_depth_feedback(depth: int) -> void:
       var error: int = depth - TARGET_DEPTH
       _offset -= error * NUDGE_RATE  # positive error = running fast = slow down
   ```
   The target of 2 inputs keeps a small buffer against jitter without
   accumulating lag.

4. Add queue depth to `NetworkTelemetry` and the debug overlay so drift is
   visible before it becomes a problem.

**Note:** The nudge rate (0.5ms per step at 20 Hz = 10ms/s max correction) is
conservative. Tune after observing real drift rates in play sessions.

---

## Improvement 2 — Per-Packet Sequence Numbers and Packet Loss Measurement

**Files:** `Scripts/game/world_state_codec.gd`, `Scripts/networking/network_manager.gd`,
`Scripts/networking/network_telemetry.gd`, `Scripts/ui/network_debug_overlay.gd`

**Problem:** There is currently zero visibility into packet loss. The only indirect
signal is `is_extrapolating` on interpolation buffers. You cannot distinguish a
lossy connection from a slow one, and you cannot measure whether the 12-frame
redundant input batch is actually sufficient.

**Plan:**

1. Add a `uint16` sequence number to the world state wire array (header, before
   skater data).

2. The host increments it on every broadcast. Clients track `_last_received_seq:
   int`. Gaps in the sequence indicate dropped packets.

3. Clients echo the last received sequence in each input batch header (a free ACK
   riding on an existing unreliable packet — no new RPCs).

4. The host computes per-peer packet loss rate over a rolling 1-second window:
   ```
   loss_rate = (expected_packets - received_packets) / expected_packets
   ```
   where `expected_packets` is inferred from elapsed time × `STATE_RATE`.

5. Loss rate goes into `NetworkTelemetry` and the debug overlay.

**Unlocks:** Improvement 3 (dynamic batch window) and Improvement 4 (adaptive
jitter buffer) both depend on this data.

---

## Improvement 3 — Dynamic Input Batch Window

**Files:** `Scripts/controllers/local_controller.gd`, `Scripts/networking/network_manager.gd`

**Problem:** The redundant input batch window is fixed at 12 frames (50ms at 240 Hz).
This covers a single dropped packet. At 20% packet loss, two consecutive drops
happen ~4% of the time — enough to lose `shoot_pressed` inputs and cause shots that
fire on the client but not the host. At low loss rates, the fixed window is fine.

**Plan:**

Read the host's measured loss rate for this peer (from Improvement 2) and expand
the batch window when loss is elevated:

```gdscript
# NetworkManager._process, when building the batch:
var loss_rate: float = NetworkManager.get_peer_loss_rate()
var batch_frames: int = 24 if loss_rate > 0.10 else 12
var batch: Array[InputState] = _local_controller.get_input_batch(batch_frames)
```

Update `LocalController.get_input_batch` to accept a `frames: int` parameter
instead of hardcoding 12.

At 18 bytes per InputState, expanding to 24 frames adds ~215 bytes per batch at
20 Hz = ~4.3 KB/s — well within budget.

**Dependency:** Improvement 2 for loss rate measurement.

---

## Improvement 4 — Ghost State Reliable RPCs

**Files:** `Scripts/game/game_manager.gd`, `Scripts/networking/network_manager.gd`,
`Scripts/controllers/remote_controller.gd`

**Problem:** Ghost state transitions (offside, icing) are delivered via world state
at 20 Hz — up to 50ms late for remote players. During those 50ms, a player who is
ghosted on the host appears solid on other clients: they look collidable, they look
eligible to receive a pass. At 8 m/s that's a 40cm window of incorrect state.

The local player already gets instant offside feedback via `_predict_offside`. Remote
players don't.

**Plan:**

1. Track per-peer ghost state on the host: `_last_ghost_state: Dictionary[int, bool]`.
   Populated in `_apply_ghost_state`.

2. On every ghost state transition, emit a reliable RPC immediately rather than
   waiting for the next world state broadcast:
   ```gdscript
   if new_ghost != _last_ghost_state.get(peer_id, false):
       _last_ghost_state[peer_id] = new_ghost
       NetworkManager.send_ghost_state_to_all(peer_id, new_ghost)
   ```

3. `RemoteController.apply_ghost_rpc(is_ghost: bool)` sets the ghost state
   immediately on the visual representation. World state `is_ghost` continues as
   a fallback for correction and for clients that join mid-game.

---

## Improvement 5 — Adaptive Jitter Buffer

**Files:** `Scripts/controllers/remote_controller.gd`,
`Scripts/controllers/puck_controller.gd`, `Scripts/controllers/goalie_controller.gd`

**Problem:** `interpolation_delay` is a fixed compile-time constant (66ms). On LAN
(2ms RTT, near-zero jitter) this adds 64ms of unnecessary latency to all remote
actor positions. On a variable connection (40ms RTT, 20ms jitter) 66ms is
occasionally too shallow and `is_extrapolating` fires, causing visible stuttering.
A single value cannot be correct for all connections.

**Plan:**

Measure inter-arrival jitter of world state packets. Maintain a rolling 2-second
window of `|actual_interval - expected_interval|` samples per client. Compute a
target delay:

```
target_delay = (rtt / 2) + (P95_jitter * 1.5)
```

Adjust `interpolation_delay` slowly toward the target to avoid visible jumps:

```gdscript
# In each controller's _process or _interpolate:
var target: float = _compute_target_delay()
interpolation_delay = move_toward(interpolation_delay, target, MAX_ADJUST_RATE * delta)
# MAX_ADJUST_RATE = 0.005 (5ms per second)
```

Set a floor (`min_delay = rtt / 2`) and ceiling (`max_delay = 150ms`) to prevent
degenerate values.

**Dependency:** Improvement 2 for packet arrival timestamps (needed for jitter
measurement). The `rtt` value comes from `ClockSync`.

---

## Improvement 6 — Delta Compression / World State Quantization

**File:** `Scripts/game/world_state_codec.gd`

**Problem:** Each world state broadcast is ~520 bytes at 20 Hz = ~83 KB/s upstream.
Fine for broadband; problematic on mobile hotspots and shared connections. The typed
`SkaterNetworkState` objects are the right internal representation — compression lives
entirely at the wire boundary.

**Plan:**

Quantize the flat wire array before sending:

| Field | Current | Quantized | Notes |
|-------|---------|-----------|-------|
| Position X/Z | float32 | int16 (1cm) | 26m range → 2600 steps |
| Position Y | float32 | uint8 (1cm) | small range |
| Velocity X/Y/Z | float32 | int16 (0.1 m/s) | ±30 m/s → 600 steps |
| Blade/hand pos | float32×3 | int8×3 (1cm) | encoded as offset from skater position (±1.5m range) |
| Facing / rotations | float32 | uint16 (0.006°) | full circle, 360/0.006 = 60000 steps |

Rough post-quantization size: ~16 bytes per skater vs ~72 current. Six skaters:
~96 bytes vs ~432. Total packet: ~200 bytes vs ~520 — approximately 60% reduction.

Encode/decode lives entirely in `WorldStateCodec`. The typed state objects
(`SkaterNetworkState`, etc.) remain unchanged throughout the rest of the codebase.

Wire format version bump required — old and new builds cannot interoperate.

---

## Improvement 7 — Rewind-Based Hit Detection

**Files:** `Scripts/game/game_manager.gd`, `Scripts/networking/network_manager.gd`

**Problem:** Body check crediting (`HitTracker.on_hit`) fires when Godot's physics
detects contact on the host — based on where players are right now, not where they
were when the checking player initiated contact. At 80ms RTT the hit victim has moved
~50cm since the checker saw them. False negatives (missed hit credit) are common in
close puck battles.

**Plan:**

Mirror the pickup claim system for body checks:

1. When `LocalController` detects a local body check contact (`body_checked_player`
   signal on the local skater), send a reliable `receive_hit_claim(peer_id,
   host_timestamp, rtt_ms)` RPC to the host.

2. Host handler (`_on_hit_claim_received`) rewinds `StateBufferManager` to
   `host_timestamp - rtt_ms / 2000.0`, checks whether the victim was within
   body-check contact range of the checker at that time, and calls
   `HitTracker.on_hit` if valid.

3. The existing Godot-physics-based hit detection on the host remains authoritative
   for server-side contact. The claim path adds lag-compensated crediting for
   client-initiated checks that the host's current-frame test would miss.

---

## Improvement 8 — Rollback for Shot Resolution

**Files:** `Scripts/game/game_manager.gd`, `Scripts/controllers/goalie_controller.gd`,
`Scripts/controllers/puck_controller.gd`

**Problem:** When a shot fires, the host resolves it from the current simulation
state — the goalie is where it is now, not where the shooter saw it. At 80ms RTT
the goalie may have moved significantly since the shooter released. Shots that
visually go in on the client are overridden by the host. This is the single largest
remaining source of "feels wrong" in shooting.

**Plan:**

When the `release_puck` RPC arrives at the host:

1. Rewind `StateBufferManager` to `host_timestamp - rtt_ms / 2000.0` (the same
   pattern used for pickup lag comp).

2. Retrieve the goalie position and state at the rewound time.

3. Instead of resolving the shot against the current goalie state, use the rewound
   goalie state as the authoritative blocker. Advance the puck kinematically from
   the rewound blade position using the shot direction and power for `rtt_ms / 2`
   worth of time to get the authoritative puck state at "now."

4. Set the puck to that state and broadcast normally.

**Constraint:** Full Jolt re-simulation of N physics ticks per shot is not feasible
without a sandboxed physics sub-step API (not available in Godot 4 / Jolt). Use
kinematic prediction for the fast-forward step — the same math already used in
`PuckController`'s client-side trajectory prediction. This won't be pixel-perfect,
but disagreements will be small enough for soft reconcile to handle invisibly.

**Scope:** Implement for shots on goal first (highest ROI). Dump-ins and passes can
stay with current resolution.

**Dependency:** None technically, but do this after the shot state broadcast work
(Fix 3) is stable, since both touch the shot release path.

---

## Dedicated Server Migration Notes

When the move to a headless server happens, the networking code is already
reasonably well-positioned. A few things to be deliberate about now:

**Naming convention (apply immediately to all new code):**

`NetworkManager.is_host` conflates "I am the physics authority" with "I am one
of the players." On a dedicated server these are separate. Use `is_server` for
physics-authority checks in any new code written from this point, even if it just
aliases `is_host` for now:

```gdscript
# Preferred in new code:
if NetworkManager.is_server:
    # server-only logic

# Avoid in new code (will need find-replace at migration time):
if NetworkManager.is_host:
```

**What changes at migration time:**

- `NetworkManager.is_server = true` on the headless process; false on all clients
  including the lobby host.
- All six players go through the claim path for pickups — host pickup advantage
  disappears.
- `ClockSync` runs on all six clients (currently only non-host players run it).
- `LocalController` is removed from the server process entirely — the server has
  no local player.
- `GameManager` server/client split: everything currently gated on `is_host`
  becomes `is_server` on the server, and absent on clients.
- Anti-abuse hardening (claim rate limiting, connection flood protection) is
  deferred to the dedicated server pass — see the Future Work section of
  `NETWORKING_REFACTOR_PLAN.md`.
