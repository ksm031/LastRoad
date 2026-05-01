extends Node
class_name LastRoadVehicle

const _Road = preload("res://scripts/road_renderer.gd")

# ── 차량 파라미터 ────────────────────────────────────────────
const MAX_SPEED     := 240.0   # km/h
const ACCEL         := 11.0    # km/h/s  (제로백 ~9초, 일반 승용차 수준)
const BRAKE_FORCE   := 35.0    # km/h/s  (100→0 약 2.9초, 일반 차량 기준)
const DRAG          := 5.0     # 자연 감속 (엔진 브레이크 수준)
const LATERAL_SPEED := 2.5     # cam_x(차선) 단위/초

# ── 연료 파라미터 ────────────────────────────────────────────
const FUEL_MAX           := 40.0   # L  (기본 탱크 용량)
const FUEL_RATE_BASE     := 5.5    # L/km  (기본 소모율)
# scroll_z 1.0 = SCROLL_RATE(0.05) * speed(km/h) * dt
# 1 km ≈ scroll_z 50  (SCROLL_RATE * 1000).  따라서  L/s = FUEL_RATE_BASE * speed * SCROLL_RATE / 1000 * speed?  아니요.
# 세계 단위 변환: 1 km = 1000 m. scroll_z 단위는 "세계 단위". SCROLL_RATE = 0.05 → speed 100 km/h 에서 5.0 /s.
# 1 km ≈ 어떤 scroll_z? → scroll_z는 실제 거리 단위가 아니므로,
# 우리는 단순히  km/h → km/s 변환 후 소모율을 곱합니다.
# fuel_consumed_per_sec = (speed_km_h / 3600.0) * FUEL_RATE_BASE
# 이러면 100 km/h 에서  100/3600 * 5.5 ≈ 0.153 L/s  →  40L로 약 261초(4.3분) 주행 가능
# GDD 기준: 만땅 40L로 7.2 km → 80 km/h 기본속도에서  7.2/80*3600 = 324초(5.4분)
# → 소모율 조정:  fuel/s = speed / 3600 * FUEL_RATE_BASE * FUEL_DRAIN_MULT
const FUEL_DRAIN_MULT    := 0.75   # 밸런스 조정용 배율 (GDD 기준 만땅 ~5분 주행)
const FUEL_EMPTY_MAX_SPD := 15.0   # 0L 시 최고속도 (기어가는 수준)

# ── 핸들 파라미터 ────────────────────────────────────────────
const MAX_STEER_DEG := 35.0
const STEER_SPEED   := 150.0

# ── 코너 자동 조향(핸들 비주얼용) ─────────────────────────────
# k(곡률) -> 조향각(도). 너무 세면 과장되어 보이므로 작게.
const AUTO_STEER_GAIN_DEG := 220.0
const AUTO_STEER_MAX_DEG  := 18.0
# 플레이어 입력은 "기본 조향"에 더해지는 오프셋
const PLAYER_STEER_MAX_DEG := 16.0

# ── 스크롤 ───────────────────────────────────────────────────
const SCROLL_RATE := 0.05

# ── 코스(반복): len=구간 길이(세계 z), k=곡률(좌·우 코너, 클수록 급) ──
const COURSE: Array[Dictionary] = [
	{ "len": 52.0, "k": 0.0 },
	{ "len": 72.0, "k": -0.09 },
	{ "len": 48.0, "k": 0.0 },
	{ "len": 78.0, "k": 0.08 },
	{ "len": 46.0, "k": 0.0 },
	{ "len": 68.0, "k": -0.075 },
	{ "len": 56.0, "k": 0.0 },
]
var _course_length: float = -1.0

const HILL_AMP_PX  := 22.0   # 최대 상하 이동(픽셀) — 체감용(주기 없는 노이즈라 숨쉬는 느낌 적음)
const HILL_SEG_LEN := 85.0   # 세계 z 기준 한 덩어리 길이(작을수록 변화가 빨라져 언덕 체감↑)

