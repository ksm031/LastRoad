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
var max_dist : float = 150.0   # 이 거리에서 지평선 크기. game_world.MONSTER_MAX_DIST와 동기화
var _anim_time : float = 0.0

# ── 창 던지기 연출 (Doc 08): game_world가 매 프레임 spear_system.get_mirror_state()를 넣어준다 ──
# { phase, side(-1/1), arm_t(0~1 팔 올림), streak_t(0~1 창 접근) }
var spear_state : Dictionary = {}
var _spear_fx : Node2D   # 웬디고 스프라이트 위에 그리기 위한 별도 레이어

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

	# 창 연출 레이어 — 웬디고 뒤에 add 해야 위에 그려짐
	_spear_fx = Node2D.new()
	_spear_fx.draw.connect(_on_spear_fx_draw)
	add_child(_spear_fx)

func update_state(p_scroll_z: float, monster_dist: float, delta: float, zoomed: bool = false) -> void:
	scroll_z = p_scroll_z
	_monster_distance = monster_dist
	_active_strips = NUM_STRIPS_HIGH if zoomed else NUM_STRIPS_LOW

	_anim_time += delta * 15.0
	if _wendigo.texture:
		var total_frames := _wendigo.hframes * _wendigo.vframes
		_wendigo.frame = int(_anim_time) % total_frames

		# 상한 거리에서도 지평선에 작게 보이도록 (고무줄 모델: 괴물은 항상 미러 안에 있다)
		# pow 0.6 → 멀 때 크기 변화가 완만하고, 가까워질수록 급격히 커짐
		var dist_t := clampf(_monster_distance / maxf(max_dist, 1.0), 0.0, 1.0)
		var visual_depth := lerpf(2.5, 0.06, pow(dist_t, 0.6))

		var ground_y := BillboardManager.HORIZON_Y + visual_depth * (BillboardManager.ROAD_BOTTOM_Y - BillboardManager.HORIZON_Y)

		var base_h := float(_wendigo.texture.get_height()) / float(_wendigo.vframes)
		var target_h := visual_depth * 450.0

		var scale_factor := target_h / maxf(base_h, 1.0)
		_wendigo.scale = Vector2(scale_factor, scale_factor)

		_wendigo.position = Vector2(BillboardManager.SCREEN_W * 0.5, ground_y - target_h * 0.5)

	queue_redraw()
	if _spear_fx:
		_spear_fx.queue_redraw()

# ── 창 던지기: 들린 팔 + 날아오는 창 (Doc 08 §시퀀스) ──
# 룸미러는 좌우 반전 없음 → 오른쪽 화면에 손이 보이면 도로 오른쪽으로 창이 온다.
func _on_spear_fx_draw() -> void:
	if spear_state.is_empty() or _wendigo == null or _wendigo.texture == null:
		return
	var side := int(spear_state.get("side", 1))
	var arm_t := float(spear_state.get("arm_t", 0.0))
	var streak_t := float(spear_state.get("streak_t", 0.0))
	if arm_t <= 0.0 and streak_t <= 0.0:
		return

	var frame_w := float(_wendigo.texture.get_width()) / float(_wendigo.hframes) * _wendigo.scale.x
	var frame_h := float(_wendigo.texture.get_height()) / float(_wendigo.vframes) * _wendigo.scale.y
	var pos := _wendigo.position
	var black := Color(0.02, 0.02, 0.03, 1.0)

	if arm_t > 0.0:
		# 어깨 → 머리 위로 올라가는 팔 + 창. 멀리 있어도 식별되도록 최소 두께 보장
		var shoulder := pos + Vector2(float(side) * frame_w * 0.28, -frame_h * 0.12)
		var reach := frame_h * 0.75 * arm_t
		var hand := shoulder + Vector2(float(side) * frame_w * 0.22 * arm_t, -reach)
		var thick := maxf(frame_w * 0.08, 2.5)
		_spear_fx.draw_line(shoulder, hand, black, thick)
		# 창: 손에서 위로 길게. 윈드업 후반에 수평→수직으로 세워짐
		var spear_len := frame_h * 0.9 * clampf(arm_t * 1.3, 0.0, 1.0)
		var tip := hand + Vector2(float(side) * spear_len * (1.0 - arm_t) * 0.6, -spear_len * arm_t)
		_spear_fx.draw_line(hand, tip, black, maxf(thick * 0.7, 2.0))
		# 창끝 들쭉날쭉한 느낌: 짧은 가지 2개
		var d := (tip - hand).normalized()
		_spear_fx.draw_line(tip, tip - d * spear_len * 0.15 + d.orthogonal() * thick * 1.5, black, maxf(thick * 0.5, 1.5))
		_spear_fx.draw_line(tip, tip - d * spear_len * 0.12 - d.orthogonal() * thick * 1.2, black, maxf(thick * 0.5, 1.5))

	if streak_t > 0.0:
		# 괴물 손에서 거울 하단(차 뒤) side 쪽으로 쭉 뻗어오는 검은 줄기
		var start := pos + Vector2(float(side) * frame_w * 0.4, -frame_h * 0.6)
		var end_pt := Vector2(BillboardManager.SCREEN_W * 0.5 + float(side) * 420.0, BillboardManager.SCREEN_H + 40.0)
		var head := start.lerp(end_pt, streak_t)
		var tail := start.lerp(end_pt, maxf(streak_t - 0.35, 0.0))
		var w := lerpf(2.0, 26.0, streak_t)
		_spear_fx.draw_line(tail, head, black, w)
		_spear_fx.draw_line(tail, head, Color(0.02, 0.02, 0.03, 0.35), w * 2.2)

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
