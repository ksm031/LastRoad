extends Node2D
class_name LastRoadScavenging

const CAMERA_DEPTH := 0.84
const ROAD_HW_MAX  := 650.0
const ROAD_BOTTOM_Y := 500.0
const HORIZON_Y_BASE := 300.0

# ── 스폰 튜닝 ────────────────────────────────────────────────
const SPACING_Z        := 100.0   # 거리가 꽤 멀게 (가끔 나옴)
const SPAWN_CHANCE     := 0.40    # 40% 확률로 스폰
const VISIBLE_DZ_MIN   := 0.05
const VISIBLE_DZ_MAX   := 78.0

var scroll_z: float = 0.0
var cam_x: float = 0.0
var hill_px: float = 0.0
var _curve_x: PackedFloat32Array = PackedFloat32Array()

var _tex_car: Texture2D

func _ready() -> void:
	_tex_car = load("res://Asset/Image/object/Scrapped_car.png") as Texture2D

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	queue_redraw()

func _rand01(seed: int) -> float:
	var h := int((seed * 1103515245 + 12345) & 0x7fffffff)
	return float(h & 0xFFFF) / 65535.0

# 특정 k 위치에 스폰되는 폐차 정보
func _car_at_k(k: int) -> Dictionary:
	var r := _rand01(k * 31415 + 92)
	if r > SPAWN_CHANCE:
		return {}
	
	# 스폰 체크(seed 92)와 완전히 다른 시드로 side 결정 → 왼/오른 균등 분배
	var side_r := _rand01(k * 57833 + 441)
	var side := -1 if side_r < 0.5 else 1
	var wz := float(k) * SPACING_Z + 20.0 + _rand01(k * 31415 + 88) * 20.0
	return {
		"k": k,
		"side": side,
		"wz": wz
	}

# 나무가 스폰되지 않도록 피해야 할 구간 검사 (tree_renderer에서 호출)
func is_in_clear_zone(wz: float, tree_side: int) -> bool:
	# 근처 k값 검사
	var k0 := int(floor((wz - 15.0) / SPACING_Z))
	var k1 := int(ceil((wz + 15.0) / SPACING_Z))
	for k in range(k0, k1 + 1):
		var car = _car_at_k(k)
		if not car.is_empty():
			var car_z = float(car["wz"])
			var car_side = int(car["side"])
			# 차 주변의 나무가 차를 뚫고 나오는 현상을 막기 위해 클리어 존 확장 (반경 12.0)
			if car_side == tree_side and absf(wz - car_z) < 12.0: 
				return true
	return false

func _curve_at_depth(depth: float) -> float:
	var n := _curve_x.size()
	if n <= 1:
		return 0.0
	var idx := clampi(int(round((1.0 - depth) * float(n - 1))), 0, n - 1)
	return _curve_x[idx]

func get_draw_entries() -> Array:
	if _tex_car == null:
		return []

	var hy := HORIZON_Y_BASE + hill_px
	var entries: Array = []

	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))
	for k in range(k_min, k_max + 1):
		var o := _car_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX:
			continue
		if dz <= 0.0:
			continue

		# 클램프 없이 실제 깊이 적용
		var depth: float = CAMERA_DEPTH / dz
		if depth < 0.02:
			continue

		var road_hw := depth * ROAD_HW_MAX
		var cx_curve := _curve_at_depth(depth)
		var road_cx := 640.0 + cx_curve - cam_x * depth * 320.0
		var ground_y := hy + depth * (ROAD_BOTTOM_Y - hy)

		# 갓길 배치 (도로 바깥쪽)
		var side := int(o["side"])
		# 멀리 있을수록(depth 낮을수록) road_hw가 작아지므로, 고정 픽셀 오프셋 추가
		# edge_mult: 도로 절반 폭의 배수, fixed_px: 화면 픽셀 단위 최소 여백
		var edge_mult := 1.55
		var fixed_px := float(side) * 55.0   # depth와 무관한 고정 이격
		var x := road_cx + float(side) * road_hw * edge_mult + fixed_px

		# 차 높이를 기존(150) 대비 두 배(300)로 키움
		var h := depth * 300.0 
		var w := h * float(_tex_car.get_width()) / maxf(float(_tex_car.get_height()), 1.0)
		var y := ground_y - h

		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)

		entries.append({
			"is_car": true,
			"d": depth,
			"rect": Rect2(x - w * 0.5, y, w, h),
			"fade": fade,
			"side": side,
			"tex": _tex_car
		})

	return entries

## 가장 가까운 폐차 정보 반환 (dz 기준). 없으면 빈 딕셔너리.
func get_nearest_car() -> Dictionary:
	var best := {}
	var best_dz := 999.0
	var k_min := int(floor((scroll_z + 0.1) / SPACING_Z))
	var k_max := int(ceil((scroll_z + 20.0) / SPACING_Z))
	for k in range(k_min, k_max + 1):
		var o := _car_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := absf(wz - scroll_z)
		if dz < best_dz:
			best_dz = dz
			best = o
			best["dz"] = dz
	return best

func get_car_screen_rect(o: Dictionary) -> Rect2:
	if _tex_car == null or o.is_empty():
		return Rect2()
		
	var wz := float(o["wz"])
	var dz := wz - scroll_z
	if dz <= 0.0:
		return Rect2()
		
	var depth: float = CAMERA_DEPTH / dz
	var hy := HORIZON_Y_BASE + hill_px
	var road_hw := depth * ROAD_HW_MAX
	var cx_curve := _curve_at_depth(depth)
	var road_cx := 640.0 + cx_curve - cam_x * depth * 320.0
	var ground_y := hy + depth * (ROAD_BOTTOM_Y - hy)
	
	var side := int(o["side"])
	var edge_mult := 1.55
	var fixed_px := float(side) * 55.0
	var x := road_cx + float(side) * road_hw * edge_mult + fixed_px
	
	var h := depth * 300.0 
	var w := h * float(_tex_car.get_width()) / maxf(float(_tex_car.get_height()), 1.0)
	var y := ground_y - h
	return Rect2(x - w * 0.5, y, w, h)
