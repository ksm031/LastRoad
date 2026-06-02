shader_type canvas_item;

uniform float offset : hint_range(0.0, 30.0) = 0.0;
uniform float wave_speed : hint_range(0.0, 10.0) = 2.0;
uniform float wave_frequency : hint_range(0.0, 100.0) = 15.0;
uniform float time_phase : hint_range(0.0, 1000.0) = 0.0;
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 base = texture(screen_texture, uv);
	vec3 col;

	if (offset <= 0.01) {
		col = base.rgb;
	} else {
		float distortion = sin(uv.y * wave_frequency + time_phase * wave_speed)
			* cos(uv.x * wave_frequency * 0.8 + time_phase * wave_speed * 0.9);
		float dist_center = distance(uv, vec2(0.5));

		vec2 wave_offset = vec2(distortion) * 0.0012 * offset * (0.3 + dist_center * 1.4);
		vec2 distorted_uv = clamp(uv + wave_offset, vec2(0.001), vec2(0.999));

		float shift = offset * 0.0018 * dist_center;

		float r = texture(screen_texture, clamp(distorted_uv + vec2(shift, 0.0), vec2(0.001), vec2(0.999))).r;
		float g = texture(screen_texture, distorted_uv).g;
		float b = texture(screen_texture, clamp(distorted_uv - vec2(shift, 0.0), vec2(0.001), vec2(0.999))).b;
		col = vec3(r, g, b);
	}

	// desaturation 적용 (붉은색 보존)
	float luminance = dot(col, vec3(0.299, 0.587, 0.114));
	float red_dominance = max(0.0, col.r - max(col.g, col.b));
	float local_desat = desaturation * (1.0 - clamp(red_dominance * 2.5, 0.0, 1.0));
	col = mix(col, vec3(luminance), local_desat);

	COLOR = vec4(col, base.a);
}

