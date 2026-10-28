extends Node2D
class_name LastRoadSpear
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ══════════════════════════════════════════════════════════════
#  창 던지기 (Doc 08 §창 던지기)
#  괴물이 경계 단계 이내로 접근하면 룸미러에서 한쪽 팔을 들고(윈드업)
#  창을 던진다. 손이 보이는 쪽의 반대로 차선을 옮겨야 피한다.
#
#  시퀀스: warn(0.8) → windup(스테이지별) → throw(0.3) → approach(0.5)
#          → [명중 판정] → flight(1.0, 전방으로 사라짐) → idle
#  룸미러 연출은 rearview_renderer가 get_mirror_state()를 읽어 그린다.
#  이 노드 자체는 명중 판정 직후의 전방 비행만 _draw()로 그린다.
# ══════════════════════════════════════════════════════════════

signal spear_hit(side: int)      # side: -1 좌 / +1 우 (창이 지나간 도로 측)
signal spear_missed(side: int)
signal spear_warning(side: int)  # 경고 시작 (사운드·자막 훅)

# ── 스테이지별 패턴 (Doc 08 표): [윈드업 초, 발동 주기 초, 2연발 확률, 페이크 확률] ──
const STAGE_TABLE := {
	3: [1.5, 40.0, 0.0, 0.0],
	4: [1.2, 30.0, 0.0, 0.0],
	5: [1.0, 25.0, 0.3, 0.0],
	6: [0.8, 20.0, 0.5, 0.3],
}
const MIN_STAGE := 3

const WARN_DUR     := 0.8
const THROW_DUR    := 0.3
const APPROACH_DUR := 0.5
const FLIGHT_DUR   := 1.0
const DOUBLE_GAP   := 0.8    # 2연발 간격

# ── 거리 단계 (괴물 거리 / 상한 비율) ──
# 안전(>0.60) 발동 없음 / 경계 ×1 / 위험(<0.35) ×1.5 / 임박(<0.15) ×2
const DIST_SAFE    := 0.60
const DIST_DANGER  := 0.35
const DIST_IMMINENT := 0.15

# ── 명중 판정: 창은 side 쪽 절반 도로를 훑는다. 반대편 끝으로 피해야 안전 ──
const HIT_CAM_X_MARGIN := -0.15   # cam_x * side > 이 값이면 명중

# ── 전방 비행 시각 ──
const FLIGHT_DZ_START := 0.6
const FLIGHT_DZ_END   := 60.0
const SPEAR_LEN_Z     := 3.0      # 세계 단위 길이 (사람 키 정도 → 과장)
const SPEAR_HEIGHT_PX := 40.0     # depth=1 기준 노면 위 높이

# ── 상태 ──
var phase      : String = "idle"  # idle / warn / windup / throw / approach / flight
var side       : int = 1          # 괴물이 든 팔 = 창이 오는 도로 측
var _shown_side: int = 1          # 룸미러에 보이는 팔 (페이크 시 중간에 바뀜)
var _fake      : bool = false
var _fake_switched : bool = false
var _phase_t   : float = 0.0
var _windup_dur: float = 1.0
var _cooldown  : float = 25.0
var _double_pending : bool = false
var _double_timer   : float = 0.0
var _stage     : int = 1
var _rng       := RandomNumberGenerator.new()

# 투영 입력 (전방 비행 렌더용)
var _cam_x    : float = 0.0
var _curve_x  : PackedFloat32Array = PackedFloat32Array()
var _hill_px  : float = 0.0

func _ready() -> void:
	_rng.randomize()
	z_index = 1   # 도로·빌보드 위, 비/HUD 아래

func reset_stage(stage: int) -> void:
	_stage = stage
	phase = "idle"
	_phase_t = 0.0
	_double_pending = false
	if STAGE_TABLE.has(stage):
		# 첫 발은 주기의 절반 뒤 (스테이지 진입 직후 날아오지 않게)
		_cooldown = float(STAGE_TABLE[stage][1]) * 0.5
	queue_redraw()

func is_active() -> bool:
	return phase != "idle"

## 룸미러 연출용 상태. rearview_renderer가 매 프레임 읽는다.
##  arm_t: 팔이 올라간 정도 0~1 / streak_t: 날아오는 창의 접근 0~1
func get_mirror_state() -> Dictionary:
	var arm_t := 0.0
	var streak_t := 0.0
	match phase:
		"warn":     arm_t = 0.4 * (_phase_t / WARN_DUR)
		"windup":   arm_t = 0.4 + 0.6 * (_phase_t / _windup_dur)
		"throw":    arm_t = 1.0 - (_phase_t / THROW_DUR)
		"approach": streak_t = _phase_t / APPROACH_DUR
	return {
		"phase": phase,
		"side": _shown_side,
		"arm_t": clampf(arm_t, 0.0, 1.0),
		"streak_t": clampf(streak_t, 0.0, 1.0),
		"alert": phase == "warn" or phase == "windup",
	}

