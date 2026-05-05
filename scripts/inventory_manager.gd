extends Node
class_name InventoryManager

const TRUNK_COLS := 5
const TRUNK_ROWS := 4
const TRUNK_SIZE := TRUNK_COLS * TRUNK_ROWS  # 20칸

# 트렁크: "" = 빈 슬롯
var trunk: Array = []

# 폐차 상태 캐싱: wreck_seed -> { items: Dictionary, revealed: Array, search_slot: int, search_timer: float, search_done: bool }
var wreck_states: Dictionary = {}

# ── 아이템 데이터베이스 ───────────────────────────────────
# color: BGR hex string (Color() 생성용)
const ITEM_DB := {
	"fuel_can":    {"name": "기름통(10L)",    "type": "consumable", "value": 0,     "color": Color(0.78, 0.59, 0.12), "size": [2, 2]},
	"patch_kit":   {"name": "타이어패치킷",   "type": "consumable", "value": 0,     "color": Color(0.43, 0.75, 0.27)},
	"cigarette":   {"name": "담배",           "type": "consumable", "value": 0,     "color": Color(0.91, 0.85, 0.63)},
	"scrap":       {"name": "고철덩어리",     "type": "junk",       "value": 300,   "color": Color(0.47, 0.47, 0.47)},
	"aluminum":    {"name": "알루미늄캔",     "type": "junk",       "value": 500,   "color": Color(0.63, 0.63, 0.75)},
	"copper_wire": {"name": "동선묶음",       "type": "junk",       "value": 1000,  "color": Color(0.75, 0.47, 0.20)},
	"wiper_blade": {"name": "와이퍼블레이드", "type": "junk",       "value": 1000,  "color": Color(0.47, 0.59, 0.66), "size": [2, 1]},
	"oil_filter":  {"name": "오일필터",       "type": "junk",       "value": 1500,  "color": Color(0.63, 0.50, 0.31)},
	"spark_plug":  {"name": "스파크플러그",   "type": "junk",       "value": 2000,  "color": Color(0.78, 0.78, 0.31)},
	"battery":     {"name": "중고배터리",     "type": "junk",       "value": 3000,  "color": Color(0.31, 0.63, 0.31)},
	"side_mirror": {"name": "사이드미러",     "type": "junk",       "value": 4000,  "color": Color(0.39, 0.71, 0.78)},
	"canned_food": {"name": "통조림",         "type": "junk",       "value": 2000,  "color": Color(0.78, 0.63, 0.31)},
	"flashlight":  {"name": "손전등",         "type": "junk",       "value": 3000,  "color": Color(0.90, 0.90, 0.31)},
	"first_aid":   {"name": "상비약세트",     "type": "junk",       "value": 5000,  "color": Color(0.87, 0.31, 0.31)},
	"tool_set":    {"name": "공구세트",       "type": "junk",       "value": 7000,  "color": Color(0.59, 0.39, 0.31), "size": [2, 1]},
	"smartphone":  {"name": "스마트폰",       "type": "junk",       "value": 10000, "color": Color(0.47, 0.47, 0.78)},
	"wallet":      {"name": "지갑",           "type": "junk",       "value": 10000, "color": Color(0.78, 0.71, 0.20)},
	"gold_ring":   {"name": "금반지",         "type": "junk",       "value": 20000, "color": Color(0.94, 0.78, 0.00)},
	"mil_supply":  {"name": "군용물자",       "type": "junk",       "value": 25000, "color": Color(0.35, 0.55, 0.27), "size": [1, 1]},
	"big_engine":  {"name": "대형 엔진(테스트)", "type": "part",       "value": 50000, "color": Color(0.90, 0.20, 0.20), "size": [3, 2]},
}

func _ready() -> void:
	trunk.resize(TRUNK_SIZE)
	for i in TRUNK_SIZE:
		trunk[i] = ""

