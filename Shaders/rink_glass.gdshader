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

// A body driven into the boards rattles the pane (BoardCheckVFX): the glass
// either side of where he hit it flexes back and forth, its whole height, and
// dies away, its reflection swinging and the pane frosting and catching the
// light as it goes. The pane is a few long flat quads, so this is drawn rather
// than bent. `rattle_t` runs 0 → 1 over the rattle; `rattle_pos` is where it
// struck, in the rink's space.
uniform vec3 rattle_pos = vec3(0.0, -100.0, 0.0);
uniform float rattle_t : hint_range(0.0, 1.0) = 1.0;
uniform float rattle_strength : hint_range(0.0, 1.0) = 0.0;
// How far along the boards the pane flexes, how many times it swings over the
// rattle, how its swing varies along the pane (radians a metre: the panes are
// ~1.5 m wide), and at full strength how far it bends the normal, how much it
// frosts and the sheen it catches: the pane is nearly clear, so a swung
// reflection alone does not show.
const float RATTLE_REACH_M = 3.0;
const float RATTLE_SWINGS = 7.0;
const float RATTLE_ALONG = 2.1;
const float RATTLE_BEND = 0.28;
const float RATTLE_FROST = 0.17;
const vec3 RATTLE_SHEEN = vec3(0.2, 0.22, 0.26);

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

	// The rattle: a damped swing of the pane near the hit, fading along it.
	vec2 from_hit = v_local.xz - rattle_pos.xz;
	float reach = 1.0 - smoothstep(0.0, RATTLE_REACH_M, length(from_hit));
	float life = rattle_strength * (1.0 - rattle_t) * (1.0 - rattle_t);
	float run = (from_hit.x + from_hit.y) * RATTLE_ALONG;
	float swing = sin(rattle_t * RATTLE_SWINGS * 6.2831853 + run);
	float rattle = life * reach * swing;
	vec3 sheen = vec3(0.0);
	if (life * reach > 1e-4) {
		vec3 sideways = normalize(vec3(from_hit.x, 0.0, from_hit.y) + vec3(1e-4, 0.0, 0.0));
		vec3 bend = (VIEW_MATRIX * MODEL_MATRIX * vec4(sideways, 0.0)).xyz;
		NORMAL = normalize(NORMAL + bend * rattle * RATTLE_BEND);
		block = min(block + life * reach * RATTLE_FROST, 1.0);
		sheen = RATTLE_SHEEN * life * reach * (0.5 + 0.5 * swing);
	}

	ALBEDO = tint.rgb * tint.a;
	ALPHA = block;
	METALLIC = 0.0;
	SPECULAR = specular_strength;
	ROUGHNESS = mix(roughness_clean, smudge_roughness, smudge);
	EMISSION = edge_colour * edge_strength * top_edge + sheen;
}
