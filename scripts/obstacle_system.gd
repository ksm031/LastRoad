extends Node2D
class_name LastRoadObstacles

const _Road = preload("res://scripts/road_renderer.gd")

const CAMERA_DEPTH := 0.84
const ROAD_HW_MAX  := 650.0
const ROAD_BOTTOM_Y := 500.0
const HORIZON_Y_BASE := 300.0

# ── 스폰 튜닝 ────────────────────────────────────────────────
const SPACING_Z        := 22.0   # 큰 값일수록 덜 자주
const SPAWN_CHANCE     := 0.14   # 0~1
const VISIBLE_DZ_MIN   := -1.0
const VISIBLE_DZ_MAX   := 78.0

# ── 충돌 튜닝 ────────────────────────────────────────────────
const HIT_DZ           := 0.38   # 더 가까이 와야 충돌로 처리
const HIT_COOLDOWN_Z   := 4.0    # 같은 장애물이 재히트 되는 것 방지(지나갈 때까지)

var scroll_z: float = 0.0
var cam_x: float = 0.0
var hill_px: float = 0.0
var _curve_x: PackedFloat32Array = PackedFloat32Array()

var _textures: Array[Texture2D] = []
var _hit_until_z: Dictionary = {} # key(int) -> until_z(float)

func _ready() -> void:
	# 사용자가 추가한 돌 텍스처 로드
	for i in range(1, 10):
		var t := load("res://Asset/Image/Obstacle/rock_%02d.png" % i) as Texture2D
		if t:
			_textures.append(t)

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	queue_redraw()

func check_collision(vehicle: LastRoadVehicle) -> bool:
	if _textures.is_empty():
		return false
	_prune_hits()
	var hit := false

	var lane := clampi(int(round(vehicle.cam_x)), -1, 1)
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	for k in range(k0, k1 + 1):
		var o := _obstacle_at_k(k)
		if o.is_empty():
			continue
		if int(o["lane"]) != lane:
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
	# 지나간 장애물 히트 기록 제거
	var keys := _hit_until_z.keys()
	for k in keys:
		if float(_hit_until_z[k]) <= scroll_z:
			_hit_until_z.erase(k)

func _obstacle_at_k(k: int) -> Dictionary:
	# 결정적 생성: 같은 k는 항상 같은 결과
	var r := _rand01(k * 7919 + 11)
	if r > SPAWN_CHANCE:
		return {}
	var lane := int(floor(_rand01(k * 7919 + 97) * 3.0)) - 1  # -1,0,1
	var wz := float(k) * SPACING_Z + 12.0 + _rand01(k * 7919 + 203) * 6.0
	var tidx := int(floor(_rand01(k * 7919 + 409) * float(_textures.size())))
	tidx = clampi(tidx, 0, _textures.size() - 1)
	return {
		"k": k,
		"lane": lane,
		"wz": wz,
		"tidx": tidx,
	}

func _rand01(seed: int) -> float:
	var h := int((seed * 1103515245 + 12345) & 0x7fffffff)
	return float(h & 0xFFFF) / 65535.0

func _curve_at_depth(depth: float) -> float:
	var n := _curve_x.size()
	if n <= 1:
		return 0.0
	# depth 1(가까움) -> idx 0, depth 0(멀리) -> idx n-1
	var idx := clampi(int(round((1.0 - depth) * float(n - 1))), 0, n - 1)
	return _curve_x[idx]

func _draw() -> void:
	if _textures.is_empty():
		return

	var hy := HORIZON_Y_BASE + hill_px
	var entries: Array = []

	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))
	for k in range(k_min, k_max + 1):
		var o := _obstacle_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX:
			continue

		var depth := clampf(CAMERA_DEPTH / dz, 0.0, 1.0)
		if depth < 0.02:
			continue

		var road_hw := depth * ROAD_HW_MAX
		var cx_curve := _curve_at_depth(depth)
		var road_cx := 640.0 + cx_curve - cam_x * depth * 320.0
		var ground_y := hy + depth * (ROAD_BOTTOM_Y - hy)

		# 차선 위치(도로 폭 기반)
		var lane := int(o["lane"])
		var lane_off := float(lane) * road_hw * 0.42
		var x := road_cx + lane_off

		var tex := _textures[int(o["tidx"])]
		var h := depth * 120.0
		var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
		var y := ground_y - h

		# 원거리 페이드
		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)

		entries.append({
			"d": depth,
			"tex": tex,
			"rect": Rect2(x - w * 0.5, y, w, h),
			"fade": fade
		})

	entries.sort_custom(func(a, b): return a.d < b.d)
	for e in entries:
		draw_texture_rect(e.tex, e.rect, false, Color(1.0, 1.0, 1.0, e.fade))

