# mitts_native — GDExtension hot-path kernels

C++ ports of per-tick math kernels, registered as `Native*` classes
(`NativeTopHandIK`, `NativeSkaterMovement`,
`NativePuckStep`, `NativeBladeDangle`, `NativeArmRig`, `NativeSkaterGait`,
`NativeLegChain`, `NativeCarryRollout`, `NativeShotOdds`, `NativeHemFlaps`,
`NativeBladePass`). The
GDScript originals (in `Scripts/domain/rules/`, `Scripts/domain/ai/`,
`Scripts/controllers/` and `Scripts/actors/`) remain the behavioral
reference; each ported kernel is pinned to its reference by a seeded fuzz test
(`tests/unit/rules/test_native_ik_parity.gd` and its siblings). **Change a
solver in both places or not at all** — the parity tests are the gate.

This directory exists because interpreter overhead on the 120 Hz tick (and its
reconcile-replay amplification) is the game's scripting bottleneck. The rule
for what belongs here: settled, evaluation-grade math with a coarse call
boundary — primitives and vectors in, results out, no callbacks into GDScript
mid-solve. "Settled" is the bar for something new: a mechanic still being found
stays in GDScript until it stops changing. Mature orchestration, feel tunables
and all, may be ported when the measured cost earns it; the GDScript stays the
reference and the parity test is the gate, as for any kernel.

## The one non-kernel: `NativeGifEncoder`

`NativeGifEncoder` (goal-clip GIF export, `Scripts/game/gif_exporter.gd`) is
registered here but is **not** a port and touches no tick. It qualifies on the
other half of the rule — a coarse boundary around work GDScript is simply too
slow for (palette quantization plus LZW over ~150 frames: seconds interpreted,
well under one in C++). Three consequences worth knowing:

- **It has no parity gate**, because it has no GDScript reference to agree
  with. `tests/unit/game/test_gif_encoder.gd` pins it by decoding its output
  with an independently written GIF reader instead.
- **It is deliberately absent from `NativeKernels.KERNEL_CLASSES`.** That
  census answers "is gameplay running the C++ or the GDScript path?", and a
  non-gameplay class in it would make the boot log and debug digest report
  `PARTIAL` for a reason that has nothing to do with the tick.
- **It is the reason `build_profile.json` enables `Image`.** The other bound
  engine class beyond `RefCounted` / `OS` is `Skeleton3D`, for `NativeArmRig`
  (below).

## Layout

- `src/` — extension sources. One `.h`/`.cpp` pair per ported kernel plus
  `register_types.*`.
- `godot-cpp/` — git submodule, branch `4.5` (no 4.6 branch exists upstream
  yet; GDExtension is forward-compatible, `compatibility_minimum = "4.5"`).
  Switch to the matching branch when upstream publishes it.
- `build_profile.json` — limits generated bindings to the classes actually
  used; keeps a clean build to ~1–2 min instead of ~10.
- `mitts_native.gdextension` — the manifest Godot auto-loads. Until a binary
  for the current platform exists under `bin/`, Godot logs a load error at
  startup and the `Native*` classes are simply absent — the game and the GUT
  suite still run, and parity/benchmark tests go *pending* instead of failing.
  **In CI that skip is a failure instead** (`MITTS_REQUIRE_NATIVE=1`, see
  `tests/native_parity_guard.gd`): the workflow builds the extension first, so
  an absent class there means the build or the registration broke, and a skip
  would report a gate that never ran as green.
- `bin/` — build output, gitignored. Every machine builds its own.
  `bin/.built-from` records the commit the binary was built from; the git hooks
  compare it against the working tree (`.githooks/native-stale-check.sh`). A
  kernel's `configure` only catches a binary that reads a tunable the scripts no
  longer have, and drops to the GDScript fallback silently. A binary older than
  a tunable or method it lacks passes, then runs without the tunable or errors
  on the missing call, so the hook's warning is the only one.

## Building

First time (or after the submodule bumps):

```bash
git submodule update --init native/godot-cpp
bash native/build.sh              # or: cd native && scons build_profile=build_profile.json -jN
```

`build.sh` builds `template_debug` (what the editor and headless GUT runs
load). Pass `target=template_release` for the export build. On Windows, run
from a shell where either MSVC (`x64 Native Tools` prompt) or MinGW is on
PATH — scons picks up whichever it finds; add `use_mingw=yes` to force MinGW.

After the first successful build, restart the editor once so it picks up the
extension. Subsequent rebuilds hot-reload (`reloadable = true`), though
Windows sometimes holds the DLL lock — if the reload doesn't take, restart the
editor.

