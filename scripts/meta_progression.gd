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
	# A. 드라이빙
	{"id": "accel",       "name": "가속 향상",     "desc": "기본 가속도 +10%",              "branch": 0, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "brake",       "name": "제동 향상",     "desc": "기본 브레이크 성능 +15%",       "branch": 0, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "handling",    "name": "핸들 향상",     "desc": "기본 핸들 응답 +15%",           "branch": 0, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "top_speed",   "name": "고속 드라이빙", "desc": "기본 최고속도 +10 km/h",        "branch": 0, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "racer",       "name": "레이서",        "desc": "드라이빙 스탯 전체 +8%",        "branch": 0, "tier": 3, "cost": 60, "prereq": ""},

	# B. 자원
	{"id": "fuel_eff",    "name": "절약 주행",     "desc": "연비 소모 -10%",                "branch": 1, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "trunk_1",     "name": "큰 트렁크",     "desc": "트렁크 +1칸",                   "branch": 1, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "fuel_cap",    "name": "여유 있는 탱크", "desc": "기본 연료 용량 +10L",           "branch": 1, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "fast_loot",   "name": "빠른 손",       "desc": "수색 속도 +25%",                "branch": 1, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "vet_farmer",  "name": "베테랑 파머",   "desc": "트렁크 +1칸 + 잡품 판매가 +10%", "branch": 1, "tier": 3, "cost": 60, "prereq": ""},

	# C. 생존
	{"id": "strong_heart", "name": "강심장",       "desc": "시작 정신력 +15",               "branch": 2, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "smoker_1",     "name": "담배 중독",    "desc": "담배 회복량 +10 (20→30)",       "branch": 2, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "tough_body",   "name": "강화 차체",    "desc": "기본 차체 내구도 +25%",         "branch": 2, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "smoker_2",     "name": "헤비 스모커",  "desc": "담배 회복량 추가 +10 (30→40)",  "branch": 2, "tier": 2, "cost": 35, "prereq": "smoker_1"},
	{"id": "unyielding",   "name": "불굴",        "desc": "정신력 0에서 화면 왜곡 -30%",   "branch": 2, "tier": 3, "cost": 60, "prereq": ""},

	# D. 적응
	{"id": "keen_eye",     "name": "예민한 눈",    "desc": "적 감지 거리 +20%",             "branch": 3, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "fast_react",   "name": "빠른 반응",    "desc": "점퍼 탈출 게이지 -20%",         "branch": 3, "tier": 1, "cost": 20, "prereq": ""},
	{"id": "radio_sense",  "name": "라디오 감각",  "desc": "라디오 안전 구간 폭 +1스텝",    "branch": 3, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "reality",      "name": "현실 감각",    "desc": "환각 기준 정신력 40→30",        "branch": 3, "tier": 2, "cost": 35, "prereq": ""},
	{"id": "survival",     "name": "생존 본능",    "desc": "괴물 임박 시 최고속도 +15 km/h (10초)", "branch": 3, "tier": 3, "cost": 60, "prereq": ""},
]

const BRANCH_NAMES := ["드라이빙", "자원", "생존", "적응"]
const BRANCH_COLORS := [
	Color(0.3, 0.7, 1.0),   # 파랑
	Color(0.4, 0.9, 0.3),   # 초록
	Color(1.0, 0.5, 0.3),   # 주황
	Color(0.8, 0.4, 0.9),   # 보라
]

# ── 런타임 상태 ──
var total_points   : int = 0           # 누적 보유 포인트 (퍽용)
var unlocked_perks : Dictionary = {}   # id -> true

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
	# 특수 선행 조건 (헤비 스모커 → 담배 중독)
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
	save_data()
	return true

func has_perk(perk_id: String) -> bool:
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

func _find_perk(perk_id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == perk_id:
			return p
	return {}

func get_unlocked_count() -> int:
	return unlocked_perks.size()
