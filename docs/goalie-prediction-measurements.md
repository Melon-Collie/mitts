# Predicting the goalie on the render clock: what was measured

The plan's open item (`docs/goalie-rebuild-plan.md`, "Open: the client predicts
the goalie on the render clock", #903) proposes that a client re-seed a copy of
the host's keeper at each snapshot's capture instant and step the same keeper
code forward to the render instant, never free-running between snapshots. It
asks for two measurements before deciding: what stepping him costs per frame
for two goalies, a save choice included, and how often and how far a predicted
save disagrees with the host's. This is both, plus what the copied state
weighs.

Instrument: `tests/instruments/keeper/test_keeper_prediction.gd` (the state
copy is `keeper_state_cloner.gd` beside it). It asserts nothing.

```
KEEPER_PREDICTION_TIERS=HARD,EASY bash .claude/hooks/run-gut.sh \
    -gselect=test_keeper_prediction -gdir=res://tests/instruments   # ~11 min
KEEPER_PREDICTION_QUICK=1 bash .claude/hooks/run-gut.sh ...          # wire-set check only, ~1.5 min
```

## How it measures

**The host** is the real keeper (`KeeperController` on `Goalie.tscn`) and the
real puck's server tick (`Puck._physics_process`, his save boxes its contacts),
played at 90 Hz through scripted plays: eight named ones (slot wristers low and
high, a cold shot from the dot, a point slapper, a carry across the slot and a
shot, a cross-crease pass and one-timer, a pad save and a put-back, a sharp-angle
drive and a short-side shot) and a sweep of 40 shots (net front, slot, dot,
high slot; low corners, five-hole, top corners; 25 m/s; the carrier standing or
skating in at 6 m/s). Every carrier settles first with the puck in the
keeper's eyes for longer than `KeeperPlayRead.PRIME_S`, so most of these shots
are ones he can read primed (the one-timer and the put-back are not; whether
each shot was primed is not recorded). The play is run twice: the
first pass records the world and the keeper every tick, the second (checked to
replay the first exactly: 0 ticks of drift) takes the snapshots.

**The client** is a second keeper in a world of its own. At every snapshot tick
(every 2nd, 45 Hz) the host keeper's whole sim state is copied onto it by
reflection, and it is stepped on from the recorded world.

**The span.** A snapshot captured at host time S arrives a one-way trip later,
when the client draws `estimated_host_time() + input_lead`. The input lead
already carries the one-way trip (`ClockSync.input_lead_for_rtt(rtt) = rtt/2 +
~28 ms`), so the span is **twice the one-way plus ~28 ms**, not the one-way plus
a fixed 25 ms lead. It is rounded up to the tick (the tick a frame between two
interpolates toward); the render clock then moves on two ticks before the next
snapshot, so each copy is compared at span and span + 1 tick and stepped to
span + 2, and every host tick is compared exactly once.

| one-way | input lead | span | ticks stepped to the render tick |
|---|---|---|---|
| 15 ms | 42.8 ms | 57.8 ms | 6 (66.7 ms) |
| 30 ms | 57.8 ms | 87.8 ms | 8 (88.9 ms) |
| 50 ms | 77.8 ms | 127.8 ms | 12 (133.3 ms) |
| 75 ms | 102.8 ms | 177.8 ms | 16 (177.8 ms) |
| 100 ms | 127.8 ms | 227.8 ms | 21 (233.3 ms) |

Hard reads in 130 ms cold and 70 ms primed; Easy in 300 and 160 ms.

**What the copy is fed after S:**

- **TRUTH**: the world as the host had it, every release and contact on its
  tick. A lower bound on disagreement, and the check that the copy is complete.
- **HIDDEN**: as TRUTH, but a release after S is not seen until the next
  snapshot re-seeds him: the puck stays on its carrier's blade (a pass in flight
  flies on), the shooter's shot state stays, and nothing the release causes
  reaches the copy. This is a remote shooter's shot; the client's own shot it
  knows before the host does, which is TRUTH.
- **DR**: as HIDDEN, with the skaters dead-reckoned from S at their S velocity
  and shot states.
- **WIRE**: TRUTH, but copying only the fields listed as needed on the wire
  (below), the rest left stale from the last copy or, every other snapshot, at a
  never-played keeper's defaults.