## Shipping

Players never build anything: `deploy.yml` and `deploy-steam.yml` cross-
compile the Windows `template_release` DLL with mingw-w64 (statically linked
runtime, no extra dependencies) before the Godot export, and the export packs
whatever the `.gdextension` manifest references. A missing DLL ships a
working game that silently runs the GDScript fallback — the boot log and the
debug digest's `native_kernels` field are how you catch that, in a shipped
build exactly as on a dev machine.

## Verifying a port

```bash
bash .claude/hooks/run-gut.sh -gtest=res://tests/unit/rules/test_native_ik_parity.gd
bash .claude/hooks/run-gut.sh -gdir=res://benchmarks   # includes the IK micro-bench
```

The micro-benchmark (`benchmarks/test_ik_micro_benchmark.gd`) reports
GDScript-vs-native µs/call including boundary-crossing cost (the IK solvers and
the arm rebuild). Compare
relatively within one run; a debug engine build inflates both sides
differently.

## Wired call sites

Every port is live behind a null-checked native handle created where its
GDScript config is built — the extension missing simply leaves the handle
null and the reference GDScript path runs (a fresh clone, or any platform
without a built binary, loses performance, never correctness — CI builds it):

- **Movement** — `SkaterController._apply_movement` / `_apply_block_movement`
  (per-tick thrust rides `apply_movement_with_thrust`), plus the batched
  `integrate_forward` in `RemoteController` (stage-3 render) and
  `LagCompRewind.forward_predict_skater` (host claim rewind) — both through
  the SAME per-skater instance (`SkaterController.native_movement()`), which
  is what keeps render == rewind.
- **Blade IK** — `SkaterIKCoordinator` (`project_blade`, and
  `_solve_top_hand`'s three passes onto the leaned ice as one
  `solve_on_ice` call, its per-tick config in the arguments rather than set
  property by property each pass); the rest of the config syncs inside the
  cached-config builders, so `invalidate_configs()` covers both
  representations. `test_native_ik_parity.gd` holds `solve_on_ice` against
  the coordinator's own GDScript loop.
- **Blade dangle** — `SkaterIKCoordinator.apply_blade_from_mouse` step 2 (the
  stateful speed-cap / arrive-law smoother, `NativeBladeDangle.advance`);
  reset/seed forward from `reset_blade_smoothing` / `seed_blade_smoothing`,
  config syncs via `_sync_dangle_config` under `invalidate_configs()`.
- **Blade pass** — the whole of `SkaterIKCoordinator.apply_blade_toward`
  (every skater's tick, and every replayed input): the reach target, the board
  and net reach limits, the carry's two hands and backhand stop, the rest reach,
  the hand solve, the commit pose, the transit hop, the board, goalie and net
  clamps and the rigid rebuild. It drives the two kernels above through `bind`,
  so the dangle's state and the top hand's config are one between the paths.
  The coordinator gathers the pass's inputs once
  (`_native_blade_toward`); the rink and net arrive by `set_rink` / `set_net`,
  and the tunables by `configure` under `invalidate_configs()`. A puck released
  mid-pass is the one place the GDScript calls out: `run` returns with the
  release pending, the coordinator fires it and `resume`s with the live
  `has_puck`, because what the goalie loop does next depends on whether the
  release took the puck. `test_native_blade_pass_parity.gd` skates the two side
  by side; the GDScript stays the reference.
- **Puck step** — host drive (`Puck._drive_analytic`, per sub-step so the
  goalie interleave keeps its exact order) and client prediction
  (`PuckController._run_prediction`, whole-tick `step_tick` batching), both
  configured by `NativePuckStepFactory` so authority and prediction run the
  identical step.
- **Swept-OBB atom** — `GoalieContactDetector.nearest` (host saves + client
  goalie-stop prediction).
- **Gait core** — `SkaterSkatingCoordinator.apply` (render rate, every skater):
  `locomote` runs `SkaterLocomotion`, the hip alignment and pivot read and the
  reach sit in one call, and `solve` the `GaitPose` stance and leg solve (LegIK,
  the ice frame, the runner depth) on the hips' tilt the coordinator reads off
  the skater. The overlay layers stay GDScript and shape the pose the port
  loads into `GaitPose` (`load_native_legs` before the leg layers,
  `load_native_trunk` after them), so every pass runs the port and the parity
  fuzz (`tests/unit/rules/test_native_gait_parity.gd`) drives the overlays too.
  Tunables load by name in `configure(controller)`, re-run from
  `SkaterController.apply_attributes`.

- **Leg chain** — `SkaterLegRig`'s contact seat (render rate, every drawn
  skater): the second-foot plant walks a knee out from the gait's pose,
  evaluating the leg chain to the runner a dozen to two dozen times a frame
  (`_plant_feet`, `_chain_low`), and every ankle write lays the blade
  (`_foot_pose`). The rig mirrors the leg's rest geometry and the gait's pose
  into the kernel and keeps the bone writes. Measured with
  `benchmarks/test_skater_frame_benchmark.gd`: the seat from 17–36 µs to 7–10
  in the glide, the turns and the stop.
  `tests/unit/rules/test_native_leg_chain_parity.gd`.

