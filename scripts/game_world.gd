extends Node2D

# ── 화면 상수 ────────────────────────────────────────────────
const SCREEN_W  := 1280
const SCREEN_H  := 720
const HORIZON_Y := 300

# ── 노드 참조 ────────────────────────────────────────────────
var _road    : Node2D
var _trees   : Node2D
var _sky_a   : Sprite2D
var _sky_b   : Sprite2D
var _mtn_a   : Sprite2D
var _mtn_b   : Sprite2D
var _vehicle: LastRoadVehicle
var _hud     : CanvasLayer
var _rain_layer : CanvasLayer
var _rain    : Node2D
var _obstacles: LastRoadObstacles
var _watchers : LastRoadWatchers
var _camera   : Camera2D

var _monster_distance: float = 60.0  # 초기 괴물 간격 (세계 단위)
var _sanity_ratio: float = 1.0        # 정신력 (1.0 = 정상, 0.0 = 패닉)

# ── 스테이지 진행 시스템 ─────────────────────────────────────
const MONSTER_SPEEDS := [70.0, 80.0, 90.0, 100.0, 110.0, 120.0]  # 스테이지 1~6
const STAGE_LENGTH  := 600.0    # 각 스테이지 목표 거리 (세계 단위, 밸런스 조정용)
const TOTAL_STAGES  := 6

var current_stage     : int   = 1
var stage_start_z     : float = 0.0     # 스테이지 시작 시점의 scroll_z

# 게임 상태: "playing", "stage_clear", "game_over"
var _game_state       : String = "playing"
var _state_timer      : float = 0.0
const STAGE_CLEAR_DURATION := 3.0
const GAMEOVER_FADE_DURATION := 1.5

# ── 배경 무한 스크롤 (코너에서만 누적) ────────────────────────
var _sky_tile_w := 1.0
var _mtn_tile_w := 1.0
var _sky_scroll := 0.0
var _mtn_scroll := 0.0
const CORNER_BG_K_THRESH := 0.0035
const BG_MTN_SPEED       := 0.38
const BG_SKY_VS_MTN      := 0.32
const MTN_Y_OFFSET       := 22.0  # 산맥을 조금 내려 지평선 틈 가리기

# ── 언덕 시 배경 세로 패럴랙스 (숨쉬는 느낌 방지: 스무딩) ───────
const MTN_H_PX           := 130.0
const MTN_HILL_FACTOR    := 0.18  # 언덕 픽셀의 일부만 산이 따라옴
const SKY_HILL_FACTOR    := 0.06  # 하늘은 더 느리게
const BG_Y_SMOOTH_SPEED  := 6.0   # 클수록 빠르게 목표로 수렴

const _RoadScript    = preload("res://scripts/road_renderer.gd")
const _TreeScript    = preload("res://scripts/tree_renderer.gd")
const _VehicleScript = preload("res://scripts/vehicle.gd")
const _HudScript     = preload("res://scripts/hud.gd")
const _ObstacleScript = preload("res://scripts/obstacle_system.gd")
const _RainScript    = preload("res://scripts/rain_renderer.gd")
const _WatcherScript = preload("res://scripts/watcher_system.gd")

var _mtn_base_y: float = 0.0
var _sky_base_y: float = 0.0
var _mtn_y: float = 0.0
var _sky_y: float = 0.0

# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	# 카메라 이동 시 화면 밖(회색) 영역이 보이지 않도록 거대한 검은색 배경을 먼저 깔아줍니다.
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(6000, 6000)
	add_child(bg)
	
	_build_sky_tiled()
	_build_mountain_tiled()
	_road    = _RoadScript.new();    add_child(_road)
	_trees   = _TreeScript.new();    add_child(_trees)
	_watchers = _WatcherScript.new(); add_child(_watchers)
	_obstacles = _ObstacleScript.new(); add_child(_obstacles)
	_vehicle = _VehicleScript.new(); add_child(_vehicle)
	# rain은 화면 고정이어야 하므로 CanvasLayer에 올려 카메라 줌/패럴랙스 영향 차단
	_rain_layer = CanvasLayer.new()
	_rain_layer.layer = 1               # hud와 같은 레이어지만 트리 상 먼저라 아래 렌더
	add_child(_rain_layer)
	_rain = _RainScript.new()
	_rain_layer.add_child(_rain)
	_hud  = _HudScript.new();       add_child(_hud)
	_rain.start_rain()
	
	_camera = Camera2D.new()
	_camera.position = Vector2(640.0, 360.0)
	add_child(_camera)
	
	_hud.follow_viewport_enabled = true

