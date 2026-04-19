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
var _camera   : Camera2D

var _monster_distance: float = 60.0  # 초기 괴물 간격 (세계 단위, 600은 지평선 너머였음)
const MONSTER_SPEED := 90.0           # 괴물 고정 속도 (km/h)

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
	_vehicle.handle_input(delta)
	_vehicle.update_scroll(delta)
	_vehicle.update_rpm(delta)
	var curve_x := _vehicle.compute_strip_curve_offsets()
	var hill_px := _vehicle.hill_offset_px()
	
	# 괴물 간격 업데이트 (km/h -> 세계 단위 변환율 SCROLL_RATE = 0.05)
	var speed_diff := _vehicle.speed - MONSTER_SPEED
	_monster_distance += speed_diff * 0.05 * delta
	_monster_distance = maxf(_monster_distance, 0.0)
	
	_update_backdrops(delta)
	_update_backdrops_vertical(delta, hill_px)
	_hud.update(_vehicle.speed, _vehicle.scroll_z, _vehicle.steering_angle, _vehicle.rpm, _monster_distance, delta)
	
	# 카메라 줌 업데이트 (전체 화면 줌)
	var ease_t := smoothstep(0.0, 1.0, _hud._focus_t)
	var screen_center := Vector2(640.0, 360.0)
	
	# 룸미러의 중심 (665, 81). 
	# 카메라가 이 좌표를 향하면 룸미러가 화면 정중앙에 옵니다.
	# 룸미러가 화면 중앙보다 약간 위쪽에 오게 하려면, 카메라가 살짝 아래를 봐야 하므로 y값을 늘려줍니다.
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
	if _obstacles.check_collision(_vehicle):
		_hud.on_rock_hit()


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
