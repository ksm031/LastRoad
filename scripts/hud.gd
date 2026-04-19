extends CanvasLayer

const RearviewRenderer = preload("res://scripts/rearview_renderer.gd")

# ╔══════════════════════════════════════════════════════════╗
# ║  ★ 룸미러 마스킹 조정 — 여기서만 수정하세요            ║
# ╠══════════════════════════════════════════════════════════╣
const MIRROR_MIN    := Vector2(535.0,  44.0)
const MIRROR_MAX    := Vector2(795.0, 118.0)
const PORTRAIT_BASE := Vector2(500.0, -90.0)
const PORTRAIT_W    := 335.0
const PORTRAIT_H    := 450.0

const SPD_GAUGE_CENTER := Vector2(422.0, 569.0)
const RPM_GAUGE_CENTER := Vector2(172.0, 569.0)
const NEEDLE_SCALE     := 1.0
const SPD_ANGLE_MIN    := -120.0
const SPD_ANGLE_MAX    :=  120.0
const RPM_ANGLE_MIN    := -120.0
const RPM_ANGLE_MAX    :=  120.0

const SPEED_MAX   := 240.0
const RPM_IDLE    := 800.0
const RPM_REDLINE := 7200.0

var _mirror_clip  : Control
var _portrait     : Sprite2D
var _rearview_node: RearviewRenderer
var _dash         : Sprite2D
var _wheel        : Sprite2D
var _spd_pivot    : Node2D
var _rpm_pivot    : Node2D
var _hud_spd      : Label

const IMPACT_TIME := 0.22
const IMPACT_MAG  := 9.0
var _impact_t: float = 0.0

var _focusing: bool = false
var _focus_t: float = 0.0

var _wiper_pivot_L: Node2D
var _wiper_pivot_R: Node2D
var _wiper_state: int = 0
var _z_pressed: bool = false
var _wiper_time: float = 0.0

func _ready() -> void:
	_build_wipers()
	_build_portrait_and_mirror()
	_build_dashboard()
	_build_needles()
	_build_wheel()
	_build_labels()
	set_process(true)

func _process(delta: float) -> void:
	if _impact_t > 0.0:
		_impact_t = maxf(_impact_t - delta, 0.0)
		
	# 포커싱 키 (F)
	_focusing = Input.is_key_pressed(KEY_F)
	if _focusing:
		_focus_t = minf(_focus_t + delta * 5.0, 1.0)
	else:
		_focus_t = maxf(_focus_t - delta * 5.0, 0.0)
		
	# 와이퍼 토글 키 (Z)
	if Input.is_key_pressed(KEY_Z):
		if not _z_pressed:
			_wiper_state = (_wiper_state + 1) % 3
			_z_pressed = true
	else:
		_z_pressed = false
		
	_update_wipers(delta)

func on_rock_hit() -> void:
	_impact_t = IMPACT_TIME

func _build_portrait_and_mirror() -> void:
	_mirror_clip = Control.new()
	_mirror_clip.position = MIRROR_MIN
	_mirror_clip.size = MIRROR_MAX - MIRROR_MIN
	_mirror_clip.clip_contents = true
	add_child(_mirror_clip)
	
	_rearview_node = RearviewRenderer.new()
	_rearview_node.modulate = Color(0.95, 0.95, 1.0)
	_mirror_clip.add_child(_rearview_node)
	
	_portrait = Sprite2D.new()
	var tex := load("res://Asset/Image/Portrait.png") as Texture2D
	if tex:
		_portrait.texture = tex
		_portrait.centered = false
		_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_portrait.scale = Vector2(1.0, 1.0)
		_portrait.position = PORTRAIT_BASE - MIRROR_MIN
		_portrait.modulate = Color(0.78, 0.83, 0.90)
	_mirror_clip.add_child(_portrait)

func _build_wipers() -> void:
	# 대시보드 안쪽 너무 깊숙이 박혀있지 않도록 y 위치를 450으로 더 끌어올립니다.
	_wiper_pivot_L = _make_wiper_assembly(Vector2(280.0, 450.0))
	_wiper_pivot_R = _make_wiper_assembly(Vector2(750.0, 450.0))

