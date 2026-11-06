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
  it; a hand-written copy or decode of ~2 KB of fields would be far cheaper,
  and is not measured here. The steps-only column is the one that carries.
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
buffer as the plan suggests (not tried here). For two goalies at 45 Hz that is
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
