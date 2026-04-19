extends Node
class_name LastRoadVehicle

const _Road = preload("res://scripts/road_renderer.gd")

# ── 차량 파라미터 ────────────────────────────────────────────
const MAX_SPEED     := 240.0   # km/h
const ACCEL         := 60.0    # km/h/s
const BRAKE_FORCE   := 105.0   # km/h/s (브레이크 감도)
const DRAG          := 20.0    # 자연 감속
const LATERAL_SPEED := 2.5     # cam_x(차선) 단위/초

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
const SHIFT_UP    := 6500.0
const SHIFT_DOWN  := 1500.0
const GEAR_RATIO  := [200.0, 100.0, 65.0, 48.0, 38.0, 32.0]

# ── 상태 ─────────────────────────────────────────────────────
var speed          : float = 0.0
var cam_x          : float = 0.0
var scroll_z       : float = 0.0
var steering_angle : float = 0.0
var rpm            : float = 800.0
var gear           : int   = 0
var _player_steer_offset : float = 0.0

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

	var w := Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	var s := Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")
	var a := Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left")
	var d := Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right")

	if _accel_lock > 0.0:
		w = false

	if w:
		speed = minf(speed + ACCEL * delta, MAX_SPEED)
	elif s:
		speed = maxf(speed - BRAKE_FORCE * delta, 0.0)
	else:
		speed = maxf(speed - DRAG * delta, 0.0)

	if a:
		cam_x = maxf(cam_x - LATERAL_SPEED * delta, -1.0)
	elif d:
		cam_x = minf(cam_x + LATERAL_SPEED * delta, 1.0)

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

func update_rpm(delta: float) -> void:
	if speed < 1.0:
		gear = 0
		rpm = move_toward(rpm, IDLE_RPM, 3000.0 * delta)
		return
	if rpm > SHIFT_UP and gear < GEAR_RATIO.size() - 1:
		gear += 1
	elif gear > 0 and speed * GEAR_RATIO[gear] < SHIFT_DOWN:
		gear -= 1
	var target_rpm := maxf(speed * GEAR_RATIO[gear], IDLE_RPM)
	rpm = move_toward(rpm, target_rpm, 2500.0 * delta)


func apply_rock_hit() -> void:
	# 속도 급락 + 잠깐 가속 불가
	speed = minf(speed, ROCK_HIT_SPEED)
	if speed < ROCK_HIT_SPEED:
		speed = ROCK_HIT_SPEED
	_accel_lock = ACCEL_LOCK_TIME
