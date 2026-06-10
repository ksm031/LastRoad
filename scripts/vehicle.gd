extends Node
class_name LastRoadVehicle

const _Road = preload("res://scripts/road_renderer.gd")  # NUM_STRIPS 참조용

signal fuel_depleted
signal gear_changed(new_gear: int)

# ── 차량 파라미터 ────────────────────────────────────────────
# ── 공기 저항 및 마찰 (관성 감속용) ───────────────────────────
const _BASE_DRAG         := 5.0     # km/h/s
# ── 차량 기본 파라미터 (업그레이드 전) ─────────────────────────
const MAX_SPEED_BASE     := 90.0    # km/h (초반엔 많이 부족하게 설정)
const ACCEL_BASE         := 5.0     # km/h/s
const BRAKE_FORCE_BASE   := 40.0    # km/h/s
const LATERAL_SPEED_BASE := 1.8     # cam_x(차선) 단위/초
const COLLISION_WIDTH    := 0.6     # 차폭 (차선 단위)

# ── 전투: 속도 임계 처치 (Doc 31 §1) ──────────────────────────
# 충돌 속도가 임계 이상이면 관통 처치, 미만이면 충격 튕김.
const KILL_THRESHOLD_BASE := 80.0   # km/h. 적별 기본값은 game_world에서 가산
const ENGINE_THRESHOLD_PER_LV := 3.0 # 엔진 레벨당 임계 -3 (Lv5 → -15, 최저 65)
const BOUNCE_SPEED_MULT   := 0.65   # 임계 미만 충돌 시 속도 -35%

# ── 실제 적용되는 스탯 (업그레이드 반영) ───────────────────────
var max_speed     : float = MAX_SPEED_BASE
var accel         : float = ACCEL_BASE
var brake_force   : float = BRAKE_FORCE_BASE
var lateral_speed : float = LATERAL_SPEED_BASE
var fuel_max      : float = FUEL_MAX_BASE
var fuel_rate     : float = FUEL_RATE_BASE
var headlight_range : float = 1.0
var traction_factor : float = 1.0  # 1.0 = 정상, < 1.0 = 미끄러움

# ── 메타 퍽 적용 변수 ──
var _meta_progression: Node = null
var _cigarette_buff_time: float = 0.0
var _emergency_fuel_timer: float = 5.0

# ── 차량 내구도 상태 (신규 5파츠) ─────────────────────────────
var dur_lf_tire     : float = 100.0  # 0~100%
var dur_rf_tire     : float = 100.0
var dur_lb_tire     : float = 100.0
var dur_rb_tire     : float = 100.0
var dur_drivetrain  : float = 100.0

# ── 연료 파라미터 ────────────────────────────────────────────
# ── 연료 파라미터 ────────────────────────────────────────────
const FUEL_MAX_BASE      := 40.0   # L
const FUEL_RATE_BASE     := 5.5    # L/km (낮을수록 좋음)
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

# ── 스크롤 (속도감 1.5배 상향) ──────────────────────────────────
const SCROLL_RATE := 0.075

# ── 코스(반복): len=구간 길이(세계 z), k=곡률, h=언덕 높이(픽셀, +내리막 -오르막) ──
const COURSE := [
	{ "len": 52.0, "k":  0.0,    "h":   0.0 },   # 평지 직선
	{ "len": 72.0, "k": -0.09,   "h": -45.0 },   # 왼쪽 코너 오르막
	{ "len": 48.0, "k":  0.0,    "h": -62.0 },   # 직선 급오르막
	{ "len": 78.0, "k":  0.08,   "h":  35.0 },   # 오른쪽 코너 → 내리막 전환
	{ "len": 46.0, "k":  0.0,    "h":  58.0 },   # 직선 내리막
	{ "len": 68.0, "k": -0.075,  "h":  18.0 },   # 왼쪽 코너 내리막 끝
	{ "len": 56.0, "k":  0.0,    "h":   0.0 },   # 평지로 복귀
]
var _course_length: float = -1.0

