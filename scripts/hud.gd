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

# ── 연료 게이지 ────────────────────────────────────────────────
# fuel gauge needle.png이 1×23px(폭 1픽셀)로 육안으로 보이지 않아,
# speed meter needle.png(3×47px)를 재활용하고 스케일만 줄입니다.
const FUEL_GAUGE_CENTER := Vector2(296.0, 555.0)  # RPM과 속도계 사이 작은 게이지
const FUEL_NEEDLE_SCALE := 0.55
const FUEL_ANGLE_MIN    := -65.0   # E (왼쪽, Empty)
const FUEL_ANGLE_MAX    :=  65.0   # F (오른쪽, Full)

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
var _fuel_pivot   : Node2D
var _hud_spd      : Label

# ── 저연료 및 괴물 추격 시각 효과 ──────────────────────────────────
var _low_fuel_overlay : ColorRect
var _monster_vignette : ColorRect
var _fuel_ratio       : float = 1.0
var _sanity_ratio     : float = 1.0

const IMPACT_TIME := 0.22
const IMPACT_MAG  := 9.0
var _impact_t: float = 0.0

const WATCHER_IMPACT_TIME := 0.6
var _watcher_impact_t: float = 0.0

var _focusing: bool = false
var _focus_t: float = 0.0

var _wiper_pivot_L: Node2D
var _wiper_pivot_R: Node2D
var _wiper_state: int = 0
var _z_pressed: bool = false
var _wiper_time: float = 0.0

# ── 포트레이트 깜빡임 ────────────────────────────────────────────────
var _tex_portrait : Texture2D
var _tex_blink_1  : Texture2D
var _tex_blink_2  : Texture2D
var _tex_blink_3  : Texture2D

var _blink_timer: float = 0.0
var _blink_state: int = 0
var _next_blink_time: float = 0.0

# ── 게임오버 / 스테이지 클리어 UI ───────────────────────────────
var _gameover_overlay : ColorRect
var _center_label     : Label

# ── 점퍼 보닛 오버레이 ────────────────────────────────────────
var _jumper_hood_overlay : Sprite2D
var _escape_gauge_bg     : ColorRect
var _escape_gauge_fill   : ColorRect
const ESCAPE_GAUGE_W     := 300.0
const ESCAPE_GAUGE_H     := 10.0
var _jumper_impact_t     : float = 0.0
const JUMPER_IMPACT_TIME := 0.45

# ── 라디오 시스템 ─────────────────────────────────────────
const RADIO_PANEL_POS := Vector2(548.0, 570.0) # 라디오 전체 위치 미세조정용 변수
const RADIO_LCD_OFFSET := Vector2(63.0, 32.0)  # 라디오 패널 내부의 액정(LCD) 오프셋
const RADIO_DIAL_OFFSET := Vector2(27.0, 40.0) # 라디오 패널 내부의 다이얼 오프셋
const RADIO_FREQ_MIN  := 87.5
const RADIO_FREQ_MAX  := 108.0
const WIPER_SWITCH_REL_POS := Vector2(140.0, 5.0) # 핸들 중심 기준 상대 위치 (약간 오른쪽 위)
const RADIO_FREQ_STEP := 0.5
const RADIO_TOTAL_STEPS := 42   # (108.0 - 87.5) / 0.5 + 1

var _radio_panel    : Sprite2D
var _radio_lcd      : Sprite2D
var _radio_dial     : Sprite2D
var _wiper_switch   : Sprite2D
var _radio_freq_label : Label
var _tex_lcd_normal : Texture2D
var _tex_lcd_death  : Texture2D

var _radio_step     : int = 0      # 0 = 87.5 MHz, 205 = 108.0 MHz
var _radio_on_death : bool = true   # 현재 죽음의 주파수인지
var _v_pressed      : bool = false  # V키 토글
var _radio_focus_t  := 0.0          # 라디오 줌을 위한 보간 변수 (0~1)
var _radio_tune_timer := 0.0
const RADIO_TUNE_DELAY := 0.15      # 0.5 스텝에 맞춘 적절한 이동 속도

# 죽음의 주파수 구간 정의 (안전 구간 2개)
var _safe_zones : Array = []  # [[start_step, end_step], ...]

const CLICK_RADIUS := 16.0  # 커서 원의 반지름 (32x32 / 2), 관대한 클릭 판정에 사용

func _ready() -> void:
	_build_jumper_overlay()  # dashboard보다 먼저 추가 → 대시보드 뒤에 렌더
	_build_dashboard()
	_build_wipers()
	_build_portrait_and_mirror()
	_build_needles()
	_build_fuel_needle()
	_build_wheel()
	_build_radio()
	_build_labels()
	_build_visual_overlays()
	_build_stage_overlays()
	_build_wiper_switch()
	_generate_safe_zones(6)  # 스테이지 1 기준: 안전 구간 3.0MHz (6스텝)
	_setup_cursor()
	set_process(true)

func _setup_cursor() -> void:
	# 두께 2px 흰색 속빈 원 커서
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(15.5, 15.5)
	for y in range(32):
		for x in range(32):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if dist >= 13.0 and dist <= 15.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(15, 15))