func _make_wiper_assembly(pos: Vector2) -> Node2D:
	var pivot := Node2D.new()
	pivot.position = pos
	
	var tex_a := load("res://Asset/Image/wiper_a.png") as Texture2D
	var sprite_a := Sprite2D.new()
	if tex_a:
		sprite_a.texture = tex_a
		sprite_a.centered = false
		sprite_a.offset = Vector2(0, -8.5) # 왼쪽 끝 중심
		sprite_a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pivot.add_child(sprite_a)
	
	var pivot_b := Node2D.new()
	pivot_b.position = Vector2(230.0, 0.0) # a의 오른쪽 끝
	sprite_a.add_child(pivot_b)
	
	var tex_b := load("res://Asset/Image/wipe_b.png") as Texture2D
	var sprite_b := Sprite2D.new()
	if tex_b:
		sprite_b.texture = tex_b
		sprite_b.centered = true
		sprite_b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# a와 평행하게 부착 (필요 시 수정 가능)
		sprite_b.rotation = 0.0 
	pivot_b.add_child(sprite_b)
	
	add_child(pivot)
	return pivot

func _build_dashboard() -> void:
	_dash = Sprite2D.new()
	var tex := load("res://Asset/Image/dashboard.png") as Texture2D
	if tex:
		_dash.texture = tex
		_dash.centered = false
		_dash.position = Vector2.ZERO
		_dash.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_dash.scale = Vector2(
			1280.0 / float(tex.get_width()),
			720.0  / float(tex.get_height())
		)
	add_child(_dash)

func _build_needles() -> void:
	_spd_pivot = _make_needle_pivot(SPD_GAUGE_CENTER)
	_spd_pivot.rotation = deg_to_rad(-120.0)
	_rpm_pivot = _make_needle_pivot(RPM_GAUGE_CENTER)
	_rpm_pivot.rotation = deg_to_rad(-120.0)

func _make_needle_pivot(center: Vector2) -> Node2D:
	var pivot := Node2D.new()
	pivot.position = center
	var needle := Sprite2D.new()
	var tex := load("res://Asset/Image/speed meter needle.png") as Texture2D
	if tex:
		needle.texture = tex
		needle.centered = false
		needle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		needle.scale = Vector2(NEEDLE_SCALE, NEEDLE_SCALE)
		needle.position = Vector2(
			-float(tex.get_width())  * NEEDLE_SCALE * 0.5,
			-float(tex.get_height()) * NEEDLE_SCALE
		)
	pivot.add_child(needle)
	add_child(pivot)
	return pivot

func _build_wheel() -> void:
	_wheel = Sprite2D.new()
	var tex := load("res://Asset/Image/steering wheel.png") as Texture2D
	if tex:
		_wheel.texture = tex
		_wheel.centered = true
		_wheel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_wheel.scale = Vector2(1.0, 1.0)
		_wheel.position = Vector2(290.0, 660.0)
	add_child(_wheel)

func _build_labels() -> void:
	_hud_spd = Label.new()
	_hud_spd.position = Vector2(28, 24)
	_hud_spd.add_theme_font_size_override("font_size", 22)
	_hud_spd.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	add_child(_hud_spd)

	var help := Label.new()
	help.position = Vector2(28, 54)
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	help.text = "W/S: 가속·감속   A/D: 좌우 이동   F: 뒤보기"
	add_child(help)

func update(speed: float, scroll_z: float, steering_angle: float, rpm: float, monster_distance: float = 600.0, delta: float = 0.0) -> void:
	_update_gauges(speed, rpm)
	_update_shake(speed, scroll_z, steering_angle)
	if _wheel != null:
		_wheel.rotation = deg_to_rad(steering_angle)
	if _hud_spd != null:
		_hud_spd.text = "%.0f km/h" % speed
		
	if _rearview_node != null:
		_rearview_node.update_state(scroll_z, monster_distance, delta)

