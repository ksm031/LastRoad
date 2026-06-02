extends Node2D
class_name LastRoadJiwon
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 스폰 튜닝 ─────────
var SPACING_Z      := 35.0
var seed_offset    := 0
const VISIBLE_DZ_MIN := 0.38
const VISIBLE_DZ_MAX := 85.0
const WZ_BASE_OFFSET := 20.0
const WZ_MAX_JITTER  := 10.0

# ── 충돌 튜닝 ─────────
const HIT_DZ         := 0.45
const HIT_COOLDOWN_Z := 5.0

const WATCHER_BASE_H := 450.0

var scroll_z : float = 0.0
var cam_x    : float = 0.0
var hill_px  : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var _headlight_range : float = 1.0

var _texture   : Texture2D
var _idle_textures: Array[Texture2D] = []
var _down_textures: Array[Texture2D] = []
var _anim_time: float = 0.0

var _hit_info  : Dictionary = {}
var _light_pool: LightMaterialPool
var billboard_mgr: BillboardManager
const POOL_SIZE := 4  # 딱 한 명만 스폰되므로 풀 사이즈 축소

var target_k: int = -1

func _ready() -> void:
	pass

func load_assets() -> void:
	if not _idle_textures.is_empty(): return
	
	# idle: injured 이미지를 기본(idle)으로 사용
	var t := BillboardManager.load_with_normal("res://Asset/Image/Character/jiwon_injured.png")
	if t:
		_idle_textures.append(t)
	
	# down: 충돌 시 쓰러지는 3프레임 연출용 이미지 (1~3)
	for i in range(1, 4):
		var d := BillboardManager.load_with_normal("res://Asset/Image/Character/jiwon_down_%02d.png" % i)
		if d:
			_down_textures.append(d)
			
	if _idle_textures.size() > 0:
		_texture = _idle_textures[0]
	
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

const _AMBIENT_NORMAL := Color(0.28, 0.25, 0.32, 1.0)
const _AMBIENT_DARK   := Color(0.24, 0.22, 0.26, 1.0)

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

func prepare_spawn(course_length_z: float, sanity_ratio: float) -> void:
	# GDD: 정신력이 40% 이하일 때만 환영(지원) 등장 가능
	if sanity_ratio > 0.4:
		target_k = -1
		return
		
	# 정신력이 낮을수록 등장 확률 증가 (최대 70%)
	var spawn_chance := lerpf(0.7, 0.2, (sanity_ratio - 0.0) / 0.4)
	var r := BillboardManager.get_rand01(seed_offset + 999)
	if r > spawn_chance:
		target_k = -1
		return
		
	var max_k = int(course_length_z / SPACING_Z) - 5
	if max_k < 10:
		target_k = -1
		return
		
	# 10번째 인덱스부터 끝쪽 사이 어딘가에 딱 1번만 등장
	var rand_offset = int(BillboardManager.get_rand01(seed_offset + 777) * float(max_k - 10))
	target_k = 10 + rand_offset

func get_spawned_info() -> Dictionary:
	if target_k == -1: return {}
	return _watcher_at_k(target_k)

func _process(delta: float) -> void:
	if _idle_textures.size() > 0:
		_anim_time += delta
		var frame_idx = int(floor(_anim_time * 6.0)) % _idle_textures.size()
		_texture = _idle_textures[frame_idx]

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float, p_headlight_range: float = 1.0) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_headlight_range = p_headlight_range
	_update_billboards()

const OBJECT_WIDTH     := 0.9

func check_collision(vehicle: LastRoadVehicle) -> bool:
	_prune_hits()
	if _texture == null:
		return false
	
	var hit := false
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	
	var threshold := (vehicle.COLLISION_WIDTH + OBJECT_WIDTH) * 0.5
	
	for k in range(k0, k1 + 1):
		var o := _watcher_at_k(k)
		if o.is_empty():
			continue
		
		if abs(float(o["lane"]) - vehicle.cam_x) > threshold:
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		if dz < 0.0 or dz > HIT_DZ:
			continue
		if _is_hit_active(k):
			continue
		
		_hit_info[k] = {
			"until_z": wz + HIT_COOLDOWN_Z,
			"hit_time": _anim_time,
			"is_hallucination": bool(o["is_hallucination"]) # 충돌 정보에 환영 여부 저장
		}
		
		hit = true
		break
	return hit

