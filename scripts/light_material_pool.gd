extends RefCounted
class_name LightMaterialPool

## 헤드라이트 조명 효과를 위한 ShaderMaterial 풀을 관리하는 클래스입니다.
## 각 시스템(장애물, 나무 등)에서 이 클래스를 인스턴스화하여 사용합니다.

var _materials: Array[ShaderMaterial] = []
var _current_idx: int = 0
var _ambient_normal: Color
var _ambient_dark: Color
var _is_dark: bool = false

func _init(pool_size: int, normal_ambient: Color, dark_ambient: Color) -> void:
	_ambient_normal = normal_ambient
	_ambient_dark   = dark_ambient
	_materials = BillboardManager.create_headlight_materials(pool_size, _ambient_normal)

## 매 프레임 업데이트 시작 시 호출하여 인덱스를 초기화합니다.
func reset() -> void:
	_current_idx = 0

## 다음 가용한 머티리얼을 반환하고 파라미터를 설정합니다.
func get_material(light_h: float, is_jumping: bool = false, jump_t: float = 0.0) -> ShaderMaterial:
	if _current_idx >= _materials.size():
		return null
	
	var mat := _materials[_current_idx]
	mat.set_shader_parameter("light_height", light_h)
	
	# 점퍼 등 특수 유닛을 위한 파라미터 (기본값 false/0.0)
	# 풀 재사용 시 이전 슬롯이 점퍼였다면 jump_t가 남아있을 수 있으므로 둘 다 명시적으로 리셋
	if is_jumping:
		mat.set_shader_parameter("is_jumping", true)
		mat.set_shader_parameter("jump_t", jump_t)
	else:
		mat.set_shader_parameter("is_jumping", false)
		mat.set_shader_parameter("jump_t", 0.0)
	
	_current_idx += 1
	return mat

## 낮/밤 모드에 따라 주변광(Ambient) 색상을 일괄 변경합니다.
func set_dark_mode(dark: bool) -> void:
	_is_dark = dark
	var c := _ambient_dark if _is_dark else _ambient_normal
	for mat in _materials:
		mat.set_shader_parameter("ambient_color", c)