## 매 프레임. blocked = 점퍼 탑승·인벤토리 열림·라디오 줌 등 (Doc 30 §4 상호 잠금)
func update_state(delta: float, stage: int, monster_dist: float, monster_max: float,
		vehicle: LastRoadVehicle, p_curve_x: PackedFloat32Array, p_hill_px: float, blocked: bool) -> void:
	_stage = stage
	_cam_x = vehicle.cam_x
	_curve_x = p_curve_x
	_hill_px = p_hill_px

	if phase == "idle":
		_update_cooldown(delta, monster_dist, monster_max, blocked)
		return

	_phase_t += delta
	match phase:
		"warn":
			if _phase_t >= WARN_DUR:
				_enter("windup")
		"windup":
			# 페이크: 윈드업 60% 지점에서 반대 손으로 바꿈 (Doc 08 §페이크 패턴)
			if _fake and not _fake_switched and _phase_t >= _windup_dur * 0.6:
				_fake_switched = true
				_shown_side = side
			if _phase_t >= _windup_dur:
				_enter("throw")
		"throw":
			if _phase_t >= THROW_DUR:
				_enter("approach")
		"approach":
			if _phase_t >= APPROACH_DUR:
				# ── 명중 판정: 차가 창이 오는 쪽 절반에 있으면 명중 ──
				if vehicle.cam_x * float(side) > HIT_CAM_X_MARGIN:
					spear_hit.emit(side)
				else:
					spear_missed.emit(side)
				_enter("flight")
		"flight":
			queue_redraw()
			if _phase_t >= FLIGHT_DUR:
				phase = "idle"
				queue_redraw()
				# 2연발 예약 (Doc 08: 스테이지 5~6)
				if _double_pending:
					_double_pending = false
					_double_timer = DOUBLE_GAP

func _update_cooldown(delta: float, monster_dist: float, monster_max: float, blocked: bool) -> void:
	if not STAGE_TABLE.has(_stage):
		return
	if blocked:
		return
	# 2연발 대기 중이면 거리 무관하게 짧은 타이머로 발사
	if _double_timer > 0.0:
		_double_timer -= delta
		if _double_timer <= 0.0:
			_start_throw(false)
		return

	var ratio := monster_dist / maxf(monster_max, 1.0)
	if ratio > DIST_SAFE:
		return   # 안전 단계: 사정거리 밖. 쿨다운도 흐르지 않음
	var rate := 1.0
	if ratio < DIST_IMMINENT:
		rate = 2.0
	elif ratio < DIST_DANGER:
		rate = 1.5
	_cooldown -= delta * rate
	if _cooldown <= 0.0:
		_start_throw(true)

func _start_throw(allow_double: bool) -> void:
	var row: Array = STAGE_TABLE[_stage]
	_windup_dur = float(row[0])
	_cooldown   = float(row[1]) * _rng.randf_range(0.85, 1.15)
	side = 1 if _rng.randf() < 0.5 else -1
	_fake = _rng.randf() < float(row[3])
	_fake_switched = false
	# 페이크면 처음엔 반대 손을 보여준다
	_shown_side = -side if _fake else side
	_double_pending = allow_double and _rng.randf() < float(row[2])
	_enter("warn")
	spear_warning.emit(_shown_side)

func _enter(p: String) -> void:
	phase = p
	_phase_t = 0.0

# ── 전방 비행 렌더: 차 옆을 지나 지평선으로 사라지는 검은 창 ──
func _draw() -> void:
	if phase != "flight":
		return
	var t := clampf(_phase_t / FLIGHT_DUR, 0.0, 1.0)
	# ease-out: 가까이서 빠르고 멀어질수록 느려 보임
	var e := 1.0 - pow(1.0 - t, 2.2)
	var dz_tail := lerpf(FLIGHT_DZ_START, FLIGHT_DZ_END, e)
	var dz_tip  := dz_tail + SPEAR_LEN_Z * (1.0 + e * 2.0)   # 멀어질수록 모션 블러처럼 길어짐

	var p0 := _project(dz_tail)
	var p1 := _project(dz_tip)
	var d0 := float(p0["depth"])
	var w0 := maxf(d0 * 14.0, 1.5)
	var w1 := maxf(float(p1["depth"]) * 6.0, 1.0)

	var a: Vector2 = p0["pos"]
	var b: Vector2 = p1["pos"]
	var dir := (b - a)
	if dir.length() < 0.5:
		return
	var n := dir.normalized().orthogonal()
	var alpha := 1.0 - smoothstep(0.75, 1.0, t)
	# 무채색화와 무관하게 항상 검정 (Doc 08 §시각 디자인)
	var col := Color(0.02, 0.02, 0.03, alpha)
	var pts := PackedVector2Array([a + n * w0, a - n * w0, b - n * w1, b + n * w1])
	draw_polygon(pts, PackedColorArray([col, col, col, col]))
	# 잔상: 뒤쪽으로 흐릿한 꼬리
	var tail_end := a - dir.normalized() * (40.0 * d0)
	var tcol := Color(0.02, 0.02, 0.03, alpha * 0.35)
	draw_line(a, tail_end, tcol, w0 * 1.2)

func _project(dz: float) -> Dictionary:
	var proj := BillboardManager.calculate_projection(dz, _cam_x, _curve_x, _hill_px, 1.0)
	var depth: float = proj.depth
	var x: float = float(proj.road_cx) + float(side) * float(proj.road_hw) * 0.62
	var y: float = float(proj.ground_y) - depth * SPEAR_HEIGHT_PX
	return { "pos": Vector2(x, y), "depth": depth }
