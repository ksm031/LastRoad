extends Node
class_name MetaProgression

# ── 세이브 경로 ──
const SAVE_PATH := "user://meta_save.dat"

# ── 포인트 경제 ──
const POINTS_PER_STAGE  := 15
const FULL_CLEAR_BONUS  := 40
const TOTAL_STAGES      := 6

# ── 퍽 데이터 ──────────────────────────────────────────────────
# 각 퍽: id, name, desc, branch, tier, cost, prereq(선행 퍽 id 또는 "")
const PERKS := [
	# A. 탐험 (branch 0)
	{"id": "keen_eye_new",     "name": "날카로운 눈",     "desc": "적 감지 거리 +20% 및 갓길 수색 속도 +25%", "branch": 0, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "deeper_shoulder",  "name": "더 깊은 갓길",    "desc": "갓길 파편 파밍 시 1행 5칸 비밀 슬롯 임시 추가", "branch": 0, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "rusty_handle",     "name": "녹슨 손잡이",     "desc": "슬롯머신 1회 비용 ₩3,000 → ₩2,000",          "branch": 0, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "famous_shop",      "name": "소문난 상점",     "desc": "정비소 부품 및 가솔린 15% 할인",             "branch": 0, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "hidden_route",     "name": "숨겨진 경로",     "desc": "스테이지 이동 시 무작위 추가 아이템 1개 파밍", "branch": 0, "tier": 3, "cost": 60, "prereq": ""},

	# B. 유물 (branch 1)
	{"id": "first_luck",       "name": "첫 번째 행운",    "desc": "런 시작 시 무작위 1티어 부적 1개 즉시 장착",    "branch": 1, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "junk_collector",   "name": "잡동사니 수집가", "desc": "부적 판매가 2배 (+중복 획득 시 ₩2,500 환급)", "branch": 1, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "rich_display",     "name": "풍성한 진열대",   "desc": "정비소 부적 진열 슬롯 2개 → 3개 확장",        "branch": 1, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "slot_taming",      "name": "슬롯머신 길들이기", "desc": "슬롯머신 성공률 70% → 85% 향상",             "branch": 1, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "unknown_relic",    "name": "미지의 유물",     "desc": "부적 DB 히든 부적 5종 해금",                "branch": 1, "tier": 3, "cost": 60, "prereq": ""},

	# C. 생존 (branch 2)
	{"id": "trunk_expand",     "name": "트렁크 확장",     "desc": "기본 트렁크 세로 슬롯 +1줄 (5x4 → 5x5)",     "branch": 2, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "emergency_fuel",   "name": "비상 연료",       "desc": "연료 0% 시 5초 동안 20km/h로 비상 주행 허용", "branch": 2, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "cigarette_taste",  "name": "담배의 맛",       "desc": "담배 사용 시 정신력 +10% 추가 및 10초간 전조등 1.5배", "branch": 2, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "emergency_repair", "name": "응급 수리",       "desc": "매 스테이지 3 진입 시 30% 이하인 부품 30% 복구", "branch": 2, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "last_resort",      "name": "마지막 발악",     "desc": "정신력 0 상태일 때 화면 왜곡 효과 30% 감쇄",   "branch": 2, "tier": 3, "cost": 60, "prereq": ""},

	# D. 운명 (branch 3)
	{"id": "premonition",      "name": "예감",           "desc": "사슴머리/도망자 출현 3.0초 전 나침반 깜빡임 경고", "branch": 3, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "radio_secret",     "name": "라디오의 비밀",   "desc": "라디오 죽음의 주파수 명료도 향상 1단계 해금",   "branch": 3, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "reality_sense",    "name": "현실 감각",       "desc": "정신력 환각 연출 트리거 임계값 40% → 30% 감소",  "branch": 3, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "fate_reroll",      "name": "운명 재굴림",     "desc": "스테이지 선택 시 루트 재굴림 기회 1회 지급",    "branch": 3, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "legacy",           "name": "유산",           "desc": "사망 시 소지 자금의 30%를 다음 런으로 인계",    "branch": 3, "tier": 3, "cost": 60, "prereq": ""},

	# 21번째 히든 퍽 (branch -1)
	{"id": "locked_slot",      "name": "잠긴 칸",         "desc": "인벤토리 우하단 잠긴 칸 해제 (시체 자동 적재)", "branch": -1, "tier": 1, "cost": 0, "prereq": ""},
]

