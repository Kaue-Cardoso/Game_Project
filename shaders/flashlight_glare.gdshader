shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 source_uv = vec2(0.5, 0.5);
uniform float aspect_ratio = 1.0;
uniform vec4 glare_color : source_color = vec4(1.0);

void fragment() {
	vec2 offset = UV - source_uv;
	offset.x *= aspect_ratio;

	float distance_to_light = length(offset);
	float core = 1.0 - smoothstep(0.0, 0.1, distance_to_light);
	float halo = 1.0 - smoothstep(0.0, 0.35, distance_to_light);

	float opacity = strength * (0.4 + halo * 0.35 + core * 0.5);
	COLOR = vec4(glare_color.rgb, clamp(opacity, 0.0, 0.9));
}
