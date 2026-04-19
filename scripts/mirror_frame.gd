extends Node2D

func _draw() -> void:
	# 크롬 테두리
	draw_rect(Rect2(548.0, 8.0, 184.0, 94.0), Color(0.40, 0.35, 0.28))
	# 어두운 내부 배경 (초상화 없을 때 폴백)
	draw_rect(Rect2(550.0, 10.0, 180.0, 90.0), Color(0.04, 0.04, 0.06))