const BRANCH_NAMES := ["탐험", "유물", "생존", "운명"]
const BRANCH_COLORS := [
	Color(0.2, 0.6, 0.9),   # 탐험: 시원한 파랑
	Color(0.9, 0.7, 0.2),   # 유물: 골드/옐로우
	Color(0.8, 0.2, 0.2),   # 생존: 레드/크림슨
	Color(0.5, 0.2, 0.8),   # 운명: 딥 퍼플
]

# ── 런타임 상태 ──
var total_points   : int = 0           # 누적 보유 포인트 (퍽용)
var unlocked_perks : Dictionary = {}   # id -> true

# ── 진엔딩 및 상태 세이브 필드 ──
var locked_slot_unlocked: bool = false
var corpse_cutscene_played: bool = false
var corpse_disposed: bool = false
var true_ending_clear: bool = false
var fleeing_hit_count: int = 0
var a_ending_count: int = 0

func _ready() -> void:
	load_data()

# ── 퍽 해금 가능 여부 판정 ──
func can_unlock(perk_id: String) -> bool:
	if unlocked_perks.has(perk_id):
		return false
	var perk := _find_perk(perk_id)
	if perk.is_empty():
		return false
	if total_points < int(perk["cost"]):
		return false
		
	# 21번째 퍽 (locked_slot) 특수 조건
	if perk_id == "locked_slot":
		# locked_slot을 제외한 20개 퍽이 모두 해금되었는지 체크
		var normal_unlocked_count := 0
		for p in PERKS:
			if p["id"] != "locked_slot" and unlocked_perks.has(p["id"]):
				normal_unlocked_count += 1
		return normal_unlocked_count >= 20

	# 티어 선행 조건: 같은 브랜치의 이전 티어 퍽 중 하나 이상 해금 필요
	var tier := int(perk["tier"])
	if tier >= 2:
		var branch := int(perk["branch"])
		var has_prev_tier := false
		for p in PERKS:
			if int(p["branch"]) == branch and int(p["tier"]) == tier - 1 and unlocked_perks.has(p["id"]):
				has_prev_tier = true
				break
		if not has_prev_tier:
			return false
	# 특수 선행 조건
	var prereq := str(perk["prereq"])
	if prereq != "" and not unlocked_perks.has(prereq):
		return false
	return true

func unlock_perk(perk_id: String) -> bool:
	if not can_unlock(perk_id):
		return false
	var perk := _find_perk(perk_id)
	total_points -= int(perk["cost"])
	unlocked_perks[perk_id] = true
	if perk_id == "locked_slot":
		locked_slot_unlocked = true
	save_data()
	return true

func has_perk(perk_id: String) -> bool:
	# 편의를 위해 locked_slot은 클래스 변수로도 체크 가능하게 함
	if perk_id == "locked_slot":
		return locked_slot_unlocked
	return unlocked_perks.has(perk_id)

# ── 런 종료 시 포인트 지급 ──
func award_run_points(stages_cleared: int) -> int:
	var pts := stages_cleared * POINTS_PER_STAGE
	if stages_cleared >= TOTAL_STAGES:
		pts += FULL_CLEAR_BONUS
	total_points += pts
	save_data()
	return pts

# ── 세이브 / 로드 ──
func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var data := {
		"total_points": total_points,
		"unlocked_perks": unlocked_perks.keys(),
		"locked_slot_unlocked": locked_slot_unlocked,
		"corpse_cutscene_played": corpse_cutscene_played,
		"corpse_disposed": corpse_disposed,
		"true_ending_clear": true_ending_clear,
		"fleeing_hit_count": fleeing_hit_count,
		"a_ending_count": a_ending_count,
	}
	f.store_string(JSON.stringify(data))
	f.close()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data = json.data
	if data is Dictionary:
		total_points = int(data.get("total_points", 0))
		unlocked_perks.clear()
		var perks_arr = data.get("unlocked_perks", [])
		if perks_arr is Array:
			for pid in perks_arr:
				unlocked_perks[str(pid)] = true
		locked_slot_unlocked = bool(data.get("locked_slot_unlocked", false))
		corpse_cutscene_played = bool(data.get("corpse_cutscene_played", false))
		corpse_disposed = bool(data.get("corpse_disposed", false))
		true_ending_clear = bool(data.get("true_ending_clear", false))
		fleeing_hit_count = int(data.get("fleeing_hit_count", 0))
		a_ending_count = int(data.get("a_ending_count", 0))

func _find_perk(perk_id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == perk_id:
			return p
	return {}

func get_unlocked_count() -> int:
	return unlocked_perks.size()

