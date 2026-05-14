extends CanvasLayer
class_name LootUI

signal loot_ui_closed
signal item_used(item_id: String)

# ── 레이아웃 상수 ──────────────────────────────────────────
const SLOT_W    := 58
const SLOT_H    := 44
const SLOT_GAP  := 2
const TRUNK_COLS := 5
const TRUNK_ROWS := 4
const WRECK_COLS := 8   # 화면 맞게 조정
const WRECK_ROWS := 10  # 기본 행 수 (랜덤으로 10~16)

const SEARCH_TIME := 0.10   # 슬롯 1개당 수색 시간 (초)

# ── 데이터 참조 ───────────────────────────────────────────
var inv: InventoryManager
var meta: MetaProgression
var vehicle: LastRoadVehicle
var charm_sys: CharmSystem
var _wreck_seed: int = -1

# ── 폐차 상태 ─────────────────────────────────────────────
var _wreck_cols: int = WRECK_COLS
var _wreck_rows: int = WRECK_ROWS
var _wreck_items: Dictionary = {}   # slot_idx -> item_id
var _revealed: Array  = []          # bool per slot

var _active_state: Dictionary = {}
var _search_slot: int   = 0
var _search_timer: float= 0.0
var _search_done: bool  = false

# ── 드래그 상태 ───────────────────────────────────────────
var _held_item: String  = ""
var _held_from_type: String = ""  # "trunk" | "wreck"
var _held_from_idx: int = -1

# ── UI 노드 참조 ──────────────────────────────────────────
var _root        : Control
var _trunk_slots : Array = []   # Control per trunk slot
var _wreck_slots : Array = []   # Control per wreck slot
var _drag_panel  : Panel
var _drag_label  : Label
var _info_label  : Label
var _tooltip_panel : PanelContainer
var _tooltip_name_lbl  : Label
var _tooltip_type_lbl  : Label
var _tooltip_size_lbl  : Label
var _tooltip_val_lbl   : Label
var _discard_zone: Control
var _search_lbl  : Label
var _trunk_count_lbl: Label
var _close_btn   : Button
var _sort_btn    : Button

var _title_lbl   : Label
var _is_trunk_only : bool = false

# ── 내구도 UI 노드 ──────────────────────────────────────────
var _durability_panel: Control
var _drivetrain_rect: TextureRect
var _lf_tire_rect: TextureRect
var _rf_tire_rect: TextureRect
var _lb_tire_rect: TextureRect
var _rb_tire_rect: TextureRect

# ─────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 12
	_build_ui()

# ── 외부에서 호출: 트렁크 전용 오픈 ───────────────────────
func open_trunk() -> void:
	_is_trunk_only = true
	_title_lbl.text = "내 인벤토리"
	_wreck_panel_bg.visible = false
	_wreck_scroll_clip.visible = false
	_search_lbl.visible = false
	
	_held_item = ""
	_search_done = true
	_refresh_trunk_ui()
	_refresh_durability_ui()
	_root.visible = true

# ── 외부에서 호출: 폐차 오픈 ─────────────────────────────
func open_wreck(wreck_seed: int) -> void:
	_is_trunk_only = false
	_title_lbl.text = "갓길 수색"
	_wreck_panel_bg.visible = true
	_wreck_scroll_clip.visible = true
	_search_lbl.visible = true

	_wreck_rows = 10 + (wreck_seed % 7)   # 10~16행
	_active_state = inv.get_or_generate_wreck_state(wreck_seed, _wreck_cols, _wreck_rows)
	_wreck_items = _active_state["items"]
	_revealed = _active_state["revealed"]
	_search_slot  = _active_state["search_slot"]
	_search_timer = _active_state["search_timer"]
	_search_done  = _active_state["search_done"]
	_held_item    = ""
	_rebuild_wreck_grid()
	_refresh_trunk_ui()
	_refresh_durability_ui()
	_root.visible = true

func close() -> void:
	_root.visible = false
	_held_item = ""
	_update_drag_vis()
	loot_ui_closed.emit()

func is_open() -> bool:
	return _root != null and _root.visible

# ─────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not is_open(): return

	# 드래그 팔로우
	if _held_item != "":
		_drag_panel.position = get_viewport().get_mouse_position() + Vector2(8, 8)
		_tooltip_panel.visible = false

	# 툴팁 팔로우
	elif _tooltip_panel.visible:
		var mp := get_viewport().get_mouse_position()
		var tx := mp.x + 16.0
		var ty := mp.y + 16.0
		# 화면 오른쪽 넘침 방지
		if tx + _tooltip_panel.size.x > 1280.0:
			tx = mp.x - _tooltip_panel.size.x - 8.0
		if ty + _tooltip_panel.size.y > 720.0:
			ty = mp.y - _tooltip_panel.size.y - 8.0
		_tooltip_panel.position = Vector2(tx, ty)

	_process_search_bar()

	if _search_done: return

	var loot_speed_mult := 1.25 if (meta and meta.has_perk("fast_loot")) else 1.0
	_search_timer += delta * loot_speed_mult
	_active_state["search_timer"] = _search_timer
	if _search_timer >= SEARCH_TIME:
		_search_timer -= SEARCH_TIME
		_active_state["search_timer"] = _search_timer
		_reveal_next_slot()