var _f_toggled      : bool = false  # 거울 줌 토글
var _v_toggled      : bool = false  # 라디오 줌 토글
var _d_toggled      : bool = false  # 계기판 줌 토글
var _dash_focus_t   : float = 0.0   # 계기판 줌을 위한 보간 변수 (0~1)
var _is_dragging_dial : bool = false
var _drag_start_x   : float = 0.0
var _drag_start_step: int = 0
const DASH_GAUGES_RECT := Rect2(90.0, 470.0, 420.0, 190.0)



var _drag_accum : float = 0.0

func _input(event: InputEvent) -> void:
	# ── 키보드 토글 ──
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			if _f_toggled: _f_toggled = false
			else: _v_toggled = false; _f_toggled = true
		elif event.keycode == KEY_V:
			if _v_toggled: _v_toggled = false
			else: _f_toggled = false; _v_toggled = true
		return
			
	# ── 마우스 버튼 ──
	if event is InputEventMouseButton:
		# 클릭 중에는 커서 숨김, 뗄 때 복원
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_f_toggled = false
			_v_toggled = false
			_d_toggled = false
			_is_dragging_dial = false
			return
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var click_glob: Vector2 = event.global_position
				
				# ── A. 라디오 줌 상태일 때 ──
				if _v_toggled:
					# 1. 다이얼 드래그
					if _radio_dial and _radio_dial.get_local_mouse_position().length() < 30.0 + CLICK_RADIUS:
						_is_dragging_dial = true
						_drag_accum = 0.0
						return
					# 2. 패널 클릭 (줌 해제)
					if _radio_panel:
						var lp := _radio_panel.get_local_mouse_position()
						var size := _radio_panel.texture.get_size()
						if Rect2(Vector2.ZERO, size).grow(CLICK_RADIUS).has_point(lp):
							_v_toggled = false
							return
					# 라디오 상태에서는 다른 UI(룸미러 등) 클릭 원천 차단
					return

				# ── B. 룸미러 줌 상태일 때 ──
				if _f_toggled:
					if _mirror_clip and _mirror_clip.get_global_rect().grow(CLICK_RADIUS).has_point(click_glob):
						_f_toggled = false
						return
					# 룸미러 상태에서는 라디오 클릭 차단
					return

				# ── C. 계기판 줌 상태일 때 ──
				if _d_toggled:
					if DASH_GAUGES_RECT.grow(CLICK_RADIUS).has_point(click_glob):
						_d_toggled = false
						return
					return

				# ── D. 평상시 (주행 화면) ──
				# 1. 룸미러 클릭 진입
				if _mirror_clip and _mirror_clip.get_global_rect().grow(CLICK_RADIUS).has_point(click_glob):
					_f_toggled = true
					_v_toggled = false # 상호 배타적
					_d_toggled = false
					return
				
				# 2. 라디오 패널 클릭 진입
				if _radio_panel:
					var lp := _radio_panel.get_local_mouse_position()
					var size := _radio_panel.texture.get_size()
					if Rect2(Vector2.ZERO, size).grow(CLICK_RADIUS).has_point(lp):
						_v_toggled = true
						_f_toggled = false # 상호 배타적
						_d_toggled = false
						return
				
				# 3. 계기판 클릭 진입
				if DASH_GAUGES_RECT.grow(CLICK_RADIUS).has_point(click_glob):
					_d_toggled = true
					_f_toggled = false
					_v_toggled = false
					return

				# 4. 와이퍼 스위치
				if _wiper_switch:
					# 와이퍼 스위치 노드 자체의 로컬 마우스 좌표로 판정
					var lp := _wiper_switch.get_local_mouse_position()
					var size := _wiper_switch.texture.get_size()
					# centered = true 이므로 영역을 -0.5만큼 오프셋
					if Rect2(-size * 0.5, size).grow(CLICK_RADIUS).has_point(lp):
						_wiper_state = (_wiper_state + 1) % 3
						return
			else:
				_is_dragging_dial = false


	# ── 마우스 드래그 (주파수 조작) ──
	if event is InputEventMouseMotion:
		if _is_dragging_dial and _v_toggled:
			_drag_accum += event.relative.x
			if absf(_drag_accum) >= 10.0:
				var steps = int(_drag_accum / 10.0)
				var new_step = clampi(_radio_step + steps, 0, RADIO_TOTAL_STEPS - 1)
				if new_step != _radio_step:
					_radio_step = new_step
					_update_radio_display()
				_drag_accum = fmod(_drag_accum, 10.0)

