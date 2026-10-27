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

## Open questions

- The exact set time: 0.25 s is the interceptor's best policy measured so far;
  runs aiming for 0.1 s and 0.5 s would pin the shortest that strips reliably.
- Whether the stick lift belongs in the worst case beside the jab.
- Whether a defender who fails his one chance can earn a second further down a
  long path (a chase from behind).