# ── RPM / 기어 파라미터 ───────────────────────────────────────
const IDLE_RPM    := 800.0
const REDLINE_RPM := 7200.0

# 스로틀 위치별 변속 RPM (현실 자동변속기 동작)
# - 가속 중(W 눌림): 높은 RPM까지 끌어올린 뒤 변속 (가속력 확보)
# - 코스팅(W 안 눌림): 낮은 RPM에서 일찍 업시프트 (연비/조용한 주행)
const SHIFT_UP_THROTTLE := 6300.0
const SHIFT_UP_COAST    := 2200.0
const SHIFT_DOWN_NORMAL := 1200.0   # 평상시 다운시프트
const SHIFT_DOWN_KICKDN := 4200.0   # W + 저RPM → 토크 확보용 강제 다운시프트
const SHIFT_DOWN_BRAKE  := 2600.0   # S 눌렀을 때 엔진 브레이크용 다운시프트

# 변속 후 잠금 시간 — 기어 헌팅 방지
const SHIFT_LOCKOUT     := 0.35
# 변속 순간 RPM 흔들림 — 실제 변속감
const SHIFT_RPM_DROP    := 400.0    # 업시프트 시 RPM 살짝 떨어짐
const SHIFT_RPM_BLIP    := 350.0    # 다운시프트 시 RPM 살짝 올라감

const GEAR_RATIO  := [200.0, 100.0, 65.0, 48.0, 38.0, 32.0]

# ── 상태 ─────────────────────────────────────────────────────
var speed          : float = 0.0
var cam_x          : float = 0.0
var scroll_z       : float = 0.0
var steering_angle : float = 0.0
var rpm            : float = 800.0
var gear           : int   = 0
var _player_steer_offset : float = 0.0
var _shift_lockout       : float = 0.0

# ── 연료 상태 ────────────────────────────────────────────────
var fuel           : float = FUEL_MAX  # 현재 연료 (L)
var fuel_ratio     : float = 1.0       # fuel / FUEL_MAX (0~1), HUD 표시용

# ── 방해물(돌) 패널티 ─────────────────────────────────────────
const ROCK_HIT_SPEED   := 15.0  # “시속 10km대”
const ACCEL_LOCK_TIME  := 0.2
var _accel_lock: float = 0.0

func _course_total_length() -> float:
	if _course_length < 0.0:
		_course_length = 0.0
		for s in COURSE:
			_course_length += float(s["len"])
	return _course_length


## 현재 주행 거리 기준 구간 곡률 (직선이면 0)
func curvature_at_scroll() -> float:
	return curvature_at_z_world(scroll_z)


## 도로 스트립별 누적 횡오프셋 (의사 3D 코너). `road_renderer` 스트립 수와 동일해야 함.
func compute_strip_curve_offsets() -> PackedFloat32Array:
	var n   := _Road.NUM_STRIPS
	var out := PackedFloat32Array()
	out.resize(n)
	var sh  := _Road.SCREEN_H
	var hy  := _Road.HORIZON_Y
	var rby := _Road.ROAD_BOTTOM_Y
	var cd  := _Road.CAMERA_DEPTH
	# 카메라(i=0, x=0) → 지평선(i=n-1) 방향으로 적분.
	# 차 바로 앞은 직선, 먼 거리에서 커브가 보이는 것이 올바른 방향.
	var x       := 0.0
	var dx      := 0.0
	var prev_wz := scroll_z + cd
	for i in range(0, n):
		var t     := float(i) / float(n)
		var y_bot := lerpf(sh, hy, t)
		var depth := clampf((y_bot - hy) / (rby - hy), 0.008, 1.0)
		var wz    := scroll_z + cd / depth
		var dz    := minf(maxf(wz - prev_wz, 0.0), 2.0)
		prev_wz   = wz
		dx += curvature_at_z_world(wz) * dz * 3.5
		x  += dx
		out[i]   = x
	return out