func _process(delta: float) -> void:
	if _impact_t > 0.0:
		_impact_t = maxf(_impact_t - delta, 0.0)
	if _watcher_impact_t > 0.0:
		_watcher_impact_t = maxf(_watcher_impact_t - delta, 0.0)
	if _jumper_impact_t > 0.0:
		_jumper_impact_t = maxf(_jumper_impact_t - delta, 0.0)

		
	# 포커싱 (거울)
	if _f_toggled:
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
		
	# 라디오 포커싱
	if _v_toggled:
		_radio_focus_t = minf(_radio_focus_t + delta * 5.0, 1.0)
	else:
		_radio_focus_t = maxf(_radio_focus_t - delta * 5.0, 0.0)

	# 계기판 포커싱
	if _d_toggled:
		_dash_focus_t = minf(_dash_focus_t + delta * 5.0, 1.0)
	else:
		_dash_focus_t = maxf(_dash_focus_t - delta * 5.0, 0.0)

	if _wheel != null:
		var ease_dash := smoothstep(0.0, 1.0, _dash_focus_t)
		_wheel.modulate.a = 1.0 - ease_dash

	if _jumper_hood_overlay != null and _jumper_hood_overlay.visible:
		if _jumper_sliding_down:
			_jumper_slide_time -= delta
			var t := clampf(1.0 - (_jumper_slide_time / 0.4), 0.0, 1.0)
			# Slide down
			var y_offset := lerpf(0.0, 500.0, t)
			_jumper_hood_overlay.position = Vector2(640.0 + _jumper_current_sway, 240.0 + y_offset)
			_jumper_hood_overlay.modulate = Color(0.42, 0.42, 0.42, 1.0 - t)
			if _jumper_slide_time <= 0.0:
				_jumper_hood_overlay.visible = false
				_jumper_sliding_down = false
				_watcher_impact_t = WATCHER_IMPACT_TIME
		else:
			_jumper_hood_overlay.scale = Vector2(_jumper_base_sc, _jumper_base_sc)
			_jumper_hood_overlay.modulate = Color(0.42, 0.42, 0.42, 1.0)


			# 관성을 이용한 좌우 흔들림 및 회전 적용
			_jumper_current_sway = lerpf(_jumper_current_sway, _jumper_target_sway, clampf(delta * 4.5, 0.0, 1.0))
			_jumper_hood_overlay.position = Vector2(640.0 + _jumper_current_sway, 240.0)
			_jumper_hood_overlay.rotation = lerpf(_jumper_hood_overlay.rotation, deg_to_rad(_jumper_current_sway * 0.05), clampf(delta * 4.5, 0.0, 1.0))
	else:
		_jumper_target_sway = 0.0
		_jumper_current_sway = 0.0
		if _jumper_hood_overlay != null:
			_jumper_hood_overlay.rotation = 0.0

	_update_wipers(delta)

	_update_portrait_blink(delta)
	_update_death_tint(delta)

var _death_tint_t: float = 0.0  # 0: 정상, 1: 완전 붉은빛

func _update_death_tint(delta: float) -> void:
	if _dash == null: return
	# 죽음의 주파수면 서서히 켜지고, 안전 구간이면 서서히 꺼짐
	if _radio_on_death:
		_death_tint_t = minf(_death_tint_t + delta * 2.0, 1.0)
	else:
		_death_tint_t = maxf(_death_tint_t - delta * 2.0, 0.0)

	# 맥동: 0.08 진폭으로 천천히 흔들림
	var pulse := sin(float(Time.get_ticks_msec()) * 0.002) * 0.08 + 0.92
	var tint_strength := _death_tint_t * pulse
	# modulate: 붉은 채널 유지, 나머지 약간 낮춤
	_dash.modulate = Color(1.0, 1.0 - tint_strength * 0.35, 1.0 - tint_strength * 0.35)

func on_rock_hit() -> void:
	_impact_t = IMPACT_TIME

func on_watcher_hit() -> void:
	_watcher_impact_t = WATCHER_IMPACT_TIME

func _build_portrait_and_mirror() -> void:
	_mirror_clip = Control.new()
	_mirror_clip.position = MIRROR_MIN
	_mirror_clip.size = MIRROR_MAX - MIRROR_MIN
	_mirror_clip.clip_contents = true
	_mirror_clip.show_behind_parent = true
	if _dash != null:
		_dash.add_child(_mirror_clip)
	else:
		add_child(_mirror_clip)
	
	_rearview_node = RearviewRenderer.new()
	_rearview_node.modulate = Color(0.95, 0.95, 1.0)
	_mirror_clip.add_child(_rearview_node)
	
	_tex_portrait = load("res://Asset/Image/Portrait.png")
	_tex_blink_1  = load("res://Asset/Image/Portrait_blink_01.png")
	_tex_blink_2  = load("res://Asset/Image/Portrait_blink_02.png")
	_tex_blink_3  = load("res://Asset/Image/Portrait_blink_03.png")

	_portrait = Sprite2D.new()
	if _tex_portrait:
		_portrait.texture = _tex_portrait
		_portrait.centered = false
		_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_portrait.scale = Vector2(1.0, 1.0)
		_portrait.position = PORTRAIT_BASE - MIRROR_MIN
		_portrait.modulate = Color(0.78, 0.83, 0.90)
	_mirror_clip.add_child(_portrait)
	
	_next_blink_time = randf_range(2.0, 4.0)

func _build_wipers() -> void:
	# 와이퍼 크기가 커진 것을 감안하되 실제 탠덤 와이퍼처럼 닦이는 영역이 겹치도록 간격 조정
	_wiper_pivot_L = _make_wiper_assembly(Vector2(280.0, 450.0))
	_wiper_pivot_R = _make_wiper_assembly(Vector2(720.0, 450.0))

func _make_wiper_assembly(pos: Vector2) -> Node2D:
	var scale_inv := Vector2(1.0, 1.0)
	if _dash != null:
		scale_inv = Vector2(1.0 / _dash.scale.x, 1.0 / _dash.scale.y)
		
	var pivot := Node2D.new()
	pivot.position = pos * scale_inv
	pivot.scale = Vector2(1.3, 1.3) * scale_inv  # 와이퍼 크기 1.3배 증가 + 스케일 보정
	pivot.show_behind_parent = true # 대시보드 뒤에 그려지도록 설정
	
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
	
	if _dash != null:
		_dash.add_child(pivot)
	else:
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
			1280.0 / (float(tex.get_width()) - 200.0),
			720.0  / (float(tex.get_height()) - 200.0)
		)
		_dash.offset = Vector2(-100.0, -100.0)
	add_child(_dash)

