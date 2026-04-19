extends Node2D

# --- Screen constants ---
const SCREEN_W     := 1280.0
const SCREEN_H     := 720.0
const HORIZON_Y    := 300.0

# --- Perspective constants ---
# ROAD_HW_MAX : 도로 최대 반폭 (픽셀)
const ROAD_HW_MAX      := 650.0
# ROAD_BOTTOM_Y : 도로가 최대 폭에 도달하는 화면 Y 좌표 (대시보드 위)
const ROAD_BOTTOM_Y    := 500.0
# CAMERA_DEPTH : 투영 깊이 상수 (FOV ~60도 기준 0.84)
const CAMERA_DEPTH     := 0.84
# STRIPE_INTERVAL : 한 줄무늬 쌍의 세계 단위 길이
const STRIPE_INTERVAL  := 1.2
# NUM_STRIPS : 도로를 몇 개의 수평 띠로 나눌지
const NUM_STRIPS       := 200

# --- Colors (GDD 팔레트 기반) ---
const COL_SKY_FILL  := Color(0.039, 0.039, 0.078, 1.0)   # #0A0A14 (sky 이미지 없을 때 폴백)
const COL_GRASS_A   := Color(0.022, 0.032, 0.012, 1.0)   # 야간 잔디 (거의 검정)
const COL_GRASS_B   := Color(0.032, 0.045, 0.018, 1.0)   # 야간 잔디 B
const COL_ROAD_A    := Color(0.072, 0.062, 0.055, 1.0)   # 야간 도로
const COL_ROAD_B    := Color(0.088, 0.076, 0.066, 1.0)   # 야간 도로 B
const COL_RUMBLE_W  := Color(0.800, 0.800, 0.800, 1.0)   # #CCCCCC
const COL_LANE_Y    := Color(0.831, 0.722, 0.251, 1.0)   # #D4B840 (중앙선 황색)

# --- State (game_world 에서 매 프레임 갱신) ---
var scroll_z : float = 0.0   # 세계 단위로 누적된 전진 거리
var cam_x    : float = 0.0   # 차선 횡 오프셋 (-1 = 좌, 0 = 중앙, 1 = 우)
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var hill_px  : float = 0.0   # 지평선 Y 오프셋(픽셀)

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array = PackedFloat32Array(), p_hill_px: float = 0.0) -> void:
	scroll_z = p_scroll_z
	cam_x    = p_lane_x
	_curve_x = p_curve_x
	hill_px  = p_hill_px
	queue_redraw()

