# Netcode Fixes

Targeted correctness fixes for known bugs and architectural gaps in the current
networking implementation. All of these are things that are currently wrong, not
enhancements. Each fix is self-contained enough to be reviewed and tested
individually.

## Collaboration Style

Same as the previous networking plan: present the specific change and rationale
before editing any file. Wait for explicit approval before proceeding. Flag any
deviation from this plan immediately.

---

## Fix 1 — Segment-Segment Blade Detection

**Files:** `Scripts/domain/rules/puck_interaction_rules.gd`, `Scripts/actors/skater.gd`,
`Scripts/controllers/puck_controller.gd`, `Scripts/game/game_manager.gd`

**Problem:** `PuckInteractionRules.check_pickup` and `check_poke` sweep the puck
(`puck_prev → puck_curr`) but treat the blade as a static point sampled at the end
of the tick. When the puck is nearly stationary — the most common pickup scenario in
puck battles — the puck segment degenerates to a point and the test becomes a simple
distance check against the blade's final position only. A fast stick swing that passes
through the pickup zone entirely within a single physics tick is missed.

The correct test is segment-vs-segment (capsule vs capsule): sweep both the puck and
the blade across the tick.

**Fix:**

1. Add `_prev_blade_contact: Vector3` to `Skater`. Store it at the very top of
   `_physics_process` before any movement runs, so it holds the blade's world
   position from the start of the tick:
   ```gdscript
   func _physics_process(_delta: float) -> void:
       _prev_blade_contact = get_blade_contact_global()
       # ... rest of physics
   
   func get_prev_blade_contact_global() -> Vector3:
       return _prev_blade_contact
   ```

2. Replace `_point_segment_dist_sq` in `PuckInteractionRules` with a
   segment-segment minimum distance function. Update both `check_pickup` and
   `check_poke` signatures to accept `blade_prev` and `blade_curr`:
   ```gdscript
   static func check_pickup(
           puck_prev: Vector3, puck_curr: Vector3,
           blade_prev: Vector3, blade_curr: Vector3,
           radius: float) -> bool:
       return _segment_segment_dist_sq(puck_prev, puck_curr, blade_prev, blade_curr) <= radius * radius
   ```
   The segment-segment distance function is the standard analytical solution
   (Eberly, "Distance Between Two Line Segments").

3. Update `PuckController._check_interactions` to pass both blade positions:
   ```gdscript
   var blade_curr: Vector3 = skater.get_blade_contact_global()
   var blade_prev: Vector3 = skater.get_prev_blade_contact_global()
   PuckInteractionRules.check_pickup(puck_prev, puck_curr, blade_prev, blade_curr, PICKUP_RADIUS)
   ```

4. Update the lag comp path in `game_manager.gd` (`_on_pickup_claim_received`).
   The state buffer already queries two consecutive snapshots for `puck_prev`
   and `puck_pos`. Do the same for blade: query `snapshot` and `prev_snap` for
   the skater's `blade_position` field. This also fixes Fix 2 below (see
   dependency note).

**Review gate:** Unit tests in `tests/unit/rules/` covering: stationary puck +
fast blade swing, both moving toward each other, near-miss, degenerate
(zero-length) segments.

---

## Fix 2 — Authoritative Blade Position in Lag Comp

**File:** `Scripts/game/game_manager.gd`

**Problem:** `_on_pickup_claim_received` validates the claim using `blade_pos`
sent by the client in the RPC payload. This is the client's locally predicted
blade position, which may have diverged from what the host computed for that
skater at `rewind_time`. It also means a modified client could send an arbitrary
blade position and have it validated.

The state buffer already stores `SkaterNetworkState.blade_position` per peer at
every captured tick. That authoritative value should be used instead.

**Fix:**

Replace the client-provided `blade_pos` and `blade_vel` with values read from
the state buffer at `rewind_time` and `rewind_time - 1/240`:

```gdscript
# game_manager.gd _on_pickup_claim_received — after querying snapshot / prev_snap:
var skater_snap: SkaterNetworkState = snapshot.get_skater_state(peer_id)
var skater_prev_snap: SkaterNetworkState = prev_snap.get_skater_state(peer_id)
if skater_snap == null or skater_prev_snap == null:
    return
var blade_curr: Vector3 = skater_snap.blade_position
var blade_prev: Vector3 = skater_prev_snap.blade_position
if not PuckInteractionRules.check_pickup(puck_prev, puck_pos, blade_prev, blade_curr, PuckController.PICKUP_RADIUS):
    return
```

This requires `WorldSnapshot` to expose `get_skater_state(peer_id: int) ->
SkaterNetworkState`. Add that method to `StateBufferManager` if it doesn't
already index by peer ID.

