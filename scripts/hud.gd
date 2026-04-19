extends CanvasLayer

# ╔══════════════════════════════════════════════════════════╗
# ║  ★ 룸미러 마스킹 조정 — 여기서만 수정하세요            ║
# ╠══════════════════════════════════════════════════════════╣
# ║  MIRROR_MIN/MAX : 미러 투명 영역 좌상단/우하단 (픽셀)   ║
# ║    x 범위 → 좌우 클립   y 범위 → 상하 클립             ║
# ║  PORTRAIT_BASE  : 초상화 좌상단 위치                    ║
# ║    x 크게 → 얼굴 왼쪽 부분 표시                        ║
# ║    x 작게 → 얼굴 오른쪽 부분 표시                      ║
# ║    y 작게(더 음수) → 얼굴 위쪽(이마·눈) 표시           ║
# ║    y 크게(0에 가깝게) → 얼굴 아래쪽(코·입) 표시        ║
# ╚══════════════════════════════════════════════════════════╝
const MIRROR_MIN    := Vector2(535.0,  44.0)
const MIRROR_MAX    := Vector2(795.0, 118.0)
const PORTRAIT_BASE := Vector2(500.0, -90.0)
const PORTRAIT_W    := 335.0
const PORTRAIT_H    := 450.0

# ╔══════════════════════════════════════════════════════════╗
# ║  ★ 계기판 바늘 — 여기서만 수정하세요                   ║
# ╠══════════════════════════════════════════════════════════╣
# ║  _GAUGE_CENTER : 바늘 피벗 위치 (x크게→오른쪽, y크게→아래)║
# ║  NEEDLE_SCALE  : 바늘 크기 (1.0 = 원본 3×47px)         ║
# ║  _ANGLE_MIN    : 0(공회전) 위치 각도 (도, 음수=왼쪽)   ║
# ║  _ANGLE_MAX    : 최댓값 위치 각도 (도, 양수=오른쪽)    ║
# ╚══════════════════════════════════════════════════════════╝
const SPD_GAUGE_CENTER := Vector2(422.0, 569.0)
const RPM_GAUGE_CENTER := Vector2(172.0, 569.0)
const NEEDLE_SCALE     := 1.0
const SPD_ANGLE_MIN    := -120.0   # 0 km/h 바늘 위치
const SPD_ANGLE_MAX    :=  120.0   # 240 km/h 바늘 위치
const RPM_ANGLE_MIN    := -120.0   # 공회전 바늘 위치
const RPM_ANGLE_MAX    :=  120.0   # 레드라인 바늘 위치

# ── 계기 표시 범위 ───────────────────────────────────────────
const SPEED_MAX   := 240.0
const RPM_IDLE    := 800.0
const RPM_REDLINE := 7200.0

# ── 노드 참조 ────────────────────────────────────────────────
var _portrait     : Sprite2D
var _portrait_mat : ShaderMaterial
var _dash         : Sprite2D
var _wheel        : Sprite2D
var _spd_pivot    : Node2D
var _rpm_pivot    : Node2D
var _hud_spd      : Label

func _ready() -> void:
	_build_portrait()
	_build_dashboard()
	_build_needles()
	_build_wheel()
	_build_labels()

# ── 초상화 ───────────────────────────────────────────────────
func _build_portrait() -> void:
	_portrait = Sprite2D.new()
	var tex := load("res://Asset/Image/Portrait.png") as Texture2D
	if tex:
		_portrait.texture = tex
		_portrait.centered = false
		_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_portrait.scale = Vector2(1.0, 1.0)
		_portrait.position = PORTRAIT_BASE

	_portrait_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 clip_min_uv;
uniform vec2 clip_max_uv;
void fragment() {
	if (UV.x < clip_min_uv.x || UV.x > clip_max_uv.x ||
		UV.y < clip_min_uv.y || UV.y > clip_max_uv.y) {
		discard;
	}
	vec4 c = texture(TEXTURE, UV);
	vec3 tint = vec3(0.78, 0.83, 0.90);
	COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), vec4(c.rgb * tint, 1.0), c.a);
}
"""
	_portrait_mat.shader = shader
	_portrait_mat.set_shader_parameter("clip_min_uv", Vector2(
		(MIRROR_MIN.x - PORTRAIT_BASE.x) / PORTRAIT_W,
		(MIRROR_MIN.y - PORTRAIT_BASE.y) / PORTRAIT_H
	))
	_portrait_mat.set_shader_parameter("clip_max_uv", Vector2(
		(MIRROR_MAX.x - PORTRAIT_BASE.x) / PORTRAIT_W,
		(MIRROR_MAX.y - PORTRAIT_BASE.y) / PORTRAIT_H
	))
	_portrait.material = _portrait_mat
	add_child(_portrait)

# ── 대시보드 ─────────────────────────────────────────────────
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

# ── 계기 바늘 ────────────────────────────────────────────────
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

# ── 핸들 ─────────────────────────────────────────────────────
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

# ── 라벨 ─────────────────────────────────────────────────────
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
	help.text = "W/S: 가속·감속   A/D: 좌우 이동"
	add_child(help)

# ── 매 프레임 갱신 ───────────────────────────────────────────
func update(speed: float, scroll_z: float, steering_angle: float, rpm: float) -> void:
	_update_gauges(speed, rpm)
	_update_shake(speed, scroll_z, steering_angle)
	if _wheel != null:
		_wheel.rotation = deg_to_rad(steering_angle)
	if _hud_spd != null:
		_hud_spd.text = "%.0f km/h" % speed

func _update_gauges(speed: float, rpm: float) -> void:
	if _spd_pivot != null:
		var t := clampf(speed / SPEED_MAX, 0.0, 1.0)
		_spd_pivot.rotation = deg_to_rad(lerpf(SPD_ANGLE_MIN, SPD_ANGLE_MAX, t))
	if _rpm_pivot != null:
		var t := clampf((rpm - RPM_IDLE) / (RPM_REDLINE - RPM_IDLE), 0.0, 1.0)
		_rpm_pivot.rotation = deg_to_rad(lerpf(RPM_ANGLE_MIN, RPM_ANGLE_MAX, t))

func _update_shake(speed: float, scroll_z: float, steering_angle: float) -> void:
	# 대시보드·핸들·바늘: 노면 충격 진동
	var bounce := sin(scroll_z * 15.0) * (speed / SPEED_MAX) * 1.2
	var sway   := -(steering_angle / 35.0) * 2.5
	var offset := Vector2(sway, bounce)
	if _dash != null:
		_dash.position    = offset
	if _wheel != null:
		_wheel.position   = Vector2(290.0, 660.0) + offset
	if _spd_pivot != null:
		_spd_pivot.position = SPD_GAUGE_CENTER + offset
	if _rpm_pivot != null:
		_rpm_pivot.position = RPM_GAUGE_CENTER + offset

	# 룸미러 초상화: 다른 주파수로 독립 진동
	if _portrait != null:
		var spd_t   := speed / SPEED_MAX
		var mir_x   := sin(scroll_z * 22.7) * spd_t * 0.8 + sway * 0.3
		var mir_y   := cos(scroll_z * 18.3) * spd_t * 0.6
		_portrait.position = PORTRAIT_BASE + Vector2(mir_x, mir_y)
