# Strip interception — a path's risk as one chance per defender

The question the carrier's keep read answers: given his planned path and each
defender's position and velocity, how risky is the path? Two parts:

1. **His space** — the stretch of the path the defender can physically get his
   stick to before the puck gets there: his position, his velocity and the
   movement physics (`AIArrival`), his options and not his choices.
2. **Will he strip it** — given he can get there, the odds he takes the puck, by
   how much time he has to spare there.

What it leaves out on purpose:

- **Contact.** A defender already on the carrier means the path planning has
  failed; slipping away is the protect read's and the rolled moves' problem, not
  the planner's.
- **What our defenders tend to do.** Nothing in it is fitted to how our defending
  bots play (gap keeping, late engagement). Fitting the planner to the bots it
  plays against, then judging it by them, confirms itself.

## Why not the strip odds as they are

`AIStripOdds` (`docs/defender-race-plan.md`) sums expected strips over the path's
stretches from a fan of where each defender might be. Read by how far ahead it
looks (`tests/instruments/ai/test_strip_odds_by_horizon.gd`) it expects twice the
losses our defenders take at 0.5–1.5 s and a third of them at 2–3 s: the fan
thins a defender the further ahead it looks, so an entry read from further back
looks easier and the carrier backs off to re-approach (the entry drill's
moment 04, `tests/instruments/ai/test_entry_moment_trace.gd`). It is also fitted
to our defending bots.

What the race reads measured (`tools/strip_race_fit.py`): no loss anywhere a
defender could not get his stick first, and once he can, a rate that does not
grow with the time he has to spare. Summed over stretches, though, any race read
inherits the sum's trouble — time in reach, the contact burst, every defender
reaching everything late.

## The model

- **One chance per defender per path.** For each defender, the point of the path
  where his spare time (the puck's time there less his stick's) is greatest.
  None non-negative: he is no threat. Otherwise the path's risk from him is
  `p(spare)` there.
- **Defenders are separate chances:** keep = Π (1 − p_i).
- **`p(spare)` is the one curve calibrated**, against a worst-case interceptor
  (below), never against our defending bots.

## The worst-case interceptor

A scripted defender in the duel harness: a real body (movement, arm, poke rules)
whose input is replaced every tick. He knows the carrier's path, skates flat out
to the earliest point of it he reaches with time to set, faces it, and jabs his
blade through the puck once it is in reach. What he can do, not what ours
choose to — so the model's risk is the upper bound a planner should plan against.

Run against the same scripted carrier paths as the race truth instrument
(`tests/instruments/ai/test_defender_race_truth.gd`), the stagings recorded with
each defender's spare time at his best point; `p(spare)` is read off them.

## Steps

1. The interceptor and its instrument; record the runs.
2. Fit `p(spare)`; score the one-chance model on the interceptor runs (held
   out), and on the bot runs as a sanity check only.
3. Talk it through before anything reaches production.

## Open questions

- Whether the stick lift belongs in the worst case beside the jab.
- Whether a defender who fails his one chance can earn a second one further down
  a long path (a chase from behind).
