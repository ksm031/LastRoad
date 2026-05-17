extends CanvasLayer
class_name HallucinationVideo

## 환각 영상 시스템
## 정신력이 0이 되면 주기적으로 실사 영상을 오버레이 재생.
## 영상 종료 시 게임 화면 전체에 글리치 이펙트.

# ── 튜닝 파라미터 ──────────────────────────────────────────
var TRIGGER_INTERVAL   := 30.0   # 트리거 체크 주기 (초)
var TRIGGER_CHANCE     := 1.0    # 발동 확률 (0.0~1.0, 지금은 100%)
var VIDEO_ALPHA        := 0.35   # 영상 투명도 (35%)

# 글리치 아웃 연출
const GLITCH_OUT_DURATION := 0.12   # 글리치 효과로 사라지는 시간 (초)
const GLITCH_RAMP_START   := 0.12   # 영상 끝나기 이 시간 전부터 글리치 시작 (초)

# ── 내부 상태 ──────────────────────────────────────────────
var _trigger_timer     := 0.0
var _is_playing        := false
var _glitch_phase      := false
var _glitch_timer      := 0.0
var _time_acc          := 0.0

# 수동 글리치 (환영 충돌 등)
var _manual_glitch     := false
var _manual_glitch_timer := 0.0
var _manual_glitch_dur   := 0.3

# ── 노드 참조 ──────────────────────────────────────────────
var _video_player  : VideoStreamPlayer
var _root_control  : Control

# 글리치 오버레이 (screen_texture 미사용 — 반투명 노이즈 덮어씌움)
var _glitch_rect   : ColorRect
var _glitch_mat    : ShaderMaterial

# ── 비디오 스트림 ──────────────────────────────────────────
var _video_stream  : VideoStream

func _ready() -> void:
	layer = 19
	_build_video_ui()
	_build_glitch_overlay()
	_load_video()

func _load_video() -> void:
	var ogv_path := "res://Asset/Movie/jiwon_body.ogv"
	if ResourceLoader.exists(ogv_path):
		_video_stream = load(ogv_path)
		print("[환각영상] ogv 로드 완료")
	else:
		push_warning("[환각영상] 영상 파일을 찾을 수 없음: " + ogv_path)

func _build_video_ui() -> void:
	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.visible = false
	add_child(_root_control)

	_video_player = VideoStreamPlayer.new()
	_video_player.expand = true
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_player.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_video_player.finished.connect(_on_video_finished)
	_root_control.add_child(_video_player)

func _build_glitch_overlay() -> void:
	# screen_texture를 쓰지 않는 순수 오버레이 방식
	# glitch_intensity=0이면 셰이더가 alpha=0을 출력 → 완전 투명
	_glitch_rect = ColorRect.new()
	_glitch_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch_rect.color = Color.WHITE  # 알파 0이면 고도 엔진이 렌더링을 생략(Culling)할 수 있으므로 흰색 지정
	_glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_rect.visible = false  # 평소엔 숨김 — 글리치 시에만 켬

	var shader_path := "res://scripts/video_glitch.gdshader"
	if ResourceLoader.exists(shader_path):
		_glitch_mat = ShaderMaterial.new()
		_glitch_mat.shader = load(shader_path)
		_glitch_mat.set_shader_parameter("glitch_intensity", 0.0)
		_glitch_mat.set_shader_parameter("glitch_time", 0.0)
		_glitch_mat.set_shader_parameter("glitch_seed", randf() * 1000.0)
		_glitch_rect.material = _glitch_mat
	
	add_child(_glitch_rect)

# ── 외부 호출: 매 프레임 정신력 전달 ──────────────────────
func update_sanity(sanity: float, delta: float) -> void:
	_time_acc += delta
	if _glitch_mat:
		_glitch_mat.set_shader_parameter("glitch_time", _time_acc)

	# 수동 글리치 업데이트
	if _manual_glitch:
		_update_manual_glitch(delta)
		return

	# [디버그] H 키로 즉시 재생 테스트
	if Input.is_key_pressed(KEY_H) and not _is_playing:
		_start_playback()
		return

	if _is_playing:
		_update_playing(delta)
		return

	if sanity > 0.0:
		_trigger_timer = 0.0
		return

	_trigger_timer += delta
	if _trigger_timer >= TRIGGER_INTERVAL:
		_trigger_timer = 0.0
		if randf() <= TRIGGER_CHANCE:
			_start_playback()

