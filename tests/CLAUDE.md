# Test suite

GUT (`addons/gut/`). Tests live in three tiers, each mirroring the source
layout (`rules/`, `game/`, `ai/`, `state/`, `controllers/`, `ui/`, `input/`):

| tier | dir | runs |
|---|---|---|
| default | `tests/unit/` | every push and PR, the deploy gates, and a bare `run-gut.sh` |
| slow | `tests/slow/` | a second CI job on PRs to `main` only |
| instruments | `tests/instruments/` | never automatically — on demand, read by a person |

## Running

```
bash .claude/hooks/run-gut.sh                                # default tier
bash .claude/hooks/run-gut.sh -gdir=res://tests/unit/state   # one directory
bash .claude/hooks/run-gut.sh -gdir=res://tests/slow         # slow tier
bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments  # instruments
bash .claude/hooks/run-gut.sh -gdir=res://benchmarks         # benchmarks
```

**On Windows, redirect rather than pipe** — the console exe throttles badly on
an MSYS pipe. On the web, run `.claude/hooks/wait-for-godot.sh` once first;
piping is fine on Linux. Use `-gselect=<script substring>` to run one script
while iterating. `-gjunit_xml_file=<path>` records every test's time, which is
how to find what a tier is paying for.

## Which tier a test goes in

**Default** unless it is expensive. A test that drives the real
keeper tick by tick over a shot grid, or the duel harness through
seconds of multi-body skating, costs seconds where a fixture costs
milliseconds; it goes in `slow/`. Before putting one there, ask whether the
same claim could be made by a fixture against the model — a cheap property in
`unit/` beats an expensive one anywhere.

**A test that asserts nothing is an instrument**, whatever it costs: a sweep
that prints a table and ends `assert_true(true)`. It is a measuring tool for a
person deciding something, not a gate, so it lives in `instruments/` and is run
when that decision comes up. A behaviour the instrument motivated gets its own
cheap assertion in `unit/`.

## What gets a test

The domain layer is pure GDScript with no engine APIs, so it is fully testable
headless — every new rule class, domain state type, and reconcile change ships
with a GUT test. Controllers and actors are tested where their logic is
extractable; scene-dependent behavior is verified by the user in a local session.

## Calibration and characterisation tests

A model that is tuned has two kinds of test, and they must not be mixed.

**Properties** say what any honest version of the model does, whatever its
calibration: a monotonicity (a wider angle never scores higher), a bound, an
ordering that is a physical necessity, an identity (a keeper outside the
shooting cone concedes the empty net), a comparison against a live constant
rather than its current value. They are ordinary assertions and a tuning change
never breaks them unless it breaks the physics. `tests/unit/ai/test_shot_odds.gd`
is the model.

**Calibration values** — what the model currently says at the doctrine's
reference looks — are a **snapshot**: rows recorded through `tests/snapshot.gd`
into a checked-in table beside the test (`tests/unit/rules/snapshots/`). Any
moved row fails with its pinned and current value. When the move is intended,
rerun the test with `MITTS_UPDATE_SNAPSHOTS=1`, review the table's diff, and
say in the commit that the new numbers are the intended ones. Never write a
tuned threshold (`assert_gt(score, 0.8)`) as an assertion: it is a snapshot row
that has to be re-pinned by hand.

Measurements against the live goalie that cost seconds are the same kind of
thing; they live in the slow tier until they are turned into properties plus a
snapshot.

A model that predicts the live goalie is held against **measured data** rather
than against itself: `tests/unit/ai/data/shot_odds_truth.txt` is the goalie's
open set per cell, written by an instrument that drives the real
keeper (minutes), and `test_shot_odds_vs_truth.gd` scores the shot
model against it in milliseconds. The data file is regenerated when the goalie
changes, never hand-edited; the test's error and concordance bounds are ratchets.

## Ratchets

`test_ui_uses_the_locale_seam.gd` is a ratchet: untranslated string literals
per file under `Scripts/ui/`, with the migrated live-match surfaces pinned at
zero and the menu files pinned at what they had. Its table is the backlog
written down, un-growable rather than invisible.

