extends RefCounted
class_name RadioScripts

# ══════════════════════════════════════════════════════════════
#  라디오 방송 텍스트 (Doc 27) — 음성 에셋이 없으므로 LCD 아래 자막 티커로 노출.
#  일반 주파수: DJ 멘트·뉴스(도망자 충돌 횟수 반영)·시보·사연·날씨·음악 소개·광고 순환
#  죽음의 주파수: 난수방송. 런 횟수(초기 1~3 / 중기 4~6)와 진엔딩 퍽 여부로 단계
# ══════════════════════════════════════════════════════════════

const DJ := [
	"안녕하십니까, 청취자 여러분. 지금 이 시각은 새벽 세 시 십 분을 가리키고 있습니다. 저는 오늘 새벽도 여러분 곁에 함께하겠습니다.",
	"이 늦은 시간, 라디오 앞에 계신 청취자 여러분. 어떤 사연을 안고 계십니까. 먼 길을 달리고 계신 분도 계시겠지요.",
	"오늘 새벽은 안개가 다소 끼겠다고 합니다. 운전 중이신 청취자 여러분, 전조등 꼭 켜시고 안전 운전 부탁드리겠습니다.",
	"잠시 후 청취자 여러분의 사연을 읽어드리겠습니다. 오늘 밤도 사연 보내주신 분들, 감사합니다.",
	"지금 이 시각, 어디선가 이 노래를 듣고 계실 청취자 여러분께 이 곡을 보내드리겠습니다.",
	"새벽녘이 되면 공기가 달라지지요. 조금만 있으면 동이 틉니다. 조금만 더 힘내시기 바랍니다, 청취자 여러분.",
]
const NEWS_COUNT_WORDS := ["세", "네", "다섯", "여섯", "일곱", "여덟", "아홉", "열"]
const NEWS_TEMPLATE := "경찰 당국에 따르면 27번 국도 일대에서 이번 달 들어 실종 신고 %s 건이 접수된 것으로 확인됐습니다. 실종자들은 모두 야간 이동 중 가족과의 연락이 두절된 것으로 알려졌습니다."
const TIME_SIGNAL := [
	"삐— 지금 이 시각은 새벽 세 시 정각입니다.",
	"삐— 지금 이 시각은 새벽 네 시 정각입니다.",
]
const LETTERS := [
	"자, 이번에는 청취자 여러분의 사연을 읽어드리겠습니다. 경기도에서 연락 주셨습니다. '남자친구가 어젯밤 27번 국도를 지나간다고 하고서 연락이 닿지 않습니다.' …별일 없기를 바랍니다. 이분께 노래 한 곡 보내드리겠습니다.",
	"장거리 운전 중이신 청취자 분께서 사연 보내주셨습니다. '혼자 밤새 달리고 있습니다. 라디오가 없었으면 어쩔 뻔했습니다.' 무사히 도착하시길 바랍니다.",
]
const LETTER_LATE := "…27번 국도를 이용하시는 청취자 여러분께 당부 말씀 드리겠습니다. 한 청취자 분의 가족 분이 해당 구간에서 연락이 끊어졌다고 하십니다. 관련 정보를 알고 계신 분은 경찰에 신고해 주시기 바랍니다."
const WEATHER := [
	"기상청에 따르면 오늘 새벽 27번 국도를 포함한 내륙 지방에는 짙은 안개가 끼겠으며, 가시거리가 50미터 이하로 떨어지는 곳도 있겠습니다. 감속 운행하시기 바랍니다.",
	"오늘 새벽 최저 기온은 영하 2도까지 내려가겠으며, 일부 도로 결빙이 예상됩니다. 각별히 주의하시기 바랍니다.",
	"27번 국도 ○○분기점 부근에서 사고 처리가 진행 중에 있습니다. 해당 구간 우회를 권고 드립니다.",
]
const MUSIC := [
	"지금부터 들으실 곡은…",
	"다음 곡은 청취자 여러분께서 많이 신청해 주신 곡입니다.",
	"잠시 후 이어지는 노래, 감상하시기 바랍니다.",
	"…자, 다음 곡 이어서 들으시겠습니다.",
]
const ADS := [
	"깊은 밤, 홀로 운전하시는 분들을 위한 ○○보험. 언제 어디서나 든든하게 함께하겠습니다.",
	"새벽 배달, ○○우유. 신선함이 다릅니다.",
	"피로가 쌓이셨습니까. ○○한방에서 여러분의 건강을 책임지겠습니다.",
	"자, 광고 말씀 들으셨습니다. 계속해서…",
]

