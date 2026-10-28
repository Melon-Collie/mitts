# 5v5 performance — what was measured

Findings from the 5v5 frame-cost investigation. This exists because the tool that
produced most of it (the F7 interleaved cosmetic-freeze sweep, `PerfProbe`) was
removed once it had answered its questions — it made the F3 overlay unusable and
its results were not going to change. The numbers are kept here so nobody
re-runs the same two weeks of work.

**Read every absolute number as a debug build unless marked otherwise.** An
export build measured ~12% cheaper overall and ~30% cheaper on the cosmetic rig
specifically, so the shipped frame is better than these figures. Rankings hold
across both.

Reference machine: i7-11700K / RTX 3080 / 240 Hz display, 5v5 (10 skaters,
2 goalies), host role, offline.

## Measure frame pacing before believing a frame number

`main_thread_ms` in the F3 panel and the digest is **not measured**. It is a
residual: `frame_ms − max(gpu_ms, cpu_render_ms)`. Anything that decides frame
length independently of how much work the main thread did therefore lands in it.

- An **fps cap** idles the main thread by exactly the work you removed, so an A/B
  measures zero.
- **FIFO vsync** (Options → Video → V-Sync: Enabled, and Adaptive until it drops)
  quantises the frame to whole refresh periods. This bites *below* the ceiling
  too, which is the trap: a saving registers only when it flips a frame onto an
  earlier refresh, so the measured gap can read as nothing or as several times
  the truth. On the 240 Hz reference machine frames land at 240 / 120 / 80 fps
  and nothing between — a 125 fps average with a 75 fps minimum is that, not a
  cost.

The shipped defaults are **vsync Enabled, no cap**. A sweep taken there is not
comparable to one taken uncapped. The digest reports `vsync_mode`, `fps_cap`,
`refresh_hz`, `thread_model` and `bound_by` so a pasted capture can be checked rather than
trusted.

Mailbox vsync is exempt — triple-buffered and not capped to refresh.

## Where a 5v5 frame goes

Per rendered frame, against a 7.4 ms main thread (~104 fps, debug):

| | ms | share |
|---|---|---|
| cosmetic rig (pose solve + write) | 1.63 | 22% |
| unattributed — engine node work, `_process` | ~2.30 | 31% |
| skater controller step ×10 | 0.87 | 12% |
| VFX + world HUD + ice scratches, combined | 0.59 | 8% |
| goalies ×2 | 0.44 | 6% |
| skater bodies ×10 | 0.44 | 6% |
| AI proper (snapshot + brains + kick) | 0.47 | 6% |
| capture + broadcast | 0.22 | 3% |
| puck | 0.19 | 3% |

There is no hot spot. The largest single item is 22% and everything else is under
an eighth of the frame.

## The cosmetic sweep's verdict (three clean runs, 36–38 rotations each)

Savings in main-thread ms per frame, against an unfrozen baseline. "Resolved"
means the gap cleared two standard errors on the difference.

| frozen | saves | resolved |
|---|---|---|
| ALL cosmetics | 2.22–2.47 | yes |
| the rig | 1.63–1.86 | yes |
| the rig's WRITE half only | 0.24–0.52 | no |
| VFX | 0.04–0.27 | no |
| ice scratch map | 0.04–0.14 | no |
| world HUD | 0.01, and once negative | no |

Conclusions that are settled and should not be re-litigated:

- **The rig is ~73% of all cosmetic cost**, consistently, across every run.
  Within it the *solve* (gait, head tracking, off-hand IK) dominates the *write*
  (bone poses, mesh rebuild) — the write half never resolved in any run.
- **The world HUD is free.** Moving the rings, chevrons, slapper indicator and
  stamina gauge into the ice shader took it to zero. Nothing further to win.
- **The ice scratch map is free.** The `UPDATE_ONCE`-instead-of-`UPDATE_ALWAYS`
  idea is worth nothing; do not spend the correctness risk.
- **VFX is at or below the noise floor.** It measured *negative* in one export
  run. The idle early-out and blade-trail guard that were proposed for it are not
  justified. Separately, swapping `basis.inverse()` for `transposed()` benchmarks
  as noise (0.23 vs 0.22 µs) — leave the clearer spelling.

## Host tick cost (`HostCostProbe`, still live — F3 → P)

