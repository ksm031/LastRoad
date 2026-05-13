extends RefCounted
class_name CrtTheme

# ── CRT 인산체 앰버 컬러 팔레트 ─────────────────────────────
const BG_BLACK     := Color(0.0, 0.0, 0.0, 0.97)
const BG_PANEL     := Color(0.03, 0.03, 0.02, 0.95)

const AMBER        := Color(0.93, 0.85, 0.55)      # 기본 텍스트
const AMBER_BRIGHT := Color(0.98, 0.93, 0.72)      # 강조 텍스트
const AMBER_MID    := Color(0.70, 0.63, 0.40)      # 보조 텍스트
const AMBER_DIM    := Color(0.40, 0.36, 0.22)      # 비활성/뮤트
const AMBER_BORDER := Color(0.55, 0.50, 0.30, 0.8) # 테두리

const GREEN_DATA   := Color(0.45, 0.90, 0.45)      # 데이터/수치
const RED_WARN     := Color(0.90, 0.30, 0.20)      # 경고/삭제
const CYAN_INFO    := Color(0.40, 0.80, 0.90)      # 정보 강조

const SLOT_EMPTY   := Color(0.12, 0.11, 0.09)      # 빈 슬롯 (밝게 하여 그리드 구분)
const SLOT_HOVER   := Color(0.18, 0.16, 0.12)      # 호버
const SLOT_BORDER  := Color(0.30, 0.27, 0.18, 0.6)

# ── 폰트 로딩 ──────────────────────────────────────────────
static var _font_cache: Font = null

static func get_font() -> Font:
	if _font_cache != null:
		return _font_cache
	var path := "res://Font/NeoDunggeunmoPro-Regular.ttf"
	if ResourceLoader.exists(path):
		_font_cache = load(path) as Font
	return _font_cache

# ── 라벨에 CRT 스타일 적용 ─────────────────────────────────
static func style_label(lbl: Label, font_size: int = 14, color: Color = AMBER) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	var f := get_font()
	if f:
		lbl.add_theme_font_override("font", f)

# ── CRT 스타일 버튼 StyleBox 생성 ─────────────────────────
static func make_button_style(bg_color: Color = Color(0.08, 0.08, 0.05), border_color: Color = AMBER_BORDER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.border_color = border_color
	s.border_width_left = 1; s.border_width_top = 1
	s.border_width_right = 1; s.border_width_bottom = 1
	s.content_margin_left = 8; s.content_margin_right = 8
	s.content_margin_top = 4; s.content_margin_bottom = 4
	s.corner_radius_top_left = 0; s.corner_radius_top_right = 0
	s.corner_radius_bottom_left = 0; s.corner_radius_bottom_right = 0
	return s

static func style_button(btn: Button, font_size: int = 13) -> void:
	var f := get_font()
	if f:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", AMBER)
	btn.add_theme_color_override("font_hover_color", AMBER_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", AMBER_BRIGHT)
	btn.add_theme_color_override("font_disabled_color", AMBER_DIM)
	
	btn.add_theme_stylebox_override("normal",  make_button_style())
	btn.add_theme_stylebox_override("hover",   make_button_style(Color(0.12, 0.11, 0.07), AMBER))
	btn.add_theme_stylebox_override("pressed", make_button_style(Color(0.18, 0.16, 0.08), AMBER_BRIGHT))
	btn.add_theme_stylebox_override("disabled", make_button_style(Color(0.04, 0.04, 0.03), AMBER_DIM))

# ── CRT 패널 배경 (얇은 앰버 테두리 + 어두운 배경) ─────────
static func make_panel_bg(parent: Control, pos: Vector2, sz: Vector2) -> ColorRect:
	# 테두리 역할 (약간 큰 앰버 Rect)
	var border := ColorRect.new()
	border.position = pos - Vector2(1, 1)
	border.size = sz + Vector2(2, 2)
	border.color = AMBER_BORDER
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(border)
	# 내부 배경
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = sz
	bg.color = BG_PANEL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg

# ── 스캔라인 오버레이 (가로선) ──────────────────────────────
static func add_scanline_overlay(parent: Control) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 50
	overlay.set_script(_ScanlineScript)
	parent.add_child(overlay)

# 스캔라인 그리기용 내부 스크립트
const _ScanlineScript = preload("res://scripts/crt_scanline.gd")
