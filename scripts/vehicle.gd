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

# ── 언덕(가벼운 출렁임): 화면 픽셀 기준 지평선 오프셋 ───────────────
const HILL_AMP_PX   := 14.0  # 최대 상하 이동(픽셀) — 1번(살짝) 기준
const HILL_FREQ     := 0.11  # z에 대한 주파수 (클수록 자주 출렁)
const HILL_AMP_VAR  := 0.35  # 런마다 약간 다른 느낌(고정 난수 대신 z로 변조)

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
	# 두 개 사인파를 합쳐서 반복감은 줄이고 "살짝 출렁"만 만든다
	var a := sin(scroll_z * HILL_FREQ)
	var b := sin(scroll_z * (HILL_FREQ * 0.63) + 1.7)
	var amp := HILL_AMP_PX * (1.0 - HILL_AMP_VAR) + HILL_AMP_PX * HILL_AMP_VAR * (0.5 + 0.5 * b)
	return a * amp

func handle_input(delta: float) -> void:
	var w := Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	var s := Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")
	var a := Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left")
	var d := Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right")

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

	var target_steer := 0.0
	if a:
		target_steer = -MAX_STEER_DEG
	elif d:
		target_steer = MAX_STEER_DEG
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