**What is compared**, client against host on the same tick: the farthest any
corner of any of his 22 save boxes sits from the host's (the box gap), the root,
the save state (chosen, low half, hand, side), and per shot the verdict: the
shot's free flight (the puck's own frame step, no keeper) marched against each
keeper's boxes tick by tick, first contact (which part, which tick) or the goal
line. On the host that verdict matched the real puck's first contact on every
shot but one (Easy's sharp-angle shot: wide in free flight, met by the real puck
three ticks later).

## Approximations

- The client's own puck prediction is not modelled. A loose puck already in
  flight at S, and his contacts with it, are the host's in every feed; what a
  mispredicted keeper does to the puck is read from the shot verdicts instead.
- Remote skaters are fed truth (TRUTH, HIDDEN) or constant-velocity dead
  reckoning (DR). The plays move their skaters at constant velocity, so DR adds
  almost nothing over HIDDEN here; real skating would.
- Only a release is hidden. Tips, body blocks and stick contacts are not in
  these plays.
- No packet loss, jitter or clock error: the span is exact and fixed per
  one-way.
- Every host shot met his gear (first contact, as the shot field counts a
  save), so a client save where the host is beaten is not exercised; every
  verdict disagreement below is the client's keeper missing a puck the host's
  met.
- The shots are a scripted set, mostly primed. The disagreement rates are for
  this set and are not a game-wide rate.

## Disagreement

TRUTH is **0.0 cm on every compared tick at every one-way** (4,260 ticks per
one-way and tier): with the world he saw, the copy steps to exactly the host's
keeper. The keeper is deterministic, the reflective copy is complete (nothing
reached was uncopyable), and the WIRE subset reproduces it exactly too.

HIDDEN, the release not yet seen:

| | one-way | box gap p50 / p95 / max | ticks gap > 1 cm | save state differs (ticks with a save) | shot verdicts: X / ~ of shots | box gap at the verdict p95 / max | parts furthest off |
|---|---|---|---|---|---|---|---|
| Hard | 15 ms | 0.0 / 0.3 / 72.6 cm | 2.9% | 2 / 886 | 0 / 0 of 49 | 14.9 / 45.6 cm | mask, blocker forearm |
| | 30 ms | 0.0 / 1.2 / 83.7 | 5.2% | 96 / 886 | 0 / 1 | 18.5 / 45.6 | mask, shaft, forearms |
| | 50 ms | 0.0 / 20.7 / 105.5 | 9.9% | 282 / 886 | 1 / 1 | 28.8 / 45.6 | mask, shaft, forearms |
| | 75 ms | 0.0 / 42.1 / 117.8 | 14.6% | 468 / 886 | 2 / 6 | 45.6 / 78.2 | shaft, mask, forearms |
| | 100 ms | 0.0 / 56.1 / 124.3 | 20.5% | 677 / 886 | 4 / 9 | 73.9 / 78.2 | shaft, forearms, mask |
| Easy | 15 ms | 0.0 / 0.3 / 23.9 | 2.7% | 0 / 1066 | 0 / 0 of 48 | 16.7 / 18.5 | mask |
| | 30 ms | 0.0 / 0.8 / 36.0 | 4.6% | 0 / 1068 | 0 / 0 | 17.9 / 21.5 | mask |
| | 50 ms | 0.0 / 3.4 / 45.8 | 8.9% | 0 / 1072 | 0 / 0 | 18.5 / 21.5 | mask |
| | 75 ms | 0.0 / 10.3 / 48.9 | 13.4% | 96 / 1076 | 1 / 1 | 24.0 / 27.9 | mask, shaft |
| | 100 ms | 0.0 / 23.9 / 60.8 | 19.2% | 325 / 1079 | 3 / 5 | 32.9 / 34.6 | mask, shaft |

X: one keeper met the shot and the other did not. ~: both met it, on another
part or another tick. DR is within half a centimetre of HIDDEN at p95 everywhere
(the instrument prints both). The roots sit at most 1.8 cm apart at p95: what
differs is his limbs, not where he stands.

Box gap by play, Hard, HIDDEN (p95 / max cm):

