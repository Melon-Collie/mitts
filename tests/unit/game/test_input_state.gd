extends GutTest

# InputState — serialization round-trip.
# Catches regressions where host_timestamp is dropped from the wire format
# or field indices shift after a migration.


func test_round_trip_preserves_host_timestamp() -> void:
	var s := InputState.new()
	s.host_timestamp = 3.14159
	var r := InputState.from_array(s.to_array())
	assert_almost_eq(r.host_timestamp, 3.14159, 0.00001)


func test_round_trip_preserves_all_fields() -> void:
	var s := InputState.new()
	s.host_timestamp   = 1.5
	s.delta            = 1.0 / 240.0
	s.move_vector      = Vector2(0.5, -0.3)
	s.mouse_world_pos  = Vector3(1.0, 0.0, -2.5)
	s.mouse_screen_pos = Vector2(320.0, 240.0)
	s.shoot_pressed    = true
	s.shoot_held       = false
	s.slap_pressed     = false
	s.slap_held        = true
	s.brake            = false
	s.elevation_up     = true
	s.elevation_down   = false
	s.block_held       = true

	var r := InputState.from_array(s.to_array())

	assert_almost_eq(r.host_timestamp, s.host_timestamp, 0.00001)
	assert_almost_eq(r.delta, s.delta, 0.00001)
	assert_almost_eq(r.move_vector.x, s.move_vector.x, 0.00001)
	assert_almost_eq(r.move_vector.y, s.move_vector.y, 0.00001)
	assert_almost_eq(r.mouse_world_pos.x, s.mouse_world_pos.x, 0.00001)
	assert_almost_eq(r.mouse_world_pos.z, s.mouse_world_pos.z, 0.00001)
	assert_almost_eq(r.mouse_screen_pos.x, s.mouse_screen_pos.x, 0.00001)
	assert_almost_eq(r.mouse_screen_pos.y, s.mouse_screen_pos.y, 0.00001)
	assert_eq(r.shoot_pressed,   s.shoot_pressed)
	assert_eq(r.shoot_held,      s.shoot_held)
	assert_eq(r.slap_pressed,    s.slap_pressed)
	assert_eq(r.slap_held,       s.slap_held)
	assert_eq(r.brake,           s.brake)
	assert_eq(r.elevation_up,    s.elevation_up)
	assert_eq(r.elevation_down,  s.elevation_down)
	assert_eq(r.block_held,      s.block_held)


func test_array_length_is_sixteen() -> void:
	# Field count sentinel — if someone adds a field without updating
	# to_array/from_array, this catches the mismatch.
	var s := InputState.new()
	assert_eq(s.to_array().size(), 17)


# ── Binary (bytes) round-trip ─────────────────────────────────────────────────

func test_bytes_round_trip_preserves_all_fields() -> void:
	var s := InputState.new()
	s.host_timestamp   = 1.5
	s.delta            = 1.0 / 60.0
	s.move_vector      = Vector2(0.5, -0.3)
	s.mouse_world_pos  = Vector3(1.0, 0.0, -2.5)
	s.mouse_screen_pos = Vector2(320.0, 240.0)
	s.shoot_pressed    = true
	s.shoot_held       = false
	s.slap_pressed     = false
	s.slap_held        = true
	s.brake            = false
	s.elevation_up     = true
	s.elevation_down   = false
	s.block_held       = true

	var r := InputState.from_bytes(s.to_bytes())

	assert_almost_eq(r.host_timestamp,   s.host_timestamp,   0.0001)
	assert_almost_eq(r.delta,            s.delta,            0.00001)
	assert_almost_eq(r.move_vector.x,    s.move_vector.x,    0.001)
	assert_almost_eq(r.move_vector.y,    s.move_vector.y,    0.001)
	assert_almost_eq(r.mouse_world_pos.x, s.mouse_world_pos.x, 0.01)
	assert_almost_eq(r.mouse_world_pos.z, s.mouse_world_pos.z, 0.01)
	assert_almost_eq(r.mouse_screen_pos.x, s.mouse_screen_pos.x, 1.0)
	assert_almost_eq(r.mouse_screen_pos.y, s.mouse_screen_pos.y, 1.0)
	assert_eq(r.shoot_pressed,   s.shoot_pressed)
	assert_eq(r.shoot_held,      s.shoot_held)
	assert_eq(r.slap_pressed,    s.slap_pressed)
	assert_eq(r.slap_held,       s.slap_held)
	assert_eq(r.brake,           s.brake)
	assert_eq(r.elevation_up,    s.elevation_up)
	assert_eq(r.elevation_down,  s.elevation_down)
	assert_eq(r.block_held,      s.block_held)


func test_bytes_size_sentinel() -> void:
	assert_eq(InputState.BYTES_SIZE, 23)


func test_from_bytes_supports_offset() -> void:
	var s := InputState.new()
	s.host_timestamp = 2.0
	s.shoot_pressed = true
	# Embed the bytes at offset 5 inside a larger buffer
	var buf := PackedByteArray(); buf.resize(5 + InputState.BYTES_SIZE)
	var inner := s.to_bytes()
	for i: int in InputState.BYTES_SIZE:
		buf[5 + i] = inner[i]
	var r := InputState.from_bytes(buf, 5)
	assert_almost_eq(r.host_timestamp, 2.0, 0.0001)
	assert_eq(r.shoot_pressed, true)
