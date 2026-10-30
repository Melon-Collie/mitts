class_name GoalieSaveRules

# Pure save resolution: what the puck does after it meets the goalie.
#
# It is a CONTACT, not a choice. The puck strikes a surface with a material and
# an orientation, and the rebound follows from the two — the same
# normal/tangential decomposition the blade deflect and the boards use
# (PuckCollisionRules.deflect_velocity_3d), through the real outward normal the
# swept-OBB test reports. There is no menu of save outcomes to pick from, no
# speed at which the model changes character, and no exit vector written down in
# advance.
#
# TWO THINGS ARE NOT CONTACTS, and both are the same kind of exception: they are
# things the goalie DOES rather than things his equipment is made of.
#
#   GLOVE CATCH  — a puck does not stop because leather is soft, it stops
#                  because he closes his hand on it. The only outcome that ENDS
#                  a play, so the whistle depends on it.
#   CHEST TRAP   — a shot into the chest of a squared goalie is a dead play: he
#                  smothers it against his body and it drops in front of him. It
#                  does NOT end the play here (the ruleset is deliberately
#                  low-stoppage — he does not cover for a whistle); it is the
#                  first beat of a two-beat sequence whose second beat is the
#                  crease sweep. See CHEST_TRAP_DROP_M_S, which is coupled to
#                  that sweep's window and has a test holding the pair together.
#
# Both are gated on `is_face_presented` and nothing else: what he can smother or
# catch is what he is looking at. A puck into his back is equipment, and
# equipment is a material.
#
# Deterministic (no randomness) so a client-predicted puck and the host agree
# before reconciliation.

# Which save surface the puck struck. Ordering is load-bearing: it indexes
# MATERIALS. MASK is separate from CHEST because they resolve oppositely — he
# smothers with his chest and he emphatically does not smother with his face.
enum SavePart { STICK, PAD, BLOCKER, CHEST, GLOVE, MASK }

# ── Materials ────────────────────────────────────────────────────────────────
# Two numbers per surface, flat, indexed by SavePart × STRIDE: the fraction of
# the frozen puck's rigid-wall COR the surface keeps (PuckRestitution.rigid_wall,
# so the speed falloff is the puck's own measured behaviour), and the Coulomb
# coefficient of the puck's rubber sliding on its facing
# (PuckCollisionRules.reflect_with_friction). A fraction above 1.0 would make gear
# livelier than a steel wall, which no gear is.
#
# Nothing has measured puck rebound off goalie gear, so THE ORDERINGS ARE THE
# PHYSICAL CLAIM, not the digits. Stiffest to softest: a composite paddle is the
# hardest thing on him; a blocker is a board behind thin foam; a leg pad is thick
# foam over a stiff core, built to absorb; a chest protector is foam over a
# torso that gives; and softest of all is a glove the hand did not close on,
# which is a floppy leather pocket. Grippiest to slickest: cloth tape on the
# blade; the glove's leather; the chest's jersey; the smooth synthetic facings
# of pads and blocker, slick as a painted shell. Move a row and you are
# asserting something about the equipment — keep the orders.
#
# The stick's grip is load-bearing: its faces lean back to ramp a shot up into
# him (~20° set, ~45° in the butterfly), and a puck that keeps its slide up them
# leaves at shot speed over the glass. Holding it on a face tilted α takes
# friction ≥ tan α / (1 + e).
const MAT_STRIDE: int = 2
const MAT_COR_SCALE: int = 0
const MAT_FRICTION: int = 1
const MATERIALS: Array[float] = [
	0.90, 0.80,   # STICK   — composite paddle under cloth tape
	0.55, 0.30,   # PAD     — thick foam over a stiff core, built to absorb
	0.80, 0.30,   # BLOCKER — a board behind thin foam
	0.25, 0.50,   # CHEST   — foam over a torso that gives with the shot
	0.20, 0.60,   # GLOVE   — softest of all: a leather pocket he did not close
	0.80, 0.30,   # MASK    — a hard painted shell with a head behind it
]