func _reveal_next_slot() -> void:
	var total := _wreck_cols * _wreck_rows
	while _search_slot < total:
		if not _revealed[_search_slot]:
			_revealed[_search_slot] = true
			
			# ── 자석 고양이 부적: 빈 칸 수색 시 15% 확률로 기름 1L 획득 ──
			var slot_item := str(_wreck_items.get(_search_slot, ""))
			if slot_item == "" and charm_sys and charm_sys.has_charm("magnetic_cat"):
				if randf() < 0.15:
					if vehicle:
						vehicle.fuel = minf(vehicle.fuel + 1.0, vehicle.fuel_max)
						vehicle.fuel_ratio = vehicle.fuel / vehicle.fuel_max
					# 심리적 피드백: 슬롯을 연두색으로 플래시
					var slot_ctrl := _wreck_slots[_search_slot] as Control
					var bg := slot_ctrl.get_node_or_null("BG") as ColorRect
					if bg:
						var orig_color := bg.color
						bg.color = Color(0.15, 0.55, 0.25, 0.9)  # 연두색 플래시
						var tw := create_tween()
						tw.tween_property(bg, "color", orig_color, 0.6)
			
			_refresh_wreck_slot(_search_slot)
			_search_slot += 1
			_active_state["search_slot"] = _search_slot
			_update_search_label()
			return
		_search_slot += 1
		_active_state["search_slot"] = _search_slot
	_search_done = true
	_active_state["search_done"] = true
	_update_search_label()

func _update_search_label() -> void:
	var total := _wreck_cols * _wreck_rows
	if _search_done:
		_search_lbl.text = "수색 완료"
	else:
		var pct := int(float(_search_slot) / float(total) * 100.0)
		_search_lbl.text = "수색 중... %d%%" % pct

# ─────────────────────────────────────────────────────────
# UI 빌드
# ─────────────────────────────────────────────────────────
func _build_ui() -> void:
	# 전체 루트
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	# 어두운 오버레이
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.97)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(overlay)
	CrtTheme.add_scanline_overlay(_root)

	# ── 제목 ──
	_title_lbl = Label.new()
	_title_lbl.text = "갓길 수색"
	_title_lbl.position = Vector2(20, 12)
	CrtTheme.style_label(_title_lbl, 22, CrtTheme.AMBER_BRIGHT)
	_root.add_child(_title_lbl)

	# 닫기 버튼
	_close_btn = Button.new()
	_close_btn.text = "✕ 닫기"
	_close_btn.position = Vector2(1180, 8)
	_close_btn.size = Vector2(90, 36)
	_close_btn.z_index = 50
	CrtTheme.style_button(_close_btn, 14)
	_close_btn.pressed.connect(close)
	_root.add_child(_close_btn)

	# ── 트렁크 패널 (좌) ──
	_build_trunk_panel()

	# ── 폐차 인벤 패널 (우) ──
	_build_wreck_panel()

	# ── 버리기 존 (하단 중앙) ──
	_build_discard_zone()

	# ── 차량 내구도 패널 ──
	_build_durability_panel()

	# ── 아이템 정보 라벨 (하단, 비워둠) ──
	_info_label = Label.new()
	_info_label.visible = false
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_info_label)

	# ── 툴팁 패널 (타르코프 스타일 플로팅 박스) ──
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 20
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.02, 0.02, 0.01, 0.97)
	tip_style.border_color = CrtTheme.AMBER_BORDER
	tip_style.border_width_left = 1; tip_style.border_width_top = 1
	tip_style.border_width_right = 1; tip_style.border_width_bottom = 1
	tip_style.content_margin_left = 10; tip_style.content_margin_right = 10
	tip_style.content_margin_top = 8; tip_style.content_margin_bottom = 8
	_tooltip_panel.add_theme_stylebox_override("panel", tip_style)
	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 3)
	_tooltip_panel.add_child(tip_vbox)
	_tooltip_name_lbl = Label.new()
	CrtTheme.style_label(_tooltip_name_lbl, 15, CrtTheme.AMBER_BRIGHT)
	tip_vbox.add_child(_tooltip_name_lbl)
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", CrtTheme.AMBER_DIM)
	tip_vbox.add_child(sep)
	_tooltip_type_lbl = Label.new()
	CrtTheme.style_label(_tooltip_type_lbl, 12, CrtTheme.AMBER_MID)
	tip_vbox.add_child(_tooltip_type_lbl)
	_tooltip_size_lbl = Label.new()
	CrtTheme.style_label(_tooltip_size_lbl, 11, CrtTheme.AMBER_DIM)
	tip_vbox.add_child(_tooltip_size_lbl)
	_tooltip_val_lbl = Label.new()
	CrtTheme.style_label(_tooltip_val_lbl, 13, CrtTheme.AMBER)
	tip_vbox.add_child(_tooltip_val_lbl)
	_root.add_child(_tooltip_panel)

	# ── 드래그 패널 (항상 최상위) ──
	_drag_panel = Panel.new()
	_drag_panel.size = Vector2(SLOT_W, SLOT_H)
	_drag_panel.visible = false
	_drag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_label = Label.new()
	_drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_drag_label.add_theme_font_size_override("font_size", 11)
	_drag_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_panel.add_child(_drag_label)
	_drag_panel.z_index = 100
	_root.add_child(_drag_panel)

