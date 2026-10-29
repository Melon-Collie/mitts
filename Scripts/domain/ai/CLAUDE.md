# Bot AI — design rules

Scope: `Scripts/domain/ai/` (scoring, role behaviors, skill profiles) and its
consumers in `Scripts/ai/`. Read this before changing how a bot *decides*
anything; the per-file comments cover how each piece works. What the bots
consider, piece by piece, and where a new feature plugs in is the catalogue in
`DECISIONS.md` (`test_decisions_inventory_resolves.gd` keeps its citations live).

## Evaluators model perception, never feel

Every multiplier in the utility scoring must be a quantity the bot can
physically **see** — the open-net angle a shooter can hit, a defender's reach
vs. the puck's flight time, the goal mouth's projected width — not a curve
shaped to feel right (`1 - x/K`). A grounded model generalizes to situations
nobody tuned and stays honest when an upstream number moves; a magic curve is a
model you haven't built yet.

When a behavior is wrong, fix the **model** — give it the perception it's
missing. Do not bolt on a corrective multiplier or a hard positional gate: those
compensate for a model that isn't seeing something, and they rot.

Constants in an evaluator must be physical measurements (a reaction delay, a
reach, a body width), not shape parameters. *Feel* tunables — staging offsets,
difficulty knobs, how the game should play — are legitimately hand-picked; the
line is evaluation vs. feel, not "numbers are bad".

## One currency across the carrier's compete

SHOOT, PASS and CARRY are compared numerically, so all three price the shot
through the value seam (`AIShotValue` / `score_shoot_value`). Leaving one leg on
a different model makes that leg win or lose on scale alone, and a hold priced in
the wrong model is a permanent veto on the other two. The committed shot is the
seam's own pick (aim and loft), so what is priced is what is fired.

The turnover COST is in the same currency as the gains it is subtracted from.
The carrier's gains are odds of scoring wherever he stands, so
`AICarrierField.turnover_cost` prices a loss as the opponent's possession of the
spot (`AIPossessionValue`), and passes `in_xg` to `counter_rush_cost`. What a spot
with no shot right now is worth — a turnover there, the carrier's search
horizon — is that one read, for either side. The defence reads
a man on it too: `threat_of_carrier` (his shot, or his possession of the spot)
and `threat_of_feed` (his one-timer, or the lane × his possession), a candidate's
body pushed onto the read's defence for the one call. The outlet and breakout
roles stand where the lane to them × our possession of the spot is best, so
there is no second scale left to mix in.

The giveaway bars (`SHOT_MIN_VALUE` 0.05, `PASS_MIN_VALUE` 0.02) are scale-bound
to that seam — odds of scoring on today's goalie with a first shot. A pass's bar
is weighed against keeping the puck: when both reads of keeping it (the carry
and the drive-in) lose it where he stands, that loss comes off the bar, up to
the whole bar, leaving only settle doubt's raise. A pressured carrier with an
open man ahead is choosing between the pass and a turnover, and a 0.015 outlet
is not a giveaway next to that.

A pass's receiver is priced at the best of his shot off the feed, his straight
drive in, and the zone entries our possession of his spot is priced by, from
when the puck reaches him (`AICarrierField.entry_value`) — the read the defence
prices a feed to him by. He does not search, and a straight drive alone misses
every lane but the one at the net: a man taking a feed in stride at the blue
line with a defender in the middle is worth the lanes either side of him.

## Difficulty rides three independent axes

`BotSkillProfile` splits every tier knob onto one of three axes. Keeping them
separate is what makes tiers tunable without a rebalance cascade:

| axis | what it changes | knobs |
|---|---|---|
| **PRECISION** | how sharp the bot is | reaction delay, dispatch cadence, aim/timing error, settle doubt |
| **PACE** | how much time and space a human gets | pursuit standoff, anticipation lead, check aggression |
| **COGNITION** | which reads exist in its model at all | the bool gates |

Precision only shows up on the bot's *finish*. Pace is what a human feels on
**every** possession, which is why the two are separate dials — reach for pace
when a tier feels oppressive, precision when it finishes too well.

The pace knobs further split by what a lower tier concedes: standoff and
anticipation concede **space** (positioning); check aggression concedes
**threat** (physicality).

Two things deliberately outside the table. **Aim slew is not a tier knob** — a
bot slews its cursor at its build's lever-derived blade speed (`AISkaterCaps.blade_speed`),
so execution difficulty rides the bot's attribute build. Every knob is
denominated in seconds; the dispatch period is rounded to whole ticks at the
current rate.

