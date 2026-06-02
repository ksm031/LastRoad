extends CanvasLayer

# ── 스킬 트리 UI ──
# 메인 메뉴에서 "강화" 버튼으로 열리는 퍽 해금 화면

const MetaProgression = preload("res://scripts/meta_progression.gd")

signal closed

const SCREEN_W := BillboardManager.SCREEN_W
const SCREEN_H := BillboardManager.SCREEN_H

var meta: MetaProgression

var _root   : Control
var _points_label : Label
var _desc_label   : Label
var _perk_buttons : Dictionary = {}  # perk_id -> Button
var _perk_cost_labels : Dictionary = {}  # perk_id -> Label

# 브랜치별 X 위치
const BRANCH_X := [160.0, 420.0, 680.0, 940.0]
# 티어별 Y 위치
const TIER_Y := {1: 200.0, 2: 340.0, 3: 480.0}
const BTN_W := 200.0
const BTN_H := 50.0

func _ready() -> void:
	layer = 21
	visible = false

func open() -> void:
	_build_ui()
	visible = true

func close() -> void:
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	_perk_buttons.clear()
	_perk_cost_labels.clear()
	closed.emit()

func _build_ui() -> void:
	if _root != null:
		_root.queue_free()
		_perk_buttons.clear()
		_perk_cost_labels.clear()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 배경
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# 타이틀
	var title := Label.new()
	title.text = "스킬 트리"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 20.0)
	title.size = Vector2(SCREEN_W, 50.0)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_root.add_child(title)

	# 보유 포인트
	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.position = Vector2(0.0, 65.0)
	_points_label.size = Vector2(SCREEN_W, 30.0)
	_points_label.add_theme_font_size_override("font_size", 22)
	_points_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_root.add_child(_points_label)

	# 설명 라벨 (하단)
	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.position = Vector2(0.0, 560.0)
	_desc_label.size = Vector2(SCREEN_W, 60.0)
	_desc_label.add_theme_font_size_override("font_size", 18)
	_desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_desc_label)

	# 브랜치 헤더
	for b in range(4):
		var header := Label.new()
		header.text = MetaProgression.BRANCH_NAMES[b]
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.position = Vector2(BRANCH_X[b] - BTN_W * 0.5, 120.0)
		header.size = Vector2(BTN_W, 30.0)
		header.add_theme_font_size_override("font_size", 20)
		header.add_theme_color_override("font_color", MetaProgression.BRANCH_COLORS[b])
		_root.add_child(header)

	# 연결선 그리기용 노드
	var line_drawer := Control.new()
	line_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	line_drawer.draw.connect(_draw_lines.bind(line_drawer))
	_root.add_child(line_drawer)

	# 퍽 버튼 배치
	for perk in MetaProgression.PERKS:
		var pid : String = perk["id"]
		var branch : int = int(perk["branch"])
		var tier : int = int(perk["tier"])

		var cx : float
		var cy : float

		if branch == -1:
			# locked_slot의 독립 좌표
			cx = 1140.0
			cy = 340.0
		else:
			# 같은 브랜치·티어 내에서 몇 번째인지 (2개면 좌우 배치, 1개면 가운데)
			var same_tier := _get_perks_in(branch, tier)
			var idx := same_tier.find(pid)
			var count := same_tier.size()

			cx = BRANCH_X[branch]
			if count == 2:
				cx += (float(idx) - 0.5) * (BTN_W * 0.55)
			cy = TIER_Y[tier]

		var btn := Button.new()
		btn.text = str(perk["name"])
		btn.position = Vector2(cx - BTN_W * 0.5, cy)
		btn.size = Vector2(BTN_W, BTN_H)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_perk_pressed.bind(pid))
		btn.mouse_entered.connect(_on_perk_hover.bind(pid))
		btn.mouse_exited.connect(_on_perk_unhover)
		_root.add_child(btn)
		_perk_buttons[pid] = btn

		# 비용 라벨
		var cost_lbl := Label.new()
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.position = Vector2(cx - BTN_W * 0.5, cy + BTN_H + 2.0)
		cost_lbl.size = Vector2(BTN_W, 20.0)
		cost_lbl.add_theme_font_size_override("font_size", 13)
		_root.add_child(cost_lbl)
		_perk_cost_labels[pid] = cost_lbl

	# 닫기 버튼
	var close_btn := Button.new()
	close_btn.text = "돌아가기"
	close_btn.position = Vector2(540.0, 640.0)
	close_btn.size = Vector2(200.0, 45.0)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(close)
	_root.add_child(close_btn)

	_refresh_all()