# ── 트렁크 패널 ──────────────────────────────────────────
func _build_trunk_panel() -> void:
	var panel_x := 30.0
	var panel_y := 60.0

	var bg := ColorRect.new()
	bg.position = Vector2(panel_x - 6, panel_y - 30)
	bg.size = Vector2(TRUNK_COLS * (SLOT_W + SLOT_GAP) + 12, 24 + TRUNK_ROWS * (SLOT_H + SLOT_GAP) + 60)
	bg.color = CrtTheme.BG_PANEL
	_root.add_child(bg)

	var lbl := Label.new()
	lbl.text = "내 차 트럭크"
	lbl.position = Vector2(panel_x, panel_y - 26)
	CrtTheme.style_label(lbl, 14, CrtTheme.AMBER)
	_root.add_child(lbl)

	_trunk_count_lbl = Label.new()
	_trunk_count_lbl.position = Vector2(panel_x + 100, panel_y - 26)
	CrtTheme.style_label(_trunk_count_lbl, 13, CrtTheme.AMBER_DIM)
	_root.add_child(_trunk_count_lbl)

	_sort_btn = Button.new()
	_sort_btn.text = "정리"
	_sort_btn.position = Vector2(panel_x + 220, panel_y - 30)
	_sort_btn.size = Vector2(50, 24)
	CrtTheme.style_button(_sort_btn, 12)
	_sort_btn.pressed.connect(func():
		inv.sort_trunk()
		_refresh_trunk_ui()
	)
	_root.add_child(_sort_btn)

	_trunk_slots.clear()
	for row in TRUNK_ROWS:
		for col in TRUNK_COLS:
			var s := _make_slot_node(
				Vector2(panel_x + col * (SLOT_W + SLOT_GAP),
						panel_y + row * (SLOT_H + SLOT_GAP)),
				"trunk", row * TRUNK_COLS + col
			)
			_trunk_slots.append(s)
			_root.add_child(s)

# ── 폐차 인벤 패널 ──────────────────────────────────────
var _wreck_grid_parent : Control
var _wreck_panel_bg : ColorRect
var _wreck_scroll_clip : Control   # clips the grid

func _build_wreck_panel() -> void:
	var panel_x := 760.0
	var panel_y := 60.0
	var grid_w := WRECK_COLS * (SLOT_W + SLOT_GAP)
	var panel_h := 600.0

	_wreck_panel_bg = ColorRect.new()
	_wreck_panel_bg.position = Vector2(panel_x - 6, panel_y - 30)
	_wreck_panel_bg.size = Vector2(grid_w + 12, panel_h + 30)
	_wreck_panel_bg.color = CrtTheme.BG_PANEL
	_root.add_child(_wreck_panel_bg)

	var lbl := Label.new()
	lbl.text = "폐차 인벤토리"
	lbl.position = Vector2(panel_x, panel_y - 26)
	CrtTheme.style_label(lbl, 14, CrtTheme.AMBER)
	_root.add_child(lbl)

	_search_lbl = Label.new()
	_search_lbl.text = ""
	_search_lbl.position = Vector2(panel_x + 170, panel_y - 26)
	CrtTheme.style_label(_search_lbl, 13, CrtTheme.GREEN_DATA)
	_root.add_child(_search_lbl)

	# 스크롤 클립 영역
	_wreck_scroll_clip = Control.new()
	_wreck_scroll_clip.position = Vector2(panel_x, panel_y)
	_wreck_scroll_clip.size = Vector2(grid_w, panel_h - 10)
	_wreck_scroll_clip.clip_contents = true
	_wreck_scroll_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_wreck_scroll_clip)

	_wreck_grid_parent = Control.new()
	_wreck_grid_parent.position = Vector2.ZERO
	_wreck_grid_parent.mouse_filter = Control.MOUSE_FILTER_PASS
	_wreck_scroll_clip.add_child(_wreck_grid_parent)

