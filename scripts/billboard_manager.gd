extends Node2D
class_name BillboardManager

# ── 화면/도로 공통 상수 ─────────────────────────────────────
const SCREEN_W       := 1280.0
const SCREEN_H       := 720.0
const HORIZON_Y      := 300.0
const ROAD_BOTTOM_Y  := 500.0
const ROAD_HW_MAX    := 650.0
const CAMERA_DEPTH   := 0.84
const STRIPE_INTERVAL := 2.0

# ── 헤드라이트 밝기 설정 (조절 가능) ──────────
static var HL_INTENSITY_ROAD   := 0.6
static var HL_INTENSITY_OBJECTS:= 1.3

# ── 조명 효과 관련 (Flicker, Shake, Lightning) ──
static var current_flicker: float = 1.0
static var lightning_intensity: float = 0.0
static var _flicker_timer: float = 0.0
static var _shake_intensity: float = 0.0

# ── 도로 색상 (road_renderer / rearview_renderer 공유) ──────
const COL_GRASS_A  := Color(0.022, 0.032, 0.012, 1.0)
const COL_GRASS_B  := Color(0.032, 0.045, 0.018, 1.0)
const COL_ROAD_A   := Color(0.072, 0.062, 0.055, 1.0)
const COL_ROAD_B   := Color(0.088, 0.076, 0.066, 1.0)
const COL_RUMBLE_W := Color(0.800, 0.800, 0.800, 1.0)
const COL_LANE_Y   := Color(0.831, 0.722, 0.251, 1.0)

static func get_curve_at_depth(depth: float, curve_x: PackedFloat32Array) -> float:
	var n := curve_x.size()
	if n <= 1: return 0.0
	var t : float = 1.0 - depth * (ROAD_BOTTOM_Y - HORIZON_Y) / (SCREEN_H - HORIZON_Y)
	var findex : float = t * float(n - 1)
	var idx := clampi(int(floor(findex)), 0, n - 2)
	var frac := findex - float(idx)
	return lerpf(curve_x[idx], curve_x[idx + 1], frac)

static func get_road_cx(depth: float, cam_x: float, curve_x: PackedFloat32Array) -> float:
	var cx_curve := get_curve_at_depth(depth, curve_x)
	return 640.0 + cx_curve - cam_x * depth * 320.0

static func get_ground_y(depth: float, hill_px: float) -> float:
	var hy := HORIZON_Y + hill_px
	return hy + depth * (ROAD_BOTTOM_Y - hy)

static func get_road_hw(depth: float) -> float:
	return depth * ROAD_HW_MAX

# ── 헤드라이트 셰이더 (watcher / jumper / obstacle 공유) ────────
# is_jumping / jump_t는 점퍼 전용 — 기본값 false/0.0 이므로 다른 시스템에선 무해
const HEADLIGHT_SHADER := """
shader_type canvas_item;
uniform float light_height : hint_range(0.0, 1.0) = 0.0;
uniform vec4  light_color   : source_color = vec4(0.91, 0.78, 0.48, 1.0);
uniform vec4  ambient_color : source_color = vec4(0.42, 0.42, 0.42, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.0;
uniform float light_skew : hint_range(-1.0, 1.0) = 0.0;
uniform float flicker : hint_range(0.0, 2.0) = 1.0;
uniform float lightning : hint_range(0.0, 2.0) = 0.0;
uniform float sway : hint_range(0.0, 1.0) = 0.0;
uniform float sway_offset = 0.0;
uniform bool  is_jumping = false;
uniform float jump_t : hint_range(0.0, 1.5) = 0.0;

void fragment() {
	vec2 uv = UV;
	
	// 바람에 흔들리는 효과 (상단부만 휘어짐, 개별 오프셋 적용)
	if (sway > 0.01) {
		float sway_val = sin(TIME * 2.5 + sway_offset) * 0.04 * sway;
		uv.x += sway_val * (1.0 - uv.y);
	}
	
	vec4 tex = texture(TEXTURE, uv);
	
	// 노말맵 계산 (CanvasTexture 사용 시 NORMAL_TEXTURE 자동 할당)
	vec3 normal = texture(NORMAL_TEXTURE, uv).rgb * 2.0 - 1.0;
	
	// 헤드라이트 방향 벡터 (카메라 -> 오브젝트)
	// z는 정면(1.0), y는 아래에서 위로(-0.15), x는 차량과의 상대적 위치(light_skew)
	vec3 light_dir = normalize(vec3(light_skew * 0.8, -0.15, 1.0));
	float diff = max(dot(normal, light_dir), 0.0);
	
	// 기존 높이 기반 조명
	float y_up = 1.0 - uv.y;
	float transition = 0.15;
	float lit = smoothstep(light_height, light_height - transition, y_up);
	
	// 노말맵 효과를 기존 조명(lit)에 결합 (기본 밝기 0.3 보장)
	float normal_factor = 0.3 + 0.7 * diff;
	float final_lit = lit * normal_factor;
	
	if (is_jumping) {
		float jump_unlit = smoothstep(jump_t, jump_t - 0.1, y_up);
		final_lit = min(final_lit, jump_unlit);
	}
	
	vec4 dark   = tex * ambient_color;
	// 번개 칠 때는 헤드라이트 색상도 중립적인 흰색으로 믹스하여 노란 기운 제거
	vec4 bright = tex * mix(light_color, vec4(1.1, 1.1, 1.2, 1.0), lightning) * intensity * flicker;
	
	// 번개 효과: 주변광을 일시적으로 대폭 상승시킴 (노말 무시)
	dark = mix(dark, tex * 1.5, lightning);
	
	COLOR   = mix(dark, bright, final_lit);
	COLOR.a = tex.a;
}
"""

