# Stick settling — the range between a clean catch and a deflect

Status: **Phases 1–3 built, awaiting playtest.**

As built, these differ from the design below:
- Phase 1: the settle's held blade holds its reach *target* in the skater's
  frame (`hold_seat`), not the wrister freeze's re-read of the solved blade,
  which walks outward in tight.
- Phase 2: the settle is priced at the any-angle ceiling: in the duel
  harness's reception sweep, bot catches arrive with a mean blade alignment of
  0.2–0.4. A softer pace is only priced where its flight fits `PASS_LEAD_MAX_S`,
  which Phase 3 raised to 1.0 s (with the finisher's feed horizon).
- Phase 3: the bobble is decided by load and by where on the blade the puck
  lands — read off where its path crosses the blade's line, end-on counting as
  the edge (decided: the blade position, not a probability). The bobbler is
  locked out for the full `settle_max_s`, not the 0.12 s deflect-bobble
  cooldown: measured, a 0.12 s bobble was regathered in ~0.13 s, cheaper than
  holding the catch, and bots priced it that way and fired hard on purpose.

## Decisions banked

- **A hard catch costs time.** A reception the hands only just absorb leaves the
  receiver *settling*: they have the puck, but can't act with it until the
  window ends. The window grows with how hard the catch was.
- **Settling locks every on-puck action.** No wrister, no slapshot, no quick
  pass, no nudge, and no stickhandling: the blade holds the puck at its seat.
  Skating is untouched. The lock is meant to be obvious, not subtle.
- **One-timers are exempt by construction.** The lock lives in
  `SKATING_WITH_PUCK` only. A pickup into a held slap charge never enters that
  state, so "one-time it or eat the settle" is the decision a hard feed offers.
- **No randomness.** The window is a pure function of the contact — relative
  speed, blade angle, blade curve — like the catch decision itself. Identical
  contacts settle identically.
- **Settle ships first, bobble later.** Phase 1 adds no new loose-puck outcome.
  Catch/deflect stays exactly where it is today.
- **Bot passes get softer** (Phase 2), priced rather than retuned: the settle a
  hard feed costs the receiver goes into the passer's valuation.
- **A press during the settle is queued**, not dropped. It fires on the first
  unlocked input.
- **The pickup sound scales with arrival speed**, so a hard catch is heard as
  well as seen.
- **The human quick pass is left alone.** It is due to be removed, so it keeps
  its flat 14 m/s until then.

## Why — the data

Today a catch is binary: under the ceiling (22 m/s receiver-relative at any
angle, 30 m/s squared) it is clean and the receiver can release on the next
tick; above it, it deflects. The only trace of a hard catch is the cosmetic
reception cushion.

Yu, Boucher, Bornn & Javan, *Playing Fast Not Loose* (Sloan 2019), Figure 9,
measured ~0.5 M even-strength NHL passes (2017-18, Sportlogiq). A *failed*
reception is one where the puck touched the receiver's blade but possession was
not gained. Bar heights, read off the figure (±1 ft/s), world frame:

| Pass type | Received (m/s) | Failed (m/s) |
|---|---|---|
| d2d | 10.7 | 13.4 |
| rush | 10.5 | 14.5 |
| north | 11.0 | 14.3 |
| south | 11.7 | 14.0 |
| ozentry | 12.5 | 16.5 |
| outlet | 14.5 | 18.3 |
| slot | 16.6 | 16.8 |
| ozstretch | 17.2 | 22.4 |
| eastwest | 18.0 | 20.4 |
| stretch | 20.4 | 21.9 |

What it says for the model:

- **Real failures sit below our ceiling.** Failed receptions average 13–22 m/s;
  every one of those is a clean catch in the game today.
- **Failure is a gradient.** The received/failed means sit 2–5 m/s apart, so the
  distributions overlap heavily. Here, blade angle and the receiver's skating
  supply that spread.
- **Slot is the exception** — equal means, so slot failures come from traffic,
  not pace. Settling is not expected to explain them.
- **Pace scales with distance.** Short passes ~11 m/s, long ones 17–20.

Limits: means only (no spread, no per-speed failure rate), and world frame. A
stretch pass to a receiver skating away arrives much softer in their frame, so
the long-pass rows overstate reception difficulty; the short-pass rows are close
to receiver-relative. Soccer research (first-to-second-touch interval as the
measure of control; Tsukuba 2026 on first-touch rebound vs. receive-to-pass
time) supports "settle time" as a real, measurable consequence of the first
touch. No hockey source measures settle duration, so the duration is feel.

## Phase 1 — the settle lock

### The rule

`PuckReceptionRules.reception_load(puck_velocity, receiver_velocity,
blade_normal, deflect_min_speed, alignment_bonus) -> float`: the share of the
blade's catch capacity this contact uses, `(relative_speed / threshold)²`, where
`threshold` is exactly the one `should_receive` builds (deflect floor plus the
squared-blade bonus, both already scaled by `reception_ceiling_mult` at the call
sites). Squared because the hands soak energy (½mv² over the give), which is the
model the 22/30 thresholds are calibrated on. `should_receive` is rewritten on
top of it (`load < 1`, or under `pickup_max_speed`), so the catch and the settle
cannot disagree about the threshold.

`PuckReceptionRules.settle_time(load, clean_load, max_s) -> float`: zero up to
`clean_load`, then linear in load to `max_s` at the ceiling. Starting values,
both feel tunables on `Puck` beside the reception thresholds:

| | value | poorly angled blade (ceiling 22) | squared blade (ceiling 30) |
|---|---|---|---|
| `settle_clean_load` | 0.30 | clean to ~12 m/s | clean to ~16.4 m/s |
| `settle_max_s` | 0.40 | 18 m/s → 0.21 s; 21 m/s → 0.35 s | 24 m/s → 0.20 s |

A 14 m/s quick pass to a standing receiver on a poorly angled blade settles for
about 0.06 s, and is clean when squared. The 12 m/s clean edge sits at the top
of the short-pass received means.

### Where the window is decided: the host, once

The host computes the window at each grant site from the same relative velocity
the catch decision judged:

- present-time catch: `PuckController._check_interactions` (the `relative_vel`
  already built for `should_receive`)
- lag-comp claim: `PickupClaimResolver` (the *rewound* relative velocity at
  `pickup_claim_resolver.gd:353`), passed into `apply_lag_comp_pickup`
- scripted tutorial grants: no settle

The window becomes an **absolute deadline in input-stamp time**:
`settle_until = grant_time + lag_grace + settle_time`. `lag_grace` is the same
offset the one-timer window uses (`ShotReleaseRules.one_timer_window_grace`,
via `one_timer_window_lag_grace()`): zero for the host's own player and bots,
one-way trip plus input lead for a remote client. The deadline travels with the
grant, through `puck_picked_up_by` → `GameManager._on_server_puck_picked_up_by`
→ `controller.on_puck_picked_up_network(settle_until)`.

Why a deadline and not a duration: both the host and the client gate *each
input* against `input.host_timestamp < settle_until`. The host replays the
client's inputs at their own stamps, so the two sides make the same decision on
every input, whatever the latency. A duration would start on each side at a
different stamp. If the host's lock ended first, the host would act on a press
the client swallowed and reconcile would yank the client into a wind-up. If it
ended last, the host would eat a shot the client predicted. With a shared
deadline neither can happen, and the lock needs **no reconcile save/restore**:
it is a comparison, not a timer the replay ticks.

### The wire

`SnapshotEventLog`'s `PICKED_UP` record already has an unused s32 `arg`. It
carries `settle_until` in milliseconds of host time (session-relative, so s32
lasts 24 days). The reliable backstop `notify_puck_picked_up(event_seq)` gains
the same parameter, and the snapshot dispatch branch passes `arg` through,
following `send_puck_stolen` / `notify_puck_stolen(event_seq, forced_lift_ms)`.
`local_puck_pickup_confirmed` carries it to `on_local_player_picked_up_puck`.
The RPC signature changes, so `PROTOCOL_VERSION` is bumped. Other clients get
nothing new: a settling carrier's held blade is already in the replicated pose.

### The gate

`SkaterController` holds `settle_until: float`, written only by
`on_puck_picked_up_network`, and cleared by `teleport_to` and on losing the
puck. Every controller (Local, AI, Remote, and the reconcile replay) funnels
through `_process_input`, so one gate covers all of them:

- `_state_skating_with_puck` (`skater_state_machine.gd:161`): while settling,
  the blade runs `apply_blade_from_mouse(..., hold_blade = true)` — the same
  freeze `WRISTER_AIM` uses, so the puck stays pinned at the seat — and the
  quick pass, wrister, and slap entries are skipped.
- The nudge in `_process_input` (`skater_controller.gd:1681`) is skipped.

**A press inside the window is queued.** Every entry fires on a rising edge, so
without a queue a press made during the settle would never fire, even if held.
The gate records the latest wrister, slap, quick pass, or nudge press seen while
settling, and the first unlocked input dispatches it as if pressed on that
input. From there the button's real state takes over: still held, the wind-up
proceeds normally; already released, a wrister or slapper releases at once at
its minimum charge (a queued tap is a quick touch, not a full shot). A later
press replaces an earlier one. Both sides read the same input stream, so the
queue is deterministic — but unlike the deadline it is state the replay
evolves, so it joins the shot-state fields `LocalController` saves and restores
around a reconcile.

### The tell

The reception cushion becomes the settle. Its amplitude today is `(v / 22)²`
against a fixed 22 m/s; it becomes the same reception load (the receiver's own
ceiling), and its return to the seat is timed to land on the deadline. The blade
visibly comes home at the moment the receiver can act — a diegetic tell, like
the loft seat, that a defender can read. Observers fire the cushion from their
own estimate of the arrival, as they do today, so theirs is approximate.

The pickup sound (`Sound.PUCK_PICKUP`, played at a fixed 0 dB from
`GameManager._on_local_pickup_sound` and `_on_remote_carrier_sound`) takes the
same arrival speed — receiver-relative, the number the cushion reads — as
situational gain. `SoundManager.reception_volume_db(speed)` mirrors
`shot_volume_db`: amplitude linear in speed, 0 dB at the 22 m/s ceiling, with a
floor so a walking-pace pickup is still audible. A hard catch plays at today's
level and a soft one plays quieter; if the cue then sits too low in the mix
overall, its `_MIX_DB` level comes up, never the call site. The speed is
recorded on the host's `puck_pickup` replay event, and `ReplayEventReplayer`
plays it back through the same helper.

### Bots obey (in Phase 1)

Without this, bots under the lock press into a dead gate and burn their
`_intent_max_wait_ticks` timeout. Bots run on the host, so they read the
controller's deadline directly; nothing is replicated for them.

- `RoleContext` gets `self_settle_s` (time left), beside `self_stagger_timer`.
- `AIRoleCarrier` treats it like stagger (`carrier.gd:695`): carry, don't start
  a release.
- The state machine doesn't latch a press while settling
  (`skater_agent_state_machine.gd:1680-1694`).

### Tests

- `test_puck_reception_rules.gd`: `reception_load` matches the existing threshold
  (`should_receive` ⇔ load < 1 above `pickup_max_speed`); `settle_time` is zero
  at or below `clean_load` and monotonic up to `max_s`; a squared blade settles
  shorter than a poorly angled one at the same speed; `reception_ceiling_mult`
  scales the load.
- Controller: while settling, quick pass, wrister, slap, and nudge don't fire and
  the blade holds; a press inside the window fires on the first unlocked input
  (held → normal wind-up, released → minimum-charge release); a later press
  replaces an earlier one; a pickup into a held slap charge is unaffected.
- Reconcile: a queued press survives a replay across the deadline.
- `reception_volume_db`: 0 dB at the ceiling, monotonic, clamped to its floor.
- Determinism: the same input stream against the same deadline gives the same
  actions on a host-side `RemoteController` and a `LocalController`.
- Wire: `PICKED_UP.arg` round-trips through both the snapshot block and the
  reliable RPC.
- Check the ratchets. `skater_controller.gd` and `puck_controller.gd` are
  probably grandfathered at their size, so the gate wants to live in a
  collaborator, or the entry bump is deliberate and visible in the diff.

### Playtest checklist (user)

- A hard feed to a standing receiver: the blade visibly gives and comes home,
  and LMB, RMB, pass, and Q do nothing until it does.
- The same feed, received with the blade squared or skating with the pass:
  shorter or no settle.
- Hold LMB through the settle: the wrister starts as the blade comes home.
- Tap pass during the settle: the pass goes as the blade comes home.
- A soft pickup sounds quieter than a hard catch.
- One-timer a hard feed: no settle.
- Online against a remote host: no shot fires that wasn't pressed, and none
  gets eaten.

## Phase 2 — bots pass softer

The bot feed is one constant, `AIPuckLane.PASS_TARGET_CLOSING_M_S` = 20 m/s
receiver-relative (×0.75 / 0.85 / 1.0 by tier). That is above every received
mean except stretch passes, so with Phase 1 in place nearly every bot pass
settles.

**Price it, don't retune it.** Search a short pace ladder per receiver, the way
`AIRimPass` already does (`PACE_FRACS`, softest within `RIM_SOFT_SHARE` of the
best). Each pace is valued through the existing `_pass_variant_ev`, with the
settle the receiver pays at that arrival speed added to `receiver_release_t`
(`carrier_pass_search.gd:388`, `:642`) and to the reception-pressure horizon
(`:476`). A harder pass then costs the receiver time, a softer one costs lane
exposure and goalie time, and the pick should land near the measured distance
curve without being tuned to it. Fallback, if the ladder costs too much per
tick: a fitted target-vs-distance table — keeping in mind that the data is world
frame while the solve targets receiver-relative speed.

Changes that must come with it:

- `RECEIVE_TRIGGER_PUCK_SPEED_M_S` = 14 (`skater_agent_reception.gd:15`, and the
  one-timer reads in `skater_agent_one_timer.gd`) drops to about 8–9.
  Otherwise softer passes stop counting as incoming and become loose-puck races.
- `PASS_LEAD_MAX_S` = 0.6 s caps the lead at ~6.5 m of flight at 11 m/s; it
  rises or follows flight time.
- The 10 m/s floor (`DEFAULT_WRISTER_POWER_MIN_M_S`) is rechecked against the
  short-pass means.
- `expected_pass_speed` (the defensive threat model across the role behaviors)
  stays on the same function as the fired pass.
- The tests that pin 20 m/s (`test_ai_action_scoring.gd:543-678`,
  `test_role_carrier.gd:351-357`, `test_bot_mirrors.gd:40-43`,
  `test_skater_agent_state_machine.gd:1212`, `:1507`, the slow-tier
  `test_pass_reception_catch.gd`) become property tests. The role snapshot
  tables will move.
- AI changes run the benchmarks before and after (per-tick p95/max, per-call
  evaluator ranking); the pace ladder multiplies pass-search calls.

The full checklist for where bot perception and decisions plug in is
`Scripts/domain/ai/DECISIONS.md`. The settle entries are added there.

## Phase 3 — near-miss bobble (as built)

Past the bobble line the catch fails softly. The line is `bobble_load` (0.67)
at the middle of the blade, less `bobble_edge_share` (0.4) of it at the toe or
heel, quadratic between (`PuckReceptionRules.bobble_load_at`): ~18 m/s on a
poorly angled blade at the middle, ~14 at the edge — the spread of the NHL
failed-reception means. Where on the blade is read off where the puck's path
crosses the blade's line in the receiver's frame (`blade_contact_offset`); a
path within ~11.5° of the blade's own line comes in end-on, at the edge. The
contact point at pickup is useless for this: the sweep registers at the rim of
the 0.5 m pickup radius, twice the blade's length across.

The face takes the impact as a deflect does, in the receiver's frame, but the
cupped face keeps only `bobble_tangential_retain` (0.35) of the glance and the
hands let `bobble_pace_retain` (0.45) of the result through
(`PuckCollisionRules.bobble_velocity`): ~2.5 m/s relative to him, mostly off
the face's normal, hopping by its into-face speed (`bobble_lift_*`). He is locked out of it for `settle_max_s`; anyone else
can take it. All three host verdict paths run it. Bots price it as the
receiver's expected hold (`AIFeedReception.reception_hold_s`: the settle by the odds
of a catch, the lockout by the odds of a bobble, from the measured split of
middle and edge contacts) in the reception read and the time discount, and the
duel harness mirrors it.

## Open questions

- **Queued charged shots.** A wrister or slapper tapped and released during the
  settle fires at minimum charge on unlock. If that reads as a misfire, a
  released charged-shot press could cancel instead of firing (the quick pass
  and nudge still queue).
