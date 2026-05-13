extends Node2D
class_name LastRoadWatchers
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 상수 (BillboardManager 투영 모델 사용) ─────

# ── 스폰 튜닝 (route_type에 따라 game_world에서 조정) ─────────
var SPACING_Z      := 35.0    # 실제값은 spawn_config.gd에서 주입
var SPAWN_CHANCE   := 0.42
var seed_offset    := 0       # 스테이지마다 다른 배치를 위한 시드 오프셋
const VISIBLE_DZ_MIN := -1.0
const VISIBLE_DZ_MAX := 85.0

# ── 충돌 튜닝 ────────────────────────────────────────────────
const HIT_DZ         := 0.45
const HIT_COOLDOWN_Z := 5.0

# ── 와쳐 스프라이트 높이 (depth=1 기준 픽셀) ────────────────────
# 공백이 생긴 새로운 이미지에 맞춰 스케일업 (기존 440 -> 550)
const WATCHER_BASE_H := 550.0


# ── 상태 ──────────────────────────────────────────────────────
var scroll_z : float = 0.0
var cam_x    : float = 0.0
var hill_px  : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var _headlight_range : float = 1.0

var _texture   : Texture2D
var _idle_textures: Array[Texture2D] = []
var _down_textures: Array[Texture2D] = []
var _anim_time: float = 0.0

var _hit_info  : Dictionary = {} # key(int) -> { until_z: float, hit_time: float }
var _light_pool: LightMaterialPool
var billboard_mgr: BillboardManager
const POOL_SIZE := 20
var jiwon_info: Dictionary = {}

func _ready() -> void:
	pass

func load_assets() -> void:
	if not _idle_textures.is_empty(): return
	
	# idle: watcher_idle_01 ~ 04
	for i in range(1, 5):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/watcher_idle_%02d.png" % i)
		if t:
			_idle_textures.append(t)
	
	# down: watcher_down_01 ~ 06
	for i in range(1, 7):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/watcher_down_%02d.png" % i)
		if t:
			_down_textures.append(t)
			
	if _idle_textures.size() > 0:
		_texture = _idle_textures[0]
	
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

const _AMBIENT_NORMAL := Color(0.28, 0.25, 0.32, 1.0)
const _AMBIENT_DARK   := Color(0.05, 0.04, 0.07, 1.0)  # 어두운 루트: 헤드라이트만 광원

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

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

const OBJECT_WIDTH     := 0.9     # 와쳐 자체 너비

func check_collision(vehicle: LastRoadVehicle) -> bool:
	_prune_hits()
	if _texture == null:
		return false
	
	var hit := false
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	
	# 통합 충돌 범위 계산: (차폭 + 오브젝트폭) / 2
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
	var r := BillboardManager.get_rand01(k * 13331 + 7, seed_offset)
	if r > SPAWN_CHANCE:
		return {}
	var lane := int(floor(BillboardManager.get_rand01(k * 13331 + 53, seed_offset) * 3.0)) - 1
	var wz := float(k) * SPACING_Z + 20.0 + BillboardManager.get_rand01(k * 13331 + 101, seed_offset) * 10.0
	
	if jiwon_info.has("wz"):
		var j_wz: float = jiwon_info["wz"]
		var j_lane: int = jiwon_info["lane"]
		
		# 1. 안전 간격 유지 (지원 기준 앞뒤 40m 내에는 스폰 금지)
		if absf(wz - j_wz) < 40.0:
			return {}
			
		# 2. 제일 가까운 앞쪽 적 캐릭터가 같은 차선에 없도록 강제 변경
		if wz > j_wz and wz < j_wz + 120.0:
			if lane == j_lane:
				lane = j_lane + 1
				if lane > 1: lane = -1
				
	return { "k": k, "lane": lane, "wz": wz }


func _update_billboards() -> void:
	if _texture == null or billboard_mgr == null:
		return
	
	var k_min := int(floor((scroll_z + VISIBLE_DZ_MIN) / SPACING_Z))
	var k_max := int(ceil((scroll_z + VISIBLE_DZ_MAX) / SPACING_Z))
	
	var entries: Array = []
	for k in range(k_min, k_max + 1):
		var o := _watcher_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		
		var is_hit = _is_hit_active(k)
		if not is_hit and (dz <= -1.0 or dz > VISIBLE_DZ_MAX):
			continue
			
		var render_dz = dz
		if is_hit and dz < 0.84:
			render_dz = 0.84
		
		var proj := BillboardManager.calculate_projection(render_dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth

		var lane := int(o["lane"])
		var lane_off: float = float(lane) * float(proj.road_hw) * 0.42
		var x: float = float(proj.road_cx) + lane_off
		
		var tex_to_use := _texture
		if is_hit and _down_textures.size() > 0:
			var hit_time = float(_hit_info[k]["hit_time"])
			var elapsed = _anim_time - hit_time
			var frame = int(floor(elapsed * 24.0))
			if frame >= _down_textures.size():
				frame = _down_textures.size() - 1
			tex_to_use = _down_textures[frame]
		
		var h := depth * WATCHER_BASE_H
		var hit_y_offset := 0.0
		if is_hit:
			h *= 1.5
			var hit_time = float(_hit_info[k]["hit_time"])
			var elapsed = _anim_time - hit_time
			hit_y_offset = minf(elapsed * 45.0, 15.0)

		var w: float = h * float(tex_to_use.get_width()) / maxf(float(tex_to_use.get_height()), 1.0)
		var fade: float = 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var light_h: float = proj.light_h

		entries.append({
			"depth": depth,
			"rect": Rect2(x - w * 0.5, float(proj.ground_y) + hit_y_offset - h * 0.78, w, h),
			"fade": fade,
			"light_h": light_h,
			"ground_y": float(proj.ground_y),
			"tex": tex_to_use
		})

	if _light_pool:
		_light_pool.reset()
		
	for i in range(entries.size()):
		var e = entries[i]
		var mat := _light_pool.get_material(e.light_h) if _light_pool else null
		billboard_mgr.add_entry(e.depth, e.rect, e.tex, e.fade, mat, Color.WHITE, false, float(e.light_h), float(e.ground_y))