## 수동 글리치 트리거 (환영 충돌 등에서 재사용)
func trigger_glitch(duration: float = 0.3) -> void:
	if _is_playing: return # 영상 재생 중에는 무시
	
	_manual_glitch = true
	_manual_glitch_timer = 0.0
	_manual_glitch_dur = duration
	_glitch_rect.visible = true
	if _glitch_mat:
		_glitch_mat.set_shader_parameter("glitch_seed", randf() * 1000.0)

func _update_manual_glitch(delta: float) -> void:
	_manual_glitch_timer += delta
	var t := _manual_glitch_timer / _manual_glitch_dur
	
	if t >= 1.0:
		_manual_glitch = false
		_glitch_rect.visible = false
		if _glitch_mat:
			_glitch_mat.set_shader_parameter("glitch_intensity", 0.0)
		return
	
	# 피크가 중간에 오도록 설정 (0 -> 1 -> 0)
	var intensity := sin(t * PI)
	if _glitch_mat:
		_glitch_mat.set_shader_parameter("glitch_intensity", intensity)

func _start_playback() -> void:
	if _video_stream == null or _is_playing:
		return

	_is_playing = true
	_glitch_phase = false
	_glitch_timer = 0.0
	# _time_acc 는 유지

	# 글리치 초기화
	if _glitch_mat:
		_glitch_mat.set_shader_parameter("glitch_intensity", 0.0)
		_glitch_mat.set_shader_parameter("glitch_seed", randf() * 1000.0)

	_video_player.stream = _video_stream

	# 페이드 인 연출 (1초)
	_video_player.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween = create_tween()
	tween.tween_property(_video_player, "modulate", Color(1.0, 1.0, 1.0, VIDEO_ALPHA), 1.0)

	_video_player.play()
	_root_control.visible = true

	print("[환각영상] 재생 시작")

func _update_playing(delta: float) -> void:
	if _glitch_phase:
		_update_glitch_out(delta)
		return

	var stream_len := _video_player.get_stream_length()
	var remaining  := stream_len - _video_player.stream_position

	if stream_len > 0.0 and remaining <= GLITCH_RAMP_START and remaining > 0.0:
		_begin_glitch_out()

func _begin_glitch_out() -> void:
	if _glitch_phase: return
	_glitch_phase = true
	_glitch_timer = 0.0
	_glitch_rect.visible = true
	print("[환각영상] 글리치 시작! mat=", _glitch_mat != null)

func _update_glitch_out(delta: float) -> void:
	_glitch_timer += delta
	var t := clampf(_glitch_timer / GLITCH_OUT_DURATION, 0.0, 1.0)
	var intensity := smoothstep(0.0, 1.0, t)

	if _glitch_mat:
		_glitch_mat.set_shader_parameter("glitch_intensity", intensity)

	# 영상도 함께 서서히 사라짐
	_video_player.modulate = Color(1.0, 1.0, 1.0, VIDEO_ALPHA * (1.0 - smoothstep(0.3, 1.0, t)))

	if t >= 1.0:
		_finish_playback()

func _on_video_finished() -> void:
	if not _glitch_phase:
		_begin_glitch_out()

func _finish_playback() -> void:
	_is_playing = false
	_glitch_phase = false
	_video_player.stop()
	_root_control.visible = false
	_glitch_rect.visible = false  # 글리치 종료 시 숨김

	if _glitch_mat:
		_glitch_mat.set_shader_parameter("glitch_intensity", 0.0)

	print("[환각영상] 재생 종료")

func force_stop() -> void:
	if _is_playing:
		_finish_playback()

func is_playing() -> bool:
	return _is_playing or _manual_glitch
