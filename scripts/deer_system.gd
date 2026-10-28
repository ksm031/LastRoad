extends Node2D
class_name LastRoadDeer
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ══════════════════════════════════════════════════════════════
#  사슴머리 (Doc 06 §보스형 위협, Doc 19 §사슴머리)
#  도로 전 차선을 점유. 회피 불가. 차가 '통과'하며 속도만이 피해를 줄인다.
#  스테이지 6 고정 2~3회. BO 없음 — 통과 자체가 의식적 순간.
#
#  통과 판정은 game_world가 signal로 받아 정신력·부품·채도·주변 적 활성화를 처리.
#  스프라이트 임시: 와쳐 idle을 거대·암색으로. 뿔은 코드로 그린다(가장 늦게 드러남).
# ══════════════════════════════════════════════════════════════

signal deer_passed(speed_kmh: float)

var stage: int = 1
var seed_offset: int = 0
var stage_len: float = 600.0
const MIN_STAGE := 6
const BASE_H := 1500.0            # depth=1 기준. 화면을 덮는 크기
const VISIBLE_DZ_MAX := 95.0      # 멀리서부터 실루엣
const PASS_DZ := 0.35
const ANTLER_REVEAL_DZ := 40.0    # 이 거리 안에서 뿔이 보이기 시작
const HOLD_AFTER_PASS := 5.0      # 통과 후 스폰 정지 윈도우 (Doc 30 §4)

var _positions: Array = []        # 이번 스테이지의 wz 목록
var _passed: Dictionary = {}      # wz(int) -> true
var _texture: Texture2D
var _light_pool: LightMaterialPool
var billboard_mgr: BillboardManager
var scroll_z: float = 0.0
var cam_x: float = 0.0
var hill_px: float = 0.0
var _curve_x: PackedFloat32Array = PackedFloat32Array()
var _headlight_range: float = 1.0
var _anim_time: float = 0.0
var recent_pass_timer: float = 0.0   # 통과 직후 잔여 (game_world가 읽어 스폰/창 보류)
const TINT := Color(0.12, 0.10, 0.12, 1.0)

func load_assets() -> void:
	if _texture != null: return
	_texture = BillboardManager.load_with_normal("res://Asset/Image/Character/watcher_idle_01.png")
	_light_pool = LightMaterialPool.new(4, Color(0.30, 0.26, 0.30, 1.0), Color(0.22, 0.20, 0.24, 1.0))

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

## 스테이지 진입 시: 6스테이지면 2~3곳 결정적 배치 (0.30·0.62·0.86 지점 ±5%)
func reset_stage(p_stage: int, p_stage_len: float, p_seed: int) -> void:
	stage = p_stage
	stage_len = p_stage_len
	seed_offset = p_seed
	_positions.clear()
	_passed.clear()
	recent_pass_timer = 0.0
	if stage < MIN_STAGE:
		return
	var count := 2 + (1 if BillboardManager.get_rand01(4242, seed_offset) < 0.5 else 0)
	var fr := [0.30, 0.62, 0.86]
	for i in range(count):
		var jitter := (BillboardManager.get_rand01(4300 + i, seed_offset) - 0.5) * 0.10
		var wz := clampf((float(fr[i]) + jitter) * stage_len, 100.0, stage_len - 70.0)
		# 숨 비트 구역을 피한다
		if not PressureDirector.can_spawn_at(wz):
			wz = clampf(wz + 60.0, 100.0, stage_len - 70.0)
		_positions.append(wz)

func is_near(ahead_units: float = 12.0) -> bool:
	for wz in _positions:
		var dz := float(wz) - scroll_z
		if dz > -1.0 and dz < ahead_units:
			return true
	return false

func update_state(p_scroll_z: float, p_cam_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float, p_headlight_range: float, speed_kmh: float, delta: float) -> void:
	scroll_z = p_scroll_z
	cam_x = p_cam_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_headlight_range = p_headlight_range
	_anim_time += delta
	if recent_pass_timer > 0.0:
		recent_pass_timer -= delta
	# 통과 판정
	for wz in _positions:
		var key := int(wz)
		if _passed.has(key):
			continue
		var dz := float(wz) - scroll_z
		if dz <= PASS_DZ:
			_passed[key] = true
			recent_pass_timer = HOLD_AFTER_PASS
			deer_passed.emit(speed_kmh)

func _process(_delta: float) -> void:
	_update_billboards()

func _update_billboards() -> void:
	if _texture == null or billboard_mgr == null or _positions.is_empty():
		return
	if _light_pool:
		_light_pool.reset()
	for wz in _positions:
		var dz := float(wz) - scroll_z
		if dz < 0.3 or dz > VISIBLE_DZ_MAX:
			continue
		var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth
		var h := depth * BASE_H
		var w: float = h * float(_texture.get_width()) / maxf(float(_texture.get_height()), 1.0) * 1.6  # 도로 전 차선 점유 느낌
		var x: float = float(proj.road_cx)
		var fade: float = 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.6) / (VISIBLE_DZ_MAX * 0.4), 0.0, 1.0)
		# 미세하게 숨 쉬듯 흔들림
		var sway := sin(_anim_time * 0.8) * depth * 6.0
		var mat := _light_pool.get_material(float(proj.light_h)) if _light_pool else null
		billboard_mgr.add_entry(depth, Rect2(x - w * 0.5 + sway, float(proj.ground_y) - h * 0.82, w, h), _texture, fade, mat, TINT, false, float(proj.light_h), float(proj.ground_y))
	queue_redraw()

## 뿔: 가까워질수록 드러난다 (가장 마지막에 보이는 것)
func _draw() -> void:
	if _positions.is_empty():
		return
	for wz in _positions:
		var dz := float(wz) - scroll_z
		if dz < 0.3 or dz > ANTLER_REVEAL_DZ:
			continue
		var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth
		var reveal := 1.0 - clampf(dz / ANTLER_REVEAL_DZ, 0.0, 1.0)
		var h := depth * BASE_H
		var top := Vector2(float(proj.road_cx), float(proj.ground_y) - h * 0.80)
		var col := Color(0.03, 0.02, 0.03, reveal)
		var L := h * 0.42 * reveal
		var thick := maxf(depth * 10.0, 1.5)
		for s in [-1.0, 1.0]:
			var base := top + Vector2(s * h * 0.06, 0.0)
			var tip := base + Vector2(s * L * 0.55, -L)
			draw_line(base, tip, col, thick)
			# 가지 2개
			var m1 := base.lerp(tip, 0.45)
			draw_line(m1, m1 + Vector2(s * L * 0.35, -L * 0.25), col, thick * 0.7)
			var m2 := base.lerp(tip, 0.75)
			draw_line(m2, m2 + Vector2(-s * L * 0.18, -L * 0.28), col, thick * 0.6)