# ── 폐차 드롭 생성 ────────────────────────────────────────
# wreck_seed: 폐차 k 값 기반. 반환: 상태 딕셔너리
func get_or_generate_wreck_state(wreck_seed: int, wreck_cols: int, wreck_rows: int) -> Dictionary:
	if wreck_states.has(wreck_seed):
		return wreck_states[wreck_seed]

	var rng := RandomNumberGenerator.new()
	rng.seed = wreck_seed

	# 각 아이템 독립 확률 판정
	var drop_table := [
		["fuel_can",    0.25],
		["patch_kit",   0.20],
		["cigarette",   0.15],
		["scrap",       0.60],
		["aluminum",    0.45],
		["copper_wire", 0.30],
		["wiper_blade", 0.25],
		["oil_filter",  0.22],
		["spark_plug",  0.18],
		["battery",     0.13],
		["side_mirror", 0.09],
		["canned_food", 0.22],
		["flashlight",  0.18],
		["first_aid",   0.12],
		["tool_set",    0.08],
		["smartphone",  0.04],
		["wallet",      0.06],
		["gold_ring",   0.02],
		["mil_supply",  0.02],
	]

	var dropped: Array = []
	for entry in drop_table:
		if rng.randf() < float(entry[1]):
			dropped.append(str(entry[0]))

	var total_slots := wreck_cols * wreck_rows
	var result: Dictionary = {}
	var occupied: Array = []
	
	# 1. 대형 엔진(2x2) 먼저 배치 (경계 안넘어가게)
	var engine_corners := []
	for r in range(wreck_rows - 1):
		for c in range(wreck_cols - 1):
			engine_corners.append(r * wreck_cols + c)
	engine_corners.shuffle()
	
	if engine_corners.size() > 0:
		var corner : int = engine_corners[0]
		result[corner] = "big_engine"
		var cr := corner / wreck_cols
		var cc := corner % wreck_cols
		# 2x2 영역 점유 (다른 1x1 아이템이 안 들어가게)
		for dr in 2:
			for dc in 2:
				occupied.append((cr + dr) * wreck_cols + (cc + dc))

	# 2. 나머지 1x1 아이템 배치
	var available: Array = []
	for i in total_slots:
		if not occupied.has(i):
			available.append(i)
	available.shuffle()

	for i in mini(dropped.size(), available.size()):
		result[available[i]] = dropped[i]

	var revealed_arr := []
	revealed_arr.resize(total_slots)
	for i in total_slots:
		revealed_arr[i] = false

	var state = {
		"items": result,
		"revealed": revealed_arr,
		"search_slot": 0,
		"search_timer": 0.0,
		"search_done": false
	}
	wreck_states[wreck_seed] = state
	return state

# ── 트렁크 조작 ───────────────────────────────────────────
func trunk_add(item_id: String) -> int:
	var data := get_item_data(item_id)
	var sz : Array = data.get("size", [1, 1])
	var w : int = sz[0]
	var h : int = sz[1]
	
	for r in range(TRUNK_ROWS - h + 1):
		for c in range(TRUNK_COLS - w + 1):
			if can_fit_item(item_id, r * TRUNK_COLS + c):
				trunk[r * TRUNK_COLS + c] = item_id
				return r * TRUNK_COLS + c
	return -1

func can_fit_item(item_id: String, start_idx: int) -> bool:
	var data := get_item_data(item_id)
	var sz : Array = data.get("size", [1, 1])
	var w : int = sz[0]
	var h : int = sz[1]
	
	var start_r := start_idx / TRUNK_COLS
	var start_c := start_idx % TRUNK_COLS
	
	if start_r + h > TRUNK_ROWS or start_c + w > TRUNK_COLS:
		return false
		
	# 해당 영역이 다른 아이템의 '시각적 점유' 영역과 겹치는지 확인
	for r in range(start_r, start_r + h):
		for c in range(start_c, start_c + w):
			var idx := r * TRUNK_COLS + c
			# 1. 해당 슬롯 자체에 아이템이 있는가?
			if str(trunk[idx]) != "":
				return false
			# 2. 다른 슬롯에 있는 큰 아이템이 이 구역을 덮고 있는가?
			if _get_covering_item_idx(idx, start_idx) != -1:
				return false
	return true

