extends CanvasLayer
class_name ShopUI

signal depart_requested(route_type: String)

const SLOT_W    := 58
const SLOT_H    := 44
const SLOT_GAP  := 2
const TRUNK_COLS := 5
const TRUNK_ROWS := 4
const SHOP_COLS := 9
const SHOP_ROWS := 13

var inv: InventoryManager
var upgrades: VehicleUpgradeSystem
var meta: MetaProgression
var vehicle: LastRoadVehicle
var charm_sys: Node
var current_stage: int = 1

var _root: Control
var _money_lbl: Label
var _info_label: Label
var _mode := "shop" # "shop" | "route"

# UI Containers
var _shop_panel: Control
var _route_panel: Control
var _trunk_slots: Array = []
var _shop_slots: Array = []
var _shop_items: Dictionary = {} # slot_idx -> item_id

# Upgrade UI Nodes
var _upgrade_container: VBoxContainer
var _stat_labels: Dictionary = {}      # part_id -> Label (stat values)
var _part_name_labels: Dictionary = {}  # part_id -> Label (flavor name)
var _pip_containers: Dictionary = {}    # part_id -> HBoxContainer (visual pips)
var _upgrade_btns: Dictionary = {}     # part_id -> Button

# Dragging
var _held_item: String = ""
var _held_from_type: String = "" # "trunk" | "shop"
var _held_from_idx: int = -1
var _drag_panel: Panel
var _drag_icon: TextureRect

func _ready() -> void:
	layer = 15
	_build_ui()

func open(stage: int, p_upgrades: VehicleUpgradeSystem, p_meta: MetaProgression) -> void:
	current_stage = stage
	upgrades = p_upgrades
	meta = p_meta
	_mode = "shop"
	_generate_shop_items()
	
	_refresh_all_slots()
	_refresh_money()
	_refresh_upgrades()
	_switch_mode("shop")
	_root.visible = true

func _on_buy_charm_pressed() -> void:
	if inv.money < 3000:
		_info_label.text = "부적을 구매할 돈이 부족합니다."
		return
	if charm_sys == null:
		return
		
	# 랜덤으로 1개 선택
	var keys = charm_sys.CHARM_DB.keys()
	var new_charm = keys[randi() % keys.size()]
	
	if charm_sys.has_charm(new_charm):
		_info_label.text = "이미 가지고 있는 부적입니다. 다시 시도해보세요."
		return
		
	inv.money -= 3000
	_refresh_money()
	
	var added = charm_sys.add_charm(new_charm)
	if added:
		var data = charm_sys.get_charm_data(new_charm)
		_info_label.text = "새로운 부적 획득: " + data.get("name", "")
	# 실패했다면 꽉 차서 charm_full 시그널이 발동된 상태일 것임

func close() -> void:
	_root.visible = false
	_return_held_item()

func is_open() -> bool:
	return _root != null and _root.visible

func _process(delta: float) -> void:
	if not _root.visible: return
	if _held_item != "":
		_drag_panel.position = get_viewport().get_mouse_position() + Vector2(8, 8)

