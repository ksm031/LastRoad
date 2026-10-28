extends Node2D
class_name LastRoadMovers
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ══════════════════════════════════════════════════════════════
#  이동형 적 — 러너 · 워커 · 앰부서 · 행렬 컬트 (Doc 19)
#
#  러너(2+):   갓길 대기 → 차를 인식(TRIGGER_DZ)하면 차의 차선을 향해 달려든다. 막판 회피.
#  워커(4+):   도로 좌우 끝을 왕복. Y축 접근 없음. 틈으로 통과.
#  앰부서(2+): 수풀에 숨어 보이지 않다가 가까이 오면 도로로 뛰쳐나와 선다. 0.5초 반응.
#  행렬(3+):   외줄 3~5명(선두 우두머리)이 1m/s로 도로를 횡단. 한 명씩 칠 수 있다.
#
#  배치는 시드 기반 결정적(k → 타입·위치·방향). 러너 차선·행렬 진행도만 런타임 상태.
#  스프라이트는 임시: 와쳐/점퍼 idle에 타입별 틴트.
# ══════════════════════════════════════════════════════════════

enum MoverType { RUNNER, WALKER, AMBUSHER, CULT }

# ── 스폰 튜닝 (spawn_config.gd에서 주입) ──
var SPACING_Z    := 55.0
var SPAWN_CHANCE := 0.30
var seed_offset  := 0
var stage        := 1
const RUNNER_MIN_STAGE   := 2
const AMBUSHER_MIN_STAGE := 2
const CULT_MIN_STAGE     := 3
const WALKER_MIN_STAGE   := 4
const CULT_K_MOD         := 7     # k % 7 == 3 인 슬롯만 행렬 후보 → 스테이지당 ~1.5회

const VISIBLE_DZ_MIN := 0.40
const VISIBLE_DZ_MAX := 85.0
const WZ_BASE_OFFSET := 25.0
const WZ_MAX_JITTER  := 12.0

# ── 러너 ──
const RUNNER_TRIGGER_DZ   := 26.0
const RUNNER_START_LANE   := 1.55
const RUNNER_LANE_SPEED   := 0.75   # 차선/초 (3 m/s 상당)
const RUNNER_BASE_H       := 500.0
# ── 워커 ──
const WALKER_LANE_SPEED   := 0.8
const WALKER_LANE_LIMIT   := 1.0
const WALKER_BASE_H       := 480.0
# ── 앰부서 ──
const AMB_TRIGGER_DZ      := 13.0   # 90km/h 기준 ~1.9초 전. 보고 꺾을 수 있는 최소치
const AMB_START_LANE      := 1.7
const AMB_LANE_SPEED      := 1.9    # 뛰쳐나오는 속도 (차선/초)
const AMB_BASE_H          := 520.0
# ── 행렬 컬트 ──
const CULT_TRIGGER_DZ     := 60.0   # 멀리서부터 횡단 시작 (판단 시간 확보)
const CULT_START_LANE     := 1.35
const CULT_LANE_SPEED     := 0.22   # 1 m/s 상당. 도로 횡단 ~12초
const CULT_GAP            := 0.34   # 행렬 간격 (차선 단위)
const CULT_BASE_H         := 470.0
const CULT_LEADER_SCALE   := 1.28

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
var _hit_info  : Dictionary = {}    # hit_key(int) -> { until_z, hit_time, type, lane, leader }
var _runner_lane : Dictionary = {}  # k -> float (러너·앰부서 현재 차선)
var _cult_progress : Dictionary = {} # k -> float (행렬 진행도, 차선 단위)
var _cult_passed_flag : bool = false # 행렬을 치지 않고 지나침 (정신력 -2 시선 비용)
var jiwon_info : Dictionary = {}
var billboard_mgr: BillboardManager
var _runner_charged_flag: bool = false   # 러너가 막 돌진을 시작함 (혼잣말 트리거)
var _ambush_flag: bool = false           # 앰부서가 막 뛰쳐나옴