| play | 15 ms | 30 ms | 50 ms | 75 ms | 100 ms |
|---|---|---|---|---|---|
| slot wrister, low glove | 0.0 / 2.0 | 0.3 / 26.0 | 2.0 / 46.6 | 31.7 / 46.9 | 46.6 / 58.1 |
| slot wrister, top blocker | 0.0 / 1.0 | 0.2 / 16.7 | 1.0 / 37.9 | 29.2 / 37.9 | 37.9 / 37.9 |
| dot, cold, far pad | 0.0 / 1.2 | 0.2 / 13.9 | 1.2 / 50.4 | 40.6 / 66.5 | 62.6 / 78.0 |
| point slapper, five-hole | 0.0 / 0.1 | 0.0 / 16.0 | 0.0 / 25.2 | 16.8 / 42.6 | 30.2 / 82.6 |
| carried across the slot, shot | 0.0 / 1.2 | 0.0 / 23.6 | 0.0 / 71.8 | 0.9 / 83.8 | 47.8 / 90.7 |
| cross-crease pass, one-timer | 1.3 / 8.2 | 3.0 / 14.4 | 8.2 / 28.8 | 14.4 / 43.8 | 32.8 / 74.5 |
| rebound and put-back | 15.1 / 72.6 | 43.0 / 83.7 | 61.5 / 105.5 | 83.7 / 117.8 | 110.7 / 118.8 |
| sharp angle, short side high | 0.0 / 10.4 | 0.0 / 28.7 | 2.9 / 47.8 | 19.9 / 53.9 | 47.8 / 55.6 |
| sweep, standing (20 shots) | 0.4 / 18.5 | 1.9 / 26.4 | 22.7 / 63.4 | 45.8 / 99.0 | 57.4 / 119.9 |
| sweep, skating in (20 shots) | 0.4 / 24.0 | 1.5 / 28.5 | 24.0 / 61.3 | 43.8 / 80.0 | 57.3 / 124.3 |

The shots whose verdict differed, Hard, HIDDEN (release to verdict; = same, ~,
X; at 15 / 30 / 50 / 75 / 100 ms):

| shot | release to verdict | host | 15 | 30 | 50 | 75 | 100 |
|---|---|---|---|---|---|---|---|
| sharp angle, short side high | 111 ms | shaft | = | = | X | X | X |
| net front, skating in, low glove | 78 ms | blade | = | ~ | ~ | ~ | ~ |
| slot, standing, top blocker | 167 ms | blocker | = | = | = | X | X |
| slot, standing, low glove / low blocker / five-hole | 178 ms | blade, paddle | = | = | = | ~ | ~ |
| slot, skating in, top glove / top blocker | 178 ms | glove, blocker | = | = | = | ~ | ~ / X |
| slot, skating in, low glove / low blocker / five-hole | 189 ms | blade | = | = | = | = | ~ |
| slot wrister, top blocker | 222 ms | blocker | = | = | = | = | X |
| dot, cold, far pad | 233 ms | glove | = | = | = | = | ~ |

The other 36 shots agreed at every one-way, the standing net-front shots
(44–67 ms) and everything from the dot and the high slot (267–389 ms) among
them.

### Why it disagrees where it does

- **A verdict differs only for a shot whose flight is longer than his read and
  shorter than the span.** Shorter than his read, neither keeper has moved for
  it when it arrives; longer than the span, the copy that draws the arrival was
  seeded after the release. The shots above fit that window: on Hard, primed,
  70 ms up to the span.
- **The save itself goes after the primed read, not the cold one.** The plan's
  window is the cold read (130 ms on Hard), but a settled carrier primes him and
  he reads a primed shot in 70 ms: the save state already differs on 2 ticks at
  15 ms one-way (the second compared tick, 78 ms, is past 70) and on 11% of the
  ticks with a save at 30 ms (an 89 ms span), where the cold read would still
  hold. On Easy (160 ms primed) it holds through 50 ms one-way and starts at
  75 ms.
- **Below the read, the gaps are his eyes and his cover.** At 15 ms one-way the
  ticks over 1 cm are almost all the mask: `KeeperLook` turns his head to the
  puck as it is now, not one read ago, so a hidden release turns the host's head
  and not the copy's. The put-back play differs at every one-way because a
  release ends a cover at once (`read.reading()` gates `_cover_the_puck`, the
  poke and the fetch the tick the read starts) and the cover and the fetch plan
  on the puck as it is now.

## Cost

