# Shot field: price the shot that is fired, against the keeper it is fired at

Status: **steps 1–3 built on `claude/shot-field-integration`** (with the
resolution branch and #896's keeper fix); step 4 open. Follows from the possession floor's step 5
(`docs/possession-floor-plan.md` §7): the bots fire sharp-angle shots because the
field's live read prices them far above what the keeper concedes, so keeping the
puck never gets to compete.

## The measurement

`tests/instruments/ai/test_shot_field_live_read.gd` stages the truth table's
keeper states (`shot_odds_stager.gd`) at 18 spots (on the field's grid, between
its points, beyond it) and sets the live read (`AIShotValue.now` / `.feed`)
beside the keeper's measured open set. Baseline, bias = live − measured best aim
at the reference scatter:

| staging | on the grid | between | beyond |
|---|---|---|---|
| set | +0.105 | +0.094 | +0.048 |
| 3 m feed, one-timed / caught | −0.172 / −0.001 | −0.192 / −0.136 | +0.042 / +0.035 |
| 6 m feed, one-timed / caught | −0.079 / +0.068 | −0.034 / −0.020 | +0.082 / +0.002 |
| decoy | −0.362 | −0.050 | −0.235 |
| deke | +0.059 | +0.004 | +0.039 |
| wrap | +0.163 | +0.397 | +0.302 |

## What is wrong, and the evidence

1. **The value is the mean of each matched cell's own best aim**
   (`_weigh`: `Σ w · _odds[c]`), not the odds of any one aim. Where the matched
   cells have their holes at different aims, no shot scores what it says. The
   pick (the best aim of the cells' blended open sets) is the shot actually
   fired, and where the matched cells are alike its odds match what that aim
   does: caught feeds 0.47 / 0.39 against 0.51 / 0.36 measured at the pick, a
   decoy 0.91 against 0.96, a deke 0.22 against 0.20.
2. **The kernel mixes keepers who look alike and are not.** A set keeper matches
   deke and feed cells (up to 71 of them); a sealed keeper after a wrap matches
   cells that concede where he does not. Even the pick's odds miss there (set:
   0.11 said, 0.03 scored; the SET cell alone says 0.07, the truth). What tells
   them apart is how the play got there — "history no read carries", as
   `shot_set` already says — and the bot does see it: it carried the puck in,
   took a feed, or came round the net.
3. **Coverage.** Past x = ±8 m and 15 m out the grid clamps to its edge spot;
   decoys are sampled 3 and 6 m across, and a keeper pulled further (a
   cross-ice play) falls back to one nearest cell ("cells 1" in the
   instrument), reading 0.00 where 61 of 72 shots score.
4. **One-timers off a 3 m feed read low** (−0.17); not yet diagnosed.

## Steps

Each is measured with the instrument before and after, and
`test_shot_odds_vs_truth.gd`'s ratchets bank what improves.

1. **Price the shot that is fired.** `shot_now`'s value is the best aim of the
   matched cells' blended open sets: the pick's own odds, one definition for
   both.
2. **Read the keeper against the play the bot saw.** The query names the
   history it perceived — the shooter carried it in (SET and DEKE cells), took a
   feed (FEED cells; a decoy is a feed's limit), came round the net (WRAP) — and
   weighs only cells of that history. A perception input, not a gate.

   Steps 1 and 2 land together, in GDScript and `NativeShotOdds` at once. In
   GDScript the blend costs 13× the read it replaces (46 → 606 µs a read, the
   carrier's compete 4×: 72 aims × the 8–58 cells that hold 99% of the
   kernel's weight), so it cannot ship there alone; and the weighing changes in
   step 2 anyway, so the C++ changes once, after the instrument has settled the
   design (`test_shot_field_live_read.gd` computes both reads from the field's
   own arrays). The native kernel gains the per-aim odds and the blend; the
   parity test gates it.
   **Design readings** (the instrument's `hist` columns: the best aim of the
   blend over the matched cells of the play the bot saw; bias against the
   measured best aim, and what that aim scores):

   | staging | live | step 1 alone (blend) | steps 1+2 (history) | what its pick scores |
   |---|---|---|---|---|
   | set, on the grid | +0.105 | 0.112 against 0.069 | **+0.020** | **0.069**, the measured best (was 0.029) |
   | set, between | +0.094 | 0.149 against 0.199 | −0.082 | 0.034 |
   | set, beyond | +0.048 | 0.057 against 0.014 | +0.016 | 0.008 |
   | deke, on the grid | +0.059 | 0.218 against 0.219 | −0.025 | 0.217 |
   | deke, between | +0.004 | 0.212 against 0.316 | −0.153 | 0.269 |
   | caught feed, 3 m / 6 m on the grid | −0.001 / +0.068 | 0.466 / 0.387 | −0.086 / +0.019 | 0.514 / 0.356 |
   | decoy, on the grid | −0.362 | unchanged: coverage | −0.373 | 0.776 |
   | wrap, between | +0.397 | 0.316 against 0.156 | +0.160 | 0.000 |

   On the grid, the set keeper and the deke are fixed: the value is within
   0.025 and the pick scores what is measured. Between the grid's points every
   reading is off, in both directions, by up to 0.18: neighbouring spots' holes
   are in different places and the grid is too coarse to interpolate them
   (#853), which step 3 has to answer with density, not only width. The wrap is
   not history: its own cells disagree with it (both sides' wraps are sampled,
   and the far post's concede what the near post's do not), so it gets its own
   diagnosis before step 2 lands.
   **On the resolution branch's field** (`claude/keen-gates-o9wmar`,
   `docs/shot-field-resolution-plan.md`: goal intervals bisected to ~5 mm, the
   grid out to the boards and the blue line), the same instrument reads, bias
   against the measured best aim:

   | staging | live | steps 1+2 | what its pick scores |
   |---|---|---|---|
   | set, on the grid | +0.130 (says 0.148, measured 0.018) | **+0.026** | 0.017 (live's pick: 0.000) |
   | set, between | +0.125 | −0.042, every pair ranked right | 0.011 |
   | set, the new spots (±9–10 m wide, 17–18 m out) | +0.023 | +0.004 | 0.005 |
   | caught feed 3 m / 6 m, on the grid | +0.005 / +0.078 | −0.102 / +0.045 | 0.426 / 0.316 |
   | decoy, on the grid / the new spots | −0.360 / −0.437 | −0.373 / −0.438 | |
   | wrap | +0.21 to +0.41 | +0.17 to +0.21 | 0.000 |
   | 3 m feed, one-timed | −0.15 to −0.21 | | |

   It fixes the grid's edges and leaves the live read's own errors as they were,
   and steps 1–2 work on it as on the old field. So this plan builds on that
   branch.

   **As built.** `AIShotOdds.shot_now` returns `_blend_best` (in
   `NativeShotOdds.blend_best` where the kernel ran the query); the history is
   `AIShotOdds.History` (ANY, CARRIED, FED, WRAPPED), a mask over each cell's
   kind, threaded through `AIShotValue.now`, `score_shoot_value` and
   `AICarrierField.value_at`. A history no matching cell shares falls back to
   every cell. The carrier reads FED until the keeper has had
   `AIGoalieModel.goalie_reset_s` (his read plus a push the width of the mouth)
   since it took the puck, CARRIED after; a carry's arrival is CARRIED. Nothing
   yet tells the bot it came round the net, so WRAPPED is the instrument's until
   step 4. The other bot readers name their play too: the counter-rush threat
   and the defence's `threat_of_carrier` read CARRIED, the dump search's support
   shots FED. History-blind, a deep keeper matches the in-tight range decoys (a
   keeper set on a carrier 2 m out, then beaten from the spot): a slot shot
   against our squared keeper read 0.98 where CARRIED reads 0.30 and the SET
   cell 0.32.

   **Readings on the regenerated field** (#896's keeper, the resolution grid,
   decoys to 12 m across; `test_shot_field_live_read.gd`, bias against the
   measured best aim; on the grid / between / beyond):

   | staging | bias | what its pick scores, on the grid |
   |---|---|---|
   | set | +0.027 / −0.048 / +0.003 | 0.017, the measured best |
   | caught feed 3 m | −0.032 / **−0.220** / −0.003 | 0.482 |
   | caught feed 6 m | +0.015 / −0.037 / −0.037 | 0.276 |
   | one-timer 3 m | **−0.153 / −0.203** / +0.013 | |
   | one-timer 6 m | −0.091 / −0.003 / +0.033 | |
   | decoy | −0.065 / −0.055 / −0.141 | 0.935 |
   | deke | −0.027 / **−0.146** / −0.005 | 0.193 |
   | wrap | **+0.214 / +0.170 / +0.205** | 0.000 |

   The truth table: mean error 0.104 (was 0.112), concordance 0.943 (0.919), the
   pick keeps 0.757 of the best odds (0.744). Cost, native kernel: a shot-now
   read 4.6 → 8.1 µs (the blend over 72 aims); host AI per game-second 1.06–1.11×
   in every scenario but the 5v5 O-zone cycle, 1.30×, where shot reads are
   densest (`benchmarks/test_ai_perf_benchmark.gd`, two runs each).
3. **Far decoys, and density.** *Far decoys done (above); density open.* The resolution branch measures the zone to the
   boards; what it leaves is the keeper pulled further than 6 m across (decoys
   are still sampled at ±3 and ±6 m: a cross-ice play reads 0.00 where most shots
   score) and the interpolation between spots. Decoys out to 12 m across, then a
   regeneration (`generate-shot-field.sh`, about 70 minutes on four processes).
4. **The wrap, and one-timers.** Diagnose the wrap first (its own cells
   disagree: which post each sealed keeper is on against the release's side),
   then the 3 m one-timer's underpricing.

Done when every staging's bias is within ±0.05 on and between the grid, the
pick scores what the value says, and `test_ozone_possession.gd` no longer shows
the carrier firing from sharp angles a second after he gets the puck low.

Out of scope: rebounds and screens (the field measures first contact, #785),
and the keeper himself (`docs/AUDIT_2026-07_GOALIE_REALISM.md`).
