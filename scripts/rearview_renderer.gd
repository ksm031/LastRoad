extends Node2D
class_name RearviewRenderer

# 공통 상수는 BillboardManager에 정의됨
const NUM_STRIPS_LOW   := 80
const NUM_STRIPS_HIGH  := 200
var _active_strips     : int = 80

# --- Colors (후방 전용) ---
const COL_SKY       := Color(0.12, 0.14, 0.18, 1.0)

var scroll_z : float = 0.0
var _wendigo : Sprite2D
var _monster_distance : float = 200.0
var _anim_time : float = 0.0

# 나무 렌더링 관련
var _tree_textures : Array[Texture2D] = []
const TREE_BASE_H := 480.0
const TREE_LAYERS := [
	[1.3, 4.0, 30],
	[2.0, 5.0, 150]
]

# 웬디고 스프라이트 시트 설정
const WENDIGO_HFRAMES := 5
const WENDIGO_VFRAMES := 5

func _ready() -> void:
	for i in range(1, 8):
		var t := load("res://Asset/Image/trees/tree_%02d.png" % i) as Texture2D
		if t:
			_tree_textures.append(t)

	_wendigo = Sprite2D.new()
	var tex := load("res://Asset/Image/Character/Wendigo_sprint_down.png") as Texture2D
	if tex:
		_wendigo.texture = tex
		_wendigo.hframes = WENDIGO_HFRAMES
		_wendigo.vframes = WENDIGO_VFRAMES
		_wendigo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_wendigo)

func update_state(p_scroll_z: float, monster_dist: float, delta: float, zoomed: bool = false) -> void:
	scroll_z = p_scroll_z
	_monster_distance = monster_dist
	_active_strips = NUM_STRIPS_HIGH if zoomed else NUM_STRIPS_LOW

	_anim_time += delta * 15.0
	if _wendigo.texture:
		var total_frames := _wendigo.hframes * _wendigo.vframes
		_wendigo.frame = int(_anim_time) % total_frames

		var dist_t := clampf(_monster_distance / 60.0, 0.0, 1.0)
		var visual_depth := lerpf(2.5, 0.08, pow(dist_t, 0.8))

		var ground_y := BillboardManager.HORIZON_Y + visual_depth * (BillboardManager.ROAD_BOTTOM_Y - BillboardManager.HORIZON_Y)

		var base_h := float(_wendigo.texture.get_height()) / float(_wendigo.vframes)
		var target_h := visual_depth * 450.0

		var scale_factor := target_h / maxf(base_h, 1.0)
		_wendigo.scale = Vector2(scale_factor, scale_factor)

		_wendigo.position = Vector2(BillboardManager.SCREEN_W * 0.5, ground_y - target_h * 0.5)

	queue_redraw()

func _draw() -> void:
	var hy := BillboardManager.HORIZON_Y
	draw_rect(Rect2(0.0, 0.0, BillboardManager.SCREEN_W, hy), COL_SKY)
	draw_rect(Rect2(0.0, hy, BillboardManager.SCREEN_W, BillboardManager.SCREEN_H - hy), BillboardManager.COL_GRASS_A)

	for i in range(_active_strips):
		var t      := float(i)     / float(_active_strips)
		var t_next := float(i + 1) / float(_active_strips)

		var y_bot  := lerpf(BillboardManager.SCREEN_H, hy, t)
		var y_top  := lerpf(BillboardManager.SCREEN_H, hy, t_next)
		var strip_h := maxf(y_bot - y_top, 0.5)

		var depth := clampf((y_bot - hy) / (BillboardManager.ROAD_BOTTOM_Y - hy), 0.0, 1.0)
		var road_hw := depth * BillboardManager.ROAD_HW_MAX
		var road_cx := BillboardManager.SCREEN_W * 0.5

		var world_z   := -scroll_z + BillboardManager.CAMERA_DEPTH / maxf(depth, 0.005)
		var stripe    := (int(floorf(world_z / BillboardManager.STRIPE_INTERVAL)) % 2 + 2) % 2

		var gc := BillboardManager.COL_GRASS_A if stripe == 0 else BillboardManager.COL_GRASS_B
		draw_rect(Rect2(0.0, y_top, BillboardManager.SCREEN_W, strip_h), gc)

		var rc := BillboardManager.COL_ROAD_A if stripe == 0 else BillboardManager.COL_ROAD_B
		draw_rect(Rect2(road_cx - road_hw, y_bot, road_hw * 2.0, strip_h), rc)

		if road_hw > 8.0:
			var rw := maxf(road_hw * 0.06, 2.0)
			draw_rect(Rect2(road_cx - road_hw, y_bot, rw, strip_h), BillboardManager.COL_RUMBLE_W)
			draw_rect(Rect2(road_cx + road_hw - rw, y_bot, rw, strip_h), BillboardManager.COL_RUMBLE_W)

		if stripe == 0 and road_hw > 15.0:
			var lw := maxf(depth * 4.0, 1.0)
			draw_rect(Rect2(road_cx - lw * 0.5, y_bot, lw, strip_h), BillboardManager.COL_LANE_Y)

	# 후방 나무 렌더링
	if not _tree_textures.is_empty():
		var entries := []
		for side in [-1, 1]:
			for li in range(TREE_LAYERS.size()):
				var edge_mult := float(TREE_LAYERS[li][0])
				var spacing   := float(TREE_LAYERS[li][1])
				var x_scatter := int(TREE_LAYERS[li][2])
				var z_offset  := float(li) * spacing * 0.37 + (0.0 if side == -1 else spacing * 0.5)

				var k_min := int(ceilf((scroll_z - 72.0 - z_offset) / spacing))
				var k_max := int(floorf((scroll_z - 0.4 - z_offset) / spacing))

				for k in range(k_min, k_max + 1):
					var wz  := float(k) * spacing + z_offset
					var dz  := scroll_z - wz
					if dz <= 0.0:
						continue

					var depth := clampf(BillboardManager.CAMERA_DEPTH / dz, 0.0, 1.0)
					if depth < 0.02:
						continue

					var ground_y := hy + depth * (BillboardManager.ROAD_BOTTOM_Y - hy)
					var road_hw := depth * BillboardManager.ROAD_HW_MAX
					var road_cx := BillboardManager.SCREEN_W * 0.5

					var hash_val := absi(k * 134775813 + side * 1103515245 + li * 987654321)
					var xvar     := float(hash_val % (x_scatter * 2) - x_scatter) * depth
					var margin   := float(side) * depth * 28.0
					var tx       := road_cx + float(side) * road_hw * edge_mult + xvar + margin

					var th  := depth * TREE_BASE_H
					var t_idx := absi(k * 2654435761 + side * 40503 + li * 1234567) % _tree_textures.size()
					var tex := _tree_textures[t_idx]
					var tw  := th * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)

					if tx + tw * 0.5 < 0.0 or tx - tw * 0.5 > BillboardManager.SCREEN_W:
						continue

					entries.append({
						"d":    depth,
						"rect": Rect2(tx - tw * 0.5, ground_y - th, tw, th),
						"tex":  tex,
					})

		entries.sort_custom(func(a, b): return a.d < b.d)
		for e in entries:
			draw_texture_rect(e.tex, e.rect, false, Color(0.32, 0.38, 0.26))
