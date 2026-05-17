extends Node2D
class_name BloodDripParticle

var _velocity: Vector2
var _lifetime: float
var _depth_scale: float = 1.0
const MAX_LIFE := 0.45

func _init(origin: Vector2, depth_scale: float = 1.0) -> void:
	position = origin
	_depth_scale = depth_scale
	# 원근감에 비례한 운동 속도(속차 페럴렉스) 보정
	_velocity = Vector2(randf_range(-18.0, 18.0), randf_range(70.0, 120.0)) * _depth_scale
	_lifetime = MAX_LIFE
	z_index = 12

func _process(delta: float) -> void:
	_lifetime -= delta
	position += _velocity * delta
	# 원근감에 비례한 중력 낙하 보정
	_velocity.y += (280.0 * _depth_scale) * delta
	modulate.a = clampf(_lifetime / MAX_LIFE, 0.0, 1.0)
	queue_redraw()
	if _lifetime <= 0.0:
		queue_free()

func _draw() -> void:
	var a := modulate.a
	# 원근감에 비례한 혈방울 크기 스케일링 (가독성 보장을 위한 최소 크기 한계선 보정)
	var r1 := maxf(2.2 * _depth_scale, 1.4)
	var r2 := maxf(1.4 * _depth_scale, 0.9)
	var offset_y := maxf(2.5 * _depth_scale, 1.8)
	
	draw_circle(Vector2.ZERO, r1, Color(0.82, 0.08, 0.04, a))
	draw_circle(Vector2(0.0, offset_y), r2, Color(0.55, 0.03, 0.02, a * 0.75))
