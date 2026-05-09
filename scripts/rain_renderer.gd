extends Node2D

# ── 공중 빗줄기 (차창 밖 비) ────────────────────────────────
const N_AIR_DROPS   := 250
const AIR_SPEED     := 720.0
const AIR_LEAN_DEG  := 12.0
const AIR_LEN       := 22.0

# ── 유리 물방울 풀 ──────────────────────────────────────────
const MAX_DROPS        := 120
const SPAWN_RATE       := 140.0   # drops/sec (풀 축소에 맞춰 조정)
const SLIDE_THRESHOLD  := 2.5     # 이 반지름(px) 이상이면 미끄러짐
const SLIDE_ACCEL_K    := 45.0    # 가속도 계수
const MAX_STRETCH      := 3.0
const MERGE_FACTOR     := 0.82    # 반지름합의 82% 이내면 병합

# ── 와이퍼 감지 ─────────────────────────────────────────────
const WIPER_REACH := 442.0  # HUD에서 스케일이 1.3배 커졌으므로 340.0 -> 442.0으로 증가
const WIPER_MIN   := 10.0

# ── 상태 ───────────────────────────────────────────────────
var is_raining : bool = false
var vehicle_speed : float = 0.0

# 공중 빗줄기
var _rx : PackedFloat32Array
var _ry : PackedFloat32Array
var _rs : PackedFloat32Array

# 유리 방울 풀 (r<0.01 = 비활성 슬롯)
var _dx       : PackedFloat32Array
var _dy       : PackedFloat32Array
var _dr       : PackedFloat32Array
var _dvy      : PackedFloat32Array
var _dstretch : PackedFloat32Array

# 와이퍼 상태 (game_world에서 매 프레임 동기화)
var _wp      : Array[Vector2] = [Vector2(280.0, 450.0), Vector2(750.0, 450.0)]
var _wa_prev : Array[float]   = [0.0, 0.0]
var _wa_curr : Array[float]   = [0.0, 0.0]

# 스폰 누적
var _spawn_acc : float = 0.0
var _merge_frame : int = 0

# 셰이더 오버레이
var _shader_mat : ShaderMaterial
var _bb         : BackBufferCopy
var _glass      : Node2D

var _mask_vp : SubViewport
var _fog_adder : Node2D
var _wiper_eraser : Node2D
var _current_delta : float = 0.0
var _air_drops_layer : Node2D

# ────────────────────────────────────────────────────────────
func _ready() -> void:
	_rx.resize(N_AIR_DROPS)
	_ry.resize(N_AIR_DROPS)
	_rs.resize(N_AIR_DROPS)
	for i in N_AIR_DROPS:
		_rx[i] = randf() * BillboardManager.SCREEN_W
		_ry[i] = randf() * BillboardManager.SCREEN_H
		_rs[i] = 0.55 + randf() * 0.90

	_dx.resize(MAX_DROPS)
	_dy.resize(MAX_DROPS)
	_dr.resize(MAX_DROPS)
	_dvy.resize(MAX_DROPS)
	_dstretch.resize(MAX_DROPS)
	for i in MAX_DROPS:
		_dr[i]       = 0.0
		_dstretch[i] = 1.0

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load("res://scripts/windshield_glass.gdshader")
	_shader_mat.set_shader_parameter("screen_size", Vector2(BillboardManager.SCREEN_W, BillboardManager.SCREEN_H))
	
	_mask_vp = SubViewport.new()
	_mask_vp.size = Vector2(BillboardManager.SCREEN_W, BillboardManager.SCREEN_H)
	_mask_vp.disable_3d = true
	_mask_vp.transparent_bg = false
	_mask_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mask_vp)
	
	_fog_adder = Node2D.new()
	_fog_adder.draw.connect(_on_fog_add_draw)
	_mask_vp.add_child(_fog_adder)
	
	_wiper_eraser = Node2D.new()
	var sub_mat = CanvasItemMaterial.new()
	sub_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	_wiper_eraser.material = sub_mat
	_wiper_eraser.draw.connect(_on_wiper_erase_draw)
	_mask_vp.add_child(_wiper_eraser)

	_shader_mat.set_shader_parameter("wipe_mask", _mask_vp.get_texture())
	_push_drops_to_shader()

	_bb = BackBufferCopy.new()
	_bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_bb.visible = false
	add_child(_bb)

	_glass = Node2D.new()
	_glass.material = _shader_mat
	_glass.visible = false
	_glass.draw.connect(_on_glass_draw)
	add_child(_glass)

	_air_drops_layer = Node2D.new()
	_air_drops_layer.draw.connect(_on_air_drops_draw)
	add_child(_air_drops_layer)