func _switch_mode(m: String) -> void:
	_mode = m
	_shop_panel.visible = (_mode == "shop")
	_route_panel.visible = (_mode == "route")
	if _mode == "route":
		_build_routes()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	CrtTheme.add_scanline_overlay(_root)
	
	_shop_panel = Control.new()
	_shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shop_panel)
	
	_route_panel = Control.new()
	_route_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_route_panel)
	
	# ── 왼쪽: 스탯 패널 ─────────────────────────────────────
	const STAT_X  := 15
	const PANEL_Y := 10

	var title := Label.new()
	title.text = "정 비 소"
	CrtTheme.style_label(title, 28, CrtTheme.AMBER_BRIGHT)
	title.position = Vector2(STAT_X, PANEL_Y)
	_shop_panel.add_child(title)

	_money_lbl = Label.new()
	CrtTheme.style_label(_money_lbl, 18, CrtTheme.AMBER)
	_money_lbl.position = Vector2(STAT_X, PANEL_Y + 44)
	_shop_panel.add_child(_money_lbl)

	CrtTheme.make_panel_bg(_shop_panel, Vector2(STAT_X, PANEL_Y + 72), Vector2(230, 570))

	var stats_title := Label.new()
	stats_title.text = "차량 업그레이드"
	CrtTheme.style_label(stats_title, 14, CrtTheme.AMBER)
	stats_title.position = Vector2(STAT_X + 8, PANEL_Y + 76)
	_shop_panel.add_child(stats_title)

	_upgrade_container = VBoxContainer.new()
	_upgrade_container.position = Vector2(STAT_X + 8, PANEL_Y + 105)
	_upgrade_container.size = Vector2(214, 300)
	_upgrade_container.add_theme_constant_override("separation", 4)
	_shop_panel.add_child(_upgrade_container)

	var part_info := {
		"engine": "엔진 (최속/가속)",
		"fuel_tank": "연료탱크 (용량)",
		"turbine": "터빈 (연비)",
		"tires": "타이어 (조향)",
		"brakes": "브레이크 (제동)",
		"headlight": "헤드라이트 (시야)"
	}

	for pid in part_info:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		
		# 1열: 부품 종류 이름
		var type_lbl := Label.new()
		type_lbl.text = part_info[pid]
		CrtTheme.style_label(type_lbl, 10, CrtTheme.AMBER_DIM)
		row.add_child(type_lbl)
		
		# 2열: 현재 부품 이름 (Flavor Name)
		var name_lbl := Label.new()
		name_lbl.text = "부품명"
		CrtTheme.style_label(name_lbl, 13, CrtTheme.AMBER_BRIGHT)
		_part_name_labels[pid] = name_lbl
		row.add_child(name_lbl)
		
		# 3열: 게이지(Pips) 및 스탯 수치
		var h_box_gauge := HBoxContainer.new()
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		for i in 5:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(10, 6)
			pip.color = Color(0.10, 0.09, 0.05)
			pips.add_child(pip)
		_pip_containers[pid] = pips
		h_box_gauge.add_child(pips)
		
		var spacer := Control.new(); spacer.custom_minimum_size = Vector2(8, 0); h_box_gauge.add_child(spacer)
		
		var stat_val_lbl := Label.new()
		stat_val_lbl.text = "0.0"
		CrtTheme.style_label(stat_val_lbl, 11, CrtTheme.GREEN_DATA)
		_stat_labels[pid] = stat_val_lbl
		h_box_gauge.add_child(stat_val_lbl)
		row.add_child(h_box_gauge)
		
		# 4열: 업그레이드 버튼
		var up_btn := Button.new()
		up_btn.text = "₩0"
		up_btn.custom_minimum_size = Vector2(214, 28)
		CrtTheme.style_button(up_btn, 11)
		up_btn.pressed.connect(_on_upgrade_pressed.bind(pid))
		_upgrade_btns[pid] = up_btn
		row.add_child(up_btn)
		
		_upgrade_container.add_child(row)
		var line_spacer := Control.new(); line_spacer.custom_minimum_size = Vector2(0, 4); _upgrade_container.add_child(line_spacer)

	_info_label = Label.new()
	_info_label.position = Vector2(260, 540)
	_info_label.size = Vector2(316, 48)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	CrtTheme.style_label(_info_label, 13, CrtTheme.RED_WARN)
	_shop_panel.add_child(_info_label)

	var charm_btn := Button.new()
	charm_btn.text = "부적 뽑기 (₩3000)"
	charm_btn.position = Vector2(260, 600)
	charm_btn.size = Vector2(316, 48)
	CrtTheme.style_button(charm_btn, 16)
	charm_btn.pressed.connect(_on_buy_charm_pressed)
	_shop_panel.add_child(charm_btn)

	var next_btn := Button.new()
	next_btn.text = "정비 완료 →"
	next_btn.position = Vector2(260, 655)
	next_btn.size = Vector2(316, 48)
	CrtTheme.style_button(next_btn, 16)
	next_btn.pressed.connect(func(): _switch_mode("route"))
	_shop_panel.add_child(next_btn)

	# ── 가운데: 내 인벤 ──────────────────────────────────────
	const TRUNK_X := 260
	const TRUNK_Y := PANEL_Y

	CrtTheme.make_panel_bg(_shop_panel, Vector2(TRUNK_X, TRUNK_Y + 22), Vector2(TRUNK_COLS*(SLOT_W+SLOT_GAP)+16, TRUNK_ROWS*(SLOT_H+SLOT_GAP)+36))

	var tlbl = Label.new()
	tlbl.text = "내 트럭크  (우클릭: 판매)"
	CrtTheme.style_label(tlbl, 14, CrtTheme.AMBER_MID)
	tlbl.position = Vector2(TRUNK_X, TRUNK_Y + 4)
	_shop_panel.add_child(tlbl)

	for i in TRUNK_COLS*TRUNK_ROWS:
		var r = i / TRUNK_COLS; var c = i % TRUNK_COLS
		var s = _make_slot(Vector2(TRUNK_X+6 + c*(SLOT_W+SLOT_GAP), TRUNK_Y+48 + r*(SLOT_H+SLOT_GAP)), "trunk", i)
		_trunk_slots.append(s)
		_shop_panel.add_child(s)

	# 버리기 존 (트렁크 바로 아래)
	var trunk_grid_h := TRUNK_ROWS * (SLOT_H + SLOT_GAP)
	var discard_zone = Control.new()
	discard_zone.position = Vector2(TRUNK_X, TRUNK_Y + 22 + 36 + trunk_grid_h + 4)
	discard_zone.size = Vector2(TRUNK_COLS*(SLOT_W+SLOT_GAP)+16, 38)
	var dbg = ColorRect.new()
	dbg.color = Color(0.20, 0.05, 0.03, 0.85)
	dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	discard_zone.add_child(dbg)
	var dl = Label.new()
	dl.text = "버리기"
	dl.set_anchors_preset(Control.PRESET_FULL_RECT)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	CrtTheme.style_label(dl, 14, CrtTheme.RED_WARN)
	discard_zone.add_child(dl)
	discard_zone.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_held_item = ""; _held_from_type = ""; _held_from_idx = -1; _update_drag_vis()
	)
	_shop_panel.add_child(discard_zone)

	# ── 오른쪽: 상점 (세로 끝까지) ──────────────────────────
	const SHOP_X := 600
	const SHOP_Y := PANEL_Y

	CrtTheme.make_panel_bg(_shop_panel, Vector2(SHOP_X, SHOP_Y + 22), Vector2(SHOP_COLS*(SLOT_W+SLOT_GAP)+16, SHOP_ROWS*(SLOT_H+SLOT_GAP)+36))

	var slbl = Label.new()
	slbl.text = "상점  (우클릭: 구매)"
	CrtTheme.style_label(slbl, 14, CrtTheme.AMBER_MID)
	slbl.position = Vector2(SHOP_X, SHOP_Y + 4)
	_shop_panel.add_child(slbl)

	for i in SHOP_COLS*SHOP_ROWS:
		var r = i / SHOP_COLS; var c = i % SHOP_COLS
		var s = _make_slot(Vector2(SHOP_X+6 + c*(SLOT_W+SLOT_GAP), SHOP_Y+48 + r*(SLOT_H+SLOT_GAP)), "shop", i)
		_shop_slots.append(s)
		_shop_panel.add_child(s)

	# 드래그 패널
	_drag_panel = Panel.new()
	_drag_panel.visible = false
	_drag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_panel.z_index = 100
	_drag_icon = TextureRect.new()
	_drag_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_panel.add_child(_drag_icon)
	_root.add_child(_drag_panel)