Shot scatter (`shot_aim_error_rad`) acts on execution only: the compete prices a
spot through the value seam, which is a property of the chance rather than the
shooter, so a wobblier tier takes the same shots and misses more of them (#699).

Tuning order, when a tier is wrong: if it plays like a pushover, raise the
precision knobs back toward Hard and let the pace knobs keep it beatable; if it
still feels superhuman, soften pace (standoff up, anticipation and aggression
down) before touching precision. If it makes plays a human wouldn't SEE rather
than plays it executes too well, that is settle doubt — raise the frac for a
higher bar, the τ for a longer one.

### Hesitation is a raised bar, never a timer

A lower tier is less sure of a puck it has just gained. That is expressed as
**settle doubt** (`BotSkillProfile.settle_penalty_frac`): a decaying fraction by
which a fresh carrier handicaps its own read of every ACTIVE option against that
option's *giveaway bar*. An obvious play out-values a raised bar on the first
tick; a marginal one waits for the doubt to drain. So the bot deliberates over
close calls and is decisive on clear ones — a tier reads as *less sure* rather
than *laggier*.

Charge it against the **bar**, never against the carry it competes with. The
stand-still carry candidate is by construction worth the same as firing from
where the bot stands, so a handicap inside the fire-vs-carry compete can only be
a uniform delay — it holds the doorstep tap-in exactly as hard as the hopeless
point shot, which is the flat "may not commit for N seconds" gate this rule
exists to rule out. The decay is exp(-t/τ) and never reaches exactly zero: that
is harmless against an absolute bar, but inside the compete, where stand-still
ties fire exactly, any residual penalty would suppress firing forever.

### The rule that keeps cognition gates honest

A gate may only remove an **input** the evaluator consumes (perception — the
lower tier scores with less information) or remove an **option** from the
compete (repertoire — the play simply isn't considered).

A gate must **never** corrupt a shared evaluator per tier. No difficulty-scaled
fudge factors inside the scoring, no tier-aware constants in the models. This is
what lets one set of evaluators serve every tier and stay unit-testable.

Normal and Hard deliberately run **all gates open** — they are the same player
separated only by continuous tuning, so the gap reads as "sharper" rather than
"knows moves the other doesn't". Easy is where gates close.

## A defensive stand is a moving frame, not a spot

Everything a defensive role computes — the gap ladder's stand, the angling
shade, a cover point, a backchecker's hip — RIDES an opponent and sweeps toward
our net at his pace. So the role publishes the stand's own velocity
(`RoleDecision.target_velocity`) and the steering flies the route in that frame
(`AISteering`, moving-frame pursuit): the commanded velocity is the stand's plus
a closing term that is spent by the time you arrive, so an approach ends
*matched* to the play rather than stopped in front of it. Flown as a parked
point, a defender could only defend from ice he was already standing on: one
starting 20 m off his stand meets the carrier at ~10 m/s of relative speed.

Three consequences:

- **Price a stand at the ride it is skated at.** A candidate pushed onto a
  possession read standing still is a man a carrier at speed out-skates
  (`AICarrySpace`'s escape credit), so only the end of his drive — the crease —
  would read as covering it, and the argmax walks the pressurer in.
  `carrier_best_option` takes the candidate's velocity; PRESSURE passes its
  `stand_ride_velocity` (`test_role_pressure.gd`).
- **Do not bound a route by placing the stand defensively** (a step-up plan, an
  approach-speed limit). The route already regulates its own approach, so a
  placement bound on top is two controllers on one axis: the stand lands where
  the defender already stands and he never closes on anybody. A bound on what
  the route may COMMAND is a different thing — the stand stays where it is and
  the frame still closes on him — and that is where the retreat floor and the
  advance cap live (below).
- **A ride velocity is a commitment with no terminating condition.** A stand only
  gets one when the role really produced a stand. A degenerate "hold where you
  are" fallback that also rides a man matches his velocity forever — out through
  the end boards. `AISteering.is_rideable_anchor` is the structural backstop; the
  role is still expected not to publish one it did not earn.

Both halves are pinned by `tests/slow/ai/test_defensive_routing.gd` (share of
time in shape, and whether a defence pair gets blown by) and
`test_rush_gap_discipline.gd` (up-ice speed and excursion at the meet). They
measure the BODY over multi-second rushes, which is the only honest home for a
claim about a route — a single dispatch cannot see one.

## DZONE is a shape, not a location

The raw possession table flips to DZONE the instant the puck crosses our blue
line with an opponent carrying. Slotting on that alone re-slots still-
backchecking forwards onto zone posts and dissolves the backcheck at the line, so
the brain holds the rush/recovery shape until the bodies the coverage assumes
have arrived (`AIRushRead.coverage_ready`, gated by
`AIPossessionState.coverage_read`). Get back, get set, THEN take your man.

Three rules keep the gate honest:

- **Parity, not everybody**, capped at the bodies we have. Requiring every body
  makes four home bots wait on a fifth who is late, and a team genuinely a man
  short (a human who will not backcheck, a ghosted bot) would never satisfy it.
  Once the numbers are even the late man joins as a layer for free: the bodies
  already home win the important jobs in the soonest-to-arrive election, and
  the straggler inherits the leftover.
- **Bots only.** A loafing human must not inflate a requirement he will not
  satisfy, nor count toward the cap.
- **No coverage clause, and no time floor.** Asking whether men are already
  covered is a MAN-coverage test gating entry into a ZONE, and a correctly
  executed zone fails it — so the gate could never be satisfied by the shape it
  gates, and a time floor would end up doing all the work. A home-ness predicate
  is monotone in the recovery it waits on, so it clears on its own.

The gate is asymmetric on purpose. Becoming UNSET is instant, while leaving
coverage takes a sustained stretch, because a body straddling the blue line to
pressure the point is not a broken structure.

## Forecheck or set up

Their puck in their zone is a forecheck only while we can pressure it: our
soonest forechecker's blade on the puck before its carrier can make his first
play. A man with time to look up makes the stretch pass past an aggressive
forecheck, so `AIForecheckRead` prices exactly that time — the pickup and its
settle for a loose puck, his read (`CARRIER_READ_S`, a choice reaction set by feel, less
what he has already held it; the brain counts the hold) and the release window —
and the brain runs FORECHECK while we beat it, TRANS_DEFENSE (the set
neutral-zone shape) once we cannot. So a dump, a strip or a turnover we are on
when they collect it is forechecked, and a D who has had the puck settled
behind his net is not: the 1-1-3 waits for him. In 5v5 a D counts only as far
down the wall as the strong D's pinch goes; F1 is a forward. A loose puck is
raced on its path, from where it is first played, a tie counted as ours (a 50/50
in their end is gone after). The hysteresis sits on the margin
(`ENTER_MARGIN_S` / `HOLD_MARGIN_S`), not on the shape, for the reason the
recovery race's does.

Never price it as catching him before he skates the puck out: a retriever deep
in his corner is a long skate from his line, so that race reads a forechecker
from our own end as on him, and every stretch pass beats it.

**A dump-in opens the forecheck at the release.** The point of dumping it is the
forecheck it starts, so our release from a carry outside their zone, untouched
since, is raced the same way while it flies (`TeamBrain._read_dump_in`): FORECHECK
when we win it or are on whoever plays it before he can move it, TRANS_DEFENSE
when he has the time, and the possession table's shape when it is played before their line
(a feed taken in the neutral zone). The same release inside their zone — a pass,
a shot gone wide — keeps the attack's shape. Who released it and from where is
all the read uses; whom it was meant for is never published.

**The forecheck is the 1-2-2** (3v3: the 1-1-1). F1 pressures the puck (PRESSURE);
F2 reacts in front of their net (`F2_NET`: the breakout-feed argmax centred in the
slot, where the reverse, the D-to-D behind the net and the net-front outlet run);
F3 supports on the near wall (5v5 `F3_WALL`, the same argmax at half-wall height,
who also fills the strong point while its D pinches; 3v3 `F3_HIGH`, high on the
near wall at their line); the D pair holds their line, ready.

**The set shape is the 1-1-3** (3v3: the 1-2), **filled from the back.** Our line's
posts elect first, each with a deadline — the carrier's arrival there less the
brake margin — so whoever can be set there in time holds it whatever his
position, a body already deeper than the line always can, and a team caught
short fills the line before it fills anything up the ice. The jobs:

- `BACK_STRONG` owns the carrier and **stands him up at our line**: while even a
  man standing on the line would make his retreat in time (the stand priced with
  a standing start's ramp cushion is still up-ice of it), he waits on it, inside
  the dots, and the carrier comes to him. Then the gap ladder and its route as
  below. A back man deeper in the zone steps up to the line only if he can be
  set on it before the carrier eats that slack: arriving with up-ice momentum is
  how he gets walked into his net (`test_defensive_routing.gd`). A man already
  riding the retreat, or caught out in front of the carrier, rides the ladder
  back instead — holding the line from there brakes him flat-footed in front of
  a carrier at speed (`test_speed_rush_defence.gd`); a stalled carrier is still
  stepped up on.
- `BACK_MID` holds the middle of our line behind him and the feed across is HIS:
  `BACK_STRONG` plays the pass (the odd-man lane fan) only while nobody holds the
  middle. Two bodies reading one pass leaves the carrier walking in.
- `BACK_WEAK` (5v5) the weak lane.
- The back line moves with the carrier only as far as the gap and the ramp
  require (`AIRoleNeutralZone.back_line_depth_m`), never past the house gate, and
  each back man picks up a man only once he is in his ice (his post plus a cover
  envelope): covering a man still up the ice walks the line out to escort him.
- `NZ_F1` steers from in front while the carrier is in their half — the angled
  stand, no deeper into their zone than their circle tops (the forecheck we did
  not take) and not past the red line — then runs him down from behind.
  `NZ_MID` (5v5) holds mid-ice a layer up from our line, then comes back through
  the middle.

## The rush fills the lanes the carrier leaves

On a 5v5 rush (TRANS_OFFENSE) the two lane slots fill the two of the three
lanes the carrier is not in: both wings round a carrier up the middle, the
middle and the far wing round one on a wall. A man driving the middle pushes
their D off the line and opens the entry; two men outside with the carrier on
one wall double his lane and leave the middle empty. The carrier's lane is the
brain's read (`AIRoleRushLane.carrier_lane`, hysteretic, held while the puck is
loose), so the slot election and the role agree on it. LANE_L is always the
left of the two, so a lane change swaps where the fillers go, never which of
them goes. The TRAILER (any group) is the activating fourth man: a D joins
the rush when a forward carries; DVALVE stays home.

## The defensive verbs

A defensive role should read as *pick who is mine, call a verb, add my extras*.
Three verbs exist as shared code; the roles compose them.

| verb | seam | callers |
|---|---|---|
| **cover a threat** — take the ice between him and our net, in the feed lane, riding him | `AIDefensiveVerbs.cover_threat` | MARK, the 5v5 zone soft-lock, BACK_MID, BACK_WEAK, NZ_MID |
| **close the carrier** — read his approach, hold the ladder's gap, angle him off the middle | `read_carrier_approach` + `carrier_stand` | PRESSURE, BACK_STRONG, NZ_F1's steer, and the read alone for NZ_F1's backcheck |
| **go get the puck** — race it, or hold the pre-contain stand when somebody else has won it | `AIDefensiveVerbs.chase_puck` | CHASE |

`AICarrierApproach` is the carrier half's subject: his position and velocity, the
line he retreats us down, the route he has left, and his pace along it, filled
into caller-owned scratch.

Two things deliberately do NOT go through the second verb. **NZ_F1's backcheck
takes the hip, unangled** — a backchecker is behind the play and catching up, so he has
no inside to take; he shares the read and places his own target. And **PRESSURE
cannot simply call a verb that fills the decision**, because its argmax sits
between the stand and the answer: it consumes `carrier_stand` as the ring's
centre and `inside_dir` / `inside_shade_m` as a floor on the candidates, then
sets the target itself. Outside a forecheck its ROUTE is BACK_STRONG's
(`depth_first`, the retreat floor, `set_advance_cap`), so the argmax picks the
bearing and nothing about how the body skates there changes at the line; a
forechecker (the carrier in his own zone) has no retreat to manage.

A loose puck is not a fourth subject — it is a carrier nobody is holding. Both
of the first two verbs reach it through `resolve_defensive_play_ref`, which
answers with the puck when no one carries. `chase_puck`'s DECLINE branch is the
closing verb applied to the puck (`fill_approach` on the puck, then
`carrier_stand`), so the pre-contain point is exactly the stand BACK_STRONG will want
when possession flips.

The election of WHICH body runs the race is not part of the verb and stays in
`AILoosePuckChase` / `GameManager` — the verb answers "do I go", the election
answers "am I the one who may".

**The reach-in is the pressurer's extra, and it is a jab or a lift.** Whichever
role owns the carrier reaches in when the puck is inside its stick; the jab aims
the blade through the puck, and `AIStickLiftRead` turns it into a stick lift
exactly when the carrier's body stands on the line to the puck (the jab has no
path) and the shaft's liftable point is still in reach. The lift is the
`lifts_sticks` cognition gate, closed on Easy so a shielded puck genuinely
protects it against a beginner tier.

**A defensive-zone coverer's extra is the stick tie** (`AIStickTieRead`), and its
price is its own stick. The man is tied only while the puck is coming to him — a loose
puck whose path reaches his blade, or his carrier with a pass lane no defender's
stick reaches — and only when the coverer's free stick could not have stopped it,
with the man's shaft in reach, and he holds it while that stays true. A puck
already at the man's blade starts no tie — loose for a tick under his own
stickhandle or a contested pickup, it is his puck, not a feed — but a tie already
made holds through the arrival, which is the reception it exists to deny. His blade
follows the man's stick through a lag of `StickCheckRules.TIE_LAG_BUDGET_S` —
what a human holder sees it late by over the network — so a bot holding a tie is
beaten by the same jukes a human would be. A tied attacker the feed is coming to
pulls his stick straight away; one it isn't coming to holds on, keeping that
defender's stick out of the play. Both halves are the `ties_sticks` cognition
gate, closed on Easy. The tie reads the covered man from
`RoleDecision.locked_man_pid`, which MARK and the 5v5 zone roles set and
`cover_threat` deliberately does not: BACK_MID, BACK_WEAK and NZ_MID cover a man in
transition, where the stick belongs in the passing lane, so they publish no lock
and never tie.

**On the boards, the checker's extra is the pin** (`apply_board_play`, every
tick after dispatch). A check driven into a man on the wall that will not knock
him down reaches for the pin on the stick button instead, and the hold follows
what is coached: keep the stick on him while our support beats theirs to the puck (the same momentum-blind top-speed
bound for both sides), or in our own end to kill the play; never as the last man
back outside it. Locked, the pinner drives into the wall and matches the victim's
slide, read through a lag of `BoardPinRules.PIN_LAG_BUDGET_S`, so a bot is
beaten by the same reversals a human would be. It rides the PACE physicality knob
(`check_aggression`, zero on Easy), not a cognition gate. A pinned bot slides
along the wall and reverses when its pinner commits to following (his along-wall
speed our way past half our cap), no sooner than a reversal can land. A carrier
at the wall with a checker coming square, stick out, answers him as coached,
bracing last (`AIPinThreatRead`): he skates out of the checker's line along the
wall if he gets past the offset where the hit stops being square before contact,
and holds the commit only when he can't. Bracing costs the commit's grip and
stride, so it is never free insurance. Read through the tier's perception delay,
a fast square drive catches him still thinking he has time, and a slow approach
gives him time to leave. The `protects_the_puck` cognition gate.

**Any defender meets a carrier skating into him with the shoulder**
(`AIStandUpRead`, applied by `SkaterAgentStandUp` after dispatch): Ctrl held
inside `MEET_S` of contact when, committed, the contact rocks him. It is not
the body-check commit — nothing is chased and no containment is given up,
because by then the contact is happening anyway; it only makes a carrier who
skates into a set defender meet a check rather than a bump. It rides
`check_aggression` (zero on Easy).

**Any defender's extra is the shot block** (`AIShotBlockRead`, applied by
`SkaterAgentShotBlock` every tick after dispatch). He drops into it when an
opponent in our end winds up and we stand on the line from the release to our
net, the shot is still under the block's seal when it reaches us (his replicated
loft rung under gravity), and we are not inside the room our goalie needs to see
around a screen. He stays down while the released puck is still coming through
us. The last defender on a man-down rush dives across a pass lane past his
standing reach: his stick, plus what he skates toward the lane while the pass
travels to it from rest across it. The dive must still reach the lane, and no
teammate may be nearer it. Both are the `blocks_shots` cognition gate, closed on
Easy.

