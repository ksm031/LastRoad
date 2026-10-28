extends RefCounted
class_name MonologueSystem

# ══════════════════════════════════════════════════════════════
#  운전자 혼잣말 (Doc 26)
#  - 침묵이 기본값. 상황별 쿨다운 + 전역 쿨다운으로 말수를 억제한다.
#  - 정신력 구간: 70+ / 40~70 / 40 미만 / 10 미만. ""는 침묵.
#    (10% 이하 강제 침묵은 hud.show_subtitle이 추가로 보장)
#  - 죄책감 랜덤 발화: 조용한 구간에서 런당 2~3회. 정신력이 낮을수록 깊은 층.
#
#  사용: var line := mono.pick("watcher", sanity); if line != "": hud.show_subtitle(line)
# ══════════════════════════════════════════════════════════════

# situation → [70+, 40~70, 40미만, 10미만]
const LINES := {
	"run_start":        ["...또 시작이네.", "...얼마나 더야.", "...또야.", ""],
	"watcher":          ["...저기 있네. 피하면 돼.", "...또 서있어.", "...뭘 보는 거야.", ""],
	"runner":           ["속도 올려. 지나가기 전에.", "오지 마. 그냥 오지 마.", "...피해야 해.", ""],
	"jumper_on":        ["핸들 흔들어. 떼어내면 돼.", "내려가. 내려가라고.", "", ""],
	"jumper_off":       ["됐어.", "", "", ""],
	"ambusher":         ["갑자기.", "아—", "", ""],
	"radio_death_on":   ["...주파수 바꿔야겠다.", "꺼. 꺼라.", "...들려.", ""],
	"radio_death_long": ["", "그만해.", "", ""],
	"fuel_40":          ["기름 떨어진다. 멈출 곳 찾아야 해.", "...조금만 더.", "...서도 되는 거야?", ""],
	"fuel_15":          ["서야 해. 지금 서야 해.", "제발.", "", ""],
	"monster_near":     ["빠르게. 더 빠르게.", "안 잡혀. 안 잡혀.", "...잡히면 안 돼.", "...제발."],
	"hallucination":    ["", "...없었네. 없는 거였어.", "...없는 거야. 맞아.", ""],
	"maintenance":      ["...잠깐 쉴 수 있겠네.", "여기서 멈추면 돼. 잠깐이야.", "...멈춰도 되는 건가.", ""],
	"passenger_buckle": ["", "...뭔가 걸렸나.", "...뭔가 걸렸나.", ""],
}

# 상황별 재발화 최소 간격(초). 없는 키는 DEFAULT_COOLDOWN
const COOLDOWNS := {
	"watcher": 40.0, "runner": 25.0, "monster_near": 30.0, "hallucination": 20.0,
	"fuel_40": 999.0, "fuel_15": 999.0, "radio_death_on": 45.0, "radio_death_long": 60.0,
	"passenger_buckle": 120.0,
}
const DEFAULT_COOLDOWN := 15.0
const GLOBAL_GAP := 6.0            # 어떤 말이든 이 간격 안에는 다시 말하지 않는다

# 죄책감 층 (Doc 26 §죄책감 혼잣말)
const GUILT_1 := ["...어쩔 수 없었어.", "...다 맞아.", "...달랐어야 했는데.", "...그럴 수밖에 없었어."]
const GUILT_2 := ["...미안.", "...알아.", "...그러면 안 됐는데.", "...내가—", "...다시 하면."]
const GUILT_3 := ["...살아있었잖아.", "...알면서.", "...말했어야 했는데.", "...왜 그랬어."]
const GUILT_4 := ["...소리가 났었어.", "...두드렸어."]
const GUILT_RUN_CAP := 3
const GUILT_QUIET_SEC := 25.0      # 이만큼 아무 일(말) 없던 뒤에만
const GUILT_INTERVAL_MIN := 80.0
const GUILT_INTERVAL_MAX := 150.0

var _time: float = 0.0
var _last_any: float = -100.0
var _last_by: Dictionary = {}
var _guilt_count: int = 0
var _guilt_tier4_used: bool = false
var _guilt_next: float = 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()
	reset_run()

func reset_run() -> void:
	_time = 0.0
	_last_any = -100.0
	_last_by.clear()
	_guilt_count = 0
	_guilt_tier4_used = false
	_guilt_next = _rng.randf_range(GUILT_INTERVAL_MIN, GUILT_INTERVAL_MAX)

func tick(delta: float) -> void:
	_time += delta

static func _band(sanity: float) -> int:
	if sanity >= 0.70: return 0
	if sanity >= 0.40: return 1
	if sanity >= 0.10: return 2
	return 3

## 상황에 맞는 대사. 쿨다운/침묵이면 "". force=true면 상황 쿨다운 무시(전역 간격은 유지)
func pick(situation: String, sanity: float, force: bool = false) -> String:
	if not LINES.has(situation):
		return ""
	if _time - _last_any < GLOBAL_GAP:
		return ""
	var cd := float(COOLDOWNS.get(situation, DEFAULT_COOLDOWN))
	if not force and _last_by.has(situation) and _time - float(_last_by[situation]) < cd:
		return ""
	var line: String = str(LINES[situation][_band(sanity)])
	# 쿨다운은 침묵이어도 소모 (같은 상황에서 계속 재시도하지 않게)
	_last_by[situation] = _time
	if line == "":
		return ""
	_last_any = _time
	return line

## 조용한 구간의 죄책감 발화. 매 프레임 호출, 말할 때만 문자열 반환
func tick_guilt(delta: float, sanity: float, quiet: bool) -> String:
	tick(delta)
	if _guilt_count >= GUILT_RUN_CAP:
		return ""
	if not quiet or _time - _last_any < GUILT_QUIET_SEC:
		return ""
	_guilt_next -= delta
	if _guilt_next > 0.0:
		return ""
	_guilt_next = _rng.randf_range(GUILT_INTERVAL_MIN, GUILT_INTERVAL_MAX)
	var pool: Array = GUILT_1
	if sanity <= 0.15 and not _guilt_tier4_used and _rng.randf() < 0.5:
		_guilt_tier4_used = true
		pool = GUILT_4
	elif sanity <= 0.30:
		pool = GUILT_3
	elif sanity <= 0.50:
		pool = GUILT_2
	elif _rng.randf() > 0.5:
		return ""   # 1층은 "아주 드물게"
	_guilt_count += 1
	_last_any = _time
	return str(pool[_rng.randi() % pool.size()])