func _make_slot(pos: Vector2, ptype: String, idx: int) -> Control:
	var s = Control.new()
	s.position = pos
	s.size = Vector2(SLOT_W, SLOT_H)
	var bg = ColorRect.new(); bg.name="BG"; bg.size=s.size; bg.color=CrtTheme.SLOT_EMPTY; bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	s.add_child(bg)
	var icon = TextureRect.new(); icon.name="Icon"; icon.size=s.size; icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	s.add_child(icon)
	var lbl = Label.new(); lbl.name="Val"; lbl.size=s.size; lbl.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; lbl.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
	CrtTheme.style_label(lbl, 10, CrtTheme.AMBER)
	s.add_child(lbl)
	s.gui_input.connect(_on_slot_input.bind(ptype, idx))
	return s

func _generate_shop_items() -> void:
	_shop_items.clear()
	var stock = ["fuel_can", "patch_kit", "cigarette", "big_engine", "spark_plug", "oil_filter"]
	for item_id in stock:
		# 첫 번째로 들어갈 수 있는 빈 공간 찾기
		for i in SHOP_COLS * SHOP_ROWS:
			if _can_fit("shop", item_id, i):
				_shop_items[i] = item_id
				break

func _refresh_money() -> void:
	if inv: 
		_money_lbl.text = "보유 자금: ₩%d" % inv.money
		# 자금이 변하면 업그레이드 버튼 활성화 여부도 다시 계산해야 함
		_refresh_upgrades()

func _on_sell_all_pressed() -> void:
	if inv == null: return
	var earned = inv.sell_all_junk(meta)
	if earned > 0:
		_info_label.text = "잡동사니를 판매하여 ₩%d를 획득했습니다!" % earned
		_refresh_money()
		_refresh_upgrades()
	else:
		_info_label.text = "판매할 잡동사니가 없습니다."

func _refresh_upgrades() -> void:
	if upgrades == null or vehicle == null: return
	
	for pid in _stat_labels:
		var lv = upgrades.upgrades.get(pid, 0)
		var p_data = upgrades.PART_DATA.get(pid, {})
		var lv_data = p_data.get("levels", [{}])[lv]
		
		# 1. 부품 이름 업데이트
		_part_name_labels[pid].text = lv_data.get("n", "알 수 없음")
		
		# 2. 게이지(Pips) 업데이트
		var pips = _pip_containers[pid].get_children()
		for i in 5:
			if i < lv:
				pips[i].color = CrtTheme.AMBER_BRIGHT
			else:
				pips[i].color = Color(0.10, 0.09, 0.05)
		
		# 3. 현재 스탯 표시
		var cur_stat_str := ""
		var next_stat_str := ""
		match pid:
			"engine":
				cur_stat_str = "%d km/h" % vehicle.max_speed
				if lv < upgrades.MAX_UPGRADE_LV: next_stat_str = " → %d" % (vehicle.max_speed + 15)
			"fuel_tank":
				cur_stat_str = "%dL" % int(vehicle.fuel_max)
				if lv < upgrades.MAX_UPGRADE_LV: next_stat_str = " → %d" % (int(vehicle.fuel_max) + 8)
			"turbine":
				cur_stat_str = "%.1f L/km" % vehicle.fuel_rate
				if lv < upgrades.MAX_UPGRADE_LV: next_stat_str = " → %.1f" % (vehicle.fuel_rate * 0.92)
			"tires":
				cur_stat_str = "조향 %.1f" % vehicle.lateral_speed
				if lv < upgrades.MAX_UPGRADE_LV: next_stat_str = " → %.1f" % (vehicle.lateral_speed + 0.2)
			"brakes":
				cur_stat_str = "제동 %d" % int(vehicle.brake_force)
				if lv < upgrades.MAX_UPGRADE_LV: next_stat_str = " → %d" % (int(vehicle.brake_force) + 8)
			"headlight":
				cur_stat_str = "시야 %.1f배" % vehicle.headlight_range
				if lv < upgrades.MAX_UPGRADE_LV: next_stat_str = " → %.1f" % (vehicle.headlight_range + 0.15)
		
		_stat_labels[pid].text = cur_stat_str + next_stat_str
		
		# 4. 버튼 상태
		var btn: Button = _upgrade_btns[pid]
		if lv >= upgrades.MAX_UPGRADE_LV:
			btn.text = "최대 레벨 도달"
			btn.disabled = true
		else:
			var cost = upgrades.UPGRADE_COSTS[lv]
			btn.text = "업그레이드: ₩%d" % cost
			btn.disabled = (inv.money < cost)

