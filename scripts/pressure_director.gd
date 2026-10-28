extends RefCounted
class_name PressureDirector

# ══════════════════════════════════════════════════════════════
#  동시 압박 조율 (Doc 30) — 경량 구현
#
#  1) 숨 비트: 스테이지마다 '거리 구역' [wz0, wz1]을 결정적으로 배치.
#     구역 안에서는 적(와쳐·점퍼·러너·워커)이 스폰되지 않고, 창·라디오 전환이 보류된다.
#     시간이 아닌 거리로 정의해야 시드 기반 스폰이 결정적으로 유지된다.
#  2) 스파이크 잠금: 시각+인지 채널 스파이크(창 시퀀스, 러너 돌진)가 같은 순간 겹치지 않게
#     register_spike() / spike_active() 로 서로 양보한다.
#  3) 적응형 압박: 펑크·구동계 고장·정비 직전 등 플레이어 상태에 따른 창 빈도 배수.
#
#  모두 static — 씬 어디서든 PressureDirector.xxx 로 접근.
# ══════════════════════════════════════════════════════════════

# ── 숨 비트 (Doc 30 §5): [간격 초, 윈도우 초] 스테이지 1~6 ──
const BREATH_TABLE := [
	[60.0, 15.0],
	[75.0, 12.0],
	[90.0, 10.0],
	[100.0, 8.0],
	[120.0, 7.0],
	[150.0, 5.0],
]
const UNITS_PER_SEC := 6.75   # 90km/h 기준 세계 단위/초 (vehicle SCROLL_RATE 0.075)
const END_HOLD_UNITS := 60.0  # 정비 구간 직전 — 신규 스파이크 보류 구간 (Doc 30 §6)

static var breath_zones: Array = []     # [[wz0, wz1], ...]
static var stage_len: float = 600.0
static var _spike_until: float = 0.0    # 현재 활성 스파이크 종료 시각 (Time.get_ticks_msec 기준 초)

## 스테이지 진입 시 호출. seed_offset으로 구역 위치를 흔든다 (±10%)
static func setup_stage(stage: int, p_stage_len: float, seed_offset: int) -> void:
	stage_len = p_stage_len
	breath_zones.clear()
	_spike_until = 0.0
	var row: Array = BREATH_TABLE[clampi(stage - 1, 0, BREATH_TABLE.size() - 1)]
	var interval_u := float(row[0]) * UNITS_PER_SEC
	var window_u   := float(row[1]) * UNITS_PER_SEC
	# 스테이지 길이 안에 들어가는 숨 비트 개수 (최소 1, 도입부·종료부 제외)
	var count := maxi(int(floor((p_stage_len - 120.0) / interval_u)), 1)
	for i in range(count):
		var base := 120.0 + interval_u * float(i + 1) - window_u
		if base + window_u > p_stage_len - END_HOLD_UNITS:
			base = p_stage_len - END_HOLD_UNITS - window_u
		var jitter := (BillboardManager.get_rand01(9001 + i * 77, seed_offset) - 0.5) * interval_u * 0.2
		var z0 := clampf(base + jitter, 80.0, p_stage_len - window_u - 10.0)
		breath_zones.append([z0, z0 + window_u])

## 이 거리에 적을 놓아도 되는가 (숨 비트 구역 밖인가)
static func can_spawn_at(wz: float) -> bool:
	for z in breath_zones:
		if wz >= float(z[0]) and wz <= float(z[1]):
			return false
	return true

## 플레이어가 지금 숨 비트 안에 있는가
static func in_breath(scroll_z: float) -> bool:
	return not can_spawn_at(scroll_z)

## 정비 구간 직전(도착 보장 구간)인가
static func near_stage_end(scroll_z: float) -> bool:
	return scroll_z >= stage_len - END_HOLD_UNITS

## 시각+인지 스파이크 등록 (초). 같은 채널의 다른 스파이크는 끝날 때까지 양보
static func register_spike(duration: float) -> void:
	var until := _now() + duration
	if until > _spike_until:
		_spike_until = until

static func spike_active() -> bool:
	return _now() < _spike_until

static func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001

## 적응형 압박 (Doc 30 §6) — 창 빈도 배수
static func spear_rate_mult(vehicle: LastRoadVehicle) -> float:
	var m := 1.0
	var flats := 0
	if vehicle.dur_lf_tire <= 0.0: flats += 1
	if vehicle.dur_rf_tire <= 0.0: flats += 1
	if vehicle.dur_lb_tire <= 0.0: flats += 1
	if vehicle.dur_rb_tire <= 0.0: flats += 1
	if flats >= 2:
		m *= 0.7
	if vehicle.dur_drivetrain <= 0.0:
		m *= 0.5
	return m
