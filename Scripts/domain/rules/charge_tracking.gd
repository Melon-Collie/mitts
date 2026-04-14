class_name ChargeTracking

# Accumulates wrister charge distance from blade movement while aiming.
# Resets the accumulator when the blade's direction of motion changes by
# more than max_direction_variance_deg — models the player "setting up"
# the shot: pulling the blade in a straight sweep loads charge; zig-zags
# reset it.
#
# Caller owns the per-frame state (prev_blade_pos, prev_direction,
# charge). Each tick it calls accumulate() with the current blade
# position and stores back the returned values.
#
# Returns { "charge": float, "direction": Vector3 }.
#   - direction: the most recent meaningful movement unit vector. Caller
#     passes this as prev_direction next tick. Vector3.ZERO means "no
#     direction yet recorded" (first frame or negligible movement).
static func accumulate(
		prev_blade_pos: Vector3,
		current_blade_pos: Vector3,
		prev_direction: Vector3,
		current_charge: float,
		max_direction_variance_deg: float) -> Dictionary:
	var blade_delta := current_blade_pos - prev_blade_pos
	blade_delta.y = 0.0
	var dist: float = blade_delta.length()
	if dist <= 0.001:
		# Negligible movement — charge and direction unchanged.
		return {"charge": current_charge, "direction": prev_direction}

	var current_dir: Vector3 = blade_delta.normalized()
	var new_charge: float = current_charge
	if prev_direction != Vector3.ZERO:
		var angle_deg: float = rad_to_deg(prev_direction.angle_to(current_dir))
		if angle_deg > max_direction_variance_deg:
			new_charge = 0.0
	new_charge += dist
	return {"charge": new_charge, "direction": current_dir}
