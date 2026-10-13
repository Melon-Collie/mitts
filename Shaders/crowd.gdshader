// Spectator crowd animation and shading. Both crowd MultiMeshes (bodies +
// heads) share one material with this shader, so the whole bowl animates off a
// single `excitement` uniform with zero per-frame CPU work.
//
// Per-instance INSTANCE_CUSTOM (set once at build time in ArenaCrowd):
//   .x = phase (0..1)      — de-syncs motion between neighbours, and seeds the
//                            per-person shade and hair rolls below
//   .y = sway amplitude    — how much this fan rocks side to side
//   .z = hop amplitude     — how hard this fan jumps when excited
// Per-instance COLOR: the paint, with alpha 0 marking a bare head (skin, no hat
// or hair colour of its own) for the hair pass.
//
// The head mesh shares the body's instance transform and custom data, and
// displacement is a continuous function of local VERTEX.y — so head and body
// move as one person even though they're separate draw calls.
shader_type spatial;
render_mode cull_disabled;

// 0 = idle murmur sway, 1 = goal celebration. Tweened by ArenaStands.
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
// Figure-local heights, written from ArenaFigureMesh by ArenaCrowd: above
// head_base_y is head, and body_top_y is where the torso box ends.
uniform float head_base_y;
uniform float body_top_y;

// The crowd casts no shadows (ArenaCrowd.attach), so nothing darkens a lap in
// the row's shade of the seat back and the fan in front; this does instead, from
// LAP_SHADE at the seat up to full at the shoulders.
const float LAP_SHADE = 0.55;
// Per-person brightness spread, so a block of one team colour reads as people
// in slightly different light and fabric rather than one painted slab.
const float SHADE_MIN = 0.86;
const float SHADE_MAX = 1.08;
// Share of bare heads that stay bare.
const float BALD_SHARE = 0.12;

varying float v_height;
varying float v_crown;
varying flat float v_shade;
varying flat vec3 v_hair;

float roll(float seed, float salt) {
	return fract(sin(seed * salt) * 43758.5453);
}

vec3 hair_colour(float r) {
	if (r < 0.34) return vec3(0.07, 0.06, 0.05);  // black
	if (r < 0.64) return vec3(0.20, 0.13, 0.08);  // dark brown
	if (r < 0.82) return vec3(0.40, 0.28, 0.17);  // light brown
	if (r < 0.92) return vec3(0.70, 0.56, 0.34);  // blond
	return vec3(0.62, 0.60, 0.58);                // grey
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	v_height = VERTEX.y;
	v_shade = mix(SHADE_MIN, SHADE_MAX, roll(seed, 12.9898));
	v_hair = hair_colour(roll(seed, 78.233));
	bool bare = COLOR.a < 0.5 && roll(seed, 39.346) >= BALD_SHARE;
	v_crown = (bare && VERTEX.y > head_base_y && NORMAL.y > 0.5) ? 1.0 : 0.0;

	float phase = seed * 6.2831853;
	float sway_amp = INSTANCE_CUSTOM.y;
	float hop_amp = INSTANCE_CUSTOM.z;
	// Sway: lean grows with height, so heads move more than hips.
	float sway = sin(TIME * 1.4 + phase) * mix(0.03, 0.10, excitement) * sway_amp;
	VERTEX.x += sway * VERTEX.y;
	// Celebration hop: whole spectator bounces, frequency de-synced per fan.
	float hop_freq = 4.2 + 2.4 * seed;
	float hop = abs(sin(TIME * hop_freq + phase)) * 0.18 * hop_amp * excitement;
	VERTEX.y += hop;
}

void fragment() {
	vec3 paint = mix(COLOR.rgb, v_hair, v_crown);
	float lap = v_height < head_base_y
			? mix(LAP_SHADE, 1.0, smoothstep(0.0, body_top_y, v_height))
			: 1.0;
	ALBEDO = paint * v_shade * lap;
	ROUGHNESS = 0.85;
	// Cloth and skin, not plastic: well under the 0.5 default's F0.
	SPECULAR = 0.3;
}
