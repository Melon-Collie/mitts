# Networking Design Notes

Design decisions and reasoning behind the multiplayer networking system. This is retrospective documentation — the system is implemented. See `ARCHITECTURE.md` for the technical reference.

---

## Model: Authoritative Host

One player hosts. The host runs all physics authoritatively. Clients predict locally to hide latency and reconcile against server state when corrections arrive.

**Why not peer-to-peer?** Contested interactions (two players going for the same puck) require a single arbiter. P2P either requires lockstep (bad for a fast-paced game) or gets complex fast. A single authority is simpler and more correct.

**Why not a dedicated server?** Not yet warranted. The architecture is written to make this transition easy — `NetworkManager.is_host` will become `multiplayer.is_server()`, and the host's local player concept goes away. Nothing structural prevents it.

---

## Rates

- **Input (client → host): 60 Hz, unreliable.** Matches physics rate. Unreliable is fine — if a packet drops, the host just uses the last known input for that frame. No accumulation problem.
- **World state (host → clients): 20 Hz, unreliable.** Clients interpolate between snapshots, so occasional drops cause a brief stutter rather than a hard error. Higher rates reduce interpolation artifacts but increase bandwidth.
- **Events: reliable.** Carrier transitions, spawns, slot assignments. These must arrive exactly once in order. Unreliable world state is insufficient for events because a dropped packet means the event never fires — the diff approach (detecting changes in world state) is fragile under packet loss.

---

## Skater Networking

### Why Client-Side Prediction?

Without prediction, every input the local player makes has a round-trip delay before they see the result. At any real network latency this feels unresponsive. Prediction runs the physics locally so the player sees their input applied instantly, then reconciles silently when the server confirms.

### Reconciliation: Reset + Replay

When the server state arrives:

1. Discard input history older than `last_processed_sequence` (server has already processed these)
2. Check if the error (position + velocity delta) exceeds a threshold
3. If yes: reset to server position, replay all unconfirmed inputs forward

The threshold check (step 2) is important — without it, you reset and replay 20 times per second even when the client and server agree perfectly, which causes micro-jitter and wastes CPU at 240 Hz physics.

### Why Not Predict Remote Players?

Remote players' inputs aren't available locally, so there's nothing to predict from. Interpolation between server snapshots is the correct approach — it trades a fixed delay (100ms) for smooth, artifact-free movement.

---

## Puck Networking

### Why the Puck Is Different

The puck is a `RigidBody3D` running physics on the server only (frozen on clients). It can't be predicted the same way as a skater because there are no "puck inputs" to replay — its behavior is entirely physics-driven on the server. The three client-side modes reflect this:

**1. Local carrier — pin to blade**
When the local player has the puck, its position is deterministically the blade tip. We know this with certainty, so we apply it directly every frame. No interpolation, no lag, no round-trip.

**2. Trajectory prediction — integrate after release**
The local player initiates the release, so we know the direction and power at the moment of release. We integrate position forward using `GameRules.ICE_FRICTION` while waiting for the server's physics results to arrive. When server state arrives, we reconcile: if the error is within threshold (puck traveled where we expected), we smoothly hand off to interpolation; if not (shot was blocked, deflected, etc.), we snap to server state.

**3. Interpolation — everything else**
When the puck is free or another player is carrying it, we buffer server snapshots and interpolate with a 100ms delay. Same pattern as remote skaters.

### `_carrier_peer_id` Is Never Updated From World State

This is a subtle but important decision. World state is unreliable — if the packet containing a carrier change is dropped, the client never sees the transition. Worse, if local release prediction sets `_carrier_peer_id = -1` but the next world state packet still says `carrier_peer_id = local_peer_id` (because the server hasn't processed the release yet), the world state would overwrite our predicted state and put us back in carrier mode.

The fix: `_carrier_peer_id` on clients is owned exclusively by `notify_local_pickup()` and `notify_local_release()`. World state carries `carrier_peer_id` for reference (it's packed in for potential future use) but never writes to the local carrier tracker. Carrier transitions come through reliable channels only.

### Why Not Predict Pickup?

Pickup is detected server-side via physics collision — the client can't know when it happens before the server tells it. More importantly, two players can contest the same puck simultaneously, and the server must arbitrate who wins. If the client predicted pickup and then got corrected (the other player won the battle), the rollback would feel worse than the single round-trip delay for the reliable notification. Pickup prediction is intentionally out of scope.

### Carrier Transitions: Reliable RPCs

The previous implementation embedded carrier change detection in the unreliable world state diff (`_last_carrier_peer_id` tracking in `GameManager`). This was fragile:
- A dropped packet meant the transition never fired
- Only the local player received carrier events — remote players' `has_puck` was never updated on clients
- Release felt laggy — the local player had to wait for a server round-trip before their state machine transitioned out of `SKATING_WITH_PUCK`

The fix:
- **Pickup:** Server detects via `puck_picked_up` signal → reliable RPC to the specific client who picked up the puck → `on_puck_picked_up_network()` on their `LocalController`
- **Release:** Client predicts immediately (state machine + trajectory prediction) → reliable RPC to server to execute physics

Remote players don't need carrier events on clients because their state machines don't run client-side — they only interpolate.

---

## World State Format

```
[peer_id, skater_state_array, peer_id, skater_state_array, ..., puck_x, puck_vel, puck_carrier_peer_id]
```

Puck state is always the last 3 elements. Skater states are variable-length pairs before that. The parser uses `state.size() - 3` as the boundary.

**Tradeoff:** This format is fragile if you add more top-level state (goalies, score, etc.) — the boundary calculation needs updating each time. A length-prefixed or tagged format would be more extensible. Acceptable for now given the small number of state types.

---

## Planned: Goalie Networking

Same pattern as puck. Server runs goalie AI, serializes state into world state, clients interpolate using `BufferedGoalieState`. The compact serialization plan (state enum + position + facing, clients reconstruct body part positions from config locally) avoids sending 6 body part transforms per tick.

## Planned: Headless Server

The current `NetworkManager.is_host` check maps directly to `multiplayer.is_server()` in a dedicated server model. When the time comes: remove the host's `LocalController`, replace `is_host` checks with `multiplayer.is_server()`, and the authority model stays identical. No structural changes to the prediction/reconciliation/interpolation system.
