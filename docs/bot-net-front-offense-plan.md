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
- **The shape the bots play is a cycle-and-retrieve,** not the NHL's 2-3 as
  such. The bots are not bad in the zone; they get gummed up. The step-1
  additions all stay (the value-priced HIGH_SLOT, the general rotation, the
  weak D's activation, the shared cover), since they cost nothing measurable
  and give the cycle its moving parts. What comes next is why the carrier
  does not use them.

---

## How the O-zone is played (research)

A web survey of coaching and analytics sources, condensed. Nothing could be
fetched from this environment, so the numbers come from search summaries of
the sources listed. They are real-hockey numbers, so they are hypotheses for
what our own measurements should find and targets for the shape; no evaluator
reads them as constants.

- **The shape has moved to a "2-3".** Two forwards work low (cutbacks, slip
  passes). The other three, both D and F3, are a moving high line, and F3
  skates downhill into the slot when space opens, or arrives at the far post.
  It replaced the 3-2 spread and the box+1 because standard D-zone coverage is
  outnumbered up high. (Jack Han, jhanhky.substack.com: "The hidden benefit of
  attacking downhill", "The DZC dilemma".)
- **F3 is not a fixed spot between the dots.** He is the low-to-high outlet,
  the safety valve, and a moving third point who attacks the seam when the
  defence collapses low.
- **Width beats a collapsed box.** Shots with no lateral puck movement score
  about 3%. A pass across the "royal road" through the slot first lifts that to
  roughly 15–33% (Valiquette; Stimson via NHL.com). Defenders who collapse onto
  the low man leave the weak-side D or forward open for the cross-ice
  one-timer.
- **Someone is always weak-side low.** The backdoor spot is 1–3 m off the goal
  line and 1.5–3 m outside the far post. It is filled by the net-front man
  sliding across, the weak-side forward, or the weak D sneaking down the flank.
- **Rebounds.** Shots with a rebound are about 5% of shots and over 15% of
  goals. A second shot within 2–3 s scores at about 4× the rate. Rebounds go in
  about 23% of the time at 5v5. They come out far-post and into the slot when
  the keeper does not control them. A low far-pad shot is "shooting to pass"
  for a teammate crashing. The players must arrive within about 2 s of the
  shot.
- **Screens and tips.** A clear-sight shot scores about 3%, a screened one
  about 14% and a deflection about 15% (Valiquette). Tips score about 17–19%,
  against 9% for wrist shots. A single static screen is the easiest one for a
  goalie, so the screener moves with the shooter's sightline. Defenders box
  out early, so position is won before the shot. The tipper stands just off
  the shot line, 1.5–4.5 m out, facing the shooter, blade on the ice.
- **Point shots set up the tip, screen or rebound.** On its own a point shot
  is about 3%. The D walks the line to open a lane, uses a wrister or snap
  shot over a slapshot, and goes D-to-D or back low when no lane opens.
- **Only one D below the circle tops at a time,** with a forward covering his
  point.
- **3v3.** Two high and one low. When the puck goes high, the next-highest
  player becomes support or a shot option. Players arrive late from above the
  hash marks with speed. Teams regroup, even out of the zone, rather than
  force a play. Against a man-to-man defence, crossing routes and curl-and-
  delays make 2-on-1s.
- **Shot danger by location.** The low slot is about 2× the high slot, and
  perimeter shots are about 2–4%. A royal-road pass, a rebound inside 3 s, a
  screen or a tip each multiply the danger several times over.

What this means for the plan:

- **Step 1's model fix is the right direction.** Pricing F3's spot at the
  one-timer's worth lets the shot field's feed cells pay for cross-seam and
  weak-side spots, which is the royal road.
- **The shape question is a doctrine decision,** made with the user below. It
  is whether the 5v5 O-zone stays 3 low / 2 high (`docs/5v5-ai-plan.md` §2,
  held by `test_ozone_spacing.gd`) or becomes the 2-3 with F3 in the high line.
- **The net-front steps get targets.** Rebound stations are reached within 2 s
  of the release (3b). The screener moves with the shooter's sightline rather
  than standing still (step 4). The point shot is worth taking mostly for what
  happens at the net, which 3a's credit prices.

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
is therefore the first thing step 1 builds. Its baseline, before the role
changes (Hard bots, 6 s a fixture; weak x is positive away from the puck's
side; "nearest D" is the attacker's nearest defender):

| fixture | HIGH_SLOT depth / weak x / nearest D | NET_FRONT depth / weak x | off-puck nearest D |
|---|---|---|---|
| D holds it up top | 10.0 / −1.8 / 2.2 | 3.2 / −0.9 | 3.07 |
| D carries at the point | 7.6 / +0.9 / 2.2 | 3.6 / −1.2 | 4.52 |
| F carries low | 9.4 / −2.2 / 2.8 | 5.1 / −0.7 | 4.37 |
| C carries high slot | 8.1 / −2.2 / 3.5 | — | 4.43 |

What the table shows:

- **HIGH_SLOT has a defender closest of any off-puck attacker** (2.2–3.5 m),
  and he stands at the top of the circles, shaded to the strong side.
- **Nobody holds the weak side low.** NET_FRONT stays central and
  strong-shaded, and FINISHER only appears while a pass is in flight.
- **The weak point drifts to the middle** (+0.4 m) while a forward carries
  low.

All three are the "slot-protecting defence never has to spread" picture the
user described.

### Status: first pass built, no measurable change in outcomes

Decided with the user: value decides the shape (no fixed 3-2 or 2-3), and the
rotation is general, not only the pinch's.

**Built.**

- HIGH_SLOT's grid is priced at the one-timer (above), with no above-the-puck
  filter.
- **Either vacated point is filled.** `rotate_up_to_point` reads both, and
  `point_vacated` counts a D as gone only while he is deeper than his stands
  and not skating back to his point ahead of the filler. This fixes a
  clumping path: on a strong-side flip, the sunk strong D was relabelled the
  "vacated" weak point, and F3 ran up to the line beside him.
- **The partner** holds the middle of the line whichever D is off it.
- **The weak D's flank activation** (`_flank_activation`), covered as the
  pinch is.
- **A spot shares its value with a teammate inside one defender's span**
  (`AIStationSearch.shared_cover`, 2 × `BLADE_REACH_M`). This applies to
  HIGH_SLOT, the flank and the finisher's stations.

**Measured** (`test_ozone_possession_5v5.gd` with `MITTS_OZ_JITTER=11`: 576
Hard possessions a configuration, per possession, ± one standard error):

| | shot | slot shot | picked | stripped | set read of its shot |
|---|---|---|---|---|---|
| before | 0.312 ± 0.019 | 0.102 ± 0.013 | 0.326 | 0.318 | 0.040 ± 0.006 |
| all of it | 0.306 | 0.109 | 0.323 | 0.339 | 0.036 ± 0.005 |
| without the HIGH_SLOT pricing | 0.304 | 0.094 | 0.299 | 0.335 | 0.028 ± 0.004 |
| without the flank activation | 0.307 | 0.102 | 0.325 | 0.337 | 0.030 ± 0.004 |
| rotation only (neither of those two) | 0.321 | 0.116 | 0.316 | 0.319 | 0.041 ± 0.006 |
| without the shared cover | 0.311 | 0.104 | 0.314 | 0.333 | 0.032 ± 0.005 |

**What it shows.**

- **Every configuration is within noise of the others.** The 48-run sweep's
  11 shots against 18 was chaos: one perturbation re-deals every possession.
  Only a difference of about 0.05 in the shot rate shows at this size.
- **The attack's own spacing** (off-puck nearest teammate,
  `test_ozone_spacing.gd`) went from 5.5 / 7.4 / 7.1 / 7.2 m to
  5.3 / 5.0 / 7.4 / 6.4 m with all of it. The forwards settle just outside the
  one-defender span, where the old fixed staging spread them further.

So moving the off-puck bodies has not changed what the carrier makes of the
possession. Whether that is because he does not use the new options (about
one pass a possession either way) is the next thing to read.

### Why the carrier does not use the ice (the trace)

`MITTS_OZ_TRACE=1` logs the carrier's compete every 0.1 s, and each receiver's
feed as the pass search priced it (`AICarrierPassTrace`). Over a J=11 sweep
(about 9,900 samples, step-1 code):

| receiver | feed worth > 0 | lane closed | led out of the zone | median spot worth |
|---|---|---|---|---|
| NET_FRONT | 12% | 82% | 0% | 0.165 |
| HIGH_SLOT | 10% | 81% | 4% | 0.050 |
| POINT_STRONG | 8% | 42% | 48% | 0 |
| POINT_WEAK | 7% | 46% | 46% | 0 |

- **The carry leads the compete on two samples in three.** Any pass is worth
  anything on under half of them, and the carry still out-values it on two in
  three of those (median margin 0.03).
- **The points were never receivers at their own stand.** The pass search
  keeps a feed's lead `OZ_RECEIVE_LINE_BUFFER_M` (2.1 m) inside the line; the
  points stood `POINT_INSET_M` (2.0 m) inside it. So the low-to-high was off
  whenever a D held his stand, and the pass-option cache never counted the
  points. `POINT_INSET_M` is now 2.4 m (the buffer plus a blade), and
  `test_role_defenseman.gd` holds the order. After it, the points' worth is
  0.04 and POINT_WEAK's out-of-zone gate is 27%. POINT_STRONG's stays at 41%:
  a D skating back up from his sink is led out of the zone.
- **The slot's lanes are shut four ticks in five.** That is the sturdy slot
  defence the user described, and it is what the cycle has to move.

Outcomes with the inset fix (576 possessions): shot 0.293 ± 0.019, slot shot
0.102 ± 0.013, picked 0.366 ± 0.020, stripped 0.306, set read 0.036 ± 0.005.
That is within noise of the code before step 1, with one pass more in every
ten possessions.

**Also seen:** the finisher's rush depth gate (`stage_dist`, 5 m in a set
cycle) leaves its weak-dot and high-slot stations unreachable, so NET_FRONT
never rotates up. It is left alone until step 4 prices the screen that would
keep the net front manned.

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

**Built** (`test_generate_rebound_field.gd` via
`.claude/hooks/generate-rebound-field.sh`; data in
`Scripts/domain/ai/generated/rebound_field_data.gd`, held current by
`test_rebound_field_is_current.gd`). It measures 25 spots (x ±8, ±4, 0 at 3.5,
6, 9.5, 15 and 19.5 m out) × 3 lofts × 8 aims, a charged wrister at a keeper
set square on the carrier. The harness is a subclass
(`rebound_shot_harness.gd`), so the shot field's fingerprint is untouched.

| shot from | goal | missed | covered | live rebound | in front of the net at 0.5 s | keeper down at 0.5 s / 1.0 s |
|---|---|---|---|---|---|---|
| 3.5 m | 1% | 0% | 21% | 78% | 89% | 85% / 15% |
| 6 m | 1% | 3% | 24% | 72% | 80% | 87% / 10% |
| 9.5 m | 0% | 17% | 17% | 66% | 80% | 90% / 1% |
| 15 m | 0% | 32% | 16% | 53% | 77% | 97% / 2% |
| 19.5 m | 0% | 33% | 0% | 67% | 100% | 100% / 0% |

"In front of the net" is the crease, low slot or slot, within 10 m and 4.5 m
across. Three live rebounds in four sit on the ice, slow enough for a stick,
in front of the net within 1.5 s: half of all shots. For about half a second
the keeper is down on nearly every one, and by a second he is up. So the
rebound is worth its race, the window is the first second, and the
second chance is against a keeper on his knees. The flat
`REBOUND_RECOVER_SHARE` credit sees none of it.

Not measured: a keeper caught off the shot (the field's DECOY and FEED
keepers), tips and screens (2b, 2c), and a missed shot's path round the
boards (a "W" row stops at the goal line).

**Who wins the rebound today (2d).** `test_ozone_possession_5v5.gd` with
`MITTS_OZ_REBOUND=1` plays on past the first shot, drawing the save from the
field (`AIReboundField`, the nearest spot's shots by a seed per run). On a J=11
sweep (576 possessions, 169 shots, step-1 code):

- **They touch a live rebound first 74% ± 4% of the time, and we touch it
  first 26% ± 4%.** Their median first touch is 0.36 s after the save, ours
  0.83 s.
- **We get a second shot within 3 s on 11% ± 3% of live rebounds** (0.09 a
  shot), a median 1.1 s after the save, when the keeper is still down 20% of
  the time. We arrive after the half-second he is on his knees.

28 of the shots were touched in flight (a block or a tip) and draw no save.

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

**Status: measured, SET keeper only** (`test_generate_screen_field.gd` →
`generated/screen_field_data.gd`, 20 spots × 21 cells × 24 shots). The share
scored, unscreened → the best on-line station:

| out \ across | −8 | −4 | 0 | +4 | +8 |
|---|---|---|---|---|---|
| 6 m | 0 → 0.08 | 0 → 0.04 | 0.04 → 0.17 | 0 → 0.04 | 0 → 0.04 |
| 9.5 m | 0 → 0.04 | 0 → 0.21 | 0 → 0.25 | 0 → 0.25 | 0 → 0.08 |
| 15 m | 0 → 0.04 | 0 → 0.08 | 0 → 0.21 | 0 → 0.08 | 0 → 0.04 |
| 19.5 m | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |

- **Only a body on the line screens.** At 0.4 m off it every spot but the
  slot's top measured 0. The keeper looks round a body that does not cover the
  release, which is the point of his peek.
- **The best stations are 2.5–5 m out**, not on the crease.
- **From the points a screen buys nothing.** A charged wrister from 19.5 m
  scores 0 with or without a body in front. That is a fact about the goalie,
  not the bots, and is raised with the user separately.
- **The DECOY half was not measured.** The SET keeper concedes ~0, so the
  ratio the two options were to be chosen by has no denominator. The screen is
  modelled as a share of his saves turned into goals ((screened − clean) ÷
  (1 − clean)), read through his own sightline test. That form is nothing
  against a net already open, and it is cheap. Whether a screen on a beaten
  keeper is worth more than this share says is unmeasured.

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

**Status: built and measured, not yet switched on.**

- **The field measures the second chance itself.** Each live rebound is frozen
  at its contest sample (the first within 1.5 s where a stick can play it in
  front of the net) and 0.5 s later, and 12 second shots are fired from the
  puck there at the keeper as he then was, restored before each
  (`rebound_shot_harness.gd`, main's `keeper_state_cloner.gd`). They score
  9.6% at the contest (mostly a puck in his pads) and 29% half a second later
  (the puck in the slot, him still getting up). The NHL's rebound shots score
  about 23%. Extrapolating the shot field instead (`AIShotValue.now` against a
  "down" keeper) read 0.4–0.6, and a credit built on it reached 0.37 with two
  defenders at the net.
- **`AIReboundValue.credit`** prices it. Each rebound is touched first by one
  side, at its contest sample or its late one, on the momentum-honest clock
  and never before the puck. Ours, it is worth the second shot measured where
  we touched it, or the late one when we touched it first and nobody of
  theirs can be on it before then. Typical values: 0.03–0.07 for a shot from
  4 m with its shooter following it, 0.14 from 9.5 m with a man at the crease
  and one defender, 0.03 with two, and ~0 from the point unless we win the
  crease.
- **Switched on alone, it made the offence worse** (576 possessions, J=11, the
  rebound sweep):

  | | shots | slot shots | first touch ours | xG / possession (first + second) |
  |---|---|---|---|---|
  | flat credit | 0.29 | 53 | 26% | 0.0276 + 0.0043 = 0.032 ± 0.005 |
  | measured credit | 0.41 | 36 | 33% | 0.0223 + 0.0023 = 0.025 ± 0.004 |

  The carrier shot more, from angles, for rebounds the team does not collect
  as priced. The credit races our men from where they stand at the release,
  but nobody moves for the rebound until the save, and the second shots come
  early (0.83 s median), at the keeper's pads, where the measured conversion
  is lowest.
- **So the carrier keeps a flat credit for now** (`AIActionScoring
  .FLAT_REBOUND_CREDIT`, the old 0.3 × the floor at their goal line), and the
  measured one is switched on with 3b/3c, which make the follow-up it prices
  happen. The pair is then measured together on the rebound sweep's xG.

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

**Status: built (`645baa1`), no measurable effect.** NET_FRONT crashes to
the release's measured contest point and the FINISHER to its late point
(`AIReboundField.crash_point`) while our shot is on its way. The finisher's
tip read now asks whether his blade can reach the puck's line in time
(`AILoosePuckChase.reach_eta`), so a tip he cannot make becomes a crash.

Rebound sweep, J=11, 576 possessions each:

| | first touch ours | 2nd shots / shot | xG / possession |
|---|---|---|---|
| flat credit | 26% ± 4% | 0.089 | 0.032 ± 0.005 |
| crash, flat credit | 28% ± 4% | 0.088 | 0.030 ± 0.005 |
| measured credit, no crash | 33% ± 3% | 0.119 | 0.025 ± 0.004 |
| crash + measured credit | 32% ± 3% | 0.119 | 0.029 ± 0.004 |

**Who beats us** (the first toucher's slot, crash + flat credit, 136 live
rebounds): their ZONE_D_STRONG 47 and ZONE_D_WEAK 20, half of all
rebounds, then ZONE_C 12 and the wingers 19. Ours: FINISHER 14, NET_FRONT 12,
the rest 12. Their house D stand between our forwards and the net, and a
rebound comes out to whoever is inside. Crashing on the release cannot
change that geometry. Winning inside position at the net is what can, and
that is step 4's net-front battle (the screen and the box-out), not more of
step 3. The measured credit stays off until something wins rebounds as it
prices them.

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