func _on_glass_draw() -> void:
	_glass.draw_rect(Rect2(0.0, 0.0, BillboardManager.SCREEN_W, BillboardManager.SCREEN_H), Color.WHITE)


# ── 공개 API ────────────────────────────────────────────────
func start_rain() -> void:
	is_raining = true
	_bb.visible = true
	_glass.visible = true


## 클리어 연출용: 빗줄기는 유지하되 성애·물방울만 즉시 제거
func hide_glass_effects() -> void:
	for i in MAX_DROPS:
		_dr[i] = 0.0
	_push_drops_to_shader()
	_mask_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	await get_tree().process_frame
	_mask_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_bb.visible = false
	_glass.visible = false


func stop_rain() -> void:
	is_raining = false
	for i in MAX_DROPS:
		_dr[i] = 0.0
	_push_drops_to_shader()
	_shader_mat.set_shader_parameter("wet_amount", 0.0)
	# 성애 마스크 초기화 — CLEAR_MODE_NEVER이므로 한 프레임만 ALWAYS로 전환해 클리어
	_mask_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	await get_tree().process_frame
	_mask_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_bb.visible = false
	_glass.visible = false
	queue_redraw()
	_air_drops_layer.queue_redraw()


## hud의 와이퍼 피벗 위치/현재 각도를 매 프레임 전달받음.
func set_wiper_transforms(lp: Vector2, lr: float, rp: Vector2, rr: float) -> void:
	_wp[0] = lp
	_wp[1] = rp
	_wa_prev[0] = _wa_curr[0]
	_wa_prev[1] = _wa_curr[1]
	_wa_curr[0] = lr
	_wa_curr[1] = rr


# ────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not is_raining:
		return
	_current_delta = delta
	_fog_adder.queue_redraw()
	_wiper_eraser.queue_redraw()
	_air_drops_layer.queue_redraw()

	_update_air(delta)
	_spawn_drops(delta)
	_update_drops(delta)
	_wipe_drops()
	_merge_frame += 1
	if _merge_frame >= 3:
		_merge_frame = 0
		_merge_drops()
	_push_drops_to_shader()
	queue_redraw()
	_glass.queue_redraw()

func _on_fog_add_draw() -> void:
	if not is_raining: return
	# 2.0초 동안 완전히 하얗게(1.0) 되려면 초당 1/2.0씩 더함
	_fog_adder.draw_rect(Rect2(0, 0, BillboardManager.SCREEN_W, BillboardManager.SCREEN_H), Color(1, 1, 1, _current_delta / 2.0))

func _on_wiper_erase_draw() -> void:
	if not is_raining: return
	for w in 2:
		var p = _wp[w]
		var a0 = _wa_prev[w]
		var a1 = _wa_curr[w]
		if is_equal_approx(a0, a1):
			continue
		
		# 앞뒤로 조금 여유를 둬서 부채꼴 그리기
		var amin = minf(a0, a1) - 0.08
		var amax = maxf(a0, a1) + 0.08
		
		var pts = PackedVector2Array()
		pts.append(p)
		
		var steps = max(2, int((amax - amin) * 20))
		for i in range(steps + 1):
			var a = lerpf(amin, amax, float(i) / float(steps))
			pts.append(p + Vector2(cos(a), sin(a)) * WIPER_REACH)
		
		_wiper_eraser.draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 1)]))