The `blade_vel` parameter can be removed from the `receive_pickup_claim` RPC
signature and from `LocalController`'s send site — it is no longer used.

**Dependency:** Requires Fix 1 for the updated `check_pickup` signature.

---

## Fix 3 — Shot State in World State

**Files:** `Scripts/networking/skater_network_state.gd`,
`Scripts/game/world_state_codec.gd`, `Scripts/controllers/local_controller.gd`,
`Scripts/controllers/skater_controller.gd`

**Problem:** The shot state machine (`_state`, `_charge`) is never broadcast in
world state — it is reconstructed entirely by replaying inputs after a reconcile.
The recent commit (a69391f) introduced save/restore of `_charge_distance`,
`_prev_blade_dir`, and `_prev_mouse_screen_pos` around the replay loop to prevent
charge corruption during reconcile. This is a patch: it prevents the reconcile
from introducing new charge corruption, but it does not correct charge state that
was already wrong before the reconcile (e.g. from a dropped `shoot_pressed` input).
The server's authoritative charge value never wins.

Additionally, restoring `_prev_mouse_screen_pos` to its pre-replay value is
incorrect: the replay processed real inputs that moved the mouse, and the post-
replay baseline should reflect where the mouse actually was at the end of the
replay sequence, not before it started.

**Fix:**

**3a. Add shot state to `SkaterNetworkState`:**
```gdscript
var shot_state: int = 0     # SkaterController.State enum value
var shot_charge: float = 0.0
```

**3b. Encode and decode in `WorldStateCodec`:**
Append `shot_state` and `shot_charge` to the skater section of the wire array.
This is a wire-format change — old and new builds cannot interoperate.

**3c. Update `LocalController.reconcile`:**

Remove the save/restore of `_charge_distance`, `_prev_blade_dir`, and
`_prev_mouse_screen_pos`. The `is_replaying` flag and the restore of
`_state`, `_follow_through_timer`, `_follow_through_is_slapper`, and
`_one_timer_window_timer` are correct and stay.

Before the replay loop, seed `_prev_mouse_screen_pos` from the first input in
the replay window so the first replayed frame's direction-variance delta is zero
rather than a large garbage value:
```gdscript
if not _input_history.is_empty():
    _prev_mouse_screen_pos = _input_history[0].mouse_screen_pos
```

After the replay loop, before applying the server's authoritative values, set
`_prev_mouse_screen_pos` to the last replayed input's position so the next real
frame has the correct baseline:
```gdscript
if not _input_history.is_empty():
    _prev_mouse_screen_pos = _input_history.back().mouse_screen_pos
```

Then apply server authority on shot state. If server and client disagree, server
wins:
```gdscript
if server_state.shot_state != pre_state:
    _state = server_state.shot_state as State
    _charge_distance = server_state.shot_charge
    # charge fields derived from _charge_distance are reset naturally next frame
```

**3d. Populate on encode (host side):**
`WorldStateCodec` reads `shot_state` and `shot_charge` from `SkaterController`
via a new getter, or directly from the controller reference in the player record.

**Note on kept fixes from a69391f:**
- `is_replaying` guard in `SkaterController._do_release` — correct, keep.
- `_pending_local_release` flag in `PuckController` — correct, separate fix, keep.

**Review gate:** Under simulated lag, fire a wrister during a reconcile. Charge
should survive the reconcile intact. The server's `shot_state = SKATING` should
override a client's false `WRISTER_AIM` within one broadcast cycle.

---

## Fix 4 — Contest Window Timer Moved to Physics Thread

**File:** `Scripts/game/game_manager.gd`

**Problem:** The 50ms contest window check for pickup claims runs in `_process`
(display thread, ~60 Hz). The effective window is 50ms + up to one display frame:
50–66ms at 60fps, 50–83ms at 30fps, 50–57ms at 144fps. Meanwhile
`_check_interactions` runs at 240 Hz in `_physics_process`. The window is
nondeterministic across frame rates.

**Fix:**

Move the pending claim age check into `_physics_process`. Add a
`_pending_claim_timer: float` accumulator:

```gdscript
# _physics_process:
if not _pending_pickup_claim.is_empty():
    _pending_claim_timer += delta
    if _pending_claim_timer >= _CONTEST_WINDOW_S:
        puck_controller.apply_lag_comp_pickup(_pending_pickup_claim.skater)
        _pending_pickup_claim = {}
        _pending_claim_timer = 0.0
```

Reset `_pending_claim_timer` wherever `_pending_pickup_claim` is cleared
(contested pickup path and `_on_server_puck_picked_up_by`).

---

## Fix 5 — RTT Decoupling for Pickup Rewind Depth

**Files:** `Scripts/networking/clock_sync.gd`, `Scripts/networking/network_manager.gd`,
`Scripts/game/game_manager.gd`