func _build_radio() -> void:
	if _dash == null: return
	
	# 대시보드가 스케일되어 있으므로, 화면 좌표를 대시보드 로컬 좌표로 변환
	var scale_inv := Vector2(1.0 / _dash.scale.x, 1.0 / _dash.scale.y)
	
	# 라디오 패널 (206x72px)
	_radio_panel = Sprite2D.new()
	var tex_panel := load("res://Asset/Image/radio_panel.png") as Texture2D
	if tex_panel:
		_radio_panel.texture = tex_panel
		_radio_panel.centered = false
		_radio_panel.position = RADIO_PANEL_POS * scale_inv
		_radio_panel.scale = scale_inv
		_radio_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dash.add_child(_radio_panel)
	
	# 라디오 LCD (100x20px) — 패널 내 오프셋 (48, 30)
	_tex_lcd_normal = load("res://Asset/Image/radio_lcd_normal.png") as Texture2D
	_tex_lcd_death  = load("res://Asset/Image/radio_lcd_death.png") as Texture2D
	
	_radio_lcd = Sprite2D.new()
	if _tex_lcd_death:
		_radio_lcd.texture = _tex_lcd_death
	_radio_lcd.centered = false
	_radio_lcd.position = (RADIO_PANEL_POS + RADIO_LCD_OFFSET) * scale_inv
	_radio_lcd.scale = scale_inv
	_radio_lcd.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dash.add_child(_radio_lcd)
	
	# 주파수 표시 라벨 (LCD 위에 오버레이)
	_radio_freq_label = Label.new()
	_radio_freq_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_freq_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radio_freq_label.position = (RADIO_PANEL_POS + RADIO_LCD_OFFSET) * scale_inv
	_radio_freq_label.size = Vector2(100.0, 20.0)
	_radio_freq_label.scale = scale_inv
	_radio_freq_label.add_theme_font_size_override("font_size", 14)
	_radio_freq_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	_dash.add_child(_radio_freq_label)
	
	# 다이얼 (16x16px) — 패널 우측 하단으로 이동
	_radio_dial = Sprite2D.new()
	var tex_dial := load("res://Asset/Image/radio_dial.png") as Texture2D
	if tex_dial:
		_radio_dial.texture = tex_dial
		_radio_dial.centered = true
		_radio_dial.position = (RADIO_PANEL_POS + RADIO_DIAL_OFFSET) * scale_inv
		_radio_dial.scale = scale_inv
		_radio_dial.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dash.add_child(_radio_dial)
	_update_radio_display()

func _build_wiper_switch() -> void:
	if _wheel == null: return
	
	_wiper_switch = Sprite2D.new()
	var tex := load("res://Asset/Image/wiper_switch.png") as Texture2D
	if tex:
		_wiper_switch.texture = tex
		_wiper_switch.centered = true
		_wiper_switch.position = WIPER_SWITCH_REL_POS
		_wiper_switch.show_behind_parent = true # 핸들 뒤로 배치
		_wiper_switch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_wheel.add_child(_wiper_switch)

## 안전 구간 생성 (스테이지에 따라 폭이 달라짐)
func _generate_safe_zones(safe_width: int) -> void:
	_safe_zones.clear()
	# 2개의 안전 구간을 전체 스텝(42개) 내에 랜덤 배치
	var zone1_start := randi_range(2, 18 - safe_width)
	var zone2_start := randi_range(22, 38 - safe_width)
	_safe_zones.append([zone1_start, zone1_start + safe_width - 1])
	_safe_zones.append([zone2_start, zone2_start + safe_width - 1])
	_update_radio_display()

## 현재 주파수가 안전 구간인지 확인
func _is_safe_frequency() -> bool:
	for zone in _safe_zones:
		if _radio_step >= int(zone[0]) and _radio_step <= int(zone[1]):
			return true
	return false

## 라디오 표시 업데이트 (LCD 텍스처, 주파수 텍스트, 다이얼 회전)
func _update_radio_display() -> void:
	var freq := RADIO_FREQ_MIN + _radio_step * RADIO_FREQ_STEP
	
	# 주파수 텍스트 갱신
	if _radio_freq_label:
		_radio_freq_label.text = "%.1f FM" % freq
	
	# 안전/죽음 구간 판별
	_radio_on_death = not _is_safe_frequency()
	
	# LCD 텍스처 변경
	if _radio_lcd:
		if _radio_on_death:
			_radio_lcd.texture = _tex_lcd_death
			if _radio_freq_label:
				_radio_freq_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
		else:
			_radio_lcd.texture = _tex_lcd_normal
			if _radio_freq_label:
				_radio_freq_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	
	# 다이얼 회전: 9시(-90°) ~ 3시(+90°)
	if _radio_dial:
		var t := float(_radio_step) / float(RADIO_TOTAL_STEPS - 1)
		var angle := lerpf(-90.0, 90.0, t)
		_radio_dial.rotation = deg_to_rad(angle)

