# Bot net-front offence — spacing, rebounds, screens, tips

Status: **plan, nothing built.** The CLAUDE.md workflow applies: this doc is
the plan, and deviations get discussed first. It is the decision-layer half of
#785 (price net presence, crash the net) and the rebound half of #924, and it
waits on #736 (tips) for its last step. The mechanics it leans on are already
built: the press, the dig-in and the screen press (`docs/net-front-battles-plan.md`),
the goalie's screened read (`GoalieScreenRules`), the deliberate tip
(`PuckCollisionRules.tip_turn`), and the keeper steering his rebounds
(`test_keeper_steers_his_rebounds.gd`). What is missing is any reason for a
bot to go and use them.

## Decisions banked (with the user)

- **Order: spacing, then measure, then rebounds, screens, tips.** Spacing is
  the cheapest step and a model fix on its own. The three net-front items share
  one missing input, which is what happens at the net after the first shot, so
  they are measured together before any of them changes behaviour.
- **Measure, then model.** Rebounds, screens and tips are each priced from a
  table measured against the live keeper, the way the shot field is
  (`docs/shot-currency-plan.md`), never from a curve shaped to feel right. The
  tip removal (`0102aef`) is the warning: `tip_ev` read the redirect off
  one-timer feed cells, priced tips at 0.07–0.41 where #736 measured roughly 0
  in 8, and the bad price made up half the 5v5 shots.
- **Both modes, 5v5 first.** Each step is measured and tuned on the 5v5 set
  O-zone first, then 3v3 is re-measured. The roles are shared (FINISHER and
  NET_FRONT are one module), so most changes reach 3v3 on their own.
- **Coaching gates stay coaching gates.** Where a behaviour is a tactical rule,
  for example "the second attacker on a rush drives the net" (`finisher.gd`'s
  rush depth gate), it stays one. What this plan adds is the value those rules
  chase, priced so that the rule can eventually be retired.
- **The rebound field has its own generator,** sharing `shot_odds_stager.gd`
  with the shot field but never regenerated with it.
- **The screen's model is chosen by 2b's measurement** (§2b: a separate table
  or a shot-field cell kind).
- **A second man on an O-zone loose puck is in scope** (§3d), together with
  #604's attacking-zone chase decline.

---

## What the bots do today

### 1. Rebounds

