shader_type canvas_item;

const int MAX_DROPS = 350;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2  screen_size = vec2(1280.0, 720.0);
uniform vec4  drops[MAX_DROPS];                  // xy=pos(px), z=radius(px), w=stretch
uniform sampler2D wipe_mask : hint_default_white; // 와이퍼로 지워진 안개 마스크

// 카메라 파라미터 — 유리 효과가 카메라 줌에 따라 같이 이동하도록
uniform vec2  cam_center_uv = vec2(0.5, 0.5);  // 카메라 위치 (0-1 UV 공간)
uniform float cam_zoom = 1.0;

void fragment() {
	vec2 pixel = SCREEN_UV * screen_size;

	// 룸미러 영역 (스크린 좌표) — 앞유리 효과 없이 원본 그대로
	bool in_mirror = pixel.x >= 535.0 && pixel.x <= 795.0
	              && pixel.y >= 44.0  && pixel.y <= 118.0;

	// 스크린 픽셀 → 유리면 좌표 (카메라 줌 역변환)
	vec2 glass_pixel = (pixel - screen_size * 0.5) / cam_zoom + cam_center_uv * screen_size;

	vec2 total_offset = vec2(0.0);
	float highlight    = 0.0;
	float drop_mask    = 0.0;

	for (int i = 0; i < MAX_DROPS; i++) {
		vec4 d = drops[i];
		if (d.z < 0.5) continue;

		vec2 local = glass_pixel - d.xy;   // 유리면 좌표로 거리 계산
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

		drop_mask = max(drop_mask, 1.0 - n * n);

		// 스펙큘러 하이라이트
		vec2  light_dir = normalize(vec2(-0.55, -0.8));
		float ldot = dot(-dir_screen, light_dir);
		float hi = smoothstep(0.35, 1.0, ldot)
			* smoothstep(0.3, 0.8, n)
			* smoothstep(1.0, 0.88, n);
		highlight = max(highlight, hi);
	}

	// 유리면 UV (카메라 줌 보정) — wipe_mask 샘플링에 사용
	vec2 glass_uv = (SCREEN_UV - 0.5) / cam_zoom + cam_center_uv;

	// 굴절된 유리 UV → 스크린 UV로 역변환
	vec2 refracted_glass_uv = glass_uv + total_offset / screen_size;
	vec2 refract_uv = (refracted_glass_uv - cam_center_uv) * cam_zoom + 0.5;

	// 마스크 텍스처에서 안개 농도
	float fog_factor = texture(wipe_mask, glass_uv).r;
	float blur_lod = fog_factor * 2.2;

	// 색수차 (유리면 → 스크린 UV 스케일 보정)
	vec2  ca    = total_offset * cam_zoom * 0.08 / screen_size;
	float red   = textureLod(screen_texture, refract_uv + ca, blur_lod).r;
	float green = textureLod(screen_texture, refract_uv, blur_lod).g;
	float blue  = textureLod(screen_texture, refract_uv - ca, blur_lod).b;
	vec3  refracted = vec3(red, green, blue);

	// 방울 자체에만 물 색 틴트
	vec3 water_color = vec3(0.72, 0.88, 1.00);
	vec3 color = mix(refracted, refracted * water_color, drop_mask * 0.28);

	// 전체 유리 물막/김서림 틴트
	vec3 glass_tint = vec3(0.8, 0.85, 0.9);
	color = mix(color, glass_tint, fog_factor * 0.15);

	// 스펙큘러
	color += vec3(1.0, 0.98, 0.94) * highlight * 0.70;

	// 룸미러 영역은 유리 효과 없이 원본
	vec3 raw = texture(screen_texture, SCREEN_UV).rgb;
	COLOR = vec4(in_mirror ? raw : color, 1.0);
}
