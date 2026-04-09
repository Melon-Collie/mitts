# Goalie Tuning: Make It Beatable

The goalie is currently too good — unbeatable even without reactive saves implemented. The base positioning and state transitions are mechanically perfect. This plan introduces friction into the goalie's execution to create scoring opportunities.

---

## Changes

### 1. Remove Stick (disable, don't delete)

Hide the stick body part — disable its collision and visibility. Don't remove the code or scene node, just turn it off so we can bring it back later with better behavior.

This immediately opens the five-hole as a scoring option. The five-hole gap between pads (especially during lateral movement) is no longer sealed by a perfect rectangle.

### 2. Reduce Lerp Speeds

The body parts currently transition between state configs too quickly. The goalie drops to butterfly and the pads seal the ice almost instantly.

Reduce the body part lerp rate significantly. The goal: when the goalie drops to butterfly, there should be a visible window where the pads are mid-rotation and haven't sealed the ice yet. Same for RVH transitions — the goalie should visibly be "getting into position" rather than snapping there.

This is an `@export` value so it can be tuned in the inspector. Start by halving whatever the current value is and see how it feels. It might need to go even lower.

### 3. Reduce Movement Speeds

Shuffle speed and T-push speed are both too fast. The goalie tracks laterally so well that cross-crease passes don't create real scoring chances.

Reduce both `shuffle_speed` and `t_push_speed`. The goalie should noticeably lag behind on a quick cross-crease pass — the puck arrives on the other side and the goalie is still sliding over. Again, start by reducing by ~30-40% and tune from there.

Also reduce `depth_speed` slightly so telescoping in and out isn't instant either.

### 4. Add Tracking Lag

This is the big one. Currently the goalie reads the puck position every frame and computes a perfect target position instantly. A real goalie reads the play and reacts — they don't have frame-perfect tracking.

**Implementation:** Instead of reading `puck.global_position` directly each frame, maintain a `_tracked_puck_position` that lerps toward the actual puck position with a delay. All positioning logic (depth calculation, lateral target, facing) reads from `_tracked_puck_position` instead of the real puck position.

```
@export var tracking_speed: float = 6.0  # how fast the goalie "reads" the puck

func _update_tracking(delta: float) -> void:
    var actual_pos: Vector3 = _puck.global_position
    _tracked_puck_position = _tracked_puck_position.lerp(actual_pos, tracking_speed * delta)
```

This single change affects everything:
- **Lateral positioning:** Quick passes mean the tracked position is behind the real puck, so the goalie slides to the wrong spot briefly
- **Depth:** Fast rushes toward the net mean the goalie telescopes out late
- **Facing:** Dekes and lateral moves cause the goalie to face where the puck was, not where it is
- **RVH entry:** The goalie might be slightly late recognizing the puck has gone to a steep angle

The `tracking_speed` export is the master tuning knob for goalie difficulty. Higher = more responsive (harder to beat), lower = more lag (easier to beat). This could eventually tie into character stats or difficulty settings.

**Important:** Shot detection (`_on_puck_released`) should still use the REAL puck position and velocity, not the tracked position. The goalie's reaction to a shot should be based on the actual trajectory, not its delayed read. The tracking lag is for positional play, not shot reactions.

---

## Implementation Order

1. Disable stick (quick win, immediately testable)
2. Reduce movement speeds (simple number changes, test how cross-crease passes feel)
3. Reduce lerp speeds (simple number change, test how butterfly/RVH transitions look)
4. Add tracking lag (new code, biggest impact on feel)

Test after each step. The goalie should go from "unbeatable wall" to "competent but you can find openings." The goal is that when you score, you feel like you did something smart — moved the puck fast enough to exploit the lag, found the five-hole during a shuffle, roofed it during a slow butterfly drop.

---

## Tuning Guidance

All of these are `@export` values. During playtesting:

- If the goalie still feels too good after all changes: reduce `tracking_speed` first (it affects everything)
- If the goalie looks drunk and out of position: increase `tracking_speed`
- If butterfly is still sealing too fast: reduce body part lerp rate
- If cross-crease is still not working: reduce `t_push_speed`
- If the five-hole is too easy to score on without the stick: we went too far, consider bringing the stick back with reduced coverage

The tracking lag and movement speeds interact — a goalie with slow tracking but fast movement will lurch around (late to read, then rockets to position). A goalie with fast tracking but slow movement will read the play correctly but not get there in time. The sweet spot is both being slightly limited so the goalie looks smart but physically can't cover everything.
