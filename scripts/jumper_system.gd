extends Node2D
class_name LastRoadJumpers
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 상수 (BillboardManager 투영 모델 사용) ─────
# CAMERA_DEPTH, ROAD_HW_MAX 등은 BillboardManager에 정의됨

# ── 스폰 튜닝 (route_type에 따라 game_world에서 조정) ─────────
var SPACING_Z      := 65.0    # 실제값은 spawn_config.gd에서 주입
var SPAWN_CHANCE   := 0.15
var seed_offset    := 0       # 스테이지마다 다른 배치를 위한 시드 오프셋
const VISIBLE_DZ_MIN := 0.40
const VISIBLE_DZ_MAX := 85.0
const WZ_BASE_OFFSET := 15.0   # _jumper_at_k: k*SPACING_Z + 15 + jitter
const WZ_MAX_JITTER  := 15.0

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




# ── 상태 ──────────────────────────────────────────────────────
var scroll_z : float = 0.0
var cam_x    : float = 0.0
var hill_px  : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var _headlight_range : float = 1.0

var _idle_textures : Array[Texture2D] = []
var _jump_textures : Array[Texture2D] = []
var _hold_texture  : Texture2D

var _anim_time : float = 0.0
# k -> { until_z: float, hit_time: float, jump_done: bool }
var _hit_info  : Dictionary = {}
var _light_pool: LightMaterialPool
var billboard_mgr: BillboardManager
const POOL_SIZE := 15
var jiwon_info: Dictionary = {}
var last_hit_k : int = -999999   # Doc 31 §4: 직전 충돌 인덱스 (즉시 처치 차단용)

# 점프 애니메이션 완료 시 보닛 탑승 알림
signal jumper_boarded

# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	pass

func load_assets() -> void:
	if not _idle_textures.is_empty(): return

	for i in range(1, 5):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/jumper_idle_%02d.png" % i)
		if t:
			_idle_textures.append(t)

	for i in range(1, 7):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/jumper_jump_%02d.png" % i)
		if t:
			_jump_textures.append(t)

	_hold_texture = BillboardManager.load_with_normal("res://Asset/Image/Character/jumper_hold_01.png")
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

const _AMBIENT_NORMAL := Color(0.42, 0.42, 0.42, 1.0)
const _AMBIENT_DARK   := Color(0.25, 0.25, 0.28, 1.0)

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

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
func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float, p_headlight_range: float = 1.0) -> void:
	scroll_z = p_scroll_z
	cam_x = p_lane_x
	_curve_x = p_curve_x
	hill_px = p_hill_px
	_headlight_range = p_headlight_range
	_update_billboards()

const OBJECT_WIDTH     := 0.9     # 점퍼 자체 너비

func check_collision(vehicle: LastRoadVehicle) -> bool:
	_prune_hits()
	var hit := false
	
	var k0 := int(floor(scroll_z / SPACING_Z)) - 1
	var k1 := k0 + 4
	
	# 통합 충돌 범위 계산: (차폭 + 오브젝트폭) / 2
	var threshold := (vehicle.COLLISION_WIDTH + OBJECT_WIDTH) * 0.5
	
	for k in range(k0, k1 + 1):
		var o := _jumper_at_k(k)
		if o.is_empty():
			continue
		
		if abs(float(o["lane"]) - vehicle.cam_x) > threshold:
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
		last_hit_k = k
		hit = true
		break
	return hit

# Doc 31 §4: 고속 즉시 처치 시 호출 — 점프→보드 연출/신호를 막고 즉시 제거.
func kill_hit(k: int) -> void:
	if _hit_info.has(k):
		_hit_info[k]["jump_done"] = true   # _process의 jumper_boarded emit 차단 + 렌더 제외

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
	var r := BillboardManager.get_rand01(k * 17239 + 11, seed_offset)
	if r > SPAWN_CHANCE:
		return {}
	var lane := int(floor(BillboardManager.get_rand01(k * 17239 + 67, seed_offset) * 3.0)) - 1
	var wz := float(k) * SPACING_Z + 15.0 + BillboardManager.get_rand01(k * 17239 + 113, seed_offset) * 15.0
	
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



func _get_idle_texture() -> Texture2D:
	if _idle_textures.is_empty():
		return null
	var frame_idx := int(floor(_anim_time * IDLE_FPS)) % IDLE_SEQUENCE.size()
	return _idle_textures[IDLE_SEQUENCE[frame_idx]]

# ── 스프라이트 업데이트 ──────────────────────────────────────
func _update_billboards() -> void:
	if billboard_mgr == null:
		return
		

	var entries : Array = []
	var kr := BillboardManager.visible_k_range(scroll_z, SPACING_Z, VISIBLE_DZ_MIN, VISIBLE_DZ_MAX, WZ_BASE_OFFSET, WZ_MAX_JITTER)

	for k in range(kr.x, kr.y + 1):
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

		var proj := BillboardManager.calculate_projection(render_dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth

		var lane := int(o["lane"])
		var lane_off: float = float(lane) * float(proj.road_hw) * 0.42
		var x: float = float(proj.road_cx) + lane_off

		var current_ground_y: float = float(proj.ground_y)

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
				current_ground_y -= sin(t * PI) * 110.0 * depth
			else:
				tex_to_use = _hold_texture
		else:
			tex_to_use = _get_idle_texture()


		if tex_to_use == null:
			continue

		var h: float = depth * JUMPER_BASE_H * scale_mult
		var w: float = h * float(tex_to_use.get_width()) / maxf(float(tex_to_use.get_height()), 1.0)
		var fade: float = 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var light_h: float = proj.light_h

		var jump_t: float = 0.0
		if is_jumping:
			var hit_time := float(_hit_info[k]["hit_time"])
			var elapsed := _anim_time - hit_time
			var jump_duration := float(JUMP_FRAMES) / JUMP_ANIM_FPS
			jump_t = clampf(elapsed / jump_duration, 0.0, 1.0) * 1.2


		entries.append({
			"depth": depth, "x": x, "y": current_ground_y,
			"w": w, "h": h, "fade": fade,
			"light_h": light_h, "tex": tex_to_use,
			"is_jumping": is_jumping,
			"jump_t": jump_t
		})

	if _light_pool:
		_light_pool.reset()
		
	for i in range(entries.size()):
		var e = entries[i]
		var mat := _light_pool.get_material(e.light_h, bool(e["is_jumping"]), float(e["jump_t"])) if _light_pool else null
		
		var rect := Rect2(e.x - e.w * 0.5, e.y - e.h * 0.78, e.w, e.h)
		billboard_mgr.add_entry(e.depth, rect, e.tex, e.fade, mat, Color.WHITE, false, float(e.light_h), float(e.y))