func _on_upgrade_pressed(part_id: String) -> void:
	if upgrades == null:
		return
	
	var result = upgrades.upgrade_part(part_id, inv.money)
	if result.get("success", false):
		inv.money -= int(result["cost"])
		# 성공 시 차량 스탯 즉시 반영
		if vehicle:
			vehicle.apply_upgrades(upgrades)
		_refresh_money()
		_refresh_upgrades()
	else:
		_info_label.text = "업그레이드 실패: 자금이 부족하거나 최대 레벨입니다."

func _refresh_all_slots() -> void:
	for i in _trunk_slots.size(): _refresh_slot(_trunk_slots[i], str(inv.trunk[i]) if inv else "")
	for i in _shop_slots.size(): _refresh_slot(_shop_slots[i], str(_shop_items.get(i, "")))

func _refresh_slot(s: Control, item_id: String) -> void:
	var bg: ColorRect = s.get_node("BG")
	var icon: TextureRect = s.get_node("Icon")
	var lbl: Label = s.get_node("Val")
	if item_id == "":
		bg.color = CrtTheme.SLOT_EMPTY; bg.size = Vector2(SLOT_W, SLOT_H); icon.texture = null; lbl.text = ""; s.z_index = 0; return
	
	var data = inv.get_item_data(item_id) if inv else {}
	bg.color = data.get("color", Color(0.5,0.5,0.5)).darkened(0.3)
	var sz = data.get("size", [1, 1])
	var w = int(sz[0]); var h = int(sz[1])
	bg.size = Vector2(w * SLOT_W + (w - 1) * SLOT_GAP, h * SLOT_H + (h - 1) * SLOT_GAP)
	icon.size = bg.size
	s.z_index = 1 if (w > 1 or h > 1) else 0
	
	var p = "res://Asset/Image/item/%s.png" % item_id
	icon.texture = load(p) if ResourceLoader.exists(p) else null
	var val = int(data.get("value", 0))
	lbl.text = "₩" + str(val) if val > 0 else ""
	lbl.size = bg.size

func _find_anchor(ptype: String, idx: int) -> int:
	var cols = TRUNK_COLS if ptype == "trunk" else SHOP_COLS
	var cr = idx / cols; var cc = idx % cols
	var dict = inv.trunk if ptype == "trunk" else _shop_items
	
	if ptype == "trunk":
		for i in dict.size():
			if str(dict[i]) == "": continue
			var sz = inv.get_item_data(str(dict[i])).get("size", [1,1])
			if sz[0] == 1 and sz[1] == 1: continue
			var r = i / cols; var c = i % cols
			if cr >= r and cr < r + sz[1] and cc >= c and cc < c + sz[0]: return i
	else:
		for i in dict.keys():
			var item = str(dict[i])
			if item == "": continue
			var sz = inv.get_item_data(item).get("size", [1,1])
			if sz[0] == 1 and sz[1] == 1: continue
			var r = i / cols; var c = i % cols
			if cr >= r and cr < r + sz[1] and cc >= c and cc < c + sz[0]: return i
	return idx

func _can_fit(ptype: String, item_id: String, start_idx: int, ignore_idx: int = -1) -> bool:
	var cols = TRUNK_COLS if ptype == "trunk" else SHOP_COLS
	var rows = TRUNK_ROWS if ptype == "trunk" else SHOP_ROWS
	var sz = inv.get_item_data(item_id).get("size", [1,1])
	var w = int(sz[0]); var h = int(sz[1])
	var r = start_idx / cols; var c = start_idx % cols
	if r + h > rows or c + w > cols: return false
	
	for dr in h:
		for dc in w:
			var idx = (r + dr) * cols + (c + dc)
			var anchor = _find_anchor(ptype, idx)
			if anchor != idx: # covered by another large item
				if anchor != ignore_idx: return false
			else:
				var has_item = (inv.trunk[idx] != "") if ptype == "trunk" else _shop_items.has(idx)
				if has_item and idx != ignore_idx: return false
	return true