Per host physics tick, 8333 µs budget at 120 Hz:

| section | µs | per actor |
|---|---|---|
| dispatch: apply | 826 | 76 ×10 |
| ↳ of which the skater controller step | ~760 | |
| goalies | 386 | **193 ×2** |
| skater bodies | 383 | 38 ×10 |
| snapshot build + enrich + accel | 262 | |
| capture + broadcast | 189 | |
| puck | 163 | |
| dispatch: kick | 122 | |
| game tail (checks + trackers) | 108 | |
| brains | 28 | |
| **attributed total** | **~2500** | |
| *AI worker (off-thread)* | *1330* | worker behind on <6% of ticks |

Taken in an all-bot 5v5 and before `KeeperController`, so two rows have moved
since. The skater step above is the bots' only (`SKATER_STEP`, inside
`AIController.apply_decision`); a human's (`LocalController` /
`RemoteController`, at priority −1) is its own row, "human skater steps". The
goalie row measures the goalie the keeper replaced. The worker row was the last
batch's time re-recorded every tick, which reads as a batch's duration; it is
now charged once, on the tick its batch is harvested, so it reads as worker time
per tick. And the AI block's main-thread totals no longer add in the brains,
which run on the worker.

Three things this settled:

- **`dispatch: apply` is not AI.** The bulk of it is
  `SkaterController._process_input`, the same call `LocalController` and
  `RemoteController` make. It is the ordinary skater tick, paid per skater
  whoever drives it. The AI proper is ~419 µs/tick, about 5% of the tick.
- **The team brains are not a spike source.** 28 µs mean. `force_retick()` firing
  off-cadence on every carrier change was a plausible story for scrum-time
  hitches and it is wrong.
- **The AI worker thread is healthy.** It finishes inside ~1.3 ms of an 8.3 ms
  tick and blocks a fresh kick on under 6% of ticks. Optimising `decide()` would
  buy bot responsiveness, not frame rate — and a faster worker kicks *more*
  batches, which slightly *increases* main-thread work.

The `Tick attributed` percentage on the panel divides by the tick **budget**, not
the step's length. The physics step ends when the work does and the remaining
wall time is `_process` and rendering, so a low percentage is not evidence of
unattributed physics.

## The AI decide path

`decide()` runs on the worker thread and the main thread never blocks on it. From
`benchmarks/test_ai_micro_benchmark.gd` and `test_ai_perf_benchmark.gd`:

- 5v5 total 122k–149k µs per game-second (12–15% of a core), of which the team
  brains are ~2%.
- Worst AI tick p95 2.3–3.2 ms, max 4.0–7.1 ms — on the worker, so it surfaces as
  the worker falling behind, never as a frame hitch.
- Most expensive evaluators per call: `CARRIER compete` 1.26–1.68 ms, `best_carry`
  candidates ~1.52 ms, `best_pass` ~0.96 ms. The carrier compete is already
  throttled to ~30 Hz.
- 5v5/3v3 multiplier 1.34–1.94× for a 1.67× roster — scaling linearly, no
  blow-up.

The path already has dispatch throttling, a far-play LOD for off-puck bots beyond
18 m, scratch buffers, beam search with exact prune bounds, and the carrier
throttle. No structural waste was found.

## Node-count reduction: what it actually bought

The skinned-skater work (see `docs/skinned-skater-plan.md`) took a skater from 67
nodes to 32 and a goalie from 46 to 41 — roughly 335 fewer scene nodes at 5v5.
Measured main thread before and after: **~6.4 ms → 6.53 ms.** The premise that
per-node transform propagation dominated was wrong, and the honest record of that
is in the plan document's closing section.

What the work did buy: no transparency pass for the on-ice HUD, no z-fighting,
analytic antialiasing, and the HUD's cost going to zero.

## Main thread by skater count

`.claude/hooks/measure-frame-cost.sh` plays a match against bots headless at
each skater count and times the process step (every `_process`, once a frame)
and the physics tick apart, because they scale differently with frame rate. "At
90 fps" composes them: the process step plus (tick rate / 90) ticks. The table
below was taken at the 120 Hz tick; *The tick at 90 Hz* after it compares the
two. Headless draws nothing, so this is the CPU's frame alone. The table below was taken on a 4-core
cloud container with the editor (debug) binary and the native kernels built,
two runs a count. Read the shape and the shares; the milliseconds belong to that
machine.

