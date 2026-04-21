# Netcode Audit — April 2026

New items identified during a broad networking audit. The bulk of known
improvements and fixes already live in `NETCODE_FIXES.md` and
`NETCODE_IMPROVEMENTS.md`. Everything here is additive to those.

---

## 1 — World State Rate: 20 Hz → 40 Hz

**File:** `Scripts/game/constants.gd`

**Why:** At 20 Hz (50ms interval) a 30 m/s slap shot travels 1.5m between
authoritative snapshots. Client-side trajectory prediction covers the gap but
the reconciliation window is large and corrections are aggressive. At 40 Hz
(25ms interval) the gap halves to 0.75m, soft-reconcile corrections shrink
proportionally, and interpolation has twice as many brackets to work with.

**Bandwidth cost:** ~203 bytes × 40 Hz × 5 clients ≈ 32 KB/s upstream from
host. Trivial for any residential connection.

**Physics divisibility:** 240 Hz / 40 Hz = 6 ticks per broadcast. Clean
integer — no fractional-tick accumulation.

**Change:**
```gdscript
const STATE_RATE: int = 40
```

`NetworkManager` already drives broadcast on a `1.0 / STATE_RATE` timer.
No structural changes required.

**Note:** The `_jitter_samples` window in `NetworkManager` is currently 40
samples, which at 40 Hz represents exactly 1 second of history. That remains
correct — no change needed there.

---

## 2 — Interpolation Delay: 100ms → 75ms

**File:** `Scripts/game/constants.gd`

**Why:** The 100ms delay was sized to guarantee two snapshot brackets at 20 Hz
(50ms interval + jitter margin). At 40 Hz the interval is 25ms, so 75ms gives
three brackets with the same jitter margin. Reducing the delay by 25ms directly
reduces remote actor visual lag by 25ms, which is perceptible in fast puck
battles.

**Change:**
```gdscript
const NETWORK_INTERPOLATION_DELAY: float = 0.075
```

All three interpolating controllers (`RemoteController`, `PuckController`,
`GoalieController`) read this constant as their baseline `@export` default —
no per-file changes required unless per-actor tuning is desired.

**Dependency:** Do this alongside or after item 1. On 20 Hz the 75ms floor
leaves only a 25ms margin above the snapshot interval — too tight if jitter
spikes.

---

## 3 — Reconcile Blend Instead of Snap

**File:** `Scripts/controllers/local_controller.gd`

**Why:** The current reconcile flow snaps position instantly to the replay
result. For corrections at or above the 5cm threshold the local player sees
their skater skip. Velocity is always correct post-reconcile (snap velocity
immediately — errors compound). Position can be blended over a few frames
without meaningful delay to convergence.

**Plan:**

Add three fields to `LocalController`:
```gdscript
var _reconcile_blend_from: Vector3 = Vector3.ZERO
var _reconcile_blend_target: Vector3 = Vector3.ZERO
var _reconcile_blend_t: float = 1.0  # 1.0 = blend complete / inactive
```

At the end of a triggered reconcile, instead of leaving the skater at the
replay position:
```gdscript
_reconcile_blend_from = skater.global_position  # pre-snap visual position
_reconcile_blend_target = replay_result_position
_reconcile_blend_t = 0.0
skater.global_position = replay_result_position  # physics body snaps immediately
```

In `_physics_process`, before any movement runs:
```gdscript
const BLEND_FRAMES: int = 3
if _reconcile_blend_t < 1.0:
    _reconcile_blend_t = minf(_reconcile_blend_t + 1.0 / BLEND_FRAMES, 1.0)
    skater.visual_offset = _reconcile_blend_from.lerp(_reconcile_blend_target, _reconcile_blend_t) - _reconcile_blend_target
```

This requires `Skater` to expose a `visual_offset: Vector3` that is applied to
the mesh root each frame but not to the physics body — the body is already at
the correct position. Clear `visual_offset` when `_reconcile_blend_t` reaches
1.0.

**Scope note:** Only worthwhile if `Skater` supports a visual offset without
rearchitecting the mesh hierarchy. If the mesh is a direct child of the
`CharacterBody3D` with no intermediate node, add a `MeshRoot` Node3D between
them and shift the visual offset there.

---

## 4 — Bounds Checking in WorldStateCodec.decode_world_state

**File:** `Scripts/game/world_state_codec.gd`

**Why:** A truncated or malformed UDP packet causes an out-of-bounds array
access and crashes the host. Currently all peers are trusted (P2P), but once
the ENet port is exposed on a dedicated server any machine can send garbage to
it. This is a one-day fix that prevents a whole class of availability attacks.

**Plan:**

At the start of each decode section, check the remaining byte count before
reading:
```gdscript
if bytes.size() < offset + SKATER_STRIDE:
    push_warning("WorldStateCodec: truncated skater section")
    return
```

Define `SKATER_STRIDE`, `PUCK_STRIDE`, `GOALIE_STRIDE`, `GAME_STATE_STRIDE`
as named constants at the top of the file so the check values stay in sync
with the actual encode layout.

Return early (emit no signals) on any size mismatch rather than crashing. The
next broadcast will arrive within 25ms and carry a complete packet.

---

## 5 — NetworkSim One-Sided Jitter

**File:** `Scripts/networking/network_sim.gd`

**Why:** `randf_range(-jitter_ms, jitter_ms)` allows simulated packets to
arrive *earlier* than their scheduled time, which is physically impossible on
real networks. This makes the simulator optimistic — tested conditions feel
better than real conditions at the same labeled jitter level.

**Change:**
```gdscript
# Before:
var jitter_offset_ms: float = randf_range(-jitter_ms, jitter_ms)

# After:
var jitter_offset_ms: float = randf_range(0.0, jitter_ms * 2.0)
```

Same mean delay (delay_ms + jitter_ms), same variance, one-sided distribution.
Tested presets will feel slightly worse than before, which means they more
accurately represent real network conditions.

---

## 6 — Hermite Spline Interpolation for Remote Skaters

**File:** `Scripts/controllers/remote_controller.gd`

**Why:** The current bracket lerp for position is C0-continuous — position
matches at bracket endpoints but the rate of change (velocity) is
discontinuous. At 40 Hz this is less visible than at 20 Hz, but at bracket
boundaries remote skaters still have a subtle stutter in their acceleration.
Hermite interpolation uses the velocity field already in each `SkaterNetworkState`
snapshot to define tangents at both endpoints, giving C1-continuous motion
(smooth velocity) at zero additional bandwidth cost.

**Change:** Replace the lerp in the interpolation path with a cubic Hermite:

```gdscript
static func _hermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, t: float, dt: float) -> Vector3:
    var t2: float = t * t
    var t3: float = t2 * t
    return (2*t3 - 3*t2 + 1) * p0 \
         + (t3 - 2*t2 + t) * dt * v0 \
         + (-2*t3 + 3*t2) * p1 \
         + (t3 - t2) * dt * v1
```

Where `dt` is the time span between `from_state` and `to_state` and `t` is
the normalized position within that span. Apply to position only; facing and
upper_body_rotation_y can stay slerped/lerped — they are already smooth enough.

**Priority:** Do this after item 1 (40 Hz). At 40 Hz the bracket span is 25ms
and velocity tangents are reliable. At 20 Hz the 50ms span amplifies velocity
quantization error and Hermite can overshoot.