func _refresh_all() -> void:
	if meta == null:
		return
	_points_label.text = "보유 포인트: %dpt" % meta.total_points

	var normal_unlocked_count := 0
	for p in MetaProgression.PERKS:
		if p["id"] != "locked_slot" and meta.has_perk(p["id"]):
			normal_unlocked_count += 1

	for perk in MetaProgression.PERKS:
		var pid : String = perk["id"]
		var btn : Button = _perk_buttons[pid]
		var cost_lbl : Label = _perk_cost_labels[pid]

		if pid == "locked_slot":
			var show_locked := (normal_unlocked_count >= 20) or meta.locked_slot_unlocked
			btn.visible = show_locked
			cost_lbl.visible = show_locked

		if meta.has_perk(pid):
			# 해금됨
			btn.disabled = true
			btn.modulate = Color(0.6, 1.0, 0.6)
			cost_lbl.text = "해금됨"
			cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		elif meta.can_unlock(pid):
			# 해금 가능
			btn.disabled = false
			btn.modulate = Color(1.0, 1.0, 1.0)
			cost_lbl.text = "%dpt" % int(perk["cost"])
			cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		else:
			# 조건 미충족
			btn.disabled = true
			btn.modulate = Color(0.4, 0.4, 0.4)
			cost_lbl.text = "%dpt" % int(perk["cost"])
			cost_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _on_perk_pressed(perk_id: String) -> void:
	if meta.unlock_perk(perk_id):
		_refresh_all()

func _on_perk_hover(perk_id: String) -> void:
	var perk := meta._find_perk(perk_id)
	if not perk.is_empty():
		_desc_label.text = "%s — %s" % [str(perk["name"]), str(perk["desc"])]

func _on_perk_unhover() -> void:
	_desc_label.text = ""

func _get_perks_in(branch: int, tier: int) -> Array:
	var result := []
	for p in MetaProgression.PERKS:
		if int(p["branch"]) == branch and int(p["tier"]) == tier:
			result.append(p["id"])
	return result

func _draw_lines(drawer: Control) -> void:
	# 티어 간 연결선
	for branch in range(4):
		var t1_perks := _get_perks_in(branch, 1)
		var t2_perks := _get_perks_in(branch, 2)
		var t3_perks := _get_perks_in(branch, 3)

		# T1 → T2
		for pid1 in t1_perks:
			for pid2 in t2_perks:
				_draw_perk_line(drawer, pid1, pid2)
		# T2 → T3
		for pid2 in t2_perks:
			for pid3 in t3_perks:
				_draw_perk_line(drawer, pid2, pid3)

func _draw_perk_line(drawer: Control, from_id: String, to_id: String) -> void:
	if not _perk_buttons.has(from_id) or not _perk_buttons.has(to_id):
		return
	var from_btn : Button = _perk_buttons[from_id]
	var to_btn   : Button = _perk_buttons[to_id]
	var from_pos := from_btn.position + Vector2(BTN_W * 0.5, BTN_H)
	var to_pos   := to_btn.position + Vector2(BTN_W * 0.5, 0.0)

	var col := Color(0.3, 0.3, 0.3)
	if meta != null:
		if meta.has_perk(from_id) and meta.has_perk(to_id):
			col = Color(0.4, 0.9, 0.4, 0.8)
		elif meta.has_perk(from_id):
			col = Color(0.7, 0.7, 0.3, 0.6)
	drawer.draw_line(from_pos, to_pos, col, 2.0)
