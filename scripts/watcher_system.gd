extends Node2D
class_name LastRoadWatchers

# ── 상수 (road_renderer / obstacle_system과 동일한 투영 모델) ─────
const CAMERA_DEPTH   := 0.84
const ROAD_HW_MAX    := 650.0
const ROAD_BOTTOM_Y  := 500.0
const HORIZON_Y_BASE := 300.0

# ── 스폰 튜닝 ────────────────────────────────────────────────
const SPACING_Z      := 55.0    # 와쳐 간 최소 거리 (세계 단위)
const SPAWN_CHANCE   := 0.18    # k마다 와쳐가 존재할 확률
const VISIBLE_DZ_MIN := 0.05
const VISIBLE_DZ_MAX := 85.0

# ── 충돌 튜닝 ────────────────────────────────────────────────
const HIT_DZ         := 0.45
const HIT_COOLDOWN_Z := 5.0

# ── 와쳐 스프라이트 높이 (depth=1 기준 픽셀) ────────────────────
# 공백이 생긴 새로운 이미지에 맞춰 스케일업 (기존 440 -> 550)
const WATCHER_BASE_H := 550.0

# ── 헤드라이트 셰이더 (GDD 03-driving.md 기준) ──────────────────
const HEADLIGHT_SHADER := """
shader_type canvas_item;

uniform float light_height : hint_range(0.0, 1.0) = 0.0;
uniform vec4 light_color : source_color = vec4(0.91, 0.78, 0.48, 1.0);
uniform vec4 ambient_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float edge = 1.0 - light_height;
    float lit = smoothstep(edge - 0.35, edge, UV.y);
    vec4 dark = tex * ambient_color;
    vec4 bright = tex * light_color;
    COLOR = mix(dark, bright, lit);
    COLOR.a = tex.a;
}
"""

# ── 상태 ──────────────────────────────────────────────────────
var scroll_z : float = 0.0
var cam_x    : float = 0.0
var hill_px  : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()

var _texture   : Texture2D
var _idle_textures: Array[Texture2D] = []
var _down_textures: Array[Texture2D] = []
var _anim_time: float = 0.0

var _shader    : Shader
var _hit_info  : Dictionary = {} # key(int) -> { until_z: float, hit_time: float }

# 스프라이트 풀 (재활용)
var _sprites   : Array[Sprite2D] = []
const POOL_SIZE := 12

func _ready() -> void:
	for i in range(1, 5):
		var t = load("res://Asset/Image/Character/watcher_idle_%02d.png" % i) as Texture2D
		if t:
			_idle_textures.append(t)
			
	for i in range(1, 7):
		var t = load("res://Asset/Image/Character/watcher_down_%02d.png" % i) as Texture2D
		if t:
			_down_textures.append(t)
	
	if not _idle_textures.is_empty():
		_texture = _idle_textures[0]
	
	# 셰이더 컴파일
	_shader = Shader.new()
	_shader.code = HEADLIGHT_SHADER
	
	# 스프라이트 풀 생성
	for i in POOL_SIZE:
		var spr := Sprite2D.new()
		spr.texture = _texture
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.visible = false
		
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("light_height", 0.0)
		mat.set_shader_parameter("light_color", Color(0.91, 0.78, 0.48, 1.0))
		mat.set_shader_parameter("ambient_color", Color(0.06, 0.06, 0.08, 1.0))
		spr.material = mat
		
		add_child(spr)
		_sprites.append(spr)

func _process(delta: float) -> void:
	if _idle_textures.size() > 0:
		_anim_time += delta
		var frame_idx = int(floor(_anim_time * 6.0)) % _idle_textures.size() # 6 FPS
		_texture = _idle_textures[frame_idx]
		# 개별 스프라이트 텍스처는 _update_sprites에서 할당하므로 여기서 일괄 할당 제거

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_update_sprites()

# ── 충돌 체크 ────────────────────────────────────────────────
func check_collision(vehicle: LastRoadVehicle) -> bool:
	_prune_hits()
	if _texture == null:
		return false
	
	var hit := false
	var lane := clampi(int(round(vehicle.cam_x)), -1, 1)
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	for k in range(k0, k1 + 1):
		var o := _watcher_at_k(k)
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
		
		_hit_info[k] = {
			"until_z": wz + HIT_COOLDOWN_Z,
			"hit_time": _anim_time
		}
		
		# 충돌 효과는 game_world.gd에서 처리 (apply_watcher_hit + 정신력 감소)
		hit = true
		break
	return hit

func _is_hit_active(k: int) -> bool:
	if not _hit_info.has(k):
		return false
	# 시간 기반으로 0.4초 동안은 무조건 화면에 남도록 함
	var hit_time = float(_hit_info[k]["hit_time"])
	return (_anim_time - hit_time) < 0.4