This machine: a container CPU, the stock Godot 4.6.2 headless debug binary, no
native extension. No keeper code is native on any build, so the extension would
not change his tick; the absolute numbers are this machine's, and the ratios to
the host's own tick are the comparison to read. "Two keepers" is twice the
measured keeper, who faces every shot; a keeper at the far end is cheaper, so it
is pessimistic.

Hard (Easy within ~10%):

| one-way | step p50 / p95 / max µs | ticks that choose a save: p50 / max µs | a snapshot's steps (span + 2), mean ms | two keepers per 60 fps frame, steps only, mean ms | with the reflective copy, mean ms | the snapshot's frame, two keepers (copy + span), p95 / max ms |
|---|---|---|---|---|---|---|
| 15 ms | 207 / 481 / 7353 | 1967 / 7353 | 1.96 | 2.93 | 9.27 | 17.5 / 40.9 |
| 30 ms | 203 / 465 / 7715 | 1948 / 7715 | 2.36 | 3.54 | 9.85 | 18.7 / 50.1 |
| 50 ms | 200 / 454 / 7842 | 1965 / 7842 | 3.21 | 4.82 | 11.15 | 21.4 / 50.1 |
| 75 ms | 199 / 448 / 27641 | 1954 / 7565 | 4.09 | 6.13 | 12.50 | 24.5 / 49.9 |
| 100 ms | 196 / 437 / 8983 | 1959 / 6037 | 5.09 | 7.64 | 13.97 | 27.5 / 60.4 |

The host's own keeper tick on the same run: p50 220 µs, p95 532 µs, the ticks
that choose a save up to 3.5 ms; two keepers cost the host **0.77 ms per 60 fps
frame**.

- **A predicted step costs what the host's tick costs** (~200 µs p50); a tick
  that chooses a save (every candidate posed and tested) costs ~2 ms, ten times
  that.
- **Re-stepping the span every snapshot multiplies it.** Each snapshot replays
  span + 2 ticks (8 at 15 ms one-way, 23 at 100 ms), so per frame the client
  pays 3.8× the host's cost for the two keepers at 15 ms one-way and 9.9× at
  100 ms, steps alone.
- **The reflective copy is the instrument's, not a design's.** It costs ~4.1 ms
  a keeper (1.3 ms for the wire set alone), most of the per-frame figure with
  it; decoding the fields from bytes is measured below (*Over the delta
  channel*: ~1.25 ms with a generic decoder). The steps-only column is the one that carries.
- **The snapshot's frame spikes.** The catch-up (copy plus the span's steps)
  lands in the frame the snapshot arrives in: 17–28 ms for two keepers at p95
  here (about 8 ms of it the reflective copy), 41–60 ms at the worst. Of a
  step, solving his skeleton is ~17 µs and seating his 22 boxes on their nodes
  ~80 µs.

## What the copy carries

Everything reachable from the controller by script variables: the controller's
own fields and ten collaborators (motor, brain, read, play, save, cover, look,
fetch, poke, clear), the motor's eight (footwork, drop, slide, post, route, save
move, glide, low ready) and the Keeper node's skeleton. Shared, not copied: the
nodes (goalie, puck, skaters), the tier's profile, his world view and the
client-side interpolation plumbing. Nothing reached was a Callable, a Signal or
a native object, so no keeper source had to change.

Taken mid-save, quantized at `KeeperPoseCodec`'s scales (2 B a float, 6 B a
position, 1 B an int, a bit a bool, 130 B a pose):

| | leaves | poses | quantized |
|---|---|---|---|
| everything the copy writes | 2,267 | 33 | 8.6 KB (24.9 KB raw) |
| the wire set (WIRE: reproduces TRUTH exactly) | 793 | 5 | **1.87 KB** |
| of it, the pose already on the wire | | 1 | 130 B |
| of it, the play read's history (`KeeperPlayRead._at` … `_count`) | 396 | | 690 B |
| of it, the rest | | 4 | 1.05 KB |

Left off the wire set, and checked unneeded (left stale and at defaults, the
copy still exact): the tier's tuning, each collaborator's scratch (the save's
trial skeletons and poses, the route's planning, the cover, poke and fetch
plans), the poses each mover builds once in `_init`, the skeleton (solved from
the pose), and the controller's measured velocities. What stays: every mover's
phase, clocks and from/to (`KeeperFootwork`, `KeeperGlide`, `KeeperDrop`,
`KeeperSlide`, `KeeperPost`, `KeeperSaveMove` with its from and to poses,
`KeeperLowReady`), the motor's queue and frozen state, the route's goal, the
brain's zone, post, race and plant, the shot read (age, flight, primed, hidden
time), the play read's current read and its history, the save under way (its
halves, hand, face, clocks and the hand going back), the look, and the
controller's flags and clocks. The instrument prints the field list. It is
checked over these plays only: states they do not reach (a long RVH sequence, a
held cover played out) could need more.