func _draw() -> void:
	var hy := HORIZON_Y + hill_px
	# 지평선 아래 전체를 잔디색으로 채운다 (strips로 덮어쓰기 전 베이스)
	draw_rect(Rect2(0.0, hy, SCREEN_W, SCREEN_H - hy), COL_GRASS_A)

	for i in range(NUM_STRIPS):
		# t : 0.0 = 화면 최하단(가장 가까운 도로), 1.0 = 지평선
		var t      := float(i)     / float(NUM_STRIPS)
		var t_next := float(i + 1) / float(NUM_STRIPS)

		# 화면 Y 좌표 (선형 매핑, 아래→위)
		# lerp() 는 Variant 반환 → float 전용 lerpf() 사용
		var y_bot  := lerpf(SCREEN_H, hy, t)
		var y_top  := lerpf(SCREEN_H, hy, t_next)
		var strip_h := maxf(y_bot - y_top, 0.5)

		# depth: 1.0 = ROAD_BOTTOM_Y(대시보드 위), 0 = 지평선; 그 아래는 1.0 고정
		var depth := clampf((y_bot - hy) / (ROAD_BOTTOM_Y - hy), 0.0, 1.0)

		# 도로 반폭 — 선형 원근 감소
		var road_hw := depth * ROAD_HW_MAX

		# 도로 중심 X — 코너 누적 오프셋 + 차선(cam_x)
		var cx_curve := 0.0
		if _curve_x.size() == NUM_STRIPS:
			cx_curve = _curve_x[i]
		var road_cx := SCREEN_W * 0.5 + cx_curve - cam_x * depth * 320.0

		# 줄무늬 패리티 — 세계 공간 기반 (depth ≈ 0 방지)
		var world_z   := scroll_z + CAMERA_DEPTH / maxf(depth, 0.005)
		var stripe    := (int(floorf(world_z / STRIPE_INTERVAL)) % 2 + 2) % 2

		# ── 잔디 ──
		var gc := COL_GRASS_A if stripe == 0 else COL_GRASS_B
		draw_rect(Rect2(0.0, y_top, SCREEN_W, strip_h), gc)

		# ── 도로 ──
		var rc := COL_ROAD_A if stripe == 0 else COL_ROAD_B
		draw_rect(Rect2(road_cx - road_hw, y_top, road_hw * 2.0, strip_h), rc)

		# ── 럼블 스트립 (흰색, 구간별 도색 마모 효과) ──
		if road_hw > 8.0:
			var rw        := maxf(road_hw * 0.06, 2.0)
			var paint_sec := int(floorf(world_z / 3.0))
			# 좌우 독립 해시로 각각 마모 패턴 결정
			for rs in [-1, 1]:
				var phash   := absi(paint_sec * 2654435761 + rs * 1234567) % 1000
				var paint_a : float
				if phash < 15:        # ~1.5% 완전 박리
					paint_a = 0.0
				elif phash < 110:     # ~9.5% 부분 마모
					paint_a = 0.2 + float(phash - 15) / 95.0 * 0.5
				else:                 # ~89% 정상
					paint_a = 1.0
				if paint_a > 0.01:
					var rcl := Color(COL_RUMBLE_W.r, COL_RUMBLE_W.g, COL_RUMBLE_W.b, paint_a)
					if rs == -1:
						draw_rect(Rect2(road_cx - road_hw,      y_top, rw, strip_h), rcl)
					else:
						draw_rect(Rect2(road_cx + road_hw - rw, y_top, rw, strip_h), rcl)

		# ── 중앙 황색 점선 (stripe == 0 인 줄무늬에만) ──
		if stripe == 0 and road_hw > 15.0:
			var lw := maxf(depth * 4.0, 1.0)
			draw_rect(Rect2(road_cx - lw * 0.5, y_top, lw, strip_h), COL_LANE_Y)

	# ── 헤드라이트 콘 ──────────────────────────────────────────────────────────
	const HL_APEX_X  := 132.0
	const HL_APEX_Y  := 620.0
	const HL_OUTER_W := 340.0
	const HL_INNER_W := 240.0   # 중앙 너머까지 뻗어야 도로 위에서 자연스럽게 겹침

	var beam_cx  := SCREEN_W * 0.5
	var c_apex   := Color(0.96, 0.90, 0.62, 0.88)
	var c_center := Color(0.96, 0.90, 0.62, 0.08)   # 수평선 중앙 미광 (좌우 그라데이션용)
	var c_zero   := Color(0.0, 0.0, 0.0, 0.0)

	# 왼쪽 글로우
	draw_polygon(
		PackedVector2Array([
			Vector2(beam_cx - HL_APEX_X, HL_APEX_Y),
			Vector2(beam_cx - HL_OUTER_W - 60.0, hy),
			Vector2(beam_cx + HL_INNER_W + 40.0, hy),
		]),
		PackedColorArray([Color(c_apex.r, c_apex.g, c_apex.b, 0.20), c_zero, c_zero]))

	# 왼쪽 코어 (4점: outer-dark → center-dim → inner-dark, 좌우 그라데이션)
	draw_polygon(
		PackedVector2Array([
			Vector2(beam_cx - HL_APEX_X, HL_APEX_Y),
			Vector2(beam_cx - HL_OUTER_W, hy),
			Vector2(beam_cx,              hy),
			Vector2(beam_cx + HL_INNER_W, hy),
		]),
		PackedColorArray([c_apex, c_zero, c_center, c_zero]))

	# 오른쪽 글로우
	draw_polygon(
		PackedVector2Array([
			Vector2(beam_cx + HL_APEX_X, HL_APEX_Y),
			Vector2(beam_cx - HL_INNER_W - 40.0, hy),
			Vector2(beam_cx + HL_OUTER_W + 60.0, hy),
		]),
		PackedColorArray([Color(c_apex.r, c_apex.g, c_apex.b, 0.20), c_zero, c_zero]))

	# 오른쪽 코어
	draw_polygon(
		PackedVector2Array([
			Vector2(beam_cx + HL_APEX_X, HL_APEX_Y),
			Vector2(beam_cx - HL_INNER_W, hy),
			Vector2(beam_cx,              hy),
			Vector2(beam_cx + HL_OUTER_W, hy),
		]),
		PackedColorArray([c_apex, c_zero, c_center, c_zero]))