- **Arm rig** — `SkaterArmRig._update_arm` (render rate, every drawn skater,
  both arms): `pose` runs the whole arm and **writes the bones itself** — the
  five arm parts and that side's deltoid cap, on the `Skeleton3D` handed to
  `bind`. That is the one exception to "results out": the math is cheaper
  than the crossings, so a port that hands six transforms back for GDScript to
  write measured 9.2 µs against the GDScript's 10.6; one crossing is ~4. The
  rig keeps its own view of the caps (`_basis`, `_girdle`) for the reposes it
  makes itself (trunk texture, sizing) and reads the native's back on demand
  (`_sync_cap`); a degenerate span returns false and takes the GDScript path.
  `tests/unit/rules/test_native_arm_rig_parity.gd`.

- **Carry rollout** — `AICarryRollout.roll_all` (the bot carrier's near moves,
  four rolls a carry search on the AI worker): every move skated in one call,
  through the movement step `NativeSkaterMovement` shares (`movement_step`), the
  facing rule, the board shield and the body's containment. The domain cannot
  name a ClassDB class, so the application layer installs the kernel
  (`NativeCarryRolloutFactory.install`, from `GameManager._ready`) and each
  rollout builds its own; the caps load by name once per caps object. 780 → 85 µs
  for the seven moves. `tests/unit/ai/test_native_carry_rollout_parity.gd`.

- **Shot-field read** — `AIShotOdds._weigh` (every shot the bots price, on the
  AI worker): the bilinear spot blend, each spot's kernel over its cells and the
  weighted odds in one call. The GDScript builds the field and hands its packed
  per-cell arrays over once (`attach_native`, re-run when
  `NativeShotOddsFactory.install` sets the factory from `GameManager._ready`);
  each query's inputs stay GDScript. The matched cells come back only to the
  queries that read them (the pick, the xG spread, a deflection). Weights round
  through float as the GDScript's packed arrays do, so the two agree to the bit.
  38 → 5 µs a read; the carrier's carry search 26–28% faster in the zone.
  `tests/unit/ai/test_native_shot_odds_parity.gd`.

- **Jersey tails** — `HemFlaps.step` (render rate, every skater and keeper,
  every frame): the cloth below the belt or the chest protector — the
  anchors, the verlet step, the relaxation (segment lengths, the ring's
  spacing) and the push out of what it drapes over — in one call that reads
  its bones off the skeleton and **writes the flap bones itself**, as
  `NativeArmRig` does. Its drape, shares and tunables load in `configure`
  (`HemFlaps.configure_native`, re-run on a tuck change), then its colliders:
  the skater's thighs and lathe pants (`collide_skater`,
  `SkaterHemColliders`) or the keeper's pants and thigh guards as rounded
  sections (`collide_sections`, `KeeperTailColliders`). Skater 280 → 10 µs a
  frame with the writes, a thigh in the hem; a keeper's 48 flaps ~1.7 ms →
  under 0.1 ms. `tests/unit/rules/test_native_hem_flaps_parity.gd`, both.

The parity suites force the GDScript path on their reference objects (e.g.
nulling `_skating._native`) — a parity test must never compare the native
port against itself.

## Adding a kernel

1. Port the rule class to `src/<name>.h/.cpp`, mirroring the GDScript math
   exactly (double scalars, `real_t` vector components — GDScript's precision
   model). Keep the reasoning comments in the GDScript file; the C++ port
   points back at it.
2. Register the class in `register_types.cpp`.
3. Add any newly-referenced engine classes to `build_profile.json`.
4. Add a seeded fuzz parity test beside the existing one, and a
   GDScript-vs-native row to the micro-benchmark.
5. Wire the call site behind a `ClassDB.class_exists` check so unbuilt
   checkouts fall back to the GDScript path.
