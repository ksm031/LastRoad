extends Node
class_name CharmSystem

signal charm_added(charm_id: String)
signal charm_removed(charm_id: String)
signal charm_full(new_charm_id: String) # 6개 꽉 찼을 때 UI 팝업용
signal charms_updated()

const MAX_CHARMS = 6

# ── 부적 도감 (24종) ──
# type: speed, economy, horror, survival
const CHARM_DB := {
	"nodding_dog": {
		"name": "흔들리는 강아지 인형",
		"desc": "속도가 최고속도의 90% 이상일 때, 정신력이 초당 1씩 서서히 회복된다.",
		"type": "speed"
	},
	"rusty_compass": {
		"name": "낡은 나침반",
		"desc": "고속 주행 중 조향 시 차체 흔들림이 50% 감소한다.",
		"type": "speed"
	},
	"broken_speedometer": {
		"name": "부서진 속도계",
		"desc": "최고 속도 한계가 15% 상승하지만, 가속 페달을 밟는 동안 라디오 조작이 불가능하다.",
		"type": "speed"
	},
	"worn_brake_pad": {
		"name": "마모된 브레이크 패드",
		"desc": "가속 페달을 10초 이상 밟고 있으면 가속도가 30% 증가한다. (브레이크 사용 시 초기화)",
		"type": "speed"
	},
	"adrenaline_syringe": {
		"name": "아드레날린 주사기",
		"desc": "와쳐 등 괴물(적) 충돌 시 속도 감소 무효 + 3초간 가속도 +20%",
		"type": "speed"
	},
	"burnt_clutch": {
		"name": "타버린 클러치",
		"desc": "남은 연료가 30% 미만일 때, 최고 속도가 20% 증가한다.",
		"type": "speed"
	},
	
	"bloody_coin": {
		"name": "피 묻은 동전",
		"desc": "폐차 수색 속도가 2배 빨라지지만, 정차 중 괴물 접근 속도가 1.5배가 된다.",
		"type": "economy"
	},
	"magnetic_cat": {
		"name": "자석 고양이",
		"desc": "폐차 수색 시 '빈 칸'을 탐색할 때마다 15% 확률로 기름 1L를 획득한다.",
		"type": "economy"
	},
	"rusty_padlock": {
		"name": "녹슨 자물쇠",
		"desc": "트렁크 용량이 2칸 줄어드는 대신, 폐차 수색 시 '차량 부품'이 확정 1개 등장한다.",
		"type": "economy"
	},
	"golden_cog": {
		"name": "황금 톱니바퀴",
		"desc": "차체 내구도가 100%일 때, 상점에 잡품 판매 시 1.5배의 가격을 받는다.",
		"type": "economy"
	},
	"gamblers_dice": {
		"name": "도박사의 주사위",
		"desc": "파밍 아이템 발견 시 50% 확률로 2개를 얻지만, 50% 확률로 아이템 대신 정신력을 10 잃는다.",
		"type": "economy"
	},
	"discarded_receipt": {
		"name": "버려진 영수증",
		"desc": "파츠 업그레이드 비용이 15% 할인된다. (상점 소모품 진열은 1칸 감소)",
		"type": "economy"
	},

	"freakish_antenna": {
		"name": "기괴한 안테나",
		"desc": "라디오가 노이즈 상태일 때, 괴물과의 거리가 서서히 멀어진다.",
		"type": "horror"
	},
	"distorted_mirror": {
		"name": "일그러진 룸미러",
		"desc": "점퍼(Jumper)를 떼어내는 데 성공하면 정신력을 25 회복한다.",
		"type": "horror"
	},
	"blind_owl": {
		"name": "눈먼 부엉이 조각",
		"desc": "헤드라이트를 완전히 끄고 주행하면 정신력이 자연 소모되지 않는다.",
		"type": "horror"
	},
	"half_smoked_cig": {
		"name": "피우다 만 담배꽁초",
		"desc": "담배 사용 시 즉시 회복량이 10으로 줄어들지만, 60초에 걸쳐 총 40을 추가 회복한다.",
		"type": "horror"
	},
	"torn_photo": {
		"name": "찢어진 사진",
		"desc": "정신력이 20 이하일 때, 연료 소모율이 30% 감소한다.",
		"type": "horror"
	},
	"tangled_tape": {
		"name": "감겨있는 카세트테이프",
		"desc": "와쳐(Watcher)의 시선 게이지 상승 속도가 30% 감소한다.",
		"type": "horror"
	},

	"safe_drive_amulet": {
		"name": "안전운전 부적",
		"desc": "차체 내구도가 100%일 때, 모든 적의 접근 빈도 및 속도가 20% 감소한다.",
		"type": "survival"
	},
	"old_wiper_motor": {
		"name": "낡은 와이퍼 모터",
		"desc": "와이퍼 작동 중, 전방의 장애물이 희미하게 야광으로 빛나 강조된다.",
		"type": "survival"
	},
	"heavy_weight": {
		"name": "무거운 추",
		"desc": "제동력이 50% 상승하고 충돌 피해를 20% 줄여주지만, 최고 속도가 10% 감소한다.",
		"type": "survival"
	},
	"punctured_tin": {
		"name": "구멍 난 양철통",
		"desc": "가속 페달에서 발을 떼고 타력 주행(Coasting) 시 연료가 미세하게 회복된다.",
		"type": "survival"
	},
	"thick_patch": {
		"name": "두꺼운 타이어 패치",
		"desc": "타이어 펑크 시 공기압 자연 감소 속도가 50% 줄어든다.",
		"type": "survival"
	},
	"crash_test_dummy": {
		"name": "단단한 더미 인형",
		"desc": "스테이지당 1회 한정, 장애물 충돌로 인한 차체 내구도 감소를 무효화한다.",
		"type": "survival"
	},
	"weathered_pebble": {
		"name": "풍화된 조약돌",
		"desc": "포트홀·낙석 충돌 시 타이어 내구도 손상이 50% 감소하고, 5초간 괴물 접근 속도가 30% 느려진다.",
		"type": "survival"
	}
}