`test_no_god_class_growth.gd` is deliberately *not* one. It gates the shape of
`Scripts/` — 800 lines a file, 25 public functions a class — but the files
already over a limit are listed without a number and may change size freely.
Do not pin per-file numbers back onto it: they get bumped on most commits and
conflict on every parallel merge without stopping the listed files growing. The
guard is against a new file crossing a limit. When it fires:

- **over the limit and unlisted** — split it, or add it to the list and say why
  in the commit.
- **listed and now under the limit** — the file graduated; delete its entry.

## Netcode harnesses

Three deterministic netcode simulations under `tests/harness/`. None is a
physics harness — nothing in any of them skates. (Two other files there are not
netcode: `pin_race_harness.gd` ticks two real `SkaterController`s and a
`BoardPinTracker` against the boards for the pin's escape race, read by
`tests/slow/game/test_pin_escape_race.gd` and the instrument beside it; and
`body_jerk_harness.gd` skates the real controller through scripted transitions
and measures every drawn bone's per-frame jerk, for the body-smoothness
instrument and the `test_body_stays_smooth.gd` gate, which share its one
scenario list.) The netcode three exist because every netcode defect found so far has lived in the
plumbing (clocks, queues, buffers, ordering), and every one was found by reading
code or post-hoc telemetry rather than by a failing test.

**All three share one load-bearing property: each can reproduce a KNOWN effect
on demand.** Each has a mode flag selecting the legacy behaviour, and a test
asserting the legacy mode still fails. If one of those tests ever goes green, the
harness has stopped modelling the effect and every other assertion in the file is
worthless — **fix the harness, don't delete the test.**

### Input timing

`net_timing_harness.gd` covers the input pipeline: physics-step scheduling
against the render loop, stamping, the link, the host's dedupe/gate/drain, and
how overdue each input is when the host pops it.

It runs the real `NetworkManager.next_sim_offset` and the real
`ClockSync.input_lead_for_rtt`;
the dedupe/gate/drain rules are mirrors of `RemoteController` (a Node that can't
be stood up headless) pinned to the same constants.

Two legacy modes give it teeth. `StampMode` switches between wall-clock and
tick-domain stamping (`test_legacy_wall_stamping_loses_inputs_at_60fps`), and
`LeadMode` between a margin-only lead and one that also pays the one-way trip
(`test_a_margin_only_lead_runs_inputs_overdue`).

`test_net_timing_harness.gd` sweeps client framerates (including 75/100/144,
which do NOT divide the 120 Hz tick and so produce an irregular step pattern)
against a latency matrix, asserting: stamps never collide, no input is dropped as
a duplicate, the drain never fires on a clean link, queue depth stays bounded,
inputs land on time at every RTT, and pop-overdue does not track framerate.

### Claim rewind

`net_rewind_harness.gd` covers the other half: does every lookup a claim resolver
makes land inside the host's state buffer, and do client and host agree on the
depth they reconstruct a remote body at? It runs the real
`StateBufferManager.get_state_at` (the future-query clamp is the thing under
test) and the real `LagCompRewind` view-times; only the ring WRITE is mirrored,
since `capture()` needs live controllers.

`ResolveMode` selects resolve-on-arrival (legacy) vs holding until the buffer
covers the instant (`DeferredClaimQueue`, shipping).
`test_resolving_on_arrival_overruns_the_buffer` is this harness's teeth, and
`test_a_fast_link_overruns_worse_than_a_slow_one` pins the counter-intuitive
shape that made the bug hard to find by playing: the CLEANER the link, the
further past the buffer the lookup lands.

`warmup_skipped` is reported rather than silently excluded — a claim stamped
before the ring is deep enough to hold its own rewind can only say "the session
just started", so a test can tell "excluded a warmup claim" from "asserted
nothing".

### Claim geometry

`net_geometry_harness.gd` answers what the other two deliberately leave open:
they assert the lookup was in RANGE, this asserts the ANSWER was right. When the
client sees its blade reach the puck, does the host's rewind agree? A false
negative is a claim the player earned and the host refused — the quantity behind
the host row's `pickup_claim_misses`.

The player aims at what they SEE (blade placed on the rendered puck), so the
client's own view always connects and the host's verdict is the entire
measurement. The blade is exact on both sides — locally predicted, then read
from the buffer rather than re-predicted — so **every disagreement is puck
prediction error and nothing else.**

