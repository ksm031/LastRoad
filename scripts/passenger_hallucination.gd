extends CanvasLayer
class_name PassengerHallucination

# ── 조수석 환영 노드 ──
var _passenger_sprite: TextureRect

var _buckle_timer: float = 0.0
var _rustle_timer: float = 0.0

var _current_level: int = 0  # 0=정상, 1=버클(<=50), 2=실루엣(<=30), 3=선명(<=10)
var _master_volume_altered: bool = false
var _hud_node: Node = null

func _ready() -> void:
	# HUD layer가 15이므로, 조수석 환영은 대시보드 바로 뒷편(layer 9)에 렌더링되거나
	# 부적 가림 UI 등의 관계에 따라 조정합니다.
	# 여기서는 조수석 비주얼만 담당하므로 layer = 9 로 설정합니다.
	layer = 9
	visible = true
	_build_visuals()

func _build_visuals() -> void:
	# 조수석 환영 스프라이트 (화면 오른쪽 조수석 위치)
	_passenger_sprite = TextureRect.new()
	_passenger_sprite.position = Vector2(840, 60)
	_passenger_sprite.size = Vector2(440, 660)
	_passenger_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_passenger_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_passenger_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_passenger_sprite)

func update_sanity(sanity_ratio: float, delta: float) -> void:
	var new_lvl := 0
	if sanity_ratio <= 0.10:
		new_lvl = 3
	elif sanity_ratio <= 0.30:
		new_lvl = 2
	elif sanity_ratio <= 0.50:
		new_lvl = 1
		
	if new_lvl != _current_level:
		_current_level = new_lvl
		_on_level_changed()
		
	_process_hallucination(sanity_ratio, delta)

func _on_level_changed() -> void:
	match _current_level:
		0:
			_passenger_sprite.modulate.a = 0.0
			if _master_volume_altered:
				AudioServer.set_bus_volume_db(0, 0.0)
				_master_volume_altered = false
		1:
			_passenger_sprite.modulate.a = 0.0
			if _master_volume_altered:
				AudioServer.set_bus_volume_db(0, 0.0)
				_master_volume_altered = false
		2:
			# 실루엿 로드
			var tex = load("res://Asset/Image/jiwon_passenger_seat_01.png")
			if tex:
				_passenger_sprite.texture = tex
			_passenger_sprite.modulate = Color(0.15, 0.15, 0.22, 0.5)
			if _master_volume_altered:
				AudioServer.set_bus_volume_db(0, 0.0)
				_master_volume_altered = false
		3:
			# 선명 실루엿 + 고개 돌림
			var tex = load("res://Asset/Image/jiwon_passenger_seat_01.png")
			if tex:
				_passenger_sprite.texture = tex
			_passenger_sprite.modulate = Color(0.6, 0.45, 0.45, 0.95)
			
			# 마스터 볼륨 -50% 감쇄 (-6dB)
			AudioServer.set_bus_volume_db(0, -6.0)
			_master_volume_altered = true

func _process_hallucination(sanity_ratio: float, delta: float) -> void:
	if _current_level >= 1:
		_buckle_timer += delta
		
		# 5초 주기 버클 소리
		if _buckle_timer >= 5.0:
			_buckle_timer = 0.0
			_play_sound("buckle_click")
	else:
		_buckle_timer = 0.0
		
	if _current_level == 2:
		# 반투명 흔들림 연출
		_passenger_sprite.modulate.a = 0.35 + randf() * 0.2
		_rustle_timer += delta
		if _rustle_timer >= 8.0:
			_rustle_timer = 0.0
			_play_sound("rustle")
	elif _current_level == 3:
		# 선명 노이즈 연출
		_passenger_sprite.modulate.a = 0.85 + randf() * 0.1
	else:
		_rustle_timer = 0.0

func _play_sound(sound_type: String) -> void:
	var sfx_path := ""
	if sound_type == "buckle_click":
		sfx_path = "res://Asset/Sound/SFX/click.wav"
	elif sound_type == "rustle":
		sfx_path = "res://Asset/Sound/SFX/rustle.wav"
		
	if sfx_path != "" and FileAccess.file_exists(sfx_path):
		var ap := AudioStreamPlayer.new()
		ap.stream = load(sfx_path)
		ap.volume_db = -12.0
		add_child(ap)
		ap.play()
		ap.finished.connect(ap.queue_free)

func force_stop() -> void:
	_current_level = 0
	_on_level_changed()