**The coverer's other extra is the press** (`AIPressRead`, applied by
`SkaterAgentPress` after every other body and stick pass). Within
`STEP_IN_M` of the man who screens our goalie, he holds Ctrl and drives into him
when the pair's motion the host would lay (`PressRules` on the man's replicated
facing, posture, brake, stagger and intent) moves him off the sightline within
`READ_S`, by the goalie's own body test (`AIScreenRead`). The push runs along
the line through the man, so it clears a screen only from the side that moves
him off it; getting to that side is the role's.
A held tie keeps its stick through the press. It rides `check_aggression`. A
screener in their end with a defender on him digs in, braking in the stance,
whose anchored stop holds an equal man's drive; a carrier skating into a man
who stands him up holds Ctrl, the brace, when the pair moves his way harder
with his body in it (`AIPressRead.pair_accel`, with against without). Both ride
the `protects_the_puck` gate.

### The three facts a station reads, and the one that stays unread

**CONTROL** (`AIRushRead.pressure_eta_s`) drives NEITHER the hold decision nor
the station leash, and must not be wired to either. Contested control with nobody
behind you gives a retreat nothing to cover, so it cannot send bodies home; and
shrinking the leash under pressure turns an outer bound into an attractor that
drags a POINT into the corner. The pressure-dependent "give close support under
heavy pressure" belongs to SUPPORT's own positioning, which already prices
pressure. **SUPPORT** (`has_support_behind`) and **NUMBERS** (an attacker behind
my stand) are the two that bind.

The D-vs-forward asymmetry needs **no per-position appetite scalar** — it emerges
from who is physically rearmost. In an O-zone cycle the POINTS are the rearmost
bodies (~9 m from our blue line), so they read no support and respect any man who
gets behind them: they ARE the last layer. F3's high-slot float sits ~8 m further
up-ice, reads the points as support, and holds.

And when the read says back off, the target is **not home**. Better a 3-on-2 than
a pinch that becomes a 3-on-1: backing off restores a NUMBERS LAYER and then
stops.

### The play-connection leash

`pull_into_play` is the bound nothing else supplies. Every other bound pulls a
station toward home, so without it no term can ever say "you have left the
attack" — it is what makes the support triangle CONTRACT under pressure instead
of stretching. It is denominated in a FLIGHT TIME rather than metres, because
support is defined by whether a pass is on. It applies only while WE possess and
only to a HOLDING station: clamping a legitimate recovery back up-ice toward the
puck would undo the coverage the numbers read just called for.

### A pinch is priced on both halves, and its cover is another role's read