# ── 하늘 (2타일 무한 가로 스크롤) ────────────────────────────
func _build_sky_tiled() -> void:
	var tex := load("res://Asset/Image/sky.png") as Texture2D
	if tex == null:
		return
	var sc := Vector2(
		float(SCREEN_W) / float(tex.get_width()),
		float(HORIZON_Y) / float(tex.get_height())
	)
	_sky_tile_w = float(tex.get_width()) * sc.x
	_sky_a = Sprite2D.new()
	_sky_b = Sprite2D.new()
	for s in [_sky_a, _sky_b]:
		s.texture = tex
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.scale = sc
		s.position = Vector2(0.0, 0.0)
		add_child(s)
	_sky_b.position.x = _sky_tile_w
	_apply_pair_scroll(_sky_a, _sky_b, _sky_scroll, _sky_tile_w)
	_sky_base_y = 0.0
	_sky_y = _sky_base_y

# ── 산 실루엣 (2타일 무한 가로 스크롤) ───────────────────────
func _build_mountain_tiled() -> void:
	var tex := load("res://Asset/Image/mountain.png") as Texture2D
	if tex == null:
		return
	var mtn_h := MTN_H_PX
	var sc := Vector2(
		float(SCREEN_W) / float(tex.get_width()),
		mtn_h / float(tex.get_height())
	)
	_mtn_tile_w = float(tex.get_width()) * sc.x
	var y0 := float(HORIZON_Y) - mtn_h + MTN_Y_OFFSET
	_mtn_base_y = y0
	_mtn_y = _mtn_base_y
	_mtn_a = Sprite2D.new()
	_mtn_b = Sprite2D.new()
	for s in [_mtn_a, _mtn_b]:
		s.texture = tex
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.scale = sc
		s.position = Vector2(0.0, y0)
		add_child(s)
	_mtn_b.position.x = _mtn_tile_w
	_apply_pair_scroll(_mtn_a, _mtn_b, _mtn_scroll, _mtn_tile_w)


func _apply_pair_scroll(a: Sprite2D, b: Sprite2D, scroll: float, tile_w: float) -> void:
	if tile_w <= 0.0 or a == null or b == null:
		return
	var s := fposmod(scroll, tile_w)
	var y0 := a.position.y
	a.position = Vector2(-s, y0)
	b.position = Vector2(tile_w - s, y0)

# ─────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _game_state == "game_over":
		_state_timer += delta
		var fade := clampf(_state_timer / GAMEOVER_FADE_DURATION, 0.0, 1.0)
		_hud.set_gameover_fade(fade)
		# 카메라 줌 리셋 (룸미러 보는 중 게임오버 시 대응)
		_hud._focus_t = maxf(_hud._focus_t - delta * 5.0, 0.0)
		var ease_go := smoothstep(0.0, 1.0, _hud._focus_t)
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.2, 2.2), ease_go)
		_camera.position = Vector2(640.0, 360.0).lerp(Vector2(665.0, 120.0), ease_go)
		return
	
	if _game_state == "stage_clear":
		_state_timer += delta
		if _state_timer >= STAGE_CLEAR_DURATION:
			_advance_to_next_stage()
		return
	
	# ── playing 상태 ──
	_vehicle.handle_input(delta)
	_vehicle.update_scroll(delta)
	_vehicle.update_fuel(delta)
	_vehicle.update_rpm(delta)
	var curve_x := _vehicle.compute_strip_curve_offsets()
	var hill_px := _vehicle.hill_offset_px()
	
	# 괴물 간격 업데이트
	var monster_speed := float(MONSTER_SPEEDS[clampi(current_stage - 1, 0, TOTAL_STAGES - 1)])
	var speed_diff := _vehicle.speed - monster_speed
	_monster_distance += speed_diff * 0.05 * delta
	_monster_distance = maxf(_monster_distance, 0.0)
	
	# ── 게임오버 체크: 괴물에게 따라잡힘 ──
	if _monster_distance <= 0.0:
		_game_state = "game_over"
		_state_timer = 0.0
		_hud.show_gameover()
		return
	
	# ── 스테이지 클리어 체크 ──
	var stage_distance := _vehicle.scroll_z - stage_start_z
	if stage_distance >= STAGE_LENGTH:
		if current_stage >= TOTAL_STAGES:
			# 최종 스테이지 클리어 = 엔딩
			_game_state = "stage_clear"
			_state_timer = 0.0
			_hud.show_stage_clear(current_stage, true)
		else:
			_game_state = "stage_clear"
			_state_timer = 0.0
			_hud.show_stage_clear(current_stage, false)
		return
	
	# 정신력 업데이트 (괴물이 40 단위 이내로 다가오면 공포감으로 감소)
	# GDD: 자동 회복 없음. 담배와 정비 구간에서만 회복
	if _monster_distance < 40.0:
		var drain_spd := (40.0 - _monster_distance) * 0.0025
		_sanity_ratio -= drain_spd * delta
	
	# 라디오 죽음의 주파수: 정신력 -2/초 (GDD 18-radio.md)
	if _hud.get_radio_on_death():
		_sanity_ratio -= 0.02 * delta  # 2% per second
	
	_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	
	_update_backdrops(delta)
	_update_backdrops_vertical(delta, hill_px)
	_hud.update(_vehicle.speed, _vehicle.scroll_z, _vehicle.steering_angle, _vehicle.rpm, _monster_distance, delta, _vehicle.fuel_ratio, _sanity_ratio, current_stage, stage_distance, STAGE_LENGTH)
	_rain.vehicle_speed = _vehicle.speed
	
	# 카메라 줌 업데이트 (전체 화면 줌)
	var screen_center := Vector2(640.0, 360.0)
	
	if _hud._radio_focus_t > 0.0:
		var radio_ease_t := smoothstep(0.0, 1.0, _hud._radio_focus_t)
		# 라디오 위치 주변으로 줌. 라디오 패널 중앙 정도
		var target_camera_pos: Vector2 = _hud.RADIO_PANEL_POS + Vector2(100.0, 36.0)
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.5, 2.5), radio_ease_t)
		_camera.position = screen_center.lerp(target_camera_pos, radio_ease_t)
	else:
		var ease_t := smoothstep(0.0, 1.0, _hud._focus_t)
		var target_camera_pos := Vector2(665.0, 120.0) 
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.2, 2.2), ease_t)
		_camera.position = screen_center.lerp(target_camera_pos, ease_t)
	
	_rain.set_wiper_transforms(
		_hud._wiper_pivot_L.position, _hud._wiper_pivot_L.rotation,
		_hud._wiper_pivot_R.position, _hud._wiper_pivot_R.rotation
	)
	_road.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)
	_trees.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)
	_obstacles.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)
	_watchers.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)
	if _obstacles.check_collision(_vehicle):
		_hud.on_rock_hit()
	if _watchers.check_collision(_vehicle):
		# 와쳐: 속도 살짝 감소 + 정신력 감소 (GDD: 충돌 효과 + 정신력 -5~-20)
		_vehicle.apply_watcher_hit()
		_sanity_ratio -= 0.10  # 정신력 10% 감소
		_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
		_hud.on_watcher_hit()