func _update_gauges(speed: float, rpm: float) -> void:
	if _spd_pivot != null:
		var t := clampf(speed / SPEED_MAX, 0.0, 1.0)
		_spd_pivot.rotation = deg_to_rad(lerpf(SPD_ANGLE_MIN, SPD_ANGLE_MAX, t))
	if _rpm_pivot != null:
		var t := clampf((rpm - RPM_IDLE) / (RPM_REDLINE - RPM_IDLE), 0.0, 1.0)
		_rpm_pivot.rotation = deg_to_rad(lerpf(RPM_ANGLE_MIN, RPM_ANGLE_MAX, t))

func _update_wipers(delta: float) -> void:
	if _wiper_pivot_L == null or _wiper_pivot_R == null:
		return
		
	var speed_mult := 0.0
	if _wiper_state == 1:
		speed_mult = 1.0 # 1단
	elif _wiper_state == 2:
		speed_mult = 2.0 # 2단
		
	if _wiper_state > 0:
		_wiper_time += delta * speed_mult * 3.5
	else:
		# 정지: 가장 가까운 정수 PI 배수로 스무스하게 이동 (제자리 주차)
		var target := ceilf(_wiper_time / PI) * PI
		if _wiper_time < target - 0.01:
			_wiper_time = move_toward(_wiper_time, target, delta * 3.5)
		else:
			_wiper_time = target # 주차 완료
			
	var sweep := sin(_wiper_time)
	
	# 주차 시 각도 0도(수평), 최대 스윕 시 -85도(거의 수직)
	var angle := lerpf(0.0, -85.0, sweep)
	
	_wiper_pivot_L.rotation = deg_to_rad(angle)
	_wiper_pivot_R.rotation = deg_to_rad(angle)

func _update_shake(speed: float, scroll_z: float, steering_angle: float) -> void:
	# 포커싱 중일 때 쉐이킹 감쇠
	var ease_t := smoothstep(0.0, 1.0, _focus_t)
	var shake_mult := 1.0 - ease_t
	
	var bounce := sin(scroll_z * 15.0) * (speed / SPEED_MAX) * 1.2 * shake_mult
	var sway   := -(steering_angle / 35.0) * 2.5 * shake_mult
	var offset := Vector2(sway, bounce)

	if _impact_t > 0.0:
		var t := _impact_t / IMPACT_TIME
		var kick := t * t
		var ph := float(Time.get_ticks_msec()) * 0.055
		# 충돌 진동은 포커싱 중에도 유지할지 선택 (현재는 같이 감쇠)
		offset += Vector2(sin(ph * 1.7), cos(ph * 2.1)) * (IMPACT_MAG * kick) * shake_mult
	
	if _dash != null:
		_dash.position    = offset
	if _wheel != null:
		_wheel.position   = Vector2(290.0, 660.0) + offset
	if _spd_pivot != null:
		_spd_pivot.position = SPD_GAUGE_CENTER + offset
	if _rpm_pivot != null:
		_rpm_pivot.position = RPM_GAUGE_CENTER + offset

	if _portrait != null and _rearview_node != null:
		var spd_t   := speed / SPEED_MAX
		var mir_x   := (sin(scroll_z * 22.7) * spd_t * 0.8 + sway * 0.3) * shake_mult
		var mir_y   := (cos(scroll_z * 18.3) * spd_t * 0.6) * shake_mult
		
		# 초상화는 왼쪽 아래로 사라짐
		var slide_x := lerpf(0.0, -350.0, ease_t)
		var slide_y := lerpf(0.0, 150.0, ease_t)
		_portrait.position = PORTRAIT_BASE - MIRROR_MIN + Vector2(mir_x + slide_x, mir_y + slide_y)
		
		# 후방 도로는 룸미러에 꽉 차게 기본 스케일 고정
		var base_scale := 0.35
		_rearview_node.scale = Vector2(base_scale, base_scale)
		
		# 룸미러 중심 좌표 (Control 내부 좌표)
		var mirror_center := (MIRROR_MAX - MIRROR_MIN) * 0.5
		# RearviewRenderer가 룸미러에서 보여줄 중심 좌표 
		# (기존 300에서 250으로 낮춰서, 지평선이 거울 아래쪽에 위치하고 하늘/괴물의 상체가 더 많이 보이게 함)
		var rv_center := Vector2(1280.0 * 0.5, 240.0)
		_rearview_node.position = mirror_center - (rv_center * base_scale) + Vector2(mir_x, mir_y)
