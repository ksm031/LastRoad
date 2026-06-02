extends Node2D
class_name LastRoadScavenging
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 상수 (BillboardManager 투영 모델 사용) ─────

# ── 스폰 튜닝 (route_type에 따라 game_world에서 조정) ─────────
var SPACING_Z        := 100.0   # 거리가 꽤 멀게 (가끔 나옴)
var SPAWN_CHANCE     := 0.40    # 40% 확률로 스폰
var seed_offset      := 0      # 스테이지마다 다른 배치를 위한 시드 오프셋
const VISIBLE_DZ_MIN   := 0.001
const VISIBLE_DZ_MAX   := 78.0

var scroll_z: float = 0.0
var cam_x: float = 0.0
var hill_px: float = 0.0
var _curve_x: PackedFloat32Array = PackedFloat32Array()
var _headlight_range: float = 1.0

var next_car_dist_mult: float = 1.0

var _tex_car: Texture2D
var billboard_mgr: BillboardManager
var _light_pool: LightMaterialPool
const POOL_SIZE := 50

func _ready() -> void:
	pass

func load_assets() -> void:
	if _tex_car != null: return
	_tex_car = BillboardManager.load_with_normal("res://Asset/Image/object/Scrapped_car.png")
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

const _AMBIENT_NORMAL := Color(0.42, 0.40, 0.38, 1.0)
const _AMBIENT_DARK   := Color(0.08, 0.07, 0.06, 1.0) # 다시 어둡게 복구

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

func _update_billboards() -> void:
	if _tex_car == null or billboard_mgr == null:
		return

	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))
	if _light_pool:
		_light_pool.reset()
	for k in range(k_min, k_max + 1):
		var o := _car_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz <= 0.0 or dz > VISIBLE_DZ_MAX:
			continue

		var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth

		var side := int(o["side"])
		var edge_mult := 1.20
		var fixed_px := float(side) * 25.0
		var x: float = float(proj.road_cx) + float(side) * float(proj.road_hw) * edge_mult + fixed_px

		var h: float = depth * 360.0 
		var w: float = h * float(_tex_car.get_width()) / maxf(float(_tex_car.get_height()), 1.0)
		var fade: float = 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)

		# 바닥에 완전히 밀착된 느낌을 주기 위해 더 많이 가라앉힘 (22% 높이만큼)
		var y_sink := h * 0.22
		var rect := Rect2(x - w * 0.5, float(proj.ground_y) - h + y_sink, w, h)
		var flip_h := (side == 1)
		
		var mat := _light_pool.get_material(float(proj.light_h)) if _light_pool else null
		billboard_mgr.add_entry(depth, rect, _tex_car, fade, mat, Color.WHITE, flip_h, float(proj.light_h), float(proj.ground_y))



func _car_at_k(k: int) -> Dictionary:
	# 스테이지 내 최소 2대 스폰 보장 (k=2, k=4 강제 스폰)
	var is_forced := (k == 2 or k == 4)
	
	var r := BillboardManager.get_rand01(k * 31415 + 92, seed_offset)
	if not is_forced and r > SPAWN_CHANCE:
		return {}
	
	# 스폰 체크(seed 92)와 완전히 다른 시드로 side 결정 → 왼/오른 균등 분배
	var side_r := BillboardManager.get_rand01(k * 57833 + 441, seed_offset)
	var side := -1 if side_r < 0.5 else 1
	var wz := float(k) * SPACING_Z + 20.0 + BillboardManager.get_rand01(k * 31415 + 88, seed_offset) * 20.0
	
	# 카니발 입장권 및 자석고양이 시너지로 다음 폐차 등장 거리 단축
	var current_k := int(floor(scroll_z / SPACING_Z))
	if k > current_k and next_car_dist_mult != 1.0:
		var dist := wz - scroll_z
		wz = scroll_z + dist * next_car_dist_mult

	return {
		"k": k,
		"side": side,
		"wz": wz
	}

## 아이템 획득 가능 여부 체크
func is_in_clear_zone(wz: float, side: int) -> bool:
	# 근처 k값 검사 (폐차 스폰 간격 SPACING_Z 고려)
	var k0 := int(floor((wz - 10.0) / SPACING_Z))
	var k1 := int(ceil((wz + 10.0) / SPACING_Z))
	for k in range(k0, k1 + 1):
		var o := _car_at_k(k)
		if not o.is_empty():
			var car_z := float(o["wz"])
			var car_side := int(o["side"])
			# 폐차와 같은 쪽이고, 거리가 6.0 미만일 때만 나무를 지움 (기존보다 좁게 조정)
			if car_side == side and absf(wz - car_z) < 6.0: 
				return true
	return false

## 가장 가까운 폐차 정보 반환 (dz 기준). 없으면 빈 딕셔너리.
func get_nearest_car() -> Dictionary:
	var best := {}
	var min_dz := 9999.0
	
	var k_min := int(floor((scroll_z) / SPACING_Z))
	var k_max := k_min + 5
	for k in range(k_min, k_max + 1):
		var o := _car_at_k(k)
		if not o.is_empty():
			var dz := float(o["wz"]) - scroll_z
			if dz > 0.0 and dz < min_dz:
				min_dz = dz
				best = o
	if not best.is_empty():
		best["dz"] = min_dz
		# 플레이어가 폐차 근처로 오면 할인 배율 리셋
		if min_dz < 10.0:
			next_car_dist_mult = 1.0
	return best

func get_car_screen_rect(o: Dictionary) -> Rect2:
	if _tex_car == null or o.is_empty():
		return Rect2()
		
	var wz := float(o["wz"])
	var dz := wz - scroll_z
	if dz <= 0.0:
		return Rect2()
		
	var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _headlight_range)
	var depth: float = proj.depth
	
	var side := int(o["side"])
	var edge_mult := 1.20
	var fixed_px := float(side) * 25.0
	var x: float = float(proj.road_cx) + float(side) * float(proj.road_hw) * edge_mult + fixed_px
	
	var h: float = depth * 360.0 
	var w: float = h * float(_tex_car.get_width()) / maxf(float(_tex_car.get_height()), 1.0)
	return Rect2(x - w * 0.5, float(proj.ground_y) - h, w, h)
