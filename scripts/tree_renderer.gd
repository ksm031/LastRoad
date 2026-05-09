extends Node2D
const BillboardManager = preload("res://scripts/billboard_manager.gd")

# ── 상수 (BillboardManager 투영 모델 사용) ─────

const TREE_BASE_H    := 480.0
const DZ_MIN         := 0.001
const DZ_MAX         := 72.0
# 도로(차선) 쪽으로 당겨지는 산란을 상쇄 — depth 1 기준 픽셀, 바깥으로만 밀기
const TREE_MARGIN_FROM_ROAD := 28.0

# 모든 레이어: [edge_mult, spacing, x_scatter_px] — edge_mult는 road_hw 배수(도로 밖 거리)
const LAYER_CONFIGS := [
	[1.22, 3.0,  18],   # 도로 바로 옆 (이전 1.05 → 차선 침범 방지)
	[1.40, 4.0,  50],
	[1.68, 5.5, 115],
	[2.02, 2.5, 195],
	[2.34, 2.5, 255],
	[2.82, 3.0, 325],
	[3.48, 3.0, 425],
	[4.58, 3.5, 555],
]

var scroll_z : float = 0.0
var cam_x    : float = 0.0
var _curve_x : PackedFloat32Array = PackedFloat32Array()
var hill_px  : float = 0.0
var scavenging_sys: Node2D = null
var seed_offset : int = 0  # 스테이지마다 다른 배치를 위한 시드 오프셋
var _textures : Array[Texture2D] = []
var billboard_mgr: Node # BillboardManager
var _range_mult : float = 1.0
var _light_pool : LightMaterialPool
const POOL_SIZE := 400

func _ready() -> void:
	for i in range(1, 8):
		var t := load("res://Asset/Image/trees/tree_%02d.png" % i) as Texture2D
		if t:
			_textures.append(t)
	
	_light_pool = LightMaterialPool.new(POOL_SIZE, _AMBIENT_NORMAL, _AMBIENT_DARK)

const _AMBIENT_NORMAL := Color(0.35, 0.38, 0.32, 1.0)
const _AMBIENT_DARK   := Color(0.04, 0.05, 0.03, 1.0)

func set_dark_mode(is_dark: bool) -> void:
	if _light_pool:
		_light_pool.set_dark_mode(is_dark)

func update_state(sz: float, cx: float, p_curve_x: PackedFloat32Array = PackedFloat32Array(), p_hill_px: float = 0.0, p_range_mult: float = 1.0) -> void:
	scroll_z = sz
	cam_x    = cx
	_curve_x = p_curve_x
	hill_px  = p_hill_px
	_range_mult = p_range_mult
	_update_billboards()

func _update_billboards() -> void:
	if _textures.is_empty() or billboard_mgr == null:
		return
	if _light_pool:
		_light_pool.reset()
		
	for side in [-1, 1]:
		for li in range(LAYER_CONFIGS.size()):
			var edge_mult := float(LAYER_CONFIGS[li][0])
			var spacing   := float(LAYER_CONFIGS[li][1])
			var x_scatter := int(LAYER_CONFIGS[li][2])
			var z_offset  := float(li) * spacing * 0.37 + (0.0 if side == -1 else spacing * 0.5)

			var k_min := int(ceilf((scroll_z + DZ_MIN - z_offset) / spacing))
			var k_max := mini(int(floorf((scroll_z + DZ_MAX - z_offset) / spacing)), k_min + 65)

			for k in range(k_min, k_max + 1):
				var wz  := float(k) * spacing + z_offset
				var dz  := wz - scroll_z
				if dz <= 0.0:
					continue
					
				if scavenging_sys != null and scavenging_sys.is_in_clear_zone(wz, side):
					continue

				var proj := BillboardManager.calculate_projection(dz, cam_x, _curve_x, hill_px, _range_mult)
				var depth: float = proj.depth

				var hash_val := absi((k + seed_offset) * 134775813 + side * 1103515245 + li * 987654321)
				var xvar     := float(hash_val % (x_scatter * 2) - x_scatter) * depth
				var margin   := float(side) * depth * TREE_MARGIN_FROM_ROAD
				var tx: float = float(proj.road_cx) + float(side) * float(proj.road_hw) * edge_mult + xvar + margin

				var th  := depth * TREE_BASE_H
				var tex := _textures[_tex_idx(k, side, li)]
				var tw  := th * float(tex.get_width()) / float(tex.get_height())

				if tx + tw * 0.5 < 0.0 or tx - tw * 0.5 > BillboardManager.SCREEN_W:
					continue

				var fade := 1.0 - clampf((dz - DZ_MAX * 0.75) / (DZ_MAX * 0.25), 0.0, 1.0)

				var c_r := 0.32
				var c_g := 0.38
				var c_b := 0.26
				if hash_val % 100 < 40:
					var r_shift = (float(hash_val % 21) / 20.0) * 0.2 - 0.1
					var g_shift = (float((hash_val / 21) % 21) / 20.0) * 0.2 - 0.1
					var b_shift = (float((hash_val / 441) % 21) / 20.0) * 0.2 - 0.1
					c_r = clampf(c_r + r_shift, 0.0, 1.0)
					c_g = clampf(c_g + g_shift, 0.0, 1.0)
					c_b = clampf(c_b + b_shift, 0.0, 1.0)

				var rect = Rect2(tx - tw * 0.5, float(proj.ground_y) - th, tw, th)
				
				var mat := _light_pool.get_material(float(proj.light_h)) if _light_pool else null
				billboard_mgr.add_entry(depth, rect, tex, fade, mat, Color(c_r, c_g, c_b))

func _tex_idx(k: int, side: int, layer: int) -> int:
	return absi(k * 2654435761 + side * 40503 + layer * 1234567) % _textures.size()
