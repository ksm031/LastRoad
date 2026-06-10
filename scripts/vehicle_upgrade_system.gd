extends Node
class_name VehicleUpgradeSystem

# ── 차량 파츠 업그레이드 상태 ──
var upgrades : Dictionary = {
	"engine": 0,
	"fuel_tank": 0,
	"turbine": 0,
	"tires": 0,
	"brakes": 0,
	"headlight": 0,
	"bumper": 0      # Doc 31 §6: 전투 전담 무기 파츠
}

# 업그레이드 비용 (레벨 0->1, 1->2 ...)
const UPGRADE_COSTS := [5000, 12000, 25000, 48000, 90000]
const MAX_UPGRADE_LV := 5

# ── 파츠 상세 데이터 (몰입감용 명칭) ──
const PART_DATA := {
	"engine": {
		"name": "엔진",
		"levels": [
			{"n": "순정 엔진", "d": "기본적인 4기통 엔진."},
			{"n": "튜닝된 흡기", "d": "공기 흡입 효율을 높여 가속력이 소폭 상승합니다."},
			{"n": "고성능 캠샤프트", "d": "엔진 회전 한계를 높여 최고속도가 증가합니다."},
			{"n": "강화된 피스톤", "d": "내구성과 출력을 동시에 확보합니다."},
			{"n": "트윈 스크롤 터보", "d": "압도적인 가속력을 제공하는 터보차저를 장착합니다."},
			{"n": "실험용 V8 블록", "d": "종말의 도로 위에서 가장 강력한 심장입니다."}
		]
	},
	"fuel_tank": {
		"name": "연료탱크",
		"levels": [
			{"n": "기본 탱크", "d": "40L 용량의 표준 탱크."},
			{"n": "보조 격벽", "d": "출렁임을 방지하고 공간 효율을 개선합니다."},
			{"n": "대용량 합금 탱크", "d": "가벼우면서도 더 많은 연료를 담습니다."},
			{"n": "확장형 리저버", "d": "장거리 주행을 위한 추가 저장 공간을 확보합니다."},
			{"n": "안전 셀 탱크", "d": "피격 시 누유를 방지하고 용량을 극대화합니다."},
			{"n": "대형 커스텀 드럼", "d": "사실상 트렁크 절반을 연료로 채웁니다."}
		]
	},
	"turbine": {
		"name": "연료 관리 (연비)",
		"levels": [
			{"n": "표준 ECU", "d": "기본적인 연료 분사 제어."},
			{"n": "오일 필터 개선", "d": "엔진 오일 순환을 돕고 마찰을 줄여 연비를 개선합니다."},
			{"n": "연료 분사 맵핑", "d": "ECU를 재설정하여 연료 낭비를 최소화합니다."},
			{"n": "경량 크랭크축", "d": "엔진의 회전 관성을 줄여 에너지 효율을 높입니다."},
			{"n": "에어로 다이나믹 킷", "d": "공기 저항을 줄여 고속 주행 시 연비를 대폭 향상합니다."},
			{"n": "나노 코팅 실린더", "d": "마찰 계수를 극한으로 낮춘 최첨단 엔진 공정입니다."}
		]
	},
	"tires": {
		"name": "타이어 & 조향",
		"levels": [
			{"n": "낡은 타이어", "d": "마모가 심한 중고 타이어."},
			{"n": "사계절 타이어", "d": "새 제품으로 교체하여 접지력을 회복합니다."},
			{"n": "강화 서스펜션", "d": "차체 흔들림을 잡아주어 조향이 더 정교해집니다."},
			{"n": "고성능 스포츠 타이어", "d": "급격한 차선 변경에도 안정감을 유지합니다."},
			{"n": "레이싱 슬릭", "d": "아스팔트 위에 달라붙는 듯한 기동성을 보여줍니다."},
			{"n": "전천후 오프로드 셋", "d": "어떤 도로 상태에서도 완벽한 핸들링을 보장합니다."}
		]
	},
	"brakes": {
		"name": "브레이크",
		"levels": [
			{"n": "표준 드럼식", "d": "평범한 제동 성능."},
			{"n": "메탈 패드 교체", "d": "마찰력이 높은 패드로 교체하여 제동 거리를 줄입니다."},
			{"n": "환기형 디스크", "d": "열 방출 효율을 높여 연속 제동 시에도 성능을 유지합니다."},
			{"n": "4피스톤 캘리퍼", "d": "더 강력한 압력으로 바퀴를 멈춰 세웁니다."},
			{"n": "세라믹 브레이크", "d": "고속에서도 즉각적인 정지가 가능해집니다."},
			{"n": "ABS 마스터 실린더", "d": "어떤 속도에서도 바퀴가 잠기지 않고 확실히 제동합니다."}
		]
	},
	"headlight": {
		"name": "헤드라이트",
		"levels": [
			{"n": "낡은 전구", "d": "희미한 황색 불빛. 바로 앞만 겨우 보입니다."},
			{"n": "반사판 청소", "d": "내부 반사판을 닦아 빛의 직진성을 높입니다."},
			{"n": "할로겐 램프", "d": "표준 할로겐 전구로 교체하여 광량이 눈에 띄게 늘어납니다."},
			{"n": "고전압 HID", "d": "강력한 화이트 광원으로 먼 곳의 적을 더 빨리 감지합니다."},
			{"n": "멀티 프로젝션", "d": "빛을 집약시켜 조사 거리를 대폭 연장합니다."},
			{"n": "초고출력 LED 서치라이트", "d": "지평선 끝까지 비추는 최강의 서치라이트입니다."}
		]
	},
	# Doc 31 §6: 범퍼 — 전투 전담 파츠 (차의 공격력 강화)
	"bumper": {
		"name": "범퍼 (전투)",
		"levels": [
			{"n": "순정 범퍼", "d": "아무 보강도 없는 기본 범퍼."},
			{"n": "강화 고무 범퍼", "d": "킬 임계 속도가 5km/h 낮아져 더 느린 속도로도 적을 처치합니다."},
			{"n": "철제 보강재", "d": "관통 처치 시 차체 내구도 소모가 25% 감소합니다."},
			{"n": "쐐기형 충각", "d": "관통 수가 1 늘어 한 번에 최대 2명까지 동시 처치합니다."},
			{"n": "중장갑 그릴", "d": "임계 미만 충돌(튕김) 시 내구도 손실이 40% 감소합니다."},
			{"n": "전차 돌기", "d": "킬 임계 속도가 추가로 10km/h 낮아지고(총 -15) 처치 후 속도를 전혀 잃지 않습니다."}
		]
	}
}

func can_upgrade_part(part_id: String, current_money: int, has_discount: bool = false) -> bool:
	var lv = upgrades.get(part_id, 0)
	if lv >= MAX_UPGRADE_LV: return false
	var cost = UPGRADE_COSTS[lv]
	if has_discount:
		cost = int(float(cost) * 0.85)
	return current_money >= cost

func upgrade_part(part_id: String, current_money: int, has_discount: bool = false) -> Dictionary:
	# 성공 시 { "success": true, "cost": int, "new_lv": int } 반환
	if not can_upgrade_part(part_id, current_money, has_discount):
		return {"success": false}
	
	var lv = upgrades[part_id]
	var cost = UPGRADE_COSTS[lv]
	if has_discount:
		cost = int(float(cost) * 0.85)
	upgrades[part_id] = lv + 1
	return {"success": true, "cost": cost, "new_lv": upgrades[part_id]}


func reset_upgrades() -> void:
	for key in upgrades.keys():
		upgrades[key] = 0