func _prune_hits() -> void:
	var keys := _hit_info.keys()
	for k in keys:
		var hit_time = float(_hit_info[k]["hit_time"])
		if (_anim_time - hit_time) >= 0.4 and float(_hit_info[k]["until_z"]) <= scroll_z:
			_hit_info.erase(k)

# ── 결정적 와쳐 생성 ────────────────────────────────────────
func _watcher_at_k(k: int) -> Dictionary:
	var r := _rand01(k * 13331 + 7)
	if r > SPAWN_CHANCE:
		return {}
	var lane := int(floor(_rand01(k * 13331 + 53) * 3.0)) - 1  # -1, 0, 1
	var wz := float(k) * SPACING_Z + 20.0 + _rand01(k * 13331 + 101) * 10.0
	return {
		"k": k,
		"lane": lane,
		"wz": wz,
	}

func _rand01(seed_val: int) -> float:
	var h := int((seed_val * 1103515245 + 12345) & 0x7fffffff)
	return float(h & 0xFFFF) / 65535.0

func _curve_at_depth(depth: float) -> float:
	var n := _curve_x.size()
	if n <= 1:
		return 0.0
	var idx := clampi(int(round((1.0 - depth) * float(n - 1))), 0, n - 1)
	return _curve_x[idx]

# ── z → light_height 매핑 (GDD 기준) ────────────────────────
func _z_to_light_height(depth: float) -> float:
	if depth < 0.10:
		return 0.0
	var t := clampf((depth - 0.10) / 0.90, 0.0, 1.0)
	return sqrt(t)

# ── 스프라이트 업데이트 ──────────────────────────────────────
func _update_sprites() -> void:
	if _texture == null:
		for spr in _sprites:
			spr.visible = false
		return
	
	var hy := HORIZON_Y_BASE + hill_px
	var entries : Array = []
	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))
	
	for k in range(k_min, k_max + 1):
		var o := _watcher_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		
		# 치인 상태면 무조건 렌더링에 포함하고, dz를 화면 하단에 고정
		var is_hit = _is_hit_active(k)
		if not is_hit and (dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX):
			continue
			
		var render_dz = dz
		if is_hit and dz < 0.84:
			render_dz = 0.84 # 카메라 바로 앞(화면 하단)에 드래그되도록 고정
		
		var depth: float = CAMERA_DEPTH / render_dz
		if depth < 0.02:
			continue
		
		var road_hw := depth * ROAD_HW_MAX
		var cx_curve := _curve_at_depth(depth)
		var road_cx := 640.0 + cx_curve - cam_x * depth * 320.0
		var ground_y := hy + depth * (ROAD_BOTTOM_Y - hy)
		
		var lane := int(o["lane"])
		var lane_off := float(lane) * road_hw * 0.42
		var x := road_cx + lane_off
		
		# 텍스처 결정 로직 (충돌 다운 애니메이션 우선)
		var tex_to_use := _texture
		if _is_hit_active(k) and _down_textures.size() > 0:
			var hit_time = float(_hit_info[k]["hit_time"])
			var elapsed = _anim_time - hit_time
			# 치고 지나가는 시간이 매우 짧으므로 24 FPS 정도로 빠르게 재생
			var frame = int(floor(elapsed * 24.0))
			if frame >= _down_textures.size():
				frame = _down_textures.size() - 1 # 마지막 프레임 유지
			tex_to_use = _down_textures[frame]
		
		var h := depth * WATCHER_BASE_H
		var w := h * float(tex_to_use.get_width()) / maxf(float(tex_to_use.get_height()), 1.0)
		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var light_h := _z_to_light_height(depth)
		
		entries.append({
			"depth": depth,
			"x": x,
			"y": ground_y,
			"w": w,
			"h": h,
			"fade": fade,
			"light_h": light_h,
			"tex": tex_to_use
		})
	
	entries.sort_custom(func(a, b): return a.depth < b.depth)
	
	for i in POOL_SIZE:
		if i < entries.size():
			var e = entries[i]
			var spr := _sprites[i]
			spr.visible = true
			spr.texture = e.tex
			spr.scale = Vector2(e.w / float(e.tex.get_width()), e.h / float(e.tex.get_height()))
			spr.position = Vector2(e.x - e.w * 0.5, e.y - e.h * 0.78)
			spr.modulate.a = e.fade
			spr.z_index = int(e.depth * 100.0)
			
			var mat := spr.material as ShaderMaterial
			if mat:
				mat.set_shader_parameter("light_height", e.light_h)
		else:
			_sprites[i].visible = false
