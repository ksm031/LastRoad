extends CanvasLayer
class_name CutscenePlayer

# ══════════════════════════════════════════════════════════════
#  런 클리어 컷신 (Doc 25) — 텍스트 전용 임시 구현.
#  원안은 픽셀아트 컷어웨이. 아트가 오기 전까지 어둠 위에 문장이 하나씩 떠오르고 사라진다.
#  play(pages): pages = [[text, seconds], ...]. 아무 키나 누르면 다음 페이지.
# ══════════════════════════════════════════════════════════════

signal finished

const FADE := 0.6

# Doc 25 컷신 1~9 (텍스트 각색). 10회 이후는 9번 반복. 진엔딩 퍽 해금 후 10회+는 미구현
const RUN_CUTSCENES := [
	[ # 1회 — 처음 본 순간
		["컬트 무리. 의식인지 집회인지 모를 장면.", 3.5],
		["카메라가 천천히 그녀에게 닿는다.\n나머지와 다른 무언가.", 4.0],
		["그녀는 고개를 든다.", 3.0],
		["[i]암전.[/i]", 2.0],
	],
	[ # 2회 — 그가 접근했을 때
		["낯선 공간. 그가 그녀에게 말을 건다.", 3.5],
		["그녀는 경계한다.\n그는 다음에 또 나타난다.", 4.0],
		["[i]그녀의 표정이 조금씩 바뀐다.[/i]", 3.0],
	],
	[ # 3회 — 그녀가 달라지는 것
		["책. 창문 밖. 혼자 앉아 있는 그녀.", 3.5],
		["전과 다른 자세, 전과 다른 눈빛.", 3.5],
		["[i]그가 문 너머에서 지켜본다. 흐뭇한 표정.[/i]", 3.5],
	],
	[ # 4회 — 첫 번째 다툼
		["그녀가 뭔가를 원한다. 말한다.", 3.0],
		["그가 부드럽게 방향을 돌린다.\n그녀가 잠깐 멈추다가 — 넘어간다.", 4.5],
		["[i]그는 옳다고 믿는다. 그녀는 그 표정을 본다.[/i]", 3.5],
	],
	[ # 5회 — 싸우고 싶다
		["그녀: \"나는 여기서 싸워야 해.\"", 3.5],
		["그: \"도망가는 게 맞아. 둘이 나가면 돼.\"", 3.5],
		["그녀: [i]말이 없다.[/i]", 3.0],
		["[i]창밖. 27번 국도 표지판.[/i]", 3.0],
	],
	[ # 6회 — 그가 그린 미래
		["밤. 그가 말한다. 도망간 후의 삶을.", 3.5],
		["다른 도시, 다른 이름, 조용한 곳.\n그의 목소리가 계속된다.", 4.0],
		["[i]그녀는 듣는다. 끝까지. 아무 말도 하지 않는다.[/i]", 4.0],
	],
	[ # 7회 — 그날 밤, 출발 전
		["차 안. 27번 국도. 시동이 걸린다.", 3.5],
		["그녀의 옆얼굴.", 2.5],
		["[i]그녀는 창밖을 본다. 그는 앞을 본다.[/i]", 4.0],
	],
	[ # 8회 — 언쟁의 파편
		["그녀: \"넌 또 결정하고 있잖아.\"", 3.5],
		["그: \"널 위해서 하는 말이야.\"", 3.5],
		["그녀: \"내가 뭘 원하는지 나한테 물어봤어?\"", 4.0],
	],
	[ # 9회 — 안전벨트
		["핸들을 쥔 그의 손.", 3.0],
		["[i]딸깍.[/i]", 2.0],
		["안전벨트 풀리는 소리.", 3.0],
		["그의 손이 핸들을 더 단단히 쥔다.", 3.5],
		["[i]암전.[/i]", 2.0],
	],
]

static func pages_for_clear(clear_count: int) -> Array:
	var idx := clampi(clear_count, 1, RUN_CUTSCENES.size()) - 1
	return RUN_CUTSCENES[idx]

var _bg: ColorRect
var _label: RichTextLabel
var _pages: Array = []
var _idx: int = -1
var _t: float = 0.0
var _playing: bool = false

func _ready() -> void:
	layer = 21   # 메인 메뉴(20) 위
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 1)
	_bg.size = Vector2(1280, 720)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(160, 280)
	_label.size = Vector2(960, 200)
	var font_neo := load("res://Font/NeoDunggeunmoPro-Regular.ttf") as Font
	if font_neo:
		_label.add_theme_font_override("normal_font", font_neo)
		_label.add_theme_font_override("italics_font", font_neo)
	_label.add_theme_font_size_override("normal_font_size", 26)
	_label.add_theme_font_size_override("italics_font_size", 24)
	_label.add_theme_color_override("default_color", Color(0.82, 0.80, 0.78))
	add_child(_label)
	visible = false

func is_playing() -> bool:
	return _playing

func play(pages: Array) -> void:
	_pages = pages
	_idx = -1
	_t = 0.0
	_playing = true
	visible = true
	_label.modulate.a = 0.0
	_advance()

func _advance() -> void:
	_idx += 1
	_t = 0.0
	if _idx >= _pages.size():
		_playing = false
		visible = false
		finished.emit()
		return
	_label.text = "[center]" + str(_pages[_idx][0]) + "[/center]"

func _process(delta: float) -> void:
	if not _playing or _idx < 0 or _idx >= _pages.size():
		return
	_t += delta
	var dur := float(_pages[_idx][1])
	# 페이드 인 → 유지 → 페이드 아웃
	var a := 1.0
	if _t < FADE:
		a = _t / FADE
	elif _t > dur - FADE:
		a = maxf((dur - _t) / FADE, 0.0)
	_label.modulate.a = a
	if _t >= dur:
		_advance()

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		# 페이지 스킵 (단, 최소 0.8초는 보여준다)
		if _t >= 0.8:
			_advance()
		get_viewport().set_input_as_handled()