- **The scoring counts first contact only.** The shot field measures whether
  the first contact with the keeper is a goal (#785). The carrier's compete
  adds a flat rebound credit to every shot that reaches the net
  (`AIActionScoring.with_rebound`:
  `p + (1 − p) · REBOUND_RECOVER_SHARE · FLOOR_THEIR_GOAL_LINE`). The credit is
  the same with two of ours at the crease as with none, so a shot taken for the
  rebound is never worth more than any other.
- **Nobody positions for one.** Once the puck is released, FINISHER and
  NET_FRONT hold where they are (`_positioning_decision` returns `self_pos` with
  no teammate carrying), except for the tip read while a shot is in flight.
  HIGH_SLOT and SUPPORT re-centre on the puck as if it were a passer.
- **The chase starts at the save, not at the release.** The election walks
  `AITrajectory.predict_puck`, which has no net and no keeper in it. While a
  shot is in flight its predicted path runs through the cage to the end boards,
  so the race only starts once the keeper has touched the puck, after the
  carrier-reaction delay, and with bodies nobody set up for it.
- **One man goes.** The election names one chaser a team, and the rest hold
  their stations (#924 §1, #604).

### 2. Tips

The finisher still tips a shot coming at him (`_try_reactive_decision`), and
still scores his stations by `max(feed, tip_ev)`. Since `0102aef` the carrier
never shoots *for* a tip. The finisher's station pricing still reads the
unmeasured `tip_ev`, so the tip station is valued by the same model that was
retired from the carrier.

### 3. Screens

The keeper's read is screened (`GoalieScreenRules.screen_occlusion_delay`), a
screener digs in (`skater_agent_press.gd:_dig_in`), and a defender presses a
screener off the sightline (`_press_the_screen`). Nothing values standing
there:

- The shot value lists screens as not modelled, and the shot field has no
  screened cells.
- NET_FRONT's tip/screen station is valued only through `tip_ev`.

So no bot goes to the net to screen, and the battle the press was built for
does not start on its own.

### 4. Spacing

- **5v5 OZONE has three bodies high and central.** It is CARRIER, two points
  on the blue line, NET_FRONT at the crease, and HIGH_SLOT
  (`role_slots_5v5.gd:_specs_for_state`).
- **HIGH_SLOT is scored on the lanes, not the chance.**
  `high_slot.gd:decide` samples a band 8–11 m out and ±3 m across. It scores
  each spot by `lane_clear(feed) × lane_clear(shot)`, the odds the puck gets
  through, never by what the shot is worth once it does. A spot further from a
  defence that protects the slot clears its lanes more often, and nothing pays
  for being closer, so the argmax sits at the top of the band. The band's ±3 m
  also keeps him in the middle, where the defence is.
- **3v3 SUPPORT parks high.** Its O-zone station is 3 m inside the blue line,
  shaded to the carrier's side (`support.gd:_generate_candidates`), with a
  weak-flank candidate at the top of the circles. That is partly doctrine (the
  first man back) and is measured before anything changes.

---

## Step 1 — Spacing (5v5 HIGH_SLOT, then 3v3)

### Model fix

Score each HIGH_SLOT candidate in the finisher's currency:
`AIActionScoring.score_pass_value(carrier, c, …, one_timer = true)`. That is
the chance he would have off the feed, which already contains both lanes and
the shot's worth from there against the defence and the keeper. The lane
product was a stand-in for this.

- **Widen the candidate set,** and let the value pick: depths ~6–11 m (the
  bumper up to the circle tops) and laterally out to the dots (±6.7 m),
  weak-side shaded. The weak-side flank is where a slot-protecting defence
  leaves ice open.
- **Keep the bounds that are doctrine:**
  - *Above the puck.* The `stay_above` filter while the puck is no higher than
    the band.
  - *First man back.* `AILastManDiscipline.offensive_station_target`, which is
    what legitimately limits how low he may go.
  - *Pinch fill.* `rotate_up_to_point`.
- **3v3 SUPPORT** already scores by `score_pass_value − counter_rush_cost`.
  Re-measure it after the 5v5 change, and only touch it if it still reads
  clumped at the line.

### If the direct fix does not spread them

One defender standing between two attackers covers both of them, and a
per-candidate score blind to teammates cannot see that. The anti-crowd radius
is only a hard filter at 1–2 m. The grounded fix is to price a station at what
it ADDS: the defence's best response to the carrier's options with me there,
against the same options without me (`carrier_best_option`'s machinery, read
from the attack's side). It is more expensive, so it is built only if the
measurement asks for it.

### Measurement and acceptance

- **`test_ozone_spacing.gd` (slow).** Add a per-role log: HIGH_SLOT's depth and
  lateral distribution, and each attacker's distance to his nearest defender
  (spread). Keep the four-high ceiling (≤ 5%).
- **`test_ozone_possession_5v5.gd` (instrument).** Track shots, slot shots, the
  priced value of the shots taken, and turnovers that become counters, so a
  lower F3 is not a weaker first man back.
- **Acceptance.** HIGH_SLOT sits lower and wider. Spread rises, shot value and
  slot shots rise, and four-high and counter-rush turnovers do not rise.
- **3v3.** `test_ozone_possession.gd`, same reads.

**Baseline (today, `test_ozone_spacing.gd`).** Every fixture passes with two
high and 2.6–3.0 low a tick, and 0% four-high. So the shape count does not see
the complaint. Its "low" band reaches 10.7 m out, and a HIGH_SLOT at the top
of the circles counts as low. The per-role depth, lateral and spread log above
is therefore the first thing step 1 builds, and its baseline is recorded here
before the role changes.

---

## Step 2 — Measure the net front (instruments only, no behaviour change)

All three are instruments against the live keeper, each writing a small
generated table with a staleness test like `test_shot_field_is_current.gd`.
Each table is regenerated whenever the goalie changes, as the shot field is.

### 2a. The rebound field

From a coarse release grid (a subset of the shot field's spots, e.g. x ∈
{−8, −4, 0, 4, 8} × out ∈ {3.5, 6, 9.5, 15, 19.5}), each loft, and a SET
keeper, fire charged shots and record what the save does:

- whether it was a goal, covered (whistle), or deflected out of play;
- for a live rebound, the puck's position and velocity at a few times after
  contact (e.g. 0.25 / 0.5 / 1.0 s), and the keeper's state at each: position,
  stance, and facing.

The keeper's state is what lets the second shot be priced through the
existing seam. The shot field is kernel-weighted over the keeper's stance and
offset, so a keeper caught down and across reads as open as he really is.

### 2b. Screen uplift

The shot field's SET cells, repeated with a screener body on the sightline at
net-front stations (1.5–3.5 m out, 0 / 0.5 / 1.0 m off the release→keeper
line). This measures the conversion and the keeper's read delay against the
unscreened cell. A body that does not hide the release is measured too, so the
table knows where a screen stops working.

The same screened cells are also measured with the keeper caught off the
shot (DECOY-style), not only SET. Their result decides how a screen is
modelled:

- **A separate uplift table** if screened ÷ unscreened conversion holds
  roughly constant across keeper states. The screen then scales the clean
  odds, and that is cheap to read.
- **A SCREEN cell kind in the shot field,** read through the existing kernel,
  if the ratio moves with where the keeper stands. A single factor would
  misprice exactly the screens that matter.

The 2b instrument prints that comparison, and the choice is made with the user
on its numbers.

### 2c. Tips through a live blade (#736's next step)

Point and circle-top shots through a live skater's blade holding the deflect,
at tip spots in front of the net, tipped up and down. This records the
outgoing direction and height spread, and the conversion against the live
keeper. It answers both of #736's questions: is the deflection physics right,
and is the keeper too good against it. If the physics is wrong, that is a
gameplay fix, raised separately before step 5.

### 2d. The O-zone instrument goes past the first shot

`test_ozone_possession_5v5.gd` ends a possession at its first shot. Let it run
on through the save and record who touches the rebound first, when, and from
where. That is the baseline for step 3.

---

## Step 3 — Rebounds

### 3a. A rebound credit priced by who gets there

Replace the flat `REBOUND_RECOVER_SHARE` with the measured field. For a shot
from a spot:

```
rebound(spot) = Σ over the measured live rebounds r of w_r ·
        [ race_r · second_chance(r) − (1 − race_r) · turnover(r) ]
    + cover share · faceoff value in their zone
```

- **`race_r`** is `arrival_race` to the rebound's spot at its time, our soonest
  body against theirs, each with the momentum-honest arrival clock. This is
  where net presence enters: with nobody of ours near the crease, the race is
  theirs.
- **`second_chance(r)`** is `score_shoot_value` from the rebound's spot,
  against the keeper as the field recorded him there (stance, offset, facing).
- **`turnover(r)`** is `AICarrierField.turnover_cost` at that spot, in the same
  currency.

The carrier's compete reads this through the existing `rebound` flag on
`score_shoot_value`, so "shoot for a rebound" emerges with no new intent: with
men at the net the shot is worth more, and with none it is worth less than
today's flat credit.

**Cost.** `score_shoot_value` sits on the carry search's hot path. Per
dispatch, the rebound read is a lookup on the release spot plus a race per
landing cluster against bodies whose arrival times are computed once. It is
held to the benchmarks (per-tick p95/max before and after).

### 3b. Off the puck: stand where the rebound goes

- **With a shot in flight** (our release, puck heading at the net), FINISHER,
  NET_FRONT and HIGH_SLOT argmax over rebound stations: our odds of winning
  that rebound × its second chance, against the defence.
- **With a shot look leading** (the carrier's shoot-now read on top), the
  net-front man's station argmax gains the rebound term beside the feed and the
  tip, so he goes to the net before the release.

The rush depth gate (`finisher.gd`) says that "nothing in the scoring prices
the net's rebounds and body presence". Once this term does, re-measure whether
the gate still binds, and retire it if it does not.

### 3c. The chase races the rebound from the release

While our shot is in flight, the election races the measured rebound
distribution for that release instead of a path through the cage, so bodies
start moving at the release.

### 3d. A second man on an O-zone loose puck (#924, #604)

Today one chaser goes and everyone else holds. In their zone that loses every
50/50 that squirts out of the first contest. The second man plays the puck's
NEXT spot, not the puck:

- **Where.** The spot where the first contest sends it: where their soonest
  collector would make his first play, by the forecheck's own clock
  (`AIForecheckRead.read_loose`), or where a rebound comes off the keeper, from
  3a's distribution.
- **Who.** The teammate other than the elected chaser whose arrival there
  (`AIArrival.time_to_arrive`) beats their soonest body by the most. He leaves
  his station only if that race is ours (`arrival_race` above the contest
  band) and if the shot we would get from winning it is worth more than the
  station he leaves. Last-man discipline still binds him
  (`offensive_station_target`), so a point never becomes the second man.
- **#604's decline.** The chase decline that fires by default deep in the
  attacking zone is reworked in this step. In their zone a lost race is
  declined only when the second man's read says nobody of ours can contest
  the next spot either.

The election stays one chaser a team. The second man is a role decision read
off the election's result, so the two never send the same body.

Tests: a unit test that the second man goes when his race is won and holds
when it is lost or when he is the last layer; a slow-tier 5v5 cycle with a
rebound off a point shot, counting our share of first touches on the squirt.

### Tests

- A unit test that the rebound credit rises with our bodies at the net and
  falls with theirs, and equals first contact behind the goal line.
- A station test for FINISHER and NET_FRONT with a shot in flight.
- The chase election's race on a shot in flight.
- The 2d instrument: our share of first touches on rebounds, before and after.

---

## Step 4 — Screens

- **The shot value reads the screen** through the measured uplift (2b): the
  bodies between the release and the keeper, from either team, at the
  replicated positions. Both sides use one seam, so the defence's threat reads
  also see a screened shooter as more dangerous, and a defender's own body
  screening his keeper is already the shot block's concern.
- **NET_FRONT's station argmax gains a screen term:** the carrier's shot with
  me on the sightline, against without me. That puts a forward on the
  sightline. Battles follow from what exists: the screener digs in, and a
  defender presses him.
- **Tests:** a screen-uplift test against the 2b table; a NET_FRONT station
  test that he takes the sightline when the carrier has a shot; and a slow-tier
  scenario counting net-front contact ticks in a 5v5 cycle, which is the
  aggregate the user asked for.

---

## Step 5 — Tips

- **Rebuild `tip_ev` from the measured tip table (2c).** Hold it against the
  instrument's cells, like `test_shot_odds_vs_truth.gd`.
- **Restore the carrier's shoot-for-tip** (the `_pick_fire_phase` block
  `0102aef` removed), priced by the new `tip_ev`, as `max` with the direct
  shot.
- **Acceptance.** The 5v5 O-zone sweep must not regress to tips from the walls
  making up half the shots. Tips should come from spots where the table says
  they score.
- **Order.** If 2c shows a tip on the shot line still scores ~0, the carrier's
  half stays out, and only the finisher's station pricing moves to the measured
  value.

---

## 3v3

After each 5v5 step, re-measure 3v3 (`test_ozone_possession.gd`).

- FINISHER is shared with NET_FRONT, so steps 3–5 reach it directly.
- SUPPORT gets the rebound station term in 3b if the 2d-style measurement shows
  the 3v3 high man never touches a rebound.

---

## Open questions

1. **The screen's model** is decided on 2b's numbers (§2b).
2. **Per-tier goalie fields (#786)** are out of scope. Every table here is
   measured against the Hard keeper, as the shot field is.

## Where it lives

| piece | file |
|---|---|
| HIGH_SLOT station | `Scripts/domain/ai/role_behaviors/high_slot.gd` |
| 3v3 SUPPORT station | `Scripts/domain/ai/role_behaviors/support.gd` |
| FINISHER / NET_FRONT stations, tip read | `Scripts/domain/ai/role_behaviors/finisher.gd` |
| rebound credit, `tip_ev` | `Scripts/domain/ai/action_scoring.gd` |
| shot value seam | `Scripts/domain/ai/shot_value.gd`, `shot_odds.gd` |
| chase election | `Scripts/domain/ai/loose_puck_chase.gd` |
| carrier shot pick | `Scripts/domain/ai/role_behaviors/carrier.gd:_pick_fire_phase` |
| new generated tables | `Scripts/domain/ai/generated/` |
| instruments | `tests/instruments/ai/` |