## 라디오가 죽음의 주파수인지 외부에서 확인
func get_radio_on_death() -> bool:
	return _radio_on_death

## 스테이지별 안전 구간 폭 업데이트
func update_radio_for_stage(stage: int) -> void:
	# 스테이지 1~6: 0.5 MHz 스텝 단위의 안전구간 스텝 수 (3.0, 2.0, 1.5, 1.0, 1.0, 0.5 MHz)
	var widths := [6, 4, 3, 2, 2, 1]
	var w := int(widths[clampi(stage - 1, 0, 5)])
	_generate_safe_zones(w)


func _build_needles() -> void:
	_spd_pivot = _make_needle_pivot(SPD_GAUGE_CENTER, "res://Asset/Image/speed meter needle.png", NEEDLE_SCALE)
	_spd_pivot.rotation = deg_to_rad(-120.0)
	_rpm_pivot = _make_needle_pivot(RPM_GAUGE_CENTER, "res://Asset/Image/speed meter needle.png", NEEDLE_SCALE)
	_rpm_pivot.rotation = deg_to_rad(-120.0)

func _build_fuel_needle() -> void:
	# fuel gauge needle.png이 1×23px로 너무 작아 보이지 않으므로, speed meter needle을 재활용
	_fuel_pivot = _make_needle_pivot(FUEL_GAUGE_CENTER, "res://Asset/Image/speed meter needle.png", FUEL_NEEDLE_SCALE)
	_fuel_pivot.rotation = deg_to_rad(FUEL_ANGLE_MAX)  # 시작: Full(오른쪽)

func _make_needle_pivot(center: Vector2, tex_path: String, sc: float) -> Node2D:
	var pivot := Node2D.new()
	pivot.position = center
	var needle := Sprite2D.new()
	var tex := load(tex_path) as Texture2D
	if tex:
		needle.texture = tex
		needle.centered = false
		needle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		needle.scale = Vector2(sc, sc)
		needle.position = Vector2(
			-float(tex.get_width())  * sc * 0.5,
			-float(tex.get_height()) * sc
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
	help.text = "W/S: 가속·감속   A/D: 좌우 이동   F: 뒤보기   Z: 와이퍼   V: 라디오 조작"
	add_child(help)


## 시각 효과 오버레이 생성 (저연료, 괴물 추격)
func _build_visual_overlays() -> void:
	# 연료 40% 이하: 화면 하단 서서히 어두워짐
	_low_fuel_overlay = ColorRect.new()
	_low_fuel_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_low_fuel_overlay.position = Vector2(0.0, 360.0)
	_low_fuel_overlay.size = Vector2(1280.0, 360.0)
	_low_fuel_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_low_fuel_overlay)

	# 괴물 접근 시: 적색 비네트
	_monster_vignette = ColorRect.new()
	_monster_vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	_monster_vignette.position = Vector2.ZERO
	_monster_vignette.size = Vector2(1280.0, 720.0)
	_monster_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_monster_vignette)

## 게임오버 / 스테이지 클리어 오버레이 생성
func _build_stage_overlays() -> void:
	# 전체 화면 검은색 오버레이 (게임오버 암전용)
	_gameover_overlay = ColorRect.new()
	_gameover_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_gameover_overlay.position = Vector2.ZERO
	_gameover_overlay.size = Vector2(1280.0, 720.0)
	_gameover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameover_overlay.visible = false
	add_child(_gameover_overlay)
	
	# 중앙 텍스트 라벨 (GAME OVER / STAGE CLEAR)
	_center_label = Label.new()
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.position = Vector2(0.0, 0.0)
	_center_label.size = Vector2(1280.0, 720.0)
	_center_label.add_theme_font_size_override("font_size", 48)
	_center_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	_center_label.visible = false
	add_child(_center_label)

var _jumper_base_sc : float = 1.0
var _jumper_hood_time : float = 0.0

## 점퍼 보닛 오버레이 생성 (dashboard보다 먼저 _ready에서 호출)
func _build_jumper_overlay() -> void:
	# 보닛 위 점퍼 스프라이트 (도로 뷰 하단 중앙)
	_jumper_hood_overlay = Sprite2D.new()
	var tex := load("res://Asset/Image/Character/jumper_hold_01.png") as Texture2D
	if tex:
		_jumper_hood_overlay.texture = tex
		_jumper_hood_overlay.centered = true
		_jumper_hood_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 세로 기준으로 스케일 설정 (화면에 크게)
		var target_h := 1350.0
		var sc := target_h / float(tex.get_height())
		_jumper_base_sc = sc
		_jumper_hood_overlay.scale = Vector2(sc, sc)
	_jumper_hood_overlay.position = Vector2(640.0, 240.0)
	_jumper_hood_overlay.visible = false
	add_child(_jumper_hood_overlay)




	# 탈출 게이지 배경
	_escape_gauge_bg = ColorRect.new()
	_escape_gauge_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	_escape_gauge_bg.size = Vector2(ESCAPE_GAUGE_W, ESCAPE_GAUGE_H)
	_escape_gauge_bg.position = Vector2(640.0 - ESCAPE_GAUGE_W * 0.5, 310.0)
	_escape_gauge_bg.visible = false
	add_child(_escape_gauge_bg)

	# 탈출 게이지 채우기
	_escape_gauge_fill = ColorRect.new()
	_escape_gauge_fill.color = Color(0.9, 0.7, 0.1, 0.9)
	_escape_gauge_fill.size = Vector2(0.0, ESCAPE_GAUGE_H)
	_escape_gauge_fill.position = Vector2(640.0 - ESCAPE_GAUGE_W * 0.5, 310.0)
	_escape_gauge_fill.visible = false
	add_child(_escape_gauge_fill)

