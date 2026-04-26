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
const VISIBLE_DZ_MIN := -2.0
const VISIBLE_DZ_MAX := 85.0

# ── 충돌 튜닝 ────────────────────────────────────────────────
const HIT_DZ         := 0.45
const HIT_COOLDOWN_Z := 5.0

# ── 와쳐 스프라이트 높이 (depth=1 기준 픽셀) ────────────────────
const WATCHER_BASE_H := 440.0

# ── 헤드라이트 셰이더 (GDD 03-driving.md 기준) ──────────────────
const HEADLIGHT_SHADER := """
shader_type canvas_item;

uniform float light_height : hint_range(0.0, 1.0) = 0.0;
uniform vec4 light_color : source_color = vec4(0.91, 0.78, 0.48, 1.0);
uniform vec4 ambient_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // UV.y: 0.0=상단, 1.0=하단
    // 하단(발)부터 light_height만큼 위로 빛이 올라옴
    // 전환 구간을 0.35로 넓혀서 빛이 서서히 올라오는 느낌 강조
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
var _shader    : Shader
var _hit_until_z : Dictionary = {}

# 스프라이트 풀 (재활용)
var _sprites   : Array[Sprite2D] = []
const POOL_SIZE := 12

func _ready() -> void:
	_texture = load("res://Asset/Image/Character/watcher_idle_01.png") as Texture2D
	
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
		_hit_until_z[k] = wz + HIT_COOLDOWN_Z
		# 충돌 효과는 game_world.gd에서 처리 (apply_watcher_hit + 정신력 감소)
		hit = true
		break
	return hit

func _is_hit_active(k: int) -> bool:
	return _hit_until_z.has(k) and float(_hit_until_z[k]) > scroll_z

func _prune_hits() -> void:
	var keys := _hit_until_z.keys()
	for k in keys:
		if float(_hit_until_z[k]) <= scroll_z:
			_hit_until_z.erase(k)

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
	# depth: 0.0 = 매우 멀리 (지평선), 1.0 = 바로 앞
	# 헤드라이트 범위 진입은 depth 약 0.10부터 (더 멀리서부터 빛이 보임)
	if depth < 0.10:
		return 0.0
	# depth 0.10 → 0.0,  depth 1.0 → 1.0
	var t := clampf((depth - 0.10) / 0.90, 0.0, 1.0)
	# sqrt 커브: 멀리서부터 발 아래가 서서히 밝아지고 점진적으로 올라옴
	return sqrt(t)

# ── 스프라이트 업데이트 ──────────────────────────────────────
func _update_sprites() -> void:
	if _texture == null:
		for spr in _sprites:
			spr.visible = false
		return
	
	var hy := HORIZON_Y_BASE + hill_px
	
	# 보이는 와쳐 수집
	var entries : Array = []
	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))
	
	for k in range(k_min, k_max + 1):
		var o := _watcher_at_k(k)
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
		
		# 차선 위치
		var lane := int(o["lane"])
		var lane_off := float(lane) * road_hw * 0.42
		var x := road_cx + lane_off
		
		# 스프라이트 크기 계산
		var h := depth * WATCHER_BASE_H
		var w := h * float(_texture.get_width()) / maxf(float(_texture.get_height()), 1.0)
		
		# 원거리 페이드
		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		
		# 헤드라이트 높이
		var light_h := _z_to_light_height(depth)
		
		entries.append({
			"depth": depth,
			"x": x,
			"y": ground_y,
			"w": w,
			"h": h,
			"fade": fade,
			"light_h": light_h,
		})
	
	# depth 순 정렬 (멀리 있는 것부터 그리기)
	entries.sort_custom(func(a, b): return a.depth < b.depth)
	
	# 스프라이트 풀에 할당
	for i in POOL_SIZE:
		if i < entries.size():
			var e = entries[i]
			var spr := _sprites[i]
			spr.visible = true
			spr.scale = Vector2(e.w / float(_texture.get_width()), e.h / float(_texture.get_height()))
			# 하단 중앙 정렬: centered=false이므로 좌상단이 기준
			# 발이 도로 표면 아래로 약간 묻히도록 0.72 계수 적용 (대시보드에 가려짐)
			spr.position = Vector2(e.x - e.w * 0.5, e.y - e.h * 0.72)
			spr.modulate.a = e.fade
			spr.z_index = int(e.depth * 100.0)
			
			# 셰이더 파라미터 업데이트
			var mat := spr.material as ShaderMaterial
			if mat:
				mat.set_shader_parameter("light_height", e.light_h)
		else:
			_sprites[i].visible = false