# How fast a trapped puck slides off the chest and onto the ice. NOT a rebound —
# his momentum is gone and this is the puck coming off a padded, forward-tilted
# face under gravity, which is why it is a walking pace and takes its DIRECTION
# from the contact normal rather than from any goalie-frame constant.
#
# IT IS COUPLED TO THE CREASE SWEEP, and that coupling is the whole reason the
# number matters. The sweep can only take a puck that is still within
# GoalieCreaseClear.reach after GoalieController.clear_dwell has elapsed, which
# measured out at roughly 2 m/s from a chest-save stand-off — above that the puck
# is out of his reach before the dwell completes and the second beat never fires,
# leaving the puck loose in the paint, which is the opposite of a dead play.
# test_a_trapped_chest_puck_is_still_there_for_the_sweep holds the pair together;
# do not raise this without reading it.
const CHEST_TRAP_DROP_M_S: float = 1.0


# Whole-contact result: the resolved velocity plus the two discrete flags saying
# which of the goalie's own acts produced it.
class ContactResult:
	var velocity: Vector3 = Vector3.ZERO
	var caught: bool = false    # glove catch — the goalie holds it, play stops
	# Chest smother — the shot is dead but the PLAY is not: the puck goes down in
	# front of him for the crease sweep to clear. The caller OWES this outcome a
	# position as well as a velocity — the puck belongs on the ice at the contact's
	# XZ, not at the contact point — see resolve_contact.
	var trapped: bool = false


# Resolve a puck-vs-goalie contact. `contact_normal` points out of the struck
# surface toward the puck (SweptDiscOBB's outward normal); `goalie_forward` is
# the direction he faces, used ONLY by the catch; `surface_velocity` is the
# struck part's own motion, used ONLY by the material rebound — what he catches
# and what he smothers are acts, and a moving hand does not change either.
# Fills a caller-owned result (no allocation). Deterministic, so a
# client-predicted puck and the host agree before reconciliation.
static func resolve_contact(
		incoming: Vector3, part: int, contact_normal: Vector3,
		result: ContactResult, goalie_forward: Vector3 = Vector3.ZERO,
		surface_velocity: Vector3 = Vector3.ZERO) -> void:
	var presented: bool = is_face_presented(contact_normal, goalie_forward)
	if part == SavePart.GLOVE and presented:
		# He closed his hand on it. Zero rather than a slow drift: the controller
		# pins the transform from the catch signal, which arrives on the next
		# frame's drain, and a puck still carrying pace crosses several
		# centimetres in between.
		result.velocity = Vector3.ZERO
		result.caught = true
		result.trapped = false
		return
	if part == SavePart.CHEST and presented:
		# Smothered. The shot's momentum is gone — none of it survives, which is
		# what makes this a dead play rather than a soft rebound — and the puck
		# slides off the face he trapped it against.
		#
		# THE CALLER MUST PUT IT ON THE ICE (see `trapped`). A trapped puck does
		# not free-fall from chest height through his own equipment: measured, it
		# picked up 2 m/s on the way down and landed on his own paddle, the
		# stiffest surface on him, which kicked it straight back out of the sweep's
		# window. He is holding it against his body and placing it down, and the
		# placement is as much a part of the act as the velocity is.
		result.velocity = trapped_drop_velocity(contact_normal)
		result.caught = false
		result.trapped = true
		return
	result.velocity = rebound_velocity(
			incoming, part, contact_normal, surface_velocity)
	result.caught = false
	result.trapped = false


# Where a smothered puck goes: off the face it was trapped against, at a walking
# pace, with no vertical of its own so gravity takes it to the ice from wherever
# on his chest the contact happened. Direction is the contact normal's HORIZONTAL
# part, so the puck leaves in front of him rather than on his skate line — a puck
# dropped dead on his own toes is one his next shuffle or stick swing shoves
# goalward, which is the "he beat himself off a chest save" own goal.
#
# A dead-vertical normal (a puck landing on top of his shoulders) has no
# horizontal to slide along, so it simply drops.
static func trapped_drop_velocity(contact_normal: Vector3) -> Vector3:
	var out := Vector3(contact_normal.x, 0.0, contact_normal.z)
	if out.length_squared() < 0.000001:
		return Vector3.ZERO
	return out.normalized() * CHEST_TRAP_DROP_M_S


