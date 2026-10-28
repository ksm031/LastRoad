extends Node2D
class_name LastRoadMovers
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ══════════════════════════════════════════════════════════════
#  이동형 적 — 러너 · 워커 (Doc 19)
#
#  러너: 갓길 끝에 서 있다가 차를 인식하면(TRIGGER_DZ) 차의 차선을 향해 달려든다.
#        속도가 느릴수록 러너가 정렬할 시간이 길어진다. 막판에 반대로 꺾어 피한다.
#  워커: 도로 좌우 끝을 왕복한다. Y축 접근 없음. 위치를 보고 빈 틈으로 통과한다.
#
#  배치는 시드 기반 결정적(k → 타입·위치·방향). 러너의 '현재 차선'만 런타임 상태.
#  스프라이트는 임시: 러너 = 와쳐 idle 적색 틴트, 워커 = 점퍼 idle 청색 틴트.
# ══════════════════════════════════════════════════════════════

enum MoverType { RUNNER, WALKER }

# ── 스폰 튜닝 (spawn_config.gd에서 주입) ──
var SPACING_Z    := 55.0
var SPAWN_CHANCE := 0.30
var seed_offset  := 0
var stage        := 1
const RUNNER_MIN_STAGE := 2   # Doc 19 스테이지별 조합: 러너 2부터
const WALKER_MIN_STAGE := 4   # 워커 4부터
const WALKER_RATIO     := 0.45  # 둘 다 가능할 때 워커 비율

const VISIBLE_DZ_MIN := 0.40
const VISIBLE_DZ_MAX := 85.0
const WZ_BASE_OFFSET := 25.0
const WZ_MAX_JITTER  := 12.0

# ── 러너 ──
const RUNNER_TRIGGER_DZ   := 26.0   # 이 거리 안으로 오면 달리기 시작
const RUNNER_START_LANE   := 1.55   # 갓길 (도로 밖)
const RUNNER_LANE_SPEED   := 0.75   # 차선 단위/초 (3 m/s 상당)
const RUNNER_BASE_H       := 500.0
# ── 워커 ──
const WALKER_LANE_SPEED   := 0.8    # 차선 단위/초 (4 m/s, 도로 폭 횡단 ~2.5초)
const WALKER_LANE_LIMIT   := 1.0
const WALKER_BASE_H       := 480.0

# ── 충돌 ──
const OBJECT_WIDTH   := 0.9
const HIT_DZ         := 0.45
const HIT_COOLDOWN_Z := 5.0

# ── 상태 ──
var scroll_z : float = 0.0
var cam_x    : float = 0.0
var hill_px  : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var _headlight_range : float = 1.0
var _anim_time : float = 0.0
var _hit_info  : Dictionary = {}   # k -> { until_z, hit_time, type }
var _runner_lane : Dictionary = {} # k -> float (활성화된 러너의 현재 차선)
var jiwon_info : Dictionary = {}
var billboard_mgr: BillboardManager

var _runner_textures : Array[Texture2D] = []
var _runner_down     : Array[Texture2D] = []
var _walker_textures : Array[Texture2D] = []
var _walker_down     : Array[Texture2D] = []
var _light_pool: LightMaterialPool
const POOL_SIZE := 20
const _AMBIENT_NORMAL := Color(0.36, 0.33, 0.36, 1.0)
const _AMBIENT_DARK   := Color(0.24, 0.22, 0.26, 1.0)
const RUNNER_TINT := Color(1.0, 0.70, 0.62, 1.0)
const WALKER_TINT := Color(0.72, 0.80, 1.0, 1.0)

func load_assets() -> void:
	if not _runner_textures.is_empty(): return
	for i in range(1, 5):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/watcher_idle_%02d.png" % i)
		if t: _runner_textures.append(t)
	for i in range(1, 7):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/watcher_down_%02d.png" % i)
		if t: _runner_down.append(t)
	for i in range(1, 5):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/jumper_idle_%02d.png" % i)
		if t: _walker_textures.append(t)
	for i in range(1, 6):
		var t := BillboardManager.load_with_normal("res://Asset/Image/Character/jumper_down_%02d.png" % i)
		if t: _walker_down.append(t)
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

func reset_stage() -> void:
	_hit_info.clear()
	_runner_lane.clear()

func _process(delta: float) -> void:
	_anim_time += delta
	_update_runners(delta)
	_update_billboards()

