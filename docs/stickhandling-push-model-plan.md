# Stickhandling push model — motion-keyed blade contact

Status: IMPLEMENTED (`CarryContactRules` + `Skater._update_carry_contact`),
pending on-ice tuning. Follows the contact-point tell (#596,
`docs/elevation-rework-plan.md` §6.3), which seated the carried puck heel→toe
by loft level and added a shaft-angle toe drag; this model subsumes that toe
drag. Deltas from the plan as written:

- The update lives in `Skater._physics_process`, not the IK call site — it
  runs identically on local, AI, and remote skaters (the IK pipeline never
  touches a client-rendered remote), which delivered §5's remote parity
  directly instead of via a separate feed. Consequence: remote views now
  reconstruct the full blade-beside-puck arrangement (the forehand factor is
  no longer 0 on remotes; a peer flipping a beat off the owner is absorbed by
  the factor smoothing).
- The transit lift became a sin-envelope hop fired per face flip (a flip
  during a live hop rides it out) — the "complete each hop" option from trap
  #2, replacing (1 − |smoothed factor|) outright.
- `carry_side_switch_threshold` (the position-hysteresis export) is retired;
  the flip-speed threshold is the hysteresis.

## 1. The defect in the current model

Everything about the carried contact is keyed off **position** — which side of
the body the cursor sits on. `Skater.update_carry_side` picks the rendered
face by body side with hysteresis and never flips within a side; the toe-drag
roll keys off shaft steepness, which is a proxy for "cursor near the feet."

Real stickhandling is keyed off **motion**: the blade contacts the puck on the
side *opposite* where the puck is going, because that is the side you push
from. To move the puck left you push from its right; to bring it down-left
you push from up-right. Dangling in place on one body side alternates faces
every stroke — the tick-tock texture — which a position-keyed side can never
produce. The current model conflates two distinct facts:

- **body side** = where the puck is (position) — governs ROM, reach, which
  strokes are anatomically available;
- **contact face** = which side of the puck the blade is on (motion) — governs
  what the blade is visibly doing.

Today both are driven by position. The fix is to key the contact face (and
the stroke dressing) off the puck's velocity **in the carrier's frame** —
dangle velocity, not world velocity; you stickhandle relative to yourself
while gliding.

## 2. The decomposition

Let `v_rel` = blade-contact velocity minus the skater's body velocity
(world XZ). Decompose at the blade against two axes that already exist in
`get_carry_target_global`:

- `stick_dir` — the horizontal hand→contact direction (≈ body-outward),
- `face_normal` — its 90° Y-rotation (the blade's face axis).

**Face-normal component** (`v_perp = v_rel · face_normal`) — the side-to-side
stroke. The blade sits on the trailing side: contact-face target =
`−sign(v_perp)`, with a speed deadband and velocity-space hysteresis. This
*replaces* the body-side key as the side driver (working decision — see §7).

**Inward component** (`v_in = −(v_rel · stick_dir)`, positive = pulled toward
the body) — and this is why toe drags exist at all: the blade's faces point
sideways off the stick line, so **no face points back at the carrier**. A flat
blade physically cannot push the puck toward the body. The only way to create
a pulling surface is to roll the wrists so the toe curve hooks over the far
side of the puck. Inward motion therefore *forces* toe contact + closed-face
roll; the model produces the toe drag as a consequence instead of bolting it
on.

## 3. Stroke grammar

Chirality picks which inward diagonal gets which dressing. For a lefty
(blade on −X, forehand = left side); mirror everything for a righty:

| stroke (lefty) | contact face | seat | wrists |
|---|---|---|---|
| push out / lateral, either side | trailing face, per `v_perp` | mid-blade (elevation seat untouched) | square |
| pull in from the forehand side (down/right) | forehand face rolled over | slides toward the toe | full roll — **the toe drag** |
| pull in from the backhand side (down/left) | backhand face | heel-to-mid | mild cup — the backhand cradle (a backhand can't roll to a forehand hook) |
| at rest / below deadband | hold last side | unchanged | cupped — the cradle |

Camera note: from the gameplay camera's ~75° tilt, roll about the blade's
long axis barely reads (that axis points near the viewer). What does read from
overhead is the toe visibly curling in around the puck. Implemented as an
**axial twist about the hosel line** — the axis a real wrist roll actually
has — which produces that horizontal toe sweep (~7 cm at 20°) as a
consequence AND keeps the hosel tip (the point the shaft aims at) invariant,
so no dressing can kink the shaft→blade junction. An earlier heel-local yaw
term did the same sweep but bent the junction; it's gone.

## 4. What is kept, what is reworked

**Kept as-is:**
- The pin is sacred: cursor = puck, `get_carry_target_global` stays the
  authority, no push physics, no independent puck motion during carry.
- The elevation seat (`carry_contact_flat_u/high_u`) — that is *intent*, not
  stroke. Reworked after playtest (§7d): it is WIND-UP-ONLY and expressed by
  the blade mesh sliding around the frozen puck, never by the pin.
- The transit-lift mechanism (blade hops over the puck when the smoothed face
  factor crosses zero) — right mechanism, it just fires far more often once
  the side is motion-keyed.

**Reworked:**
- `update_carry_side` becomes the motion-keyed side tracker (deadband +
  velocity hysteresis instead of the position threshold).
- `get_toe_drag_factor` becomes the inward-pull grammar: composes the current
  positional read (shaft steep = stick tucked at the feet — still a legitimate
  drag posture) with the gestural read (`v_in` on the correct diagonal); all
  face-angle dressings ride one axial hosel-line twist (see §3 camera note).

**Where the code goes:** the stroke solver — (v_perp, v_in, current side,
handedness) → (face target, seat offset, twist) — is pure stateless math:
`domain/rules/` + GUT tests, per the project rule. `Skater` owns the smoothed
state and applies the solved targets; the IK coordinator feeds it, replacing
the `update_carry_side` call site.

## 5. Signal source and network posture

`Skater.blade_world_velocity` is already computed each tick on **every peer**
from the replicated (and, on remotes, interpolated) blade marker — so
`blade_world_velocity − skater.velocity` gives every machine the same `v_rel`
with **no new wire field**, the same posture as the contact-point tell. It is
one tick stale relative to the current tick's IK; irrelevant for a smoothed
cosmetic.

Reconcile: the side/seat state is cosmetic and replay-tolerant, exactly like
today's carry side — replay recomputes it from replayed blade motion; drift
across a snap is absorbed by the smoothing.

Hot path: value-type math only, a few floats of state on `Skater`, no
allocation — same budget as the code it replaces.

## 6. Traps (known going in)

1. **Deadband is the cradle, not an edge case.** Below the stroke threshold
   there is no motion to key off; hold the last side, cupped. Without a real
   deadband the side flips on interpolation noise at rest.
2. **Fast alternation vs the transit lift.** The lift peaks when the smoothed
   factor is mid-flip; under a fast dangle the factor lives near zero and the
   blade would hover permanently instead of hopping per stroke. Needs
   flip-rate awareness (scale lift by time-since-flip, or complete each hop
   before honoring the next flip).
3. **Rest-side feel changes.** Replacing the position key alters how the
   forehand/backhand carry reads when *not* stroking. Playtest checkpoint —
   the deadband cradle should preserve it, but that's a judgment call on ice.
4. **Blade marker vs mesh.** The face-side offset moves the blade *marker*
   (as today, ±`carry_blade_offset`); the twist dressing moves the *mesh
   only* — never the marker the contact math reads.

## 7. Open decisions

- **Replace vs compose** the body-side key: working decision is *replace*
  (body side keeps governing ROM/reach/dressing availability only). Revisit
  after the first on-ice pass if the rest carry feels wrong.
- Whether the elevation chevrons shrink/retire stays parked with the
  contact-point tell playtest (elevation plan §6.3).

## 7b. Wrister address (follow-up, implemented)

The freeze at LMB-down used to fossilize whatever carry side was live, so a
backhand-frozen pose could wind a forehand shot — the pose lied. During
WRISTER_AIM the controller now pushes the live aim line (`_wrister_aim_dir` —
origin→cursor for humans, the committed direction for bots) onto the skater
each tick, and the blade addresses the **trailing side of that line** — the
push model applied to the shot itself, decided by the same
`CarryContactRules.stroke_side` rule strokes use (aim·face_normal as the
stroke, `wrister_address_commit_dot` as the hysteresis so a near-parallel aim
holds instead of flickering). An address factor eases toward the committed
side and the delta to the live carry factor slides the blade **mesh** along
the face-normal axis (marker local +X), with the transit hop firing on the
crossing.

First cut keyed the side off the swing-chirality *label* mapped to the
body-relative carry arrangement — wrong whenever the label's natural pose
disagreed with where the aim line actually sat (the "wrong handedness on some
shots" report). Geometric trailing-side is handedness-free and cannot land on
the wrong side of the puck. (The release's hand is no longer a swing read at
all — it comes from where the puck sits against the aim, `WristerLoad`.)

Mesh-only by design: the marker, pin, release spawn, and the pinned aim
origin are untouched (`wrister_origin_world` is load-bearing for the
gamepad's shot-cursor anchor and the wrist shot's load, so it must not
move). On aim exit the address becomes the real carry side, so there is no
pop.

**Replicated (v56):** render-only remotes can't derive the side (no aim
line; the replicated torso coil is a scaled+clamped encoding that can't be
inverted without the shooter's controller tunables), so the host's committed
side rides the movement-intent byte's spare bit 7 — validity implicit in
`shot_state == WRISTER_AIM`. `RemoteController` pushes it via
`Skater.apply_wire_blade_side`, and the skater's address pass adopts it through
the same crossing/hop detection as the derived path, so a spectated
shooter's blade re-addresses exactly as the shooter sees it. This makes the
address a real defensive tell: every peer — goalie, bots, and human
defenders alike — reads the wind-up side before the release.

## 7c. Catch/release blade geometry (follow-up, implemented)

The last visible untruth was the space *between* strokes: a real dangle is
push → the blade hops over → the far face receives, and each contact has a
place on the blade — every push leaves **off the toe** (the toe is the last
point of contact of any stroke), and the far face lands **heel-first** and
rolls the puck back out to the carry seat.

Told entirely on the blade-mesh channel the wrister address established —
the cursor = puck binding is untouched, no coast, no free-flight physics,
zero gameplay surface:

- **Stroke toe ride** — the mesh slides heel-ward with `|v_perp|` (ramping
  over [`carry_flip_speed`, `carry_stroke_full_speed`]), seating the puck
  toward the toe through a hard push. Flips only fire mid-stroke, so every
  release leaves off the toe by construction — no future knowledge needed.
- **Extended hop** — `carry_transit_hop_time` 0.18 → 0.24 s: the blade
  crosses at the same speed but hangs, the readable gap between touches.
- **Heel catch** — when a hop lands while carrying, a transient slides the
  mesh toe-ward (heel at the puck) and decays at `carry_catch_decay`,
  rolling the puck back to the seat. Fires on stroke flips and wrister
  re-address landings alike.

The full one-sided contact model (puck coasting between touches, catches
where geometry says, the pokeable free window) would renegotiate the pin, and
the pin is sacred. §7e draws its look on the blade mesh instead.

## 7d. Playtest rework: the pin never carries a seat

First on-ice pass verdict: any seat term on the PIN moves the puck off the
cursor while stickhandling, which fights the mouse binding — and after the
address (§7b) and the catch/release prosody (§7c) proved the blade-mesh
channel, pin seats were also inconsistent with how every other tell is
told. Reworked: `get_carry_target_global` carries no along-blade term at
all (cursor = puck is exact during carry), the drag/cradle pin-seat slides
are gone (`carry_contact_drag_u`/`_cradle_u` retired — the drag keeps its
roll + toe-curl twist, the cradle its cup), and the elevation seat lives
only in the wrister wind-up, as a mesh slide seating the frozen puck
heel→toe per the level (`_aim_seat_offset_u`, eased in/out of WRISTER_AIM).
That is where the read matters — a committed shooter — and where the goalie
pre-arm will consume it.

## 7e. The release (implemented)

Keyed off velocity alone, a hard dangle pushed the puck the whole width of
every sweep and flipped faces at the turnarounds, where the puck is slowest:
the blade never let go of it. A face can only push the puck away from itself,
so contact is really keyed off FORCE — and a sweep's force is at its ends,
not its middle. `CarryStrokeState` reads that from the puck's filtered
velocity and its rate of change; a peer drawing someone else's carry takes the
side off the wire (v82) rather than differentiating an interpolated pin:

- **Push**: the puck gaining speed off the trailing face.
- **Release**: a push that peaked above `carry_release_speed`, has lost
  `carry_release_drop` of it, and is slowing fast enough to stop within
  `carry_release_stop_s`: the puck is turning round. The blade goes over the
  puck to the far face while it runs free. A sweep one way that only eases
  off — a hand's uneven pace round the body — never stops, so it keeps its
  face and the next surge is the same push (without the stop term it cost
  8–11 face changes in 3 s).
- **Catch**: the puck coming at the leading face while slowing; its turn is
  the throw, which is the next push. Speeding up toward the leading face by
  `carry_repush_margin` is a second push the same way, which sends the blade
  back to trail it.
- A stroke under the release speed keeps the plain flip, so slow carries and
  pull-acrosses are unchanged.
- **A wobble is not a stroke.** A hand on a mouse is never still, and the
  blade's inertia turns a cursor that moves on alternate ticks (60 fps against
  the 120 Hz tick) into a speed that dips on them. Keyed off raw speed, either
  one cost 4–7 face changes a stroke. So the speed is read through a
  `carry_stroke_smoothing_s` filter, a release waits for a real drop rather
  than a pause, a repush needs `carry_repush_margin`, and no face changes
  until the puck has gone `carry_flip_distance` the new way. All in seconds,
  metres and shares, so it reads the same at any frame rate.

The release hop lands as the free puck stops — its speed at the release over
the rate it has been slowing since the peak (`CarryStrokeState.stop_in_s`) —
so the far face is there to catch it however late the release was read; it
drives the side factor itself, holding
the old face for `carry_release_lead_frac` while the puck runs off it and
crossing at the top of the hop, so the blade never passes through the puck.
Through the hop the mesh stands off the puck by `carry_free_gap` (as hard as
the stroke), and the landing closes it — the catch. The stroke is read off
the pin's velocity, not the blade marker's, which carries the face flip's own
travel. Mesh-only like everything else here: the marker keeps
`carry_blade_offset` and the pin stays at the cursor.
`test_carry_stroke_state.gd`, `test_dangle_lets_the_puck_go.gd`.

**Replicated (v82).** A client drawing someone else's carry must not decide
the side: the wire's blade was placed with the host's side, and the client's
pin subtracts its own, so wherever the two differ the pin moves up to twice
`carry_blade_offset`, which reads as a stroke and flips again — measured at
about two face changes a stroke on a wobbly sweep, the remote's puck up to
15 cm off the host's. So the host's carry side rides the blade-side bit (the
wrister address's, valid by state) and the client takes it
(`Skater.apply_wire_blade_side`); it still reads the stroke
(`CarryStrokeState.observe`) to tell whether a flip it was told of was a
release, and sizes that hop the same way. A side not restaged within a tick
lapses, so the local skater decides its own again after a goal replay.
`test_remote_carry_follows_the_host.gd`.

## 7f. Playtest: the puck on the cursor, the blade on the puck (implemented)

Two offsets survived §7d. The solve places the Blade marker, which is the
heel, on the cursor's target, but the puck pins to mid-blade, so a carried puck
sat half a blade (15 cm) out along the stick from the cursor: pulled in to the
feet it stopped short, "caught, not going all the way back". The target now
steps half a blade back along the shoulder's aim line
(`SkaterIKCoordinator._blade_target_for`), which puts mid-blade, and the puck,
on the cursor; at the rim the heel clamps where it did, so reach is unchanged.
The empty stick does the same, so a pickup, a poke and a reception are aimed
with the spot the puck is then carried on.

And the drawn blade only met the puck for a square, flat blade. Pulled in, the
shaft steepens, the toe stands on the ice with the heel up to 17 cm off it, and
the toe drag rolls the wrists; the puck, at mid-blade, sat under blade that was
in the air, up to 5 cm off its face. The mesh now has a **carry seat**
(`Skater._seat_on_puck`): the part of the blade within a puck's height of the
ice is found from the dressed pose, and the blade slides so the middle of that
part rests against the puck's rim, every other mesh slide laid on from there.
Flat, that is mid-blade, as before; in tight the toe holds the puck, which is
the toe drag the table in §3 describes. A heel slid across re-aims the blade at
the hand, so the slide across is divided by the lever the seat has on the heel.
Faded by the side factor through a face change, off under the slapshot pin.
`test_carry_blade_rests_on_puck.gd` holds both.

## 8. What this buys

The blade side telegraphs the next stroke — a defender watching the carrier
sees the blade wind up on the side it is about to push from, before the puck
moves. Same deception axis as the contact-point tell: the read is real, and a
good dangler beats it by changing late. The whole blade becomes legible.

## 9. Tests

- GUT for the stroke solver: face target per quadrant of (v_perp, v_in) ×
  handedness, deadband hold, hysteresis (no flip-flop straddling the
  threshold), dressing clamps.
- Nothing mechanical beyond that — seat/twist are cosmetic; carry/release
  feel verified in a local session. The release-origin invariant (mid-blade,
  position-free trajectory) is untouched by construction.