# 구간 전환 부드럽게: 구간 끝 이 거리부터 다음 h값으로 smoothstep
const HILL_TRANSITION_LEN := 18.0

# 언덕 경사도가 속도에 미치는 영향 계수 (픽셀/초 → km/h/초)
const HILL_ACCEL_FACTOR := 0.12

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

const GEAR_RATIO := [200.0, 100.0, 65.0, 48.0, 38.0, 32.0]

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
var fuel           : float = 40.0      # 현재 연료 (L) - _BASE_FUEL_MAX와 일치시킴
var fuel_ratio     : float = 1.0       # fuel / fuel_max (0~1), HUD 표시용

# ── 방해물(돌) 패널티 ─────────────────────────────────────────
const ROCK_HIT_SPEED   := 15.0  # "시속 10km대"
const ACCEL_LOCK_TIME  := 0.2
var _accel_lock: float = 0.0
var _adrenaline_timer: float = 0.0

# ── 업그레이드 레벨 (0~5) ───────────────────────────────────
var upgrade_levels := {
	"engine": 0,      # 가속 & 최고속도
	"fuel_tank": 0,   # 연료 용량
	"turbine": 0,     # 연비 (연료 소모율 감소)
	"tires": 0,       # 조향 속도 (횡이동)
	"brakes": 0,      # 제동력
	"bumper": 0       # Doc 31 §6: 전투 (임계 속도/관통/내구도)
}

func apply_upgrades(system = null, meta = null) -> void:
	if system:
		if system is VehicleUpgradeSystem:
			upgrade_levels = system.upgrades
		elif system is Dictionary:
			# 기존 방식(Dictionary) 호환성 유지
			upgrade_levels = system
	
	if meta:
		_meta_progression = meta
	
	# ── 베이스 스탯 결정 (퍽 반영) ──
	var p_accel_mult := 1.0
	var p_brake_mult := 1.0
	var p_hand_mult  := 1.0
	var p_speed_add  := 0.0
	var p_fuel_add   := 0.0
	var p_eff_mult   := 1.0
	var p_racer_mult := 1.0
	var p_light_mult := 1.0
	
	if _meta_progression:
		if _meta_progression.has_perk("keen_eye_new"):   p_light_mult *= 1.20
	
	# 엔진: 레벨당 최고속도 +15, 가속 +1.0
	max_speed = (MAX_SPEED_BASE + p_speed_add + float(upgrade_levels["engine"]) * 15.0) * p_racer_mult
	accel     = (ACCEL_BASE     + float(upgrade_levels["engine"]) * 1.2) * p_accel_mult * p_racer_mult
	
	# 연료탱크: 레벨당 +8L
	fuel_max  = FUEL_MAX_BASE  + p_fuel_add + float(upgrade_levels["fuel_tank"]) * 8.0
	
	# 터빈: 레벨당 소모율 -8% (복리)
	fuel_rate = FUEL_RATE_BASE * pow(0.92, float(upgrade_levels["turbine"])) * p_eff_mult
	
	# 타이어: 레벨당 횡속도 +0.2
	lateral_speed = (LATERAL_SPEED_BASE + float(upgrade_levels["tires"]) * 0.2) * p_hand_mult * p_racer_mult
	
	# 브레이크: 레벨당 제동력 +8.0
	brake_force = (BRAKE_FORCE_BASE + float(upgrade_levels["brakes"]) * 8.0) * p_brake_mult * p_racer_mult
	
	# 헤드라이트: 레벨당 조사 거리 +15%
	var buff_mult := 1.5 if _cigarette_buff_time > 0.0 else 1.0
	headlight_range = (1.0 + float(upgrade_levels.get("headlight", 0)) * 0.15) * p_light_mult * buff_mult
	
	# 현재 연료 비율 유지
	fuel_ratio = fuel / fuel_max

func apply_cigarette_buff(duration: float) -> void:
	_cigarette_buff_time = duration
	apply_upgrades(null, _meta_progression)

