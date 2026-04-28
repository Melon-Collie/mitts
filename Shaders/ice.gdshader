// Ice surface — sub-surface line tint + Fresnel-driven reflectivity.
//
// The albedo texture has the rink lines painted into it. Real ice paints lines
// onto the concrete BELOW the ice sheet, so the lines should:
//   1. Appear slightly displaced when viewed at angle (parallax through depth).
//   2. Fade toward the ice color at grazing angles (more ice between viewer
//      and line), letting reflections take over.
//
// Reflectivity is left to the engine's Schlick/GGX path: we just hand it a
// reasonable F0 (SPECULAR) and an angle-varying ROUGHNESS so the surface goes
// from slightly diffuse head-on to mirror-sharp at grazing.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
// Plane size in world meters — used to convert parallax offset to UV.
uniform vec2 rink_size = vec2(26.0, 60.0);
// Color the lines fade toward at grazing. Default to the ice color itself so
// lines blend into the surrounding ice; nudge cooler/lighter for more drama.
uniform vec3 ice_fog_color : source_color = vec3(0.9, 0.95, 1.0);
// How strongly the lines fade toward fog at grazing (0 = no fade, 1 = full).
uniform float subsurface_fade : hint_range(0.0, 1.0) = 0.55;
// Apparent depth of the lines below the ice surface, in meters.
uniform float subsurface_depth : hint_range(0.0, 0.05) = 0.012;
// F0 reflectance multiplier (0.5 = water-baseline F0 of 0.04).
uniform float specular_strength : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_head_on : hint_range(0.0, 1.0) = 0.20;
uniform float roughness_grazing : hint_range(0.0, 1.0) = 0.04;
// Shapes how quickly the fade ramps up toward grazing (higher = sharper edge).
uniform float grazing_falloff : hint_range(0.5, 8.0) = 2.0;

void fragment() {
	float NdotV = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float grazing = 1.0 - NdotV;

	// Parallax: trace the view ray from the surface point down through the ice
	// to depth `subsurface_depth`, sample the albedo at that XZ.
	vec3 to_cam_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 view_world = -to_cam_world;                  // camera -> fragment
	float vy = min(view_world.y, -0.001);             // guard near-horizontal
	vec2 xz_offset = (-subsurface_depth / vy) * view_world.xz;
	vec2 uv = UV + xz_offset / rink_size;

	vec3 base = texture(albedo_tex, uv).rgb;

	// Fade lines toward ice fog at grazing.
	float fade = pow(grazing, grazing_falloff) * subsurface_fade;
	vec3 albedo = mix(base, ice_fog_color, fade);

	ALBEDO = albedo;
	METALLIC = 0.0;
	SPECULAR = specular_strength;
	ROUGHNESS = mix(roughness_head_on, roughness_grazing, grazing * grazing);
}
