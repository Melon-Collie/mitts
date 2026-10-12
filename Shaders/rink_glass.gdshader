// The glass above the boards. Premultiplied alpha, so the reflection is added at
// full strength while the glass's own tint stays as faint as it is: under plain
// alpha blending every reflection is scaled by that same low alpha and the glass
// mirrors nothing.
//
// ALPHA is how much of what lies behind the pane it blocks. Head-on that is only
// the tint; toward grazing, Fresnel turns more light away, so the pane reads as a
// surface. What it turns away comes back as the specular term's reflection, not
// as tint, so the diffuse albedo stays at the head-on absorption.
//
// Both grazing terms are held under a physical pane's (see specular_strength):
// at full strength the glass becomes a white wall hiding the crowd behind it.
shader_type spatial;
render_mode blend_premul_alpha, cull_disabled, specular_schlick_ggx;

// rgb is the tint; a is how much it blocks head-on.
uniform vec4 tint : source_color = vec4(0.85, 0.93, 1.0, 0.12);
// Godot's grazing reflectance is clamp(50 * F0, 0, 1), with F0 = 0.16 * SPECULAR².
// Real glass (IOR ~1.5, F0 0.04) is SPECULAR 0.5. But in linear light the ice is
// far brighter than the crowd behind the pane (eight spots on a white sheet,
// folded back to near-white by the tonemap), so a physical reflection of it
// washes the crowd out to a white band. 0.12 keeps the sheen and the crowd.
uniform float specular_strength : hint_range(0.0, 1.0) = 0.12;
// The most of the background the pane hides, however edge-on it is seen.
uniform float grazing_block : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_clean : hint_range(0.0, 1.0) = 0.03;
// Puck marks and glove smudges collect low on the pane, where play hits it.
uniform float smudge_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float smudge_height = 0.6;
// Height of the pane's bottom edge in the rink's space, written by HockeyRink.
uniform float pane_bottom_y;
// The top edge of a pane glows green, as real tempered glass does along its
// cut edge: it is the line that tells you where the glass stops.
uniform vec3 edge_colour : source_color = vec3(0.55, 0.85, 0.75);
uniform float edge_strength : hint_range(0.0, 2.0) = 0.35;

const float F0_GLASS = 0.04;

// Mesh space, which is the rink's: the pane heights below are measured in it.
varying vec3 v_local;
varying vec3 v_local_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_local = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float fresnel = F0_GLASS + (1.0 - F0_GLASS) * pow(1.0 - facing, 5.0);
	float block = mix(tint.a, max(tint.a, grazing_block), fresnel);

	// Smudges: a low band of patchy haze. Noise runs along the pane (x + z, so
	// both the side and end runs get it) and up it.
	float along = v_local.x + v_local.z;
	float haze = smoothstep(0.45, 0.8, value_noise(vec2(along * 1.7, v_local.y * 3.0)));
	float low = 1.0 - smoothstep(pane_bottom_y, pane_bottom_y + smudge_height, v_local.y);
	float smudge = haze * low;

	float top_edge = step(0.9, v_local_normal.y);

	ALBEDO = tint.rgb * tint.a;
	ALPHA = block;
	METALLIC = 0.0;
	SPECULAR = specular_strength;
	ROUGHNESS = mix(roughness_clean, smudge_roughness, smudge);
	EMISSION = edge_colour * edge_strength * top_edge;
}
