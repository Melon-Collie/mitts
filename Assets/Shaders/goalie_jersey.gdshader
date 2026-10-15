shader_type spatial;

// Paints the goalie's body solid (GoalieMeshBuilder) as a skater's sweater is
// painted: the jersey base, the yoke over the top of the shoulders and down
// every side to the skater's shoulder-line depth, the collar ringing the neck
// on the top face, the jersey stripes over the jersey (collar to the pants
// line), the pants band below, and the name and number decal on the back.
// Heights use object-space VERTEX.y, so bands run level on every face.
//
// Stripe pos/width follow the v2 jersey schema: 0 = collar, 1 = the jersey's
// bottom, the same span a skater's torso side gives them. Painted in array
// order; later entries overwrite earlier.

const int MAX_STRIPES = 5;

// Half-extents of the body solid (GoalieMeshBuilder.BODY_HALF_W / BODY_TOP_Y).
const float HALF_H = 0.36;
const float HALF_W = 0.26;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 yoke_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 collar_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The yoke's depth down the sides, normalised like norm_y (0 = top).
uniform float yoke_depth = 0.083;
// The collar ring round the neck guard on the top face, in object metres.
uniform float collar_radius = 0.097;
uniform float collar_center_z = 0.02;
uniform int stripe_count = 0;
uniform vec4 stripe_colors[MAX_STRIPES] : source_color;
uniform float stripe_positions[MAX_STRIPES];
uniform float stripe_widths[MAX_STRIPES];
// Transparent-background viewport with name + number drawn centred.
uniform sampler2D text_decal : hint_default_transparent, filter_linear_mipmap;
// The body solid is torso THROUGH hips: below pants_start (normalised
// height, 0 = top) the band paints as the kit's pants instead of jersey.
uniform vec4 pants_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float pants_start = 0.72;

varying vec3 v_obj;
varying vec3 v_obj_normal;

void vertex() {
	v_obj = VERTEX;
	v_obj_normal = NORMAL;
}

void fragment() {
	ROUGHNESS = 0.9;
	METALLIC = 0.0;

	// 0 = TOP of body, 1 = BOTTOM — the direction JerseyDecal's V runs.
	float norm_y = (HALF_H - v_obj.y) / (HALF_H * 2.0);
	float jersey_y = norm_y / pants_start;

	vec3 col = base_color.rgb;
	if (norm_y < yoke_depth) {
		col = yoke_color.rgb;
	}
	for (int i = 0; i < MAX_STRIPES; i++) {
		if (i < stripe_count &&
				abs(jersey_y - stripe_positions[i]) < stripe_widths[i] * 0.5) {
			col = stripe_colors[i].rgb;
		}
	}
	// After the stripes, so no jersey stripe bleeds onto the pants (the hip
	// connectors carry the pants stripes instead).
	if (norm_y > pants_start) {
		col = pants_color.rgb;
	}
	if (v_obj_normal.y > 0.9) {
		bool collar = length(vec2(v_obj.x, v_obj.z - collar_center_z)) < collar_radius;
		col = collar ? collar_color.rgb : yoke_color.rgb;
	}

	// The decal on the back (+Z) face only: the goalie faces -Z toward the
	// shooter. A viewer behind him (on +Z, looking -Z) sees object +X on their
	// right, so U must INCREASE with x to read left to right.
	if (v_obj_normal.z > 0.9) {
		float face_u = (v_obj.x + HALF_W) / (HALF_W * 2.0);
		vec4 decal = texture(text_decal, vec2(face_u, norm_y));
		col = mix(col, decal.rgb, decal.a);
	}

	ALBEDO = col;

	// Fresnel rim to match the skaters' rim light — a soft white edge glow so
	// the goalie reads as a lit volume from the top-down camera. Additive
	// emission (independent of light direction) keeps it visible in the crease
	// shadow; tuned subtle and well under the glow HDR threshold.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(rim * 0.2);
}