# 죽음의 주파수 — 난수방송
const DEATH_EARLY := [
	"(낮은 목소리들이 겹쳐 웅얼거림)",
	"…스물셋. 스물넷. 스물다섯. 스물여섯…",
	"(정적)",
	"…스물일곱.",
	"(정적. 다시 웅얼거림)",
]
const DEATH_MID := [
	"(찬송가 멜로디. 가사는 들리지 않음)",
	"…권○○. 정○○. 최○○. 박○○…",
	"(정적)",
	"…돌아오너라.",
	"(찬송가 재개)",
]
const DEATH_LATE := [
	"(이름 목록 낭독 중)",
	"…이○○. 김○○…",
	"(정적)",
	"…돌아오너라.",
	"…이○○. [익숙한 음절]. 김○○…",
]

# 일반 주파수 프로그램 순서 (한 바퀴 ≈ 2~3분 분량)
const PROGRAM := ["dj", "music", "news", "dj", "letter", "music", "ad", "weather", "time", "dj", "ad", "music"]

var _prog_idx: int = 0
var _death_idx: int = 0
var _rng := RandomNumberGenerator.new()
var _dj_i := 0
var _music_i := 0
var _ad_i := 0
var _weather_i := 0
var _letter_i := 0
var _time_i := 0

func _init() -> void:
	_rng.randomize()
	_prog_idx = _rng.randi() % PROGRAM.size()

## 일반 주파수 다음 줄
func next_normal(fleeing_hits: int, late_stage: bool) -> String:
	var seg: String = PROGRAM[_prog_idx]
	_prog_idx = (_prog_idx + 1) % PROGRAM.size()
	match seg:
		"dj":
			_dj_i = (_dj_i + 1) % DJ.size(); return DJ[_dj_i]
		"music":
			_music_i = (_music_i + 1) % MUSIC.size(); return MUSIC[_music_i]
		"ad":
			_ad_i = (_ad_i + 1) % ADS.size(); return ADS[_ad_i]
		"weather":
			_weather_i = (_weather_i + 1) % WEATHER.size(); return WEATHER[_weather_i]
		"time":
			_time_i = (_time_i + 1) % TIME_SIGNAL.size(); return TIME_SIGNAL[_time_i]
		"letter":
			if late_stage and _rng.randf() < 0.3:
				return LETTER_LATE
			_letter_i = (_letter_i + 1) % LETTERS.size(); return LETTERS[_letter_i]
		"news":
			# 도망자 충돌 횟수만큼 실종 건수가 늘어난다. 톤은 매번 같다
			var idx := clampi(fleeing_hits, 0, NEWS_COUNT_WORDS.size() - 1)
			return NEWS_TEMPLATE % NEWS_COUNT_WORDS[idx]
	return ""

## 죽음의 주파수 다음 줄. total_runs 1~3 초기 / 4~6 중기 / 진엔딩 퍽 후기
func next_death(total_runs: int, late_stage: bool) -> String:
	var pool: Array = DEATH_EARLY
	if late_stage:
		pool = DEATH_LATE
	elif total_runs >= 4:
		pool = DEATH_MID
	var line: String = pool[_death_idx % pool.size()]
	_death_idx += 1
	return line