var _jumper_target_sway : float = 0.0
var _jumper_current_sway : float = 0.0

func sway_jumper(angle: float) -> void:
	_jumper_target_sway = angle * -2.4

var _jumper_sliding_down: bool = false
var _jumper_slide_time: float = 0.0

## 보닛 위 점퍼 표시/숨김
func set_jumper_on_hood(on: bool) -> void:
	if _jumper_hood_overlay:
		if on:
			_jumper_hood_overlay.visible = true
			_jumper_hood_time = 0.0
			_jumper_sliding_down = false
			_jumper_slide_time = 0.0
			_jumper_hood_overlay.modulate = Color(0.42, 0.42, 0.42, 1.0)
			_jumper_impact_t = JUMPER_IMPACT_TIME
		else:
			if _jumper_hood_overlay.visible and not _jumper_sliding_down:
				_jumper_sliding_down = true
				_jumper_slide_time = 0.4
			else:
				_jumper_hood_overlay.visible = false
				_jumper_sliding_down = false

	if _escape_gauge_bg:
		_escape_gauge_bg.visible = on
	if _escape_gauge_fill:
		_escape_gauge_fill.visible = on
	if not on and _escape_gauge_fill:
		_escape_gauge_fill.size.x = 0.0



## 탈출 게이지 진행률 갱신 (0.0 ~ 1.0)
func update_escape_gauge(ratio: float) -> void:
	if _escape_gauge_fill:
		_escape_gauge_fill.size.x = ESCAPE_GAUGE_W * clampf(ratio, 0.0, 1.0)

## 게임오버 표시
func show_gameover() -> void:
	_gameover_overlay.visible = true
	_center_label.visible = true
	_center_label.text = ""  # 암전 후에 텍스트 표시

## 게임오버 암전 진행 (0~1)
func set_gameover_fade(t: float) -> void:
	_gameover_overlay.color.a = t
	if t >= 0.8 and _center_label.text == "":
		_center_label.text = "GAME OVER\n\n괴물에게 따라잡혔다."
		_center_label.add_theme_font_size_override("font_size", 48)

## 스테이지 클리어 표시
func show_stage_clear(stage: int, is_final: bool) -> void:
	_gameover_overlay.visible = true
	_gameover_overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	_center_label.visible = true
	if is_final:
		_center_label.text = "STAGE %d CLEAR\n\n...목적지에 도달했다." % stage
	else:
		_center_label.text = "STAGE %d CLEAR\n\n다음 구간으로 이동 중..." % stage
	_center_label.add_theme_font_size_override("font_size", 42)

## 스테이지 오버레이 숨김
func hide_stage_overlay() -> void:
	_gameover_overlay.visible = false
	_gameover_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_center_label.visible = false
	_center_label.text = ""

# ── 외부에서 매 프레임 호출 (차량 상태 갱신) ─────────────────────
func update(speed: float, scroll_z: float, steering_angle: float, rpm: float, monster_distance: float, delta: float, fuel_ratio: float, sanity_ratio: float = 1.0, stage: int = 1, stage_dist: float = 0.0, stage_len: float = 600.0) -> void:
	_fuel_ratio = fuel_ratio
	_sanity_ratio = sanity_ratio
	
	_update_gauges(speed, rpm, fuel_ratio)
	_update_shake(speed, scroll_z, steering_angle)
	_update_visual_effects(monster_distance)
	if _wheel != null:
		_wheel.rotation = deg_to_rad(steering_angle)
	if _hud_spd != null:
		var progress := clampf(stage_dist / stage_len, 0.0, 1.0) * 100.0
		_hud_spd.text = "ST%d [%.0f%%]  |  %.0f km/h  |  연료: %.1f L  |  정신력: %.0f%%  |  괴물: %.1f" % [stage, progress, speed, fuel_ratio * 40.0, sanity_ratio * 100.0, monster_distance]
		
	if _rearview_node != null:
		_rearview_node.update_state(scroll_z, monster_distance, delta)

func _update_gauges(speed: float, rpm: float, fuel_ratio: float = 1.0) -> void:
	if _spd_pivot != null:
		var t := clampf(speed / SPEED_MAX, 0.0, 1.0)
		_spd_pivot.rotation = deg_to_rad(lerpf(SPD_ANGLE_MIN, SPD_ANGLE_MAX, t))
	if _rpm_pivot != null:
		var t := clampf((rpm - RPM_IDLE) / (RPM_REDLINE - RPM_IDLE), 0.0, 1.0)
		_rpm_pivot.rotation = deg_to_rad(lerpf(RPM_ANGLE_MIN, RPM_ANGLE_MAX, t))
	if _fuel_pivot != null:
		# fuel_ratio 1.0 = Full(오른쪽), 0.0 = Empty(왼쪽)
		var ft := clampf(fuel_ratio, 0.0, 1.0)
		_fuel_pivot.rotation = deg_to_rad(lerpf(FUEL_ANGLE_MIN, FUEL_ANGLE_MAX, ft))


