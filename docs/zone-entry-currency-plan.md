# Zone Entry Currency — Design Record

Status: **implemented** (both 3v3 and 5v5; the code is shared).

## 1. The problem

Playtest: bots take the zone, then drop the puck back to a trailer. The pass
back out of the zone was a valve bug (fixed separately: `_zone_taken` keys the
pass valve on the puck). But the bots still *wanted* the drop. In the repro
scene (carrier at speed up the left wall a few metres short of the line, a
defender gapping him, the trailer 5 m behind in the middle) the drop out-scored
carrying in half the cells of the entry grid.

The carrier values ice on two scales, keyed on his own body:

- **In the zone:** xG through the value seam (`AIShotValue`).
- **Outside:** `position_potential` × realization, a 0–1 map smooth across the
  whole rink, with no step at the blue line.

Because of offsides, an outside player only ever prices an in-zone spot when an
option **crosses the line**: his own carry, a receiver's drive after a pass, or
a pass whose catch lands just inside (a teammate already in the zone is offside
and is not a receiver). Those spots were priced on the potential map too, so
entering was worth what any other metre is worth, and the trailer's drive into
the zone was priced on the same optimistic map as the carrier's.

## 2. The design

Keep the two-zone model. Change only how an outside player prices an in-zone
spot:

1. **An in-zone spot is priced by the goal-based scale**, converted into
   potential's unit (`AIRoleCarrier._entry_value`):

   ```
   entry_value(xg) = min(xg / XG_SLOT_REF, 1.0)
   ```

   `XG_SLOT_REF` (`AIActionScoring`, computed at static init) is the xG of the
   situation `position_potential` reads as 1.0: the slot ring, head-on, nothing
   in the way, a set keeper. It measures **0.174** on the live model and moves
   if the shot model moves. The cap is potential's own ceiling, and keeps the
   [0, 1] bound the carry candidates' ceiling prunes rely on.
   `test_xg_slot_ref_is_the_xg_of_potentials_full_value` holds the anchor.

2. **An in-zone carry candidate gets the entry continuation.** Converted alone,
   a spot just inside the line is worth only its shot, about a quarter of the
   potential just outside it, so entering would look like a loss. A carrier who
   gets there with the puck is worth what he does next: the drive-in from the
   candidate, priced in the in-zone regime and starting when he arrives
   (`_receiver_drive_in_value` with `from_pos` and `start_s`), converted the same
   way. It runs in the beam's first pass so in-zone candidates are ranked on it.

Everything else outside the zone (breakout and regroup passes, stand-still,
dumps, the giveaway bars, turnover costs) stays in potential currency and never
sees the conversion.

The carrier's continuation and a trailer's drive are now the same kind of read
(a carry into the zone, valued by the goal-based scale at its end), so the drop
wins only when the trailer's entry genuinely beats the carrier's.

## 3. What was tried and rejected

- **Pricing in-zone spots in xG without conversion:** in-zone values (~0.02–0.14)
  lose to every out-of-zone value (~0.4); bots stop entering.
- **Converting the whole out-of-zone map to xG** (`position_potential` ×
  `XG_SLOT_REF` everywhere, costs and bars included): a uniform rescale leaves
  the entry decision unchanged, and the giveaway bars then bind on breakout
  passes (an open outlet from our own zone is worth 0.01–0.03 xG), which needed
  its own patch. Unnecessary once it was clear the scales only meet at the entry.
- **max(potential, converted xG) for in-zone spots:** the potential map wins
  everywhere, so the goal-based scale never actually applies.

## 4. Measured

Entry grid (carrier at −8 on the left wall moving 7 m/s, trailer 5 m behind at
x = 2; carrier body 1–4.5 m short of the line; defender gap 2.5–8 m):

| | drop pass wins |
|---|---|
| before | 6 of 12 cells |
| after | 0 of 12 cells |

A smothered carrier (a checker on his hip, another sealing the line) still drops
it to the open trailer in all 4 cells tried. Both directions are pinned in
`test_role_carrier.gd`.

## 5. Known gap (not part of this change)

In the zone, the carrier's turnover costs come from `threat_surface_shoot`
(raw `position_potential` toward our net plus hole geometry) while his gains
are xG, so in-zone turnovers are overpriced roughly tenfold (a strip at the top
of the zone costs `loss_prob × ~0.24` against gains of 0.02–0.15). That biases
in-zone play toward the safe option. It is unrelated to the entry and is its own
fix.