The puck SOLVER is deliberately not modelled: client and host run the identical
shared step from the identical snapshot, so it contributes zero divergence by
construction. What decides a miss is prediction SPAN against events the client
could not know about, so the puck moves at constant velocity and the host injects
unmodelled deflections — which REDIRECT the puck at constant speed rather than
adding energy, or every distance in the result grows with run length. The
threshold is geometric and worth remembering:

    a miss needs   velocity error > pickup_radius / (one_way + lead)

about 5.5 m/s at 30 ms RTT — which is why gentle perturbations produce a 0% miss
rate rather than a small one.

Two flags, and the pairing is the point:

- `RenderMode` — where the CLIENT draws the puck: host-present (pre-v59) or
  host-present + input lead (shipping). This comparison is the harness's teeth,
  and it measured the regression a single playtest could not separate.
- `AdjudicationMode` — how the HOST answers "where was the puck": look up truth
  (shipping) or reproduce the client's own dead reckon (the treatment remote
  skaters already get). The second cannot refuse an honest claim.

**A refusal is only half the score.** Every way of not refusing grants something
the world moved past, so ranking on miss rate alone puts the most permissive
option first. `mean_grant_staleness_m` is the other half — how far the puck the
host ruled on sat from the true puck at the instant the blade was there — plus
`render_skew_m`, the on-screen gap between the puck's timeline and the player's
own body's, which is a property of the picture rather than of any claim.

Read `phantom_grants` as a distribution and not a count when staleness is
near-constant: with the default 12 m/s puck and 25 ms lead, puck-at-host-present
is stale by within float noise of the 0.30 m pickup radius, so its phantom rate
sits *at* the boundary. That coincidence is the finding; assert on the staleness.

**It reproduces the playtest.** At the conditions that session actually ran at —
a 75 ms lead (the since-removed servo pinned at its ceiling), 30–60 ms RTT, contested-puck
deflection rate — it produces 33–41% against the observed ~45%, and the same
conditions at the designed 25 ms lead give 6–15%. That is the validation that
makes the rest of its numbers worth quoting, and it makes the clock fix's effect
a falsifiable prediction rather than a hope.

**Quoting numbers from it.** One run turns on ~60 random deflection directions
and the miss rate moves ±20–25% relative across seeds. Average a dozen seeds
before quoting, and don't read a crossover between two arrangements to better
than ~±30 ms of RTT.

**Two traps it has already fallen into**, both of which flattered the result and
neither of which announced itself:

- *Deflections on a fixed period.* Every even period shares a factor with the
  2-tick snapshot cadence, so every deflection landed on a broadcast tick and the
  broadcast interval cost nothing — hiding ~15% of the prediction error. Timing
  is geometric now, and `test_the_broadcast_interval_costs_prediction_accuracy`
  fails if periodicity ever comes back.
- *The unplanned-blade fallback sitting on the puck.* A tick the client never
  planned a pose for defaulted the blade to the puck's own position, i.e. a
  guaranteed confirm precisely where the harness knew least.

`miss_rate` is an **error-exceedance curve**, not a player's felt miss rate: the
client aims at what it renders, so its own view connects on every eligible tick.
Also absent — jitter, packet loss, and any second claimant, so nothing here says
what a favor-the-actor grant does to the *other* player in a scramble.

When adding netcode timing, rewind, or claim-geometry behaviour, add the
assertion here first.

## Benchmarks

`benchmarks/` holds report-only host-cost scenarios plus a per-evaluator
micro-bench. They are outside the default suite. **AI performance changes run
them** and compare before/after tables — especially per-tick p95/max (host FPS is
set by the worst tick) and the per-call evaluator ranking.

## Determinism

Domain code must be replay-safe: the same inputs produce the same outputs, or
reconcile replay diverges from the host. Tests that touch AI or physics must not
depend on wall-clock time or unseeded randomness.

Instruments that stage the real goalie must also be order-free: each staging
starts from a full reset (`KeeperController.reset_to_crease`, the puck
restaged), so a measurement does not depend on what ran before it.
`tests/slow/ai/test_shot_field_cells_are_order_free.gd` holds it for the shot
field, whose cells are sharded across processes.
