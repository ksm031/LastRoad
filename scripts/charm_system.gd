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
	# 🚗 1. 스피드 빌드 (6종)
	"nodding_dog": {
		"name": "흔들리는 강아지 인형",
		"desc": "최고속도의 80% 이상 유지 시 정신력 +1/초 회복. SPEED 태그 부적 1개당 회복량 +0.3/초",
		"tags": ["SPEED"]
	},
	"rusty_compass": {
		"name": "낡은 나침반",
		"desc": "주행속도 50km/h 이상 시 차선 변경 안정성 +50% (커브에서 차체 흔들림 감소)",
		"tags": ["SPEED"]
	},
	"broken_speedometer": {
		"name": "부서진 속도계",
		"desc": "최고속도 제한 +15%. 가속 페달 누르는 동안 라디오 주파수 조작 불가. SPEED 태그 3개 이상 시 패널티 무효",
		"tags": ["SPEED", "RISK"]
	},
	"worn_brake_pad": {
		"name": "마모된 브레이크 패드",
		"desc": "가속만 10초 이상 연속 유지 시 가속도 +30%. 브레이크 시 게이지 초기화",
		"tags": ["SPEED"]
	},
	"adrenaline_syringe": {
		"name": "아드레날린 주사기",
		"desc": "와쳐 등 괴물(적) 충돌 시 속도 감소 무효 + 3초간 가속도 +20%",
		"tags": ["SPEED", "DURABILITY"]
	},
	"burnt_clutch": {
		"name": "타버린 클러치",
		"desc": "남은 연료 30% 미만 시 최고속도 +20%",
		"tags": ["SPEED", "RISK"]
	},
	
	# 🔦 2. 파밍 빌드 (6종)
	"bloody_coin": {
		"name": "피 묻은 동전",
		"desc": "갓길 폐차 수색 속도 2배. 정차 중 괴물 접근 속도 +50%. SCAVENGE 3개 이상 시 패널티 -25%",
		"tags": ["SCAVENGE", "RISK"]
	},
	"magnetic_cat": {
		"name": "자석 고양이",
		"desc": "폐차 수색 시 빈 칸 탐색마다 15% 확률로 기름 1L 발견. LUCK 2개 이상 시 25%로 상승",
		"tags": ["SCAVENGE", "LUCK"]
	},
	"rusty_padlock": {
		"name": "녹슨 자물쇠",
		"desc": "트렁크 -2칸. 폐차 수색 시 '차량 부품류' 잡품 최소 1개 확정 등장",
		"tags": ["SCAVENGE"]
	},
	"golden_cog": {
		"name": "황금 톱니바퀴",
		"desc": "5개 부품 모두 100% 유지 시 잡품 판매가 +50%",
		"tags": ["SCAVENGE", "DURABILITY"]
	},
	"discarded_receipt": {
		"name": "수상한 영수증 묶음",
		"desc": "정비소 파츠 업그레이드 비용 -15%. 다른 SCAVENGE 부적 1개당 추가 -3%",
		"tags": ["SCAVENGE"]
	},
	"carnival_ticket": {
		"name": "카니발 입장권",
		"desc": "폐차 수색 완료 시 50% 확률로 다음 폐차 등장 거리 -30%",
		"tags": ["SCAVENGE", "LUCK"]
	},

	# 📻 3. 정신력 빌드 (6종)
	"freakish_antenna": {
		"name": "기괴한 안테나",
		"desc": "라디오가 죽음의 주파수에 점유된 상태에서 끄지 않으면 괴물과 거리 점진 증가 (정신력은 정상 감소)",
		"tags": ["SANITY", "RISK"]
	},
	"distorted_mirror": {
		"name": "일그러진 룸미러",
		"desc": "차에 달라붙은 점퍼를 떼어내는 데 성공할 때마다 정신력 +25",
		"tags": ["SANITY"]
	},
	"blind_owl": {
		"name": "눈먼 부엉이 조각",
		"desc": "헤드라이트를 완전히 끄고 주행 중인 동안 정신력 감소량 0",
		"tags": ["SANITY", "RISK"]
	},
	"half_smoked_cig": {
		"name": "피우다 만 담배꽁초",
		"desc": "담배 사용 시 즉시 회복 -10. 대신 60초에 걸쳐 총 +40 회복",
		"tags": ["SANITY"]
	},
	"torn_photo": {
		"name": "찢어진 사진",
		"desc": "정신력 20 이하 시 연료 소모율 -30%",
		"tags": ["SANITY", "RISK"]
	},
	"cracked_hand_mirror": {
		"name": "금이 간 손거울",
		"desc": "환각 위협 충돌 시 (소멸 시) 정신력 +5. SANITY 3개 이상 시 +10",
		"tags": ["SANITY"]
	},

	# 🛡️ 4. 생존 빌드 (7종)
	"safe_drive_amulet": {
		"name": "안전운전 부적",
		"desc": "5개 부품 모두 100% 유지 시 모든 적(괴물 포함) 접근 빈도·속도 -20%",
		"tags": ["DURABILITY"]
	},
	"old_wiper_motor": {
		"name": "낡은 와이퍼 모터",
		"desc": "와이퍼 작동 중 전방 장애물(포트홀·낙석)이 야광으로 강조 표시",
		"tags": ["DURABILITY"]
	},
	"heavy_weight": {
		"name": "무거운 추",
		"desc": "브레이크 제동력 +50%, 충돌 피해 -20%, 최고속도 -10%. SPEED 태그 부적과 동시 장착 시 안티시너지",
		"tags": ["DURABILITY"]
	},
	"punctured_tin": {
		"name": "구멍 난 양철통",
		"desc": "가속 페달에서 발을 떼고 타력 주행 시 연료 게이지 미세 회복",
		"tags": ["DURABILITY", "SCAVENGE"]
	},
	"thick_patch": {
		"name": "두꺼운 타이어 패치",
		"desc": "타이어 1개 펑크 시 주행 페널티 -50% (쏠림·속도 감소 모두 절반)",
		"tags": ["DURABILITY"]
	},
	"crash_test_dummy": {
		"name": "단단한 더미 인형",
		"desc": "스테이지당 1회, 장애물 충돌로 인한 내구도 감소를 무효화. DURABILITY 3개 이상 시 스테이지당 2회로 증가",
		"tags": ["DURABILITY"]
	},
	"weathered_pebble": {
		"name": "풍화된 조약돌",
		"desc": "포트홀·낙석 충돌 시 타이어 내구도 손상이 50% 감소하고, 5초간 괴물 접근 속도가 30% 느려진다.",
		"tags": ["DURABILITY"]
	},

	# 🌀 5. 위험 빌드 (7종)
	"bound_wristwatch": {
		"name": "묶인 손목시계",
		"desc": "한 스테이지 내 누적 정차 시간이 길수록 다음 스테이지 시작 시 정신력 회복 (최대 +50)",
		"tags": ["RISK", "SCAVENGE"]
	},
	"empty_medicine_bottle": {
		"name": "빈 약통",
		"desc": "정신력 10 이하 시 모든 환각이 보이지 않게 됨. 단, 환각 위협 충돌 시 부품 손상이 정상 발생",
		"tags": ["RISK", "SANITY"]
	},
	"rusty_razor": {
		"name": "녹슨 면도날",
		"desc": "부품 내구도 감소가 발생할 때마다 25% 확률로 ₩500 즉시 획득",
		"tags": ["RISK", "SCAVENGE"]
	},
	"upside_down_talisman": {
		"name": "거꾸로 달린 부적",
		"desc": "다른 모든 부적의 페널티 -50%. 단, 보너스도 -25%",
		"tags": ["RISK", "LUCK"]
	},
	"metal_cross": {
		"name": "금속 십자가",
		"desc": "괴물에게 잡히기 직전 1회에 한해 정신력 풀회복 + 가속 부스트 5초간 강제 발동",
		"tags": ["RISK", "DEATH"]
	},
	"counterclockwise_doll": {
		"name": "시계 반대방향 인형",
		"desc": "사망 시 직전 스테이지 시작 지점으로 1회 부활. 단, 장착 중인 부적 1개 무작위 영구 소멸",
		"tags": ["RISK", "LUCK", "DEATH"]
	},
	"headwind_amulet": {
		"name": "역풍의 부적",
		"desc": "괴물의 창에 명중당하는 순간 즉시 400km/h로 가속(1초) → 이후 6초간 엔진 동력 무효",
		"tags": ["SPEED", "RISK"]
	},

	# 🗝️ 6. 히든 티어 (5종)
	"dead_man_watch": {
		"name": "죽은 자의 손목시계",
		"desc": "한 런에 1회, 게임오버 발생 5초 전의 상태로 시간이 되돌아간다. 단 BO는 발동 시점의 -50%로 영구 감소",
		"tags": ["RISK", "DEATH", "LUCK"]
	},
	"sixth_eye": {
		"name": "여섯 번째 눈",
		"desc": "정신력 40 이하에서 환각 위협이 미세한 푸른 빛으로 표시되어 실제와 구분 가능. 대신 모든 BO 획득량 -30%",
		"tags": ["SANITY", "RISK"]
	},
	"black_fang": {
		"name": "검은 송곳니",
		"desc": "사슴머리를 80km/h 이상으로 통과할 때마다 BO +50 보너스. 단, 통과 시 정신력 추가 -10",
		"tags": ["SPEED", "DEATH"]
	},
	"last_prayer": {
		"name": "마지막 기도",
		"desc": "부품 하나가 0% 도달 혹은 정신력 0 도달 직전, 부품 30%, 정신력 50, 연료 50% 회복 후 자동 소멸",
		"tags": ["DEATH", "SANITY"]
	},
	"backward_radio": {
		"name": "거꾸로 흐르는 라디오",
		"desc": "죽음의 주파수 청취 중 다음 위협(앰부서·사슴머리·괴물의 창)이 발생 5초 전 라디오에서 미리 노출. 단 정신력 회복량 -50%",
		"tags": ["SANITY", "LUCK"]
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

# ── 부적 시너지 판단 헬퍼 ──
func count_tag(tag: String) -> int:
	var count := 0
	for cid in active_charms:
		var data = get_charm_data(cid)
		var tags: Array = data.get("tags", [])
		if tags.has(tag):
			count += 1
	return count

func check_duo(a: String, b: String) -> bool:
	return active_charms.has(a) and active_charms.has(b)

func check_anti(a: String, b: String) -> bool:
	return active_charms.has(a) and active_charms.has(b)