# ── 공중 빗줄기 ─────────────────────────────────────────────
func _update_air(delta: float) -> void:
	var lean := deg_to_rad(AIR_LEAN_DEG)
	var vx_base := sin(lean) * AIR_SPEED
	var vy_base := cos(lean) * AIR_SPEED
	
	# 속도에 비례하는 퍼짐 효과 (차가 빠를수록 좌우로 비가 갈라짐)
	var spread_factor := vehicle_speed * 0.015
	var center_x := BillboardManager.SCREEN_W * 0.5
	
	for i in N_AIR_DROPS:
		var x := _rx[i]
		var y := _ry[i]
		
		var dx := x - center_x
		# 화면 중앙을 기준으로 좌우로 퍼지는 속도 추가
		var vx := vx_base + dx * spread_factor * _rs[i]
		
		# y 속도는 기본 낙하 속도 + 차속에 따른 가속(빠를수록 비가 더 세차게 스쳐 지나감)
		var vy := vy_base + vehicle_speed * 2.5 * _rs[i]
		
		_rx[i] += vx * delta
		_ry[i] += vy * delta
		
		# 화면 밖으로 나가면 다시 저 멀리 위에서 떨어지도록 스폰
		if _ry[i] > BillboardManager.SCREEN_H + 15.0 or _rx[i] < -200.0 or _rx[i] > BillboardManager.SCREEN_W + 200.0:
			# 기본 스폰 (위에서 아래로)
			_rx[i] = randf() * BillboardManager.SCREEN_W
			_ry[i] = randf_range(-150.0, -10.0)


# ── 유리 방울 스폰 ──────────────────────────────────────────
func _spawn_drops(delta: float) -> void:
	_spawn_acc += SPAWN_RATE * delta
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_spawn_one()


func _spawn_one() -> void:
	for i in MAX_DROPS:
		if _dr[i] < 0.01:
			_dx[i] = randf() * BillboardManager.SCREEN_W
			_dy[i] = randf() * BillboardManager.SCREEN_H
			var roll := randf()
			if roll < 0.40:
				_dr[i] = 1.5 + randf() * 2.0     # 1단계 (가장 작은 크기, 1.5 ~ 3.5)
			elif roll < 0.65:
				_dr[i] = 3.0 + randf() * 1.5     # 2단계 (3.0 ~ 4.5)
			elif roll < 0.85:
				_dr[i] = 4.5 + randf() * 1.5     # 3단계 (4.5 ~ 6.0)
			elif roll < 0.95:
				_dr[i] = 6.0 + randf() * 1.5     # 4단계 (6.0 ~ 7.5)
			else:
				_dr[i] = 7.0 + randf() * 0.6     # 5단계 (가장 큰 크기, 7.0 ~ 7.6)
			_dvy[i] = 0.0
			_dstretch[i] = 1.0
			return



# ── 물방울 갱신 (중력, 미끄러짐, 꼬리 자국) ────────────────
func _update_drops(delta: float) -> void:
	for i in MAX_DROPS:
		var r := _dr[i]
		if r < 0.01:
			continue

		if r > SLIDE_THRESHOLD:
			var accel := (r - SLIDE_THRESHOLD) * SLIDE_ACCEL_K
			_dvy[i] = _dvy[i] * 0.985 + accel * delta
			_dy[i] += _dvy[i] * delta

			var target_stretch := clampf(1.0 + _dvy[i] * 0.014, 1.0, MAX_STRETCH)
			_dstretch[i] = lerpf(_dstretch[i], target_stretch, clampf(delta * 5.5, 0.0, 1.0))

			# 움직이는 방울 뒤에 작은 자국 남기기
			if _dvy[i] > 18.0 and randf() < delta * 3.2:
				_leave_residue(i)
		else:
			_dvy[i] *= 0.88
			_dstretch[i] = lerpf(_dstretch[i], 1.0, clampf(delta * 2.5, 0.0, 1.0))

		# 화면 밖
		if _dy[i] > BillboardManager.SCREEN_H + 50.0:
			_dr[i] = 0.0


func _leave_residue(idx: int) -> void:
	for i in MAX_DROPS:
		if _dr[i] < 0.01:
			_dx[i] = _dx[idx] + randf_range(-1.5, 1.5)
			_dy[i] = _dy[idx] - _dr[idx] * _dstretch[idx] * 0.95
			_dr[i] = 0.9 + randf() * 1.4
			_dvy[i] = 0.0
			_dstretch[i] = 1.0
			return


# ── 와이퍼가 쓸고 지나간 방울만 제거 ────────────────────────
func _wipe_drops() -> void:
	var reach_sq := WIPER_REACH * WIPER_REACH
	var min_sq := WIPER_MIN * WIPER_MIN
	for w in 2:
		var pv := _wp[w]
		var a0 := _wa_prev[w]
		var a1 := _wa_curr[w]
		if is_equal_approx(a0, a1):
			continue
		var amin := minf(a0, a1) - 0.08  # 와이퍼 블레이드의 두께(약 4.5도)를 고려하여 패딩 추가
		var amax := maxf(a0, a1) + 0.08  # 이렇게 하면 올라갈 때도 두께만큼 앞서서 지워지므로 깔끔해 보임
		for i in MAX_DROPS:
			if _dr[i] < 0.01:
				continue
			var lx := _dx[i] - pv.x
			var ly := _dy[i] - pv.y
			var r2 := lx * lx + ly * ly
			if r2 > reach_sq or r2 < min_sq:
				continue
			var ang := atan2(ly, lx)
			if ang >= amin and ang <= amax:
				_dr[i] = 0.0


