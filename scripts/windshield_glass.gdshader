shader_type canvas_item;

const int MAX_DROPS = 350;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2  screen_size = vec2(1280.0, 720.0);
uniform vec4  drops[MAX_DROPS];                  // xy=pos(px), z=radius(px), w=stretch
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 pixel = SCREEN_UV * screen_size;
	vec2 total_offset = vec2(0.0);
	float highlight    = 0.0;
	float drop_mask    = 0.0;   // 방울 내부 누적 마스크 (틴트용)

	for (int i = 0; i < MAX_DROPS; i++) {
		vec4 d = drops[i];
		if (d.z < 0.5) continue;

		vec2 local = pixel - d.xy;
		float stretch = d.w;
		float ly = local.y / stretch;

		// 💧 위쪽 뾰족
		float tx = local.x;
		if (stretch > 1.12) {
			float y_norm = ly / d.z;
			float top_f  = max(-y_norm, 0.0);
			tx *= 1.0 + top_f * (stretch - 1.0) * 1.25;
		}

		vec2  eff = vec2(tx, ly);
		float dsq = dot(eff, eff);
		float rsq = d.z * d.z;
		if (dsq >= rsq) continue;

		float dist       = sqrt(dsq);
		float n          = dist / d.z;
		vec2  dir_eff    = eff / max(dist, 0.0001);
		vec2  dir_screen = normalize(vec2(dir_eff.x, dir_eff.y * stretch));

		// 구면 렌즈 굴절
		float ang = n * 1.57079632;
		float refract_strength = sin(ang) * cos(ang);
		total_offset -= dir_screen * refract_strength * d.z * 3.2;

		// 방울 내부 마스크 (가장자리→0, 중심→1)
		drop_mask = max(drop_mask, 1.0 - n * n);

		// 스펙큘러 하이라이트
		vec2  light_dir = normalize(vec2(-0.55, -0.8));
		float ldot = dot(-dir_screen, light_dir);
		float hi = smoothstep(0.35, 1.0, ldot)
			* smoothstep(0.3, 0.8, n)
			* smoothstep(1.0, 0.88, n);
		highlight = max(highlight, hi);
	}

	vec2 refract_uv = SCREEN_UV + total_offset / screen_size;

	// 색수차
	vec2  ca    = total_offset * 0.08 / screen_size;
	float red   = texture(screen_texture, refract_uv + ca).r;
	float green = texture(screen_texture, refract_uv).g;
	float blue  = texture(screen_texture, refract_uv - ca).b;
	vec3  refracted = vec3(red, green, blue);

	// ── 방울 자체에만 물 색 틴트 ─────────────────────────────
	// 실제 물방울은 약간 맑고 투명한 파란빛
	vec3 water_color = vec3(0.72, 0.88, 1.00);
	vec3 color = mix(refracted, refracted * water_color, drop_mask * 0.28);

	// 스펙큘러
	color += vec3(1.0, 0.98, 0.94) * highlight * 0.70;

	COLOR = vec4(color, 1.0);
}
