extends Node2D
class_name RearviewRenderer

# --- Screen constants ---
const SCREEN_W     := 1280.0
const SCREEN_H     := 720.0
const HORIZON_Y    := 300.0

# --- Perspective constants ---
const ROAD_HW_MAX      := 650.0
const ROAD_BOTTOM_Y    := 500.0
const CAMERA_DEPTH     := 0.84
const STRIPE_INTERVAL  := 1.2
const NUM_STRIPS_LOW   := 80
const NUM_STRIPS_HIGH  := 200
var _active_strips     : int = 80

# --- Colors ---
const COL_GRASS_A   := Color(0.022, 0.032, 0.012, 1.0)
const COL_GRASS_B   := Color(0.032, 0.045, 0.018, 1.0)
const COL_ROAD_A    := Color(0.072, 0.062, 0.055, 1.0)
const COL_ROAD_B    := Color(0.088, 0.076, 0.066, 1.0)
const COL_SKY       := Color(0.12, 0.14, 0.18, 1.0) # 살짝 밝아진 하늘
const COL_RUMBLE_W  := Color(0.800, 0.800, 0.800, 1.0)
const COL_LANE_Y    := Color(0.831, 0.722, 0.251, 1.0)

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
	# 나무 텍스처 로드
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
	
	_anim_time += delta * 15.0 # 15 FPS 애니메이션
	if _wendigo.texture:
		var total_frames := _wendigo.hframes * _wendigo.vframes
		_wendigo.frame = int(_anim_time) % total_frames
		
		# [긴장감 연출을 위한 시각적 속임수]
		# 실제 투영(1/x)을 쓰면 멀 때는 보이지도 않다가 마지막에 갑자기 다가오게 됩니다.
		# 멀리 있을 때(거리 60)도 거울에 꽤 크게(0.08) 보이게 하고, 가까워질 때(거리 0) 2.5배 깊이까지 들어오도록 선형 보간합니다.
		# 이렇게 하면 크기(450)를 비정상적으로 뻥튀기하는 게 아니라, 실제로 차 코앞(화면 아래쪽)까지 성큼성큼 다가오게 됩니다.
		var dist_t := clampf(_monster_distance / 60.0, 0.0, 1.0)
		var visual_depth := lerpf(2.5, 0.08, pow(dist_t, 0.8)) 
		
		var ground_y := HORIZON_Y + visual_depth * (ROAD_BOTTOM_Y - HORIZON_Y)
		
		# 웬디고 기본 높이(픽셀)
		var base_h := float(_wendigo.texture.get_height()) / float(_wendigo.vframes)
		# 크기를 거인처럼 키우는 게 아니라, 원본 스케일(450.0)을 유지하되 visual_depth가 커지면서 자연스럽게 화면에 꽉 차게 됨
		var target_h := visual_depth * 450.0 
		
		var scale_factor := target_h / maxf(base_h, 1.0)
		_wendigo.scale = Vector2(scale_factor, scale_factor)
		
		# 중앙 정렬 (다리 부분이 ground_y에 닿도록)
		_wendigo.position = Vector2(SCREEN_W * 0.5, ground_y - target_h * 0.5)

	queue_redraw()

func _draw() -> void:
	# 배경 하늘 영역 (메인 씬이 비치지 않도록 밝은 어두운 색으로 칠함)
	var hy := HORIZON_Y
	draw_rect(Rect2(0.0, 0.0, SCREEN_W, hy), COL_SKY)
	draw_rect(Rect2(0.0, hy, SCREEN_W, SCREEN_H - hy), COL_GRASS_A)

	for i in range(_active_strips):
		var t      := float(i)     / float(_active_strips)
		var t_next := float(i + 1) / float(_active_strips)

		var y_bot  := lerpf(SCREEN_H, hy, t)
		var y_top  := lerpf(SCREEN_H, hy, t_next)
		var strip_h := maxf(y_bot - y_top, 0.5)

		var depth := clampf((y_bot - hy) / (ROAD_BOTTOM_Y - hy), 0.0, 1.0)
		var road_hw := depth * ROAD_HW_MAX
		var road_cx := SCREEN_W * 0.5

		# 후방 도로이므로 스크롤 방향 반대 (-scroll_z)
		var world_z   := -scroll_z + CAMERA_DEPTH / maxf(depth, 0.005)
		var stripe    := (int(floorf(world_z / STRIPE_INTERVAL)) % 2 + 2) % 2

		var gc := COL_GRASS_A if stripe == 0 else COL_GRASS_B
		draw_rect(Rect2(0.0, y_top, SCREEN_W, strip_h), gc)

		var rc := COL_ROAD_A if stripe == 0 else COL_ROAD_B
		draw_rect(Rect2(road_cx - road_hw, y_bot, road_hw * 2.0, strip_h), rc)
		
		# 갓길 선 (럼블 스트립)
		if road_hw > 8.0:
			var rw := maxf(road_hw * 0.06, 2.0)
			# 후방은 마모 효과 없이 단순히 그리기만 해도 충분함
			draw_rect(Rect2(road_cx - road_hw, y_bot, rw, strip_h), COL_RUMBLE_W)
			draw_rect(Rect2(road_cx + road_hw - rw, y_bot, rw, strip_h), COL_RUMBLE_W)
			
		# 중앙선 (점선)
		if stripe == 0 and road_hw > 15.0:
			var lw := maxf(depth * 4.0, 1.0)
			draw_rect(Rect2(road_cx - lw * 0.5, y_bot, lw, strip_h), COL_LANE_Y)

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
					var dz  := scroll_z - wz # 후방이므로 현재 위치보다 작은 wz가 뒤쪽임
					if dz <= 0.0:
						continue

					var depth := clampf(CAMERA_DEPTH / dz, 0.0, 1.0)
					if depth < 0.02:
						continue

					var ground_y := hy + depth * (ROAD_BOTTOM_Y - hy)
					var road_hw := depth * ROAD_HW_MAX
					var road_cx := SCREEN_W * 0.5

					var hash_val := absi(k * 134775813 + side * 1103515245 + li * 987654321)
					var xvar     := float(hash_val % (x_scatter * 2) - x_scatter) * depth
					var margin   := float(side) * depth * 28.0
					var tx       := road_cx + float(side) * road_hw * edge_mult + xvar + margin

					var th  := depth * TREE_BASE_H
					var t_idx := absi(k * 2654435761 + side * 40503 + li * 1234567) % _tree_textures.size()
					var tex := _tree_textures[t_idx]
					var tw  := th * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)

					if tx + tw * 0.5 < 0.0 or tx - tw * 0.5 > SCREEN_W:
						continue

					entries.append({
						"d":    depth,
						"rect": Rect2(tx - tw * 0.5, ground_y - th, tw, th),
						"tex":  tex,
					})

		entries.sort_custom(func(a, b): return a.d < b.d)
		for e in entries:
			draw_texture_rect(e.tex, e.rect, false, Color(0.32, 0.38, 0.26))