The back layer leaves the line in two ways. A **keep-in**
(`AIRoleDefenseman.wall_rim_keepin`) costs it nothing — the stand is still the
line, just out in the wall lane where the puck's predicted path crosses it — so
every line station runs it: the points, the forecheck pair, 3v3's F3. A **pinch**
goes down the wall to keep the puck in, onto their man as he plays it between
the line and the half-wall. It is the O-zone strong point's play on a puck we
are losing up his wall as much as the forecheck pair's on a carrier bottled
there, and it is gated on WINNING it and on COVERING it (nobody behind my stand,
my partner on the line, a forward able to take my point inside
`LATE_MAN_WINDOW_S`). Winning a carrier is reaching him before his skating gets
the puck to the line; winning a loose puck is my blade on its collector before
his first play is away (`AIForecheckRead.read_loose`, the forecheck's own
pressure read), and a loose puck we collect first is the chase election's, not
a pinch. Only the strong-side D makes it; never both.

The cover is not the pinching D's to arrange. It is keyed on the one fact every
teammate can see — the strong D is deeper than any stand his slot takes — and each
role reads it for itself: the weak D holds the middle of the line, HIGH_SLOT /
F3_WALL takes the vacated point. So it fires however he got deep (pinch, chase,
battle), and releases when he is back. The D slots race the lateral trip
(`SlotSpec.lateral_race`) precisely so a pinching D keeps his job while it runs.

## Covering a man is one behavior, and the role only chooses WHO

`AIDefensiveVerbs.cover_threat` is the whole of it: take the ice between him and
our net, from inside the lane the puck would be fed to him through, riding him.
Every off-puck defensive role calls it and differs *only* in which man it names —
MARK and the five 5v5 zone roles from the threat partition, BACK_WEAK and NZ_MID
from whoever entered their lane, BACK_MID from whoever is driving the middle. **Man
defense and zone defense are the same behavior under different assigners**, so a
new coverage scheme is a new answer to "who is mine", never new positioning code.
Position and velocity come from one snapshot entry, so a stand cannot ride a body
its geometry isn't built on.

`TeamBrain` matches every man-covering body at once, and a zone role's AREA
enters as ELIGIBILITY — which men it may be handed — rather than as a private
search. Do not give the zone roles private argmaxes over their areas: the areas
overlap on purpose, and independent argmaxes double-cover (most D-zone ticks)
while leaving the best man open. The areas tile the zone, so a man can stand in
nobody's coverable area only when his area's owner is on the puck: the pressure
owner's area is therefore every zone defender's while he is (a strong D in the
corner leaves his net-front man to whoever the matching sends).

## The gap ladder is one ladder, and both puck-owners read it

`AIRoleRushD` (the rush gap) and `AIRolePressure` (the in-zone puck pressurer)
size the same gap off the same function, `AIRoleRushD.ladder_gap_m` — ~3 stick
lengths at their blue line, 2 at the red line, 1 stick at ours, and inside our own
zone "1 stick / contact: you are on him" (`docs/transition-defense-plan.md` §6).
So the TRANS_DEFENSE → DZONE re-election is not a geometry discontinuity: *the D
who gapped a carrier through the neutral zone keeps him into the zone; there is
no handoff at the line.* The same holds for the route (above) and for the hit:
the pressurer commits a body check only with support behind
(`AILastManDiscipline.has_support_behind`) or a cover its caller has already
priced (the pinch's rotation), because a committed hit loads him on
a shoulder at half a stride, and the last man back who throws one at a carrier
with speed is skated around (`test_speed_rush_defence.gd`).

Three things have to be true together, and each is load-bearing:

- **No anticipation lead in the anchor.** The route carries the man's velocity as
  a feed-forward, so leading as well double-counts his motion and inflates the
  frame-relative gap by `pace × lookahead` — a defender walked to his own goal
  line by a player who simply skates at him.
- **The ladder is a FLOOR on the gap, not just where the ring is centred.** The
  score is "how much does my body deflate his options", which improves
  monotonically as you close, so an unconstrained argmax collapses onto the man.
  Clamp candidates out onto the gap ring rather than filtering them, or the set
  empties exactly when it has closed and the bot falls through to standing still.
- **No last-man approach bound for a live carrier**, for PRESSURE or BACK_STRONG. It
  names a stand at wherever the body already is, so a pressurer being walked
  backwards is forbidden from closing on the man walking him. A loose puck keeps
  it.

A house-gate floor on the STAND is wrong: it only widens the gap past what the
ladder asks for. The floor belongs on the ROUTE (`AIRoleRushD.set_retreat_floor`),
and it says when a defender may give ice while he is still in front of the
carrier: with a gap, down to the house gate and no further, because backing off
inside it only walks him into his own net; draped on the carrier, all the way to
the crease (`RETREAT_FINISH_M`), riding him. "Draped" is within a stick, or close
enough that building to the carrier's pace from where he stands ends with him
there (the ramp cushion, below), so he is at speed when they meet rather than
reached flat-footed. It caps only the route's speed toward our net (lateral ride
untouched), and level or beaten it lifts and he chases.

The same route is capped the other way (`AIRoleRushD.set_advance_cap`): no more
speed up-ice than he can still turn into the carrier's pace before the carrier
eats the depth he holds past his gap — `approach_speed_cap`, the step-up bound
with its pivot, the carrier's pace being his whole speed turned at our net. A
gap-up keeps its stand a stick off the carrier; what the cap stops is the
moving-frame closing term walking him up-ice at a carrier who is crossing rather
than coming, which the turn down then beats. A carrier with no speed still has
his burst, which he starts the moment the defender commits: the cap prices what
he builds along his stride ramp while the defender brakes, so a stalled carrier
is closed on at a pace the defender can turn out of, never charged.

### Facing the play, or turned to skate with him

