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
//
// The figure (ArenaFigureMesh) tags each vertex's part in UV.x: 0 torso, 1
// upper arm, 2 forearm, 3 leg, 4 shoe, 5 head. The arms are posed here, rigidly
// about the shoulder and elbow pivots — the cull bounds rely on nothing else
// moving them (ArenaFigureMesh.crowd_pose_bounds). The rinkside staff use this
// shader too, on a material nobody excites and with no sway or hop rolled.
shader_type spatial;
render_mode cull_disabled;

// 0 = idle murmur sway, 1 = goal celebration. Tweened by ArenaStands.
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
// Where the seated torso ends, written from ArenaFigureMesh.
uniform float body_top_y;
// The right arm's pivots (the left mirrors them in X), and the turn at the
// elbow that straightens the forearm onto the upper arm.
uniform vec3 shoulder;
uniform vec3 elbow;
uniform float elbow_unbend;
// ArenaFigureMesh's bare-skin tones: the face under a cap or hair paint.
uniform vec3 skin_tones[5];

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
// Share of the crowd that gets its arms up for a goal, how far up (radians
// forward from hanging), how far they spread outward, and the fist pump on top.
const float CHEER_SHARE = 0.7;
const float ARM_RAISE = 2.75;
const float ARM_SPREAD = 0.35;
const float ARM_PUMP = 0.22;
// Where hair or a cap starts on the head: high on the face, low at the back.
const float HAIRLINE_FRONT = 0.655;
const float HAIRLINE_SIDE = 0.615;
const float HAIRLINE_BACK = 0.53;
// The face, on the head's front facet (figure-local metres, x from the centre
// line): eyes, the brows over them, a mouth. Each is a box; the brows take the
// hair's colour on a bare head and a dark one under a cap.
const vec2 EYE = vec2(0.024, 0.583);
const vec2 EYE_HALF = vec2(0.0085, 0.011);
const vec2 BROW = vec2(0.025, 0.607);
const vec2 BROW_HALF = vec2(0.014, 0.0045);
const vec2 MOUTH = vec2(0.0, 0.515);
const vec2 MOUTH_HALF = vec2(0.017, 0.0045);
const vec3 EYE_COLOUR = vec3(0.05, 0.04, 0.04);
// Features fade out as an eye shrinks below this many pixels across, so a far
// face is plain skin rather than a shimmer of sub-pixel dots.
const vec2 FACE_FADE_PX = vec2(1.0, 2.5);
const vec3 SHOE = vec3(0.06, 0.05, 0.05);

varying float v_height;
varying flat float v_shade;
varying flat vec3 v_hair;
varying flat vec3 v_skin;
varying flat vec3 v_trousers;
varying flat float v_bald;
varying flat float v_leg;
varying flat float v_shoe;
varying flat float v_head;
varying flat vec3 v_normal;
varying float v_x;

// 1 inside the box of half-size `half_size` about `centre`, 0 outside, with an
// edge `aa` wide.
float box(vec2 p, vec2 centre, vec2 half_size, float aa) {
	vec2 d = abs(p - centre) - half_size;
	return 1.0 - smoothstep(-aa * 0.5, aa * 0.5, max(d.x, d.y));
}

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

vec3 trouser_colour(float r) {
	if (r < 0.45) return vec3(0.16, 0.22, 0.36);  // denim
	if (r < 0.70) return vec3(0.09, 0.09, 0.10);  // black
	if (r < 0.85) return vec3(0.42, 0.36, 0.26);  // khaki
	return vec3(0.30, 0.30, 0.32);                // grey
}

// Turn `v` by `a` about the X axis through the point (`pivot_yz`).
vec3 turn_x(vec3 v, vec2 pivot_yz, float a) {
	vec2 d = v.yz - pivot_yz;
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, pivot_yz + vec2(d.x * c - d.y * s, d.x * s + d.y * c));
}