func _rebuild_wreck_grid() -> void:
	for child in _wreck_grid_parent.get_children():
		child.queue_free()
	_wreck_slots.clear()
	await get_tree().process_frame

	var total := _wreck_cols * _wreck_rows
	_wreck_grid_parent.size = Vector2(
		_wreck_cols * (SLOT_W + SLOT_GAP),
		_wreck_rows * (SLOT_H + SLOT_GAP)
	)
	for i in total:
		var row := i / _wreck_cols
		var col := i % _wreck_cols
		var s := _make_slot_node(
			Vector2(col * (SLOT_W + SLOT_GAP), row * (SLOT_H + SLOT_GAP)),
			"wreck", i
		)
		_wreck_slots.append(s)
		_wreck_grid_parent.add_child(s)
		
	# 새로 생성된 슬롯에 현재 상태(아이템 유무, 가려짐 등) 반영
	for i in total:
		_refresh_wreck_slot(i)
		
	_update_search_label()

# ── 버리기 존 ────────────────────────────────────────────
func _build_discard_zone() -> void:
	_discard_zone = Control.new()
	_discard_zone.position = Vector2(450, 672)
	_discard_zone.size = Vector2(380, 44)
	_discard_zone.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.20, 0.05, 0.03, 0.85)
	bg.size = Vector2(380, 44)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_zone.add_child(bg)

	var lbl := Label.new()
	lbl.text = "🗑  여기에 놓으면 버려짐"
	lbl.position = Vector2(0, 0)
	lbl.size = Vector2(380, 44)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	CrtTheme.style_label(lbl, 15, CrtTheme.RED_WARN)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_zone.add_child(lbl)

	_discard_zone.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_drop_to_discard()
	)
	_root.add_child(_discard_zone)

# ── 내구도 패널 ────────────────────────────────────────────
func _build_durability_panel() -> void:
	_durability_panel = Control.new()
	_durability_panel.position = Vector2(400, 120)
	_durability_panel.size = Vector2(300, 480)
	_root.add_child(_durability_panel)
	
	var lbl := Label.new()
	lbl.text = "차량 내구도"
	lbl.position = Vector2(100, -30)
	CrtTheme.style_label(lbl, 16, CrtTheme.AMBER)
	_durability_panel.add_child(lbl)
	
	# 구동계
	_drivetrain_rect = TextureRect.new()
	_drivetrain_rect.texture = load("res://Asset/Image/Drivetrain.png")
	_drivetrain_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drivetrain_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drivetrain_rect.position = Vector2(50, 0)
	_drivetrain_rect.size = Vector2(200, 480)
	_durability_panel.add_child(_drivetrain_rect)

	# 타이어들
	_lf_tire_rect = _create_tire_rect("res://Asset/Image/LF_tire.png", Vector2(10, 40))
	_rf_tire_rect = _create_tire_rect("res://Asset/Image/RF_tire.png", Vector2(230, 40))
	_lb_tire_rect = _create_tire_rect("res://Asset/Image/LB_tire.png", Vector2(10, 360))
	_rb_tire_rect = _create_tire_rect("res://Asset/Image/RB_tire.png", Vector2(230, 360))

func _create_tire_rect(path: String, pos: Vector2) -> TextureRect:
	var tr = TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = pos
	tr.size = Vector2(60, 100)
	_durability_panel.add_child(tr)
	return tr

func _refresh_durability_ui() -> void:
	if not vehicle: return
	_tint_durability(_drivetrain_rect, vehicle.dur_drivetrain)
	_tint_durability(_lf_tire_rect, vehicle.dur_lf_tire)
	_tint_durability(_rf_tire_rect, vehicle.dur_rf_tire)
	_tint_durability(_lb_tire_rect, vehicle.dur_lb_tire)
	_tint_durability(_rb_tire_rect, vehicle.dur_rb_tire)

func _tint_durability(tr: TextureRect, val: float) -> void:
	var ratio = clampf(val / 100.0, 0.0, 1.0)
	var r = 1.0 if ratio <= 0.5 else 1.0 - (ratio - 0.5) * 2.0
	var g = 1.0 if ratio >= 0.5 else ratio * 2.0
	var b = 0.0
	tr.modulate = Color(r, g, b, 1.0)