static var _shared_headlight_shader: Shader = null

static func _get_headlight_shader() -> Shader:
	if _shared_headlight_shader == null:
		_shared_headlight_shader = Shader.new()
		_shared_headlight_shader.code = HEADLIGHT_SHADER
	return _shared_headlight_shader

## 헤드라이트 ShaderMaterial 풀 생성 (각 시스템 _ready()에서 한 번 호출)
## ambient: 비조명 영역 색 — 와쳐(0.06 어둠), 점퍼(0.42 회색), 돌(0.18 흙색)
static func create_headlight_materials(pool_size: int, ambient: Color = Color(0.42, 0.42, 0.42, 1.0)) -> Array[ShaderMaterial]:
	var shader := _get_headlight_shader()
	var result: Array[ShaderMaterial] = []
	for _i in pool_size:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("light_height",  0.0)
		mat.set_shader_parameter("light_color",   Color(0.91, 0.78, 0.48, 1.0))
		mat.set_shader_parameter("ambient_color", ambient)
		mat.set_shader_parameter("intensity",     HL_INTENSITY_OBJECTS)
		mat.set_shader_parameter("is_jumping",    false)
		mat.set_shader_parameter("jump_t",        0.0)
		mat.set_shader_parameter("light_skew",    0.0)
		mat.set_shader_parameter("sway",          0.0)
		mat.set_shader_parameter("sway_offset",   0.0)
		result.append(mat)
	return result

## 노말맵이 포함된 CanvasTexture 로드 헬퍼
static func load_with_normal(path: String) -> Texture2D:
	var base := load(path) as Texture2D
	if base == null: return null
	
	var normal_path := path.replace(".png", "_normal.png")
	if FileAccess.file_exists(normal_path):
		var normal := load(normal_path) as Texture2D
		if normal:
			var ct := CanvasTexture.new()
			ct.diffuse_texture = base
			ct.normal_texture = normal
			return ct
	return base

static func get_rand01(s: int, offset: int = 0) -> float:
	var h := hash(s + offset)
	return float(h & 0x7FFFFFFF) / 2147483647.0

static func z_to_light_height(depth: float, range_mult: float = 1.0) -> float:
	# depth는 가까울수록 큼 (0.01~1.0). 먼 거리(dz=80, depth=0.01)에서는 0.0
	# dz=40m(depth=0.024) 정도부터 서서히 밝아지기 시작하도록 조정
	var min_d := 0.02 / range_mult
	var max_d := 0.25 # dz=3m 정도에서 완전히 밝아짐
	var t := clampf((depth - min_d) / (max_d - min_d), 0.0, 1.0)
	return t # 선형으로 변경하여 더 "점점" 밝아지는 느낌 복구

## 원근 투영에 필요한 모든 공통 값을 한 번에 계산
static func calculate_projection(dz: float, cam_x: float, curve_x: PackedFloat32Array, hill_px: float, range_mult: float = 1.0) -> Dictionary:
	# 화면을 벗어나기 전에 렌더링이 사라지는 현상(dz <= 0)을 방지하기 위해 하한을 0.015로 약간 올림
	var depth := CAMERA_DEPTH / maxf(dz, 0.015)
	return {
		"depth": depth,
		"road_cx": get_road_cx(depth, cam_x, curve_x),
		"road_hw": get_road_hw(depth),
		"ground_y": get_ground_y(depth, hill_px),
		"light_h": z_to_light_height(depth, range_mult)
	}