## 이번 프레임에 러너가 돌진을 시작했는가 (읽으면 소거)
func consume_runner_charged() -> bool:
	var f := _runner_charged_flag
	_runner_charged_flag = false
	return f

func consume_ambush() -> bool:
	var f := _ambush_flag
	_ambush_flag = false
	return f

func consume_cult_passed() -> bool:
	var f := _cult_passed_flag
	_cult_passed_flag = false
	return f

var _runner_textures : Array[Texture2D] = []
var _runner_down     : Array[Texture2D] = []
var _walker_textures : Array[Texture2D] = []
var _walker_down     : Array[Texture2D] = []
var _light_pool: LightMaterialPool
const POOL_SIZE := 28
const _AMBIENT_NORMAL := Color(0.36, 0.33, 0.36, 1.0)
const _AMBIENT_DARK   := Color(0.24, 0.22, 0.26, 1.0)
const RUNNER_TINT   := Color(1.0, 0.70, 0.62, 1.0)
const WALKER_TINT   := Color(0.72, 0.80, 1.0, 1.0)
const AMBUSH_TINT   := Color(0.70, 0.95, 0.62, 1.0)
const CULT_TINT     := Color(0.30, 0.27, 0.32, 1.0)   # 후드 검정 #1A1818 근사
const LEADER_TINT   := Color(0.16, 0.13, 0.16, 1.0)

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
	_cult_progress.clear()
	_cult_passed_flag = false

func _process(delta: float) -> void:
	_anim_time += delta
	_update_dynamics(delta)
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
	if jiwon_info.has("wz") and absf(wz - float(jiwon_info["wz"])) < 40.0:
		return {}

	var side := 1 if BillboardManager.get_rand01(k * 7187 + 97, seed_offset) < 0.5 else -1
	var phase := BillboardManager.get_rand01(k * 7187 + 131, seed_offset) * 10.0
	var roll := BillboardManager.get_rand01(k * 7187 + 59, seed_offset)

	# 행렬: 전용 슬롯(k % 7 == 3)에서만, 스테이지 3+
	if stage >= CULT_MIN_STAGE and posmod(k, CULT_K_MOD) == 3:
		var count := 3 + int(BillboardManager.get_rand01(k * 7187 + 173, seed_offset) * 3.0)  # 3~5
		return { "k": k, "type": MoverType.CULT, "wz": wz, "side": side, "phase": phase, "count": count }

	# 나머지 타입 풀 (스테이지 게이트)
	var pool: Array = []
	if stage >= RUNNER_MIN_STAGE:   pool.append(MoverType.RUNNER)
	if stage >= AMBUSHER_MIN_STAGE: pool.append(MoverType.AMBUSHER)
	if stage >= WALKER_MIN_STAGE:   pool.append(MoverType.WALKER)
	if pool.is_empty():
		return {}
	var type: int = pool[int(roll * float(pool.size())) % pool.size()]
	# 앰부서는 도로 진입 후 설 차선 (갓길 쪽 차선 또는 중앙)
	var stop_lane := float(side) * (0.75 if BillboardManager.get_rand01(k * 7187 + 211, seed_offset) < 0.6 else 0.0)
	return { "k": k, "type": type, "wz": wz, "side": side, "phase": phase, "stop_lane": stop_lane }

## 단일 개체의 현재 차선 (러너·앰부서는 런타임 상태, 워커는 시간 함수)
func _lane_of(o: Dictionary) -> float:
	var k := int(o["k"])
	match int(o["type"]):
		MoverType.WALKER:
			return _walker_wave(o)["lane"]
		MoverType.AMBUSHER:
			if _runner_lane.has(k):
				return float(_runner_lane[k])
			return float(o["side"]) * AMB_START_LANE
		_:
			if _runner_lane.has(k):
				return float(_runner_lane[k])
			return float(o["side"]) * RUNNER_START_LANE

