extends Node2D
class_name LastRoadObstacles
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 스폰 튜닝 (route_type에 따라 game_world에서 조정) ─────────
var SPACING_Z        := 18.0    # 실제값은 spawn_config.gd에서 주입
var SPAWN_CHANCE     := 0.25
var seed_offset      := 0     # 스테이지마다 다른 배치를 위한 시드 오프셋
const VISIBLE_DZ_MIN   := 0.35
const VISIBLE_DZ_MAX   := 90.0
const WZ_BASE_OFFSET   := 10.0   # _obstacle_at_k: k*SPACING_Z + 10 + jitter
const WZ_MAX_JITTER    := 8.0

# ── 충돌 튜닝 ────────────────────────────────────────────────
const HIT_DZ           := 0.38
const HIT_COOLDOWN_Z   := 4.0

var scroll_z: float = 0.0
var cam_x: float = 0.0
var hill_px: float = 0.0
var _curve_x: PackedFloat32Array = PackedFloat32Array()
var _headlight_range: float = 1.0

var _textures: Array[Texture2D] = []
var billboard_mgr: BillboardManager
var _hit_until_z: Dictionary = {}
var _light_pool: LightMaterialPool
const POOL_SIZE := 60
var jiwon_info: Dictionary = {}

func _ready() -> void:
	pass

func load_assets() -> void:
	if not _textures.is_empty(): return
	
	for i in range(1, 10):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Obstacle/rock_%02d.png" % i)
		if t:
			_textures.append(t)
	
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

const _AMBIENT_NORMAL := Color(0.55, 0.52, 0.48, 1.0)
const _AMBIENT_DARK   := Color(0.28, 0.26, 0.24, 1.0) # 다크 루트에서도 바닥 장애물을 최소 식별 가능하도록 조절

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float, p_headlight_range: float = 1.0) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_headlight_range = p_headlight_range
	_update_billboards()

const OBJECT_WIDTH     := 0.9     # 오브젝트 자체 너비

func check_collision(vehicle: LastRoadVehicle) -> bool:
	if _textures.is_empty():
		return false
	_prune_hits()
	var hit := false
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	
	# 통합 충돌 범위 계산: (차폭 + 오브젝트폭) / 2
	var threshold := (vehicle.COLLISION_WIDTH + OBJECT_WIDTH) * 0.5
	
	for k in range(k0, k1 + 1):
		var o := _obstacle_at_k(k)
		if o.is_empty():
			continue
		
		if abs(float(o["lane"]) - vehicle.cam_x) > threshold:
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < 0.0 or dz > HIT_DZ:
			continue
		if _is_hit_active(k):
			continue
		_hit_until_z[k] = wz + HIT_COOLDOWN_Z
		vehicle.apply_rock_hit()
		hit = true
		break
	return hit

func _is_hit_active(k: int) -> bool:
	return _hit_until_z.has(k) and float(_hit_until_z[k]) > scroll_z

func _prune_hits() -> void:
	var keys := _hit_until_z.keys()
	for k in keys:
		if float(_hit_until_z[k]) <= scroll_z:
			_hit_until_z.erase(k)

func _obstacle_at_k(k: int) -> Dictionary:
	if BillboardManager.get_rand01(k * 7919 + 11, seed_offset) > SPAWN_CHANCE:
		return {}
	var lane_r := BillboardManager.get_rand01(k * 12345 + 157, seed_offset)
	var lane := 0
	if lane_r < 0.33: lane = -1
	elif lane_r > 0.66: lane = 1
	var jitter := (BillboardManager.get_rand01(k * 9876 + 233, seed_offset) - 0.5) * 0.15
	var wz := float(k) * SPACING_Z + 10.0 + BillboardManager.get_rand01(k * 7919 + 203, seed_offset) * 8.0
	
	if jiwon_info.has("wz"):
		var j_wz: float = jiwon_info["wz"]
		var j_lane: int = jiwon_info["lane"]
		
		# 1. 안전 간격 유지 (지원 기준 앞뒤 40m 내에는 스폰 금지)
		if absf(wz - j_wz) < 40.0:
			return {}
			
		# 2. 제일 가까운 앞쪽 장애물(40m ~ 120m)이 같은 차선에 없도록 강제 변경
		if wz > j_wz and wz < j_wz + 120.0:
			if lane == j_lane:
				lane = j_lane + 1
				if lane > 1: lane = -1
				
	var tidx := clampi(int(floor(BillboardManager.get_rand01(k * 7919 + 409, seed_offset) * float(_textures.size()))), 0, _textures.size() - 1)
	return {
		"k": k, "lane": lane, "jitter": jitter, "wz": wz, "tidx": tidx,
	}

func _update_billboards() -> void:
	if _textures.is_empty() or billboard_mgr == null:
		return
	var kr := BillboardManager.visible_k_range(scroll_z, SPACING_Z, VISIBLE_DZ_MIN, VISIBLE_DZ_MAX, WZ_BASE_OFFSET, WZ_MAX_JITTER)
	if _light_pool:
		_light_pool.reset()
		
	for k in range(kr.x, kr.y + 1):
		var o := _obstacle_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX:
			continue
		var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth
		var lane := int(o["lane"])
		var jitter := float(o.get("jitter", 0.0))
		var lane_off: float = (float(lane) + jitter) * float(proj.road_hw) * 0.42
		var x: float = float(proj.road_cx) + lane_off
		var tex := _textures[int(o["tidx"])]
		var h: float = depth * 120.0
		var w: float = h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
		var y: float = float(proj.ground_y) - h
		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.8) / (VISIBLE_DZ_MAX * 0.2), 0.0, 1.0)
		var rect := Rect2(x - w * 0.5, y, w, h)
		
		var mat := _light_pool.get_material(float(proj.light_h)) if _light_pool else null
		billboard_mgr.add_entry(depth, rect, tex, fade, mat, Color.WHITE, false, float(proj.light_h), float(proj.ground_y))
