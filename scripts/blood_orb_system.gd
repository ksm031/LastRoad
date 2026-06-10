extends Node2D
class_name LastRoadBloodOrbs
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 스폰 (패턴 A: 소닉 링 식 그룹화 스폰) ───────────────
var SPACING_Z      : float = 32.0
var SPAWN_CHANCE   := 0.50
var seed_offset    := 0

const ORBS_PER_GROUP := 5
const INNER_SPACING  := 4.5

const VISIBLE_DZ_MIN   := 0.5
const VISIBLE_DZ_MAX   := 75.0
const WZ_BASE_OFFSET   := 15.0

const ORB_BASE_H       := 44.0
const ORB_FLOAT_HEIGHT := 130.0
const PUDDLE_BASE_H    := 28.0
const FLOAT_AMP_DEPTH  := 14.0
const FLOAT_SPEED      := 2.8
const COLLECT_DZ       := 1.5
const BO_PER_ORB       := 1

const ORB_COLOR  := Color(1.0, 0.72, 0.65, 1.0)
const PUDDLE_COLOR := Color(0.85, 0.35, 0.30, 0.95)

var scroll_z : float = 0.0
var cam_x    : float = 0.0
var hill_px  : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var _headlight_range : float = 1.0
var _anim_time : float = 0.0

var _tex_orb    : Texture2D
var _tex_puddle : Texture2D
var billboard_mgr: BillboardManager
var _light_pool: LightMaterialPool
const POOL_SIZE := 80

var _collected : Dictionary = {}  # int k -> true
var run_total_bo : int = 0

const _AMBIENT_NORMAL := Color(0.55, 0.22, 0.20, 1.0)
const _AMBIENT_DARK   := Color(0.42, 0.14, 0.12, 1.0)

signal orb_collected(amount: int)

func _ready() -> void:
	pass

# 적 처치 등 길 위 오브 수집 외 경로로 BO를 직접 획득 (Doc 31 §1)
func award_bo(amount: int) -> void:
	if amount <= 0:
		return
	run_total_bo += amount
	orb_collected.emit(amount)

func load_assets() -> void:
	if _tex_orb != null:
		return
	_tex_orb = load("res://Asset/Image/object/blood_orb.png") as Texture2D
	_tex_puddle = load("res://Asset/Image/object/blood_puddle.png") as Texture2D
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

func reset_run() -> void:
	_collected.clear()
	run_total_bo = 0

func clear_stage() -> void:
	_collected.clear()

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float, p_headlight_range: float = 1.0, delta: float = 0.016) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_headlight_range = p_headlight_range
	_anim_time += delta
	_update_billboards()

func _orb_at_k(k: int) -> Dictionary:
	var g := k / ORBS_PER_GROUP
	var sub_idx := k % ORBS_PER_GROUP
	
	if BillboardManager.get_rand01(g * 27183 + 17, seed_offset) > SPAWN_CHANCE:
		return {}
	var lane_r := BillboardManager.get_rand01(g * 27183 + 61, seed_offset)
	var lane := 0
	if lane_r < 0.28:
		lane = -1
	elif lane_r > 0.72:
		lane = 1
	var jitter := (BillboardManager.get_rand01(g * 27183 + 103, seed_offset) - 0.5) * 0.18
	var wz := float(g) * (SPACING_Z * 3.125) + float(sub_idx) * INNER_SPACING + WZ_BASE_OFFSET
	return { "k": k, "lane": lane, "jitter": jitter, "wz": wz }

func _update_billboards() -> void:
	if _tex_orb == null or _tex_puddle == null or billboard_mgr == null:
		return

	var virtual_spacing := (SPACING_Z * 3.125) / float(ORBS_PER_GROUP)
	var kr := BillboardManager.visible_k_range(scroll_z, virtual_spacing, VISIBLE_DZ_MIN, VISIBLE_DZ_MAX, WZ_BASE_OFFSET, 0.0)
	if _light_pool:
		_light_pool.reset()

	for k in range(kr.x, kr.y + 1):
		if _collected.has(k):
			continue
		var o := _orb_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX:
			continue

		var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth
		var lane := int(o["lane"])
		var lane_jitter := float(o.get("jitter", 0.0))
		var lane_off := (float(lane) + lane_jitter) * float(proj.road_hw) * 0.40
		var x := float(proj.road_cx) + lane_off
		var ground_y := float(proj.ground_y)

		var bob := sin(_anim_time * FLOAT_SPEED + float(k) * 1.37) * depth * FLOAT_AMP_DEPTH

		var float_offset := depth * ORB_FLOAT_HEIGHT
		var orb_h := depth * ORB_BASE_H
		var orb_w := orb_h * float(_tex_orb.get_width()) / maxf(float(_tex_orb.get_height()), 1.0)
		var orb_bottom := ground_y - float_offset - bob
		var orb_rect := Rect2(x - orb_w * 0.5, orb_bottom - orb_h, orb_w, orb_h)

		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var light_h: float = proj.light_h

		# 핏자국(Puddle) 계산 및 빌보드 등록 복구! (그림자가 필요 없으므로 is_shadowless: true 전달)
		var puddle_h := depth * PUDDLE_BASE_H
		var puddle_w := puddle_h * float(_tex_puddle.get_width()) / maxf(float(_tex_puddle.get_height()), 1.0)
		puddle_w = maxf(puddle_w, orb_w * 1.15)
		var puddle_rect := Rect2(x - puddle_w * 0.5, ground_y - puddle_h, puddle_w, puddle_h)
		
		var mat_puddle := _light_pool.get_material(light_h) if _light_pool else null
		billboard_mgr.add_entry(depth - 0.00003, puddle_rect, _tex_puddle, fade, mat_puddle, PUDDLE_COLOR, false, light_h, ground_y, false, 0.0, 0.0, 0.0, true)

		var mat_orb := _light_pool.get_material(light_h) if _light_pool else null
		# 마지막 인자로 is_shadowless: true 를 안전하게 투과!
		billboard_mgr.add_entry(depth, orb_rect, _tex_orb, fade, mat_orb, ORB_COLOR, false, light_h, ground_y, false, 0.0, 0.0, 0.0, true)

func check_collection(vehicle: LastRoadVehicle) -> int:
	if _tex_orb == null:
		return 0
	var gained := 0
	var group_spacing := SPACING_Z * 3.125
	var current_g := int(floor(scroll_z / group_spacing))
	var k0 := (current_g - 1) * ORBS_PER_GROUP
	var k1 := (current_g + 2) * ORBS_PER_GROUP
	var threshold := vehicle.COLLISION_WIDTH * 0.55 + 0.35

	for k in range(k0, k1 + 1):
		if _collected.has(k):
			continue
		var o := _orb_at_k(k)
		if o.is_empty():
			continue
		var lane := float(o["lane"]) + float(o.get("jitter", 0.0))
		if absf(lane - vehicle.cam_x) > threshold:
			continue
		var dz := float(o["wz"]) - scroll_z
		if dz < 0.05 or dz > COLLECT_DZ:
			continue
		_collected[k] = true
		gained += BO_PER_ORB

	if gained > 0:
		run_total_bo += gained
		orb_collected.emit(gained)
	return gained