// Turn `v` by `a` about the Z axis through the point (`pivot_xy`).
vec3 turn_z(vec3 v, vec2 pivot_xy, float a) {
	vec2 d = v.xy - pivot_xy;
	float c = cos(a);
	float s = sin(a);
	return vec3(pivot_xy + vec2(d.x * c - d.y * s, d.x * s + d.y * c), v.z);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float phase = seed * 6.2831853;
	float hop_freq = 4.2 + 2.4 * seed;
	v_shade = mix(SHADE_MIN, SHADE_MAX, roll(seed, 12.9898));
	v_hair = hair_colour(roll(seed, 78.233));
	v_skin = skin_tones[int(roll(seed, 3.731) * 4.999)];
	v_trousers = trouser_colour(roll(seed, 27.119));
	v_bald = step(roll(seed, 39.346), BALD_SHARE);
	int part = int(UV.x + 0.5);
	v_leg = part == 3 ? 1.0 : 0.0;
	v_shoe = part == 4 ? 1.0 : 0.0;
	v_head = part == 5 ? 1.0 : 0.0;

	if (part == 1 || part == 2) {
		float side = sign(VERTEX.x);
		float cheer = excitement * step(roll(seed, 5.731), CHEER_SHARE)
				* mix(0.75, 1.0, roll(seed, 9.137));
		float pump = ARM_PUMP * sin(TIME * hop_freq + phase);
		float raise = cheer * (ARM_RAISE + pump);
		float spread = -side * cheer * ARM_SPREAD;
		vec3 v = VERTEX;
		vec3 n = NORMAL;
		if (part == 2) {
			v = turn_x(v, elbow.yz, elbow_unbend * cheer);
			n = turn_x(n, vec2(0.0), elbow_unbend * cheer);
		}
		v = turn_z(turn_x(v, shoulder.yz, raise), vec2(side * shoulder.x, shoulder.y), spread);
		n = turn_z(turn_x(n, vec2(0.0), raise), vec2(0.0), spread);
		VERTEX = v;
		NORMAL = n;
	}
	v_height = VERTEX.y;
	v_normal = NORMAL;
	v_x = VERTEX.x;

	float sway_amp = INSTANCE_CUSTOM.y;
	float hop_amp = INSTANCE_CUSTOM.z;
	// Sway: lean grows with height, so heads move more than hips.
	float sway = sin(TIME * 1.4 + phase) * mix(0.03, 0.10, excitement) * sway_amp;
	VERTEX.x += sway * VERTEX.y;
	// Celebration hop: whole spectator bounces, frequency de-synced per fan.
	float hop = abs(sin(TIME * hop_freq + phase)) * 0.18 * hop_amp * excitement;
	VERTEX.y += hop;
}

void fragment() {
	vec3 paint = mix(mix(COLOR.rgb, v_trousers, v_leg), SHOE, v_shoe);
	if (v_head > 0.5) {
		// A bare head (alpha 0) is painted its skin, with hair rolled here; any
		// other head is painted its cap or hair, with skin rolled here.
		bool bare = COLOR.a < 0.5;
		vec3 skin = bare ? COLOR.rgb : v_skin;
		vec3 top = bare ? v_hair : COLOR.rgb;
		float hairline = v_normal.z < 0.0
				? mix(HAIRLINE_SIDE, HAIRLINE_FRONT, -v_normal.z)
				: mix(HAIRLINE_SIDE, HAIRLINE_BACK, v_normal.z);
		bool covered = v_height > hairline && !(bare && v_bald > 0.5);
		paint = covered ? top : skin;
		if (!covered && v_normal.z < -0.9) {
			float px = max(fwidth(v_x), 1e-6);
			float detail = smoothstep(FACE_FADE_PX.x, FACE_FADE_PX.y, EYE_HALF.x * 2.0 / px);
			vec2 p = vec2(abs(v_x), v_height);
			vec3 brow_colour = bare ? v_hair : EYE_COLOUR * 2.0;
			paint = mix(paint, brow_colour, detail * box(p, BROW, BROW_HALF, px));
			paint = mix(paint, EYE_COLOUR, detail * box(p, EYE, EYE_HALF, px));
			paint = mix(paint, skin * 0.55, detail * box(p, MOUTH, MOUTH_HALF, px));
		}
	}
	float lap = v_head > 0.5 ? 1.0
			: mix(LAP_SHADE, 1.0, smoothstep(0.0, body_top_y, v_height));
	ALBEDO = paint * v_shade * lap;
	ROUGHNESS = 0.85;
	// Cloth and skin, not plastic: well under the 0.5 default's F0.
	SPECULAR = 0.3;
}