func get_blocking_items(item_id: String, start_idx: int) -> Array:
	var blocks := []
	var data := get_item_data(item_id)
	var sz : Array = data.get("size", [1, 1])
	var w : int = sz[0]
	var h : int = sz[1]
	
	var start_r := start_idx / TRUNK_COLS
	var start_c := start_idx % TRUNK_COLS
	
	if start_r + h > TRUNK_ROWS or start_c + w > TRUNK_COLS:
		return [-1] # Out of bounds
		
	for r in range(start_r, start_r + h):
		for c in range(start_c, start_c + w):
			var idx := r * TRUNK_COLS + c
			if str(trunk[idx]) != "":
				if not blocks.has(idx):
					blocks.append(idx)
			var covering_idx := _get_covering_item_idx(idx, start_idx)
			if covering_idx != -1 and not blocks.has(covering_idx):
				blocks.append(covering_idx)
	return blocks

func _get_covering_item_idx(check_idx: int, ignore_idx: int = -1) -> int:
	var cr := check_idx / TRUNK_COLS
	var cc := check_idx % TRUNK_COLS
	
	for i in TRUNK_SIZE:
		if i == ignore_idx: continue
		var other_id := str(trunk[i])
		if other_id == "": continue
		
		var odata := get_item_data(other_id)
		var osz : Array = odata.get("size", [1, 1])
		if int(osz[0]) == 1 and int(osz[1]) == 1: continue
		
		var orow := i / TRUNK_COLS
		var ocol := i % TRUNK_COLS
		if cr >= orow and cr < orow + int(osz[1]) and cc >= ocol and cc < ocol + int(osz[0]):
			return i
	return -1

func trunk_remove(slot_idx: int) -> String:
	if slot_idx < 0 or slot_idx >= TRUNK_SIZE:
		return ""
	var item := str(trunk[slot_idx])
	trunk[slot_idx] = ""
	return item

func trunk_set(slot_idx: int, item_id: String) -> void:
	if slot_idx >= 0 and slot_idx < TRUNK_SIZE:
		trunk[slot_idx] = item_id

func is_trunk_full() -> bool:
	for item in trunk:
		if str(item) == "":
			return false
	return true

func get_item_data(item_id: String) -> Dictionary:
	return ITEM_DB.get(item_id, {})

func sort_trunk() -> void:
	# 1. 모든 아이템 수집
	var items := []
	for item in trunk:
		if str(item) != "":
			items.append(str(item))
	
	# 2. 트렁크 비우기
	for i in TRUNK_SIZE:
		trunk[i] = ""
	
	# 3. 큰 아이템부터 배치 (면적 내림차순 정렬)
	var big_items := []
	var small_items := []
	for item_id in items:
		var data := get_item_data(item_id)
		var sz : Array = data.get("size", [1, 1])
		if int(sz[0]) > 1 or int(sz[1]) > 1:
			big_items.append(item_id)
		else:
			small_items.append(item_id)
	
	# 큰 아이템 먼저 배치
	for item_id in big_items:
		var placed := false
		for r in TRUNK_ROWS:
			for c in TRUNK_COLS:
				var idx := r * TRUNK_COLS + c
				if can_fit_item(item_id, idx):
					trunk[idx] = item_id
					placed = true
					break
			if placed: break
	
	# 4. 작은 아이템은 비어있고 덮이지 않은 슬롯에 배치
	var si := 0
	for i in TRUNK_SIZE:
		if si >= small_items.size(): break
		if str(trunk[i]) != "": continue
		if _get_covering_item_idx(i) != -1: continue
		trunk[i] = small_items[si]
		si += 1
