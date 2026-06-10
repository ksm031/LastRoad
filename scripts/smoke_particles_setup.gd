@tool
extends GPUParticles2D

# ── 비주얼 스타일 선택 옵션 (Smooth/HD vs Pixel Art) ──
@export_enum("Smooth/HD", "Pixel Art") var visual_style: String = "Smooth/HD":
	set(val):
		visual_style = val
		_update_particle_settings()

@export var trajectory_offset: float = 0.0:
	set(val):
		trajectory_offset = val
		_update_particle_settings()

@export var rise_speed_override: float = 35.0:
	set(val):
		rise_speed_override = val
		_update_particle_settings()

@export var sway_amplitude_override: float = 42.0:
	set(val):
		sway_amplitude_override = val
		_update_particle_settings()

@export var amount_override: int = 150:
	set(val):
		amount_override = val
		_update_particle_settings()

@export var lifetime_override: float = 5.5:
	set(val):
		lifetime_override = val
		_update_particle_settings()

@export var branch_direction: float = 0.0:
	set(val):
		branch_direction = val
		_update_particle_settings()

func _ready() -> void:
	_update_particle_settings()

func _update_particle_settings() -> void:
	# ── 1. GPUParticles2D 기본 노드 프로퍼티 설정 ──
	self.amount = amount_override                  # 개수 설정
	self.lifetime = lifetime_override              # 입자 생존 수명
	self.local_coords = false                      # 로컬 좌표계 미사용 (이동 시 뒤에 흔적이 자연스럽게 남음)
	
	# 연기 기본 텍스처 로드 및 대입
	var tex_path := "res://Asset/Image/Particle/smoke_01.png"
	if ResourceLoader.exists(tex_path):
		self.texture = load(tex_path)
	
	# ── 2. CanvasItemMaterial 블렌드 모드 설정 ──
	var mat := self.material as CanvasItemMaterial
	if not mat:
		mat = CanvasItemMaterial.new()
		self.material = mat
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	
	# 필터 설정 및 셰이더용 최대 스케일 한계 결정 (크기 대폭 확장 적용)
	var max_scale := 1.1
	if visual_style == "Smooth/HD":
		self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # 부드러운 필터링
		max_scale = 1.1
	else: # "Pixel Art"
		self.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 픽셀 아트용 필터링
		max_scale = 0.7
		
	# ── 3. Custom ShaderMaterial 설정 (입자 자체의 곡선 비행용) ──
	var sm := self.process_material as ShaderMaterial
	if not sm:
		sm = ShaderMaterial.new()
		self.process_material = sm
		
	# 작성한 입자 제어 셰이더 파일 로드 및 바인딩
	var shader_res = load("res://scripts/smoke_particles.gdshader")
	if shader_res:
		sm.shader = shader_res
		# 셰이더 내 유니폼 변수(Uniform Parameters) 주입
		sm.set_shader_parameter("rise_speed", rise_speed_override)          # 입자 수직 상승 속도
		sm.set_shader_parameter("sway_amplitude", sway_amplitude_override)  # 입자 좌우 흔들림 최대폭
		sm.set_shader_parameter("sway_frequency", 0.015)                   # 굴곡 횟수 제어 주파수
		sm.set_shader_parameter("sway_speed", 1.2)                         # 파동의 흐름 속도
		sm.set_shader_parameter("particle_lifetime", lifetime_override)    # 수명
		sm.set_shader_parameter("trajectory_offset", trajectory_offset)    # 궤적 차별화 오프셋
		sm.set_shader_parameter("branch_direction", branch_direction)      # 좌우 분기 방향
		sm.set_shader_parameter("scale_min", 0.06)                         # 최소 크기
		sm.set_shader_parameter("scale_max", max_scale)                    # 최대 크기