**Problem:** `ClockSync` computes a single `rtt_ms` value by averaging 6 of the last
8 samples, dropping the 2 worst. This averaged value is used both for the clock
offset (where stability is good) and for the pickup rewind depth in
`_on_pickup_claim_received` (where accuracy matters more than smoothness). On
variable connections the average skews low, causing the rewind to be shallower than
the actual current trip time and checking the wrong historical puck position.

**Fix:**

Add `latest_rtt_ms: float` to `ClockSync`, updated on every `record_pong` with the
raw unaveraged sample:

```gdscript
func record_pong(client_send_time: float, host_time: float, recv_time: float) -> void:
    var rtt := recv_time - client_send_time
    latest_rtt_ms = rtt * 1000.0  # raw, not filtered
    # ... existing averaging logic unchanged
```

Expose via `NetworkManager.get_latest_rtt_ms() -> float`.

In `game_manager.gd`, use `latest_rtt_ms` for the rewind, capped to prevent
rewinding too deep on outlier spikes:

```gdscript
var rewind_rtt: float = clampf(NetworkManager.get_latest_rtt_ms(), 10.0, 200.0)
var rewind_time: float = host_timestamp - rewind_rtt / 2000.0
```

The existing `rtt_ms` (averaged) continues to be used for clock offset estimation
and the debug overlay — no change there.

---

## Fix 6 — Blade Extrapolation During Remote Skater Extrapolation

**File:** `Scripts/controllers/remote_controller.gd`

**Problem:** When the interpolation buffer runs dry and `RemoteController`
extrapolates, the skater body moves forward (`position + velocity * dt`) but
`blade_position` and `top_hand_position` are frozen at the last known state
(lines 89–90). At max skating speed (~8 m/s) over the 50ms cap, the body moves
~40cm while the stick hangs in space.

**Fix:**

Estimate blade and top-hand velocity from the last two buffered snapshots and
apply the same extrapolation:

```gdscript
if bracket.is_extrapolating:
    var dt: float = minf(bracket.extrapolation_dt, extrapolation_max_ms / 1000.0)
    var newest: SkaterNetworkState = bracket.to_state
    interpolated.position = newest.position + newest.velocity * dt
    interpolated.velocity = newest.velocity
    var bracket_dt: float = bracket.to_state.timestamp - bracket.from_state.timestamp
    if bracket_dt > 1e-4:
        var blade_vel: Vector3 = (bracket.to_state.blade_position - bracket.from_state.blade_position) / bracket_dt
        var hand_vel: Vector3 = (bracket.to_state.top_hand_position - bracket.from_state.top_hand_position) / bracket_dt
        interpolated.blade_position = newest.blade_position + blade_vel * dt
        interpolated.top_hand_position = newest.top_hand_position + hand_vel * dt
    else:
        interpolated.blade_position = newest.blade_position
        interpolated.top_hand_position = newest.top_hand_position
    # facing and upper_body_rotation_y frozen — acceptable over 50ms
    interpolated.upper_body_rotation_y = newest.upper_body_rotation_y
    interpolated.facing = newest.facing
    interpolated.is_ghost = newest.is_ghost
```

`bracket.from_state` is always populated during extrapolation (it is the
second-to-last buffered snapshot).

---

## Fix 7 — Input Queue Depth Cap

**File:** `Scripts/controllers/remote_controller.gd`

**Problem:** `_input_queue` has no maximum size. If `estimated_host_time()` is
calibrated too high (client clock running fast), inputs arrive with timestamps
ahead of the host's current time. The host pops one per tick but new batches
keep arriving with future-timestamped inputs. Over a long session a 1ms/s drift
produces ~1800 queued inputs after 30 minutes — 7.5 seconds of artificial lag.

**Fix:**

After deduplication and sorting in `receive_input_batch`, trim the front of the
queue if it has grown past a safety limit:

```gdscript
# After sort:
const MAX_QUEUE_DEPTH: int = 120  # 0.5s at 240 Hz
while _input_queue.size() > MAX_QUEUE_DEPTH:
    _input_queue.pop_front()
```

120 inputs is 500ms at 240 Hz — well beyond any legitimate clock offset while
still bounding the worst case.

---

## Known Limitation — Host Pickup Advantage

The host player's pickup is detected by `PuckController._check_interactions` at
240 Hz directly — no claim, no lag comp, no contest window. Client pickups go
through the claim path with RTT/2 rewind. In a simultaneous puck battle the host
player wins because their detection fires earlier in the physics pipeline and
`apply_lag_comp_pickup` checks `puck.carrier != null` before granting any claim.

This is structural and has no clean fix within the current peer-hosted model.
It disappears entirely when the dedicated server is running, since all players
will go through the claim path symmetrically. Document as a known limitation
until then.