# ─────────────────────────────────────────────────────────
# 슬롯 노드 공통 생성
# ─────────────────────────────────────────────────────────
func _make_slot_node(pos: Vector2, panel_type: String, idx: int) -> Control:
	var s := Control.new()
	s.position = pos
	s.size = Vector2(SLOT_W, SLOT_H)
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	s.set_meta("panel_type", panel_type)
	s.set_meta("slot_idx", idx)

	var bg := ColorRect.new()
	bg.name = "BG"
	bg.size = Vector2(SLOT_W, SLOT_H)
	bg.color = CrtTheme.SLOT_EMPTY
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(bg)

	# 아이콘 이미지
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(0, 0)
	icon.size = Vector2(SLOT_W, SLOT_H)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	s.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.name = "NameLbl"
	name_lbl.position = Vector2(2, 2)
	name_lbl.size = Vector2(SLOT_W - 4, SLOT_H - 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	CrtTheme.style_label(name_lbl, 10, CrtTheme.AMBER_DIM)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.name = "ValLbl"
	val_lbl.position = Vector2(2, SLOT_H - 16)
	val_lbl.size = Vector2(SLOT_W - 4, 14)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	CrtTheme.style_label(val_lbl, 9, CrtTheme.AMBER)
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(val_lbl)

	# 진행 바 (수색 중인 슬롯에만 표시)
	var prog := ColorRect.new()
	prog.name = "Prog"
	prog.color = Color(0.3, 0.9, 0.3, 0.6)
	prog.position = Vector2(0, SLOT_H - 3)
	prog.size = Vector2(0, 3)
	prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(prog)

	# 입력 처리
	s.gui_input.connect(_on_slot_input.bind(panel_type, idx))
	s.mouse_entered.connect(_on_slot_hover.bind(panel_type, idx))
	s.mouse_exited.connect(func(): _tooltip_panel.visible = false)

	return s

# ─────────────────────────────────────────────────────────
# 슬롯 UI 갱신
# ─────────────────────────────────────────────────────────
func _refresh_trunk_ui() -> void:
	var used := 0
	for i in TRUNK_COLS * TRUNK_ROWS:
		if i >= _trunk_slots.size(): break
		var item_id := str(inv.trunk[i])
		_apply_slot_state(_trunk_slots[i], item_id if item_id != "" else "", true)
		if item_id != "": used += 1
	if _trunk_count_lbl:
		_trunk_count_lbl.text = "%d/%d" % [used, inv.trunk_size]

func _refresh_wreck_slot(idx: int) -> void:
	if idx >= _wreck_slots.size(): return
	var revealed := bool(_revealed[idx])
	var item_id  := str(_wreck_items.get(idx, ""))
	if revealed:
		_apply_slot_state(_wreck_slots[idx], item_id, true)
	else:
		_apply_slot_state(_wreck_slots[idx], "??", false)

func _apply_slot_state(slot: Control, item_id: String, revealed: bool) -> void:
	if slot == null: return
	var bg        := slot.get_node_or_null("BG")        as ColorRect
	var name_lbl  := slot.get_node_or_null("NameLbl")  as Label
	var val_lbl   := slot.get_node_or_null("ValLbl")   as Label

	if not revealed:
		if bg:
			bg.color = Color(0.07, 0.06, 0.04)
			bg.size = Vector2(SLOT_W, SLOT_H)
		if name_lbl: name_lbl.text = "?"
		if name_lbl: name_lbl.add_theme_color_override("font_color", CrtTheme.AMBER_DIM)
		if val_lbl: val_lbl.text = ""
		var icon0 := slot.get_node_or_null("Icon") as TextureRect
		if icon0: icon0.visible = false
		slot.z_index = 0
		return

	if item_id == "":
		if bg:
			bg.color = CrtTheme.SLOT_EMPTY
			bg.size = Vector2(SLOT_W, SLOT_H)
		if name_lbl: name_lbl.text = ""
		if val_lbl: val_lbl.text = ""
		var icon0 := slot.get_node_or_null("Icon") as TextureRect
		if icon0: icon0.visible = false
		slot.z_index = 0
		return

	var data := inv.get_item_data(item_id)
	if data.is_empty():
		if name_lbl: name_lbl.text = item_id
		return

	var sz = data.get("size", [1, 1])
	var w = int(sz[0])
	var h = int(sz[1])
	if bg:
		var c := data.get("color", Color(0.4, 0.4, 0.4)) as Color
		bg.color = c.darkened(0.35)
		bg.size = Vector2(w * SLOT_W + (w - 1) * SLOT_GAP, h * SLOT_H + (h - 1) * SLOT_GAP)
		if w > 1 or h > 1:
			slot.z_index = 1
		else:
			slot.z_index = 0

	# 아이콘 설정
	var icon := slot.get_node_or_null("Icon") as TextureRect
	if icon:
		var icon_path := "res://Asset/Image/item/%s.png" % item_id
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
			icon.size = Vector2(w * SLOT_W + (w - 1) * SLOT_GAP, h * SLOT_H + (h - 1) * SLOT_GAP)
			icon.visible = true
		else:
			icon.visible = false
	# 이름/가격은 숨김 — 호버 시 툴팁에만 표시
	if name_lbl: name_lbl.text = ""
	if val_lbl: val_lbl.text = ""

# ─────────────────────────────────────────────────────────
# 큰 아이템의 앵커(좌상단 슬롯) 찾기
# ─────────────────────────────────────────────────────────
func _find_trunk_anchor(idx: int) -> int:
	var cr := idx / TRUNK_COLS
	var cc := idx % TRUNK_COLS
	for i in inv.trunk_size:
		var other_id := str(inv.trunk[i])
		if other_id == "": continue
		var odata := inv.get_item_data(other_id)
		var osz : Array = odata.get("size", [1, 1])
		if int(osz[0]) == 1 and int(osz[1]) == 1: continue
		var orow := i / TRUNK_COLS
		var ocol := i % TRUNK_COLS
		if cr >= orow and cr < orow + int(osz[1]) and cc >= ocol and cc < ocol + int(osz[0]):
			return i
	return idx

func _find_wreck_anchor(idx: int) -> int:
	var cr := idx / _wreck_cols
	var cc := idx % _wreck_cols
	for anchor: int in _wreck_items:
		var other_id := str(_wreck_items[anchor])
		var odata := inv.get_item_data(other_id)
		var osz : Array = odata.get("size", [1, 1])
		if int(osz[0]) == 1 and int(osz[1]) == 1: continue
		var orow := anchor / _wreck_cols
		var ocol := anchor % _wreck_cols
		if cr >= orow and cr < orow + int(osz[1]) and cc >= ocol and cc < ocol + int(osz[0]):
			return anchor
	return idx

func _on_slot_hover(panel_type: String, idx: int) -> void:
	# 큰 아이템의 덮인 영역이면 앵커로 리다이렉트
	if panel_type == "trunk":
		idx = _find_trunk_anchor(idx)
	elif panel_type == "wreck":
		idx = _find_wreck_anchor(idx)

	var item_id := ""
	if panel_type == "trunk":
		item_id = str(inv.trunk[idx])
	elif panel_type == "wreck":
		if idx < _revealed.size() and _revealed[idx]:
			item_id = str(_wreck_items.get(idx, ""))

	if item_id != "" and _held_item == "":
		var data := inv.get_item_data(item_id)
		if not data.is_empty():
			var v := int(data.get("value", 0))
			var t := str(data.get("type", ""))
			var sz = data.get("size", [1, 1])
			var type_str := "소모품" if t == "consumable" else "잡품"
			_tooltip_name_lbl.text = str(data.get("name", item_id))
			_tooltip_type_lbl.text = type_str
			_tooltip_size_lbl.text = "%dx%d" % [int(sz[0]), int(sz[1])]
			_tooltip_val_lbl.text = "₩ %d" % v if v > 0 else ""
			_tooltip_panel.visible = true
			return
	_tooltip_panel.visible = false

func _on_slot_input(ev: InputEvent, panel_type: String, idx: int) -> void:
	if not (ev is InputEventMouseButton): return
	var mb := ev as InputEventMouseButton
	
	# 아이템을 집을 때만 앵커로 리다이렉트 (놓을 때는 클릭한 그 칸이 기준이 되어야 함)
	var interaction_idx := idx
	if _held_item == "":
		if panel_type == "trunk":
			interaction_idx = _find_trunk_anchor(idx)
		elif panel_type == "wreck":
			interaction_idx = _find_wreck_anchor(idx)

	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_handle_click(panel_type, interaction_idx)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _held_item == "":
			if _is_trunk_only:
				_try_use_item(panel_type, interaction_idx)
			else:
				_auto_transfer_item(panel_type, interaction_idx)

func _try_use_item(panel_type: String, idx: int) -> void:
	if panel_type != "trunk": return
	var item_id = str(inv.trunk[idx])
	if item_id == "": return
	
	var data := inv.get_item_data(item_id)
	if str(data.get("type", "")) == "consumable":
		# 소모품 사용 후 제거
		inv.trunk_remove(idx)
		_refresh_trunk_ui()
		_tooltip_panel.visible = false
		item_used.emit(item_id)

func _handle_click(panel_type: String, idx: int) -> void:
	# 들고 있는 아이템이 없으면 집기
	if _held_item == "":
		_try_pick_up(panel_type, idx)
	else:
		# 들고 있으면 놓기
		_try_place(panel_type, idx)

func _try_pick_up(panel_type: String, idx: int) -> void:
	var item_id := ""
	if panel_type == "trunk":
		item_id = str(inv.trunk[idx])
		if item_id == "": return
		inv.trunk_remove(idx)
		_refresh_trunk_ui()
	elif panel_type == "wreck":
		if idx >= _revealed.size() or not _revealed[idx]: return
		item_id = str(_wreck_items.get(idx, ""))
		if item_id == "": return
		_wreck_items.erase(idx)
		_refresh_wreck_slot(idx)

	_held_item = item_id
	_held_from_type = panel_type
	_held_from_idx  = idx
	_update_drag_vis()

func _try_place(panel_type: String, idx: int) -> void:
	if panel_type == "trunk":
		if not inv.can_fit_item(_held_item, idx):
			var blocks := inv.get_blocking_items(_held_item, idx)
			if blocks.size() == 1 and int(blocks[0]) != -1:
				var blocking_idx : int = blocks[0]
				var swap_item_id := inv.trunk_remove(blocking_idx)
				if inv.can_fit_item(_held_item, idx):
					inv.trunk_set(idx, _held_item)
					_held_item = swap_item_id
					_held_from_type = "trunk"
					_held_from_idx = blocking_idx
					_refresh_trunk_ui()
					_update_drag_vis()
					return
				else:
					inv.trunk_set(blocking_idx, swap_item_id)
			_info_label.text = "공간이 부족합니다."
			return
		inv.trunk_set(idx, _held_item)
		_held_item = ""
		_held_from_type = ""
		_held_from_idx  = -1
		_refresh_trunk_ui()
		_update_drag_vis()
	elif panel_type == "wreck":
		if not _can_fit_wreck(_held_item, idx):
			var blocks := _get_wreck_blocking_items(_held_item, idx)
			if blocks.size() == 1 and int(blocks[0]) != -1:
				var blocking_idx : int = blocks[0]
				var swap_item_id : String = _wreck_items[blocking_idx]
				_wreck_items.erase(blocking_idx)
				if _can_fit_wreck(_held_item, idx):
					_wreck_items[idx] = _held_item
					_held_item = swap_item_id
					_held_from_type = "wreck"
					_held_from_idx = blocking_idx
					_refresh_wreck_slot(blocking_idx)
					_refresh_wreck_slot(idx)
					_update_drag_vis()
					return
				else:
					_wreck_items[blocking_idx] = swap_item_id
			_info_label.text = "공간이 부족하거나 가려진 구역입니다."
			return
		_wreck_items[idx] = _held_item
		_held_item = ""
		_held_from_type = ""
		_held_from_idx = -1
		_refresh_wreck_slot(idx)
		_update_drag_vis()

func _auto_transfer_item(panel_type: String, idx: int) -> void:
	if panel_type == "trunk":
		var item_id = str(inv.trunk[idx])
		if item_id == "": return
		var placed_idx := -1
		for i in _wreck_slots.size():
			if _can_fit_wreck(item_id, i):
				placed_idx = i
				break
		if placed_idx != -1:
			_wreck_items[placed_idx] = item_id
			inv.trunk_remove(idx)
			_refresh_trunk_ui()
			_refresh_wreck_slot(placed_idx)
			_tooltip_panel.visible = false
		else:
			_info_label.text = "폐차 인벤토리에 공간이 없습니다."
	elif panel_type == "wreck":
		if not _revealed[idx]: return
		var item_id = str(_wreck_items.get(idx, ""))
		if item_id == "": return
		var target_idx := inv.trunk_add(item_id)
		if target_idx != -1:
			_wreck_items.erase(idx)
			_refresh_wreck_slot(idx)
			_refresh_trunk_ui()
			_tooltip_panel.visible = false
		else:
			_info_label.text = "트렁크에 공간이 없습니다."

func _get_wreck_blocking_items(item_id: String, start_idx: int) -> Array:
	var data := inv.get_item_data(item_id)
	var sz : Array = data.get("size", [1, 1])
	var w : int = sz[0]
	var h : int = sz[1]
	var r := start_idx / _wreck_cols
	var c := start_idx % _wreck_cols
	
	if r + h > _wreck_rows or c + w > _wreck_cols: return [-1]
	var blocks := []
	for dr in h:
		for dc in w:
			var idx := (r + dr) * _wreck_cols + (c + dc)
			if idx >= _revealed.size() or not _revealed[idx]: return [-1]
			var anchor := _find_wreck_anchor(idx)
			if _wreck_items.has(anchor):
				if not blocks.has(anchor):
					blocks.append(anchor)
	return blocks

func _can_fit_wreck(item_id: String, start_idx: int) -> bool:
	var data := inv.get_item_data(item_id)
	var sz : Array = data.get("size", [1, 1])
	var w : int = sz[0]
	var h : int = sz[1]
	var r := start_idx / _wreck_cols
	var c := start_idx % _wreck_cols
	if r + h > _wreck_rows or c + w > _wreck_cols: return false
	for dr in h:
		for dc in w:
			var idx := (r + dr) * _wreck_cols + (c + dc)
			if idx >= _revealed.size() or not _revealed[idx]: return false
			if _wreck_items.has(idx): return false
			if _is_wreck_slot_covered_by_other(idx, -1): return false
	return true

func _is_wreck_slot_covered_by_other(check_idx: int, ignore_idx: int) -> bool:
	var cr := check_idx / _wreck_cols
	var cc := check_idx % _wreck_cols
	for idx: int in _wreck_items:
		if idx == ignore_idx: continue
		var data := inv.get_item_data(str(_wreck_items[idx]))
		var sz : Array = data.get("size", [1, 1])
		var r: int = idx / _wreck_cols
		var c: int = idx % _wreck_cols
		if cr >= r and cr < r + int(sz[1]) and cc >= c and cc < c + int(sz[0]):
			return true
	return false

func _drop_to_discard() -> void:
	if _held_item == "":
		return
	# 버리기 — 그냥 손에서 제거
	_held_item = ""
	_held_from_type = ""
	_held_from_idx  = -1
	_update_drag_vis()
	_info_label.text = "아이템을 버렸습니다."

func _update_drag_vis() -> void:
	var holding := _held_item != ""
	# 아이템 소지 중 닫기/정리 버튼 비활성화
	if _close_btn: _close_btn.disabled = holding
	if _sort_btn:  _sort_btn.disabled  = holding
	if not holding:
		_drag_panel.visible = false
		return
	# 소지 시작 — 툴팅 숨기기
	_tooltip_panel.visible = false
	_drag_panel.visible = true
	var data := inv.get_item_data(_held_item)
	var c := data.get("color", Color(0.5, 0.5, 0.5)) as Color
	# 아이템 실제 크기로 드래그 패널 크기 설정
	var sz = data.get("size", [1, 1])
	var w := int(sz[0])
	var h := int(sz[1])
	_drag_panel.size = Vector2(w * SLOT_W + (w - 1) * SLOT_GAP, h * SLOT_H + (h - 1) * SLOT_GAP)
	_drag_label.text = ""
	# 드래그 패널 배경색
	var style := StyleBoxFlat.new()
	style.bg_color = c.darkened(0.2)
	style.border_color = c
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	_drag_panel.add_theme_stylebox_override("panel", style)
	# 드래그 아이콘 표시
	var drag_icon := _drag_panel.get_node_or_null("DragIcon") as TextureRect
	if drag_icon == null:
		drag_icon = TextureRect.new()
		drag_icon.name = "DragIcon"
		drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_drag_panel.add_child(drag_icon)
	var icon_path := "res://Asset/Image/item/%s.png" % _held_item
	if ResourceLoader.exists(icon_path):
		drag_icon.texture = load(icon_path)
		drag_icon.size = _drag_panel.size
		drag_icon.visible = true
	else:
		drag_icon.visible = false

# 우클릭으로 놓기 취소 (원래 슬롯 복귀)
func _unhandled_input(ev: InputEvent) -> void:
	if not is_open(): return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _held_item != "":
			_return_held_item()

func _return_held_item() -> void:
	if _held_item == "":
		return
	if _held_from_type == "trunk" and _held_from_idx >= 0:
		# 원래 트렁크 슬롯에 되돌리기 (빈 슬롯이면 그냥 반환, 차있으면 빈 곳에)
		if str(inv.trunk[_held_from_idx]) == "":
			inv.trunk_set(_held_from_idx, _held_item)
		else:
			inv.trunk_add(_held_item)
		_refresh_trunk_ui()
	elif _held_from_type == "wreck" and _held_from_idx >= 0:
		_wreck_items[_held_from_idx] = _held_item
		_refresh_wreck_slot(_held_from_idx)

	_held_item = ""
	_held_from_type = ""
	_held_from_idx  = -1
	_update_drag_vis()

# 수색 진행 바 업데이트 (매 프레임 현재 수색 슬롯에 표시)
func _process_search_bar() -> void:
	# 이전 슬롯 바 초기화
	for s in _wreck_slots:
		var p := s.get_node_or_null("Prog") as ColorRect
		if p: p.size.x = 0

	if _search_done or _search_slot >= _wreck_slots.size(): return
	var s: Control = _wreck_slots[_search_slot] as Control
	if s == null: return
	var p := s.get_node_or_null("Prog") as ColorRect
	if p:
		p.size.x = SLOT_W * (_search_timer / SEARCH_TIME)