# ── 근접 방울 병합 (면적 보존) ──────────────────────────────
func _merge_drops() -> void:
	for i in MAX_DROPS:
		var ri := _dr[i]
		if ri < 0.01:
			continue
		for j in range(i + 1, MAX_DROPS):
			var rj := _dr[j]
			if rj < 0.01:
				continue
			var dx := _dx[i] - _dx[j]
			var dy := _dy[i] - _dy[j]
			var d2 := dx * dx + dy * dy
			var mr := (ri + rj) * MERGE_FACTOR
			if d2 < mr * mr:
				var nr := sqrt(ri * ri + rj * rj)
				var wi := ri * ri
				var wj := rj * rj
				var wsum := wi + wj
				_dx[i] = (_dx[i] * wi + _dx[j] * wj) / wsum
				_dy[i] = (_dy[i] * wi + _dy[j] * wj) / wsum
				_dr[i] = nr
				_dvy[i] = (_dvy[i] * wi + _dvy[j] * wj) / wsum
				_dstretch[i] = maxf(_dstretch[i], _dstretch[j])
				_dr[j] = 0.0
				break  # i는 한 프레임에 한 번만 병합


# ── 셰이더 유니폼 갱신 (활성 물방울만 패킹) ──────────────────
func _push_drops_to_shader() -> void:
	var data := PackedVector4Array()
	data.resize(MAX_DROPS)
	var idx := 0
	for i in MAX_DROPS:
		if _dr[i] >= 0.5:
			data[idx] = Vector4(_dx[i], _dy[i], _dr[i], _dstretch[i])
			idx += 1
	# 나머지 비활성 슬롯을 0으로 채움
	for j in range(idx, MAX_DROPS):
		data[j] = Vector4(0.0, 0.0, 0.0, 1.0)
	_shader_mat.set_shader_parameter("drops", data)


# ── 공중 빗줄기만 직접 그림 ─────────────────────────────────
func _draw_air_drops(target: CanvasItem, alpha_mult: float) -> void:
	if not is_raining:
		return
	var lean := deg_to_rad(AIR_LEAN_DEG)
	var vx_base := sin(lean) * AIR_SPEED
	var vy_base := cos(lean) * AIR_SPEED
	
	var spread_factor := vehicle_speed * 0.015
	var center_x := BillboardManager.SCREEN_W * 0.5
	
	for i in N_AIR_DROPS:
		var x := _rx[i]
		var y := _ry[i]
		var sp := _rs[i]
		
		# 현재 위치에서의 실제 속도 벡터 계산 (선이 그려지는 방향)
		var dx := x - center_x
		var vx := vx_base + dx * spread_factor * sp
		var vy := vy_base + vehicle_speed * 2.5 * sp
		
		var v_len := sqrt(vx*vx + vy*vy)
		var ex := vx / v_len if v_len > 0.0 else 0.0
		var ey := vy / v_len if v_len > 0.0 else 1.0
		
		var t := clampf(y / BillboardManager.SCREEN_H, 0.0, 1.0)
		var a := (0.22 + t * 0.38 + (sp - 0.55) * 0.12) * alpha_mult
		var ln := AIR_LEN * (0.5 + t * 0.7 + (sp - 0.55) * 0.4)
		
		# 속도가 빠를수록 빗줄기도 더 길어짐
		ln *= clampf(v_len / AIR_SPEED, 1.0, 3.5)
		
		target.draw_line(
			Vector2(x, y),
			Vector2(x + ex * ln, y + ey * ln),
			Color(0.70, 0.80, 0.95, a),
			1.0
		)

func _draw() -> void:
	if not is_raining:
		return
	_draw_air_drops(self, 1.0)

func _on_air_drops_draw() -> void:
	if not is_raining:
		return
	_draw_air_drops(_air_drops_layer, 0.3)
