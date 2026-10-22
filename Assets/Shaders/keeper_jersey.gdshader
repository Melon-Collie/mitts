shader_type spatial;

// Paints a keeper's jersey piece (KeeperGearMeshes, built in its save box's
// frame: centred, X across, Y up the piece, −Z toward the shooter) from the
// team kit, by object-space height so every band runs level round it: the
// base, the yoke over the top, the collar on the top face, the shoulder caps
// in the kit's shoulder color, the kit's stripe bands, the crest on the front
// face and the name and number on the back. A sleeve uses the bands alone.
//
// Heights are normalised over the piece: 0 = its top, 1 = its bottom.

const int MAX_STRIPES = 5;

uniform vec2 half_size = vec2(0.28, 0.26);  // the box's half width and half height
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 yoke_color : source_color = vec4(1.0);
uniform vec4 collar_color : source_color = vec4(1.0);
uniform vec4 cap_color : source_color = vec4(1.0);
uniform float yoke_depth = 0.0;
uniform float collar_radius = 0.0;
uniform float collar_center_z = 0.0;
// The shoulder caps' or the elbow cap's ellipsoid (|x| about cap_center.x),
// grown a touch so its faceted surface lies inside the test.
uniform vec3 cap_center = vec3(0.0, 1e3, 0.0);
uniform vec3 cap_radii = vec3(0.001);
uniform int stripe_count = 0;
uniform vec4 stripe_colors[MAX_STRIPES] : source_color;
uniform float stripe_positions[MAX_STRIPES];
uniform float stripe_widths[MAX_STRIPES];
uniform bool decals = false;
// The decals' frame: U across the box's width, V down its height, the same
// metres KeeperJerseyDecal lays its pixels out in.
uniform sampler2D text_decal : hint_default_transparent, filter_linear_mipmap;
uniform sampler2D crest_decal : hint_default_transparent, filter_linear_mipmap;

varying vec3 v_obj;
varying vec3 v_obj_normal;

void vertex() {
	v_obj = VERTEX;
	v_obj_normal = NORMAL;
}

void fragment() {
	float norm_y = (half_size.y - v_obj.y) / (half_size.y * 2.0);

	vec3 col = base_color.rgb;
	for (int i = 0; i < MAX_STRIPES; i++) {
		if (i < stripe_count && abs(norm_y - stripe_positions[i]) < stripe_widths[i] * 0.5) {
			col = stripe_colors[i].rgb;
		}
	}
	vec3 cap = vec3(abs(v_obj.x) - cap_center.x, v_obj.y - cap_center.y, v_obj.z - cap_center.z)
			/ (cap_radii * 1.08);
	if (dot(cap, cap) < 1.0) {
		col = cap_color.rgb;
	}
	if (norm_y < yoke_depth) {
		col = yoke_color.rgb;
	}
	if (v_obj_normal.y > 0.9 && collar_radius > 0.0) {
		bool collar = length(vec2(v_obj.x, v_obj.z - collar_center_z)) < collar_radius;
		col = collar ? collar_color.rgb : yoke_color.rgb;
	}
	if (decals) {
		// The back (+Z) face: a viewer behind sees +X on their right.
		if (v_obj_normal.z > 0.9) {
			vec4 text = texture(text_decal, vec2((v_obj.x + half_size.x) / (half_size.x * 2.0), norm_y));
			col = mix(col, text.rgb, text.a);
		}
		// The front (−Z) face: a viewer in front sees +X on their left.
		if (v_obj_normal.z < -0.9) {
			vec4 crest = texture(crest_decal, vec2((half_size.x - v_obj.x) / (half_size.x * 2.0), norm_y));
			col = mix(col, crest.rgb, crest.a);
		}
	}

	ALBEDO = col;
	ROUGHNESS = 0.9;
	// The skaters' rim (BodyRim): a soft fresnel edge so he reads as a lit volume.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(rim * 0.2);
}
