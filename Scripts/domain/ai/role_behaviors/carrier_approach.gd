class_name AICarrierApproach
extends RefCounted

# What a defender who owns the carrier knows about him — one read shared by every
# role that closes a carrier, so their degenerate-case guards cannot drift apart.
# Filled in place by AIRoleHelpers.read_carrier_approach / fill_approach.

# His REAL body, never a velocity-led point: the stand rides him, so a lead
# double-counts his motion.
var carrier_pos: Vector3 = Vector3.ZERO
var carrier_vel: Vector3 = Vector3.ZERO

# Unit vector from him toward the net we defend — the axis every gap is measured
# on. ZERO when he is on top of the net; roles handle that case themselves.
var dir_net: Vector3 = Vector3.ZERO

# Metres from him to our net.
var net_dist: float = 0.0

# His pace ALONG dir_net, m/s, floored at zero: lateral drift buys no burst
# toward our net, so a carrier flying across the slot is not closing.
var closing: float = 0.0
