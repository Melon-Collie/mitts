# Expected threat (xT) — one value for every spot on the ice

Status: **draft for discussion; nothing built.** Each decision below is open
until it is talked through, and is marked with the one recommended to start.
Once agreed, the CLAUDE.md workflow applies: this doc is the plan, and
deviations get discussed first.

## Why

What a carrier is trying to do changes at every blue line today
(`docs/zone-currency-plan.md`): in their zone his options are priced in scoring
odds, in the neutral zone in the odds of getting into their zone with the puck,
in ours in the odds of getting out. Three currencies, stitched together where
they meet:

- **Chains at the lines.** A pass back from the neutral zone into ours is worth
  P(out) × P(in from where it gets out), read live, two reads deep.
- **A turnover table per zone.** Their entry from a neutral-zone loss, their
  scoring odds over an ordinary entry's from a loss in ours, nothing in theirs.
- **Floors.** In our zone and the neutral zone every option can read negative,
  and the carrier picks the least bad.
- **Cost.** The next-line reads are the deepest live reads the bots run: the
  crossings of the line, the skate to each and the drive in behind it are about
  half of all AI time in a 5v5 (the profile in the performance work).

xT gives the whole rink one currency: **V(s), the odds that the team with the
puck at spot s scores before it loses it.** Every option is then the same
sum, wherever it is made:

    worth of an option = keep × V(where it ends) − (1 − keep) × V_them(where it is lost)

and the carrier picks the option that most improves on V(here). A shot is one
of the options: its V is the shot field's odds. A turnover costs their V from
the spot of the loss, one for one, the same shape in every zone and both
modes.

What stays: the **shot field** (it becomes the shot term inside V), the **keep
reads** (`AIStripOdds`, the lane reads, the release contest: they are the
`keep` above), and the carry and pass searches' shape. What goes, once V is in:
`AIPossessionValue`'s next-line reads and chains (`p_enter`, `p_exit`,
`play_on`, `objective_at` / `worth`), the per-zone `turnover_cost`, and the
entry race inside `AICarrierField.horizon_value`. The deepest live reads become
a table lookup.

## The decisions

### 1. What does a value depend on?

- **A. The spot alone** (classic xT): one number per cell of the rink. The live
  defence enters only through the keep odds of getting there and of what
  happens next.
- **B. The spot plus a coarse defence state**: for instance the numbers back
  (odd-man, even, set), so a top-of-the-circle spot on a 2-on-1 is worth more
  than the same spot against a set box. One table per state.
- **C. The full situation**: no longer a table; a learned function.

**Agreed: A.** The situation is layered on top, as the carry formula already
layers it: the table says what a spot is worth, and the live reads (the keep
odds of getting there against the defence as it is) say how much of that this
option collects. B stays the extension to reach for if a spot-only value
misprices rushes against set defences, since the keep odds see the defenders
between here and there but not the ones waiting after.

### 2. Where do the numbers come from?

- **A. Counted from bot-vs-bot games**, as xT is counted from match events.
  Fast to get, but the values would bake in our own defending bots' habits
  (the standing rule: never fit bot planning to our own defenders), and the
  bots' play depends on the values, so the table chases itself.
- **B. Computed from the measured models.** Value iteration over the grid: from
  each cell the carrier can shoot (the shot field), pass to another cell (the
  lane and completion reads) or carry to a neighbour (the keep reads), each
  priced against a reference defence; a cell's value is what its best option is
  worth, repeated until the values settle. Every number traces to a measured
  model, as the shot field does.
- **C. B, checked against bot games**: B builds the table, and an instrument
  compares it with outcomes in bot play. It measures and never fits.

**Agreed: B**, as a decent approximation to build and then look at. The check
in C can come later if what we see calls for it. Published hockey work gives
something to look at it against:

- xT applied to NHL zone entries (LINHAC 2024), which also reads the defensive
  threat by mirroring the offensive values and negating them, as decision 6
  does;
- Routley and Schulte's Markov game model of NHL play-by-play (UAI 2015), which
  values actions by their effect on scoring with the context and the longer
  lookahead in.

Both are counted from real NHL events, so they are a check on the shape (where
the value rises, how flat the neutral zone is), never numbers to fit: our
skaters, rink and goalie are not the NHL's.

B's hard part is 2a.

#### 2a. Which defence are the moves priced against?

A spot-only table needs one defence per spot, and that defence decides most of
the numbers. Candidates:

- the worst case the keep reads were measured against (the interceptor that
  plays the carrier perfectly), placed by a rule from the spot;
- a defence that stands where a defence can physically get from a neutral
  start (reach-based, no coaching);
- our zone-coverage shape, which is our own defending bot again (rule above).

**Agreed to try: the real defence for the move being chosen, a set defence
in the table.** An option has two parts:

1. **Getting there**: the move the carrier is choosing now, priced against
   the real defenders where they are, on the worst-case reads the keep odds
   were measured on (the third candidate above, on real positions).
2. **What the spot is worth once he is there**: the table. The defenders will
   have moved by then, so it assumes a defence that has had time to set: the
   mode's defenders goal-side between the puck and the net, covering the
   lanes. The shot field makes the same assumption of the keeper ("a keeper
   who tracked the play").

The worry is that one move of real defence is much worse than two, where the
real defenders, projected forward, also price the move after arriving and the
table starts there (roughly what the next-line reads do today, and what they
cost). So the first build keeps the depth switchable, and the two are measured
against each other on the entry and breakout drills and the advantage
scenarios before either is kept.

Still open: the rule that places the set defence. The proposal is physical:
each defender where he blocks the most value and can still get there.

### 3. Does the carrier take the best option, or a mix?

Value iteration takes the **best** option from each cell, which is how the
carrier picks. Counted xT takes what players actually did. Recommended:
**best**, because B prices what the bots would do, not what they did.

### 4. The grid

The rink is 60 m × 26 m. At **2 m cells**, 30 × 13 cells, mirrored left to right
so that half are stored, with **bilinear interpolation** between cell centres,
so nearby spots the carrier compares read smoothly rather than in steps.
**Agreed: 2 m to start**, refined only where V changes fast (the slot). The
table is generated offline, as the shot field is, so the grid costs nothing in a
match; 2 m keeps the generation (every move from every cell, each against its
set defence) manageable.

### 5. Does time cost anything?

V is odds per possession: time is not in it. Today's compete also pays a
`delay_discount` per second. Options:

- drop the discount, and let time cost only what the defence does with it (the
  keep odds of a later move are worse because the defence has closed);
- keep it as a separate term.

**Agreed: drop it.** The discount is not a fact about the ice: it charges every
second the same whether the defence closes in it or not. V and the keep odds
together price what waiting really costs: the defence gets home, and the next
move's keep is worse. The thing to watch on the test families is a carrier who
dawdles when nobody is closing on him. That would be a real gap in the model
(something waiting costs that the keep odds do not see), to be named and added,
never a discount put back.

### 6. Turnovers

**Agreed.** A loss at spot L costs **V_them(L)**: their odds of scoring from
their possession at L, the same table read from their side. It replaces the
per-zone turnover table. This brings back a turnover cost in their zone (small,
since their V deep in their own end is small), but it is one cost of one shape
in every zone and both modes, which is the condition set for ever having one
there.

### 7. 3v3 and 5v5

**Separate tables**: the spacing and the numbers back differ too much to share
one. The shot term is the shot field's (the Hard goalie), as today.

### 8. How the bots read it

- **The carrier**: every option ends somewhere; its worth is the sum in "Why".
  A pass ends where the receiver catches it (completion × his V there); a carry
  ends at its rolled move's end; a shot is the shot field.
- **The defence**: the threat of their carrier is V at his spot; of a receiver,
  the lane × his V. The same table read from the attacking side, so offence and
  defence price a spot alike, as they price a shot alike today.
- **Stations**: where the lane to them × V is best.

### 9. Generation and checks

As the shot field is (`docs/shot-currency-plan.md`):

- a generator writes the table to a generated data file;
- a staleness test fails when the models it was built from change;
- a truth instrument compares V with outcomes in bot games.

### 10. Getting there

Build the table beside today's currency. Read it in the carrier first, then
compare the entry and breakout drills and the advantage scenarios between the
two. Move the defence and the stations over next, then retire the next-line
reads. Each step runs the default and slow tiers, the drills and the
benchmarks.

### 11. Testing: the behaviors, re-staged from scratch

Much of the bot suite stands on hand-placed fixtures: one exact staging per
behavior, some restaged to sit past a threshold, so a pass or a failure can say
more about the staging than about the bot. xT changes every value the bots read,
so it is the moment to re-ground the tests too.

- **Inventory first**: what each behavior-level test wants the bot to do, in one
  plain sentence, with how it is staged and what it asserts.
- **Re-stage each behavior from scratch** as a family of starts (positions,
  speeds, the defence's shape, varied over ranges, seeded so it replays), run as
  play in the duel harness where the behavior takes more than one decision, and
  assert a rate or a bound over the family, never one pick from one spot.
- **These families are the bench for xT**: the one-move against two-move
  comparison (2a), and today's currency against xT, are measured on them as well
  as on the drills.
- The hand-placed tests a family covers retire with it; the ones guarding a
  single physical fact (a reach, a clock) stay.

## Order of the talk

1, then 2 and 2a (they decide most of the rest), then 6, 5, 4, 7, 3, 8 to 11.
