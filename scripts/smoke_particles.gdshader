shader_type particles;

// ── 파티클 운동 및 곡선 유니폼 변수 ──
uniform float rise_speed = 35.0;            // 상승 속도 (부드럽고 느리게 피어오름)
uniform float sway_amplitude = 42.0;        // 좌우 흔들림 최대 폭 (진폭)
uniform float sway_frequency = 0.015;       // 높이에 따른 물결 빈도 (주파수)
uniform float sway_speed = 1.2;             // 시간 경과에 따른 흐름 속도
uniform float particle_lifetime = 8.0;      // 화면 중간쯤에서 소멸되도록 수명 단축
uniform float trajectory_offset = 0.0;      // 두 연기 줄기 간의 궤적 차이를 위한 위상 오프셋
uniform float branch_direction = 0.0;       // 좌우 분기 방향 (-1.0 = 좌, 1.0 = 우)

// 크기 조절 (기존 대비 1.2배 확대 유지)
uniform float scale_min = 0.06;             // 시작 크기 배율
uniform float scale_max = 0.66;             // 소멸 크기 배율

// ── 난수 생성기 (파티클별 페이즈 분산용) ──
float hash(uint index) {
	float x = sin(float(index) * 12.9898) * 43758.5453;
	return x - floor(x);
}

void start() {
	// 1. 파티클 스폰 시 초기화
	TRANSFORM = EMISSION_TRANSFORM;
	
	// Y축 위쪽으로 올라가는 초기 속도 벡터 지정
	VELOCITY = vec3(0.0, -rise_speed, 0.0);
	
	// CUSTOM.x 에 파티클 고유의 위상 오프셋 지정
	CUSTOM.x = hash(INDEX) * 12.5;
	
	// CUSTOM.y 에 파티클의 현재 수명 기록 (0.0으로 시작)
	CUSTOM.y = 0.0;
	
	// CUSTOM.z 에 생성 당시의 이미터 글로벌 X 좌표 저장
	CUSTOM.z = EMISSION_TRANSFORM[3].x;
	
	// CUSTOM.w 에 생성 당시의 이미터 글로벌 Y 좌표 저장
	CUSTOM.w = EMISSION_TRANSFORM[3].y;
	
	// 초기 색상 및 알파 지정 (투명)
	COLOR = vec4(0.85, 0.88, 0.93, 0.0);
}