func _on_slot_input(ev: InputEvent, ptype: String, idx: int) -> void:
	if not ev is InputEventMouseButton or not ev.pressed: return
	_info_label.text = ""
	
	var interaction_idx = idx
	if _held_item == "": interaction_idx = _find_anchor(ptype, idx)
	
	var item_id = str(inv.trunk[interaction_idx]) if ptype == "trunk" else str(_shop_items.get(interaction_idx, ""))
	var data = inv.get_item_data(item_id) if item_id != "" else {}
	var val = int(data.get("value", 0))

	if ev.button_index == MOUSE_BUTTON_RIGHT:
		if _held_item != "": return # 들고 있을 땐 우클릭 무시
		if item_id == "": return
		if ptype == "trunk":
			# 판매 (가치가 있는 모든 템 판매 가능: 잡품, 부품, 소모품 등)
			inv.money += val
			inv.trunk[interaction_idx] = ""
			_refresh_money(); _refresh_all_slots()
		elif ptype == "shop":
			# 즉시 구매 (첫 빈칸)
			if inv.money < val: _info_label.text = "자금이 부족합니다."; return
			var placed_idx = -1
			for i in inv.trunk.size():
				if _can_fit("trunk", item_id, i):
					placed_idx = i; break
			if placed_idx == -1: _info_label.text = "트렁크가 가득 찼습니다."; return
			inv.money -= val
			inv.trunk[placed_idx] = item_id
			_shop_items.erase(interaction_idx)
			_refresh_money(); _refresh_all_slots()
		return

	if ev.button_index == MOUSE_BUTTON_LEFT:
		if _held_item == "":
			if item_id == "": return
			# 줍기
			_held_item = item_id; _held_from_type = ptype; _held_from_idx = interaction_idx
			if ptype == "trunk": inv.trunk[interaction_idx] = ""
			else: _shop_items.erase(interaction_idx)
			_refresh_all_slots(); _update_drag_vis()
		else:
			# 놓기
			if not _can_fit(ptype, _held_item, idx, _held_from_idx if ptype == _held_from_type else -1):
				_info_label.text = "공간이 부족합니다."
				return
				
			var held_val = int(inv.get_item_data(_held_item).get("value", 0))
			if ptype == "trunk":
				if _held_from_type == "shop":
					if inv.money < held_val: _info_label.text = "자금이 부족합니다."; return
					inv.money -= held_val
				var swap = str(inv.trunk[idx])
				inv.trunk[idx] = _held_item
				if swap != "":
					if _held_from_type == "shop": _shop_items[_held_from_idx] = swap; inv.money += int(inv.get_item_data(swap).get("value",0)) # 환불/판매 처리 단순화
					else: inv.trunk[_held_from_idx] = swap
			elif ptype == "shop":
				# 상점에 놓기 = 판매 혹은 제자리 돌려놓기
				if _held_from_type == "trunk":
					inv.money += held_val
				var swap = str(_shop_items.get(idx, ""))
				_shop_items[idx] = _held_item
				if swap != "":
					if _held_from_type == "trunk": inv.trunk[_held_from_idx] = swap; inv.money -= int(inv.get_item_data(swap).get("value",0))
					else: _shop_items[_held_from_idx] = swap
			
			_held_item = ""; _held_from_type = ""; _held_from_idx = -1
			_refresh_money(); _refresh_all_slots(); _update_drag_vis()

func _update_drag_vis() -> void:
	if _held_item == "": _drag_panel.visible = false; return
	_drag_panel.visible = true
	var data = inv.get_item_data(_held_item)
	var sz = data.get("size", [1, 1])
	var w = int(sz[0]); var h = int(sz[1])
	_drag_panel.size = Vector2(w * SLOT_W + (w - 1) * SLOT_GAP, h * SLOT_H + (h - 1) * SLOT_GAP)
	
	var c = data.get("color", Color(0.5,0.5,0.5))
	var style = StyleBoxFlat.new(); style.bg_color = c.darkened(0.2); style.border_color = c
	style.border_width_left = 2; style.border_width_top = 2; style.border_width_right = 2; style.border_width_bottom = 2
	_drag_panel.add_theme_stylebox_override("panel", style)
	var p = "res://Asset/Image/item/%s.png" % _held_item
	_drag_icon.texture = load(p) if ResourceLoader.exists(p) else null

func _unhandled_input(ev: InputEvent) -> void:
	if not _root.visible: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		_return_held_item()

func _return_held_item() -> void:
	if _held_item == "": return
	if _held_from_type == "trunk": inv.trunk[_held_from_idx] = _held_item
	elif _held_from_type == "shop": _shop_items[_held_from_idx] = _held_item
	_held_item = ""; _update_drag_vis(); _refresh_all_slots()

# --- Slay the Spire 스타일 노드맵 라우트 ---

