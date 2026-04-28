extends Node2D

const HORIZON_Y      := 300.0
const ROAD_BOTTOM_Y  := 500.0
const ROAD_HW_MAX    := 650.0
const CAMERA_DEPTH   := 0.84

const TREE_BASE_H    := 480.0
const DZ_MIN         := 0.05
const DZ_MAX         := 72.0
# 도로(차선) 쪽으로 당겨지는 산란을 상쇄 — depth 1 기준 픽셀, 바깥으로만 밀기
const TREE_MARGIN_FROM_ROAD := 28.0

# 모든 레이어: [edge_mult, spacing, x_scatter_px] — edge_mult는 road_hw 배수(도로 밖 거리)
const LAYER_CONFIGS := [
	[1.22, 3.0,  18],   # 도로 바로 옆 (이전 1.05 → 차선 침범 방지)
	[1.40, 4.0,  50],
	[1.68, 5.5, 115],
	[2.02, 2.5, 195],
	[2.34, 2.5, 255],
	[2.82, 3.0, 325],
	[3.48, 3.0, 425],
	[4.58, 3.5, 555],
]

var scroll_z : float = 0.0
var cam_x    : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var hill_px  : float = 0.0
var scavenging_sys: Node2D = null
var _textures : Array[Texture2D] = []

func _ready() -> void:
	for i in range(1, 8):
		var t := load("res://Asset/Image/trees/tree_%02d.png" % i) as Texture2D
		if t:
			_textures.append(t)

func update_state(sz: float, cx: float, p_curve_x: PackedFloat32Array = PackedFloat32Array(), p_hill_px: float = 0.0) -> void:
	scroll_z = sz
	cam_x    = cx
	_curve_x = p_curve_x
	hill_px  = p_hill_px
	queue_redraw()

func _tex_idx(k: int, side: int, layer: int) -> int:
	return absi(k * 2654435761 + side * 40503 + layer * 1234567) % _textures.size()

func _draw() -> void:
	if _textures.is_empty():
		return
	var hy := HORIZON_Y + hill_px

	var entries : Array = []

	for side in [-1, 1]:
		for li in range(LAYER_CONFIGS.size()):
			var edge_mult := float(LAYER_CONFIGS[li][0])
			var spacing   := float(LAYER_CONFIGS[li][1])
			var x_scatter := int(LAYER_CONFIGS[li][2])
			var z_offset  := float(li) * spacing * 0.37 + (0.0 if side == -1 else spacing * 0.5)

			var k_min := int(ceilf((scroll_z + DZ_MIN - z_offset) / spacing))
			var k_max := mini(int(floorf((scroll_z + DZ_MAX - z_offset) / spacing)), k_min + 65)

			for k in range(k_min, k_max + 1):
				var wz  := float(k) * spacing + z_offset
				var dz  := wz - scroll_z
				# dz가 0 이하면 이미 지나친 것 - 즉시 제거 (화면 경계 정지 방지)
				if dz <= 0.0 or dz < DZ_MIN:
					continue
					
				if scavenging_sys != null and scavenging_sys.is_in_clear_zone(wz, side):
					continue

				# 클램프 없이 실제 깊이 적용 (거리가 매우 가까워지면 depth 급증)
				var depth: float = CAMERA_DEPTH / dz
				if depth < 0.02:
					continue

				var ground_y := hy + depth * (ROAD_BOTTOM_Y - hy)
				var road_hw := depth * ROAD_HW_MAX
				var cx_curve := 0.0
				var ns := _curve_x.size()
				if ns > 1:
					var idx := clampi(int(round((1.0 - depth) * float(ns - 1))), 0, ns - 1)
					cx_curve = _curve_x[idx]
				var road_cx := 640.0 + cx_curve - cam_x * depth * 320.0

				# 세계 좌표 기반 x — 도로와 동일 소실점으로 수렴
				var hash_val := absi(k * 134775813 + side * 1103515245 + li * 987654321)
				var xvar     := float(hash_val % (x_scatter * 2) - x_scatter) * depth
				# 산란이 도로 쪽(-side)으로 갈 때도 최소 이격 유지
				var margin   := float(side) * depth * TREE_MARGIN_FROM_ROAD
				var tx       := road_cx + float(side) * road_hw * edge_mult + xvar + margin

				var th  := depth * TREE_BASE_H
				var tex := _textures[_tex_idx(k, side, li)]
				var tw  := th * float(tex.get_width()) / float(tex.get_height())

				# 완전히 화면 밖으로 나간 나무만 제거
				if tx + tw * 0.5 < 0.0 or tx - tw * 0.5 > 1280.0:
					continue

				# 원거리 페이드만 유지
				var fade := 1.0 - clampf((dz - DZ_MAX * 0.75) / (DZ_MAX * 0.25), 0.0, 1.0)

				entries.append({
					"d":    depth,
					"rect": Rect2(tx - tw * 0.5, ground_y - th, tw, th),
					"tex":  tex,
					"fade": fade
				})

	if scavenging_sys != null and scavenging_sys.has_method("get_draw_entries"):
		entries.append_array(scavenging_sys.get_draw_entries())

	entries.sort_custom(func(a, b): return a.d < b.d)
	for e in entries:
		if e.has("is_car"):
			var flip_h = (e.side == 1)
			if flip_h:
				draw_set_transform(Vector2(e.rect.position.x + e.rect.size.x * 0.5, e.rect.position.y), 0.0, Vector2(-1, 1))
				var local_rect := Rect2(-e.rect.size.x * 0.5, 0, e.rect.size.x, e.rect.size.y)
				draw_texture_rect(e.tex, local_rect, false, Color(1, 1, 1, e.fade))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 1)) # 복구
			else:
				draw_texture_rect(e.tex, e.rect, false, Color(1, 1, 1, e.fade))
		else:
			draw_texture_rect(e.tex, e.rect, false, Color(0.32, 0.38, 0.26, e.fade))