void process() {
	// 2. 파티클 매 프레임 위치 및 비주얼 계산
	CUSTOM.y += DELTA;
	float age_ratio = CUSTOM.y / particle_lifetime;
	
	// 수명이 만료되면 파티클 소멸
	if (age_ratio >= 1.0) {
		ACTIVE = false;
	}
	
	// 수직 위쪽 방향으로 매 프레임 이동 누적
	TRANSFORM[3].xyz += VELOCITY * DELTA;
	
	// ── ★ 생성 원점은 고정된 채, 날아가는 입자가 곡선 비행을 하도록 셋업 ──
	float height = CUSTOM.w - TRANSFORM[3].y;
	
	// 지수함수(pow)를 적용하여 위로 올라갈수록 흔들리는 범위가 가속되며 극적으로 넓어지도록 변경
	float height_factor = clamp(pow(height / 150.0, 1.4) * 0.8 + 0.18, 0.18, 4.0);
	
	// 시간에 따른 분기 팩터 (처음 0.3초/0.05비율 동안은 0, 이후 점진적으로 1로 증가)
	float split_factor = smoothstep(0.05, 0.45, age_ratio);
	float current_offset = trajectory_offset * split_factor;

	// ── 예측할 수 없이 울렁이는 복합 곡선 구현 (두 파동의 간섭 효과) ──
	// 모든 입자의 위상을 동기화하여 상승할 때 토네이도/나선형으로 서로 꼬이는 현상을 완전히 배제함
	
	// 파동 1 (기본 상승 파동 + 궤적 차별화 오프셋)
	float phase1 = height * sway_frequency + TIME * sway_speed + current_offset;
	float wave1 = sin(phase1) * 0.75 + sin(phase1 * 2.2) * 0.15;
	
	// 파동 2 (반대 방향 및 저주파 변조 파동 - 두 파동이 겹치며 예측 불가능한 흐름 유도)
	float phase2 = height * (sway_frequency * 0.65) - TIME * (sway_speed * 0.78) + current_offset * 0.7;
	float wave2 = cos(phase2) * 0.35 + sin(phase2 * 1.7) * 0.1;
	
	float wave = wave1 + wave2;
	
	// 파티클별 개별적인 수평 표류 속도(drift) 추가 (위쪽으로 상승할수록 자연스럽게 퍼지도록 유도)
	float drift_rate = (hash(INDEX + 2u) - 0.5) * 20.0; // 초당 -10px ~ +10px 표류
	float individual_drift = drift_rate * CUSTOM.y * pow(age_ratio, 1.5);
	
	// 두 가닥이 Y자 형태로 좌우로 분기되도록 벌려주는 강제적 오프셋 적용
	float branch_offset = branch_direction * 35.0 * pow(age_ratio, 1.8) * split_factor;
	
	// 개별 파티클 고유의 미세한 흔들림(Micro-Wiggle) 계산: 경향성 속의 불규칙성 부여
	// 스폰 직후에는 0에 수렴하여 완전 일치하고, 상승하여 나이가 들수록 무작위 궤적 분기가 일어남
	float micro_phase = height * (sway_frequency * 2.2) + TIME * (sway_speed * 1.5) + CUSTOM.x;
	float micro_wave = sin(micro_phase) * 0.35 + cos(micro_phase * 2.2) * 0.15;
	float individual_variance = micro_wave * 70.0 * pow(age_ratio, 1.1);
	
	// X축 좌표를 생성 당시의 기준 X에 흔들림 값 + 개별 분산 표류 + 좌우 분기 오프셋 + 개별 마이크로 변위를 합산하여 셋업
	TRANSFORM[3].x = CUSTOM.z + wave * sway_amplitude * height_factor + individual_drift + branch_offset + individual_variance;
	
	// ── 수명 비율에 따른 서서히 부푸는 크기(Scale) 계산 (초반에 급격하게 성장하도록 거듭제곱 적용) ──
	float current_scale = mix(scale_min, scale_max, pow(age_ratio, 0.55));
	
	// 기존 TRANSFORM 행렬의 Basis 스케일 적용 (회전을 고려하여 안전하게 대입)
	TRANSFORM[0].xyz = normalize(TRANSFORM[0].xyz) * current_scale;
	TRANSFORM[1].xyz = normalize(TRANSFORM[1].xyz) * current_scale;
	TRANSFORM[2].xyz = normalize(TRANSFORM[2].xyz) * current_scale;
	
	// ── 수명 비율에 따른 투명도(Alpha) 보간 ──
	float alpha = 0.0;
	if (age_ratio < 0.15) {
		alpha = (age_ratio / 0.15) * 0.12;                  // 스폰 직후 부드러운 페이드인
	} else if (age_ratio < 0.60) {
		alpha = 0.12;                                       // 중간 안정 구간 유지
	} else {
		alpha = 0.12 * (1.0 - (age_ratio - 0.60) / 0.40);    // 60% 수명 이후 급격하게 페이드아웃하여 잔상 및 꼬임 원천 제거
	}
	
	// 자연스럽게 뭉게뭉게 올라가는 밀도감(Billowing)을 시뮬레이션하기 위해 시간/높이 기반 파동으로 알파 변조
	alpha *= (0.85 + 0.18 * sin(TIME * 6.5 - height * 0.045));
	
	COLOR = vec4(0.85, 0.88, 0.93, alpha);
}