func update_buffs(delta: float) -> void:
	if _cigarette_buff_time > 0.0:
		_cigarette_buff_time = maxf(_cigarette_buff_time - delta, 0.0)
		if _cigarette_buff_time <= 0.0:
			apply_upgrades(null, _meta_progression)

func apply_emergency_repair() -> void:
	if dur_lf_tire < 30.0:     dur_lf_tire = 30.0
	if dur_rf_tire < 30.0:     dur_rf_tire = 30.0
	if dur_lb_tire < 30.0:     dur_lb_tire = 30.0
	if dur_rb_tire < 30.0:     dur_rb_tire = 30.0
	if dur_drivetrain < 30.0:  dur_drivetrain = 30.0

func _ready() -> void:
	apply_upgrades()


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
	var sh  := BillboardManager.SCREEN_H
	var hy  := BillboardManager.HORIZON_Y
	var rby := BillboardManager.ROAD_BOTTOM_Y
	var cd  := BillboardManager.CAMERA_DEPTH
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


## 현재 위치의 언덕 오프셋(픽셀). +면 지평선이 아래로(내리막), -면 위로(오르막).
## COURSE의 h값 사이를 smoothstep으로 보간.
func hill_offset_px() -> float:
	return _hill_at_z(scroll_z)

func _hill_at_z(z: float) -> float:
	var L := _course_total_length()
	if L <= 0.0:
		return 0.0
	var zz := fposmod(z, L)
	var acc := 0.0
	for i in range(COURSE.size()):
		var sl := float(COURSE[i]["len"])
		if zz < acc + sl:
			var within := zz - acc
			var h_cur := float(COURSE[i]["h"])
			var next_idx := (i + 1) % COURSE.size()
			var h_next := float(COURSE[next_idx]["h"])
			# 구간 끝 HILL_TRANSITION_LEN 거리부터 다음 값으로 smoothstep 전환
			var t := clampf((within - (sl - HILL_TRANSITION_LEN)) / HILL_TRANSITION_LEN, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(h_cur, h_next, t)
		acc += sl
	return 0.0

## 현재 경사도(픽셀/세계z). 양수=내리막, 음수=오르막.
func hill_grade() -> float:
	return (_hill_at_z(scroll_z + 1.0) - _hill_at_z(scroll_z))

func handle_input(delta: float) -> void:
	if _accel_lock > 0.0:
		_accel_lock = maxf(_accel_lock - delta, 0.0)

	var w := Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	var s := Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")
	var a := Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left")
	var d := Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right")

	if _accel_lock > 0.0:
		w = false
	
	# 구동계 간헐 정지 체크 (GDD §4.2: 30초마다 0.5초 가속 무효)
	if update_drivetrain_stall(delta):
		w = false
		
	if _adrenaline_timer > 0.0:
		_adrenaline_timer -= delta

	# ── 연료 소모 및 물리 연산 ──────────────────────────────────
	if speed > 0.1:
		# 연료 소모 공식: L/s = (L/km) * (km/s)
		var consumption := fuel_rate * (speed / 3600.0) * delta
		var prev_fuel := fuel
		fuel = maxf(fuel - consumption, 0.0)
		fuel_ratio = fuel / fuel_max
		
		# 연료가 막 0이 된 순간 신호 발생
		if prev_fuel > 0.0 and fuel <= 0.0:
			fuel_depleted.emit()

	# 가속/제동 판단
	# 내구도 페널티 계산
	var flat_count := 0
	var pull_dir := 0.0
	if dur_lf_tire <= 0.0: 
		flat_count += 1
		pull_dir -= 1.0
	if dur_lb_tire <= 0.0: 
		flat_count += 1
		pull_dir -= 1.0
	if dur_rf_tire <= 0.0: 
		flat_count += 1
		pull_dir += 1.0
	if dur_rb_tire <= 0.0: 
		flat_count += 1
		pull_dir += 1.0

	var effective_max := max_speed
	var effective_accel := accel
	
	# GDD §4.1: 타이어 펑크 정확한 패널티
	if flat_count == 1:
		effective_max  *= 0.75   # 최고속도 -25%
		effective_accel *= 0.70  # 가속력 -30%
	elif flat_count == 2:
		effective_max  *= 0.50   # 최고속도 -50%
		effective_accel *= 0.45  # 가속력 -55%
	elif flat_count >= 3:
		effective_max  = minf(effective_max, 20.0)  # 20km/h 고정
		effective_accel *= 0.20  # 가속력 -80%
		
	if _adrenaline_timer > 0.0:
		effective_accel *= 1.20
		
	if dur_drivetrain <= 0.0:
		# GDD §4.2: 최고속도 30km/h 강제 제한, 가속 -75%
		effective_max   = minf(effective_max, 30.0)
		effective_accel *= 0.25
		
	var can_accel := (fuel > 0.0)
	
	if w:
		if can_accel:
			# 연료 있을 때: 정상 가속 (내구도 페널티 반영)
			speed = minf(speed + effective_accel * delta, effective_max)
		else:
			# 연료 없을 때 (Limp Mode): 시속 15km까지 아주 천천히 가속 가능
			if speed < 15.0:
				speed = minf(speed + (accel * 0.2) * delta, 15.0)
			# 시속 15km 이상일 때는 가속 불가 (관성 주행 중이므로 else에서 처리)
	elif s:
		speed = maxf(speed - brake_force * delta, 0.0)
	
	# 코스팅 (키를 뗐거나, 연료가 없어 가속이 안 되는 상황)
	if not s and (not w or (not can_accel and speed >= 15.0)):
		var target_min := 0.0
		if not can_accel:
			target_min = 15.0 # 연료 없을 때 유지하려는 최소 속도
			
		if speed > target_min:
			# 감속 중
			var drag_factor := _BASE_DRAG * (0.5 if not can_accel else 1.0)
			speed = maxf(speed - drag_factor * delta, target_min)
		elif speed < target_min and not w:
			# 내리막 등에서 속도가 붙었다가 평지에서 감속될 때 등
			pass 

	# 언덕 경사 속도 영향: 오르막 감속, 내리막 가속 (연료 없어도 중력 영향은 받음)
	var grade := hill_grade()
	speed = clampf(speed + grade * HILL_ACCEL_FACTOR * delta, 0.0, effective_max * 1.1)

	# 차량 속도에 비례하여 좌우 조향(차선 변경) 속도 조절 (비 올 때 traction_factor 반영)
	var lateral_mult := clampf(speed / 50.0, 0.0, 1.0) * traction_factor
	var frame_pull = pull_dir * 0.25 * lateral_speed * lateral_mult * delta
	
	var lat_move := 0.0
	if a:
		lat_move = -lateral_speed * lateral_mult * delta
	elif d:
		lat_move = lateral_speed * lateral_mult * delta
		
	cam_x = clampf(cam_x + lat_move + frame_pull, -1.0, 1.0)

	# 코너 구간이면 기본으로 핸들이 돌아가고, A/D는 거기에 "추가로" 더 꺾는 방식
	var k := curvature_at_scroll()
	var auto := clampf(k * AUTO_STEER_GAIN_DEG, -AUTO_STEER_MAX_DEG, AUTO_STEER_MAX_DEG)

	var target_off := 0.0
	if a:
		target_off = -PLAYER_STEER_MAX_DEG
	elif d:
		target_off = PLAYER_STEER_MAX_DEG
	_player_steer_offset = move_toward(_player_steer_offset, target_off, STEER_SPEED * delta * traction_factor)

	var target_steer := clampf(auto + _player_steer_offset, -MAX_STEER_DEG, MAX_STEER_DEG)
	steering_angle = move_toward(steering_angle, target_steer, STEER_SPEED * delta * traction_factor)

func update_scroll(delta: float) -> void:
	scroll_z += speed * SCROLL_RATE * delta


## 매 프레임 연료 소모. game_world._process()에서 update_scroll 다음에 호출.
func update_fuel(delta: float) -> void:
	if fuel <= 0.0:
		fuel = 0.0
		fuel_ratio = 0.0
		if _meta_progression != null and _meta_progression.has_perk("emergency_fuel"):
			_emergency_fuel_timer = maxf(_emergency_fuel_timer - delta, 0.0)
		return
	else:
		_emergency_fuel_timer = 5.0
	# 소모량 = (속도 km/h → km/s) × 소모율(L/km) × 밸런스 배율
	var drain_mult := FUEL_DRAIN_MULT
	if dur_drivetrain <= 0.0:
		drain_mult *= 3.0  # 구동계 망가지면 연비 3배 악화
		
	var consumption := (speed / 3600.0) * fuel_rate * drain_mult
	fuel = maxf(fuel - consumption * delta, 0.0)
	fuel_ratio = fuel / fuel_max


## 연료 잔량에 따른 실효 최고속도
func _get_effective_max_speed() -> float:
	if fuel > 0.0:
		return max_speed
	
	if _meta_progression != null and _meta_progression.has_perk("emergency_fuel") and _emergency_fuel_timer > 0.0:
		return 20.0
		
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
			var rpm_after_up: float = speed * GEAR_RATIO[gear + 1]
			if rpm_after_up > IDLE_RPM:
				gear += 1
				rpm = maxf(rpm - SHIFT_RPM_DROP, IDLE_RPM)
				_shift_lockout = SHIFT_LOCKOUT
		# 다운시프트: 일반 / 킥다운 / 엔진브레이크
		elif gear > 0:
			var rpm_at_current: float = speed * GEAR_RATIO[gear]
			var rpm_after_down: float = speed * GEAR_RATIO[gear - 1]
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
	speed = ROCK_HIT_SPEED
	_accel_lock = ACCEL_LOCK_TIME

func apply_watcher_hit() -> void:
	# 와쳐 충돌: 속도 살짝 감소 (20% 감속) + 짧은 가속 불가
	speed *= 0.8
	_accel_lock = 0.1

# ── 전투: 속도 임계 처치 (Doc 31 §1, §6) ──────────────────────
# 적별 기본 임계값에 엔진·범퍼 업그레이드 하향을 반영한 실효 임계 속도.
func get_kill_threshold(base_threshold: float = KILL_THRESHOLD_BASE) -> float:
	var engine_lv := float(upgrade_levels.get("engine", 0))
	var bumper_lv := int(upgrade_levels.get("bumper", 0))
	var bumper_red := 0.0
	if bumper_lv >= 1: bumper_red += 5.0    # Lv1 강화 고무: -5
	if bumper_lv >= 5: bumper_red += 10.0   # Lv5 전차 돌기: 추가 -10 (총 -15)
	return base_threshold - engine_lv * ENGINE_THRESHOLD_PER_LV - bumper_red

# Doc 31 §6 Lv2: 관통 처치 시 내구도 소모 -25%
func get_pierce_dmg_mult() -> float:
	return 0.75 if int(upgrade_levels.get("bumper", 0)) >= 2 else 1.0

# Doc 31 §6 Lv4: 임계 미만 충돌(튕김) 내구도 손실 -40%
func get_bounce_dmg_mult() -> float:
	return 0.6 if int(upgrade_levels.get("bumper", 0)) >= 4 else 1.0

# Doc 31 §6 Lv3: 관통 수 +1 (1 → 2명 동시 처치)
func get_penetration_count() -> int:
	return 2 if int(upgrade_levels.get("bumper", 0)) >= 3 else 1

# 관통 처치: 모멘텀 유지(속도 감소 없음). 내구도 소모는 호출부에서 처리.
func apply_pierce_kill() -> void:
	pass

# 충격 튕김: 급감속(-35%) + 짧은 가속 불가.
func apply_bounce_hit() -> void:
	speed *= BOUNCE_SPEED_MULT
	_accel_lock = 0.2

func apply_adrenaline_boost() -> void:
	# 와쳐 등 적중 시 속도 유지 + 3초간 가속도 20% 보너스
	_adrenaline_timer = 3.0

# ── 수리 로직 ─────────────────────────────────────────────
func repair_drivetrain(amount: float) -> void:
	dur_drivetrain = minf(dur_drivetrain + amount, 100.0)

func repair_worst_tire(amount: float) -> void:
	var tires = [
		{"name": "lf", "val": dur_lf_tire},
		{"name": "rf", "val": dur_rf_tire},
		{"name": "lb", "val": dur_lb_tire},
		{"name": "rb", "val": dur_rb_tire}
	]
	tires.sort_custom(func(a, b): return a["val"] < b["val"])
	
	var worst = tires[0]["name"]
	match worst:
		"lf": dur_lf_tire = minf(dur_lf_tire + amount, 100.0)
		"rf": dur_rf_tire = minf(dur_rf_tire + amount, 100.0)
		"lb": dur_lb_tire = minf(dur_lb_tire + amount, 100.0)
		"rb": dur_rb_tire = minf(dur_rb_tire + amount, 100.0)

# ── 부품 피해 적용 (GDD 05-parts.md §4.5) ──────────────────────
# contact_type: "front" | "left" | "right" | "side_left" | "side_right" | "all"
# tire_dmg: 해당 타이어 감소량(%), drivetrain_dmg: 구동계 감소량(%)
func apply_part_damage(contact_type: String, tire_dmg: float, drivetrain_dmg: float = 0.0) -> void:
	match contact_type:
		"front":
			# 정면 충돌 → LF + RF 동시
			dur_lf_tire     = maxf(dur_lf_tire     - tire_dmg, 0.0)
			dur_rf_tire     = maxf(dur_rf_tire     - tire_dmg, 0.0)
		"left":
			# 좌측 (갓길 좌측 회피) → LF 단독
			dur_lf_tire     = maxf(dur_lf_tire     - tire_dmg, 0.0)
		"right":
			# 우측 (갓길 우측 회피) → RF 단독
			dur_rf_tire     = maxf(dur_rf_tire     - tire_dmg, 0.0)
		"side_left":
			# 측면 후방 좌측 (앰부서 등) → LB
			dur_lb_tire     = maxf(dur_lb_tire     - tire_dmg, 0.0)
		"side_right":
			# 측면 후방 우측 (앰부서 등) → RB
			dur_rb_tire     = maxf(dur_rb_tire     - tire_dmg, 0.0)
		"all":
			# 전 방향 균등 (사슴머리, 창 등) → 5개 부품 균등
			dur_lf_tire     = maxf(dur_lf_tire     - tire_dmg, 0.0)
			dur_rf_tire     = maxf(dur_rf_tire     - tire_dmg, 0.0)
			dur_lb_tire     = maxf(dur_lb_tire     - tire_dmg, 0.0)
			dur_rb_tire     = maxf(dur_rb_tire     - tire_dmg, 0.0)
	
	if drivetrain_dmg > 0.0:
		dur_drivetrain = maxf(dur_drivetrain - drivetrain_dmg, 0.0)

# ── 구동계 간헐 정지 상태 (GDD §4.2: 30초마다 0.5초간 가속 무효) ──
var _drivetrain_stall_timer: float = 30.0  # 다음 스탈까지 카운트다운
var _drivetrain_stall_active: float = 0.0  # 현재 스탈 지속 시간

func update_drivetrain_stall(delta: float) -> bool:
	# 구동계가 정상이면 타이머 리셋하고 false 반환
	if dur_drivetrain > 0.0:
		_drivetrain_stall_timer = 30.0
		_drivetrain_stall_active = 0.0
		return false
	
	# 스탈 활성 중
	if _drivetrain_stall_active > 0.0:
		_drivetrain_stall_active -= delta
		return true  # 가속 페달 무효
	
	# 스탈 카운트다운
	_drivetrain_stall_timer -= delta
	if _drivetrain_stall_timer <= 0.0:
		_drivetrain_stall_timer = 30.0
		_drivetrain_stall_active = 0.5  # 0.5초간 스탈
		return true
	
	return false
