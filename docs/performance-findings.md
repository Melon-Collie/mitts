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
`refresh_hz` and `bound_by` so a pasted capture can be checked rather than
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

## Open levers, and why each is or is not being taken

- **Move host duty to a dedicated server.** Deletes ~2.9 ms/frame of attributed
  host work plus the AI worker from the playing client — the single largest
  available win, and it costs nothing in feel. Server-side it is ~30% of a core
  per lobby at 120 Hz.
- **Rig solve LOD** — run the cosmetic pose solve at half rate for non-local
  skaters, phase-staggered so the load spreads across frames rather than
  alternating heavy/light. Worth ~0.8 ms/frame. The local skater stays at full
  rate. Not yet built.
- **Lowering the physics rate (issue #606, 120 → 90 Hz)** would cut every
  per-tick item at once, ~0.7 ms/frame. **Rejected**: the broadcast cadence is
  counted in physics ticks, so it trades responsiveness over ping for frame rate,
  and responsiveness is the higher priority.
- **Goalie update LOD** — ~0.22 ms/frame, but the only real slice is save
  geometry. Rejected on risk.

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
