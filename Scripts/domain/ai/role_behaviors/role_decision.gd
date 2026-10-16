class_name RoleDecision
extends RefCounted

# Output of a role-behavior decide() function: the state machine steers and
# aims from it. Fire decisions are not here — the carrier owns its own intent.

# Where steering should aim. For off-puck roles this is the move target;
# for CARRIER it's the chosen carry destination.
var target_position: Vector3 = Vector3.ZERO

# How fast `target_position` is itself moving, world m/s; ZERO = a spot on the
# ice. The STAND's velocity, not the man's. Never publish one for a "hold where
# you are" fallback: a ride has no terminating condition, so it would match his
# velocity forever. See Scripts/domain/ai/CLAUDE.md → "A defensive stand is a
# moving frame".
var target_velocity: Vector3 = Vector3.ZERO

# Where a ridden retreat ends: the route never commands speed toward
# `retreat_floor_center` it could not shed before the circle of
# `retreat_floor_radius_m` (0 = no floor), or a stand riding a man toward our
# net would carry the body into the crease.
var retreat_floor_center: Vector3 = Vector3.ZERO
var retreat_floor_radius_m: float = 0.0

# The other side of the same route: most speed, m/s, a stand riding a man may
# command AWAY from `retreat_floor_center` (INF = no cap). Read only with a floor.
var advance_cap_m_s: float = INF

# Optional aim override: `aim_world_pos` replaces the state machine's default
# mouse target (the ready-stance look-at toward `target_position`). Used by
# FINISHER's tip path to point the blade at the goal during a deflection.
var aim_world_pos: Vector3 = Vector3.ZERO
var has_aim_override: bool = false

# Raise the blade off the ice (stick_lift_held) this tick, so it can reach an
# airborne puck. Off-puck only — the controller ignores voluntary lifts while
# carrying — and consumed by the state machine's OFF_PUCK handler.
var lift_blade: bool = false

# Off-puck one-timer readiness — camped at the staging spot, pre-aimed at the
# open net. The state machine forwards it to TeamBrain so the carrier can reward
# the pass, and gates the ONE_TIMER_PRESSED transition on it.
var is_one_timer_ready: bool = false

# Body-check commit: `target_position` is the body intercept, and the state
# machine holds the Hit button so the bot drives THROUGH the carrier — the
# emergent collision delivers the hit.
var commit_check: bool = false

# The opponent this decision is deliberately CLOSING ON, or -1. Steering drops
# only him from the off-puck proximity repel: the role owns the gap to him, and
# AISteering.OPPONENT_REPEL_RADIUS is wider than the gap ladder, so left in it
# would push the defender off his gap. Every other opponent still repels.
var engaged_peer_id: int = -1

# This decision is on the puck carrier even though its slot is not a pressurer
# slot — the pinching D — so the poke jab arms for it.
var pressures_puck: bool = false

# The man this decision is covering, or -1: the state machine's reactive
# dispatch cadence and stick tie read it. Only the zone roles publish it.
var locked_man_pid: int = -1

# Arrive AT SPEED instead of braking to a stop at `target_position` — for a role
# pacing a MOVING waypoint, which the arrival brake would read as a station about
# to be overshot. The body-level offside brake still applies.
var arrive_at_speed: bool = false

# An offensive station kept its forward stand this dispatch. Round-tripped into
# RoleContext.prev_held_forward_stand as the pinch read's hysteresis incumbent.
var held_forward_stand: bool = false
