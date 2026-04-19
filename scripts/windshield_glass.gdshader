shader_type canvas_item;

const int MAX_DROPS = 200;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2  screen_size = vec2(1280.0, 720.0);
uniform vec4  drops[MAX_DROPS];                  // xy=pos(px), z=radius(px), w=stretch
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 pixel = SCREEN_UV * screen_size;
	vec2 total_offset = vec2(0.0);
	float highlight = 0.0;

	for (int i = 0; i < MAX_DROPS; i++) {
		vec4 d = drops[i];
		if (d.z < 0.5) continue;                // 비활성 슬롯

		vec2 local = pixel - d.xy;
		float stretch = d.w;

		// 수직 방향 스트레치 (미끄러지는 방울)
		float ly = local.y / stretch;

		// 💧 모양: 위쪽이 뾰족 (stretch가 클수록 강해짐)
		float tx = local.x;
		if (stretch > 1.12) {
			float y_norm = ly / d.z;            // -1 top, +1 bottom
			float top_f = max(-y_norm, 0.0);
			tx *= 1.0 + top_f * (stretch - 1.0) * 1.25;
		}

		vec2 eff = vec2(tx, ly);
		float dsq = dot(eff, eff);
		float rsq = d.z * d.z;
		if (dsq >= rsq) continue;

		float dist = sqrt(dsq);
		float n = dist / d.z;
		vec2 dir_eff = eff / max(dist, 0.0001);
		// 실제 스크린 방향으로 복원 (스트레치 반영)
		vec2 dir_screen = normalize(vec2(dir_eff.x, dir_eff.y * stretch));

		// 구면 렌즈 굴절: sin*cos → n≈0.7에서 최대
		float ang = n * 1.57079632;
		float refract_strength = sin(ang) * cos(ang);
		total_offset -= dir_screen * refract_strength * d.z * 1.05;

		// 좌상단 방향광 스펙큘러
		vec2 light_dir = normalize(vec2(-0.55, -0.8));
		float ldot = dot(-dir_screen, light_dir);
		float hi = smoothstep(0.35, 1.0, ldot)
			* smoothstep(0.3, 0.8, n)
			* smoothstep(1.0, 0.88, n);
		highlight = max(highlight, hi);
	}

	vec2 refract_uv = SCREEN_UV + total_offset / screen_size;

	// 색수차 — Liquid Glass의 프리즘 느낌
	vec2 ca = total_offset * 0.06 / screen_size;
	float red   = texture(screen_texture, refract_uv + ca).r;
	float green = texture(screen_texture, refract_uv).g;
	float blue  = texture(screen_texture, refract_uv - ca).b;
	vec3 refracted = vec3(red, green, blue);

	// 전체 유리 틴트 (아주 미미하게 — 방울이 주인공)
	vec3 tint = vec3(0.46, 0.56, 0.72);
	float fog = wet_amount * 0.04;
	vec3 color = mix(refracted, tint, fog);

	color += vec3(1.0, 0.98, 0.92) * highlight * 0.55;

	COLOR = vec4(color, 1.0);
}