const NODE_TYPES := {
	"normal": {"label": "일반 도로", "desc": "평범한 국도.", "color": Color(0.6, 0.6, 0.6), "icon": "🛣️"},
	"wreck":  {"label": "폐차 밀집", "desc": "파밍 최적. 도로 불량.", "color": Color(0.8, 0.5, 0.2), "icon": "🚗"},
	"dark":   {"label": "암흑",     "desc": "가로등 없음. 감지↓.", "color": Color(0.3, 0.2, 0.5), "icon": "🌑"},
	"cult":   {"label": "컬트 밀집", "desc": "잡품↑. 적 밀도↑.", "color": Color(0.7, 0.2, 0.2), "icon": "👥"},
	"weather":{"label": "날씨",     "desc": "괴물 속도↓. 시야↓.", "color": Color(0.3, 0.5, 0.7), "icon": "🌧️"},
}

# ── 맵 상태 (런 전체에서 유지) ──
var _map_nodes: Array = []       # [{col, row, type, pos, connections}]
var _map_generated: bool = false # 맵이 생성되었는지
var _player_node_idx: int = 0    # 현재 플레이어가 있는 노드 인덱스
var _selectable_nodes: Array = [] # 현재 선택 가능한 노드 인덱스 목록
var _visited_nodes: Array = []   # 지나온 노드 인덱스 목록

# ── UI 노드 ──
var _map_draw: Control
var _hovered_node: int = -1
var _car_icon_tex: Texture2D
var _tooltip_lbl: Label
var _back_btn: Button

const MAP_COLS := 7           # col 0=출발, col 1~5=스테이지 선택, col 6=목적지
const MAP_PATHS := 4          # 경로 수
const MAP_LEFT := 140.0
const MAP_RIGHT := 1140.0
const MAP_TOP := 180.0
const MAP_BOT := 540.0
const NODE_RADIUS := 16.0
const NODE_RADIUS_HOVER := 20.0
const BEZIER_SEGMENTS := 16

# 열(col)별 노드 타입 가중치 — 뒤로 갈수록 위험한 타입 증가
func _get_col_weights(col: int) -> Dictionary:
	match col:
		1: return {"normal": 5, "wreck": 3, "weather": 2, "dark": 0, "cult": 0}
		2: return {"normal": 3, "wreck": 3, "weather": 3, "dark": 2, "cult": 1}
		3: return {"normal": 2, "wreck": 3, "weather": 3, "dark": 3, "cult": 2}
		4: return {"normal": 1, "wreck": 2, "weather": 3, "dark": 4, "cult": 3}
		5: return {"normal": 0, "wreck": 2, "weather": 2, "dark": 4, "cult": 4}
		_: return {"normal": 3, "wreck": 2, "weather": 2, "dark": 2, "cult": 2}

func reset_map() -> void:
	_map_nodes.clear()
	_map_generated = false
	_player_node_idx = 0
	_selectable_nodes.clear()
	_visited_nodes.clear()

func _build_routes() -> void:
	if _car_icon_tex == null:
		_car_icon_tex = load("res://Asset/Image/car_icon.png") as Texture2D
	for c in _route_panel.get_children(): c.queue_free()
	_hovered_node = -1

	var title = Label.new()
	title.text = "경로 선택"
	CrtTheme.style_label(title, 28, CrtTheme.AMBER_BRIGHT)
	title.position = Vector2(MAP_LEFT, 80)
	_route_panel.add_child(title)

	var stage_lbl = Label.new()
	stage_lbl.text = "스테이지 %d → %d" % [current_stage, current_stage + 1]
	CrtTheme.style_label(stage_lbl, 18, CrtTheme.AMBER_DIM)
	stage_lbl.position = Vector2(MAP_LEFT, 115)
	_route_panel.add_child(stage_lbl)

	_back_btn = Button.new()
	_back_btn.text = "← 정비소로"
	_back_btn.position = Vector2(MAP_RIGHT - 130, 80)
	_back_btn.size = Vector2(130, 36)
	CrtTheme.style_button(_back_btn, 14)
	_back_btn.pressed.connect(func(): _switch_mode("shop"))
	_route_panel.add_child(_back_btn)

	# 맵은 런 시작 시 1번만 생성
	if not _map_generated:
		_generate_map()

	# 현재 노드에서 선택 가능한 노드 계산
	_selectable_nodes.clear()
	var cur = _map_nodes[_player_node_idx]
	for c_idx in cur.connections:
		_selectable_nodes.append(c_idx)

	_map_draw = Control.new()
	_map_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_draw.draw.connect(_on_map_draw)
	_map_draw.gui_input.connect(_on_map_input)
	_map_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	_route_panel.add_child(_map_draw)

	_tooltip_lbl = Label.new()
	_tooltip_lbl.visible = false
	CrtTheme.style_label(_tooltip_lbl, 16, CrtTheme.AMBER_BRIGHT)
	_tooltip_lbl.z_index = 50
	_route_panel.add_child(_tooltip_lbl)

