extends Node2D
class_name LastRoadJumpers

# ── 상수 (road_renderer / watcher_system과 동일한 투영 모델) ─────
const CAMERA_DEPTH   := 0.84
const ROAD_HW_MAX    := 650.0
const ROAD_BOTTOM_Y  := 500.0
const HORIZON_Y_BASE := 300.0

# ── 스폰 튜닝 ────────────────────────────────────────────────
const SPACING_Z      := 80.0    # 점퍼 간 최소 거리
const SPAWN_CHANCE   := 0.10    # 스폰 확률 (와쳐보다 낮음)
const VISIBLE_DZ_MIN := 0.05
const VISIBLE_DZ_MAX := 85.0

# ── 충돌 튜닝 ────────────────────────────────────────────────
const HIT_DZ         := 0.45
const HIT_COOLDOWN_Z := 5.0

# ── 점퍼 스프라이트 높이 (depth=1 기준 픽셀) ─────────────────
const JUMPER_BASE_H  := 500.0

# ── 애니메이션 ───────────────────────────────────────────────
# idle: 1-2-3-4-3-2-1 (인덱스 기준 0-1-2-3-2-1, 핑퐁)
const IDLE_SEQUENCE  := [0, 1, 2, 3, 2, 1]
const IDLE_FPS       := 6.0

# jump: 1~6 순서 재생 후 hold 전환
const JUMP_ANIM_FPS  := 12.0
const JUMP_FRAMES    := 6