# ── 다음 스테이지로 진행 ────────────────────────────────────
func _advance_to_next_stage() -> void:
	if current_stage >= TOTAL_STAGES:
		# TODO: 엔딩 씨은 처리
		return
	
	current_stage += 1
	stage_start_z = _vehicle.scroll_z
	_monster_distance = 60.0
	
	# 연료 만킱 충전
	_vehicle.fuel = _vehicle.FUEL_MAX
	_vehicle.fuel_ratio = 1.0
	
	# 정신력: 50% 미만이면 50%까지 회복 (04-resources.md)
	if _sanity_ratio < 0.5:
		_sanity_ratio = 0.5
	
	_game_state = "playing"
	_hud.hide_stage_overlay()
	_hud.update_radio_for_stage(current_stage)


# ── 코너일 때만 하늘·산 가로 패럴랙스 (무한 타일) ────────────
func _update_backdrops(delta: float) -> void:
	var k := _vehicle.curvature_at_scroll()
	if absf(k) < CORNER_BG_K_THRESH:
		return
	var v := _vehicle.speed
	var mtn_delta := k * v * BG_MTN_SPEED * delta
	var sky_delta := mtn_delta * BG_SKY_VS_MTN
	_mtn_scroll += mtn_delta
	_sky_scroll += sky_delta
	if _sky_a != null:
		_apply_pair_scroll(_sky_a, _sky_b, _sky_scroll, _sky_tile_w)
	if _mtn_a != null:
		_apply_pair_scroll(_mtn_a, _mtn_b, _mtn_scroll, _mtn_tile_w)


func _update_backdrops_vertical(delta: float, hill_px: float) -> void:
	# 언덕 시 “올라가는 느낌”은 배경의 아주 약한 상하 시차로만 준다.
	# 절대값을 1:1로 붙이면 숨쉬는 느낌이 나기 쉬워서, 스무딩 + 작은 계수로 제한.
	var target_mtn_y := _mtn_base_y + hill_px * MTN_HILL_FACTOR
	var target_sky_y := _sky_base_y + hill_px * SKY_HILL_FACTOR
	var a := clampf(delta * BG_Y_SMOOTH_SPEED, 0.0, 1.0)
	_mtn_y = lerpf(_mtn_y, target_mtn_y, a)
	_sky_y = lerpf(_sky_y, target_sky_y, a)

	if _mtn_a != null:
		_mtn_a.position.y = _mtn_y
	if _mtn_b != null:
		_mtn_b.position.y = _mtn_y
	if _sky_a != null:
		_sky_a.position.y = _sky_y
	if _sky_b != null:
		_sky_b.position.y = _sky_y
