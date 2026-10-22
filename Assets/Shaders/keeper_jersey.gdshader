shader_type spatial;

// Paints a keeper's jersey piece (KeeperGearMeshes, built in its save box's
// frame: centred, X across, Y up the piece, −Z toward the shooter) from the
// team kit, by object-space height so every band runs level round it: the
// base, the yoke over the top, the collar on the top face, the shoulder caps
// in the kit's shoulder color, the kit's stripe bands, the crest on the front
// face and the name and number on the back. A sleeve uses the bands alone, the
// pants their side stripes.
//
// Heights are normalised over the piece: 0 = its top, 1 = its bottom; the
// bands over height_m, which for the jersey runs on down its tail.

const int MAX_STRIPES = 5;

uniform vec2 half_size = vec2(0.28, 0.26);  // the box's half width and half height
// The bands run down the whole piece: the jersey's is its protector and its
// tail. The tail is lofted in keeper space, so it carries its depth below the
// collar in UV.y instead of a height in a box.
uniform float height_m = 0.52;
uniform bool depth_in_uv = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 yoke_color : source_color = vec4(1.0);
uniform vec4 collar_color : source_color = vec4(1.0);
uniform vec4 cap_color : source_color = vec4(1.0);
uniform float yoke_depth = 0.0;
uniform float collar_radius = 0.0;
uniform float collar_center_z = 0.0;
// The cap in cap_color: the shoulder cap over the top of a sleeve, down to
// cap_until; or the elbow pad's ellipsoid (its faceted surface lies inside it,
// the test grown only for rounding), so a sleeve leaving it changes colour
// where it leaves the pad.
uniform float cap_until = 0.0;
uniform vec3 cap_center = vec3(0.0, 1e3, 0.0);
uniform vec3 cap_radii = vec3(0.001);
// The shoulder number, on both side faces of a sleeve's cap: the band it is set
// in (centre height, height) and its width, in object metres.
uniform bool shoulder_number = false;
uniform sampler2D number_decal : hint_default_transparent, filter_linear_mipmap;
uniform vec2 number_band = vec2(0.0, 0.1);
uniform float number_width = 0.14;
// The pants: the kit's stripes run down the side as columns instead of round
// as bands, as on the skaters' pants. Their positions are shares of around_m
// round the piece, 0.5 the middle of the side face: the −X face for
// stripe_side −1, +X for +1, both for 0.
uniform bool side_stripes = false;
uniform float stripe_side = 0.0;
uniform float around_m = 0.7;
uniform int stripe_count = 0;
uniform vec4 stripe_colors[MAX_STRIPES] : source_color;
uniform float stripe_positions[MAX_STRIPES];
uniform float stripe_widths[MAX_STRIPES];
uniform bool decals = false;
// A right-catcher's gear is drawn turned over on its own x: the lettering and
// the crest are read the other way across, so they still read forwards.
uniform bool flip_decals = false;
// The decals' frame: U across the box's width, V down its height, the same
// metres KeeperJerseyDecal lays its pixels out in.
uniform sampler2D text_decal : hint_default_transparent, filter_linear_mipmap;
uniform sampler2D crest_decal : hint_default_transparent, filter_linear_mipmap;

varying vec3 v_obj;
varying vec3 v_obj_normal;
varying float v_depth;

void vertex() {
	v_obj = VERTEX;
	v_obj_normal = NORMAL;
	v_depth = depth_in_uv ? UV.y : half_size.y - VERTEX.y;
}

void fragment() {
	float norm_y = v_depth / (half_size.y * 2.0);
	float band_y = v_depth / height_m;

	vec3 col = base_color.rgb;
	float side = stripe_side != 0.0 ? stripe_side : sign(v_obj.x);
	for (int i = 0; i < MAX_STRIPES; i++) {
		if (i >= stripe_count) {
			continue;
		}
		bool hit = abs(band_y - stripe_positions[i]) < stripe_widths[i] * 0.5;
		if (side_stripes) {
			// Across the side face, which is near flat: z is the way round it.
			float centre = (stripe_positions[i] - 0.5) * around_m;
			hit = v_obj.x * side > 0.0
					&& abs(v_obj.z * side - centre) < stripe_widths[i] * around_m * 0.5;
		}
		if (hit) {
			col = stripe_colors[i].rgb;
		}
	}
	vec3 cap = vec3(abs(v_obj.x) - cap_center.x, v_obj.y - cap_center.y, v_obj.z - cap_center.z)
			/ (cap_radii * 1.01);
	if (dot(cap, cap) < 1.0 || (cap_until > 0.0 && norm_y < cap_until)) {
		col = cap_color.rgb;
	}
	if (yoke_depth > 0.0 && norm_y < yoke_depth) {
		col = yoke_color.rgb;
	}
	if (v_obj_normal.y > 0.9 && collar_radius > 0.0) {
		bool collar = length(vec2(v_obj.x, v_obj.z - collar_center_z)) < collar_radius;
		col = collar ? collar_color.rgb : yoke_color.rgb;
	}
	float across = flip_decals ? -1.0 : 1.0;
	if (shoulder_number && abs(v_obj_normal.x) > 0.5) {
		// Seen from the face's side, the viewer's right runs toward −Z on the
		// +X face and +Z on the −X one.
		vec2 uv = vec2(0.5 - across * sign(v_obj_normal.x) * v_obj.z / number_width,
				0.5 - (v_obj.y - number_band.x) / number_band.y);
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
			vec4 number = texture(number_decal, uv);
			col = mix(col, number.rgb, number.a);
		}
	}
	if (decals) {
		// The back (+Z) face: a viewer behind sees +X on their right.
		if (v_obj_normal.z > 0.9) {
			vec4 text = texture(text_decal,
					vec2((across * v_obj.x + half_size.x) / (half_size.x * 2.0), norm_y));
			col = mix(col, text.rgb, text.a);
		}
		// The front (−Z) face: a viewer in front sees +X on their left.
		if (v_obj_normal.z < -0.9) {
			vec4 crest = texture(crest_decal,
					vec2((half_size.x - across * v_obj.x) / (half_size.x * 2.0), norm_y));
			col = mix(col, crest.rgb, crest.a);
		}
	}

	// The mesh's vertex tint darkens its creases and openings under the paint.
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 0.9;
	// The skaters' rim (BodyRim): a soft fresnel edge so he reads as a lit volume.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(rim * 0.2);
}
