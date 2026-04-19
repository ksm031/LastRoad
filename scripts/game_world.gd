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

# ── 배경 무한 스크롤 (코너에서만 누적) ────────────────────────
var _sky_tile_w := 1.0
var _mtn_tile_w := 1.0
var _sky_scroll := 0.0
var _mtn_scroll := 0.0
const CORNER_BG_K_THRESH := 0.0035
const BG_MTN_SPEED       := 0.38
const BG_SKY_VS_MTN      := 0.32

const _RoadScript    = preload("res://scripts/road_renderer.gd")
const _TreeScript    = preload("res://scripts/tree_renderer.gd")
const _VehicleScript = preload("res://scripts/vehicle.gd")
const _HudScript     = preload("res://scripts/hud.gd")

# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_sky_tiled()
	_build_mountain_tiled()
	_road    = _RoadScript.new();    add_child(_road)
	_trees   = _TreeScript.new();    add_child(_trees)
	_vehicle = _VehicleScript.new(); add_child(_vehicle)
	_hud     = _HudScript.new();     add_child(_hud)

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

# ── 산 실루엣 (2타일 무한 가로 스크롤) ───────────────────────
func _build_mountain_tiled() -> void:
	var tex := load("res://Asset/Image/mountain.png") as Texture2D
	if tex == null:
		return
	var mtn_h := 130.0
	var sc := Vector2(
		float(SCREEN_W) / float(tex.get_width()),
		mtn_h / float(tex.get_height())
	)
	_mtn_tile_w = float(tex.get_width()) * sc.x
	var y0 := float(HORIZON_Y) - mtn_h
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
	_update_backdrops(delta)
	_hud.update(_vehicle.speed, _vehicle.scroll_z, _vehicle.steering_angle, _vehicle.rpm)
	_road.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x)
	_trees.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x)


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