const SHADOW_SHADER := """
shader_type canvas_item;
uniform float lightning = 0.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// UV.y: 0.0(상단=그림자 끝), 1.0(하단=발 부분)
	float gradient = smoothstep(0.0, 0.8, UV.y);
	// 번개 칠 때는 그림자도 연해짐
	float alpha = tex.a * COLOR.a * gradient * 0.7 * (1.0 - lightning * 0.8);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""

var _entries: Array = []
var _sprite_pool: Array[Sprite2D] = []
var _shadow_mat : ShaderMaterial

func _ready() -> void:
	_shadow_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADOW_SHADER
	_shadow_mat.shader = sh

func update_state(_p_scroll_z: float, _p_cam_x: float, _p_curve_x: PackedFloat32Array, _p_hill_px: float, _p_range_mult: float = 1.0) -> void:
	# 1. Flicker & Shake & Lightning 로직 업데이트
	_flicker_timer += 0.016 # 대략적인 delta
	
	# 번개 감쇄
	lightning_intensity = move_toward(lightning_intensity, 0.0, 0.05)
	
	# 기본 미세 떨림
	var base_flicker = 1.0 + sin(_flicker_timer * 50.0) * 0.03 * randf()
	
	# 충격에 의한 강한 떨림 감쇄
	_shake_intensity = move_toward(_shake_intensity, 0.0, 0.05)
	var impact_flicker = 1.0
	if _shake_intensity > 0.01:
		impact_flicker = 1.0 + (randf() * 2.0 - 1.0) * _shake_intensity
		if randf() < _shake_intensity * 0.5: # 가끔 아예 꺼짐
			impact_flicker = 0.2
			
	current_flicker = base_flicker * impact_flicker
	
	# 2. 엔트리 클리어
	_entries.clear()

static func add_impact_shake(amount: float) -> void:
	_shake_intensity = clampf(_shake_intensity + amount, 0.0, 1.0)

func clear_entries() -> void:
	_entries.clear()

func add_entry(depth: float, rect: Rect2, tex: Texture2D, fade: float = 1.0, mat: Material = null, color: Color = Color.WHITE, flip_h: bool = false, light_h: float = 0.0, ground_y: float = -1.0, is_jumping: bool = false, jump_t: float = 0.0, sway: float = 0.0, sway_offset: float = 0.0) -> void:
	if tex == null: return

	# 1. 실루엣 그림자 추가
	if light_h > 0.1:
		var gy = ground_y if ground_y > 0 else rect.end.y
		var dz := CAMERA_DEPTH / maxf(depth, 0.001)
		var dz_head := dz + 6.0 
		var depth_head := CAMERA_DEPTH / dz_head
		var ground_y_range := ROAD_BOTTOM_Y - HORIZON_Y
		var shadow_h := (depth - depth_head) * ground_y_range
		
		var s_rect := Rect2(rect.position.x, gy - shadow_h, rect.size.x, shadow_h)
		var center_dist := (rect.get_center().x - 640.0) / 640.0
		var skew_x := -center_dist * 1.5
		
		_entries.append({
			"depth": depth - 0.00001,
			"rect": s_rect,
			"tex": tex,
			"fade": fade * clampf(light_h * 1.5, 0.0, 0.7),
			"mat": _shadow_mat,
			"color": Color.BLACK,
			"flip_h": flip_h,
			"skew": skew_x,
			"anchor_bottom": true,
			"light_h": 0.0,
			"light_skew": 0.0
		})

	# 2. 메인 오브젝트 추가
	var screen_cx := SCREEN_W * 0.5
	var obj_cx := rect.position.x + rect.size.x * 0.5
	var skew_light := (obj_cx - screen_cx) / (SCREEN_W * 0.5)

	_entries.append({
		"depth": depth,
		"rect": rect,
		"tex": tex,
		"fade": fade,
		"mat": mat,
		"color": color,
		"flip_h": flip_h,
		"skew": 0.0,
		"anchor_bottom": false,
		"light_h": light_h,
		"light_skew": skew_light,
		"is_jumping": is_jumping,
		"jump_t": jump_t,
		"sway": sway,
		"sway_offset": sway_offset
	})

func render_all() -> void:
	# 먼 것부터 가까운 것 순서대로 정렬 (depth 작은 것이 더 멀다)
	_entries.sort_custom(func(a, b): return a.depth < b.depth)
	
	while _sprite_pool.size() < _entries.size():
		var spr := Sprite2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(spr)
		_sprite_pool.append(spr)
		
	for i in range(_sprite_pool.size()):
		var spr := _sprite_pool[i]
		if i < _entries.size():
			var e = _entries[i]
			spr.visible = true
			spr.texture = e.tex
			spr.flip_h = e.flip_h
			spr.skew = e.skew
			spr.material = e.mat
			
			if e.mat is ShaderMaterial and e.mat.shader == _get_headlight_shader():
				e.mat.set_shader_parameter("light_height", e.light_h)
				e.mat.set_shader_parameter("light_skew", e.light_skew)
				# 전역 Flicker 및 Lightning 적용
				e.mat.set_shader_parameter("flicker", current_flicker)
				e.mat.set_shader_parameter("lightning", lightning_intensity)
				e.mat.set_shader_parameter("sway", e.get("sway", 0.0))
				e.mat.set_shader_parameter("sway_offset", e.get("sway_offset", 0.0))
			
			if e.mat == _shadow_mat:
				e.mat.set_shader_parameter("lightning", lightning_intensity)
			
			var c = e.color
			c.a *= e.fade
			spr.modulate = c
			
			if e.anchor_bottom:
				# 그림자: 하단 중앙 앵커 (발 위치 고정)
				spr.centered = true
				spr.offset = Vector2(0, -e.tex.get_height() * 0.5)
				# 앵커 지점은 발바닥 중앙 (gy)
				spr.position = Vector2(e.rect.get_center().x, e.rect.end.y)
				spr.scale = e.rect.size / e.tex.get_size()
			else:
				# 일반 오브젝트: 상단 좌측 앵커 (기존 방식)
				spr.centered = false
				spr.offset = Vector2.ZERO
				spr.position = e.rect.position
				spr.scale = e.rect.size / e.tex.get_size()
		else:
			spr.visible = false
