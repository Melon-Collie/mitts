shader_type spatial;

// Paints a keeper's pants and socks (KeeperGearMeshes, built in a save box's
// frame: centred, X across, Y up the piece, −Z toward the shooter) from the
// team kit: the base, and the kit's stripes, round the piece as bands by height
// (the socks) or down its side as columns (the pants, as on the skaters').
// Heights are normalised over the bands' height_m, from the piece's top.

const int MAX_STRIPES = 5;

uniform vec2 half_size = vec2(0.28, 0.26);  // the box's half width and half height
uniform float height_m = 0.52;
uniform vec4 base_color : source_color = vec4(1.0);
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
// Drawn as part of the keeper's one skinned body (KeeperBodyRig): VERTEX has
// been moved by the skin, so the piece's box-frame place rides in CUSTOM0.
uniform bool skinned = false;

varying vec3 v_obj;

void vertex() {
	v_obj = skinned ? CUSTOM0.xyz : VERTEX;
}

void fragment() {
	float band_y = (half_size.y - v_obj.y) / height_m;

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

	// The mesh's vertex tint darkens its creases and openings under the paint.
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 0.9;
	// The skaters' rim (BodyRim): a soft fresnel edge so he reads as a lit volume.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(rim * 0.2);
}
