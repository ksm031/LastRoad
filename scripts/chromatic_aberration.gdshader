shader_type canvas_item;

uniform float offset : hint_range(0.0, 5.0) = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// 화면 중앙으로부터의 거리 (가장자리로 갈수록 색수차 강화)
	float dist = distance(uv, vec2(0.5));
	float shift = offset * 0.001 * dist;
	
	float r = texture(screen_texture, uv + vec2(shift, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(shift, 0.0)).b;
	
	COLOR = vec4(r, g, b, 1.0);
}
