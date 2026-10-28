# Strip interception — a path's risk as one chance per defender

The question the carrier's keep read answers: given his planned path and each
defender's position and velocity, how risky is the path? Two parts:

1. **His space** — the stretch of the path the defender can physically get his
   stick to, set, before the puck gets there: his position, his velocity and the
   movement physics (`AIArrival`), his options and not his choices.
2. **Will he strip it** — given he can, the odds he takes the puck.

What it leaves out on purpose:

- **Contact.** A defender already on the carrier means the path planning has
  failed; slipping away is the protect read's and the rolled moves' problem, not
  the planner's.
- **What our defenders tend to do.** Nothing in it is fitted to how our defending
  bots play (gap keeping, late engagement). Fitting the planner to the bots it
  plays against, then judging it by them, confirms itself.

## The read (`AIStripOdds`)

- **His chance at a point** (`chance_at`): his arrival clock to within his
  blade's reach of it, against the puck's time there less `SET_S` (0.25 s — a
  stick arriving with less strips next to nothing), graded across the clock's
  calibrated error the way `arrival_race` grades a race: `clamp(0.5 + (puck_t −
  arrive − SET_S) / (2 band))`, `band = max(ERROR_FLOOR_S, ERROR_FRAC × arrive)`.
- **One chance per defender per path** (`path_keep`, `carry_keep`): his best
  chance anywhere on it, taken with the odds a set stick strips (`SET_STRIP`,
  0.88). However long the puck stays in his reach, it is the one chance.
- **Defenders are separate chances:** keep = Π (1 − SET_STRIP × chance_i).
- **Where a loss happens** (`carry_strip_point`, the carry search's rolled
  moves): each defender's first chance — the first point his stick is set on with
  even odds, else his best — weighted by his odds of taking it.
- **A read looks at the first second of its path and where it is going**
  (`COMMIT_S`), from where it starts. The carrier re-plans every 33–75 ms, but a
  stick he sees coming cannot be escaped inside his reaction plus sliding a
  blade's reach aside — about a second — so that is what taking the space
  commits him to. Past it only the path's end is read, when the puck gets
  there: whether the place he is going — a crossing of the line, a destination,
  the end of a drive — is taken before he arrives. That race is what makes
  speed worth having: getting to the line sooner leaves a defender less time to
  shut a lane, so forward ice earns more than the time discount alone. A
  defender who can only get to the path in between, typically running the
  carrier down from behind ~2.4 s in, is a later decision's.

Waiting never thins the defence: with more time a defender reaches more of the
path, so a carry read from further back does not look easier. That is what
stalled the entry drill's carrier under the fan read it replaced (moment 04,
`tests/instruments/ai/test_entry_moment_trace.gd`), which spread each defender
thinner the further ahead it looked.

## What it is measured against

A worst-case interceptor (`tests/instruments/ai/test_interceptor_truth.gd`): a
real body in the duel harness whose input is replaced every tick. He knows the
carrier's path, skates flat out to the earliest point of it he reaches `SET_S`
before the puck (else the point he has most time to spare at), faces it, and jabs
his blade through the puck once it is in reach — what a defender can do, not what
ours choose to, so the read's risk is the upper bound a planner plans against.
He runs the race truth instrument's scripted carrier paths plus stagings far off
the path's side and behind it.

What the 2160 runs measured (`tools/strip_interception_fit.py`):

- No time to spare anywhere on the path: 10 of 386 lost.
- With it: ~88% lost, not rising with more spare time; the runs kept are nearly
  all ones whose first chance came as the 3 s run ended.
- The set time is physical, not his policy: aiming for no spare time instead, he
  strips less (half the runs, against 73%), and with less than a quarter second
  to spare at his point either way he takes almost nothing.
- Our defending bots, on the same paths: 30–45% of the paths they can reach.
  Not used.

`tests/unit/ai/test_strip_odds_vs_truth.gd` holds the read against the
interceptor's runs (`tests/unit/ai/data/strip_intercept_truth.txt`, written by
`tests/instruments/ai/test_interception_export.gd`): its ranking of lost runs
over kept ones and its expected losses are ratchets.

What sets the carrier's decisions (`tests/instruments/ai/test_carry_value_sources.gd`,
through the breakout and entry drills): the 1 s move's own end spot in 73% of
our-zone samples, 54% of neutral-zone and 32% of their zone, the destination
carried on in about one in ten, and that end spot's worth is the possession
read — the next line's odds from it — whose skate to the line is the long read
the window keeps from saturating.

What the reacting interceptor measured
(`tests/instruments/ai/test_reacting_interceptor_truth.gd`, both sides
reacting): losses met head on or from the side fall with how much of his range
the defender needs — half the runs a single step off the path, 5–20% at mid
and long range, none at the edge — while losses run down from behind rise to
40% at long range, all of them about 2.4 s in. The window is what separates the
two.