func _is_active(o: Dictionary) -> bool:
	return _runner_lane.has(int(o["k"]))

## 행렬 i번째(0=우두머리) 차선. 아직 출발 전이면 갓길에 대기
func _cult_member_lane(o: Dictionary, i: int) -> float:
	var k := int(o["k"])
	var side := float(o["side"])
	var prog := float(_cult_progress.get(k, 0.0))
	var p := prog - float(i) * CULT_GAP
	if p < 0.0:
		return side * CULT_START_LANE
	return side * CULT_START_LANE - side * p

static func _hit_key(k: int, i: int) -> int:
	return k * 16 + i

# ── 런타임 AI ─────────────────────────────────────────────────
func _update_dynamics(delta: float) -> void:
	var k0 := int(floor((scroll_z - WZ_BASE_OFFSET) / SPACING_Z)) - 1
	var k1 := int(ceil((scroll_z + CULT_TRIGGER_DZ - WZ_BASE_OFFSET) / SPACING_Z)) + 1
	for k in range(k0, k1 + 1):
		var o := _mover_at_k(k)
		if o.is_empty():
			continue
		var dz := float(o["wz"]) - scroll_z
		var type := int(o["type"])
		if dz < -2.0:
			_runner_lane.erase(k)
			_cult_progress.erase(k)
			continue
		match type:
			MoverType.RUNNER:
				if _hit_info.has(_hit_key(k, 0)):
					continue
				if dz <= RUNNER_TRIGGER_DZ:
					if not _runner_lane.has(k):
						# Doc 30 §3: 같은 채널 스파이크 진행 중이면 돌진을 미룬다
						if PressureDirector.spike_active():
							continue
						_runner_lane[k] = float(o["side"]) * RUNNER_START_LANE
						PressureDirector.register_spike(2.5)
						_runner_charged_flag = true
					var cur := float(_runner_lane[k])
					_runner_lane[k] = move_toward(cur, cam_x, RUNNER_LANE_SPEED * delta)
			MoverType.AMBUSHER:
				if _hit_info.has(_hit_key(k, 0)):
					continue
				if dz <= AMB_TRIGGER_DZ:
					if not _runner_lane.has(k):
						if PressureDirector.spike_active():
							continue
						_runner_lane[k] = float(o["side"]) * AMB_START_LANE
						PressureDirector.register_spike(1.5)
						_ambush_flag = true
					var cur := float(_runner_lane[k])
					_runner_lane[k] = move_toward(cur, float(o["stop_lane"]), AMB_LANE_SPEED * delta)
			MoverType.CULT:
				if dz <= CULT_TRIGGER_DZ:
					if not _cult_progress.has(k):
						_cult_progress[k] = 0.0
					_cult_progress[k] = float(_cult_progress[k]) + CULT_LANE_SPEED * delta
					# 행렬을 막 지나쳤는데 아무도 안 쳤으면 '시선' 비용
					if dz < 0.0 and dz >= -2.0 and not bool(o.get("_passed", false)):
						var any_hit := false
						for i in range(int(o["count"])):
							if _hit_info.has(_hit_key(k, i)):
								any_hit = true
								break
						if not any_hit and not _cult_progress.has(-k - 1):
							_cult_progress[-k - 1] = 1.0   # 통과 마커 (한 번만)
							_cult_passed_flag = true
			_:
				pass

