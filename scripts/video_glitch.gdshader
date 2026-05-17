shader_type canvas_item;

uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_time : hint_range(0.0, 1000.0) = 0.0;
uniform float glitch_seed : hint_range(0.0, 1000.0) = 0.0;

// 표준 해시 함수
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float gi = glitch_intensity;
	
	if (gi <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = UV;
		float t = glitch_time;
		float sd = glitch_seed;

		// ── 1. 베이스 정적 노이즈 ──
		float static_noise = hash21(uv * vec2(1280.0, 720.0) + vec2(t * 100.0, sd));
		vec3 final_color = vec3(static_noise) * 0.3;
		float final_alpha = static_noise * 0.3 * gi;

		// ── 2. 아주 얇은 수평선 (Layer 1) ──
		float y_res1 = 300.0; 
		float y_id1 = floor(uv.y * y_res1);
		float x_res1 = 3.0 + hash21(vec2(y_id1, sd)) * 20.0; 
		float x_shift1 = t * (hash21(vec2(y_id1, sd + 1.0)) - 0.5) * 15.0; 
		float x_id1 = floor((uv.x + x_shift1) * x_res1);
		
		float noise1 = hash21(vec2(x_id1, y_id1) + vec2(floor(t * 15.0), sd));
		float active1 = step(1.0 - (gi * 0.3), noise1); 

		float c_hash1 = hash21(vec2(x_id1, y_id1) + vec2(sd, floor(t * 8.0)));
		vec3 col1 = vec3(1.0);
		if (c_hash1 > 0.8) col1 = vec3(1.0, 0.0, 0.0);      
		else if (c_hash1 > 0.6) col1 = vec3(0.0, 1.0, 0.0); 
		else if (c_hash1 > 0.4) col1 = vec3(0.0, 0.0, 1.0); 
		else if (c_hash1 > 0.2) col1 = vec3(0.0, 1.0, 1.0); 

		final_color = mix(final_color, col1, active1);
		final_alpha += active1 * 0.7 * gi;

		// ── 3. 조금 짧은 수평 블록 (Layer 2) ──
		float y_res2 = 120.0; 
		float y_id2 = floor(uv.y * y_res2);
		float x_res2 = 25.0 + hash21(vec2(y_id2, sd)) * 50.0; 
		float x_shift2 = t * (hash21(vec2(y_id2, sd + 2.0)) - 0.5) * 5.0;
		float x_id2 = floor((uv.x + x_shift2) * x_res2);
		
		float noise2 = hash21(vec2(x_id2, y_id2) + vec2(floor(t * 20.0), sd + 10.0));
		float active2 = step(1.0 - (gi * 0.15), noise2); 

		float c_hash2 = hash21(vec2(x_id2, y_id2) + vec2(sd, floor(t * 12.0)));
		vec3 col2 = vec3(1.0);
		if (c_hash2 > 0.75) col2 = vec3(1.0, 0.0, 0.0);     
		else if (c_hash2 > 0.5) col2 = vec3(0.0, 1.0, 1.0); 
		else if (c_hash2 > 0.25) col2 = vec3(1.0, 0.0, 1.0);

		final_color = mix(final_color, col2, active2);
		final_alpha += active2 * 0.8 * gi;

		// ── 4. 주사선 (스캔라인) ──
		float scanline = sin(uv.y * 600.0) * 0.5 + 0.5;
		final_alpha *= mix(1.0, scanline, 0.5); 

		// ── 5. 최종 클램핑 ──
		final_alpha = clamp(final_alpha, 0.0, 0.85); 

		COLOR = vec4(final_color, final_alpha);
	}
}
