# Parallel render pass — plan

Run every skater's (and keeper's) per-frame cosmetic pass on worker threads at
once, instead of one after another on the main thread. Status: **spiked; blocked
on an engine race** (*What the spike found*, below). The spike's code is not in
the tree: it is commit `f5c5c74` on the PR #871 branch (reverted there), to cherry-
pick if the engine race is fixed. The names below (`Skater.parallel_render`,
`SkaterTickProxy`) are that commit's.

## Why this lever

A full lobby costs ~0.8 ms of frame per skater (280 fps solo → 90 fps 5v5,
export build, hosting), and the cost is linear in the skater count
(`docs/performance-findings.md`). Graphics settings move the GPU, and this frame
is bound by the main thread, so they barely help.

Of a skater's main-thread work, the render pass is about half.
`benchmarks/test_skater_frame_benchmark.gd`, native kernels built, editor
binary, a 4-core container (rank the rows; don't read them as your frame):

| state | tick (2 ticks) | render pass | of which gait | seat | stick mesh | bottom-hand IK | arms |
|---|---|---|---|---|---|---|---|
| stride | 233 µs | 270 µs | 98 | 7 | 31 | 28 | 37 |
| crossovers | 238 | 289 | 113 | 16 | 33 | 28 | 37 |
| glide | 180 | 212 | 63 | 9 | 26 | 23 | 45 |
| stop | 207 | 254 | 97 | 13 | 29 | 26 | 38 |

The render pass is the one half that does not need to run in order.
- **The tick is coupled.** A release moves the puck synchronously, mid-dispatch,
  and later skaters read it. Body checks resolve pairwise and in sequence, and
  clients predict that order. Parallelising the tick risks reconcile
  divergence for ~0.5 ms; it is not proposed.
- **The render pass is not coupled.** Each skater's pass reads only its own
  state, plus one cross-skater read: `GaitPressLayer` reads other skaters'
  root positions, which the tick wrote and nothing moves during `_process`. It
  writes only its own nodes. That is embarrassingly parallel: ten skaters and
  two keepers spread over 8+ cores.

Expected gain: most of the render pass leaves the main thread, along with the
skeleton and skin updates the engine runs on those nodes (part of the frame's
unattributed engine time). An honest range is **1–2 ms of a 5v5 frame**: 90 fps
to roughly 100–110 on the reference machine, and a slope that flattens as
players are added. This plan does not touch the tick, the GPU, or the engine's
CPU render (see *Related levers*).

## The mechanism: process thread groups (measured on 4.6.2)

Godot's `Node.process_thread_group = SUB_THREAD` runs a subtree's `_process` on
a `WorkerThreadPool` thread, in parallel with other sub-thread groups. A
throwaway scene showed how it behaves under 4.6.2:

- **Reads cross freely.** From a worker, reading another group's node
  (`transform`, `global_position`, script vars) works without error.
- **Writes outside the group are refused**, with an error naming the node:
  `set_position`, `emit_signal` on a main-thread node. A worker writes its own
  subtree only.
- **The main thread may write into a sub-thread group's nodes between passes.**
  So the tick (controllers at priority −1, the skater body at 0) can keep
  writing markers and frames from main.
- **Group order outranks priority.** All order-0 main-thread nodes process
  first, whatever their priority (a priority-5 node ran before the workers).
  The order-1 sub-thread groups run next, then an order-2 main-thread group.
  That last group is where results get collected.
- **A sub-thread group's `_physics_process` runs on a worker too.** The group
  is per node, not per callback. This is the design constraint below.

That rules out the hand-written alternative (a "pose buffer": gather on main,
solve on `WorkerThreadPool`, write back on main). It would mean splitting all
four rigs plus the arm, hem and leg kernels, which today read
`get_bone_global_pose` mid-solve and write bones themselves. Under a thread
group they keep doing exactly that. Only the accesses that leave the skater's
own subtree change.

## Design

1. **The skater subtree is its own sub-thread group**, set in code in
   `Skater._init`, before it enters the tree (no `.tscn` edit), with
   `process_thread_group_order = 1`.
   `GameCamera` and the rest of the main-thread scene still process first.
2. **The skater's tick stays on main, in its current slot.**
   `Skater._physics_process` integrates and resolves collisions against other
   skaters, so it cannot run on a worker. The skater stops physics-processing
   itself, and a main-thread node beside it (`SkaterTickProxy`) calls the same
   step in the same slot. The step must keep its place: after `GameManager`'s dispatch, before
   the puck (+1) and the capture hook (+2), and in today's order relative to
   the keeper controllers, which read live skater positions. A test pins that
   order before and after the change. Doing this first is what makes the rest
   safe.
3. **Camera culling moves to main.** `SkaterCameraCull` keeps its frustum in
   static vars and rewrites them on a camera change; `distance()` depends on
   what the previous `sees()` left there. One main-thread refresh per frame,
   before the workers, makes the statics read-only during the pass. It is the
   only mutable static on the render path: the rest are build-time mesh caches.
   The native kernels are per-instance and hold no statics.
4. **Signals out of the pass are deferred.** `skate_pushed` / `skate_touched`
   (audio) are emitted on the skater, its own node, but their handler calls
   into `SoundManager`. Connect them deferred so the handler runs on main.
   Audit every other connection to a skater signal fired from the render path
   the same way.
5. **Readers of this frame's pose run after the pass, or read last frame's.**
   Three main-thread readers consume what the pass wrote:
   - `IceScratchMap` reads the foot bones through `blade_mark_position`;
   - `SkaterSoundController` reads the gait's `skate_sound()` channels;
   - `SkaterVFX` reads the foot bones, and is a child of the skater, so it joins
     the group.

   Each reader either moves into an order-2 main-thread group or takes last
   frame's value, decided case by case. A skate mark one frame old is
   invisible. The nameplate and the rest of the world HUD are under the skater,
   so they ride the pass itself.
6. **The keeper follows the same pattern.** `Keeper._process`: 22 bones from a
   pure `KeeperGear` solve, the knee-break mesh, 48 cloth flaps. His tick is
   `KeeperController`, a separate main-thread node, so step 2 does not apply.

What stays exactly as it is: every gameplay value. The render pass's outputs
that gameplay reads (the held poses' frame drop, the faceoff address, the hip
yaw channels) are computed by the same code from the same inputs, in the same
frame, before the next tick.

## What the spike found

Built for skaters only (design steps 1–4), run in a headless 10-skater bot match
and in a GUT test that drives three parallel skaters through real frames.

What worked, and is in the tree:

- **The tick proxy.** `SkaterTickProxy` sits right after its skater and runs
  `Skater.physics_tick` there on the main thread, so the tick keeps its slot.
  A parallel skater's own `_physics_process` is a no-op;
  `set_physics_process(false)` (the replay viewer's) still stops the tick,
  because the proxy checks it.
- **The group has to be set before the skater enters the tree.** On a node
  already in the tree, 4.6.2's `_add_tree_to_process_thread_group` updates
  the owner of that node alone. Its children are re-added under their old
  owner, and the guard then refused the render pass every write below
  `MeshRoot`. So `Skater._init` sets it.
- **Camera culling** readies the shared frustum on the main thread
  (`SkaterCameraCull.prepare`, from the proxy's `_process`). Workers only read it.
- **Audio.** `AudioStreamPlayer3D` queries the physics space in its internal
  physics step, which is main-thread only; that crashed the first run. In
  parallel mode the skater's `SkaterSoundController` is its own main-thread
  group. The two skate sounds are connected deferred, and a deferred signal
  emitted on a worker is handled on the main thread the same frame.
- **`Node3D.visible` is main-thread only.** The world HUD writes it through
  `SkaterHUDCoordinator._show`, which defers the write off the main thread.

Measured, three alternating runs a mode, 10 skaters, 4 cores (one busy with the
AI worker): the process step fell from 5.6 to 4.4 ms a frame (−21%), and the main
thread at 90 fps from 13.9 to 13.0 ms.

**The blocker: physics interpolation's bookkeeping is not thread-safe.** In
4.6.2 every Node3D transform write calls `SceneTreeFTI::_node_3d_notify_set_xform`,
which pushes the node onto shared `LocalVector`s (`tick_xform_list`,
`frame_xform_list`) without taking `data.mutex`. Two skaters writing a node
transform on two workers corrupt the heap: `realloc(): invalid next size`, or a
SIGSEGV on the main thread a frame later. The test crashed in 4 of 10 runs with
interpolation on, and in 0 of 10 with `SceneTree.physics_interpolation` off.
The game needs interpolation (root `CLAUDE.md`, the render clock), so in
parallel mode **no Node3D transform may be written on a worker**. That covers:

- the stick, knob and blade meshes;
- the bottom-hand marker;
- the held poses' frame drop;
- the knockdown's `MeshRoot`;
- a remote's lower-body lag;
- the world HUD's labels;
- the VFX emitters.

It also covers one write the engine makes for us. The skeleton's update runs as
`notify_deferred_thread_group`, on the skater's worker, and its
`skeleton_updated` signal moves the head's `BoneAttachment3D` (the face gear and
hair).

### The ways forward

1. **Split the pass at the node writes.** Workers keep the gait, spine, legs,
   head and hem, which write only bones. An order-2 main-thread pass after them
   (`process_thread_group_order = 2`) does the stick, the arms (which read the
   stick), the hold, the HUD and the VFX. The worker side's few node writes are
   recorded and applied there. The head attachment becomes a placement on main.
   That puts roughly 60% of the pass in parallel. Its gate is a stress run: the
   threaded test and a full bot match, many times over, with no crash.
2. **A pure-data pose buffer.** Workers compute and write nothing; main writes
   every bone and node. The safest version, and the largest refactor: the rigs
   and the arm, hem and leg kernels all write bones themselves today.
3. **Do not thread; port to C++ instead** (the blade IK's orchestration, the
   keeper's `_seat`). No exposure to the engine's threading at all.

The race is an engine bug worth reporting upstream: thread groups are a
documented feature, and physics interpolation is on by default in new 3D
projects.

## Steps

1. ~~Spike~~ — done, above.
2. Choose a way forward.
3. **A render-pass probe** beside `HostCostProbe`: wall time of the sub-thread
   phase and the sum of per-skater passes. Their ratio is the parallelism
   actually achieved, in the F3 panel and the digest.
4. The keeper.

## Related levers, decided separately

- **Engine render thread** (`rendering/driver/threads/thread_model = Separate`).
  The project runs the default, Safe, so the engine's CPU render work (culling,
  ~760 draw calls, 8 shadow passes) is sequential on the main thread. Separate
  moves it to its own thread. Godot's docs still warn it has known bugs. A/B it
  on an export with an `override.cfg` beside the executable, before writing any
  code.
- **Gait LOD — not taken.** The gait runs every visible frame, even when the
  animation LOD skips the mesh. Thinning it would save an estimated
  ~0.1–0.15 ms of a 5v5 frame on the reference machine. That figure scales the
  ~95 µs a skater in the table above to a faster CPU and a release build, over
  the third or so of frames the LOD skips. The cost is that a held pose starting on a thinned frame would take a
  crouch shaped by a different step history. That makes the gameplay frame
  depend, by millimetres, on the host's camera. The parallel pass takes this
  work off the main thread without that trade.
- **Dedicated server.** Still the largest single lever (`performance-findings.md`).