func update_state(p_scroll_z: float, p_lane_x: float, p_curve_x: PackedFloat32Array, p_hill_px: float, p_headlight_range: float = 1.0) -> void:
	scroll_z = p_scroll_z
	cam_x    = p_lane_x
	_curve_x = p_curve_x
	hill_px  = p_hill_px
	_headlight_range = p_headlight_range

# ── 배치 (결정적) ─────────────────────────────────────────────
func _mover_at_k(k: int) -> Dictionary:
	var wz := float(k) * SPACING_Z + WZ_BASE_OFFSET + BillboardManager.get_rand01(k * 7187 + 31, seed_offset) * WZ_MAX_JITTER
	if BillboardManager.get_rand01(k * 7187 + 3, seed_offset) > SPAWN_CHANCE:
		return {}
	# Doc 30 §5 숨 비트 구역 / §6 정비 직전 보류
	if not PressureDirector.can_spawn_at(wz) or wz >= PressureDirector.stage_len - PressureDirector.END_HOLD_UNITS:
		return {}
	var can_runner := stage >= RUNNER_MIN_STAGE
	var can_walker := stage >= WALKER_MIN_STAGE
	if not can_runner and not can_walker:
		return {}
	var type := MoverType.RUNNER
	if can_walker and (not can_runner or BillboardManager.get_rand01(k * 7187 + 59, seed_offset) < WALKER_RATIO):
		type = MoverType.WALKER
	var side := 1 if BillboardManager.get_rand01(k * 7187 + 97, seed_offset) < 0.5 else -1
	var phase := BillboardManager.get_rand01(k * 7187 + 131, seed_offset) * 10.0

	if jiwon_info.has("wz"):
		if absf(wz - float(jiwon_info["wz"])) < 40.0:
			return {}
	return { "k": k, "type": type, "wz": wz, "side": side, "phase": phase }

## 현재 차선 (러너는 런타임 상태, 워커는 시간 함수)
func _lane_of(o: Dictionary) -> float:
	var k := int(o["k"])
	if int(o["type"]) == MoverType.WALKER:
		return _walker_wave(o)["lane"]
	if _runner_lane.has(k):
		return float(_runner_lane[k])
	return float(o["side"]) * RUNNER_START_LANE

func _runner_active(o: Dictionary) -> bool:
	return _runner_lane.has(int(o["k"]))

# ── 러너 AI: 인식 → 차의 차선으로 달려듦 ──
func _update_runners(delta: float) -> void:
	var k0 := int(floor((scroll_z - WZ_BASE_OFFSET) / SPACING_Z)) - 1
	var k1 := int(ceil((scroll_z + RUNNER_TRIGGER_DZ - WZ_BASE_OFFSET) / SPACING_Z)) + 1
	for k in range(k0, k1 + 1):
		var o := _mover_at_k(k)
		if o.is_empty() or int(o["type"]) != MoverType.RUNNER:
			continue
		var dz := float(o["wz"]) - scroll_z
		if dz < -2.0:
			_runner_lane.erase(k)
			continue
		if _hit_info.has(k):
			continue
		if dz <= RUNNER_TRIGGER_DZ:
			if not _runner_lane.has(k):
				# Doc 30 §3: 같은 채널(시각+인지) 스파이크가 진행 중이면 돌진을 미룬다
				if PressureDirector.spike_active():
					continue
				_runner_lane[k] = float(o["side"]) * RUNNER_START_LANE
				PressureDirector.register_spike(2.5)
			# 차의 현재 차선을 향해 일정 속도로 이동 (추적 지연 = 회피 창)
			var cur := float(_runner_lane[k])
			_runner_lane[k] = move_toward(cur, cam_x, RUNNER_LANE_SPEED * delta)

# ── 충돌: 최대 max_hits명. 결과 [{k, type}] ──
func check_collision(vehicle: LastRoadVehicle, max_hits: int = 1) -> Array:
	_prune_hits()
	var hits: Array = []
	if _runner_textures.is_empty():
		return hits
	var k0 := int(floor((scroll_z - WZ_BASE_OFFSET) / SPACING_Z)) - 1
	var k1 := k0 + 4
	var threshold := (vehicle.COLLISION_WIDTH + OBJECT_WIDTH) * 0.5
	for k in range(k0, k1 + 1):
		if hits.size() >= max_hits:
			break
		var o := _mover_at_k(k)
		if o.is_empty():
			continue
		var dz := float(o["wz"]) - scroll_z
		if dz < 0.0 or dz > HIT_DZ:
			continue
		if _hit_info.has(k):
			continue
		var lane := _lane_of(o)
		# 러너가 아직 갓길에 있으면(미활성) 충돌 없음
		if absf(lane) > 1.2:
			continue
		if absf(lane - vehicle.cam_x) > threshold:
			continue
		_hit_info[k] = { "until_z": float(o["wz"]) + HIT_COOLDOWN_Z, "hit_time": _anim_time, "type": int(o["type"]), "lane": lane }
		hits.append({ "k": k, "type": int(o["type"]) })
	return hits

