extends Sprite2D
class_name SmokeParticle

# ── 프로시저럴 담배 연기 텍스처 (최초 1회만 생성) ──────────
static var _wisp_textures: Array[Texture2D] = []
static var _generated: bool = false

const WISP_W := 24    # 약간 넓은 폭 (디테일 확보)
const WISP_H := 96    # 세로로 긴 연기 가닥

# ── 개별 파티클 상태 ─────────────────────────────────────
var _lifetime   : float = 0.0
var _max_life   : float
var _rise_speed : float
var _origin     : Vector2
var _peak_alpha : float
var _sc_start   : float
var _sc_end     : float
var _rot_speed  : float

# ── 다중 사인파 조합으로 유기적 곡선 생성 ──
var _freq1 : float;  var _amp1 : float;  var _phase1 : float
var _freq2 : float;  var _amp2 : float;  var _phase2 : float
var _freq3 : float;  var _amp3 : float;  var _phase3 : float
# 수직 방향 굴곡 (위로 올라가면서 좌우로 밀려가는 drift)
var _drift_dir : float
var _drift_accel : float

func _init(textures: Array[Texture2D], start_pos: Vector2) -> void:
	if not _generated:
		_gen_wisp_textures()
		_generated = true

	_origin = start_pos
	position = start_pos
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# ── 파티클별 랜덤 파라미터 ──
	_max_life   = randf_range(4.0, 6.5)
	_rise_speed = randf_range(50.0, 80.0)
	_peak_alpha = randf_range(0.40, 0.65)     # 일회성이므로 확연히 보이도록 가시성 증대
	_sc_start   = randf_range(0.6, 0.9)
	_sc_end     = randf_range(2.0, 3.5)       # 더 널리 확산되도록 변경
	_rot_speed  = randf_range(-0.5, 0.5)

	# ── 3개의 서로 다른 사인파 → 곡선미를 강조한 유기적 S자 곡선 ──
	_freq1  = randf_range(0.8, 1.6);   _amp1  = randf_range(28.0, 48.0);  _phase1 = randf_range(0.0, TAU)
	_freq2  = randf_range(2.2, 4.0);   _amp2  = randf_range(12.0, 26.0);  _phase2 = randf_range(0.0, TAU)
	_freq3  = randf_range(4.5, 7.0);   _amp3  = randf_range(5.0, 12.0);   _phase3 = randf_range(0.0, TAU)

	# 올라갈수록 한쪽으로 밀려가는 자연스러운 드리프트
	_drift_dir   = randf_range(-1.0, 1.0)      # 좌/우 방향
	_drift_accel = randf_range(6.0, 18.0)       # 밀려가는 가속도

	texture = _wisp_textures[randi() % _wisp_textures.size()]
	modulate = Color(0.80, 0.83, 0.90, 0.0)
	scale = Vector2(_sc_start, _sc_start * 1.3)

# ── 프로시저럴 텍스처 생성 (연기 가닥 5종) ───────────────
static func _gen_wisp_textures() -> void:
	_wisp_textures.clear()
	for v in 5:
		var img := Image.create(WISP_W, WISP_H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var cx := WISP_W / 2.0
		var sv := float(v) * 73.0

		for y in WISP_H:
			for x in WISP_W:
				# ── 가로 가우시안 감쇄 + 좌우 비대칭 흔들림 ──
				var wave_offset := sin(float(y) * 0.15 + sv) * 2.0
				var dx := (float(x) - cx - wave_offset) / (WISP_W * 0.25)
				var h_fall := exp(-dx * dx * 1.5)

				# ── 세로 감쇄 ──
				var vy := float(y) / float(WISP_H - 1)
				var v_fall: float
				if vy < 0.1:
					v_fall = vy / 0.1
				elif vy > 0.6:
					v_fall = (1.0 - vy) / 0.4
				else:
					v_fall = 1.0

				# ── 유기적 노이즈 (3겹 sin/cos 합성) ──
				var n := 0.55
				n += 0.2 * sin(float(y) * 0.35 + sv)
				n += 0.15 * sin(float(y) * 0.9 + float(x) * 1.1 + sv * 0.5)
				n += 0.1 * cos(float(x) * 1.8 + float(y) * 0.25 + sv * 1.3)
				n = clampf(n, 0.0, 1.0)

				var a := h_fall * v_fall * n
				a = clampf(a, 0.0, 1.0)

				var b := 0.80 + 0.15 * sin(float(y) * 0.18 + sv * 0.3)
				img.set_pixel(x, y, Color(b, b, b * 1.05, a))

		_wisp_textures.append(ImageTexture.create_from_image(img))

# ── 매 프레임 업데이트 ────────────────────────────────────
func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= _max_life:
		queue_free()
		return

	var t := _lifetime / _max_life

	# ── 상승 (초반 살짝 가속 → 후반 감속) ──
	var speed_mult := 1.0 + 0.5 * sin(t * PI)  # 중간에 살짝 빠르게
	position.y = _origin.y - _rise_speed * _lifetime * speed_mult * 0.7

	# ── 다중 사인파 합성 → 유기적 곡선 ──
	var sway := 0.0
	sway += sin(_lifetime * _freq1 + _phase1) * _amp1
	sway += sin(_lifetime * _freq2 + _phase2) * _amp2
	sway += sin(_lifetime * _freq3 + _phase3) * _amp3
	# 시간에 따른 드리프트 및 곡선 넓이 증가 (올라갈수록 곡선이 좌우로 커짐)
	var drift := _drift_dir * _drift_accel * _lifetime * _lifetime * 0.18
	position.x = _origin.x + sway * (0.3 + t * 1.3) + drift

	# ── 회전 (꼬이는 느낌) ──
	rotation += _rot_speed * delta

	# ── 스케일: 커지며 세로로 늘어남 ──
	var sc := lerpf(_sc_start, _sc_end, t)
	scale = Vector2(sc, sc * lerpf(1.3, 2.8, t))

	# ── 알파: 페이드인(10%) → 최대 유지(40%) → 서서히 페이드아웃 ──
	var alpha: float
	if t < 0.10:
		alpha = (t / 0.10) * _peak_alpha
	elif t < 0.40:
		alpha = _peak_alpha
	else:
		alpha = _peak_alpha * (1.0 - (t - 0.40) / 0.60)
	modulate.a = maxf(alpha, 0.0)
