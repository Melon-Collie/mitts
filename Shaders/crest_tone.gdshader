// Mutes a crest drawn behind lettering: its colour pulled toward its own grey,
// then darkened, so the fruit still reads as itself under white text.
shader_type canvas_item;

uniform float saturation : hint_range(0.0, 1.0) = 1.0;
uniform float value : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float grey = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(vec3(grey), COLOR.rgb, saturation) * value;
}
