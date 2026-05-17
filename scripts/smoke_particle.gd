extends Sprite2D
class_name SmokeParticle

var _textures: Array[Texture2D] = []
const FRAME_TIME    := 0.15 # 애니메이션 속도 2배 가속 (0.3 -> 0.15)
var _current_frame : int = 0
var _timer         : float = 0.0
var _rise_speed    : float = 210.0 # 위로 상승하는 속도 2.1배 가속 (100.0 -> 210.0)

func _init(textures: Array[Texture2D], start_pos: Vector2) -> void:
	_textures = textures
	position = start_pos
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(3.0, 3.0) # 기본 2.0배 -> 1.5배 키워서 3.0배로 시작!
	rotation = randf_range(-0.5, 0.5)
	if not _textures.is_empty():
		texture = _textures[0]
	modulate.a = 0.0

func _process(delta: float) -> void:
	var total_frames = _textures.size()
	if total_frames == 0:
		queue_free()
		return
		
	_timer += delta
	if _timer >= FRAME_TIME:
		_timer -= FRAME_TIME
		_current_frame += 1
		
		if _current_frame >= total_frames:
			queue_free()
			return
		
		texture = _textures[_current_frame]
		
		# 투명도 제어 (18프레임 기준 비율로 계산)
		var t_ratio = float(_current_frame) / float(total_frames - 1) if total_frames > 1 else 1.0
		
		if _current_frame < 3:
			modulate.a = float(_current_frame + 1) / 3.0
		elif _current_frame < 8:
			modulate.a = 1.0
		else:
			# 9~18프레임 구간에서 남은 프레임 수에 따라 페이드 아웃
			var fade_frames = total_frames - 8
			if fade_frames > 0:
				var fade_out_step = float(_current_frame - 7)
				modulate.a = clampf(1.0 - (fade_out_step / float(fade_frames)), 0.0, 1.0)

	# 위로 올라가는 움직임
	position.y -= _rise_speed * delta
	# 약간의 좌우 흔들림 추가 (자연스러움)
	position.x += sin(Time.get_ticks_msec() * 0.005 + get_instance_id()) * 0.5
	
	# 시간이 지날수록 연기가 퍼짐 (3.0 -> 5.25로 1.5배 확대 보정!)
	var grow_ratio = float(_current_frame) / float(total_frames)
	var current_sc = lerpf(3.0, 5.25, grow_ratio)
	scale = Vector2(current_sc, current_sc)