## 상태별 시각 효과 업데이트
func _update_visual_effects(monster_distance: float) -> void:
	# 연료 40% 이하: 화면 하단 어두워짐 (저연료 표시)
	if _low_fuel_overlay != null:
		var dark_alpha := 0.0
		if _fuel_ratio < 0.40:
			# 40%→0% 에서 투명도 0→0.55
			dark_alpha = lerpf(0.0, 0.55, 1.0 - _fuel_ratio / 0.40)
		_low_fuel_overlay.color = Color(0.0, 0.0, 0.0, dark_alpha)

	# 괴물 거리 30.0 이하: 적색 비네트 깜빡임 (가까워질수록 강해짐)
	if _monster_vignette != null:
		var vig_alpha := 0.0
		if monster_distance < 30.0:
			# 30.0 → 0.0 에서 투명도 0 → 0.4, 빠른 맥동 효과
			var base_a := lerpf(0.0, 0.40, 1.0 - monster_distance / 30.0)
			# 거리가 가까울수록 깜빡이는 속도도 증가
			var pulse_speed := lerpf(0.004, 0.012, 1.0 - monster_distance / 30.0)
			var pulse := (sin(float(Time.get_ticks_msec()) * pulse_speed) + 1.0) * 0.5
			vig_alpha = base_a * (0.4 + pulse * 0.6)
		_monster_vignette.color = Color(0.6, 0.0, 0.0, vig_alpha)

func _update_wipers(delta: float) -> void:
	if _wiper_pivot_L == null or _wiper_pivot_R == null:
		return
		
	var speed_mult := 0.0
	if _wiper_state == 1:
		speed_mult = 1.0 # 1단
	elif _wiper_state == 2:
		speed_mult = 2.0 # 2단
		
	if _wiper_state > 0:
		_wiper_time += delta * speed_mult * 1.75  # 기존 3.5에서 절반으로 낮춤
	else:
		# 정지: 가장 가까운 정수 PI 배수로 스무스하게 이동 (제자리 주차)
		var target := ceilf(_wiper_time / PI) * PI
		if _wiper_time < target - 0.01:
			_wiper_time = move_toward(_wiper_time, target, delta * 2.5)
		else:
			_wiper_time = target # 주차 완료
			
	# sin 제곱을 사용하면 0 ~ 1 사이를 부드럽게 왕복하며 튕기는 현상이 없음
	var sweep := sin(_wiper_time) * sin(_wiper_time)
	
	# 실제 차량 와이퍼처럼 대기 상태(-5도)에서 거의 수직 이상(-110도)까지 넓게 닦도록 수정
	var angle := lerpf(-5.0, -110.0, sweep)
	
	_wiper_pivot_L.rotation = deg_to_rad(angle)
	_wiper_pivot_R.rotation = deg_to_rad(angle)

func _update_portrait_blink(delta: float) -> void:
	if _portrait == null: return
	
	_blink_timer += delta
	if _blink_state == 0: # 평소 상태 (디폴트: portrait)
		if _blink_timer >= _next_blink_time:
			_blink_state = 1
			_blink_timer = 0.0
			if _tex_blink_1: _portrait.texture = _tex_blink_1
	elif _blink_state == 1: # 눈 감기 시작 (1)
		if _blink_timer >= 0.02:
			_blink_state = 2
			_blink_timer = 0.0
			if _tex_blink_2: _portrait.texture = _tex_blink_2
	elif _blink_state == 2: # 눈 감는 중 (2)
		if _blink_timer >= 0.02:
			_blink_state = 3
			_blink_timer = 0.0
			if _tex_blink_3: _portrait.texture = _tex_blink_3
	elif _blink_state == 3: # 완전히 감음 (3)
		if _blink_timer >= 0.04:
			_blink_state = 4
			_blink_timer = 0.0
			# 눈 뜰 때는 1단계를 거쳐 빠르게 복귀
			if _tex_blink_1: _portrait.texture = _tex_blink_1
	elif _blink_state == 4: # 눈 뜨는 중 (1)
		if _blink_timer >= 0.02:
			_blink_state = 0
			_blink_timer = 0.0
			if _tex_portrait: _portrait.texture = _tex_portrait
			
			# 정신력에 따른 눈 깜빡임 빈도 및 틱(경련) 조절
			var double_blink_chance = lerpf(0.6, 0.1, _sanity_ratio) # 낮을수록(0.0) 60% 확률로 연속 깜빡임
			var min_wait = lerpf(0.5, 2.0, _sanity_ratio)
			var max_wait = lerpf(1.5, 5.0, _sanity_ratio)
			
			if randf() < double_blink_chance:
				_next_blink_time = randf_range(0.05, 0.2) # 빠른 연속 깜빡임(불안한 틱)
			else:
				_next_blink_time = randf_range(min_wait, max_wait)

	# ── 안색 변화 (정신력에 따른 창백함) ──
	# 정상: (0.78, 0.83, 0.90) / 패닉: (0.35, 0.40, 0.50)
	var r = lerpf(0.35, 0.78, _sanity_ratio)
	var g = lerpf(0.40, 0.83, _sanity_ratio)
	var b = lerpf(0.50, 0.90, _sanity_ratio)
	_portrait.modulate = Color(r, g, b)