# ── 충돌: 최대 max_hits명. 결과 [{k, type, leader}] ──
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
		var type := int(o["type"])
		if type == MoverType.CULT:
			for i in range(int(o["count"])):
				if hits.size() >= max_hits:
					break
				var hk := _hit_key(k, i)
				if _hit_info.has(hk):
					continue
				var lane := _cult_member_lane(o, i)
				if absf(lane) > 1.2 or absf(lane - vehicle.cam_x) > threshold * 0.8:
					continue
				_hit_info[hk] = { "until_z": float(o["wz"]) + HIT_COOLDOWN_Z, "hit_time": _anim_time, "type": type, "lane": lane, "leader": i == 0 }
				hits.append({ "k": k, "type": type, "leader": i == 0 })
			continue
		var hk0 := _hit_key(k, 0)
		if _hit_info.has(hk0):
			continue
		var lane := _lane_of(o)
		if absf(lane) > 1.2:
			continue   # 아직 갓길 (미활성)
		if absf(lane - vehicle.cam_x) > threshold:
			continue
		_hit_info[hk0] = { "until_z": float(o["wz"]) + HIT_COOLDOWN_Z, "hit_time": _anim_time, "type": type, "lane": lane, "leader": false }
		hits.append({ "k": k, "type": type, "leader": false })
	return hits

func _prune_hits() -> void:
	for hk in _hit_info.keys():
		if float(_hit_info[hk]["until_z"]) <= scroll_z:
			_hit_info.erase(hk)

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
		var type := int(o["type"])
		if type == MoverType.CULT:
			for i in range(int(o["count"])):
				_render_one(o, i, dz, _hit_info.has(_hit_key(k, i)))
			continue
		# 앰부서는 뛰쳐나오기 전엔 보이지 않는다
		if type == MoverType.AMBUSHER and not _is_active(o) and not _hit_info.has(_hit_key(k, 0)):
			continue
		_render_one(o, 0, dz, _hit_info.has(_hit_key(k, 0)))

func _render_one(o: Dictionary, i: int, dz: float, is_hit: bool) -> void:
	var k := int(o["k"])
	var type := int(o["type"])
	if not is_hit and (dz < VISIBLE_DZ_MIN or dz > VISIBLE_DZ_MAX):
		return
	var render_dz := dz
	if is_hit and dz < 0.84:
		render_dz = 0.84
	var proj := BillboardManager.calculate_projection(render_dz, cam_x, _curve_x, hill_px, _headlight_range)
	var depth: float = proj.depth
	var hk := _hit_key(k, i)
	var lane: float
	if is_hit:
		lane = float(_hit_info[hk]["lane"])
	elif type == MoverType.CULT:
		lane = _cult_member_lane(o, i)
	else:
		lane = _lane_of(o)
	var x: float = float(proj.road_cx) + lane * float(proj.road_hw) * 0.42

	var tex: Texture2D
	var base_h: float
	var tint: Color
	var flip := false
	var use_jumper_set := (type == MoverType.WALKER or type == MoverType.CULT)
	match type:
		MoverType.WALKER:   base_h = WALKER_BASE_H; tint = WALKER_TINT
		MoverType.AMBUSHER: base_h = AMB_BASE_H;    tint = AMBUSH_TINT
		MoverType.CULT:
			base_h = CULT_BASE_H * (CULT_LEADER_SCALE if i == 0 else 1.0)
			tint = LEADER_TINT if i == 0 else CULT_TINT
		_:                  base_h = RUNNER_BASE_H; tint = RUNNER_TINT

	if is_hit:
		var downs := _walker_down if use_jumper_set else _runner_down
		var frame := mini(int(floor((_anim_time - float(_hit_info[hk]["hit_time"])) * 24.0)), downs.size() - 1)
		tex = downs[frame] if downs.size() > 0 else _runner_textures[0]
	elif type == MoverType.WALKER:
		tex = _walker_textures[int(_anim_time * 6.0) % _walker_textures.size()]
		flip = _walker_dir(o) < 0.0
	elif type == MoverType.CULT:
		# 느린 걸음. 우두머리는 정면 응시(프레임 고정)
		tex = _walker_textures[0] if i == 0 else _walker_textures[int(_anim_time * 2.0 + float(i)) % _walker_textures.size()]
		flip = float(o["side"]) > 0.0
	else:
		var active := _is_active(o)
		var fps := 14.0 if active else 2.0
		tex = _runner_textures[int(_anim_time * fps) % _runner_textures.size()]
		flip = float(o["side"]) > 0.0
		if active:
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