Against today's 142 B a goalie a snapshot, the wire set adds ~1.74 KB, or
~1.05 KB if the play read's history is rebuilt from the client's own snapshot
buffer as the plan suggests (tried below, *Over the delta channel*, along with
what it all costs delta'd). For two goalies at 45 Hz that is
~157 KB/s a client, or ~95 KB/s, against ~43 KB/s for the whole 5v5 snapshot
now. The estimate is a flat per-field encoding: nothing is gated on which move
is under way, though at any instant most movers are idle.

## What this says about the plan

- **Re-seeded prediction is exact when the client knows what the host knew.**
  The keeper is deterministic and his state copies completely; with the world
  as the host saw it, the predicted keeper is the host's to the bit at every
  span.
- **The window it is exact in is narrower than the plan states.** The span is
  twice the one-way plus ~28 ms, and the saves of a settled shooter go on the
  primed read: on Hard the predicted save state already differs on a few ticks
  at 15 ms one-way, on Easy it holds through 50 ms. Even inside it, his eyes, his cover and the
  release ending a cover act on the puck as it is now, so a hidden release moves
  his mask and, round a loose puck, his whole body.
- **Disagreement at the verdict is rare in this set and grows with the span.**
  No shot's verdict differed at 15 or 30 ms one-way on either tier; on Hard 1
  of 49 at 50 ms, 2 X and 6 ~ at 75 ms, 4 X and 9 ~ at 100 ms. All were shots
  whose flight fell between his read and the span; every X here was the
  client's keeper missing a shot the host's met.
- **The cost is a multiple of the host's.** Stepping him the whole span each
  snapshot costs a client 3.8–9.9× what the host pays for the same two keepers,
  ~3–8 ms a 60 fps frame on this machine before any copy, with a spike in the
  snapshot's frame that a save choice makes worse.
- **The wire state is about thirteen times today's goalie block.** ~1.9 KB a
  keeper as a flat encoding, ~1.05 KB without the play read's history.

## Over the delta channel

Since the measurement above, the world-state snapshot goes out as a delta:
each client gets the raw snapshot XOR the newest one it acked, then zstd
(`SnapshotDelta`, `WirePacking`; ~344 B a 10-skater snapshot, two goalies
included, measured with 10% loss and acks three broadcasts late,
`docs/performance-findings.md`). This section asks what the keeper's wire set
costs riding that channel, whether it can be quantized and stay exact, whether
the play read's history can be rebuilt instead of sent, and what decoding it
costs a client.

```
KEEPER_PREDICTION_BYTES=1 KEEPER_PREDICTION_TIERS=HARD,EASY bash .claude/hooks/run-gut.sh \
    -gselect=test_keeper_prediction -gdir=res://tests/instruments      # ~17 min
  + KEEPER_PREDICTION_HOST_SNAPS=1    # the keeper snaps his wire set to Q16 every snapshot tick
  + KEEPER_PREDICTION_SEARCH=F32      # a feed per class with only it lossy (or Q16, or F32:<Class,...> per field)
  + KEEPER_PREDICTION_QUICK=1 [KEEPER_PREDICTION_AT=<one-way index>]   # one one-way only
```

The codec is `tests/instruments/keeper/keeper_wire_codec.gd`: the wire set
above (the fields the WIRE feed copies), walked in the cloner's order and
written to a flat buffer, and a keeper rebuilt by reading that buffer back onto
the client's own objects (its node placed from his motor, his body posed from
the decoded pose, his boxes seated). Every client feed below starts from the
decoded bytes, never from the live objects, on the same plays and shots as
above, with the TRUTH world. Every other snapshot the client's keeper is first
reset to a never-played one, so nothing left off the wire survives in it.

### The layout

A u16 header, the values in walk order, then every bool as one bit at the end.
The layout is fixed: no snapshot of either tier changed the blob's length
(SnapshotDelta sends a resized snapshot whole).