func _pick_weighted_type(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for w in weights.values():
		total += int(w)
	if total <= 0:
		return "normal"
	var roll := rng.randi_range(0, total - 1)
	var cumul := 0
	for t in weights:
		cumul += int(weights[t])
		if roll < cumul:
			return t
	return "normal"

func _generate_map() -> void:
	_map_nodes.clear()
	_visited_nodes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()  # 매 런마다 다른 맵

	# grid[col] = [{row, type}]
	var grid: Array = []
	for _c in MAP_COLS:
		grid.append([])

	var center_row := MAP_PATHS / 2
	grid[0].append({"row": center_row, "type": "normal"})
	grid[MAP_COLS - 1].append({"row": center_row, "type": "normal"})

	# 경로 생성
	var path_rows: Array = []
	for p in MAP_PATHS:
		var row_seq: Array = []
		var cur_row: int = p
		for col in range(1, MAP_COLS - 1):
			var drift = rng.randi_range(-1, 1)
			cur_row = clampi(cur_row + drift, 0, MAP_PATHS - 1)
			row_seq.append(cur_row)
		path_rows.append(row_seq)

	# 중간 열 노드 생성 — 열별 가중치 적용
	for col in range(1, MAP_COLS - 1):
		var used_rows: Dictionary = {}
		var col_weights := _get_col_weights(col)
		for p in MAP_PATHS:
			var row = path_rows[p][col - 1]
			if not used_rows.has(row):
				used_rows[row] = _pick_weighted_type(rng, col_weights)
		var sorted_rows = used_rows.keys()
		sorted_rows.sort()
		for row in sorted_rows:
			grid[col].append({"row": row, "type": used_rows[row]})

	# grid → _map_nodes + 좌표
	var col_node_map: Array = []
	for _c in MAP_COLS:
		col_node_map.append({})

	for col in MAP_COLS:
		var entries = grid[col]
		for entry in entries:
			var row: int = entry.row
			var x = MAP_LEFT + float(col) / float(MAP_COLS - 1) * (MAP_RIGHT - MAP_LEFT)
			var y: float
			if MAP_PATHS == 1:
				y = (MAP_TOP + MAP_BOT) * 0.5
			else:
				y = MAP_TOP + float(row) / float(MAP_PATHS - 1) * (MAP_BOT - MAP_TOP)
			if col > 0 and col < MAP_COLS - 1:
				x += rng.randf_range(-15.0, 15.0)
				y += rng.randf_range(-18.0, 18.0)
			var idx = _map_nodes.size()
			col_node_map[col][row] = idx
			_map_nodes.append({
				"col": col,
				"row": row,
				"type": entry.type,
				"pos": Vector2(x, y),
				"connections": [],
			})

	# 연결선
	for p in MAP_PATHS:
		var start_idx = col_node_map[0].values()[0]
		var row_1 = path_rows[p][0]
		if col_node_map[1].has(row_1):
			var target = col_node_map[1][row_1]
			if target not in _map_nodes[start_idx].connections:
				_map_nodes[start_idx].connections.append(target)

		for ci in range(1, MAP_COLS - 2):
			var from_row = path_rows[p][ci - 1]
			var to_row = path_rows[p][ci]
			if col_node_map[ci].has(from_row) and col_node_map[ci + 1].has(to_row):
				var from_idx = col_node_map[ci][from_row]
				var to_idx = col_node_map[ci + 1][to_row]
				if to_idx not in _map_nodes[from_idx].connections:
					_map_nodes[from_idx].connections.append(to_idx)

		var last_mid := MAP_COLS - 2
		var last_row = path_rows[p][last_mid - 1]
		if col_node_map[last_mid].has(last_row):
			var from_idx = col_node_map[last_mid][last_row]
			var end_idx = col_node_map[MAP_COLS - 1].values()[0]
			if end_idx not in _map_nodes[from_idx].connections:
				_map_nodes[from_idx].connections.append(end_idx)

	# 초기 상태
	_player_node_idx = col_node_map[0].values()[0]
	_visited_nodes.append(_player_node_idx)
	_map_generated = true

func _on_map_draw() -> void:
	if _map_draw == null: return

	# 연결선 (베지어 곡선)
	for nd in _map_nodes:
		for c_idx in nd.connections:
			var to = _map_nodes[c_idx]
			var from_pos: Vector2 = nd.pos
			var to_pos: Vector2 = to.pos
			# 지나온 경로는 밝게, 선택 가능 경로는 중간, 나머지는 어둡게
			var from_idx = _map_nodes.find(nd)
			var line_color: Color
			if from_idx in _visited_nodes and c_idx in _visited_nodes:
				line_color = Color(0.93, 0.85, 0.55, 0.9)
			elif from_idx == _player_node_idx and c_idx in _selectable_nodes:
				line_color = Color(0.75, 0.70, 0.45, 0.8)
			else:
				line_color = Color(0.45, 0.40, 0.25, 0.5)
			_draw_bezier(from_pos, to_pos, line_color, 1.5)

	# 노드
	for i in _map_nodes.size():
		var nd = _map_nodes[i]
		var type_data = NODE_TYPES.get(nd.type, NODE_TYPES["normal"])
		var col_color: Color = type_data.color
		var is_player = (i == _player_node_idx)
		var is_visited = (i in _visited_nodes and i != _player_node_idx)
		var is_end = (nd.col == MAP_COLS - 1)
		var is_selectable = (i in _selectable_nodes)
		var is_hover = (i == _hovered_node)
		var radius = NODE_RADIUS_HOVER if is_hover else NODE_RADIUS

		if is_player:
			# 현재 위치 — 밝은 흰색 + 펄스
			_map_draw.draw_circle(nd.pos, radius + 2, CrtTheme.AMBER_BRIGHT)
			_map_draw.draw_arc(nd.pos, radius + 5, 0, TAU, 32, Color(0.93, 0.85, 0.55, 0.3), 2.0)
			# 차 아이콘 표시
			if _car_icon_tex != null:
				var icon_h := 28.0
				var icon_w := icon_h * float(_car_icon_tex.get_width()) / maxf(float(_car_icon_tex.get_height()), 1.0)
				var icon_rect := Rect2(nd.pos.x - icon_w * 0.5, nd.pos.y - radius - 6 - icon_h, icon_w, icon_h)
				_map_draw.draw_texture_rect(_car_icon_tex, icon_rect, false)
		elif is_visited:
			# 지나온 노드 — 어둡게 표시
			_map_draw.draw_circle(nd.pos, radius * 0.7, col_color.darkened(0.4))
			_map_draw.draw_arc(nd.pos, radius * 0.7 + 1, 0, TAU, 24, CrtTheme.AMBER_DIM, 1.5)
		elif is_end:
			_map_draw.draw_circle(nd.pos, radius, Color(0.9, 0.8, 0.3, 0.8))
			_map_draw.draw_arc(nd.pos, radius + 2, 0, TAU, 32, Color(0.9, 0.8, 0.3, 0.4), 2.0)
		elif is_selectable:
			if is_hover:
				_map_draw.draw_circle(nd.pos, radius + 5, Color(1, 1, 1, 0.12))
			_map_draw.draw_circle(nd.pos, radius, col_color)
			_map_draw.draw_arc(nd.pos, radius + 2, 0, TAU, 32, col_color.lightened(0.4), 2.0)
			_draw_node_label(nd.pos, type_data.icon)
		else:
			# 미래 노드 — 어둡게
			var dim = col_color.darkened(0.45)
			dim.a = 0.6
			_map_draw.draw_circle(nd.pos, radius * 0.65, dim)
			_map_draw.draw_arc(nd.pos, radius * 0.65 + 1, 0, TAU, 24, dim.lightened(0.15), 1.0)

func _draw_bezier(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var cx = (to.x - from.x) * 0.4
	var cp1 = from + Vector2(cx, 0)
	var cp2 = to - Vector2(cx, 0)
	var prev = from
	for s in range(1, BEZIER_SEGMENTS + 1):
		var t = float(s) / float(BEZIER_SEGMENTS)
		var it = 1.0 - t
		var pt = it*it*it*from + 3.0*it*it*t*cp1 + 3.0*it*t*t*cp2 + t*t*t*to
		_map_draw.draw_line(prev, pt, color, width, true)
		prev = pt

func _draw_node_label(pos: Vector2, icon_text: String) -> void:
	var font = ThemeDB.fallback_font
	var fsize = 14
	var text_size = font.get_string_size(icon_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
	_map_draw.draw_string(font, pos - Vector2(text_size.x * 0.5, -fsize * 0.35), icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)

func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var prev = _hovered_node
		_hovered_node = -1
		var mpos: Vector2 = ev.position
		for i in _selectable_nodes:
			if _map_nodes[i].pos.distance_to(mpos) <= NODE_RADIUS_HOVER + 8:
				_hovered_node = i
				break
		if _hovered_node != prev:
			_update_tooltip(mpos)
			_map_draw.queue_redraw()

	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if _hovered_node >= 0 and _hovered_node in _selectable_nodes:
			var nd = _map_nodes[_hovered_node]
			# 플레이어를 선택한 노드로 이동
			_visited_nodes.append(_hovered_node)
			_player_node_idx = _hovered_node
			_on_route_selected(nd.type)

func _update_tooltip(mpos: Vector2) -> void:
	if _hovered_node < 0:
		_tooltip_lbl.visible = false
		return
	var nd = _map_nodes[_hovered_node]
	var td = NODE_TYPES.get(nd.type, NODE_TYPES["normal"])
	_tooltip_lbl.text = "%s %s\n%s" % [td.icon, td.label, td.desc]
	_tooltip_lbl.position = nd.pos + Vector2(NODE_RADIUS_HOVER + 10, -20)
	if _tooltip_lbl.position.x + 200 > MAP_RIGHT:
		_tooltip_lbl.position.x = nd.pos.x - NODE_RADIUS_HOVER - 180
	_tooltip_lbl.visible = true

func _on_route_selected(rtype: String) -> void:
	close()
	depart_requested.emit(rtype)