# ── 셰이더 ──────────────────────────────────────────────────
const HEADLIGHT_SHADER := """
shader_type canvas_item;
uniform float light_height : hint_range(0.0, 1.0) = 0.0;
uniform vec4 light_color : source_color = vec4(0.91, 0.78, 0.48, 1.0);
uniform vec4 ambient_color : source_color = vec4(0.42, 0.42, 0.42, 1.0);
uniform bool is_jumping = false;
uniform float jump_t : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float edge = 1.0 - light_height;
	float lit = smoothstep(edge - 0.35, edge, UV.y);
	if (is_jumping) {
		float jump_unlit = smoothstep(jump_t - 0.15, jump_t, UV.y);
		lit = min(lit, jump_unlit);
	}
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

var _idle_textures : Array[Texture2D] = []
var _jump_textures : Array[Texture2D] = []
var _hold_texture  : Texture2D

var _anim_time : float = 0.0
# k -> { until_z: float, hit_time: float, jump_done: bool }
var _hit_info  : Dictionary = {}

var _shader    : Shader
var _sprites   : Array[Sprite2D] = []
const POOL_SIZE := 8

# 점프 애니메이션 완료 시 보닛 탑승 알림
signal jumper_boarded

# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	for i in range(1, 5):
		var t = load("res://Asset/Image/Character/jumper_idle_%02d.png" % i) as Texture2D
		if t:
			_idle_textures.append(t)

	for i in range(1, 7):
		var t = load("res://Asset/Image/Character/jumper_jump_%02d.png" % i) as Texture2D
		if t:
			_jump_textures.append(t)

	_hold_texture = load("res://Asset/Image/Character/jumper_hold_01.png") as Texture2D

	_shader = Shader.new()
	_shader.code = HEADLIGHT_SHADER

	for i in POOL_SIZE:
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.visible = false

		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("light_height", 0.0)
		mat.set_shader_parameter("light_color", Color(0.91, 0.78, 0.48, 1.0))
		mat.set_shader_parameter("ambient_color", Color(0.42, 0.42, 0.42, 1.0))
		spr.material = mat

		add_child(spr)
		_sprites.append(spr)

func _process(delta: float) -> void:
	_anim_time += delta

	# 점프 애니메이션 완료 감지 → 보닛 탑승 신호
	var jump_anim_duration := float(JUMP_FRAMES) / JUMP_ANIM_FPS
	for k in _hit_info.keys():
		var info = _hit_info[k]
		if bool(info["jump_done"]):
			continue
		var elapsed := _anim_time - float(info["hit_time"])
		if elapsed >= jump_anim_duration:
			info["jump_done"] = true
			_hit_info[k] = info
			jumper_boarded.emit()

# ── 외부 업데이트 ────────────────────────────────────────────
func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_update_sprites()

# ── 충돌 체크 ────────────────────────────────────────────────
func check_collision(vehicle: LastRoadVehicle) -> bool:
	_prune_hits()
	var hit := false
	var lane := clampi(int(round(vehicle.cam_x)), -1, 1)
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	for k in range(k0, k1 + 1):
		var o := _jumper_at_k(k)
		if o.is_empty():
			continue
		if int(o["lane"]) != lane:
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < 0.0 or dz > HIT_DZ:
			continue
		if _hit_info.has(k):
			continue

		_hit_info[k] = {
			"until_z": wz + HIT_COOLDOWN_Z,
			"hit_time": _anim_time,
			"jump_done": false
		}
		hit = true
		break
	return hit

func _is_jumping(k: int) -> bool:
	if not _hit_info.has(k):
		return false
	return not bool(_hit_info[k]["jump_done"])

func _prune_hits() -> void:
	var keys := _hit_info.keys()
	for k in keys:
		if bool(_hit_info[k]["jump_done"]) and float(_hit_info[k]["until_z"]) <= scroll_z:
			_hit_info.erase(k)

# ── 결정적 점퍼 생성 (와쳐와 다른 시드) ──────────────────────
func _jumper_at_k(k: int) -> Dictionary:
	if k == 1:
		return { "k": k, "lane": 0, "wz": 15.0 }
	var r := _rand01(k * 17239 + 11)
	if r > SPAWN_CHANCE:
		return {}
	var lane := int(floor(_rand01(k * 17239 + 67) * 3.0)) - 1
	var wz := float(k) * SPACING_Z + 15.0 + _rand01(k * 17239 + 113) * 15.0
	return { "k": k, "lane": lane, "wz": wz }


func _rand01(seed_val: int) -> float:
	var h := int((seed_val * 1103515245 + 12345) & 0x7fffffff)
	return float(h & 0xFFFF) / 65535.0

func _curve_at_depth(depth: float) -> float:
	var n := _curve_x.size()
	if n <= 1:
		return 0.0
	var idx := clampi(int(round((1.0 - depth) * float(n - 1))), 0, n - 1)
	return _curve_x[idx]

func _z_to_light_height(depth: float) -> float:
	if depth < 0.10:
		return 0.0
	var t := clampf((depth - 0.10) / 0.90, 0.0, 1.0)
	return sqrt(t)

func _get_idle_texture() -> Texture2D:
	if _idle_textures.is_empty():
		return null
	var frame_idx := int(floor(_anim_time * IDLE_FPS)) % IDLE_SEQUENCE.size()
	return _idle_textures[IDLE_SEQUENCE[frame_idx]]

# ── 스프라이트 업데이트 ──────────────────────────────────────
func _update_sprites() -> void:
	var hy := HORIZON_Y_BASE + hill_px
	var entries : Array = []
	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))

	for k in range(k_min, k_max + 1):
		var o := _jumper_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z

		var is_jumping := _is_jumping(k)
		var jump_done := _hit_info.has(k) and bool(_hit_info[k]["jump_done"])

		# 점프 완료 → 보닛에 탑승, 도로 렌더링 제거
		if jump_done:
			continue

		if not is_jumping and (dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX):
			continue

		var render_dz := dz
		if is_jumping and dz < 0.84:
			render_dz = 0.84

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

		# 텍스처 결정: 점프 애니 > idle
		var tex_to_use : Texture2D
		var scale_mult : float = 1.0
		if is_jumping:
			if not _jump_textures.is_empty():
				var hit_time := float(_hit_info[k]["hit_time"])
				var elapsed := _anim_time - hit_time
				var frame := clampi(int(floor(elapsed * JUMP_ANIM_FPS)), 0, _jump_textures.size() - 1)
				tex_to_use = _jump_textures[frame]
				
				# 점프 동안 점점 커지도록 스케일 계수 설정 (1.0 -> 1.6)
				var jump_duration := float(JUMP_FRAMES) / JUMP_ANIM_FPS
				var t := clampf(elapsed / jump_duration, 0.0, 1.0)
				scale_mult = lerpf(1.0, 1.6, t)

				# 자연스럽게 화면 중앙(640.0)으로 정렬
				x = lerpf(x, 640.0, t)

				# 점프 4, 5, 6 프레임 등에서 자연스럽게 높이를 조절하기 위해 아크를 더합니다.
				ground_y -= sin(t * PI) * 110.0 * depth
			else:
				tex_to_use = _hold_texture
		else:
			tex_to_use = _get_idle_texture()


		if tex_to_use == null:
			continue

		var h := depth * JUMPER_BASE_H * scale_mult
		var w := h * float(tex_to_use.get_width()) / maxf(float(tex_to_use.get_height()), 1.0)
		var fade := 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var light_h := _z_to_light_height(depth)

		var jump_t: float = 0.0
		if is_jumping:
			var hit_time := float(_hit_info[k]["hit_time"])
			var elapsed := _anim_time - hit_time
			var jump_duration := float(JUMP_FRAMES) / JUMP_ANIM_FPS
			jump_t = clampf(elapsed / jump_duration, 0.0, 1.0) * 1.2


		entries.append({
			"depth": depth, "x": x, "y": ground_y,
			"w": w, "h": h, "fade": fade,
			"light_h": light_h, "tex": tex_to_use,
			"is_jumping": is_jumping,
			"jump_t": jump_t
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
				mat.set_shader_parameter("is_jumping", bool(e["is_jumping"]))
				mat.set_shader_parameter("jump_t", float(e["jump_t"]))
		else:
			_sprites[i].visible = false