func is_hit_hallucination(k: int) -> bool:
	if not _hit_info.has(k): return false
	return bool(_hit_info[k].get("is_hallucination", false))

func _is_hit_active(k: int) -> bool:
	if not _hit_info.has(k):
		return false
	var hit_time = float(_hit_info[k]["hit_time"])
	return (_anim_time - hit_time) < 0.3

func _prune_hits() -> void:
	var keys := _hit_info.keys()
	for k in keys:
		var hit_time = float(_hit_info[k]["hit_time"])
		if (_anim_time - hit_time) >= 0.3 and float(_hit_info[k]["until_z"]) <= scroll_z:
			_hit_info.erase(k)

func _watcher_at_k(k: int) -> Dictionary:
	# target_k 일 때만 스폰
	if k != target_k or target_k == -1:
		return {}
		
	var lane := int(floor(BillboardManager.get_rand01(k * 13331 + 53, seed_offset) * 3.0)) - 1
	var wz := float(k) * SPACING_Z + 20.0 + BillboardManager.get_rand01(k * 13331 + 101, seed_offset) * 10.0
	
	# 지원(Jiwon)은 현재 시스템상 무조건 환영으로 간주 (정신력 낮을 때만 나오므로)
	return { "k": k, "lane": lane, "wz": wz, "is_hallucination": true }

func _update_billboards() -> void:
	if _texture == null or billboard_mgr == null:
		return
	
	var kr := BillboardManager.visible_k_range(scroll_z, SPACING_Z, VISIBLE_DZ_MIN, VISIBLE_DZ_MAX, WZ_BASE_OFFSET, WZ_MAX_JITTER)
	
	var entries: Array = []
	for k in range(kr.x, kr.y + 1):
		var o := _watcher_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		
		var is_hit = _is_hit_active(k)
		if not is_hit and (dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX):
			continue
			
		var render_dz = maxf(dz, 0.15)
		
		var proj := BillboardManager.calculate_projection(render_dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth

		var lane := int(o["lane"])
		var lane_off: float = float(lane) * float(proj.road_hw) * 0.42
		var x: float = float(proj.road_cx) + lane_off
		
		var tex_to_use := _texture
		if is_hit and _down_textures.size() > 0:
			var hit_time = float(_hit_info[k]["hit_time"])
			var elapsed = _anim_time - hit_time
			# 3프레임을 0.3초 안에 빠르게 재생 (0.1초/프레임)
			var frame = clampi(int(floor(elapsed / 0.1)), 0, _down_textures.size() - 1)
			tex_to_use = _down_textures[frame]
		
		var base_scale := 1.0
		if tex_to_use != null:
			base_scale = WATCHER_BASE_H / maxf(float(tex_to_use.get_height()), 1.0)
			
		var h := depth * float(tex_to_use.get_height()) * base_scale
		var w := depth * float(tex_to_use.get_width()) * base_scale
		
		var hit_y_offset := 0.0
		if is_hit:
			var hit_time = float(_hit_info[k]["hit_time"])
			var elapsed = _anim_time - hit_time
			hit_y_offset = minf(elapsed * 45.0, 15.0)

		var fade: float = 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var light_h: float = proj.light_h

		# 지원은 무조건 환영이므로 반투명
		var color := Color.WHITE
		color.a = 0.35

		entries.append({
			"depth": depth,
			"rect": Rect2(x - w * 0.5, float(proj.ground_y) + hit_y_offset - h * 0.78, w, h),
			"fade": fade,
			"light_h": light_h,
			"ground_y": float(proj.ground_y),
			"tex": tex_to_use,
			"color": color
		})

	if _light_pool:
		_light_pool.reset()
		
	for i in range(entries.size()):
		var e = entries[i]
		var mat := _light_pool.get_material(e.light_h) if _light_pool else null
		billboard_mgr.add_entry(e.depth, e.rect, e.tex, e.fade, mat, e.color, false, float(e.light_h), float(e.ground_y))