| | EXACT | F32 | Q16 |
|---|---|---|---|
| scalar (GDScript's float is a double) | f64 | f32 | s16 at its field's scale |
| vector component (the engine's own f32) | f32 | f32 | s16 |
| int | s32 | s32 | s8 (none overflowed) |
| bool, the history's flag bytes | a bit, a byte | a bit, a byte | a bit, a bit |
| KeeperPose (5 of them) | its fields | its fields | `KeeperPoseCodec`, 130 B |
| object (alias, null or here) | a byte | a byte | a byte |
| `_ticks` (read only modulo 3) | a byte | a byte | a byte |
| **the blob** | 4,967 B | 4,435 B | **1,917 B** (1,223 B less the history) |

Q16 scales: angles at π/32767 (every one stayed inside ±π), clocks at 1 ms,
shares and fractions of 0..1 at 1e-4, velocities at 2.5 mm/s (±82 m/s: a
spot's velocity reached 70 m/s), positions and the rest at 1 mm; NaN and ±INF
have codes of their own. Nothing was clamped. The Q16 blob is the earlier flat
estimate (1.87 KB) plus a byte per object and the residue, so that estimate
holds.

### Does it stay exact?

Box gap (cm, p95 / max) of the client rebuilt from the bytes against the host,
TRUTH world, Hard at 50 ms one-way; the full run's other one-ways and Easy
agree in shape:

| feed | box gap | ticks > 1 cm | save state differs |
|---|---|---|---|
| EXACT | 0.0 / 0.0 | 0 | 0 / 886 |
| F32 | 0.0 / 13.5 | 0.8% | 1 |
| F32, the scalars below kept f64 | 0.0 / 0.0 | 0 | 0 |
| Q16 | 0.4 / 73.0 | 3.6% | 35 |
| Q16, **the keeper snapping his wire set to Q16 on every snapshot tick** | 0.0 / 0.0 | 0 | 0 |

- **EXACT bytes reproduce the reflective copy exactly**, 0.0 cm on every
  compared tick at every one-way, both tiers: the layout carries everything the
  WIRE feed showed he needs.
- **Any rounding breaks bit-exactness, but at f32 only six scalars.**
  Searched class by class and then field by field (Hard at 50 ms, Easy at 75
  and 100 ms): `KeeperGlide.x`, `.z` and `._drive`, `KeeperShotRead.age` and
  `KeeperSlide._clock` move his boxes (up to 67 cm), `KeeperMotor.x` by
  0.1 cm; they accumulate or are compared against thresholds. With those six
  at f64 and the rest at f32 the copy is exact at every one-way on Hard and on
  Easy (the full run held five of them, which left a tick or two parting on
  Easy at 75 and 100 ms, max 16 cm, until `KeeperSlide._clock` was found;
  the six were then checked at those two). The search covers these plays
  only.
- **At Q16 the misses are in the movers and the reads.** Quantizing one class
  at a time, the rest exact: `KeeperPlayRead` (max 73 cm, 3.1% of ticks),
  `KeeperMotor` (15 cm, 36 save-state ticks), `KeeperGlide` (25 cm),
  `KeeperRoute` (17 cm), `KeeperShotRead` (15 cm, 6 save-state ticks); the
  poses, `KeeperSave` and `KeeperSaveMove` under 2 cm; the other eleven classes
  0.1 cm or nothing. No class can be named "the" field to keep: the misses are
  spread over every class that integrates something.
- **Quantizing on both sides is exact.** If the keeper's tick sets his own wire
  set to its Q16 value on every snapshot tick (every 2nd tick) — the host's
  keeper in both passes, the client's copy on the same ticks as it steps the
  span — the client rebuilt from the Q16 bytes is the host's to the bit:
  0.0 cm at 50 ms one-way on both tiers, as TRUTH and EXACT are. It costs the
  host's play nothing measurable here: on all 97 shots, both tiers, the host's
  verdict (the part and the tick of first contact) and the real puck's outcome
  are the same with the snap as without it.

Q16 disagreement without the snap, by one-way (box gap p95 / max cm, save-state
ticks differing; no shot verdict differed on either tier at any one-way):

| | 15 ms | 30 ms | 50 ms | 75 ms | 100 ms |
|---|---|---|---|---|---|
| Hard | 0.4 / 16.6, 16 | 0.4 / 32.1, 23 | 0.4 / 73.0, 35 | 0.7 / 82.6, 45 | 1.3 / 82.6, 49 |
| Easy | 0.4 / 37.4, 12 | 0.4 / 46.0, 16 | 0.4 / 45.5, 26 | 0.8 / 73.0, 33 | 2.9 / 82.6, 44 |

### What it costs on the wire

Bytes per keeper per snapshot, 45 Hz, Hard (Easy within a few bytes of each);
mean / p95 / max over 2,130 snapshots. "XOR n back" is the blob XORed against
its own value n snapshots earlier, then zstd: what SnapshotDelta ships for it
with the client's ack 1 or 3 broadcasts old.

| blob | whole | zstd | XOR 1 back, zstd | XOR 3 back, zstd |
|---|---|---|---|---|
| today's goalie block (root + pose) | 142 | 126 / 138 / 146 | 49 / 104 / 119 | 56 / 112 / 123 |
| **today's block, then the Q16 wire set less its pose** | 1,928 | 729 / 961 / 1,076 | **139 / 250 / 478** | **199 / 424 / 552** |
| the same less the play read's history | 1,234 | 456 / 598 / 663 | 103 / 203 / 429 | 132 / 339 / 451 |
| Q16 wire set alone | 1,917 | 721 / 951 / 1,070 | 135 / 235 / 465 | 195 / 417 / 545 |
| EXACT wire set | 4,967 | 1,236 / 1,763 / 1,919 | 230 / 446 / 946 | 342 / 778 / 1,078 |
| F32 wire set, five scalars f64 (six: +4 B) | 4,455 | 1,162 / 1,660 / 1,787 | 215 / 412 / 859 | 321 / 722 / 999 |

Each blob here is compressed on its own, so each carries zstd's frame and the
run-length floor: an all-zero blob of the same length compresses to 18–19 B.
Inside the real snapshot those are shared with the rest of the packet, so a
blob's marginal cost is about its figure less ~18 B; the differences between
rows stand as they are.

- **Delta'd, the wire set is ~3.5× today's goalie block, not ~13×.** Most of
  it does not change between snapshots: the movers not under way, the flags,
  the far end of the history ring. With acks three back, the goalie block
  becomes ~199 B a snapshot on average instead of ~56 B: **+~143 B a keeper**,
  ~424 B at p95 against ~112 B. With acks one back, +~90 B.
- **Two keepers on the 344 B snapshot:** +~286 B mean, ~630 B a snapshot, about
  1.8× today (~16 → ~28 KB/s a client at 45 Hz). Both keepers are costed as
  the one facing every shot here; the far keeper, standing in his crease, will
  change less, and that is not measured. The plays are dense with action (each
  is measured from shortly before the release through its tail), so the mean
  leans toward a busy keeper.
- **Lossless adds about twice what Q16 does.** EXACT is +~286 B a keeper (XOR
  3), F32 with the f64 scalars +~265 B. Q16 with the keeper's own snap is
  the cheapest exact option measured.
- **The history is ~67 B a keeper a snapshot delta'd** (199 against 132, XOR
  3), not the 690 B it weighs flat: each snapshot shifts two new entries into
  the ring.

### Rebuilding the play read's history from the client's snapshots

The client's copy took everything from the bytes except the history's seven
arrays (its head and count still sent), and refilled them from what a client
holds: the snapshots up to S, every 2nd tick, positions at 1 cm and velocities
at 0.02 m/s as `WorldStateCodec` sends them. A snapshot holds the skaters as he
read them on its tick and the puck after the puck's own tick, which is what he
reads on the next; a tick between two snapshots is them lerped, with the
earlier one's carrier and shot state. Whether a body hid the puck is taken
from the host's own reading on the snapshot tick (a client would compute it
from the snapshot). A release's exact tick, which `SnapshotEventLog` could
give, is not used.

| | one-way | box gap p50 / p95 / max cm | ticks > 1 cm | save state differs | shot verdicts differing |
|---|---|---|---|---|---|
| Hard, EXACT, history rebuilt | 15 ms | 0.0 / 0.3 / 43.8 | 3.4% | 4 / 886 | 0 of 49 |
| | 50 ms | 0.0 / 1.2 / 82.6 | 5.1% | 11 | 0 |
| | 100 ms | 0.0 / 0.7 / 82.6 | 4.6% | 12 | 0 |
| Easy, EXACT, history rebuilt | 15 ms | 0.0 / 1.7 / 38.4 | 6.5% | 0 / 1066 | 0 of 48 |
| | 50 ms | 0.0 / 9.5 / 71.5 | 9.9% | 1 | 0 |
| | 100 ms | 0.0 / 13.0 / 71.5 | 14.2% | 1 | 0 |

- **It is not exact, at any one-way.** The history holds the world as he read
  it to the bit; the client has it at a centimetre and at every 2nd tick. The
  errors land in the plays where the history decides a move: on Hard the point
  slapper (p95 32 cm at 50 ms one-way, 78 cm at 100 ms), the one-timer (23–30
  cm from 50 ms), the carry across and the sharp angle (3–18 cm and 10–13 cm
  at p95 at every one-way), and the sweep's shots at their worst tick (44–83 cm max); on Easy
  his glove, most of the ticks over a centimetre.
- **It is on the order of a hidden release.** The earlier HIDDEN feed (a
  release the client has not seen) ran 0.3–56 cm at p95 on Hard; the rebuilt
  history runs 0.3–1.2 cm at p95 on Hard and 1.7–13 cm on Easy, with maxima as
  large as HIDDEN's, and like HIDDEN it is there at the shortest span.
- **It saves ~67 B a keeper a snapshot.** Sending the history keeps the copy
  exact for about a third of the wire set's delta'd cost.

### What decoding costs a client

Per keeper per snapshot, this machine (a shared 4-core container; part of the
run overlapped another job's load, so read the ratios): µs.

| | p50 | p95 |
|---|---|---|
| the reflective copy (TRUTH, the earlier instrument's) | 4,381 | 6,868 |
| decode the Q16 bytes, pose him and seat his boxes | 1,251 | 1,993 |
| of which his fields | 1,041 | 1,616 |
| decode the EXACT bytes | 1,270 | 1,976 |
| the host's encode of the Q16 bytes | 1,321 | 2,132 |

- **Decoding the bytes is ~3.5× cheaper than the reflective copy** and the
  realistic path; it lands the catch-up the earlier report measured (copy plus
  the span's steps) at ~1.25 ms plus the steps, not ~4.4 ms plus them.
- **The decoder here is generic.** It walks each class's script variables and
  dispatches on each value's type; naming the field costs little (a field
  written by name 0.05 µs against 0.03 µs by a member assignment, measured in
  the same run), so nearly all of the ~1 ms is the walker's per-value dispatch
  in GDScript. A hand-written decode and encode of these ~800 values would be
  well under that; it is not written or measured here.
- **The encode is the host's per snapshot**, ~1.3 ms a keeper with this codec:
  ~0.12 s a second for two keepers at 45 Hz, which a hand-written encoder must
  bring down before this ships. With the keeper's own Q16 snap, each snap is
  an encode and a decode on the host every 2nd tick, and the client's replay
  of the span snaps on the same ticks; here that is the codec again, while in
  the game it would be the quantize applied to his fields in place, not
  measured.

### What this says about the plan

- **The feature lands at ~200 B a keeper a snapshot delta'd** (p95 ~420 B,
  acks three back): +~145 B a keeper over today's goalie block, the whole
  10-skater snapshot ~344 → ~630 B for two keepers on average. That is the Q16
  wire set, the history sent, riding after today's block.
- **Exactness then needs the keeper to quantize himself.** Q16 bytes alone
  disagree (up to 83 cm, no verdict changed in these plays); with his wire set
  snapped to its Q16 value at every snapshot tick on both sides, the client is
  exact (checked at 50 ms one-way, both tiers), and the host's play here was
  unchanged by it. The snap is part of
  the keeper's own tick, so it would move the shot field and the shot odds
  truth, which are regenerated from his play.
- **Without the snap, lossless is twice the bytes** (~320–340 B a keeper),
  and f32 alone is not enough: six scalars need f64.
- **Rebuilding the history is not worth its error.** It saves ~67 B a keeper
  and breaks exactness at every one-way, by as much as a hidden release.
- **Decoding is ~1.25 ms a keeper with a generic decoder**, against ~4.4 ms for
  the reflective copy; the host's encode at the same cost is the number a real
  codec has to cut.