func curvature_at_z_world(z: float) -> float:
	var L := _course_total_length()
	if L <= 0.0:
		return 0.0
	var zz := fposmod(z, L)
	var acc := 0.0
	for s in COURSE:
		var sl := float(s["len"])
		if zz < acc + sl:
			return float(s["k"])
		acc += sl
	return 0.0


## 현재 위치의 언덕 오프셋(픽셀). +면 지평선이 아래로 내려가(내리막 느낌), -면 위로 올라감.
func hill_offset_px() -> float:
	# 규칙적인 사인파는 “배경이 숨 쉬는” 느낌이 나기 쉬움 → 결정적(시드 없는) 1D 밸류 노이즈로 완만하게
	var z := scroll_z / HILL_SEG_LEN
	var i0 := int(floorf(z))
	var t := z - float(i0)
	# smoothstep
	t = t * t * (3.0 - 2.0 * t)

	var v0 := _hill_hash(i0)
	var v1 := _hill_hash(i0 + 1)
	return lerpf(v0, v1, t) * HILL_AMP_PX


func _hill_hash(i: int) -> float:
	# [-1, 1] 범위의 결정적 값 (LCG 기반)
	# GDScript에는 uint32()가 없으므로 int + 마스킹으로 32-bit처럼 취급
	var h := int((i * 1664525 + 1013904223) & 0x7fffffff)
	var x := float(h & 0xFFFF) / 65535.0
	return x * 2.0 - 1.0

