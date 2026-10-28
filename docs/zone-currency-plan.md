# Zone currency — what a carrier is trying to do depends on where he is

Status: **agreed design (in chat); steps 1–3 built.** The CLAUDE.md workflow applies:
this doc is the plan, deviations get discussed first.

## Why

Every option a carrier weighs is priced in one currency today: the odds of
scoring. Outside their zone that is a long chain — get in, then score — whose
far end is weak (about 0.04 against a set defence), so the whole neutral zone
reads flat and a pass back wins near-ties on noise (`docs/grounding-plan.md`,
"The temporal audit"). The user's framing: outside their zone, THE goal is to
get in with the puck — nothing offensive happens until you are in; in our own
zone it is to get out with it.

## Decisions

The currency is set by where the **decider** is (the carrier, for his own
compete). Each zone's goal is reaching the next zone with the puck; nothing is
worth more there, so what being in the next zone is worth multiplies every
option alike and cancels — no floor, nothing measured.

| Decider in | Currency | A turnover at L costs |
|---|---|---|
| Their zone | Scoring odds (today's) | P(they get out of their zone with it) from L × one entry in scoring odds (the mean crossing on empty ice, the neutral zone's unit) — the entry their exit takes back |
| Neutral zone | P(we get into their zone with the puck) | P(they get into our zone with it) from L |
| Our zone | P(we get out with the puck) | Their scoring odds from L ÷ their scoring odds from an ordinary entry — "how many entries that turnover hands them" |

- Our entry and their entry, our exit and their entry, and our entry and their
  exit are weighed one for one: the one symmetry the scheme assumes. A loss is
  always the other side's gain, never credited back by the odds they fail to
  make it.
- An option that ends past the decider's next line has reached the goal: worth
  its keep odds. One that ends behind it (a pass back into our zone from the
  neutral zone) is the chain: P(out) × P(in from where it gets out).
- Shots outside their zone are dead and are not a currency there. There is no
  empty net in the game.
- Their counter after they get out stays the 5v5 counter-exposure cost, in their
  zone only (elsewhere the turnover cost already is their entry).
- Every probability comes from the physical reads already in place: the keep
  along the skate (reach model), the line contest, completion and bobble, the
  projected defence.
- Tie-breaks between options with about the same odds (an entry that leaves us
  better placed in the zone; an exit better placed to get in) are a later step,
  within the decision hysteresis margin. First version: probability alone.
- The defence reads mirror the attack: a defender in the neutral zone acts to
  stop the entry, in our zone to stop the shot.

## Build order

1. **`AIPossessionValue`**: the next-line probability beside today's scoring
   read — crossings at whichever blue line is next for the man (the exit is our
   blue line, read with the same skate and line contest as an entry), and the
   chain for a man behind it.
2. **The carrier's compete** (`AICarrierField`): the currency set at `fill` from
   the carrier's zone; `horizon_value` / `value_at` answer in it; the turnover
   cost per the table; counter exposure in their zone only.
3. **The stations and the defence reads** (`AIRoleReads.attack_possession` /
   `defence_possession`, the threat reads): the same currency rule — the
   decider is whoever plays the puck for the side (their carrier for the
   defence, ours for a station).
4. **The in-zone model** (`docs/grounding-plan.md` step 2): one read of being in
   their zone at every horizon — the shot on arrival at pace, drives at several
   headings credited to where each is first covered, the pass to the open man.
   It is what their-zone scoring odds, the our-zone loss ratio and the tie-breaks
   read.
5. **The tie-breaks.**

The in-zone model was proposed first; the currency goes first because it is
what makes a carrier go for the zone, and the in-zone model only sharpens
numbers inside it.

Each step: default and slow tiers, the entry and breakout drills, the
benchmarks; snapshot moves reviewed and named in the commit.
