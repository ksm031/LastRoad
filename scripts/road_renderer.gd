extends Node2D

# 공통 상수는 BillboardManager에 정의됨
const NUM_STRIPS       := 400
const COL_SKY_FILL  := Color(0.039, 0.039, 0.078, 1.0)   # sky 이미지 없을 때 폴백

# --- State (game_world 에서 매 프레임 갱신) ---
var scroll_z       : float = 0.0
var cam_x          : float = 0.0
var _curve_x       : PackedFloat32Array = PackedFloat32Array()
var hill_px        : float = 0.0
var show_headlight : bool  = true   # 스테이지 클리어 연출 중 false로 설정
var road_modulate  : Color = Color.WHITE

var _hl_rect: ColorRect

func _ready() -> void:
	_hl_rect = ColorRect.new()
	add_child(_hl_rect)
	
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode blend_add;
uniform vec4 light_color : source_color = vec4(1.0, 0.90, 0.55, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
void fragment() {
	vec2 uv = UV;
	float x = uv.x - 0.5;
	
	// y=0(지평선), y=1(화면 하단)
	float y_raw = uv.y; 
	
	// 대시보드에 가려지는 아래쪽을 무시하고, 시야에 보이는 부분(y=0.5 주변)이 가장 밝도록 보정
	// 0.0(지평선) ~ 1.0(차 바로 앞 시야)
	float y = smoothstep(0.0, 0.5, y_raw); 
	
	// 부채꼴 형태 (멀어질수록 좁아짐)
	float cone_width = 0.15 + 0.55 * y;
	float cone = smoothstep(cone_width, cone_width - 0.3, abs(x));
	
	// 거리 감쇄 (먼 곳은 부드럽게, 가까운 곳은 강렬하게)
	// 지수를 낮추어(1.2 -> 0.6) 더 먼 곳까지 빛이 강하게 도달하게 함
	float falloff = pow(y, 0.6); 
	
	// 중앙 집중 광선 (강력한 코어)
	float core = smoothstep(0.2, 0.0, abs(x)) * 0.7 * y;
	
	float brightness = (cone + core) * falloff * intensity;
	COLOR = vec4(light_color.rgb * brightness, brightness * 0.9);
}
"""
	mat.shader = shader
	_hl_rect.material = mat
	_hl_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array = PackedFloat32Array(), p_hill_px: float = 0.0, p_headlight_range: float = 1.0) -> void:
	scroll_z = p_scroll_z
	cam_x    = p_lane_x
	_curve_x = p_curve_x
	hill_px  = p_hill_px
	
	var hy := BillboardManager.HORIZON_Y + hill_px
	if _hl_rect:
		_hl_rect.visible = show_headlight
		_hl_rect.position = Vector2(0, hy)
		_hl_rect.size = Vector2(BillboardManager.SCREEN_W, BillboardManager.SCREEN_H - hy)
		
		var mat := _hl_rect.material as ShaderMaterial
		if mat:
			# BillboardManager에 정의된 공통 강도 설정을 따름
			mat.set_shader_parameter("intensity", BillboardManager.HL_INTENSITY_ROAD * p_headlight_range)
		
	queue_redraw()

func _draw() -> void:
	var hy := BillboardManager.HORIZON_Y + hill_px
	# 지평선 아래 전체를 잔디색으로 채운다 (strips로 덮어쓰기 전 베이스)
	draw_rect(Rect2(0.0, hy, BillboardManager.SCREEN_W, BillboardManager.SCREEN_H - hy), BillboardManager.COL_GRASS_A * road_modulate)

	for i in range(NUM_STRIPS):
		var t      := float(i)     / float(NUM_STRIPS)
		var t_next := float(i + 1) / float(NUM_STRIPS)

		var y_bot  := lerpf(BillboardManager.SCREEN_H, hy, t)
		var y_top  := lerpf(BillboardManager.SCREEN_H, hy, t_next)
		var strip_h := maxf(y_bot - y_top, 0.5)

		var depth := maxf((y_bot - hy) / (BillboardManager.ROAD_BOTTOM_Y - hy), 0.0)
		var road_hw := depth * BillboardManager.ROAD_HW_MAX

		var cx_curve := 0.0
		if _curve_x.size() == NUM_STRIPS:
			cx_curve = _curve_x[i]
		var road_cx := BillboardManager.SCREEN_W * 0.5 + cx_curve - cam_x * depth * 320.0

		var world_z   := scroll_z + BillboardManager.CAMERA_DEPTH / maxf(depth, 0.005)
		var stripe    := (int(floorf(world_z / BillboardManager.STRIPE_INTERVAL)) % 2 + 2) % 2

		# ── 잔디 ──
		var gc := (BillboardManager.COL_GRASS_A if stripe == 0 else BillboardManager.COL_GRASS_B) * road_modulate
		draw_rect(Rect2(0.0, y_top, BillboardManager.SCREEN_W, strip_h), gc)

		# ── 도로 ──
		var rc := (BillboardManager.COL_ROAD_A if stripe == 0 else BillboardManager.COL_ROAD_B) * road_modulate
		draw_rect(Rect2(road_cx - road_hw, y_top, road_hw * 2.0, strip_h), rc)

		# ── 럼블 스트립 ──
		if road_hw > 8.0:
			var rw        := maxf(road_hw * 0.06, 2.0)
			var paint_sec := int(floorf(world_z / 3.0))
			for rs in [-1, 1]:
				var phash   := absi(paint_sec * 2654435761 + rs * 1234567) % 1000
				var paint_a : float
				if phash < 15:
					paint_a = 0.0
				elif phash < 110:
					paint_a = 0.2 + float(phash - 15) / 95.0 * 0.5
				else:
					paint_a = 1.0
				if paint_a > 0.01:
					var rcl := Color(BillboardManager.COL_RUMBLE_W.r, BillboardManager.COL_RUMBLE_W.g, BillboardManager.COL_RUMBLE_W.b, paint_a) * road_modulate
					if rs == -1:
						draw_rect(Rect2(road_cx - road_hw,      y_top, rw, strip_h), rcl)
					else:
						draw_rect(Rect2(road_cx + road_hw - rw, y_top, rw, strip_h), rcl)

		# ── 중앙 황색 점선 ──
		if stripe == 0 and road_hw > 15.0:
			var lw := maxf(depth * 4.0, 1.0)
			draw_rect(Rect2(road_cx - lw * 0.5, y_top, lw, strip_h), BillboardManager.COL_LANE_Y * road_modulate)