# ── 활성화된 부적 목록 ──
var active_charms: Array[String] = []

# ── 시스템 내부 변수 (시너지 카운터/타이머용) ──
var _accel_time: float = 0.0
var _dummy_used_this_stage: bool = false
var _cig_heal_timer: float = 0.0
var _cig_heal_amount: float = 0.0

func reset_run() -> void:
	active_charms.clear()
	_accel_time = 0.0
	_dummy_used_this_stage = false
	_cig_heal_timer = 0.0
	_cig_heal_amount = 0.0
	charms_updated.emit()

func reset_stage() -> void:
	_dummy_used_this_stage = false

func has_charm(charm_id: String) -> bool:
	return active_charms.has(charm_id)

func add_charm(charm_id: String) -> bool:
	if not CHARM_DB.has(charm_id):
		return false
	
	if active_charms.has(charm_id):
		return false # 중복 장착 불가
		
	if active_charms.size() >= MAX_CHARMS:
		# 최대치를 초과하면 교체 UI를 띄우기 위해 신호를 보냄
		charm_full.emit(charm_id)
		return false
		
	active_charms.append(charm_id)
	charm_added.emit(charm_id)
	charms_updated.emit()
	return true

func remove_charm(charm_id: String) -> void:
	if active_charms.has(charm_id):
		active_charms.erase(charm_id)
		charm_removed.emit(charm_id)
		charms_updated.emit()

func replace_charm(old_charm_id: String, new_charm_id: String) -> bool:
	if not active_charms.has(old_charm_id):
		return false
	if not CHARM_DB.has(new_charm_id):
		return false
		
	remove_charm(old_charm_id)
	return add_charm(new_charm_id)

func get_active_charms() -> Array[String]:
	return active_charms.duplicate()

func get_charm_data(charm_id: String) -> Dictionary:
	return CHARM_DB.get(charm_id, {})