## Passes

A pass is the same question asked of the puck's path instead of the carrier's:
can a defender get his stick to this point before the puck does?
`AILaneReach` grades every pass lane with `AIStripOdds.chance_at` — the flat
feed along its line, the saucer from where it lands, and the rim along the board
path `AIRimPass` walks. A defender reads the windup (`AIPuckLane.LANE_WINDUP_READ_DELAY_S`), so
his clock starts before the release. The set time is the carry's 0.25 s (the
best ranking of the set times tried). Defenders are separate chances, as on a
carry.

A pass cannot react to him, so what stops it is his blade taking it, and that
is a reception — the receiver's own physics (`AIFeedReception.spill_prob`) at
the puck's pace in his frame (`AILaneReach.stop_odds`). Measured on his first
touches: under 14 m/s he catches every one; from 14 m/s, where an edge contact
starts to bobble, to 18 m/s, where a middle one does, he spills 70% (his blade
is reached across the lane, so it meets the puck at its end far more often than
a set receiver's, 35%); past 18 m/s he spills nearly all, and past 22 m/s some
deflect. A spill is still lost to the passer 55% of the time, flat at every
pace. So a hard pass is hard for the defender to hold too.

A saucer is seated above the blade plane from the release
(`GameRules.PUCK_LOFT_SEAT_M`, as `Puck.release` seats it), so no grounded stick
touches it until it lands, a metre later than a launch from the ice would. Nor
does a body: a skater body-blocks hips to shoulders, and the hardest LOW release
peaks well below the hips (0.72 m at 36 m/s).

It is measured against a worst-case interceptor who reads the windup and knows
where the puck is going (`tests/instruments/ai/test_pass_truth.gd`: flat feeds,
saucers and rims to a bot receiver, in the duel harness with the game's body
blocks; he aims only where the puck is on the ice), and held by
`tests/unit/ai/test_pass_lane_vs_truth.gd`. A pass is lost to the lane when the
defender takes it, or nobody catches it and he touched it first (a deflection,
a body block); one nobody catches that he never touched first is the
reception's, and left out.

| kind | lost | expected | ranking |
|---|---|---|---|
| flat | 416 | 417 | 0.904 |
| rim | 125 | 142 | 0.891 |
| saucer | 43 | 85 | 0.871 |

(Before the defender's stop odds the flat read expected 531 against 448 lost at
0.826; the race-era read 723 at 0.824. The interceptor faces the passer from
his staging; facing away, his blade could not come round to the puck.)

What the data says about a defender close to the release: standing on a flat
feed's line within 3 m of the passer he takes 6 of 18 — he still has to set his
stick, and the flat puck slides through his legs.

What it leaves open:

- The saucer's level: the read expects about half as many losses again as a
  saucer suffers (measured before its in-air body read was dropped).
- Reception: of the flat feeds nobody caught, nearly all were the receiver's to
  lose (276 of 286), and most at pace. That says the bots pass too hard.
- The after-catch read: the receiver's exit odds are read where the pass is
  released, so defenders seem not to close during the flight (the rim breakout
  trace: 0.80 at the release, 0.005 at the catch 1.27 s later).

## The windup

Through the windup the puck sits on the blade at the release point, a
carry-handle ahead of the body toward the target, and a stick that gets to it
pokes it off before it flies. `AIPuckLane.release_contest_clean` (every shot's
and pass's release) is each defender's one chance at that held puck: within the
reach a pass is played at (`AILaneReach.defender_reach`, 1.8 m), from where his
momentum has him, read as already playing the carrier from the windup's start,
by `SET_STRIP`. The set time on a held puck is 0.05 s (`RELEASE_SET_S`): with
that reach it fits the strips' level and ranks them best of the reaches and set
times tried; the full blade reach (2.3 m) reads a standing man at its edge as
in reach, where he strips one time in six.

Measured by the instrument's windup runs: a passer holding the puck through the
windup, strippable, and a defender at 0.8–3 m round him, standing or closing at
3 m/s, playing him from its start. Gated by
`tests/unit/ai/test_release_contest_vs_truth.gd`.

- 111 of 288 windups are stripped; the read expects 103, ranking 0.789. The
  closed-form contest it replaced expected 17, ranking 0.65.
- A standing defender within about 2 m of the held puck strips two thirds of the
  time; one closing reaches out to about 2.4 m; none past it.
- A body does not shield it: a man 0.8–1.2 m directly behind the passer strips
  every time, reaching past him to a puck in front.
- What the read does not see: a defender right in front, within about a metre
  of the puck, strips less than one beside or behind (his blade cannot come in
  that close), and the stick's side.

## Open questions


- The exact set time: 0.25 s is the interceptor's best policy measured so far;
  runs aiming for 0.1 s and 0.5 s would pin the shortest that strips reliably.
- Whether the stick lift belongs in the worst case beside the jab.