func _update_shake(speed: float, scroll_z: float, steering_angle: float) -> void:
	# 포커싱 중일 때 쉐이킹 감쇠
	var ease_t := maxf(maxf(smoothstep(0.0, 1.0, _focus_t), smoothstep(0.0, 1.0, _radio_focus_t)), smoothstep(0.0, 1.0, _dash_focus_t))
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
		
	if _watcher_impact_t > 0.0:
		# 와쳐 충돌: 차가 위로 붕 떴다가 덜컹거리는 느낌 (큰 진폭)
		var t := _watcher_impact_t / WATCHER_IMPACT_TIME
		var kick := t * t
		var bounce_y := sin(t * PI) * 35.0  # 위로 35px 솟구침
		var shake_y  := sin(t * 30.0) * 10.0 * kick # 거친 덜덜거림
		offset += Vector2(0.0, -bounce_y + shake_y) * shake_mult

	if _jumper_impact_t > 0.0:
		# 점퍼 착지: 차가 아래로 쿵 내려앉았다가 위로 퉁 솟구치는 느낌 (아래에서 위로)
		var t := _jumper_impact_t / JUMPER_IMPACT_TIME
		var jiggle := sin((1.0 - t) * PI * 2.0) * 55.0 * t
		offset += Vector2(0.0, jiggle) * shake_mult


	if _dash != null:
		_dash.position    = offset
		
		if _wiper_pivot_L != null and _wiper_pivot_R != null:
			var scale_inv := Vector2(1.0 / _dash.scale.x, 1.0 / _dash.scale.y)
			# 와이퍼가 대시보드에 달려있지만 살짝 덜렁거리는 느낌을 주기 위한 미세 진동
			var wiper_jiggle := Vector2(
				sin(scroll_z * 18.0) * (speed / SPEED_MAX) * 2.0 * shake_mult,
				cos(scroll_z * 20.0) * (speed / SPEED_MAX) * 1.5 * shake_mult
			)
			if _watcher_impact_t > 0.0:
				var t := _watcher_impact_t / WATCHER_IMPACT_TIME
				var kick := t * t
				wiper_jiggle.y += sin(t * 40.0) * 12.0 * kick
				wiper_jiggle.x += cos(t * 35.0) * 8.0 * kick
			elif _impact_t > 0.0:
				var t := _impact_t / IMPACT_TIME
				var kick := t * t
				var ph := float(Time.get_ticks_msec()) * 0.055
				wiper_jiggle += Vector2(sin(ph * 2.5), cos(ph * 3.0)) * (IMPACT_MAG * 0.8 * kick)
			
			_wiper_pivot_L.position = (Vector2(280.0, 450.0) + wiper_jiggle) * scale_inv
			_wiper_pivot_R.position = (Vector2(720.0, 450.0) + wiper_jiggle) * scale_inv
	if _wheel != null:
		_wheel.position   = Vector2(290.0, 660.0) + offset
	if _spd_pivot != null:
		_spd_pivot.position = SPD_GAUGE_CENTER + offset
	if _rpm_pivot != null:
		_rpm_pivot.position = RPM_GAUGE_CENTER + offset
	if _fuel_pivot != null:
		_fuel_pivot.position = FUEL_GAUGE_CENTER + offset
	if _mirror_clip != null:
		_mirror_clip.position = MIRROR_MIN

	if _portrait != null and _rearview_node != null:
		var spd_t   := speed / SPEED_MAX
		var mir_x   := (sin(scroll_z * 22.7) * spd_t * 0.8 + sway * 0.3) * shake_mult
		var mir_y   := (cos(scroll_z * 18.3) * spd_t * 0.6) * shake_mult
		
		# ── 불안감 (미세한 떨림) ──
		var anxiety_shake_x := 0.0
		if _sanity_ratio < 0.5:
			var shake_intensity = (0.5 - _sanity_ratio) * 4.0 # 최대 2픽셀
			if randf() < 0.5:
				anxiety_shake_x = randf_range(-shake_intensity, shake_intensity) * shake_mult
		
		# 초상화는 왼쪽 아래로 사라짐
		var slide_x := lerpf(0.0, -350.0, ease_t)
		var slide_y := lerpf(0.0, 150.0, ease_t)
		_portrait.position = PORTRAIT_BASE - MIRROR_MIN + Vector2(mir_x + slide_x + anxiety_shake_x, mir_y + slide_y)
		
		# 후방 도로는 룸미러에 꽉 차게 기본 스케일 고정
		var base_scale := 0.35
		_rearview_node.scale = Vector2(base_scale, base_scale)
		
		# 룸미러 중심 좌표 (Control 내부 좌표)
		var mirror_center := (MIRROR_MAX - MIRROR_MIN) * 0.5
		# RearviewRenderer가 룸미러에서 보여줄 중심 좌표 
		# (기존 300에서 250으로 낮춰서, 지평선이 거울 아래쪽에 위치하고 하늘/괴물의 상체가 더 많이 보이게 함)
		var rv_center := Vector2(1280.0 * 0.5, 240.0)
		_rearview_node.position = mirror_center - (rv_center * base_scale) + Vector2(mir_x, mir_y)