func handle_input(delta: float) -> void:
	if _accel_lock > 0.0:
		_accel_lock = maxf(_accel_lock - delta, 0.0)

	var v_pressed := Input.is_key_pressed(KEY_V)
	var w := Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	var s := Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")
	var a := (Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left")) and not v_pressed
	var d := (Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right")) and not v_pressed

	if _accel_lock > 0.0:
		w = false

	# 연료에 따른 실효 최고속도 계산
	var effective_max := _get_effective_max_speed()

	if w:
		speed = minf(speed + ACCEL * delta, effective_max)
	elif s:
		speed = maxf(speed - BRAKE_FORCE * delta, 0.0)
	else:
		speed = maxf(speed - DRAG * delta, 0.0)

	# 연료 0이면 현재 속도도 실효 최고속도 이하로 자연 감속
	if speed > effective_max:
		speed = maxf(speed - DRAG * 2.0 * delta, effective_max)

	# 차량 속도에 비례하여 좌우 조향(차선 변경) 속도 조절
	var lateral_mult := clampf(speed / 50.0, 0.0, 1.0)
	if a:
		cam_x = maxf(cam_x - LATERAL_SPEED * lateral_mult * delta, -1.0)
	elif d:
		cam_x = minf(cam_x + LATERAL_SPEED * lateral_mult * delta, 1.0)

	# 코너 구간이면 기본으로 핸들이 돌아가고, A/D는 거기에 "추가로" 더 꺾는 방식
	var k := curvature_at_scroll()
	var auto := clampf(k * AUTO_STEER_GAIN_DEG, -AUTO_STEER_MAX_DEG, AUTO_STEER_MAX_DEG)

	var target_off := 0.0
	if a:
		target_off = -PLAYER_STEER_MAX_DEG
	elif d:
		target_off = PLAYER_STEER_MAX_DEG
	_player_steer_offset = move_toward(_player_steer_offset, target_off, STEER_SPEED * delta)

	var target_steer := clampf(auto + _player_steer_offset, -MAX_STEER_DEG, MAX_STEER_DEG)
	steering_angle = move_toward(steering_angle, target_steer, STEER_SPEED * delta)

func update_scroll(delta: float) -> void:
	scroll_z += speed * SCROLL_RATE * delta


## 매 프레임 연료 소모. game_world._process()에서 update_scroll 다음에 호출.
func update_fuel(delta: float) -> void:
	if fuel <= 0.0:
		fuel = 0.0
		fuel_ratio = 0.0
		return
	# 소모량 = (속도 km/h → km/s) × 소모율(L/km) × 밸런스 배율
	var consumption := (speed / 3600.0) * FUEL_RATE_BASE * FUEL_DRAIN_MULT
	fuel = maxf(fuel - consumption * delta, 0.0)
	fuel_ratio = fuel / FUEL_MAX


## 연료 잔량에 따른 실효 최고속도
func _get_effective_max_speed() -> float:
	if fuel > 0.0:
		return MAX_SPEED
	# 연료 0: 엔진 꺼짐 → 관성 주행, 최고속도 급감
	return FUEL_EMPTY_MAX_SPD

func update_rpm(delta: float) -> void:
	_shift_lockout = maxf(_shift_lockout - delta, 0.0)

	# 정차 상태: 1단 + 아이들 RPM
	if speed < 1.0:
		gear = 0
		rpm = move_toward(rpm, IDLE_RPM, 3000.0 * delta)
		return

	var w_pressed := Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	var s_pressed := Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")

	if _shift_lockout <= 0.0:
		# 업시프트: 스로틀 위치에 따라 변속 RPM 다름
		var shift_up_rpm := SHIFT_UP_THROTTLE if w_pressed else SHIFT_UP_COAST
		if rpm > shift_up_rpm and gear < GEAR_RATIO.size() - 1:
			# 다음 기어에서 RPM이 idle 밑으로 떨어지지 않을 때만 변속
			var rpm_after_up := speed * GEAR_RATIO[gear + 1]
			if rpm_after_up > IDLE_RPM:
				gear += 1
				rpm = maxf(rpm - SHIFT_RPM_DROP, IDLE_RPM)
				_shift_lockout = SHIFT_LOCKOUT
		# 다운시프트: 일반 / 킥다운 / 엔진브레이크
		elif gear > 0:
			var rpm_at_current := speed * GEAR_RATIO[gear]
			var rpm_after_down := speed * GEAR_RATIO[gear - 1]
			var should_downshift := false

			if rpm_at_current < SHIFT_DOWN_NORMAL:
				# 평상시 다운시프트 (속도 너무 낮음)
				should_downshift = true
			elif w_pressed and rpm_at_current < SHIFT_DOWN_KICKDN and rpm_after_down < REDLINE_RPM:
				# 킥다운: 가속 요청 + 낮은 RPM = 토크 확보를 위한 다운시프트
				should_downshift = true
			elif s_pressed and rpm_at_current < SHIFT_DOWN_BRAKE and rpm_after_down < REDLINE_RPM:
				# 엔진 브레이크: 감속 중 다운시프트로 엔진 회전저항 활용
				should_downshift = true

			if should_downshift:
				gear -= 1
				rpm = minf(rpm + SHIFT_RPM_BLIP, REDLINE_RPM)
				_shift_lockout = SHIFT_LOCKOUT

	# 목표 RPM = 속도 * 기어비, 단 아이들 ~ 레드라인 사이로 클램프
	var target_rpm := clampf(speed * GEAR_RATIO[gear], IDLE_RPM, REDLINE_RPM)
	rpm = move_toward(rpm, target_rpm, 2500.0 * delta)


func apply_rock_hit() -> void:
	# 속도 급락 + 잠깐 가속 불가
	speed = minf(speed, ROCK_HIT_SPEED)
	if speed < ROCK_HIT_SPEED:
		speed = ROCK_HIT_SPEED
	_accel_lock = ACCEL_LOCK_TIME

func apply_watcher_hit() -> void:
	# 와쳐 충돌: 속도 살짝 감소 (20% 감속) + 짧은 가속 불가
	speed *= 0.8
	_accel_lock = 0.1
