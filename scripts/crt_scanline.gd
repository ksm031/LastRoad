extends Control

# CRT 스캔라인 오버레이 — 매 3픽셀 간격으로 반투명 검정 가로줄
func _draw() -> void:
	var vp_size := get_viewport_rect().size
	var line_color := Color(0.0, 0.0, 0.0, 0.08)
	var y := 0.0
	while y < vp_size.y:
		draw_line(Vector2(0, y), Vector2(vp_size.x, y), line_color, 1.0)
		y += 3.0