| skaters | process ms/frame | tick ms | main thread at 90 fps | per added skater |
|---|---|---|---|---|
| 2 | 1.30 | 2.26 | 4.32 | |
| 4 | 2.01 | 2.86 | 5.81 | 0.75 |
| 6 | 2.39 | 3.76 | 7.41 | 0.80 |
| 8 | 2.99 | 4.33 | 8.76 | 0.67 |
| 10 | 3.56 | 4.87 | 10.06 | 0.65 |

The tick by `HostCostProbe` section, same runs (µs a tick; one probe window a
run, so single sections are noisy):

| section | 2 | 4 | 6 | 8 | 10 |
|---|---|---|---|---|---|
| dispatch: apply (bots' skater step inside) | 369 | 912 | 1438 | 1626 | 1897 |
| goalies | 587 | 701 | 624 | 485 | 646 |
| snapshot | 224 | 292 | 326 | 290 | 490 |
| human skater steps (one human) | 430 | 509 | 450 | 441 | 432 |
| skater bodies | 122 | 217 | 227 | 247 | 354 |
| capture + broadcast | 161 | 248 | 249 | 252 | 314 |
| game tail | 137 | 141 | 137 | 120 | 157 |
| dispatch: kick | 61 | 69 | 79 | 75 | 90 |
| puck | 31 | 47 | 95 | 68 | 78 |
| **attributed** | 2137 | 3156 | 3648 | 3625 | 4484 |
| *worker (off-thread)* | *589* | *1542* | *1391* | *1394* | *2321* |

- **Linear, no blow-up.** About 0.72 ms of main thread per skater at 90 fps on
  that machine (2 → 10). Each single step's slope is noise.
- **Per skater, the tick is slightly the larger half.** The controller step is
  ~0.2 ms a tick (paid 1.33 times a frame at 90 fps) against ~0.27 ms of render
  pass a frame.
- **The probe attributes most of the tick.** Its sections cover 84–95% of the
  measured tick. The rest is the step's engine side (transform propagation,
  signal dispatch), so the tick has no hidden half.
- **The two keepers are the largest fixed cost.** ~0.6 ms a tick together,
  whatever the skater count. Next are the AI snapshot (0.2–0.5 ms) and capture
  + broadcast (0.16–0.31 ms).
- **The one human's step costs about twice a bot's skater step** (~450 µs
  against ~200). The rows are not like for like: the human's covers the whole
  `LocalController` tick (input gather, offside prediction, the prediction
  history), the bots' only `_process_input`.
- **Engine render CPU barely moves with skaters.** Drawn
  (`FRAME_COST_RENDER=1`, Forward+ on software Vulkan), CPU render went from
  1.39 to 1.63 ms between 2 and 10 skaters, ~25 draw calls a skater. Drawing
  adds ~0.07 ms a skater to the process step (skeleton and skin work).

### The tick at 90 Hz

The tick went from 120 to 90 Hz with the broadcast at 45 Hz (the network
sections below hold what that costs on the wire and on screen). Same machine,
back to back, three runs a count, the 120 Hz build in a worktree beside it:

| skaters | 120 Hz: main thread at 90 fps | 90 Hz | per added skater, 120 → 90 Hz |
|---|---|---|---|
| 2 | 5.90 ms | 4.85 ms | |
| 6 | 8.71 ms | 7.50 ms | 0.70 → 0.66 ms |
| 10 | 11.99 ms | 9.61 ms | 0.82 → 0.53 ms |

A tick costs about what it did (5.2 → 5.4 ms at 10 skaters); the saving is
paying it once a frame at 90 fps rather than 1.33 times. Above 90 fps a frame
runs fewer than one tick either way, and the saving per second is the same
quarter of the tick's cost.

### Inside the skater step and the keeper's tick

Timed in place by temporary instrumentation (`Time.get_ticks_usec()` around each
phase, not committed), 10 skaters, the same machine. The timers add ~1 µs a
phase, so read the shares. A bot's `_process_input` came to ~330 µs a call:

| phase | µs | |
|---|---|---|
| `_apply_state`: the state machine, nearly all of it the blade IK (`apply_blade_toward`, ~127) | 143 | |
| ↳ resolving the cursor to a reachable target | 74 | the first `_solve_top_hand` with its reach limits 43, `arm_shoulder` 8, `_board_reach_limit` 8, `_reach_purpose` 5 |
| ↳ the hand solve for the speed-capped blade | 28 | |
| ↳ wall and net clamps | 19 | |
| ↳ the marker writes; the dangle | 6; 4 | |
| `apply_facing` | 37 | |
| `apply_upper_body` and the re-expression | 35 | |
| fall tilt, balance, velocity lean | 29 | |
| `_apply_press` | 26 | |
| `_apply_movement` | 21 | |
| the head (intent, deflect, nudge); the stick check; the tail | 11 each | |

No phase dominates the way a missing kernel would; the IK's kernels are all
native already. The cost is GDScript orchestration spread across dozens of
small calls. `arm_shoulder()` alone is re-derived four or five times a pass,
each time from `upper_body.rotation` (a basis-to-Euler decomposition per read).

Two follow-ups settled what that is not:

- **Not GDExtension crossings.** Measured from GDScript on the same binary: a
  native property write is 0.08 µs, a `Vector3` getter 0.13 µs, and a whole
  `NativeTopHandIK.solve_on_ice` 0.7 µs. Bundling the solve's dozen crossings
  into one coarse call would save a few microseconds.
- **Not repeated reads, at match scale.** Reading the pass's body state once
  instead of once a helper (rotation, tilt, the shoulder chain, the blade
  height) was bitwise identical and took an isolated carry's step from ~345 to
  ~290 µs. Across a 10-skater match, though, it moved the bots' skater step
  from 2,123 to 2,110 µs a tick (three alternating runs each): noise. A carry
  is a small share of ticks, so it was not kept.

What remains is ordinary GDScript overhead, around 0.1–0.5 µs per member
access and call, across a few hundred of them per pass. Only porting the
pass's orchestration itself removes it, so the whole pass moved to C++
(`NativeBladePass`, `native/README.md`). In the 10-skater match, three
alternating runs a mode:

| | GDScript pass | native pass | |
|---|---|---|---|
| the bots' skater step, µs a tick | 2,103 | 1,524 | −28% |
| the human's skater step, µs a tick | 639 | 512 | −20% |
| the whole host tick, ms | 6.44 | 5.59 | −13% |

Reconcile replay runs the same pass once per replayed input, so a client
gains the same per input it replays.

The keeper's tick came to ~445 µs on the host:

| phase | µs |
|---|---|
| `_place_body` | 313 |
| ↳ `_seat`: the skeleton solve 65, `KeeperGear.box` ×22 60, the parent-frame walks in `seat_save_box` ~60, the 29 node writes ~90 | ~220–320 |
| ↳ `motor.pose`; look, transform and report; the save overlay | 42; 36; 9 |
| `motor.step` | 47 |
| `_read_play` | 26 |
| `_read_receivers`, every 4th tick | 88 |
| `brain.decide`, every 4th tick | 50 |

The save boxes have to be nodes: `GoalieContactDetector` reads each one's
`global_transform`. But `seat_save_box` walks the parent chain twice a box to
re-derive frames that only change when a body is placed.

### The Separate render thread model, tried

Under `rendering/driver/threads/thread_model = Separate` (4.6.2, `override.cfg`,
the same drawn 10-skater run), Godot warns that the feature is experimental. The
run then logs 128 "can only be called from the render thread" errors from inside
the engine: `RenderingDevice::buffer_update` and `_texture_2d_update`, with no
script frame on the stack. The F3 overlay's own
`viewport_get_measured_render_time_cpu` read errors too. It is not a free lever on
this engine version, and with CPU render this flat in the skater count it would
not change the scaling anyway.

## Open levers, and why each is or is not being taken

- **Move host duty to a dedicated server.** Deletes ~2.9 ms/frame of attributed
  host work plus the AI worker from the playing client — the single largest
  available win, and it costs nothing in feel. Server-side it is ~30% of a core
  per lobby at 120 Hz.
- **Rig solve LOD** — built as `SkaterAnimationLod` (Options → Video →
  Animation Detail): the mesh pass thins by camera distance for non-local
  skaters, phase-staggered, the local skater at full rate. It thins the bone
  writes, the seat, the head, the off hand and the arm/stick rebuild; the gait
  and the hem cloth still step every visible frame.
