# Release momentum — the puck leaves with the skater's motion

Status: **Phase 1 built, awaiting playtest.** Phases 2 and 3 are designed here
and not built.

## Decisions banked

- **The puck keeps the skater's motion.** A released puck's velocity is the
  skater's velocity plus the blade's push, not the push alone. Shooting in
  stride adds pace, and shooting back against your own skating takes it away.
- **The hands correct for it, and correcting costs power.** A shooter aims at
  the target, not ahead of it: the blade pushes partly against the skater's
  motion across the shot so the puck goes where the cursor is. The push is the
  shot's power, so the part spent cancelling the drift is not spent driving the
  puck. The direction stays exact for as long as the push can cancel the drift.
- **Drift comes only from what a shooter cannot correct.** In Phase 1 that is a
  push too weak to cancel the skater's motion across the shot: soft passes and
  flips while flying sideways. Hard shots never drift.
- **A blade can always leave the puck behind.** Stopping the puck takes no
  drive, so a release never travels backward along its aim. A dead release
  while skating forward is a puck left at rest on the ice: a drop pass.
- **Momentum is horizontal, and the loft keeps its own rule.** A shot keeps the
  blade's launch angle, so its vertical scales with the horizontal pace and the
  loft ladder's set angles stay what they say. A quick pass keeps its vertical
  launch speed, because the saucer and flip are calibrated in it, no steeper
  than the host's direction check allows. Either way the host's direction check
  never moves an honest release.
- **Wrist shots and quick passes only, for now.** The slapper's line is locked
  at the press, so it gets its own treatment (Phase 3).

## The model

`ReleaseMomentum` (`Scripts/domain/rules/release_momentum.gd`). World XZ: the
aim `d` (unit), the skater's velocity `v`, the blade's push `P` (the power the
release would have had standing still). Split `v` along and across the aim:
`v_par = v·d`, `v_perp` the rest.

- **Correction:** the push cancels `v_perp` as far as it can:
  `u_perp = −v_perp × min(1, P / |v_perp|)`, and what is left drives along the
  aim: `u_par = √(P² − |u_perp|²)`.
- **Release:** `r = v + u`. While `P ≥ |v_perp|` that is
  `(v_par + √(P² − |v_perp|²)) × d`: exactly at the cursor. Past it the puck
  drifts by the motion the push could not cancel.
- **The stop:** the speed along the aim floors at zero.
- **The soft floor is a pace on the ice.** The cursor band's floor
  (`min_wrister_power`, 10 m/s) is the softest pace a standing release lands.
  Skating at the target, the hands cushion the push down to land that same pace
  (`ReleaseMomentum.floor_push`, read by `ShotMechanics.release_wrister`);
  skating away, the floor push stays 10, since no harder push comes free.

Numbers at the league ceilings (10 m/s skating, 33 m/s wrister, 14 m/s quick
pass):

| release | standing | skating at it, 8 m/s | across it, 8 m/s | away from it, 8 m/s |
|---|---|---|---|---|
| full wrister | 33 | 41 | 32.0 | 25 |
| quick pass | 14 | 22 | 11.5 | 6 |
| soft wrister | 10 | 18 | 6 | 2 |
| a push of 5 | 5 | 13 | drifts | 0 (left behind) |

The inverse, the push a release needs for a pace `S` along `d`:
`P = √((S − v_par)² + |v_perp|²)`, for `S ≥ v_par`.

## Phase 1 — wrist shots and quick passes (built)

- **`SkaterController`** applies the rule after the load's cap, at the release
  (`_release_wrister`, `_fire_quick_pass`) and in the goalie's predicted shot
  (`_update_wrister_charge`), from `skater.velocity` on that tick. It emits the
  result as the usual `(direction, power)`, so the host's release, the
  shooter's release seed, the HUD and the drills read it unchanged.
- **Netcode:** the host and the shooter both compute the release from the same
  replayed inputs, and `skater.velocity` is part of what reconcile keeps
  aligned. A small velocity difference changes the pace, never the direction,
  outside the drift case. The host's power bound for a remote wrist shot is the
  shooter's max power plus the speed of that shooter's own body on the host
  (`ShotReleaseRules.release_power_bound`), or it would cut down every honest
  shot taken in stride.
- **Bots:** a bot's pass and rim commit asks for the push that lands the pace it
  priced, from its own velocity at the commit (`ReleaseMomentum.push_for_pace`),
  the way a human passer lightens up skating toward the receiver. Shots fire at
  full push and take the gain or loss; the scoring does not price it yet
  (Phase 2).
- **What stays the same:** the load (`WristerLoad`) still reads the aim, not
  the push's direction; the arms' rule still decides how hard the push can be.

Things to watch in the playtest:
- Shots in stride should feel heavier, shots back across your own skating
  weaker.
- Soft feeds while flying across the ice drift with you. If that feels too
  punishing, the lever is how far the correction reaches, not a fudge on drift.
- A puck pushed back through the body while skating forward is now left behind
  as a drop pass, where before it was a dead release that the body skated
  through.

## Phase 2 — the rest of the model (designed)

- **The push direction feeds the load.** The blade pushes along `u`, not `d`:
  across your own skating the push leans against your motion, so the torso's
  and the arms' shares should read `u`. One fixed iteration (solve the cap on
  `d`, re-solve on the resulting `u`) is enough, and it stays reconcile-free.
- **Drift from a change of motion.** The hands correct for the velocity they
  had a reaction time ago (~0.15 s), not the velocity at the release, so a shot
  ripped mid-cut drifts by how much the velocity changed in that window. A
  steady stride stays exact. It needs a short velocity history that reconcile
  restores alongside the other shot fields.
- **Bots price it.** The shot's pace in the compete (`self_wrister_shot_speed`
  in lanes and races) becomes the release's own pace from the carrier's
  velocity; drift is priced where it can occur.

## Phase 3 — slapshots and one-timers (designed)

The slapper's line is locked at the press, and a one-timer meets a moving puck,
so their correction is partial: a tunable share of the full correction, to be
set by playtest. The puckless one-timer already folds the feed's motion
(`_strike_moving_puck`), so the skater's own motion joins it there.

## Flagged, not in scope

- **The host clamps a one-timer's power to the slapper's ceiling plus its
  centre bonus.** Phase 3 must widen that bound the same way Phase 1 widens the
  wrister's.
- **`Puck.nudge` already composes the carrier's momentum with a stick push**
  (`SkaterController` builds it), so it is consistent with this model and
  untouched.