A skater backward has 80% of his stride and 80% of his top speed
(`SkaterMovementRules`), so a carrier at speed outruns any backpedal. The
defender in front of him skates one of two retreats (`AIRoleRushD.retreat_gains`):
backpedalling facing the play, or turned to skate down the ice — each priced as
a race after the time his body takes to turn there from where it points now
(`AIStrideRamp.head_start`'s chase delay, at his facing turn rate). He faces the
play unless backpedalling loses the race — the carrier gains more on it than
the depth he holds past a stick — and then turns if that concedes less
(`set_retreat_facing` → `RoleDecision.face_travel`, which the agent skates by
putting the cursor down the route). Draped or stepping up, he faces the man.
The race is priced down the carrier's line to the net, so it only governs a
route that is mostly that retreat: a route to a stand more across the ice than
goal-side stays square to the man, so a cut back reverses his crossover instead
of a turn he has to undo (`test_role_rush_d.gd`). What a cut back still beats is
a defender who has matched a wide carrier's drift (`test_nz_turnover_recovery`'s
header; #799).

The turn's cost is what keeps it honest: from a stand a turn costs more ground
than backpedalling, so a standing defender backpedals first and turns once he
is moving with a carrier he cannot match — the coached "turn and skate" — and
turning back costs as much again, so it does not flicker. The ramp cushion is
NOT priced on these retreats: a straight race cannot see that a carrier bursting
from a stick away has to go through the defender, and priced that way the
cushion never lets him step up on a stalled carrier.

### Pace enters through the stride ramp, and only there

The ladder is the gap between two bodies already travelling together. Under the
stride ramp a defender who is not yet one concedes ground while he builds speed —
a standing body against a 9 m/s carrier gives up ~5.5 m, more than the whole
3-stick ladder. That head start is `AIRoleRushD.ramp_cushion_m`
(`AIStrideRamp.head_start`: both drive flat out down the line from their current
velocities, his up-ice momentum braked out first), and every ladder reader adds
it. It is nil for a defender riding the rush at its pace.

The threat starts from the better of his pace along the line and his whole speed
turned onto it, less the ground the arc costs at his edge-limited turn rate
(`head_start_on_me`). A turn keeps a skater's speed; read along the line only, a
carrier crossing the ice at speed looked like a standing one, and the defender
stepped up into the turn that took him wide.

The race finishes where a ridden retreat ends (`RETREAT_FINISH_M`, the paint
plus the crease buffer): the horizon is his trip there, the head start is capped
at the ice he has left to it, and the cushion never pushes a stand past it
(`_with_cushion`). BACK_STRONG's stand is still held out to the gate
(`_clamp_to_house`); inside the zone, the pressurer's is not, and the floor above
is what keeps a stand that deep from becoming a walk into the crease.

The gap-up reads the same race. "His speed advantage is gone" means he is not
coming at pace AND cannot build it past us (cushion under a stick) — the regroup
clause too, so a man crossing at speed is not regrouping; pace alone
steps a standing defender up on a fresh receiver who then bursts past him. And
when the retreat cannot hold a gap — the cushion eats all but a stick of the ice
he owns — a defender IN the carrier's lane steps up to meet him rather than be
reached while turning; off the lane he keeps retreating.

Depth comes before width (`depth_first`). A defender short of his stand's depth
has one speed budget: the pace down the line that keeps up with the carrier and
wins back the missing depth in the time his depth buys, and only the stride left
over may go across — scaled by the share of that pace he already has, so from a
stand every push goes down the line. Chasing a wide carrier's lateral first
spends the retreat, and a cut back then finds the defender level with him. A
hard "no width until at pace" gate measured worse: a defender who never shades
across is beaten wide by the off-lane starts.

The time his depth buys is the carrier's soonest trip down to it — from his pace
along the line, or his whole speed turned onto it at the arc's cost — never his
speed alone: a carrier skating across the ice at speed is not coming down it, and
pricing him as if he were leaves no stride for width at exactly the moment he
goes wide. And the cap is on width the defender would ADD: speed he already
carries across, the way he is sent, he keeps, because braking it spends the push
the depth needs.
`tests/slow/ai/test_nz_turnover_recovery.gd` scores this against the best a body
could do: a straight-line retreat on the same ramp.

### The ladder has a domain: the carrier has to be coming at us

It measures ice remaining before he reaches our blue line, which is a RETREAT
quantity. Deep in the ATTACKING zone that quantity is at its maximum and means
nothing, and PRESSURE is also the forecheck's F1, who is not managing a gap at
all. Unbounded there the ladder saturates at its 3-stick ceiling, held as a hard
floor by the gap clamp, so the forechecker cannot close even in principle (his
poke reaches ~1.9 m).

The domain read is the shared `AIRoleRushD.should_gap_up`, not a zone test. Its
"not coming at pace" clause (`AIRoleRushD.is_stalled`: closing under
`GAP_UP_CLOSING_M_S` with no head start to build) is satisfied by construction by
a D retrieving behind his own goal line, so the two
carrier-owning roles agree at the TRANS_DEFENSE → DZONE handoff exactly as they
do on the ladder itself.

### Hold a post — the open question

The per-role fallbacks and their anchor constants are still unfactored. Whether
"hold a post" should be a verb at all is open: if the assigner always names a
man, the carrier, or the puck, there is no fourth state and the constants go
with it.

## Determinism

Bot decisions must be replay-safe: same situation, same difficulty, same
behavior, every time. The **only** RNG anywhere in the bot is per-release
execution sampling — hands, never decision dice — seeded per bot and sampled
once per release, then held through the windup.

Domain AI files stay engine-free (no Godot APIs, no `tr()`), so the whole
decision layer is unit-testable headless.

**Tie-break on peer id, never on iteration order.** `AIThreatAssignment` and
`AIRoleSlots` both do, because `WorldSnapshot`'s dictionaries follow peer
REGISTRATION order. A symmetric geometry — two markers and two men mirrored about
x = 0, i.e. the faceoff net front — scores bit-identically, so without the
explicit tie-break the winner depends on who joined the session first and a
mid-session rejoin flips a standing assignment. Hysteresis cannot damp it: both
matchings score the same, so the retain branch holds forever.

## The goalie is tiered, but only ever as a weaker goalie

`GoalieSkillProfile` is the goalie's counterpart to `BotSkillProfile`: one bundle
of knobs per difficulty, which the keeper takes onto his reads, his hands and
his drop (`KeeperController._tier`), selected per match from the lobby.

Every lever in it must be a trait a real weaker goalie actually has, so a lower
tier still reads as a goalie — tracks the play, squares up, drops butterfly —
who gives up the net and can't rob you, never as a dumb one. Today every lever
is a read latency or a hand or drop speed (when he starts moving, and how fast
he gets there); his positioning is the same on every tier.

**The skater AI's goalie model is a MIRROR, not a second tier.** What the bots
predict of him outside the shot field — his leg read, his push, the depth he
takes, the post he holds, his rise — lives on `AIGoalieModel`, read from his own
code (`KeeperPositioning`, `KeeperFootwork`, `KeeperDrop`, his gear), with the
leg read synced from the match's profile by `set_goalie_profile`.
`test_ai_goalie_model_mirrors.gd` holds each one against him. The shot field
itself is measured against the Hard goalie only, so against a lower tier the
bots price shots as if the net were Hard's; per-tier fields are the planned fix.

---

## Where an evaluator goes

The files are split by dependency, not by topic, and the shape is load-bearing:
a const read across a GDScript `class_name` cycle can fail at PARSE time, which
takes the whole class down and every static call on it from every file at once.

- **Leaves** read no evaluator:
  - `arrival.gd` (`AIArrival`) — the momentum-honest arrival clock
    `time_to_arrive` and the reference speeds it assumes;
  - `net_obstacle.gd` (`AINetObstacle`) — segment tests against the cages and
    our own slot;
  - `feed_reception.gd` (`AIFeedReception`) — a feed as its receiver takes it:
    its closing speed in his frame, the settle of a catch, the odds and the
    regather of a bobble;
  - `puck_lane.gd` (`AIPuckLane`) — whether a fired puck gets through: the lane,
    the saucer, the release contest, the pass's launch speed and its own miss;
  - `bot_mechanics.gd` (`AIBotMechanics`) — the league-default execution
    constants the evaluators price and the agent executes (blade reach, the
    carry-cursor ring, the wrister charge and its lookahead);
  - `goalie_model.gd` (`AIGoalieModel`) — the keeper the bots plan against: his
    body's cover numbers, the difficulty-synced reads, planned depth, lateral
    push, post seal and predicted position.
- `action_scoring.gd` (`AIActionScoring`) holds the shot and pass reads on the
  value seam, the xG stat, position value, the races and turnover pricing.
- `carry_space.gd` (`AICarrySpace`) holds the carrier's room to operate:
  reachable-set evasion, the safety maps and the crossing sample.

Both evaluators read the leaves and never each other. `possession_value.gd`
(`AIPossessionValue`, what possession of a spot is worth) reads both from above,
so neither may read it. `test_scoring_split_stays_acyclic.gd` holds that. A
primitive both need goes in a leaf; an extraction is cut where nothing in the cut
reaches back into what remains.

## The models in detail

- **Shot value — the one shot model** (`AIShotValue`, `shot_value.gd`). Every
  "how good is a shot from here" asks it — the carrier's compete, the threat
  surfaces and coverage reads, a pass's worth to either side
  (`score_pass_value`), tips (`deflection`, the line not picked) and the
  post-game xG stat (`now_at_spread`, at the shot's context spread) — so offence
  and defence price a chance alike, and the model behind it can be replaced in
  that file alone. It answers the odds of scoring on today's
  goalie, read from `AIShotOdds`: the live keeper's open set,
  measured cell by cell (release spot × how he was beaten or set) and generated
  into `generated/shot_field_data.gd` (`docs/shot-currency-plan.md`). A goalie
  change is a regeneration (`.claude/hooks/generate-shot-field.sh`;
  `test_shot_field_is_current.gd` fails until it is run), never an edit here.
  - **Every measured carrier skated in** (`shot_odds_stager.gd`), so "set" is a
    keeper who tracked the carry, rushed back off it, and settled. A carrier who
    appears in tight with the keeper on his crease draws a committed slide,
    which no carry the bots price ever produces.
  - **The keeper is read as a Stance** — upright, down, or sealed on the post —
    plus his offset off the square, his lateral speed, his depth, and how
    square he faces the release (`AIShotOdds.squareness`, left out when his
    facing is not read); the field is kernel-weighted over those within the
    four spots around the release, each spot counting by how much matching
    evidence it holds, so a spot whose only cell is unlike the query yields to
    a neighbour with a close one. Squareness is what tells a keeper set on the
    shot from one a feed dragged off it at the same offset, so the keeper a
    carry arrives at is read facing the shot, which he has tracked: unread,
    his facing averages in those decoy and feed keepers, who in tight read far
    more open than the keeper the carry meets. Out-of-position keepers are
    measured, not extrapolated: DECOY cells set him on a carrier
    elsewhere, then shoot from the spot, and WRAP cells seal him in the RVH on
    a carrier behind the net, then shoot from a spot in close: the field's
    only keeper on the post, since in front of the goal line he stands on its
    overlap and reads as upright. A keeper on the post is read by whether the
    release is inside his seal zone (`AIGoalieModel.in_post_seal_zone`):
    inside it he is set there, outside it the puck has been pulled off the
    line and he is leaving, and blending the two priced a shot into a set seal
    off the pull-out cells a row out. A keeper "square and set" on the
    release (`AIShotValue.set_keeper`) is read from the SET cells alone,
    because a feed cell can show the same visible keeper and a different
    outcome. A pass is priced from the passer, the keeper square on him, at the
    feed's travel and flight. Outside `AIGoalieModel.GOALIE_HOME_M` the net is
    empty.
  - **Odds are at one placement scatter** (`REFERENCE_SPREAD_RAD`): a property
    of the chance, not the shooter (a wobblier tier misses more of the same
    shots). First contact is the outcome: rebounds and screens are not in it
    (#785), so a clean shot from range against a set keeper is worth ~0.
  - Held against measured cells it was not generated at by
    `test_shot_odds_vs_truth.gd`, whose error, concordance and pick-share
    bounds are ratchets.
  - The committed shot fires the field's own pick (`AIShotOdds.pick_shot_now`:
    the aim and loft with the best odds), so the price and the shot are one.

- **Carry safety** (`reach_clearance` / `best_evade_point`) — a reachable-set
  pursuit-evasion model. Each skater is a bounded-accel body: over a short
  horizon its stick can touch anywhere within (½·A·(T−reaction)² + stick) of its
  **momentum-projected** position. So a hard charger's reach rides downrange to
  where you *were* (beat him by letting him overshoot), while a jockeying
  defender's disk stays on you and a stick on the puck stays a strip threat.
  A man skating WITH a carry can also just stop from his read: the carry comes
  to him, so stopping commits him to no spot, and a defender backing off in
  front of a carrier is a wall he skates into, not a gap that holds
  (`AICarrySpace._stopped_clearance`; a chaser behind only loses ground by it).
  The carrier's projected defence reads him the same way: backing off in front
  of the carrier, he gives up no more ice, in any direction, than his stop
  takes (`AICarrierField.project_opponents`). Carried on, his retreat shows
  every delay of the entry an emptier blue line and his drift across (which
  mirrors the carrier) the far lane opening, so the carrier pulls up to wait or
  flips lanes each time the drift reverses. Which lane the carry is FOR is held
  the same way: the incumbent destination competes at the plan last found toward
  it, not at its straight-carry estimate, through which every lane past a
  defender reads alike.
  - A defender the carry path **meets** between samples is priced by the
    crossing band (`carry_crossing_keep`) on his full reach
    (`AISkaterCaps.max_blade_reach`) plus the poke's contact, the reach a
    poke-check is thrown at, less the little the shield buys at that range —
    measured by `tests/instruments/ai/test_crossing_band.gd` against a poker who
    leads the carry. The dwell and transit maps keep their own calibration on
    the stick's span: priced at full reach everywhere, a carrier in his own end
    read every forechecker's disk as closed and escaped fewer forechecks.
  - The **shot on a carry's arrival** reads a man behind the carry, skating its
    way, as on it for the whole carry (`AICarrySpace._chases`, through
    `AIShotHolds.solve_arrival`): a puck in the shooting pocket is not shielded
    as a carried one is, so the carry's own samples keep the short lunge while
    the wind-up at the crease does not. Never read that man as coasting to a
    last lunge there: a backchecker out-skating a carrier who slows into the
    crease then sails past it on paper, and the drive in out-prices the shot.
  - The **max-clearance seam** (`best_evade_point`, "can I keep the puck at
    all") prices the carrier's current safety. Where the body goes to beat a
    man is not a seam read: it is the carry's rolled moves, each priced at its
    own end (`docs/hybrid-carry-plan.md`).
  - **The boards bound the seam search** (`board_gap_m` rejects off-surface
    samples; a wall alone strips nothing). Pinned against the boards, half the
    envelope is illegal and the best seam runs along the wall, so a wall-pinned
    carrier's evadability collapses and it moves the puck.
  - **Body steering** with the puck is threat-gated and route-around
    (`AISteering._carrier_threat_repel`): each defender repels from the closest
    point of his momentum-swept reach (a beaten man exerts nothing; a charger
    sweeping through produces a sidestep, to the anchor's side or else the side
    with the ice, never into the boards), and the summed force loses any
    component opposing the anchor direction — pressure bends the carry line but
    never reverses it. Retreat is the carry *deliberation's* call, never a
    reflex.
  - **Blade-level protection** (`best_handle_protect_point` + the carrier's
    `protect_offset` / `protect_gain`): the carry mouse swings toward the
    protected seam, weighted by the safety the shield buys. HOW MUCH reads the
    max-clearance point; WHERE reads the **directed** one (`_best_clear_point`
    with the presented-forward spot as objective). Aiming at max clearance puts
    the puck on the back hip against any checker in front — on neither a shot nor
    a pass. A beaten / behind man is filtered out (`PROTECT_SCREEN_BEHIND_M`), so
    the carrier squares up the instant it clears its man.
  - **Every answer to pressure is a rolled move.** The carry search prices its
    hard cuts and its BRAKE (the stop that lets a committed checker's sweep fly
    past) by the same rollout as every other input; no separate maneuver
    overrides them. There is no deke: in the bot duels a defender does not
    bite on a fake (measured, he drifts away from it), and the rolled carry
    keeps the puck as well without one.
  - The carry mouse is clamped a blade-length inside the boards
    (`CARRY_BLADE_WALL_MARGIN_M`): a target at the kickplate slams the stick into
    the wall and knocks the puck loose.
  - The protect read is the `protects_the_puck` cognition gate
    (Easy carries naively presented so a newcomer's poke-check works).

- **Pass lanes** (`lane_clear`) — reach-vs-flight-time reachability: a defender
  blocks iff they can get a stick onto the puck's path before it passes; faster
  pucks thread better for free. The pass a carrier fires is read on the
  momentum-honest arrival clock (`AILaneReach`): at each point of the lane, can
  the defender's body get within a blade of it before the puck, skated from
  where his momentum has him when he reads the windup — a man backing in has to
  stop his retreat first. It is the reach the loose-puck chase plays a pass with
  (`AILoosePuckChase.reach_meet_time`, stick out), so a lane the passer reads
  open is one the defender cannot take. Graded by the clock's calibrated error,
  not a shaped curve; it ends a blade short of the receiver, whose own stick
  takes the puck there (a defender on his back is the reception's
  `catch_safety`). The lane is the one at the release: the carrier braked through
  his windup (`AICarrierField.pass_origin`), the receiver led from where he has
  skated to (`AIPassLead.lead`'s `release_s`), the defenders where their momentum
  has them (`opponents_release`). The cheap read the shot and off-puck searches
  use keeps the closest approach at a constant closing speed. The carrier's own read also takes each
  defender's **stick where he holds it** (`opponent_blades_release`): a
  forechecker reaching for the puck has his blade a metre nearer the lane than
  his body, and his hands start on the windup, so the first metres of a pass out
  past him are his. Only a pick his body can hold the stick at counts
  (`AISkaterCaps.max_blade_reach`). The **saucer** (`lane_clear_saucer`) is the same
  model under the flight a charged LOW release really gets (the shot ladder's
  set angle, so the lift and the carry grow with pace): during the over window a defender's reach
  collapses to their body radius (sticks fly under it), a stick stuffs it on the
  release, and from the touch-down on the rest of the lane is the accurate flat
  read, so the man it flew over still plays it sliding off behind him. A flip
  only clears a stick when it lands out of his reach. The flip must land with runway before the tape
  (`saucer_max_launch_speed`), so the carrier scores each receiver flat and
  saucered and lets EV decide (`carrier_pass_search.gd:_pass_variant_ev`, the saucer paying
  `SAUCER_EXTRA_MISS_PROB`); below ~4 m no legal saucer exists. **Receiver
  commitment** enters the completion model as an execution-miss term: a receiver
  mid-cut curves off the straight-line lead by his heading arc's tangent
  deviation (`receiver_heading_uncertainty_m` = R·(1−cos ω·t), from
  `WorldSnapshot.heading_omega_by_peer`), added to the passer's own spread in
  `pass_miss_prob`, so a feed into a hard pivot reads as the giveaway it is. The
  `reads_receiver_commitment` cognition gate.

- **Reception geometry** (`AITrajectory.solve_reception_gate`) — where a loose
  puck comes into a receiver's reach, solved on the puck's REAL path (friction +
  rounded-corner board caroms, the same integration the chase election uses), not
  the straight ray off its current velocity, which on a rim lies about both the
  arrival time and the incoming direction. One walk per receiver feeds the
  side-stand stance, the timing gate and the blade aim; each step is tested as a
  **segment**, so the walk stays coarse enough to run per tick. "Is this coming
  to me" is whether the path ever **closes**, not a dot product against the
  current velocity — a rim running away down the far wall is closing, it just has
  a corner to turn first. Boards-hugging gates are played as a **wall kill**
  (`SkaterAgentReception.wall_kill_aim`): the stance side is forced rink-inward and the blade target
  pushed ONTO the wall surface, because a blade parked on the path line leaves
  the gap the puck squirts through.

- **A pass in flight is still ours.** `AIPossessionState` keeps a fast loose
  puck with its last carrier's team outside our zone, and the rush read takes
  the same answer (`AIRushRead.fill`'s `possession_team`): read as a loose puck,
  our feed to the point is a puck advancing on our net, and the points bailed.
  A dump-in is the one release of ours the brain reads as a race instead
  ("Forecheck or set up").

- **Loose-puck retrieval is two reads, not one** (`AILoosePuckChase`).
  - The **election** names exactly one chaser per team: momentum-aware
    intercept, incumbent hysteresis, per-build top-speed caps, and the friction +
    board-aware path walk for every loose puck. Race times are solved to the
    sub-step, so bots inside one walk step of each other resolve on geometry
    rather than the peer-id tie-break. A puck in the AIR is raced from where it
    lands: no point on the path before `AITrajectory.time_until_on_blade_plane`
    is makeable, in the election, the race-lost decline, the chaser's steer and
    the reach band alike. A puck coming to a teammate's stick is his in the
    election too, raced at the puck's own time to his band (`reach_meet_time`,
    never the passer's own blade as a feed leaves it): a 15 m/s feed steps clean
    over a receiver between two samples of the body race, and the far point was
    elected to chase our own pass while it reached its man. The election times
    his body only to within a blade of the meet (`stick_out`), so a receiver
    skating into a feed a couple of metres off his body is still its man; the
    band itself times the body to the crossing, since it breaks a bot off his
    job and a feed is never in reach of the blade it is leaving.
  - The **incidental reach band** (`puck_comes_to_reach`) answers "is this puck
    coming to *me*", which is not the election's business. Losing a race by
    0.3 s is no reason to hold your station while the puck slides past your
    skates. The band is reach + one stride, gated by the bot's calibrated ETA
    against the puck's own time to the crossing point, so it self-narrows with
    puck speed and stays "extend the stick", never a second chaser. It overrides
    the one-timer camp and the race-lost decline, and yields only to a **dead**
    puck (the `-1` election) or a **teammate already first to it**.

- **Teammates don't stab at each other's puck**
  (`AILoosePuckChase.teammate_first_to_puck`). The contested-pickup rule is
  symmetric by design: two blades on one loose puck means nobody gets it, which
  is right for opponents and for a genuine jam. Our own bots must not
  manufacture jams, so when a teammate's blade is nearer the puck (and near
  enough to be taking it) the second bot takes his stick off and the reach band
  declines. Deadlock-free: yielding requires the other blade to be nearer by more
  than `YIELD_MARGIN_M`, which cannot hold in both directions.

- **Race commitment is per-path, not per-position**
  (`loose_puck_race_lost`). A chaser declines a race an opponent has already won,
  but only to an opponent actually *running* it: on the puck, closing on the
  point he'd meet it at, or standing where the puck's own line runs through his
  contest band. `path_intercept_time` asks whether a body *could* be there, never
  whether it is going. A lost race is then only *declined* when declining buys
  something: a body between the collector and our net, worth a chaser only when
  there isn't already one. `_has_containment_behind` answers that with **two
  reads OR'd**, because each is unobtainable in the regime the other covers — a
  teammate goal-side of the pickup (the forecheck), or one who can reach the
  house gate (`AIZoneCoverage.HOUSE_TOP_DEPTH_M` off our goal line) inside
  `AIRushRead.LATE_MAN_WINDOW_S` (a puck rimmed behind our own net, where nobody
  can be goal-side of it). Do not re-phrase containment as a race to
  `best_opp_meet`: when the puck caroms behind our goal line that point IS our
  net, so nobody beats the collector there. Doctrine: a LOOSE puck in our end is
  always pressured — the nearest player goes and everyone else adjusts so the
  house stays covered. The question is never "may I go?" but "if I go, is the
  house still covered?". `test_loose_puck_engagement.gd` asserts the aggregate
  ("did *anybody* go?") over perturbation families, since every individual
  decision in that failure is defensible. The attacking-zone mirror is #604.

- **A dump-in is a race for where it is played** (`AICarrierDumpSearch`). From
  the neutral zone the carrier may release the puck into their zone with nobody's
  tape to aim at: aim points in their zone (the corners, a rim round the end
  boards, a chip off either wall at the circle tops) × a soft and a hard pace,
  each walked on the puck's path at the chase election's resolution and raced by
  the soonest body of each side — their keeper too, for path in front of his
  goal line he can push and reach to. The side that meets it first plays it
  there: `p · ours(meet) − (1 − p) · theirs(meet)`, p the arrival race in
  `arrival_race`'s contest band, widened by the clock's error over the trip
  unless their keeper decides it (he is no skate mis-timed seconds out), theirs
  the turnover there plus the 5v5 counter exposure. Ours is our possession of
  the spot on arrival or the feed it opens to our support dead-reckoned to the
  race's horizon (each man's shot there × the lane against the defence then):
  in the shot currency one man behind their goal line has no shot, so without
  the support a won dump reads as worthless. So a dump is a 50/50 or better
  exactly when our side gets there first, and it is worth what the spot is worth
  with the men arriving. Under NHL rules a release from our half that crosses
  their goal line untouched, without our side first to the dots by the clear
  margin, is an icing: a faceoff at our dot, priced as a coin flip for their
  possession there. It is held to the pass's giveaway bar. Never value a dump at
  an aim point it passes through at speed, never price a chip we would play
  short of their line as one (that is the carry's), and never leave their keeper
  out of the race: a rim that dies in his crease otherwise reads as our man's
  puck at the net, and out-scores an open carrier on an empty rink. There is
  still no defensive-zone clear — a carrier in our own end with nothing worth
  keeping the puck for keeps it, protects, takes the hit, or moves it with a
  qualified pass, the rim included, and the next re-eval looks
  again (`AIRoleCarrier._pick_commit_phase`'s `retention_hopeless` branch).

- **Rims are passes whose lane is the boards** (`AIRimPass`; each receiver's
  best launch is ranked by `AICarrierPassSearch._rim_launch_for`, and only the single
  best is priced through `carrier_pass_search.gd:_pass_ev`) — a third pass variant beside the flat feed
  and the saucer, in the same currency. It is searched as a RELEASE,
  not aimed at a receiver: bearings banked glancing off the boards near the
  passer, each walked at a pace ladder up to the passer's own wrister max. Of the
  launches that reach a receiver nearly as surely as the best
  (`AICarrierPassSearch.RIM_SOFT_SHARE`), the SOFTEST is fired: easier to stop, and
  one that gets by him dies sooner. The walk is the chase election's own, so the
  receiver a rim is priced to reach is the one the election will send to it. The
  LANE is a race along that path in `arrival_race`'s contest band — the
  receiver against the soonest opponent, and against their keeper behind his own
  net by the live goalie's trip gates. Arrivals over the receiver's catch
  threshold are dropped. Zone rules mirror the straight feed's. A winner is
  released as a FLAT charged dump along its bearing at its pace. In the O-zone
  the currency prices a rim to a man low in the corner near zero; the breakout
  rim up the wall past a forechecker is where it wins.

- **Last-man discipline is universal**: the three-fact read on `AIRushRead`
  (control / support behind / numbers), never a private per-station race.
  *Stations that hold forward ice while WE possess* — the 5v5 points, the
  forecheck line pair, F3, the high slot, the trailing valve — go through
  `offensive_station_target`: hold the forward stand (leashed to the play), or
  give it up — to `numbers_floor`, goal-side of the deepest attacker behind it,
  while we still have the puck; to the retreat floor once we don't. *The two
  NEUTRAL shapes* —
  3v3 FLANK and 5v5 DBACK — go through `neutral_station_target`: a slow loose
  puck is not a rush, so giving up the stand restores a **numbers layer**
  (`numbers_floor`, floored at the house gate) instead of a post. NEUTRAL also
  demands a second clause (`home_layer_behind_me`): somebody home behind me, not
  merely nobody past me, because in a loose-puck race nobody is behind anybody
  yet and the reactive half alone lets every body step up. The clause is
  antisymmetric (strictly deeper, by a cover envelope, with the elected chaser
  excluded), so exactly one body draws the layer. PRESSURE's last-man step-up is
  the one thing apart (`settable_stand_depth`, a rendezvous clamp on how far a
  challenge may lunge). Do not resurrect a per-station graded counter race
  without a reason the shared read cannot serve, and a measurement.

- **Openness** (`release_contest_clean`, inside every shot's defender share) —
  could a carrier get his action off from this spot: the release-contest race, run to the
  puck a carry-handle ahead of the body toward the net.

- **Positional value** — the carrier searches forward until play reaches
  something concrete, and only values a spot where the search stops. One unit
  on both sides of the line: the odds of scoring.
  - *In the zone* (the spot or the carrier) every candidate is priced through
    the value seam. There is no possession floor: the seam is smooth, so a spot
    with no shot right now still scores by its distance and angle. Behind the
    goal line every shot is 0, so a candidate there is worth only the pass
    OPTION it opens.
  - *Outside it* the carry searches two steps (a rolled move, then each move
    again from where it ends, for the `CARRY_PLY2_WIDTH` best: shoot, pass or
    carry on), pricing the defence it meets on each. Where a line stops outside
    the zone it is worth our possession of the spot
    (`AICarrierField.horizon_value` → `AIPossessionValue`): the best zone entry
    (the better of the shot and one straight drive in from it, kept as far as
    the carry-safety read allows) × the skate there × the race to it
    (`arrival_race`, its band widened by the arrival clock's own error over the
    trip). In the zone the same read is the better of the shot and the drive.
    The leaf is read on arrival: its man reaches the spot when the line does,
    at the pace he arrives with, and races the defence for the entries from
    then (`horizon_value`'s `arrive_s` / `arrive_vel`). The carry's moves and
    destinations read it so, and so does a straight drive in, a receiver's
    starting when the feed reaches him: a leg read from rest against the
    defence as it stands now out-prices the others, so a cut back ending short
    of the line read as an entry still to win, and a feed back to a man 15 m
    out read as his drive in. A receiver's own spot is still read at the
    release: the race prices any defender reaching an entry first as the entry
    lost, and over a breakout's 25 m a rim's flight hands every such race to
    the forecheck.
    No shape terms and no guess at where the defence will be: the leaf ranks by
    how far the zone is and whether a defender gets to the entry first. The
    race is what keeps the leaf honest against the searched lines — without it
    a line that stays outside reads better than one that crosses into the
    defence, and the carrier stalls at the line. Standing still outside pays the
    step's decay like every move. A straight carry on to a destination across
    the attacking line is not credited from outside: the race prices getting
    in.
  - Candidates also price the **pass option** they open
    (`carrier_field.gd:pass_option_from`: cached per-teammate spot values × the lane from
    the candidate, discounted as a future action), credited as the *improvement*
    over the same read at the current spot, so a lane already open belongs to the
    live pass and repositioning earns option value only where it reopens one.
  - The **cut back** (`AICarryRollout.Move.CUT_BACK`, skating backward facing
    the destination) and **regroup** (a destination) are the peel-outs; backing
    out to reopen a lane can out-value grinding on a defender.
  - **The net is a carry / blade obstacle** (`carry_path_blocked_by_net` /
    `net_safe_blade_target`): a destination whose route crosses a cage prunes
    (the wheel is priced round it), two **post-walkout** destinations appear
    behind a goal line, a rolled move is held off the cage as the body is, and
    the carry cursor
    swings around the nearer post (stick-on-net contact dislodges the puck).
    Behind-the-goal-line ice is playable for a carrier already back there
    (`AICarrierCarrySearch._candidate_ice_legal`), or the walkouts are the only moves and
    a pressured carrier plants on the end wall.
  - An in-zone candidate reached from outside also gets its **entry
    continuation** — the drive-in from it — so a drop pass wins only when the
    trailer's entry genuinely beats the carrier's.
  - **One-way valve:** a carrier in the zone prunes any carry candidate or pass
    receiver that would leave it. The pass half keys on the PUCK where it leaves
    the blade (`AICarrierField.zone_taken`), because that is what the offside line reads. The
    valve is a hand-set *tactical* choice (zone control is a rule of the game, not
    a perception), **buffered on both sides**: carry candidates stay
    `OZ_RETREAT_LINE_BUFFER_M` off the line (the pass windup sweeps the puck a
    stick's reach behind the body), and a pass target's lead sits
    `OZ_RECEIVE_LINE_BUFFER_M` inside it.

- **The carry is a destination and a skated move** (`docs/hybrid-carry-plan.md`).
  The destination (`AICarrierDestinations`) is where the carry is FOR, chosen
  with hysteresis and priced as one straight carry there. The move is one of
  `AICarryRollout`'s seven held inputs, skated a second toward it through the
  movement physics, the facing rule and the body's containment, and priced on
  where that leaves him — the arrival value there or the destination's carried
  on, × the keep odds along the rolled path (`_rolled_safety`), − the strip
  cost. The chosen input is the carrier's stick until the next re-eval: what is
  priced is what is skated. Never price a near move by a straight line and a
  closed-form clock — that is what let a carrier plan spots it could not reach.
  A destination across a cage is skated at the arrival clock's waypoint round it
  (`AIArrival.cage_waypoint`). A move whose path reaches a crease, or the goal
  line from in front, ends at its last sample short of it and is priced there
  (`AICarryRollout.reach_short_of_net`): the carrier re-plans many times a
  horizon, so a drive at the net is a release on the way in. Never prune it
  whole — at pace in tight that leaves only the brake and the cut back.