# The rebound off `part`'s material, through the real contact normal. A
# separating puck comes back unchanged.
#
# `surface_velocity` is the struck part's own world velocity, and no part of a
# goalie is a static wall: he tracks a shot with the blocker and slides his whole
# body in and out, so the impact speed the material responds to is the RELATIVE
# one. Resolving in the surface's frame — subtract, reflect, add back — is what
# makes that true, and it degrades exactly to the static case when the part is
# still, so a fixture that offers no velocity gets today's numbers unchanged.
#
# Only the NORMAL component of the surface's motion enters: friction acts on the
# puck's slide against a still face, and a face moving along itself does not
# drag the puck with it. That would be a claim about a moving facing's grip
# that nothing here has measured.
#
# The consequence worth knowing at a call site: a puck at REST against an
# advancing face leaves at (1 + e) times the face's normal speed rather than
# sitting still while the collider walks through it, and a retreating face
# leaves it at rest rather than dragging it along.
static func rebound_velocity(
		incoming: Vector3, part: int, contact_normal: Vector3,
		surface_velocity: Vector3 = Vector3.ZERO) -> Vector3:
	var base: int = clampi(part, 0, SavePart.size() - 1) * MAT_STRIDE
	var n: Vector3 = contact_normal.normalized()
	var surface_normal_vel: Vector3 = n * surface_velocity.dot(n)
	return surface_normal_vel + PuckCollisionRules.deflect_velocity_3d(
			incoming - surface_normal_vel, contact_normal,
			MATERIALS[base + MAT_COR_SCALE],
			MATERIALS[base + MAT_FRICTION])


# His own gear's motion never carries a puck toward his own goal line. Of the
# contact's rebound off his moving gear (`moving`) against the same contact off
# that gear held still (`still`), the difference is his push; its part toward
# the goal line (`to_goal`, unit, along the rink's length) is taken off. What
# still gear does to a puck, a shot going in off a pad included, stands.
static func keep_out_of_own_net(still: Vector3, moving: Vector3, to_goal: Vector3) -> Vector3:
	var push: Vector3 = moving - still
	var toward: float = push.dot(to_goal)
	return still + (push - to_goal * toward if toward > 0.0 else push)


# The same for his gear pushed into a puck it overlaps: of the shove that
# frees the puck (`eject`), the part toward his goal line goes, so gear moving
# that way rides over a puck rather than walking it in.
static func eject_out_of_own_net(eject: Vector3, to_goal: Vector3) -> Vector3:
	var toward: float = eject.dot(to_goal)
	return eject - to_goal * toward if toward > 0.0 else eject


# Is the struck surface one the goalie is actually PRESENTING to the puck?
#
# `contact_normal` points outward, from the goalie's surface toward the puck, so
# a normal aligned with the direction he FACES was struck on his front, and one
# pointing behind him was struck on his back.
#
# Facing, not the net. Testing the normal against which side of him the net is on
# is wrong for exactly the plays that matter: a goalie tracking a wraparound or
# out playing a rim is turned, so the surface nearest his own goal can be the one
# his chest is pointed at, and the surface facing up-ice can be his shoulder.
# What he can catch is what he is looking at.
#
# It gates the CATCH and the TRAP, and nothing else — every other outcome is a
# contact. Closing a hand on a puck and smothering one against your chest are
# both things a goalie DOES, and he has to be facing it to do either; a puck into
# the back of his glove hand is leather, and leather is a material.
# Threshold-free: a face is presented or it is not, and a contact exactly side-on
# is not — you cannot catch with the edge of your hand either.
#
# A zero `goalie_forward` means the caller has no facing to offer, in which case
# every face counts as presented.
static func is_face_presented(contact_normal: Vector3, goalie_forward: Vector3) -> bool:
	if goalie_forward.length_squared() < 0.000001:
		return true
	return contact_normal.x * goalie_forward.x + contact_normal.z * goalie_forward.z > 0.0