- **Run the render pass on worker threads** — each skater's and keeper's
  `_process` in its own process thread group, so the ~half of a skater's frame
  that is cosmetic spreads across cores. Spiked: −21% on the process step, but
  blocked by an engine race (physics interpolation's lists are unlocked against
  worker-thread transform writes). `docs/parallel-render-pass-plan.md`.
- **Lowering the physics rate (issue #606, 120 → 90 Hz)** — taken, with the
  broadcast at 45 Hz and the input cushion held at 16.7 ms (1.5 ticks): −20% of
  the main thread in a 10-skater match (*The tick at 90 Hz*). What it costs is
  measured below (*Network bytes by broadcast rate* and the two sections after
  it): under a centimetre on a remote skater, about a point of refused pickup
  claims at 60 ms RTT, and host upload down a quarter.
- **Goalie update LOD** — ~0.22 ms/frame, but the only real slice is save
  geometry. Rejected on risk.

## Network bytes by broadcast rate

Measured headless in a 5v5 against bots (60 s, 7200 encodes) and over ENet
loopback for the framing. The snapshot is a fixed layout: 7 B header, 63 B per
skater, 14 B puck, 142 B per goalie, 6 B game state, so 941 B at 10 skaters and
689 B at 6, every tick. The carrier-event tail (`SnapshotEventLog`) averaged
8 B: one count byte on 71% of snapshots, 17 B per event still inside its 1 s
retention on the rest, at most 3 seen. Bots raise only carrier changes; a human
carrier's pickups and steals add records, so expect a little more with humans.
Godot's RPC framing is 3 B (a lone `PackedByteArray` argument goes raw, not
Variant-encoded); ENet adds ~10 B, Steam plus UDP/IP more (~50 B per packet is
the netcode audit's estimate, ~5%). The figures below are payload plus framing,
without the transport.

Host upload, per human client and for an all-human lobby (bots cost nothing):

| broadcast | per client (5v5) | 3v3 (5 clients) | 5v5 (9 clients) |
|---|---|---|---|
| 45 Hz (shipped) | 43 KB/s | 1.3 Mbps | 3.1 Mbps |
| 60 Hz (before 90/45) | 57 KB/s | 1.7 Mbps | 4.1 Mbps |
| 90 Hz | 86 KB/s | 2.5 Mbps | 6.2 Mbps |
| 120 Hz | 114 KB/s | 3.4 Mbps | 8.2 Mbps |

The other direction is the input batch: 3 B + 12 × 24 B inputs (24 when the
client measures >10% loss), sent at `INPUT_RATE`: 35 KB/s per client at 120 Hz,
26 KB/s at 90; an all-human 5v5's host downloads ~2.5 Mbps at 120 Hz.

Where the snapshot's bytes are: skaters 67% (of a skater's 63 B, 4 B is the
peer id), goalies 30% (130 B of each is the keeper's pose).

### What the broadcast interval costs on screen

A remote skater is drawn forward-predicted from a base `rtt/2 + interval + PDV`
in the past to `rtt/2 + lead` ahead, so the interval is not staleness but
prediction horizon: `rtt + PDV + interval + 1/INPUT_RATE + 2 ticks`. Its cost is
how far that prediction lands from the host's body. Measured by recording a
5v5 against bots as the wire carries it and replaying the client's render
offline (the same hermite base and `integrate_forward`, PDV 3 ms, against the
host's position at the instant the prediction lands; downed and pinned bodies
left out), cm:

| RTT | 120/60 (before): mean, p95, p99 | 90/90 | 90/45 (2-tick cushion) | no forward prediction, mean |
|---|---|---|---|---|
| 30 ms | 1.4, 3.3, 5.6 | 1.3, 3.2, 5.4 | 1.9, 4.3, 7.1 | 27 |
| 60 ms | 2.6, 5.9, 9.4 | 2.7, 6.3, 10.0 | 3.1, 6.9, 10.9 | 38 |
| 120 ms | 6.3, 14.1, 21.7 | 6.3, 14.2, 21.8 | 7.0, 15.6, 23.9 | 59 |

A 90 Hz physics rate lengthens the lead by 8.3 ms (the batch interval and the two
buffer ticks are tick-sized), which cancels what a 90 Hz broadcast saves:
90/90's horizon is today's within 3 ms. 90/45 adds ~11 ms of horizon and under
a centimetre. The worst cases (0.3–0.8 m) are contacts, the same at every
cadence. The replay runs on a 120 Hz recording, so it isolates what the client
knows from how the body moves; bots, not humans, did the skating.

### What it costs a pickup

The loose puck predicts from the NEWEST snapshot, not from an interpolated
past, so its span is `one_way + snapshot age + lead`: a faster broadcast saves
only the age, half an interval on average, while the lead pays in full. Measured
on a copy of `NetGeometryHarness` stepped at 360 Hz (the shipped one rounds
every lead to a 120 Hz tick, coarser than the differences here), snapshots on
each rate's schedule, the lead `rtt/2 + margin` as `ClockSync` sets it, the
same 16 seeds per row. Refused share of earned claims at 60 ms RTT:

| | 120/60 (before) | 90/90 | 90/45 | 90/90, cushion 16.7 ms | 90/45, cushion 16.7 ms (shipped) |
|---|---|---|---|---|---|
| a deflection every ~333 ms | 11.3% | 12.5% | 13.6% | 11.3% | 12.4% |
| a deflection every ~100 ms (scramble) | 30.5% | 33.1% | 35.6% | 30.4% | 33.1% |

At 30 and 120 ms the order and the gaps are the same. The input cushion is
two ticks, so 90 Hz physics stretches it from 16.7 to 22.2 ms, and that, more
than the broadcast rate, is what a pickup pays for. Held at 16.7 ms
(`BUFFER_TICKS` 1.5), 90/90 refuses what today does; whether 1.5 ticks still
covers input jitter is `NetTimingHarness`'s question. The same cushion is in a
remote skater's horizon above, where holding it leaves 90/90 3 ms shorter than
today.

## How to measure something new

The freeze-sweep approach is gone, and its lesson is worth keeping: **an A/B that
switches work off is only sound when nothing reads that work back.** It suited
cosmetics and would have been invalid for the AI or the goalie, where suppressing
the work changes the game being measured. Those have clean call seams, so they
are timed in place instead — that is what `HostCostProbe` does.

Two traps the sweep hit, both worth remembering:

1. **A 5v5 frame varies by more than the 1–2 ms being hunted.** Sampling one
   condition at one moment measures the moment. The fix was to interleave
   conditions on a short timer so each saw the same distribution of camera
   angles and scrums, and to treat *one rotation* — not one frame — as the unit
   of observation. Frames inside a rotation are near-copies, and averaging them
   as independent samples makes a result look precise while resting on three
   observations.
2. **Report the error bar.** A 0.3 ms difference means nothing when the
   rotation-to-rotation spread is 1.5 ms, and an early run had three of four
   conditions measuring *slower* than doing the work — impossible, and nothing in
   the output admitted it.

`HostCostProbe` carries the same discipline in a smaller form: means and window
peaks are both over **ticks**, so a per-actor section's peak is the tick's total
rather than the worst single actor.

## The render side: draw calls and triangles

Everything above is the main thread. The render side was measured later, by
rendering the 5v5 opening faceoff on Forward+ (software Vulkan, so draw-call and
triangle **counts**, never timings) and hiding one thing at a time. Counts are a
property of the scene and transfer to any GPU; whether they bound the frame on a
given machine is what the F3 digest's `bound_by` answers.

| | draw calls | triangles / frame |
|---|---|---|
| as it was | 1,533 | 3.56 M |
| particles cast no shadow | 1,515 | 1.16 M |
| + nets merged (54 → 3 meshes a goal) | 1,181 | 1.16 M |
| + one-material bodies (`docs/body-draw-calls-plan.md`) | 759 | 1.16 M |
| (the same, eight spot shadows off) | 309 | 0.65 M |

Two things to know before touching this:

- **Every shadowed light re-renders every frame.** Skaters move under all eight
  shadowed ceiling spots, so each shadow map is dirty every frame and redraws
  every static caster in its cone (stands, rink, nets, goalies) along with the
  movers. Hiding the moving casters therefore removes far more than their own
  draws, and the toggles do not add up to the total.
- **A particle node casts by default, and a `GPUParticles3D` draws its whole
  `amount` in every pass**, alive or not. The skaters' 300-instance blade trails
  were two-thirds of all triangles, through eight shadow maps, for dots on the
  ice. `test_particles_cast_no_shadow.gd` holds every effect to casting nothing.

What is left is mostly the shadowed spots themselves: ~450 of the 759. The
Shadow Quality setting already trims them (`PlayerPrefs._apply_shadow_quality`).

## What each Video setting costs

`.claude/hooks/measure-graphics.sh` plays a 5v5 against bots on Forward+ and
measures each Video setting changed alone from the shipped defaults
(`tools/graphics_cost_runner.gd` has the list). Only live play is sampled — a goal
replay's cameras see twice the arena — and each condition sits between two
measurements of the defaults, its cost the difference from their mean. Run it on
a machine with a graphics card for the numbers players get; the table below is
from software Vulkan (lavapipe), 1920×1080, two rotations, where a defaults frame
took ~500 ms of "GPU" time. That rasteriser is a CPU: it over-weights triangles
and compute passes against a graphics card, so the ranking is the finding, not
the milliseconds.

| change from the defaults | GPU ms (mean, range) | of the frame | draw calls | menu tier |
|---|---|---|---|---|
| Shadow Quality Medium | −65 (−84..−47) | −13% | 434 | High |
| Shadow Quality Low | −89 (−90..−89) | −18% | 357 | High |
| Render Scale 75% | −83 (−98..−67) | −17% | 528 | High |
| Render Scale 50% | −207 (−213..−200) | −42% | 498 | High |
| Upscaling FSR at 75% | −90 (−93..−87) | −18% | 570 | Medium |
| Upscaling FSR2 at 75% | +91 (+66..+117) | +18% | 654 | Medium |
| Anti-Aliasing Off | +50 (+39..+62) | +10% | 595 | High |
| Anti-Aliasing FXAA | +4 (−25..+33) | +1% | 492 | High |
| Anti-Aliasing MSAA 4x | +110 (+27..+193) | +22% | 560 | High |
| Anti-Aliasing MSAA 8x | +71 (+23..+119) | +14% | 602 | High |
| Anti-Aliasing TAA | +72 (+14..+131) | +15% | 596 | High |
| Global Illumination SDFGI | +605 (+538..+672) | +122% | 602 | High |
| Crowd Density Low | not measured | — | — | Medium |
| Crowd Density Off | not measured | — | — | Medium |
| Volumetric Fog on | +80 (+74..+85) | +16% | 624 | High |
| Reflections off | −90 (−106..−75) | −18% | 636 | High |
| Ambient Occlusion off | −49 (−62..−36) | −10% | 660 | Medium |
| Player Shadows off | 0 (−9..+9) | 0% | 470 | Low |
| Puck Shadow off | +19 (−6..+43) | noise | 664 | Low |
| Ice Scratches off | +6 (+1..+12) | noise | 566 | Low |
| Arena Ads off | +23 (+12..+34) | noise | 556 | None |
| Animation Detail Low / Full | +21 / +4 | noise | 598 / 596 | Processor |
| Color Grade None | +9 (+6..+11) | noise | 581 | None |

The tiers in Options → Video (`OptionsVideoTab`: the `Impact` rating at the end
of each row, whose tooltip explains the setting) follow the table: High for a change worth ~15% of the frame or more,
Medium for 5–15%, Low for what cannot be told from noise but does real work, None
for a colour adjustment or a one-off paint. Three calls are judgement and say so:

- **Crowd Density is Medium** by judgement alone, with no measurement of the
  setting as it stands: it changes only the fans (Low draws every one with the
  far figure, Off empties the seats), which are instanced figures, cheap on a
  graphics card. `measure-graphics.sh crowd` on a machine with one settles it.
- **Upscaling is Medium**: FSR costs nothing over bilinear, and FSR2's compute
  pass is the kind of work lavapipe is slowest at.
- **Animation Detail costs the processor, not the GPU** — the per-skater pose
  solve (*Where a 5v5 frame goes*) — so it gets its own tag rather than a GPU
  tier it would never earn.

Two readings are not understood and are not used: turning MSAA 2x **off** reads
10% slower in both rotations, and MSAA 8x cheaper than 4x. Both are worth a look
on a real card before trusting any AA number here.