func _prune_hits() -> void:
	for k in _hit_info.keys():
		if float(_hit_info[k]["until_z"]) <= scroll_z:
			_hit_info.erase(k)

# ── 렌더 ──────────────────────────────────────────────────────
func _update_billboards() -> void:
	if _runner_textures.is_empty() or billboard_mgr == null:
		return
	var kr := BillboardManager.visible_k_range(scroll_z, SPACING_Z, VISIBLE_DZ_MIN, VISIBLE_DZ_MAX, WZ_BASE_OFFSET, WZ_MAX_JITTER)
	if _light_pool:
		_light_pool.reset()

	for k in range(kr.x, kr.y + 1):
		var o := _mover_at_k(k)
		if o.is_empty():
			continue
		var wz := float(o["wz"])
		var dz := wz - scroll_z
		var is_hit := _hit_info.has(k)
		if not is_hit and (dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX):
			continue
		var render_dz := dz
		if is_hit and dz < 0.84:
			render_dz = 0.84
		var proj := BillboardManager.calculate_projection(render_dz, cam_x, _curve_x, hill_px, _headlight_range)
		var depth: float = proj.depth
		var is_walker := int(o["type"]) == MoverType.WALKER
		var lane := float(_hit_info[k]["lane"]) if is_hit else _lane_of(o)
		var x: float = float(proj.road_cx) + lane * float(proj.road_hw) * 0.42

		var tex: Texture2D
		var base_h := WALKER_BASE_H if is_walker else RUNNER_BASE_H
		var tint := WALKER_TINT if is_walker else RUNNER_TINT
		var flip := false
		if is_hit:
			var downs := _walker_down if is_walker else _runner_down
			var frame := mini(int(floor((_anim_time - float(_hit_info[k]["hit_time"])) * 24.0)), downs.size() - 1)
			tex = downs[frame] if downs.size() > 0 else _runner_textures[0]
		elif is_walker:
			tex = _walker_textures[int(_anim_time * 6.0) % _walker_textures.size()]
			# 이동 방향 쪽으로 바라보게 (삼각파 기울기 부호)
			flip = _walker_dir(o) < 0.0
		else:
			var active := _runner_active(o)
			var fps := 14.0 if active else 2.0   # 달릴 땐 빠르게
			tex = _runner_textures[int(_anim_time * fps) % _runner_textures.size()]
			flip = float(o["side"]) > 0.0
			if active:
				# 달리는 느낌: 상하 바운스
				base_h *= 1.0 + 0.05 * sin(_anim_time * 28.0)

		var h := depth * base_h
		if is_hit:
			h *= 1.4
		var w: float = h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
		var fade: float = 1.0 - clampf((dz - VISIBLE_DZ_MAX * 0.75) / (VISIBLE_DZ_MAX * 0.25), 0.0, 1.0)
		var mat := _light_pool.get_material(float(proj.light_h)) if _light_pool else null
		billboard_mgr.add_entry(depth, Rect2(x - w * 0.5, float(proj.ground_y) - h * 0.78, w, h), tex, fade, mat, tint, flip, float(proj.light_h), float(proj.ground_y))

func _walker_dir(o: Dictionary) -> float:
	return _walker_wave(o)["dir"]

## 삼각파 왕복: 거리 x(차선 단위)가 0→2L 구간은 -L→+L, 2L→4L 구간은 +L→-L
func _walker_wave(o: Dictionary) -> Dictionary:
	var L := WALKER_LANE_LIMIT
	var x := fmod(_anim_time * WALKER_LANE_SPEED + float(o["phase"]), 4.0 * L)
	if x < 2.0 * L:
		return { "lane": -L + x, "dir": 1.0 }
	return { "lane": L - (x - 2.0 * L), "dir": -1.0 }
