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
uniform float flicker : hint_range(0.0, 2.0) = 1.0;
uniform float lightning : hint_range(0.0, 2.0) = 0.0;
uniform float scroll_z;

// Simple hash for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = UV;
	float x = uv.x - 0.5;
	float y_raw = uv.y; 
	float y = smoothstep(0.0, 0.5, y_raw); 
	
	// 1. 기본 헤드라이트 원뿔
	float cone_width = 0.15 + 0.55 * y;
	float cone = smoothstep(cone_width, cone_width - 0.3, abs(x));
	float falloff = pow(y, 0.6); 
	float core = smoothstep(0.2, 0.0, abs(x)) * 0.7 * y;
	
	// 전체 밝기 균형 조정
	float final_int = (cone * 0.8 + core * 0.5) * falloff * intensity * flicker;
	
	// 번개 효과: 화면 전체를 일시적으로 밝힘 (노란색이 아닌 흰색 계열로 처리)
	vec3 base_col = light_color.rgb * final_int;
	vec3 lightning_col = vec3(lightning * 0.85 * 0.5);
	
	COLOR = vec4(base_col + lightning_col, clamp(final_int * 0.9 + lightning * 0.6, 0.0, 1.0));
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
			mat.set_shader_parameter("flicker",   BillboardManager.current_flicker)
			mat.set_shader_parameter("lightning", BillboardManager.lightning_intensity)
			mat.set_shader_parameter("scroll_z",  scroll_z)
		
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
