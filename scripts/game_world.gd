extends Node2D

const _BloodOrbScript = preload("res://scripts/blood_orb_system.gd")

# 화면/도로 공통 상수는 BillboardManager에 정의됨

# ── 노드 참조 ────────────────────────────────────────────────
var _road: Node2D
var _billboard_mgr: BillboardManager

var _trees   : Node2D

var _vehicle: LastRoadVehicle
var _hud     : CanvasLayer
var _rain_layer : CanvasLayer
var _rain    : Node2D
var _obstacles: LastRoadObstacles
var _blood_orbs: Node2D
var _scavenging: LastRoadScavenging
var _watchers : LastRoadWatchers
var _jiwons   : LastRoadJiwon
var _jumpers  : LastRoadJumpers
var _spear    : LastRoadSpear       # 창 던지기 (Doc 08)
var _movers   : LastRoadMovers      # 러너·워커 (Doc 19)
# ── 혼잣말 (Doc 26) ──
var _deer     : LastRoadDeer        # 사슴머리 (Doc 06/19, 스테이지 6)
var _cutscene : CutscenePlayer      # 런 클리어 컷신 (Doc 25)
var _deer_desat_pulse : float = 0.0 # 통과 순간 채도 급락 잔여
var _mono     : MonologueSystem = MonologueSystem.new()
var _mono_prev_radio_death : bool = false
var _mono_radio_death_time : float = 0.0
var _mono_fuel40_said : bool = false
var _mono_fuel15_said : bool = false
var _mono_monster_near : bool = false
var _mono_quiet_time : float = 0.0   # 마지막 '사건' 이후 경과 (죄책감 발화 조건)
var _loot_threat_timer : float = 0.0 # 수색 중 괴물 접근 들숨 간격
var _premonition_armed : bool = false # premonition 퍽 경고 1회성
var _camera   : Camera2D
var _inv_mgr  : InventoryManager
var _loot_ui  : LootUI
var _active_wreck_seed: int = -1
var _passenger_hallucination: PassengerHallucination

# ── 점퍼 보닛 탑승 상태 ──────────────────────────────────────
var _jumper_on_hood       : bool  = false
var _jumper_escape_gauge  : float = 0.0  # Doc 31 §4: 임계 속도 이상 유지 누적 시간(초)
# Doc 31 §4: 점퍼 탈출 = 속도 기반 (게이지 흔들기 폐지)
const JUMPER_KILL_THRESHOLD := 80.0   # 킬·탈출 임계 통일 (vehicle.get_kill_threshold로 하향)
const JUMPER_KILL_BO        := 8      # 즉시 처치 / 탈출 성공 시 BO
const JUMPER_ESCAPE_HOLD    := 0.5    # 임계 속도 이상 유지해야 탈출하는 시간(초)

# ── 전투: 속도 임계 처치 (Doc 31 §1) ──────────────────────────
# 적별 기본 임계 속도(km/h). 엔진 업그레이드로 하향됨(vehicle.get_kill_threshold).
const WATCHER_KILL_THRESHOLD := 80.0
const WATCHER_KILL_BO        := 3      # 관통 처치 시 획득 BO
const RUNNER_KILL_THRESHOLD  := 85.0   # Doc 31 적별 임계: 러너(이동 중) 85
const RUNNER_KILL_BO         := 5      # Doc 19
const WALKER_KILL_THRESHOLD  := 80.0
const WALKER_KILL_BO         := 6
const AMBUSHER_KILL_THRESHOLD := 90.0  # 갑자기 뛰쳐나오므로 더 높은 속도 필요
const AMBUSHER_KILL_BO        := 7
const CULT_KILL_THRESHOLD    := 75.0   # 저항력 낮은 인간형
const CULT_KILL_BO           := 10
const CULT_LEADER_KILL_THRESHOLD := 100.0  # 단일 최고 임계
const CULT_LEADER_KILL_BO    := 25
# 관통 처치(임계 이상): 내구도 소량 소모
const PIERCE_TIRE_DMG        := 1.5
const PIERCE_DRIVETRAIN_DMG  := 0.5
# 충격 튕김(임계 미만): 내구도 대량 소모
const BOUNCE_TIRE_DMG        := 6.0
const BOUNCE_DRIVETRAIN_DMG  := 2.0

# ── 전투: 처치 피드백 juice 상태 (Doc 31 §2) ──────────────────
var _hitstop_active : bool  = false
var _cam_shake_time : float = 0.0
var _cam_shake_dur  : float = 0.1
var _cam_shake_mag  : float = 0.0

# ── 전투: 숨겨진 콤보 (Doc 31 §3) ─────────────────────────────
# UI 없음. BO 배수 + 흡수음 pitch로만 체감. 연속 처치 간격이 윈도우 이내면 누적.
var _combo_count  : int   = 0      # 0=없음, 누적 처치 수
var _combo_timer  : float = 0.0    # 마지막 처치 이후 경과 시간(초)
var _combo_window : float = 4.0    # 콤보 유지 한계(초). §7 '검은 장갑' 부적이 늘릴 예정


var _prev_steering : float = 0.0

# ── 괴물 추격: 고무줄 모델 ────────────────────────────────────
# 거리를 크게 벌어두는 '은행' 구조 대신, 항상 백미러 사정권 안에서
# 정차하면 즉시 좁혀지고 밟으면 금방 다시 벌어지는 구조.
# 결정(정차·바위)의 대가가 수 분 뒤가 아니라 10초 안에 화면에 나타나야 한다.
# 세 값 모두 디버그 키(KP5~KP8)로 실시간 조정 가능 → 플레이테스트 후 const로 고정
var MONSTER_START_DIST : float = 100.0  # 스테이지 시작 시 거리 (세계 단위)
var MONSTER_MAX_DIST   : float = 150.0  # 거리 상한. 이 이상 벌어지지 않음 (은행 금지)
var MONSTER_GAIN_K     : float = 0.10   # 속도차(km/h) → 거리 변화 계수 (/초)
var _monster_distance: float = 100.0  # 현재 괴물 간격 (세계 단위)
var _sanity_ratio: float = 1.0        # 정신력 (1.0 = 정상, 0.0 = 패닉)
# ── 붕괴 상태 (Doc 04 §정신력 0) ──
# 0 도달 = 사망 아님. 2초 암전 → 라디오 죽음의 주파수 강제+잠금 → 조향 쏠림·가속 해제·최고속 80%·BO 차단.
# 담배로 >10% 넘기면 라디오 잠금 해제 + 7초 창. 창 안에 안전 주파수로 못 돌리면 재잠금. >30% 복귀 시 종료.
var _collapsed         : bool  = false
var _collapse_blackout : float = 0.0    # 암전 잔여 시간
var _collapse_knocks   : int   = 0      # 암전 중 트렁크 노크 재생 횟수
var _collapse_window   : float = 0.0    # 라디오 잠금 해제 후 탈출 창 잔여
var _collapse_rect     : ColorRect
const COLLAPSE_BLACKOUT_DUR := 2.0
const COLLAPSE_WINDOW_DUR   := 7.0
const COLLAPSE_UNLOCK_SANITY := 0.10
const COLLAPSE_EXIT_SANITY   := 0.30
var _weathered_pebble_timer: float = 0.0
var _cigarette_recovery_timer: float = 0.0
var _cigarette_recovery_amount: float = 0.0

# ── 스테이지 진행 시스템 ─────────────────────────────────────
# 스테이지 1~6 괴물 속도. 고무줄 모델(상한 150)에서는 거리를 은행처럼 못 쌓으므로
# 무업글 최고속(90)보다 10 이상 빠르면 풀스로틀로도 스테이지 안에 잡힌다 → 100을 천장으로.
# 엔진 업글(+15/Lv)이 여유를 만든다. (이전 70~120은 5스테이지 무업글 확정 사망)
const MONSTER_SPEEDS := [70.0, 76.0, 82.0, 88.0, 94.0, 100.0]
const STAGE_LENGTH  := 600.0    # 각 스테이지 목표 거리 (세계 단위, 밸런스 조정용)
const TOTAL_STAGES  := 6

var current_stage     : int   = 1
var stage_start_z     : float = 0.0     # 스테이지 시작 시점의 scroll_z

# 게임 상태: "splash", "main_menu", "playing", "stage_clear", "stage_exit", "game_over", "maintenance"
var _game_state       : String = "main_menu"
var _state_timer      : float = 0.0
const STAGE_CLEAR_DURATION := 3.0
const GAMEOVER_FADE_DURATION := 1.5
const RETURN_TO_MENU_DELAY := 4.0   # 게임오버/클리어 후 메뉴 복귀까지 대기 시간
const LOOP_ENDING_DURATION := 12.0  # 일반 종료 연출 길이 (Doc 11 엔딩 분기 — 루프 암시)
# 일반 종료 연출 대본: [시각(초), 문구]. 진엔딩 퍽 해금 전에는 이것뿐이다
const LOOP_ENDING_SCRIPT := [
	[1.5, "...도착했다."],
	[4.5, "...아니."],
	[7.0, "...길이 계속된다."],
	[9.5, "...또 시작이네."],
]
var _loop_ending_idx: int = 0

# ── 메인 메뉴 ──
var _menu_layer : CanvasLayer
var _menu_container : Control

# ── 스플래시 화면 ──
var _splash_layer : CanvasLayer
var _splash_tween : Tween
var _current_splash_index : int = 0
var _godot_container : Control = null
var _tpc_container : Control = null

# ── 메타 진행 / 강화 ──
var _pp_mat : ShaderMaterial
var _meta : MetaProgression
var _upgrades : VehicleUpgradeSystem
var _skill_tree_ui : Node  # SkillTreeUI
var _stages_cleared_this_run : int = 0

# ── 스테이지 클리어 → 상점 전환 연출 ──
const EXIT_DRIVE_DURATION := 3.0  # 차가 도로를 따라 멀어지는 시간
const EXIT_FADE_DURATION  := 1.2  # 페이드 아웃 시간
var _exit_fade_rect: ColorRect
var _exit_car_tex: Texture2D
var _exit_car_left_tex: Texture2D
var _exit_car_right_tex: Texture2D
var _exit_car_active_tex: Texture2D   # 현재 프레임에 실제 렌더되는 텍스처
var _exit_car_dz: float = 2.0     # 카메라로부터의 거리 (세계 단위, 점점 증가)
var _exit_cam_tilt: float = 0.0   # 카메라 틸트 (하늘을 올려다보는 효과, 픽셀 단위)

# ── 배경 무한 스크롤 (코너에서만 누적) ────────────────────────

var _sky_scroll    := 0.0
var _mtn_scroll    := 0.0
var _forest_scroll := 0.0
const CORNER_BG_K_THRESH  := 0.0035
const BG_MTN_SPEED        := 0.38
const BG_SKY_VS_MTN       := 0.32
const BG_FOREST_VS_MTN    := 1.85  # 숲은 산보다 가까우므로 더 빠르게
const MTN_Y_OFFSET        := 22.0

# ── 언덕 시 배경 세로 패럴랙스 ──────────────────────────────────
# 거리 순서: 하늘(멀) < 산(중원) < 숲(중경) — 가까울수록 지평선을 더 많이 따라감
const MTN_H_PX            := 130.0
const FOREST_H_PX         := 90.0   # 화면에서 숲이 차지할 높이(px)
const FOREST_Y_OFFSET     := 16.0   # 지평선 위 약간 겹쳐 틈 방지
const SKY_HILL_FACTOR     := 0.08    # 원경은 거의 고정
const MTN_HILL_FACTOR     := 0.35
const FOREST_HILL_FACTOR  := 0.85    # 중경은 지평선 이동을 더 민첩하게 따라감
const BG_Y_SMOOTH_SPEED   := 15.0    # 지연(Lag)을 줄이기 위해 속도 상향
const SKY_EXTRA_PX        := 80.0

const _RoadScript    = preload("res://scripts/road_renderer.gd")
const _TreeScript    = preload("res://scripts/tree_renderer.gd")
const _VehicleScript = preload("res://scripts/vehicle.gd")
const _HudScript     = preload("res://scripts/hud.gd")
const _ObstacleScript = preload("res://scripts/obstacle_system.gd")
const _RainScript    = preload("res://scripts/rain_renderer.gd")
const _WatcherScript = preload("res://scripts/watcher_system.gd")
const _JiwonScript   = preload("res://scripts/jiwon_system.gd")
const _ScavengingScript = preload("res://scripts/scavenging_system.gd")
const _JumperScript  = preload("res://scripts/jumper_system.gd")
const _SpearScript   = preload("res://scripts/spear_system.gd")
const _MoverScript   = preload("res://scripts/mover_system.gd")
const _DeerScript    = preload("res://scripts/deer_system.gd")
const _CutsceneScript = preload("res://scripts/cutscene_player.gd")
const _InvMgrScript  = preload("res://scripts/inventory_manager.gd")
const _LootUIScript  = preload("res://scripts/loot_ui.gd")
const _ShopUIScript  = preload("res://scripts/shop_ui.gd")
const _MetaScript    = preload("res://scripts/meta_progression.gd")
const _BillboardMgrScript = preload("res://scripts/billboard_manager.gd")
const _SkillTreeScript = preload("res://scripts/skill_tree_ui.gd")
const _CharmSystemScript = preload("res://scripts/charm_system.gd")
const _HallucinationScript = preload("res://scripts/hallucination_video.gd")

var _shop_ui: Node
var _charm_sys: Node
var _hallucination: HallucinationVideo
var _mtn_base_y    : float = 0.0
var _sky_base_y    : float = 0.0
var _forest_base_y : float = 0.0
var _mtn_y         : float = 0.0
var _sky_y         : float = 0.0
var _forest_y      : float = 0.0

var _debug_stop_monster: bool = false



# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	# 카메라 이동 시 화면 밖(회색) 영역이 보이지 않도록 거대한 검은색 배경을 먼저 깔아줍니다.
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(6000, 6000)
	bg.z_index = -200
	add_child(bg)
	
	_road = _RoadScript.new(); add_child(_road)
	
	# ── 매니저/시스템 초기화 ──
	_billboard_mgr = BillboardManager.new()
	add_child(_billboard_mgr)
	
	# 로딩 UI 먼저 생성
	_build_loading_screen()

	_scavenging = _ScavengingScript.new()
	_scavenging.billboard_mgr = _billboard_mgr
	add_child(_scavenging)

	_trees   = _TreeScript.new();
	_trees.scavenging_sys = _scavenging
	_trees.billboard_mgr = _billboard_mgr
	add_child(_trees)

	_watchers = _WatcherScript.new()
	_watchers.billboard_mgr = _billboard_mgr
	add_child(_watchers)

	_jiwons = _JiwonScript.new()
	_jiwons.billboard_mgr = _billboard_mgr
	add_child(_jiwons)

	_jumpers  = _JumperScript.new()
	_jumpers.jumper_boarded.connect(_on_jumper_boarded)
	_jumpers.billboard_mgr = _billboard_mgr
	add_child(_jumpers)

	# ── 창 던지기 (Doc 08) — 빌보드 위에 전방 비행을 그리므로 빌보드 다음에 add ──
	_spear = _SpearScript.new()
	_spear.spear_hit.connect(_on_spear_hit)
	_spear.spear_missed.connect(_on_spear_missed)
	_spear.spear_warning.connect(_on_spear_warning)
	add_child(_spear)

	_movers = _MoverScript.new()
	_movers.billboard_mgr = _billboard_mgr
	add_child(_movers)

	_deer = _DeerScript.new()
	_deer.billboard_mgr = _billboard_mgr
	_deer.deer_passed.connect(_on_deer_passed)
	add_child(_deer)

	_cutscene = _CutsceneScript.new()
	_cutscene.finished.connect(_on_cutscene_finished)
	add_child(_cutscene)

	_build_collapse_overlay()

	_obstacles = _ObstacleScript.new()
	_obstacles.billboard_mgr = _billboard_mgr
	add_child(_obstacles)

	_blood_orbs = _BloodOrbScript.new()
	_blood_orbs.billboard_mgr = _billboard_mgr
	add_child(_blood_orbs)

	# ── 조수석 환영 시스템 ──
	_passenger_hallucination = PassengerHallucination.new()
	add_child(_passenger_hallucination)

	_vehicle = _VehicleScript.new(); add_child(_vehicle)
	_vehicle.fuel_depleted.connect(func(): _hud.on_fuel_depleted())
	# rain은 화면 고정이어야 하므로 CanvasLayer에 올려 카메라 줌/패럴랙스 영향 차단
	_rain_layer = CanvasLayer.new()
	_rain_layer.layer = 1               # hud와 같은 레이어지만 트리 상 먼저라 아래 렌더
	add_child(_rain_layer)
	_rain = _RainScript.new()
	_rain_layer.add_child(_rain)
	_hud  = _HudScript.new();       add_child(_hud)
	_hud.loot_prompt_clicked.connect(_on_loot_prompt_clicked)
	_apply_monster_max_dist()  # 백미러 괴물 스케일을 거리 상한과 동기화

	# ── 인벤토리 / 루팅 UI ──
	# ── 메타 진행 / 강화 (가장 먼저!) ──
	_meta = _MetaScript.new()
	add_child(_meta)
	
	_charm_sys = _CharmSystemScript.new()
	add_child(_charm_sys)
	# 부적이 바뀌면 차량 모디파이어 재계산
	_charm_sys.charms_updated.connect(_on_charms_updated)
	_vehicle.part_damaged.connect(_on_part_damaged)

	_inv_mgr = _InvMgrScript.new()
	_inv_mgr.apply_meta(_meta)
	_inv_mgr.vehicle = _vehicle
	_inv_mgr.charm_sys = _charm_sys
	add_child(_inv_mgr)
	
	_loot_ui = _LootUIScript.new()
	_loot_ui.inv = _inv_mgr
	_loot_ui.meta = _meta
	_loot_ui.vehicle = _vehicle
	_loot_ui.charm_sys = _charm_sys
	add_child(_loot_ui)
	_loot_ui.loot_ui_closed.connect(func(): _hud.hide_loot_prompt())
	_loot_ui.item_used.connect(_on_item_used)
	_hud.loot_ui = _loot_ui
	_hud.meta = _meta
	
	_hud.charm_sys = _charm_sys
	_hud.init_charm_sys()
	
	_upgrades = VehicleUpgradeSystem.new()
	add_child(_upgrades)
	
	_sanity_ratio = 1.0   # (구 strong_heart 퍽은 스킬트리에 없어 제거)
	_skill_tree_ui = _SkillTreeScript.new()
	_skill_tree_ui.meta = _meta
	_skill_tree_ui.closed.connect(_on_skill_tree_closed)
	add_child(_skill_tree_ui)

	# ── 정비소 UI ──
	_shop_ui = _ShopUIScript.new()
	_shop_ui.inv = _inv_mgr
	_shop_ui.meta = _meta
	_shop_ui.vehicle = _vehicle
	_shop_ui.charm_sys = _charm_sys
	_shop_ui.depart_requested.connect(_on_shop_depart_requested)
	add_child(_shop_ui)
	_hud.shop_ui = _shop_ui

	# ── 환각 영상 시스템 ──
	_hallucination = _HallucinationScript.new()
	add_child(_hallucination)

	_camera = Camera2D.new()
	_camera.position = Vector2(640.0, 360.0)
	add_child(_camera)

	_hud.follow_viewport_enabled = true

	# ── 포스트 프로세스 (색수차 등) ──
	var pp_layer := CanvasLayer.new()
	pp_layer.layer = 15 # HUD(10)보다 높고 메인메뉴(20)보다 낮은 위치
	add_child(pp_layer)
	var pp_backbuffer := BackBufferCopy.new()
	pp_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	pp_layer.add_child(pp_backbuffer)

	var pp_rect := ColorRect.new()
	pp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	pp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pp_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_pp_mat = ShaderMaterial.new()
	_pp_mat.shader = load("res://scripts/chromatic_aberration.gdshader")
	_pp_mat.set_shader_parameter("offset", 0.0) # 기본 정신력 100% 땐 0.0으로 완전 깨끗하게 시작!
	pp_rect.material = _pp_mat
	pp_layer.add_child(pp_rect)


	# ── 블룸(Glow) 효과 (비활성화) ──────────────────────────────────────
	# WorldEnvironment + BG_CANVAS + glow는 Mobile 렌더러와 호환성 문제가 있다.
	# headlight 셰이더가 intensity 1.3 × flicker(최대 2.0)로 픽셀 밝기를 1.0 위로
	# 끌어올리면 glow_hdr_threshold(0.8)를 초과한 픽셀이 글로우 버퍼로만 흡수되고
	# 최종 캔버스 합성에서 누락되는 현상이 보고됨 (스테이지 3+에서 헤드라이트로
	# 밝게 비춰진 적/장애물이 시야 안에서 사라지지만 충돌은 정상 동작).
	# 블룸이 필요하면 CanvasLayer 위에 후처리 셰이더로 별도 구현할 것.

	# 스테이지 1 초기 배치도 매 플레이마다 다르게 (로딩 시점에 처리하도록 제거)
	# _apply_route_modifiers("normal")

	# ── 메인 메뉴 ──
	_build_main_menu()
	if _menu_container != null:
		_menu_container.visible = false
	_start_splash_sequence()

var _sky_sprite    : Sprite2D
var _mtn_sprite    : Sprite2D
var _forest_sprite : Sprite2D
var _sky_sc_x    : float = 1.0
var _mtn_sc_x    : float = 1.0
var _forest_sc_x : float = 1.0

# ── 하늘 (무한 가로 스크롤) ────────────────────────────
func _build_sky_tiled() -> void:
	var tex := load("res://Asset/Image/sky.png") as Texture2D
	if tex == null:
		return
	# 하늘을 BillboardManager.HORIZON_Y + SKY_EXTRA_PX 높이로 스케일 — 언덕 이동 시 상하 여유분 확보
	var target_sc_y := float(BillboardManager.HORIZON_Y + SKY_EXTRA_PX) / float(tex.get_height())
	var sc := Vector2(target_sc_y, target_sc_y)

	_sky_sc_x = sc.x
	_sky_sprite = Sprite2D.new()
	_sky_sprite.texture = tex
	_sky_sprite.centered = false
	_sky_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sky_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sky_sprite.region_enabled = true
	_sky_sprite.region_rect = Rect2(0.0, 1.0, BillboardManager.SCREEN_W / sc.x, float(tex.get_height()) - 2.0)
	_sky_sprite.scale = sc
	# 여유분 절반을 위로 올려서 상하 동등하게 여백 확보
	var base_y := -SKY_EXTRA_PX * 0.5
	_sky_sprite.position = Vector2(0.0, base_y)
	_sky_sprite.z_index = -100 # 가장 뒤에 렌더링
	add_child(_sky_sprite)
	_sky_base_y = base_y
	_sky_y = _sky_base_y

# ── 산 실루엣 (무한 가로 스크롤) ───────────────────────
func _build_mountain_tiled() -> void:
	var tex := load("res://Asset/Image/mountain.png") as Texture2D
	if tex == null:
		return
	var mtn_h := MTN_H_PX
	var sc := Vector2(
		float(BillboardManager.SCREEN_W) / float(tex.get_width()),
		mtn_h / float(tex.get_height())
	)
	_mtn_sc_x = sc.x
	var y0 := float(BillboardManager.HORIZON_Y) - mtn_h + MTN_Y_OFFSET
	_mtn_base_y = y0
	_mtn_y = _mtn_base_y
	
	_mtn_sprite = Sprite2D.new()
	_mtn_sprite.texture = tex
	_mtn_sprite.centered = false
	_mtn_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mtn_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_mtn_sprite.region_enabled = true
	# Y축은 1픽셀씩 여백을 줘서 상하 반복 블리딩 방지
	_mtn_sprite.region_rect = Rect2(0.0, 1.0, BillboardManager.SCREEN_W / sc.x, float(tex.get_height()) - 2.0)
	_mtn_sprite.scale = sc
	_mtn_sprite.position = Vector2(0.0, y0)
	_mtn_sprite.z_index = -90 # 하늘 위, 숲 뒤
	add_child(_mtn_sprite)

func _build_forest_tiled() -> void:
	var tex := load("res://Asset/Image/forest.png") as Texture2D
	if tex == null:
		return
	var sc := Vector2(
		float(BillboardManager.SCREEN_W) / float(tex.get_width()),
		FOREST_H_PX / float(tex.get_height())
	)
	_forest_sc_x = sc.x
	# 숲 하단을 지평선에 맞춤 (FOREST_Y_OFFSET 만큼 내려서 틈 방지)
	var y0 := float(BillboardManager.HORIZON_Y) - FOREST_H_PX + FOREST_Y_OFFSET
	_forest_base_y = y0
	_forest_y = y0

	_forest_sprite = Sprite2D.new()
	_forest_sprite.texture = tex
	_forest_sprite.centered = false
	_forest_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_forest_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_forest_sprite.region_enabled = true
	_forest_sprite.region_rect = Rect2(0.0, 1.0, BillboardManager.SCREEN_W / sc.x, float(tex.get_height()) - 2.0)
	_forest_sprite.scale = sc
	_forest_sprite.position = Vector2(0.0, y0)
	_forest_sprite.z_index = -80 # 산 위, 도로 뒤
	add_child(_forest_sprite)

func _apply_bg_scroll() -> void:
	if _sky_sprite != null:
		var rect = _sky_sprite.region_rect
		rect.position.x = _sky_scroll / _sky_sc_x
		_sky_sprite.region_rect = rect
	if _mtn_sprite != null:
		var rect = _mtn_sprite.region_rect
		rect.position.x = _mtn_scroll / _mtn_sc_x
		_mtn_sprite.region_rect = rect
	if _forest_sprite != null:
		var rect = _forest_sprite.region_rect
		rect.position.x = _forest_scroll / _forest_sc_x
		_forest_sprite.region_rect = rect

# ─────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _game_state == "main_menu" or _game_state == "splash":
		return

	if _game_state == "game_over":
		_state_timer += delta
		var fade := clampf(_state_timer / GAMEOVER_FADE_DURATION, 0.0, 1.0)
		_hud.set_gameover_fade(fade)
		# 카메라 줌 리셋 (룸미러 보는 중 게임오버 시 대응)
		_hud._focus_t = maxf(_hud._focus_t - delta * 5.0, 0.0)
		var ease_go := smoothstep(0.0, 1.0, _hud._focus_t)
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.2, 2.2), ease_go)
		_camera.position = Vector2(640.0, 360.0).lerp(Vector2(665.0, 120.0), ease_go)
		if _state_timer >= RETURN_TO_MENU_DELAY:
			_show_main_menu()
		return

	if _game_state == "stage_clear":
		# 6스테이지 클리어 = 일반 종료 (Doc 11: 진엔딩 퍽 전에는 루프 지속을 암시하는 페이드아웃)
		_state_timer += delta
		_update_loop_ending(delta)
		if _state_timer >= LOOP_ENDING_DURATION:
			_start_run_cutscene()
		return

	if _game_state == "cutscene":
		return   # cutscene_player가 finished를 보내면 메뉴로
	
	if _game_state == "stage_exit":
		_state_timer += delta
		_update_stage_exit(delta)
		return

	if _game_state == "maintenance":
		return

	# ── playing 상태 ──
	# 도망자 충돌 화면 컷 (0.2초)
	if _screen_cut_timer > 0.0:
		_screen_cut_timer -= delta
		if _screen_cut_timer <= 0.0 and not _collapsed:
			_collapse_rect.visible = false
	if _collapse_blackout > 0.0:
		_update_collapse_blackout(delta)   # 암전 중: 조작 불가, 차는 관성으로 감속
	else:
		_vehicle.handle_input(delta)

	# 차량 이동 시 폐차 루팅 UI 강제 종료 (내 인벤토리는 유지)
	if _vehicle.speed > 0.5 and _loot_ui != null and _loot_ui.is_open() and not _loot_ui._is_trunk_only:
		_loot_ui.close()
		_active_wreck_seed = -1
	_vehicle.update_scroll(delta)
	_vehicle.update_fuel(delta)
	_vehicle.update_buffs(delta)
	_vehicle.update_rpm(delta)
	var curve_x := _vehicle.compute_strip_curve_offsets()
	var hill_px := _vehicle.hill_offset_px()
	
	# 풍화된 조약돌 부적: 괴물 접근 속도 감소
	if _weathered_pebble_timer > 0.0:
		_weathered_pebble_timer -= delta
		
	# 괴물 간격 업데이트
	if not _debug_stop_monster:
		var monster_speed := float(MONSTER_SPEEDS[clampi(current_stage - 1, 0, TOTAL_STAGES - 1)])
		if _weathered_pebble_timer > 0.0:
			monster_speed *= 0.7 # 30% 느려짐
		# safe_drive_amulet: 5개 부품 모두 100% 유지 시 괴물 접근 -20%
		if _charm_sys.has_charm("safe_drive_amulet") and _all_parts_full():
			monster_speed *= 0.8

		var speed_diff := _vehicle.speed - monster_speed
		_monster_distance += speed_diff * MONSTER_GAIN_K * delta
		# freakish_antenna: 죽음의 주파수를 끄지 않으면 괴물과 거리 점진 증가
		if _charm_sys.has_charm("freakish_antenna") and _hud.get_radio_on_death():
			_monster_distance += 2.0 * delta
		_monster_distance = clampf(_monster_distance, 0.0, MONSTER_MAX_DIST)

	# ── 게임오버 체크: 괴물에게 따라잡힘 ──
	if _monster_distance <= 0.0 and _try_death_save():
		pass   # 부적이 한 번 살렸다
	elif _monster_distance <= 0.0:
		_game_state = "game_over"
		_state_timer = 0.0
		_hud.show_gameover()
		_hud.set_mirror_alert(false)
		# legacy 퍽: 사망 시 소지 자금 30%를 다음 런으로
		if _meta.has_perk("legacy"):
			_meta.carry_money = int(_inv_mgr.money * 0.3)
			_meta.save_data()
		_hud.stop_engine_sound()
		if _collapse_rect != null:
			_collapse_rect.visible = false
		if _hallucination: _hallucination.force_stop()
		return
	
	# ── 스테이지 클리어 체크 ──
	var stage_distance := _vehicle.scroll_z - stage_start_z
	if stage_distance >= STAGE_LENGTH:
		# UI 정리 — 인벤토리/루팅 닫기, 룸미러·라디오·계기판 포커스 해제
		if _loot_ui != null and _loot_ui.is_open():
			_loot_ui.close()
			_active_wreck_seed = -1
		_hud.hide_loot_prompt()
		_hud.reset_focus_states()
		if _jumper_on_hood:
			_jumper_on_hood = false
			_jumper_escape_gauge = 0.0
			_hud.set_jumper_on_hood(false, false)
		_stages_cleared_this_run += 1
		
		# 클리어 연출 시작 시 정신력 시각 효과 제거
		_clear_sanity_effects()
		_say("maintenance")

		if current_stage >= TOTAL_STAGES:
			# 최종 스테이지 클리어 = 일반 종료 연출 (진엔딩은 Doc 22, 미구현)
			_game_state = "stage_clear"
			_state_timer = 0.0
			_loop_ending_idx = 0
			_vehicle.speed = 0.0
			_hud.stop_engine_sound()
			_hud.set_mirror_alert(false)
			_hud.show_stage_clear(current_stage, true)
			_hud.set_gameover_fade(0.0)
		else:
			_advance_to_next_stage()
		return
	
	# 정신력 업데이트 (괴물이 40 단위 이내로 다가오면 공포감으로 감소)
	# GDD: 자동 회복 없음. 담배와 정비 구간에서만 회복
	if _monster_distance < 40.0:
		var drain_spd := (40.0 - _monster_distance) * 0.0025
		_sanity_ratio -= drain_spd * delta

	# ── 부적 지속 효과 (Doc 28) ──
	_update_charm_passives(delta)
	# ── 혼잣말 상황 감지 (Doc 26) ──
	_update_monologue(delta)
	# ── 수색 중 괴물 접근 청각 단서 ──
	# 루팅 UI(레이어 12)가 미러·비네트를 가리므로, 정차 수색 중엔 소리로만 접근을 알 수 있어야 한다.
	# 거리 비율 50% 아래부터 들숨이 들리고, 가까울수록 잦고 높아진다.
	if _loot_ui != null and _loot_ui.is_open():
		var ratio := _monster_distance / maxf(MONSTER_MAX_DIST, 1.0)
		if ratio < 0.5:
			_loot_threat_timer -= delta
			if _loot_threat_timer <= 0.0:
				var t := 1.0 - ratio / 0.5   # 0(멀다) ~ 1(코앞)
				_hud.play_sfx("breath", lerpf(0.7, 1.4, t))
				_loot_threat_timer = lerpf(4.0, 1.2, t)
	else:
		_loot_threat_timer = 0.0
	
	# 라디오 죽음의 주파수: 정신력 -2/초 (GDD 18-radio.md)
	if _hud.get_radio_on_death():
		_sanity_ratio -= 0.02 * delta  # 2% per second

	# ── 구동계 고장 진동 ──
	if _vehicle.dur_drivetrain <= 0.0 and _vehicle.speed > 5.0:
		if randf() < 2.0 * delta: # 초당 약 2회 정도 랜덤하게 덜컹거림
			BillboardManager.add_impact_shake(0.15)
	
	
	# 담배 점진적 정신력 회복 (4.5초에 걸쳐 회복)
	if _cigarette_recovery_timer > 0.0:
		var dt := minf(delta, _cigarette_recovery_timer)
		_cigarette_recovery_timer -= dt
		var recovery_step := (_cigarette_recovery_amount / 4.5) * dt
		_sanity_ratio += recovery_step

	_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	_update_collapse(delta)

	# ── 환각 영상 업데이트 (정신력 0일 때 주기적 재생) ──
	if _hallucination:
		_hallucination.update_sanity(_sanity_ratio, delta)
	if _passenger_hallucination != null:
		_passenger_hallucination.update_sanity(_sanity_ratio, delta)
	
	_update_backdrops(delta)
	_update_backdrops_vertical(delta, hill_px)
	
	var min_tire := minf(minf(_vehicle.dur_lf_tire, _vehicle.dur_rf_tire), minf(_vehicle.dur_lb_tire, _vehicle.dur_rb_tire))
	# ── 정신력 기반 HUD 노이즈 (계기판 떨림) ──
	var hud_rpm := _vehicle.rpm
	var hud_spd := _vehicle.speed
	if _sanity_ratio < 0.3:
		# 정신력 30% 이하부터 바늘이 무작위로 튐
		var twitch_mag := (0.3 - _sanity_ratio) * 150.0
		if randf() < 0.08:
			hud_rpm += randf_range(-twitch_mag, twitch_mag) * 5.0
			hud_spd += randf_range(-twitch_mag, twitch_mag) * 0.2
			
	var curr_bo: int = _blood_orbs.run_total_bo if _blood_orbs != null else 0
	var curr_money: int = _inv_mgr.money if _inv_mgr != null else 0
	_hud.update(hud_spd, _vehicle.scroll_z, _vehicle.steering_angle, hud_rpm, _monster_distance, delta, _vehicle.fuel_ratio, _sanity_ratio, current_stage, stage_distance, STAGE_LENGTH, _vehicle.dur_drivetrain, min_tire, curr_bo, curr_money)
	_rain.vehicle_speed = _vehicle.speed
	
	# 카메라 줌 업데이트 (전체 화면 줌)
	var screen_center := Vector2(640.0, 360.0)
	
	if _hud._radio_focus_t > 0.0:
		var radio_ease_t := smoothstep(0.0, 1.0, _hud._radio_focus_t)
		# 라디오 위치 주변으로 줌. 라디오 패널 중앙 정도
		var target_camera_pos: Vector2 = _hud.RADIO_PANEL_POS + Vector2(100.0, 36.0)
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.5, 2.5), radio_ease_t)
		_camera.position = screen_center.lerp(target_camera_pos, radio_ease_t)
	elif _hud._dash_focus_t > 0.0:
		var dash_ease_t := smoothstep(0.0, 1.0, _hud._dash_focus_t)
		var target_camera_pos := Vector2(300.0, 570.0)
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.4, 2.4), dash_ease_t)
		_camera.position = screen_center.lerp(target_camera_pos, dash_ease_t)
	else:
		var ease_t := smoothstep(0.0, 1.0, _hud._focus_t)
		var target_camera_pos := Vector2(665.0, 120.0)
		_camera.zoom = Vector2(1.0, 1.0).lerp(Vector2(2.2, 2.2), ease_t)
		_camera.position = screen_center.lerp(target_camera_pos, ease_t)

	# ── 처치 카메라 셰이크 (Doc 31 §2) ──
	if _cam_shake_time > 0.0:
		_cam_shake_time = maxf(_cam_shake_time - delta, 0.0)
		var s := _cam_shake_mag * (_cam_shake_time / maxf(_cam_shake_dur, 0.001))
		_camera.position += Vector2(randf_range(-s, s), randf_range(-s, s))


	_rain.set_wiper_transforms(
		_hud._wiper_pivot_L.global_position, _hud._wiper_pivot_L.global_rotation,
		_hud._wiper_pivot_R.global_position, _hud._wiper_pivot_R.global_rotation
	)
	
	# ── 번개 연출 (비오는 스테이지 전용) ──
	if _rain.is_raining and _game_state == "playing":
		if randf() < 0.003: # 가끔 번개
			BillboardManager.lightning_intensity = 1.2 + randf() * 0.6
		elif BillboardManager.lightning_intensity > 1.0 and randf() < 0.2: # 잔광/두번 번개
			BillboardManager.lightning_intensity = 1.0

	# 유리 셰이더에 카메라 파라미터 전달
	if _rain._shader_mat:
		_rain._shader_mat.set_shader_parameter("cam_center_uv", _camera.position / Vector2(BillboardManager.SCREEN_W, BillboardManager.SCREEN_H))
		_rain._shader_mat.set_shader_parameter("cam_zoom", _camera.zoom.x)
	# ── 정신력 기반 왜곡 및 무채색화 ──
	var threshold_p := 0.30 if _meta.has_perk("reality_sense") else 0.40
	var dist_strength_p := 0.0
	if _sanity_ratio < threshold_p:
		dist_strength_p = (threshold_p - _sanity_ratio) / threshold_p
		if _meta.has_perk("last_resort"):
			dist_strength_p *= 0.70

	# ── 정신력 기반 무채색화 (Desaturation) ──
	var desat_val := 0.0
	var s_pct := _sanity_ratio * 100.0
	if s_pct >= 70.0:
		desat_val = 0.0
	elif s_pct >= 50.0:
		var t := (70.0 - s_pct) / 20.0
		desat_val = lerpf(0.0, 0.3, t)
	elif s_pct >= 30.0:
		var t := (50.0 - s_pct) / 20.0
		desat_val = lerpf(0.3, 0.6, t)
	elif s_pct >= 10.0:
		var t := (30.0 - s_pct) / 20.0
		desat_val = lerpf(0.6, 0.85, t)
	else:
		var t := (10.0 - s_pct) / 10.0
		desat_val = lerpf(0.85, 0.95, t)

	# 사슴머리 통과: 채도 급락 후 서서히 회복 (속도가 낮을수록 깊게)
	if _deer_desat_pulse > 0.0:
		_deer_desat_pulse = maxf(_deer_desat_pulse - delta * 0.35, 0.0)
		desat_val = maxf(desat_val, _deer_desat_pulse)

	if _pp_mat != null:
		var max_dist_offset := 12.0
		var cur_offset := dist_strength_p * max_dist_offset
		_pp_mat.set_shader_parameter("offset", cur_offset)
		_pp_mat.set_shader_parameter("desaturation", desat_val)
		_pp_mat.set_shader_parameter("time_phase", Time.get_ticks_msec() * 0.001)

	_road.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_billboard_mgr.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	
	_scavenging.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_trees.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_obstacles.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_watchers._current_sanity_ratio = _sanity_ratio
	_watchers.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range, _sanity_ratio)
	_jiwons.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_jumpers.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_movers.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range)
	_deer.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range, _vehicle.speed, delta)

	# ── 창 던지기 (Doc 08) — Doc 30 §4 상호 잠금: 점퍼 탑승·인벤토리·라디오 줌 중엔 신규 발동 보류 ──
	var spear_blocked := _jumper_on_hood \
		or (_loot_ui != null and _loot_ui.is_open()) \
		or _hud.is_radio_zoomed() \
		or PressureDirector.in_breath(_vehicle.scroll_z) \
		or PressureDirector.near_stage_end(_vehicle.scroll_z) \
		or _collapse_blackout > 0.0 \
		or _deer.is_near() or _deer.recent_pass_timer > 0.0   # Doc 30 §4: 사슴머리 통과 전후 창 보류
	_spear.update_state(delta, current_stage, _monster_distance, MONSTER_MAX_DIST, _vehicle, curve_x, hill_px, spear_blocked)
	var spear_mirror := _spear.get_mirror_state()
	if _hud._rearview_node != null:
		_hud._rearview_node.spear_state = spear_mirror
	_hud.set_mirror_alert(bool(spear_mirror["alert"]))

	_blood_orbs.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px, _vehicle.headlight_range, delta)
	
	_billboard_mgr.render_all()

	var bo_pickup: int = _blood_orbs.check_collection(_vehicle)
	if bo_pickup > 0:
		print("[BO] +%d (total %d)" % [bo_pickup, _blood_orbs.run_total_bo])

	if _obstacles.check_collision(_vehicle):
		BillboardManager.add_impact_shake(0.6)
		var obs_tire_dmg := 5.0
		if _charm_sys.has_charm("weathered_pebble"):
			_weathered_pebble_timer = 5.0
			obs_tire_dmg *= 0.5   # 타이어 손상 -50%
		# crash_test_dummy: 스테이지당 1~2회 장애물 내구도 손실 무효
		if _charm_sys.dummy_charges > 0:
			_charm_sys.dummy_charges -= 1
			_hud.show_message("더미 인형이 충격을 받아냈다.")
		else:
			# GDD §4.5: 포트홀/낙석 — 현재 차선 기준 전륜 -5%, 구동계 -1.5%
			var obs_contact := _get_contact_side()
			_vehicle.apply_part_damage(obs_contact, obs_tire_dmg, 1.5)
		_hud.on_rock_hit()
	# Doc 31 §6: 범퍼 Lv3 관통 — 한 프레임에 최대 N명 처치
	var wat_hits := _watchers.check_collision(_vehicle, _vehicle.get_penetration_count())
	for wh in wat_hits:
		if bool(wh["is_hallucination"]):
			# 환영 충돌: 글리치 효과 + 정신력 큰 감소 (-8%), 물리 피해 없음
			if _hallucination: _hallucination.trigger_glitch(0.25)
			_sanity_ratio -= 0.08
			_hud.play_sfx("warning") # 환영은 기분 나쁜 소리
			_on_hallucination_collision()
		else:
			# 실체 충돌: 속도 임계 처치 판정 (Doc 31 §1)
			_resolve_speed_kill(WATCHER_KILL_THRESHOLD, WATCHER_KILL_BO)
		_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	# 러너·워커 (Doc 19) — 와쳐와 같은 속도 임계 처치 규칙, 적별 임계·BO만 다름
	var mov_hits := _movers.check_collision(_vehicle, _vehicle.get_penetration_count())
	for mh in mov_hits:
		match int(mh["type"]):
			LastRoadMovers.MoverType.WALKER:
				_resolve_speed_kill(WALKER_KILL_THRESHOLD, WALKER_KILL_BO)
			LastRoadMovers.MoverType.AMBUSHER:
				_resolve_speed_kill(AMBUSHER_KILL_THRESHOLD, AMBUSHER_KILL_BO)
				_sanity_ratio -= 0.08   # Doc 19: 앰부서 -8
			LastRoadMovers.MoverType.CULT:
				# Doc 19 행렬 컬트: 인간형 충돌 정신력 비용은 처치 여부와 무관
				if bool(mh.get("leader", false)):
					_resolve_speed_kill(CULT_LEADER_KILL_THRESHOLD, CULT_LEADER_KILL_BO)
					_sanity_ratio -= 0.25
				else:
					_resolve_speed_kill(CULT_KILL_THRESHOLD, CULT_KILL_BO)
					_sanity_ratio -= 0.15
			LastRoadMovers.MoverType.FLEEING:
				_on_fleeing_hit()   # 처치/튕김 없음. 화면 컷 + 소지품만
			_:
				_resolve_speed_kill(RUNNER_KILL_THRESHOLD, RUNNER_KILL_BO)
		_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	if _movers.consume_fleeing_passed():
		_say("fleeing_pass")
	var roadside_cost := _movers.consume_roadside_cost()
	if roadside_cost > 0.0:
		_sanity_ratio = clampf(_sanity_ratio - roadside_cost, 0.0, 1.0)   # 갓길 컬트 목격 -5/-10
		_say("roadside_cult")
	if _movers.consume_cult_passed():
		_sanity_ratio = clampf(_sanity_ratio - 0.02, 0.0, 1.0)   # 행렬 회피: 시선 비용 -2
	if _movers.consume_ambush():
		_say("ambusher")
		_hud.play_sfx("warning", 1.2)
	if _jiwons.check_collision(_vehicle):
		var is_hal := false
		for k in _jiwons._hit_info.keys():
			if _jiwons.is_hit_hallucination(k):
				is_hal = true
				break
				
		if is_hal:
			if _hallucination: _hallucination.trigger_glitch(0.35) # 지원은 더 강한 글리치
			_sanity_ratio -= 0.12 # 지원 환영은 더 큰 충격
			_hud.play_sfx("warning")
			_on_hallucination_collision()
		else:
			var jiw_contact := _get_contact_side()
			_vehicle.apply_part_damage(jiw_contact, 12.0, 4.0)
			if _charm_sys.has_charm("adrenaline_syringe"):
				_vehicle.apply_adrenaline_boost()
			else:
				_vehicle.apply_watcher_hit()
			_sanity_ratio += 0.06
			_hud.on_watcher_hit()
			
		_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	if _jumpers.check_collision(_vehicle):
		BillboardManager.add_impact_shake(0.3)
		if _jumper_on_hood:
			# 이미 탑승 중 → 보닛 점퍼 깔리는 연출 + 덜컹 효과
			# GDD: 점퍼 충돌은 부품 손상 없음 (정신력 -1/초 비용으로 대체)
			# Doc 31 §4: 두 번째 점퍼는 BO 없이 정신력만 깎임
			_jumper_on_hood = false
			_jumper_escape_gauge = 0.0
			_hud.crush_jumper_on_hood()
			_vehicle.apply_watcher_hit()
			_sanity_ratio -= 0.08
			_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
		elif _vehicle.speed >= _vehicle.get_kill_threshold(JUMPER_KILL_THRESHOLD):
			# Doc 31 §4: 킬 임계 이상 → 즉시 처치, 보닛에 올라타지 않음
			_resolve_speed_kill(JUMPER_KILL_THRESHOLD, JUMPER_KILL_BO)
			_jumpers.kill_hit(_jumpers.last_hit_k)  # 점프→보드 연출 차단
		# 임계 미만 + 미탑승 → 점프 애니메이션 진행 후 jumper_boarded 신호로 보닛 탑승

	# ── 대각선 펑크 → 정신력 지속 감소 (GDD §4.1: 대각선 조합) ──
	var _flat_lf := _vehicle.dur_lf_tire <= 0.0
	var _flat_rf := _vehicle.dur_rf_tire <= 0.0
	var _flat_lb := _vehicle.dur_lb_tire <= 0.0
	var _flat_rb := _vehicle.dur_rb_tire <= 0.0
	var _is_diagonal_flat := (_flat_lf and _flat_rb) or (_flat_rf and _flat_lb)
	if _is_diagonal_flat:
		_sanity_ratio -= 0.005 * delta  # GDD §4.1: 대각선 펑크 -0.5/초
		_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)



	# ── 보닛 위 점퍼 처리 (Doc 31 §4: 속도 기반 탈출) ──
	if _jumper_on_hood:
		# 정신력 -1/초
		_sanity_ratio -= 0.01 * delta
		_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)

		# 탈출: 임계 속도 이상을 hold_target초 유지하면 점퍼 분리
		var esc_threshold: float = _vehicle.get_kill_threshold(JUMPER_KILL_THRESHOLD)
		var hold_target: float = JUMPER_ESCAPE_HOLD   # (구 fast_react 퍽은 스킬트리에 없어 제거)
		if _vehicle.speed >= esc_threshold:
			_jumper_escape_gauge += delta
		else:
			_jumper_escape_gauge = 0.0  # 속도가 떨어지면 유지 시간 리셋
		_hud.update_escape_gauge(clampf(_jumper_escape_gauge / hold_target, 0.0, 1.0))
		_hud.sway_jumper(_vehicle.steering_angle)

		if _jumper_escape_gauge >= hold_target:
			_jumper_on_hood = false
			_jumper_escape_gauge = 0.0
			_hud.set_jumper_on_hood(false, _vehicle.steering_angle > 0.0)
			_say("jumper_off")
			# 탈출 성공 보상 + 처치 juice (콤보 적용)
			var jmp_mult := _register_combo_kill()
			var jmp_bo := int(round(float(JUMPER_KILL_BO) * jmp_mult))
			_blood_orbs.award_bo(jmp_bo)
			_hud.popup_bo(jmp_bo)
			_hud.play_sfx("pickup", _combo_pitch())
			_spawn_kill_mist(Vector2(640.0, 460.0))
			if _charm_sys.has_charm("distorted_mirror"):
				_sanity_ratio += 0.25
				_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)

	_prev_steering = _vehicle.steering_angle

	# ── 콤보 시간 감쇠 (Doc 31 §3) ──
	if _combo_count > 0:
		_combo_timer += delta
		if _combo_timer > _combo_window:
			_combo_count = 0  # 윈도우 초과 → 콤보 끊김

	# ── 부적 시너지 (지속 효과) ──
	if _charm_sys.has_charm("nodding_dog"):
		if _vehicle.speed >= _vehicle.max_speed * 0.9:
			_sanity_ratio += 0.01 * delta
			_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)


	# ── 수색 프롬프트: 정지 + 폐차 인접 시 표시 ──
	_update_loot_prompt()

func _get_contact_side() -> String:
	# 차량의 cam_x 위치를 기준으로 충돌 부위를 판별
	# cam_x는 -1.0 (좌측) ~ 1.0 (우측) 범위
	if _vehicle.cam_x < -0.2:
		return "left"
	elif _vehicle.cam_x > 0.2:
		return "right"
	return "front"

# ── 전투: 속도 임계 처치 판정 (Doc 31 §1) ─────────────────────
# base_threshold: 적별 기본 임계 속도(km/h). 엔진 업그레이드로 하향됨.
# bo_reward: 관통 처치 성공 시 획득 BO.
func _resolve_speed_kill(base_threshold: float, bo_reward: int) -> void:
	var contact := _get_contact_side()
	var eff_threshold := _vehicle.get_kill_threshold(base_threshold)
	# 충돌 지점 화면 좌표 (도로 하단, 충돌 부위 방향으로 치우침)
	var impact_x := 640.0 + (-160.0 if contact == "left" else (160.0 if contact == "right" else 0.0))
	var impact_pos := Vector2(impact_x, 460.0)

	if _vehicle.speed >= eff_threshold:
		# ── 관통 처치: 모멘텀 유지, 내구도 소량(범퍼 Lv2 감소), BO 획득 ──
		var pmul := _vehicle.get_pierce_dmg_mult()
		_vehicle.apply_part_damage(contact, PIERCE_TIRE_DMG * pmul, PIERCE_DRIVETRAIN_DMG * pmul)
		_vehicle.apply_pierce_kill()
		if _charm_sys.has_charm("adrenaline_syringe"):
			_vehicle.apply_adrenaline_boost()
		# ── 숨겨진 콤보: 배수 적용 (Doc 31 §3) ──
		var mult := _register_combo_kill()
		var bo_gain := int(round(float(bo_reward) * mult * _charm_sys.get_bo_mult()))
		if _collapsed:
			bo_gain = 0   # Doc 04 붕괴 상태: 적 타격 BO 드롭 없음
		_blood_orbs.award_bo(bo_gain)
		_sanity_ratio += 0.06  # 시원한 처치가 정신을 들게 함
		# ── juice: 히트스톱 + 미세 셰이크 + 붉은 안개 + BO 팝업 + 흡수음(콤보 pitch) ──
		_do_hitstop(0.05)
		_trigger_cam_shake(3.0, 0.1)
		_spawn_kill_mist(impact_pos)
		_hud.on_watcher_hit()       # 묵직한 타격음 + 대시보드 흔들림
		_hud.play_sfx("pickup", _combo_pitch())  # BO 흡수 '띵' (콤보 단계만큼 음높이 상승)
		_hud.popup_bo(bo_gain)
	else:
		# ── 충격 튕김: 급감속, 내구도 대량(스테이지1 완화), BO 없음 ──
		# Doc 31 §9: 스테이지 1은 첫 실패가 런을 망치지 않도록 손상 완화
		# Doc 31 §6 Lv4: 범퍼 중장갑 그릴이 튕김 손상 추가 경감
		var dmg_mult := (0.4 if current_stage == 1 else 1.0) * _vehicle.get_bounce_dmg_mult()
		_vehicle.apply_part_damage(contact, BOUNCE_TIRE_DMG * dmg_mult, BOUNCE_DRIVETRAIN_DMG * dmg_mult)
		_vehicle.apply_bounce_hit()
		_reset_combo()  # Doc 31 §3: 임계 미만 충돌(급감속)은 콤보 리셋
		# ── juice: 히트스톱 없음, 더 강하고 긴 불쾌한 셰이크 + 금속 긁힘 ──
		_trigger_cam_shake(6.0, 0.3)
		BillboardManager.add_impact_shake(0.9)
		_hud.trigger_shake("rock")  # mag 9 — 거칠고 불쾌한 흔들림
		_hud.play_sfx("warning")    # 금속 긁힘
		_sanity_ratio += 0.02
	_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)

# ── 히트스톱: 실시간 짧은 정지 (Doc 31 §2) ──
func _do_hitstop(duration: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.0
	# 4번째 인자 ignore_time_scale=true → time_scale 0에서도 실시간으로 동작
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false

func _trigger_cam_shake(mag: float, dur: float) -> void:
	_cam_shake_mag = mag
	_cam_shake_dur = dur
	_cam_shake_time = dur

# ── 숨겨진 콤보 (Doc 31 §3) ───────────────────────────────────
# 처치 등록 → 콤보 누적 후 현재 BO 배수를 반환.
func _register_combo_kill() -> float:
	if _combo_count > 0 and _combo_timer <= _combo_window:
		_combo_count += 1
	else:
		_combo_count = 1
	_combo_timer = 0.0
	return _combo_multiplier()

# 콤보 단계별 BO 배수: 1→×1, 2→×1.3, 3→×1.6, 4+→×2.0
func _combo_multiplier() -> float:
	match _combo_count:
		0, 1: return 1.0
		2:    return 1.3
		3:    return 1.6
		_:    return 2.0

# 흡수음 음높이: 콤보 단계만큼 상승, 4연속+에서 최고조 고정
func _combo_pitch() -> float:
	return 1.0 + clampf(float(_combo_count - 1), 0.0, 3.0) * 0.12

func _reset_combo() -> void:
	_combo_count = 0
	_combo_timer = 0.0

# ── 붉은 안개 분출 (Doc 31 §2) ──
func _spawn_kill_mist(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 1
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 20
	p.lifetime = 0.35
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 180.0
	p.gravity = Vector2(0, 240.0)
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.72, 0.06, 0.05)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.10, 0.08, 0.9))
	ramp.set_color(1, Color(0.45, 0.02, 0.02, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	# 수명 종료 후 자동 정리
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)

const LOOT_PROXIMITY_DZ := 5.0  # 폐차 인접 판정 거리

func _update_loot_prompt() -> void:
	# 점퍼가 보닛에 있으면 수색 프롬프트 숨김
	if _jumper_on_hood:
		_hud.hide_loot_prompt()
		return
	if _vehicle.speed > 0.5:
		_hud.hide_loot_prompt()
		return
	var nearest := _scavenging.get_nearest_car()
	if nearest.is_empty() or float(nearest["dz"]) > LOOT_PROXIMITY_DZ:
		_hud.hide_loot_prompt()
		return
	var rect := _scavenging.get_car_screen_rect(nearest)
	_hud.show_loot_prompt(int(nearest["side"]), rect)

func _on_loot_prompt_clicked() -> void:
	# 점퍼가 보닛에 있으면 수색 불가
	if _jumper_on_hood:
		return
	var nearest := _scavenging.get_nearest_car()
	if nearest.is_empty(): return
	
	var k := int(nearest["k"])
	# 스테이지 번호를 크게 곱해 더해줌으로써 다른 스테이지와 ID가 겹칠 확률을 제거
	var wreck_seed := _scavenging.seed_offset + (current_stage * 1000000) + (k * 1337)
	
	if wreck_seed == _active_wreck_seed and _loot_ui.is_open():
		return  # 이미 열려 있음
	_active_wreck_seed = wreck_seed
	_loot_ui.open_wreck(wreck_seed)

# ── 정신력 시각 효과 제거 (클리어 연출 시점) ───────────────────────────
func _clear_sanity_effects() -> void:
	if _pp_mat != null:
		_pp_mat.set_shader_parameter("offset", 0.0)
		_pp_mat.set_shader_parameter("desaturation", 0.0)
	if _hallucination != null:
		_hallucination.force_stop()
	if _passenger_hallucination != null:
		_passenger_hallucination.force_stop()
	if _hud != null:
		_hud.reset_sanity_visuals()
	# 붕괴 상태는 정비 구간에서 정신력 50% 회복과 함께 종료 (암전 오버레이 정리 포함)
	_exit_collapse()

# ── 다음 스테이지로 진행 (연출 시작) ──────────────────────────────────────
func _advance_to_next_stage() -> void:
	if current_stage >= TOTAL_STAGES:
		# TODO: 엔딩 씬 처리
		return

	_game_state = "stage_exit"
	_state_timer = 0.0
	if _hallucination: _hallucination.force_stop()
	_vehicle.speed = 0.0
	_exit_car_dz = 2.0
	_exit_cam_tilt = 0.0
	_road.show_headlight = false
	_monster_distance = MONSTER_START_DIST  # 스테이지 간 거리 초기화 (02-core-loop: 괴물 거리 초기화)

	# HUD 숨기기 + 카메라 리셋
	_hud.visible = false
	_camera.zoom = Vector2.ONE
	_camera.position = Vector2(640.0, 360.0)

	# 점퍼 상태 초기화 (점프 중이던 점퍼가 다음 스테이지에 넘어오지 않도록)
	_jumpers._hit_info.clear()
	# 진행 중이던 창 취소
	_spear.reset_stage(current_stage)
	_hud.set_mirror_alert(false)
	if _hud._rearview_node != null:
		_hud._rearview_node.spear_state = {}
	_hud.stop_wiper()

	# 성애·물방울 제거 (빗줄기는 유지)
	_rain.hide_glass_effects()

	# 차 후면 텍스처 로드 (후면 + 좌/우회전)
	_exit_car_tex = load("res://Asset/Image/car_back.png") as Texture2D
	_exit_car_left_tex = load("res://Asset/Image/car_left.png") as Texture2D
	_exit_car_right_tex = load("res://Asset/Image/car_right.png") as Texture2D
	_exit_car_active_tex = _exit_car_tex  # 초기에는 후면

	# 페이드용 검은 사각형 — CanvasLayer layer=5로 비(layer=1)보다 위에 렌더
	if _exit_fade_rect:
		_exit_fade_rect.get_parent().queue_free()
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 5
	add_child(fade_layer)
	_exit_fade_rect = ColorRect.new()
	_exit_fade_rect.color = Color(0, 0, 0, 0)
	_exit_fade_rect.position = Vector2.ZERO
	_exit_fade_rect.size = Vector2(BillboardManager.SCREEN_W, BillboardManager.SCREEN_H)
	fade_layer.add_child(_exit_fade_rect)

func _update_stage_exit(delta: float) -> void:
	var t := _state_timer
	var total := EXIT_DRIVE_DURATION + EXIT_FADE_DURATION

	# 카메라 틸트 — hill_px를 증가시켜 지평선을 아래로 내림 (하늘이 더 보이는 효과)
	# camera.position 이동 방식은 road_renderer 렌더 영역이 뷰포트 밖으로 나가 검은 영역 발생
	if t <= EXIT_DRIVE_DURATION:
		var tilt_p := clampf(t / EXIT_DRIVE_DURATION, 0.0, 1.0)
		_exit_cam_tilt = lerpf(0.0, 30.0, tilt_p * tilt_p)  # ease-in, 최대 30px (과도한 틸트 방지)

	# 도로/나무/배경은 계속 렌더 (차가 달려가는 배경)
	var curve_x := _vehicle.compute_strip_curve_offsets()
	var hill_px := _vehicle.hill_offset_px() + _exit_cam_tilt  # 틸트를 hill_px에 반영
	_update_backdrops(delta)
	_update_backdrops_vertical(delta, hill_px, true)
	_road.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)
	_billboard_mgr.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)
	_trees.update_state(_vehicle.scroll_z, _vehicle.cam_x, curve_x, hill_px)

	# 차가 도로를 따라 멀어짐 — dz 증가 (가속)
	if t <= EXIT_DRIVE_DURATION:
		var p := clampf(t / EXIT_DRIVE_DURATION, 0.0, 1.0)
		var ease_p := p * p  # ease-in 가속
		# 시작 위치를 2.0에서 1.0으로 당겨 차를 더 크고 가깝게 시작하게 함
		_exit_car_dz = lerpf(1.0, 80.0, ease_p)

		# 자동차의 실제 위치(Z)에서의 곡률을 구함 (카메라 위치 + 차의 거리)
		var k := _vehicle.curvature_at_z_world(_vehicle.scroll_z + _exit_car_dz)
		const CORNER_K_THRESH := 0.025  # 코너로 판정하는 곡률 임계값을 약간 높임 (제대로 된 코너에서만 전환)
		
		# 연출 극초반(첫 0.4초)에는 무조건 직진(back) 상태로 시작하여 앞으로 가는 느낌을 먼저 줌
		if t < 0.4:
			k = 0.0
			
		if k < -CORNER_K_THRESH and _exit_car_left_tex:
			_exit_car_active_tex = _exit_car_left_tex
		elif k > CORNER_K_THRESH and _exit_car_right_tex:
			_exit_car_active_tex = _exit_car_right_tex
		else:
			_exit_car_active_tex = _exit_car_tex

		# 빌보드로 차 렌더링
		if _exit_car_active_tex:
			var depth: float = BillboardManager.CAMERA_DEPTH / _exit_car_dz
			if depth > 0.01:
				var road_cx := BillboardManager.get_road_cx(depth, _vehicle.cam_x, curve_x)
				var ground_y := BillboardManager.get_ground_y(depth, hill_px)
				# 차 크기 — depth에 비례, 텍스처 종횡비 자동 대응
				var car_h := depth * 400.0
				var car_w := car_h * float(_exit_car_active_tex.get_width()) / maxf(float(_exit_car_active_tex.get_height()), 1.0)
				
				# 이미지 하단 여백 보정 및 하이앵글 상쇄를 위한 파격적인 오프셋
				var y_offset := car_h * 0.45
				var car_y := ground_y - car_h + y_offset
				
				var car_x := road_cx - car_w * 0.5
				# 왼쪽/오른쪽 이미지일 경우, 이미지가 넓어지면서 무게중심이 튀는 것을 방지하기 위해 X 위치 보정
				if _exit_car_active_tex == _exit_car_left_tex:
					car_x += car_w * 0.06  # 우측으로 보정 (왼쪽 차체가 넓어짐)
				elif _exit_car_active_tex == _exit_car_right_tex:
					car_x -= car_w * 0.06  # 좌측으로 보정
				
				# 지평선 근처에서 페이드
				var fade := 1.0 - clampf((ease_p - 0.8) / 0.2, 0.0, 1.0)
				
				_billboard_mgr.add_entry(depth, Rect2(car_x, car_y, car_w, car_h), _exit_car_active_tex, fade)

	_billboard_mgr.render_all()

	# 차가 사라진 후 페이드 아웃
	if t > EXIT_DRIVE_DURATION and _exit_fade_rect:
		var fade_t := clampf((t - EXIT_DRIVE_DURATION) / EXIT_FADE_DURATION, 0.0, 1.0)
		_exit_fade_rect.color = Color(0, 0, 0, fade_t)

	# 연출 완료 → 상점 진입
	if t >= total:
		if _exit_fade_rect:
			_exit_fade_rect.get_parent().queue_free()  # CanvasLayer째 제거
			_exit_fade_rect = null
		_exit_car_tex = null
		_exit_car_left_tex = null
		_exit_car_right_tex = null
		_exit_car_active_tex = null
		_exit_cam_tilt = 0.0
		_road.show_headlight = true
		_hud.visible = true
		_hud.hide_stage_overlay()
		_rain.stop_rain()  # 상점 진입 시 비/성애 제거
		_game_state = "maintenance"
		_shop_ui.open(current_stage, _upgrades, _meta)

func _on_shop_depart_requested(route_type: String) -> void:
	current_stage += 1

	# 열려 있는 UI 모두 닫기
	_loot_ui.close()
	_hud.hide_loot_prompt()

	# hidden_route 퍽: 스테이지 이동 시 무작위 아이템 1개 파밍
	if _meta.has_perk("hidden_route"):
		var finds := ["scrap", "aluminum", "copper_wire", "canned_food", "cigarette", "fuel_can", "flashlight"]
		var found: String = finds[randi() % finds.size()]
		if _inv_mgr.trunk_add(found) >= 0:
			_hud.show_message("숨겨진 경로에서 %s 발견" % str(_inv_mgr.get_item_data(found).get("name", found)))

	# 완전히 새로운 스테이지로 달리기 위해 거리·위치 초기화
	_vehicle.scroll_z = 0.0
	_vehicle.cam_x = 0.0
	_vehicle.steering_angle = 0.0
	stage_start_z = 0.0
	# 정신력: 50% 미만이면 50%까지 회복
	if _sanity_ratio < 0.5:
		_sanity_ratio = 0.5
	# bound_wristwatch: 지난 스테이지 누적 정차 시간 → 정신력 회복 (2초당 +1, 최대 +50)
	if _charm_sys.has_charm("bound_wristwatch") and _charm_sys.stage_stop_time > 0.0:
		var bonus := minf(_charm_sys.stage_stop_time * 0.005, 0.5)
		_sanity_ratio += bonus * _charm_sys.get_sanity_recovery_mult()
	_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	_charm_sys.reset_stage()
	_on_charms_updated()

	# 응급 수리 퍽: 스테이지 3 진입 시 30% 이하인 부품 30% 복구
	if current_stage == 3 and _meta.has_perk("emergency_repair"):
		_vehicle.apply_emergency_repair()


	# ── route_type에 따른 스테이지 환경 적용 ──
	_apply_route_modifiers(route_type)
	_vehicle.apply_upgrades(_upgrades, _meta)

	# 카메라 틸트 초기화 — 배경 수직 위치를 즉시 기본값으로 맞춤
	_update_backdrops_vertical(1.0, 0.0, true)

	_blood_orbs.clear_stage()
	_game_state = "playing"
	_hud.update_radio_for_stage(current_stage, STAGE_LENGTH)
	print("[GAME] 출발! 스테이지: ", current_stage, " 루트: ", route_type)

func _apply_route_modifiers(route_type: String) -> void:
	# 시드 — 스테이지마다 다른 배치
	var stage_seed := randi()
	_scavenging.seed_offset = stage_seed
	_watchers.seed_offset   = stage_seed + 11111
	_jumpers.seed_offset    = stage_seed + 22222
	_obstacles.seed_offset  = stage_seed + 33333
	_movers.seed_offset     = stage_seed + 77777
	_movers.stage           = current_stage
	_movers.reset_stage()
	_blood_orbs.seed_offset = stage_seed + 66666
	_trees.seed_offset      = stage_seed + 44444
	var bo_scale := 1.0 + (current_stage - 1) * 0.12
	_blood_orbs.SPACING_Z = 32.0 / bo_scale
	_blood_orbs.SPAWN_CHANCE = clampf(0.38 + float(current_stage) * 0.06, 0.38, 0.72)
	_jiwons.seed_offset     = stage_seed + 55555

	# Doc 30: 숨 비트 구역 배치 — 스폰 파라미터보다 먼저 (각 시스템이 참조)
	PressureDirector.setup_stage(current_stage, STAGE_LENGTH, stage_seed)

	# 스폰 파라미터 — spawn_config.gd 에서 일괄 계산
	var p := SpawnConfig.get_params(route_type, current_stage)
	_scavenging.SPACING_Z    = p["scavenging"]["spacing"]
	_scavenging.SPAWN_CHANCE = p["scavenging"]["chance"]
	_watchers.SPACING_Z      = p["watcher"]["spacing"]
	_watchers.SPAWN_CHANCE   = p["watcher"]["chance"]
	# Doc 31 §9: 스테이지 1만 전투 학습용 도입부 튜닝 적용
	_watchers.intro_tuning   = (current_stage == 1)
	_watchers.stage_len      = STAGE_LENGTH
	_jiwons.SPACING_Z        = p["watcher"]["spacing"]  # 지원도 동일한 간격 체계 사용
	_jiwons.prepare_spawn(STAGE_LENGTH, _sanity_ratio)
	var jiwon_info = _jiwons.get_spawned_info()
	_jumpers.SPACING_Z       = p["jumper"]["spacing"]
	_jumpers.SPAWN_CHANCE    = p["jumper"]["chance"]
	_jumpers.jiwon_info      = jiwon_info
	_obstacles.SPACING_Z     = p["obstacle"]["spacing"]
	_obstacles.SPAWN_CHANCE  = p["obstacle"]["chance"]
	_obstacles.intro_clear_z = 70.0 if current_stage == 1 else 0.0   # 1스테이지 출발 직후엔 바위 없음
	_obstacles.jiwon_info    = jiwon_info
	_movers.SPACING_Z        = p["mover"]["spacing"]
	_movers.SPAWN_CHANCE     = p["mover"]["chance"]
	_movers.jiwon_info       = jiwon_info
	_deer.reset_stage(current_stage, STAGE_LENGTH, stage_seed + 88888)
	_watchers.jiwon_info     = jiwon_info

	# 비
	var is_raining := route_type == "weather"
	if is_raining:
		_rain.start_rain()
		_vehicle.traction_factor = 0.7  # 미끄러움 (0.55는 고속 조향 둔화와 겹쳐 차선 변경 1.7초 — 회피 불가 수준)
	else:
		_rain.stop_rain()
		_vehicle.traction_factor = 1.0

	# ── 조명 단계 (정상-비오는날-어두운곳) ──
	var is_dark := route_type == "dark"
	var bg_mod   := Color.WHITE
	var road_mod := Color.WHITE
	
	if is_dark:
		bg_mod   = Color(0.32, 0.30, 0.42, 1.0)
		road_mod = Color(0.40, 0.38, 0.52, 1.0)
	elif is_raining:
		bg_mod   = Color(0.65, 0.65, 0.75, 1.0)
		road_mod = Color(0.70, 0.70, 0.85, 1.0)
	
	_sky_sprite.modulate    = bg_mod
	_mtn_sprite.modulate    = bg_mod
	_forest_sprite.modulate = bg_mod
	
	_road.modulate          = Color.WHITE
	_road.road_modulate     = road_mod
	
	_scavenging.set_dark_mode(is_dark or is_raining)
	_watchers.set_dark_mode(is_dark or is_raining)
	_jiwons.set_dark_mode(is_dark or is_raining)
	_jumpers.set_dark_mode(is_dark or is_raining)

	# 창 던지기 — 스테이지별 패턴 리셋 (3스테이지부터 발동)
	_spear.reset_stage(current_stage)
	_hud.set_mirror_alert(false)
	_obstacles.set_dark_mode(is_dark or is_raining)
	_movers.set_dark_mode(is_dark or is_raining)
	_deer.set_dark_mode(is_dark or is_raining)
	_blood_orbs.set_dark_mode(is_dark or is_raining)

# ── 아이템 사용 ─────────────────────────────────────────────
func _on_item_used(item_id: String) -> void:
	if item_id == "fuel_can":
		_vehicle.fuel = minf(_vehicle.fuel + 10.0, _vehicle.fuel_max)
		_vehicle.fuel_ratio = _vehicle.fuel / _vehicle.fuel_max
	elif item_id == "cigarette":
		# 담배: 정신력 20% 회복 (cigarette_taste 퍽 활성 시 30% 회복 및 버프 타이머 작동)
		var amount := 0.20
		if _meta != null and _meta.has_perk("cigarette_taste"):
			amount = 0.30
			_vehicle.apply_cigarette_buff(10.0)
		if _collapsed:
			amount *= 0.7   # Doc 04 붕괴 상태: 손이 떨려 제대로 피우지 못함 (-30%)
		amount *= _charm_sys.get_sanity_recovery_mult()   # backward_radio -50%
		if _charm_sys.has_charm("half_smoked_cig"):
			# 즉시 회복 -10, 대신 60초에 걸쳐 총 +40
			amount = maxf(amount - 0.10, 0.0)
			_charm_sys.start_cig_heal(0.40 * _charm_sys.get_sanity_recovery_mult(), 60.0)
		_cigarette_recovery_timer = 4.5
		_cigarette_recovery_amount = amount
		_hud.spawn_smoke()
	elif item_id == "patch_kit":
		# 타이어 수리: 가장 상태가 나쁜 타이어 50% 수복
		_vehicle.repair_worst_tire(50.0)
		_hud.show_message("타이어를 수리했습니다.")
		_hud.play_sfx("repair")
	elif item_id == "tool_set":
		# 구동계 수리: 40% 수복
		_vehicle.repair_drivetrain(40.0)
		_hud.show_message("구동계를 정비했습니다.")
		_hud.play_sfx("repair")
	
	if _loot_ui != null:
		_loot_ui.refresh_durability_ui()

# ── 코너일 때만 하늘·산·숲 가로 패럴랙스 (무한 타일) ────────────
func _update_backdrops(delta: float) -> void:
	var k := _vehicle.curvature_at_scroll()
	if absf(k) < CORNER_BG_K_THRESH:
		return
	var v := _vehicle.speed
	var mtn_delta    := k * v * BG_MTN_SPEED * delta
	var sky_delta    := mtn_delta * BG_SKY_VS_MTN
	var forest_delta := mtn_delta * BG_FOREST_VS_MTN
	_mtn_scroll    += mtn_delta
	_sky_scroll    += sky_delta
	_forest_scroll += forest_delta
	_apply_bg_scroll()


# ── 도망자 충돌 (Doc 19 §도망자) ────────────────────────────────
# 충돌 장면을 보여주지 않는다: 0.2초 화면 컷 → 소지품이 트렁크에 들어온다 (도로 드롭의 근사)
func _on_fleeing_hit() -> void:
	_screen_cut_timer = 0.2
	_collapse_rect.visible = true
	_collapse_rect.color = Color(0, 0, 0, 1)
	_hud.play_sfx("impact", 0.8)
	_meta.fleeing_hit_count += 1
	_meta.save_data()
	# 소지품: 지갑 50% / 담배 50% / 개인 물건 1~2개
	var drops: Array = []
	if randf() < 0.5: drops.append("wallet")
	if randf() < 0.5: drops.append("cigarette")
	var personal := ["photo", "prescription", "key_ring"]
	drops.append(personal[randi() % personal.size()])
	if randf() < 0.5: drops.append(personal[randi() % personal.size()])
	var got := 0
	for d in drops:
		if _inv_mgr.trunk_add(str(d)) >= 0:
			got += 1
	if got > 0:
		_hud.show_message("…소지품이 흩어졌다. (%d개 수거)" % got, 2.0)
	_say("fleeing_hit", true)
	_mono_quiet_time = 0.0

var _screen_cut_timer: float = 0.0

# ── 사슴머리 통과 (Doc 19 §통과 피해) ──────────────────────────
func _on_deer_passed(speed_kmh: float) -> void:
	if _game_state != "playing":
		return
	if speed_kmh >= 80.0:
		_sanity_ratio -= 0.15
		_deer_desat_pulse = 0.5
		_say("deer_fast", true)
		# black_fang 부적: 80km/h 이상 통과마다 BO +50, 정신력 추가 -10
		if _charm_sys.has_charm("black_fang"):
			_blood_orbs.award_bo(50)
			_hud.popup_bo(50)
			_sanity_ratio -= 0.10
	elif speed_kmh >= 40.0:
		_sanity_ratio -= 0.30
		_vehicle.apply_part_damage("all", 8.0, 8.0)
		_deer_desat_pulse = 0.75
		_say("deer_slow", true)
	else:
		_sanity_ratio -= 0.50
		_vehicle.apply_part_damage("all", 20.0, 20.0)
		_deer_desat_pulse = 0.95
		_movers.force_activate_near(_vehicle.scroll_z, 60.0)   # 주변 적 전체 즉시 활성화
		_say("deer_slow", true)
	_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)
	_trigger_cam_shake(4.0, 0.4)
	_hud.play_sfx("breath", 0.5)
	if _hallucination:
		_hallucination.trigger_glitch(0.4)

# ── 런 클리어 컷신 (Doc 25) ──────────────────────────────────
func _start_run_cutscene() -> void:
	_meta.full_clears += 1
	_meta.save_data()
	_game_state = "cutscene"
	_hud.visible = false
	_hud.hide_stage_overlay()
	_cutscene.play(CutscenePlayer.pages_for_clear(_meta.full_clears))

func _on_cutscene_finished() -> void:
	if _game_state == "cutscene":
		_show_main_menu()

# ── 일반 종료 연출 (Doc 11) ──────────────────────────────────
## 서서히 어두워지며 혼잣말 4줄. 마지막 줄이 런 시작 대사와 같다 — 루프.
func _update_loop_ending(_delta: float) -> void:
	var fade := clampf((_state_timer - 1.0) / (LOOP_ENDING_DURATION - 2.5), 0.0, 1.0)
	_hud.set_gameover_fade(fade)
	if _loop_ending_idx < LOOP_ENDING_SCRIPT.size():
		var row: Array = LOOP_ENDING_SCRIPT[_loop_ending_idx]
		if _state_timer >= float(row[0]):
			_loop_ending_idx += 1
			_hud.show_message(str(row[1]), 2.4)
			if _loop_ending_idx == LOOP_ENDING_SCRIPT.size():
				_hud.play_sfx("breath", 0.7)

# ── 혼잣말 (Doc 26) ───────────────────────────────────────────
## 상황 대사 시도. 침묵/쿨다운이면 아무것도 안 함
func _say(situation: String, force: bool = false) -> void:
	if _game_state != "playing" and situation != "maintenance" and situation != "run_start":
		return
	var line := _mono.pick(situation, _sanity_ratio, force)
	if line != "":
		_hud.show_subtitle(line, 2.6)
		_mono_quiet_time = 0.0

## 매 프레임 상황 감지: 와쳐 시야 진입, 러너 돌진, 라디오, 연료, 괴물 임박, 죄책감
func _update_monologue(delta: float) -> void:
	_mono_quiet_time += delta
	# 와쳐가 시야(45) 안에 처음 들어올 때
	if _watchers.nearest_real_dz() < 45.0:
		_say("watcher")
	# 러너가 막 돌진을 시작했을 때
	if _movers.consume_runner_charged():
		_say("runner")
		_mono_quiet_time = 0.0
	# 라디오 죽음의 주파수: 처음 켜질 때 / 30초 이상 방치
	var on_death := _hud.get_radio_on_death()
	if on_death and not _mono_prev_radio_death:
		_mono_radio_death_time = 0.0
		_say("radio_death_on")
	elif on_death:
		_mono_radio_death_time += delta
		if _mono_radio_death_time >= 30.0:
			_say("radio_death_long")
	_mono_prev_radio_death = on_death
	# 연료 40% / 15% — 스테이지당 1회씩
	if _vehicle.fuel_ratio <= 0.40 and not _mono_fuel40_said:
		_mono_fuel40_said = true
		_say("fuel_40")
	if _vehicle.fuel_ratio <= 0.15 and not _mono_fuel15_said:
		_mono_fuel15_said = true
		_say("fuel_15")
	if _vehicle.fuel_ratio > 0.45:
		_mono_fuel40_said = false
		_mono_fuel15_said = false
	# 괴물 임박 (상한의 20% 이내) — 진입 순간
	var near := _monster_distance < MONSTER_MAX_DIST * 0.2
	if near and not _mono_monster_near:
		_say("monster_near")
		_mono_quiet_time = 0.0
	_mono_monster_near = near
	# 죄책감 랜덤 발화: 조용한 구간(괴물 멀고, 창 없고, 점퍼 없음)
	var quiet := _mono_quiet_time > 20.0 and not _spear.is_active() and not _jumper_on_hood \
		and _monster_distance > MONSTER_MAX_DIST * 0.4
	var g := _mono.tick_guilt(delta, _sanity_ratio, quiet)
	if g != "":
		_hud.show_subtitle(g, 3.2)
		_mono_quiet_time = 0.0

# ── 부적 효과 (Doc 28) ───────────────────────────────────────
## 부적 구성이 바뀌거나 스테이지가 시작될 때 파생 수치 재계산
func _on_charms_updated() -> void:
	_vehicle.charm_mods = _charm_sys.get_vehicle_mods()
	_blood_orbs.bo_mult = _charm_sys.get_bo_mult()

func _all_parts_full() -> bool:
	return _vehicle.dur_lf_tire >= 100.0 and _vehicle.dur_rf_tire >= 100.0 \
		and _vehicle.dur_lb_tire >= 100.0 and _vehicle.dur_rb_tire >= 100.0 \
		and _vehicle.dur_drivetrain >= 100.0

## 매 프레임 지속 효과
func _update_charm_passives(delta: float) -> void:
	_vehicle.sanity_ratio_ext = _sanity_ratio
	# half_smoked_cig: 60초 점진 회복
	_sanity_ratio += _charm_sys.tick_cig_heal(delta)
	# bound_wristwatch: 정차 시간 누적
	if _vehicle.speed < 1.0:
		_charm_sys.stage_stop_time += delta
	# empty_medicine_bottle: 정신력 10 이하 환각 비표시 / sixth_eye: 40 이하 환각 푸른 빛
	var hide_hal := _charm_sys.has_charm("empty_medicine_bottle") and _sanity_ratio <= 0.10
	var tint_hal := _charm_sys.has_charm("sixth_eye") and _sanity_ratio <= 0.40
	_watchers.hide_hallucinations = hide_hal
	_jiwons.hide_hallucinations = hide_hal
	_watchers.tint_hallucinations = tint_hal
	_jiwons.tint_hallucinations = tint_hal
	# old_wiper_motor: 와이퍼 작동 중 장애물 야광 강조
	_obstacles.highlight = _charm_sys.has_charm("old_wiper_motor") and _hud.is_wiper_on()
	# broken_speedometer: 가속 중 라디오 조작 불가 (SPEED 3개 이상이면 무효)
	var w_held := Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")
	_hud.radio_input_blocked = _charm_sys.has_charm("broken_speedometer") and w_held and _charm_sys.count_tag("SPEED") < 3
	# premonition 퍽: 사슴머리/도망자 출현 ~3초(20유닛) 전 경고 (나침반 대신 미러 펄스 + 저음)
	if _meta.has_perk("premonition"):
		var imminent := _deer.is_near(20.0) or _movers.fleeing_ahead_within(20.0)
		if imminent and not _premonition_armed:
			_premonition_armed = true
			_hud.play_sfx("warning", 0.5)
			_hud.show_message("…예감.", 1.2)
		elif not imminent:
			_premonition_armed = false
	# backward_radio: 죽음의 주파수 청취 중 창 발동 5초 전 라디오가 미리 흘린다
	if _charm_sys.has_charm("backward_radio") and _hud.get_radio_on_death():
		if _spear.phase == "idle" and _spear.is_armed() and _spear.seconds_to_next() <= 5.0:
			if not _charm_sys.backward_radio_warned:
				_charm_sys.backward_radio_warned = true
				_hud.show_subtitle("[color=#b08080]…뒤에서… 던진다… 뒤에서…[/color]", 2.5)
		elif _spear.phase != "idle":
			_charm_sys.backward_radio_warned = false
	# last_prayer: 부품 0% 또는 정신력 0 도달 → 1회 회복 후 소멸
	if _charm_sys.has_charm("last_prayer"):
		var part_zero := _vehicle.dur_lf_tire <= 0.0 or _vehicle.dur_rf_tire <= 0.0 \
			or _vehicle.dur_lb_tire <= 0.0 or _vehicle.dur_rb_tire <= 0.0 or _vehicle.dur_drivetrain <= 0.0
		if part_zero or _sanity_ratio <= 0.0:
			_vehicle.dur_lf_tire = maxf(_vehicle.dur_lf_tire, 30.0)
			_vehicle.dur_rf_tire = maxf(_vehicle.dur_rf_tire, 30.0)
			_vehicle.dur_lb_tire = maxf(_vehicle.dur_lb_tire, 30.0)
			_vehicle.dur_rb_tire = maxf(_vehicle.dur_rb_tire, 30.0)
			_vehicle.dur_drivetrain = maxf(_vehicle.dur_drivetrain, 30.0)
			_sanity_ratio = maxf(_sanity_ratio, 0.5)
			_vehicle.fuel = maxf(_vehicle.fuel, _vehicle.fuel_max * 0.5)
			_vehicle.fuel_ratio = _vehicle.fuel / _vehicle.fuel_max
			_charm_sys.remove_charm("last_prayer")
			_hud.show_subtitle("…마지막 기도가 들렸다.", 2.5)
			_hud.play_sfx("pickup", 0.8)
	_sanity_ratio = clampf(_sanity_ratio, 0.0, 1.0)

## 환각 위협 충돌 공통 훅
func _on_hallucination_collision() -> void:
	_say("hallucination")
	# cracked_hand_mirror: 환각 소멸 시 정신력 +5 (SANITY 3개 이상 +10)
	if _charm_sys.has_charm("cracked_hand_mirror"):
		_sanity_ratio += 0.10 if _charm_sys.count_tag("SANITY") >= 3 else 0.05
	# empty_medicine_bottle: 환각이 안 보이는 대신 충돌하면 실제 손상
	if _charm_sys.has_charm("empty_medicine_bottle") and _sanity_ratio <= 0.10:
		_vehicle.apply_part_damage(_get_contact_side(), BOUNCE_TIRE_DMG, BOUNCE_DRIVETRAIN_DMG)
		_vehicle.apply_bounce_hit()

## 내구도 감소 훅 (vehicle.part_damaged)
func _on_part_damaged(_amount: float) -> void:
	if _game_state != "playing":
		return
	# rusty_razor: 내구도 감소마다 25% 확률 ₩500
	if _charm_sys.has_charm("rusty_razor") and randf() < 0.25:
		_inv_mgr.money += 500
		_hud.show_message("녹슨 면도날: +₩500")

## 괴물에게 잡히는 순간 1회성 구원 부적. true면 게임오버 취소
func _try_death_save() -> bool:
	# metal_cross: 정신력 풀회복 + 5초 가속 부스트
	if _charm_sys.has_charm("metal_cross") and not _charm_sys.metal_cross_used:
		_charm_sys.metal_cross_used = true
		_sanity_ratio = 1.0
		_monster_distance = MONSTER_START_DIST * 0.5
		_vehicle.speed = _vehicle.max_speed
		_vehicle._adrenaline_timer = 5.0
		_hud.show_subtitle("…십자가가 뜨겁다.", 2.5)
		_hud.play_sfx("pickup", 0.6)
		return true
	# dead_man_watch: 시간 되감기 (근사: 거리 초기화) + BO -50%
	if _charm_sys.has_charm("dead_man_watch") and not _charm_sys.dead_watch_used:
		_charm_sys.dead_watch_used = true
		_monster_distance = MONSTER_START_DIST
		_blood_orbs.run_total_bo = int(_blood_orbs.run_total_bo * 0.5)
		if _hallucination: _hallucination.trigger_glitch(0.5)
		_hud.show_subtitle("…시계가 거꾸로 돈다.", 2.5)
		return true
	# counterclockwise_doll: 스테이지 시작 지점에서 부활, 부적 1개 영구 소멸
	if _charm_sys.has_charm("counterclockwise_doll") and not _charm_sys.doll_used:
		_charm_sys.doll_used = true
		var lost := _charm_sys.lose_random_charm("counterclockwise_doll")
		_vehicle.scroll_z = stage_start_z
		_vehicle.speed = 0.0
		_vehicle.cam_x = 0.0
		_monster_distance = MONSTER_START_DIST
		_sanity_ratio = maxf(_sanity_ratio, 0.5)
		_movers.reset_stage()
		_spear.reset_stage(current_stage)
		if _hallucination: _hallucination.trigger_glitch(0.6)
		var lost_name: String = str(_charm_sys.get_charm_data(lost).get("name", "")) if lost != "" else ""
		_hud.show_subtitle("…인형이 거꾸로 돌았다. (%s 소멸)" % lost_name, 3.0)
		return true
	return false

# ── 붕괴 상태 (Doc 04 §정신력 0) ─────────────────────────────
func _build_collapse_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 19   # 포스트프로세스(15)·상점(15) 위, 메인메뉴(20) 아래
	add_child(layer)
	_collapse_rect = ColorRect.new()
	_collapse_rect.color = Color(0, 0, 0, 0)
	_collapse_rect.size = Vector2(BillboardManager.SCREEN_W, BillboardManager.SCREEN_H)
	_collapse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapse_rect.visible = false
	layer.add_child(_collapse_rect)

func _enter_collapse() -> void:
	_collapsed = true
	_collapse_blackout = COLLAPSE_BLACKOUT_DUR
	_collapse_knocks = 0
	_collapse_window = 0.0
	_collapse_rect.visible = true
	_collapse_rect.color = Color(0, 0, 0, 1)
	_blood_orbs.collection_enabled = false
	_vehicle.collapse_penalty = true
	_hud.reset_focus_states()
	if _loot_ui != null and _loot_ui.is_open():
		_loot_ui.close()
		_active_wreck_seed = -1
	_reset_combo()
	print("[SANITY] 붕괴 상태 진입")

func _exit_collapse() -> void:
	if not _collapsed:
		return
	_collapsed = false
	_collapse_blackout = 0.0
	_collapse_window = 0.0
	_collapse_rect.visible = false
	_blood_orbs.collection_enabled = true
	_vehicle.collapse_penalty = false
	_hud.set_radio_locked(false)
	print("[SANITY] 붕괴 상태 종료")

## 암전 2초: 조작 불가, 트렁크 노크 3회, 끝나면 라디오 강제 전환+잠금
func _update_collapse_blackout(delta: float) -> void:
	_collapse_blackout -= delta
	_vehicle.speed = move_toward(_vehicle.speed, 0.0, 6.0 * delta)
	var elapsed := COLLAPSE_BLACKOUT_DUR - _collapse_blackout
	# 노크: 0.5 / 1.0 / 1.6초
	var knock_times := [0.5, 1.0, 1.6]
	if _collapse_knocks < knock_times.size() and elapsed >= float(knock_times[_collapse_knocks]):
		_collapse_knocks += 1
		_hud.play_sfx("impact", 0.45)
		_trigger_cam_shake(2.0, 0.08)
	if _collapse_blackout <= 0.0:
		_collapse_blackout = 0.0
		_collapse_rect.visible = false
		_hud.force_death_frequency()
		_hud.set_radio_locked(true)
		_hud.show_message("…라디오가… 안 돌아가.", 2.2)   # 정신력 0에서도 보여야 하는 규칙 안내
	else:
		# 마지막 0.4초는 서서히 밝아짐
		_collapse_rect.color.a = clampf(_collapse_blackout / 0.4, 0.0, 1.0)

func _update_collapse(delta: float) -> void:
	if not _collapsed:
		if _sanity_ratio <= 0.0:
			_enter_collapse()
		return
	if _collapse_blackout > 0.0:
		return
	# ── 완전 종료: >30% ──
	if _sanity_ratio > COLLAPSE_EXIT_SANITY:
		_exit_collapse()
		_hud.show_subtitle("…숨을 쉬자.", 1.8)
		return
	var above_unlock := _sanity_ratio > COLLAPSE_UNLOCK_SANITY
	# >10%: 조향·가속 패널티 해제
	_vehicle.collapse_penalty = not above_unlock
	if above_unlock:
		if _hud.is_radio_locked():
			# 담배가 들었다 → 7초의 창
			_hud.set_radio_locked(false)
			_collapse_window = COLLAPSE_WINDOW_DUR
			_hud.show_subtitle("…손이 움직여. 주파수를 돌려.", 2.0)
		elif _collapse_window > 0.0:
			_collapse_window -= delta
			if _collapse_window <= 0.0 and _hud.get_radio_on_death():
				# 창을 놓침 → 재잠금. 죽음의 주파수 -2/초는 계속
				_hud.set_radio_locked(true)
				_hud.play_sfx("warning", 0.7)
	else:
		# 10% 아래로 다시 떨어짐 → 라디오 재잠금 (안전 주파수였다면 다시 끌려감)
		if not _hud.is_radio_locked():
			_hud.force_death_frequency()
			_hud.set_radio_locked(true)
			_collapse_window = 0.0

# ── 창 던지기 결과 (Doc 08 §명중 시 효과 / §빗맞춤 시 연출) ──
func _on_spear_warning(_shown_side: int) -> void:
	if _game_state != "playing":
		return
	_hud.play_sfx("breath")   # 멀리서 들리는 깊은 들숨

func _on_spear_hit(_side: int) -> void:
	if _game_state != "playing":
		return
	# 5개 부품 모두 -10% (창이 차체를 관통), 정신력 -25, 0.5초 핸들 잠금
	var spear_dmg := 10.0
	if _charm_sys.has_charm("safe_drive_amulet") and _all_parts_full():
		spear_dmg = 5.0   # 안전운전 부적: 전 부품 100% 상태의 명중 손상 -50%
	_vehicle.apply_part_damage("all", spear_dmg, spear_dmg)
	_vehicle.apply_spear_hit()
	if _charm_sys.has_charm("headwind_amulet"):
		_vehicle.apply_headwind()   # 명중 순간 400km/h 1초 → 6초 동력 무효
	_sanity_ratio = clampf(_sanity_ratio - 0.25, 0.0, 1.0)
	_reset_combo()
	_trigger_cam_shake(9.0, 0.5)
	BillboardManager.add_impact_shake(1.0)
	_hud.trigger_shake("rock")
	_hud.play_sfx("impact")
	if _hallucination:
		_hallucination.trigger_glitch(0.2)
	_hud.show_subtitle("…뚫렸어.", 1.6)

func _on_spear_missed(_side: int) -> void:
	if _game_state != "playing":
		return
	# 옆을 휙 지나감: 짧은 셰이크만. 회피 보상 없음 (살아남은 것이 보상)
	_trigger_cam_shake(2.0, 0.15)
	_hud.play_sfx("whoosh")

func _on_jumper_boarded() -> void:
	if _game_state != "playing":
		return  # playing 상태가 아니면 무시 (클리어/연출 중 신호 무시)
	if _jumper_on_hood:
		return  # 이미 탑승 중 → 무시 (check_collision에서 이미 처리)
	_jumper_on_hood = true
	_jumper_escape_gauge = 0.0
	_hud.set_jumper_on_hood(true)
	_say("jumper_on")
	# 점퍼 탑승 시 루팅 UI 강제 종료
	if _loot_ui != null and _loot_ui.is_open():
		_loot_ui.close()
		_active_wreck_seed = -1

func _update_backdrops_vertical(delta: float, hill_px: float, instant: bool = false) -> void:
	# 거리별 세로 패럴랙스: 가까울수록 지평선 이동을 더 많이 따라감
	# 하늘(0.18) < 산(0.45) < 숲(0.72) — 자연스러운 시차감
	var target_sky_y    := _sky_base_y    + hill_px * SKY_HILL_FACTOR
	var target_mtn_y    := _mtn_base_y    + hill_px * MTN_HILL_FACTOR
	var target_forest_y := _forest_base_y + hill_px * FOREST_HILL_FACTOR
	var a := 1.0 if instant else clampf(delta * BG_Y_SMOOTH_SPEED, 0.0, 1.0)
	_sky_y    = lerpf(_sky_y,    target_sky_y,    a)
	_mtn_y    = lerpf(_mtn_y,    target_mtn_y,    a)
	_forest_y = lerpf(_forest_y, target_forest_y, a)

	if _sky_sprite    != null: _sky_sprite.position.y    = _sky_y
	if _mtn_sprite    != null: _mtn_sprite.position.y    = _mtn_y
	if _forest_sprite != null: _forest_sprite.position.y = _forest_y

func _input(event: InputEvent) -> void:
	if _game_state == "splash":
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			_skip_splash()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				_hud.toggle_debug_readout()
			KEY_KP_0:
				if _game_state == "playing":
					_clear_sanity_effects()
					_advance_to_next_stage()
			KEY_KP_1:
				_debug_stop_monster = not _debug_stop_monster
				print("[DEBUG] 괴물 추격 정지 상태: ", _debug_stop_monster)
			KEY_KP_2:
				if _inv_mgr != null:
					_inv_mgr.money += 10000
					print("[DEBUG] 디버그 치트: 자금 +₩10,000원 추가 (현재: ₩", _inv_mgr.money, ")")
					if _shop_ui != null and _shop_ui.visible:
						_shop_ui._refresh_money()
			KEY_KP_3:
				if _vehicle != null:
					_vehicle.fuel = clampf(_vehicle.fuel + 10.0, 0.0, _vehicle.fuel_max)
					_vehicle.fuel_ratio = _vehicle.fuel / _vehicle.fuel_max
					print("[DEBUG] 디버그 치트: 연료 +10L 충전 (현재: ", _vehicle.fuel, "/", _vehicle.fuel_max, "L)")
			KEY_KP_ADD:
				_sanity_ratio = clampf(_sanity_ratio + 0.10, 0.0, 1.0)
				print("[DEBUG] 디버그 치트: 정신력 +10% 증가 (현재: ", int(_sanity_ratio * 100.0), "%)")
			KEY_KP_4:
				_on_item_used("cigarette")
				print("[DEBUG] 디버그 치트: 담배 사용 (연기 파티클 재생 및 정신력 회복)")
			KEY_KP_SUBTRACT:
				_sanity_ratio = clampf(_sanity_ratio - 0.10, 0.0, 1.0)
				print("[DEBUG] 디버그 치트: 정신력 -10% 감소 (현재: ", int(_sanity_ratio * 100.0), "%)")
			# ── 괴물 고무줄 튜닝 (플레이테스트용) ──
			KEY_KP_5:
				MONSTER_MAX_DIST = maxf(MONSTER_MAX_DIST - 10.0, 30.0)
				_apply_monster_max_dist()
				_print_monster_tuning()
			KEY_KP_6:
				MONSTER_MAX_DIST += 10.0
				_apply_monster_max_dist()
				_print_monster_tuning()
			KEY_KP_7:
				MONSTER_GAIN_K = maxf(MONSTER_GAIN_K - 0.01, 0.01)
				_print_monster_tuning()
			KEY_KP_8:
				MONSTER_GAIN_K += 0.01
				_print_monster_tuning()
			KEY_KP_9:
				_monster_distance = MONSTER_START_DIST
				print("[DEBUG] 괴물 거리 리셋 → ", _monster_distance)

func _apply_monster_max_dist() -> void:
	_monster_distance = minf(_monster_distance, MONSTER_MAX_DIST)
	if _hud != null and _hud._rearview_node != null:
		_hud._rearview_node.max_dist = MONSTER_MAX_DIST

func _print_monster_tuning() -> void:
	var m_spd := float(MONSTER_SPEEDS[clampi(current_stage - 1, 0, TOTAL_STAGES - 1)])
	print("[DEBUG] 괴물 튜닝  상한=%.0f  계수=%.2f  | 정차 시 상한→0까지 %.1f초  | %.0fkm/h 순항 시 +%.1f/초" % [
		MONSTER_MAX_DIST, MONSTER_GAIN_K,
		MONSTER_MAX_DIST / maxf(m_spd * MONSTER_GAIN_K, 0.001),
		_vehicle.max_speed, (_vehicle.max_speed - m_spd) * MONSTER_GAIN_K])

# ── 메인 메뉴 ────────────────────────────────────────────────────
func _build_main_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 20  # 모든 UI 위에
	add_child(_menu_layer)

	_menu_container = Control.new()
	_menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(_menu_container)

	# 배경 어둡게
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_container.add_child(bg)

	# 타이틀
	var title := Label.new()
	title.text = "LAST ROAD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 160.0)
	title.size = Vector2(BillboardManager.SCREEN_W, 80.0)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_menu_container.add_child(title)

	# 버튼 컨테이너
	var btn_box := VBoxContainer.new()
	btn_box.position = Vector2(490.0, 340.0)
	btn_box.size = Vector2(300.0, 250.0)
	btn_box.add_theme_constant_override("separation", 20)
	_menu_container.add_child(btn_box)

	var btn_start := _make_menu_button("게임시작")
	btn_start.pressed.connect(_on_menu_start)
	btn_box.add_child(btn_start)

	var btn_upgrade := _make_menu_button("강화")
	btn_upgrade.pressed.connect(_on_menu_upgrade)
	btn_box.add_child(btn_upgrade)

	var btn_exit := _make_menu_button("종료")
	btn_exit.pressed.connect(func(): get_tree().quit())
	btn_box.add_child(btn_exit)

func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300.0, 55.0)
	btn.add_theme_font_size_override("font_size", 28)
	return btn

func _show_main_menu() -> void:
	# 런 종료 시 포인트 지급
	if _stages_cleared_this_run > 0:
		_meta.award_run_points(_stages_cleared_this_run)
	_game_state = "main_menu"
	_menu_container.visible = true
	_hud.visible = false
	_hud.stop_engine_sound()
	_hud.hide_stage_overlay()
	_rain.stop_rain()
	_camera.zoom = Vector2.ONE
	_camera.position = Vector2(640.0, 360.0)

func _on_menu_start() -> void:
	if _is_loading: return
	_is_loading = true
	
	_menu_container.visible = false
	
	# 로딩 스크린 표시 및 에셋 로드 시작
	_loading_layer.visible = true
	await get_tree().process_frame
	await get_tree().process_frame # UI가 그려질 시간을 충분히 줌
	
	await _load_all_assets()
	
	_loading_layer.visible = false
	_is_loading = false
	
	_reset_game()
	_game_state = "playing"
	_say("run_start")

func _on_menu_upgrade() -> void:
	_menu_container.visible = false
	_skill_tree_ui.open()

func _on_skill_tree_closed() -> void:
	_menu_container.visible = true

func _reset_game() -> void:
	# 차량 및 메타 상태 초기화 (세션 기반)
	_upgrades.reset_upgrades()
	_inv_mgr.money = _meta.carry_money   # legacy 퍽 인계분 (없으면 0)
	_meta.carry_money = 0
	_inv_mgr.trunk.fill("")
	
	_vehicle.apply_upgrades(_upgrades, _meta)
	_vehicle.scroll_z = 0.0
	_vehicle.cam_x = 0.0
	_vehicle.steering_angle = 0.0
	_vehicle.speed = 0.0
	_vehicle.fuel = _vehicle.fuel_max
	_vehicle.fuel_ratio = 1.0

	# 게임 진행 초기화
	current_stage = 1
	stage_start_z = 0.0
	_monster_distance = MONSTER_START_DIST
	_stages_cleared_this_run = 0
	_sanity_ratio = 1.0
	_exit_collapse()
	_mono.reset_run()
	_meta.total_runs += 1   # 라디오 죽음의 주파수 단계 (초기 1~3 / 중기 4~6)
	_mono_prev_radio_death = false
	_mono_fuel40_said = false
	_mono_fuel15_said = false
	_mono_monster_near = false
	# 부적은 런 단위 (Doc 28). 이전엔 리셋이 없어 다음 런으로 넘어오던 버그
	_charm_sys.reset_run()
	# first_luck 퍽: 런 시작 시 무작위 일반 부적 1개 즉시 장착
	if _meta.has_perk("first_luck"):
		var hidden := ["dead_man_watch", "sixth_eye", "black_fang", "last_prayer", "backward_radio"]
		var pool: Array = []
		for cid in _charm_sys.CHARM_DB.keys():
			if not hidden.has(cid):
				pool.append(cid)
		if not pool.is_empty():
			_charm_sys.add_charm(str(pool[randi() % pool.size()]))
	_on_charms_updated()
	_cigarette_recovery_timer = 0.0
	_cigarette_recovery_amount = 0.0
	_state_timer = 0.0
	_exit_cam_tilt = 0.0
	_jumper_on_hood = false
	_jumper_escape_gauge = 0.0
	_active_wreck_seed = -1
	_debug_stop_monster = false
	_blood_orbs.reset_run()

	# UI 초기화
	_hud.visible = true
	_hud.hide_stage_overlay()
	_road.show_headlight = true

	# 카메라 리셋
	_camera.zoom = Vector2.ONE
	_camera.position = Vector2(640.0, 360.0)

	# 배경 리셋
	_update_backdrops_vertical(1.0, 0.0, true)

	# 스테이지 환경 적용
	_apply_route_modifiers("normal")
	_hud.update_radio_for_stage(1, STAGE_LENGTH)

# ── 자산 로딩 시스템 ──────────────────────────────────────────
var _loading_layer : CanvasLayer
var _loading_container : Control
var _loading_bar : ProgressBar
var _is_loading : bool = false
var _assets_loaded : bool = false

func _build_loading_screen() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 100 # 최상단
	_loading_layer.visible = false
	add_child(_loading_layer)
	
	_loading_container = Control.new()
	_loading_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(_loading_container)
	
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_container.add_child(bg)
	
	var label := Label.new()
	label.text = "PREPARING FOR THE LAST ROAD..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.size = Vector2(600, 100)
	label.position = Vector2(BillboardManager.SCREEN_W * 0.5 - 300, 300)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_loading_container.add_child(label)
	
	_loading_bar = ProgressBar.new()
	_loading_bar.size = Vector2(400, 20)
	_loading_bar.position = Vector2(BillboardManager.SCREEN_W * 0.5 - 200, 420)
	_loading_bar.show_percentage = false
	_loading_container.add_child(_loading_bar)
	
	# 프로그레스바 스타일링
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style_bg.set_border_width_all(1)
	style_bg.border_color = Color(0.3, 0.3, 0.3)
	
	var style_fg = StyleBoxFlat.new()
	style_fg.bg_color = Color(0.7, 0.2, 0.1, 1.0) # 강렬한 빨간색 계열
	
	_loading_bar.add_theme_stylebox_override("background", style_bg)
	_loading_bar.add_theme_stylebox_override("fill", style_fg)

func _load_all_assets() -> void:
	if _assets_loaded: return
	
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	
	# 1. 시스템별 로딩 (단계적으로 진행)
	var steps = [
		func(): if _trees.has_method("load_assets"): _trees.load_assets(),
		func(): if _obstacles.has_method("load_assets"): _obstacles.load_assets(),
		func(): if _watchers.has_method("load_assets"): _watchers.load_assets(),
		func(): if _jiwons.has_method("load_assets"): _jiwons.load_assets(),
		func(): if _jumpers.has_method("load_assets"): _jumpers.load_assets(),
		func(): if _movers.has_method("load_assets"): _movers.load_assets(),
		func(): if _deer.has_method("load_assets"): _deer.load_assets(),
		func(): if _scavenging.has_method("load_assets"): _scavenging.load_assets(),
		func(): if _blood_orbs.has_method("load_assets"): _blood_orbs.load_assets(),
		func(): _build_sky_tiled(),
		func(): _build_mountain_tiled(),
		func(): _build_forest_tiled()
	]
	
	var step_val = 100.0 / steps.size()
	for s in steps:
		s.call()
		_loading_bar.value += step_val
		await get_tree().process_frame # UI 갱신 허용
	
	_loading_bar.value = 100.0
	await get_tree().process_frame
	
	_assets_loaded = true

# ── 스플래시 화면 시퀀스 ──────────────────────────────────────────
func _start_splash_sequence() -> void:
	_game_state = "splash"
	_current_splash_index = 0
	
	_splash_layer = CanvasLayer.new()
	_splash_layer.layer = 100 # 다른 모든 UI 레이어보다 위에 배치
	add_child(_splash_layer)
	
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_layer.add_child(bg)
	
	var font_neo := load("res://Font/NeoDunggeunmoPro-Regular.ttf") as Font
	
	# 1. 엔진 스플래시 컨테이너
	_godot_container = Control.new()
	_godot_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_godot_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_godot_container.modulate.a = 0.0
	_splash_layer.add_child(_godot_container)
	
	# "MADE WITH" 라벨
	var godot_label := Label.new()
	godot_label.text = "MADE WITH"
	godot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	godot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	godot_label.add_theme_font_override("font", font_neo)
	godot_label.add_theme_font_size_override("font_size", 24)
	godot_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	godot_label.size = Vector2(1280, 50)
	godot_label.position = Vector2(0, 200)
	godot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_godot_container.add_child(godot_label)
	
	# Godot 로고
	var godot_logo := TextureRect.new()
	godot_logo.texture = load("res://icon.svg") as Texture2D
	godot_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	godot_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	godot_logo.size = Vector2(160, 160)
	godot_logo.position = Vector2(1280 / 2 - 80, 270)
	godot_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_godot_container.add_child(godot_logo)
	
	# "GODOT ENGINE" 라벨
	var godot_name_label := Label.new()
	godot_name_label.text = "GODOT ENGINE"
	godot_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	godot_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	godot_name_label.add_theme_font_override("font", font_neo)
	godot_name_label.add_theme_font_size_override("font_size", 32)
	godot_name_label.add_theme_color_override("font_color", Color(0.28, 0.55, 0.85))
	godot_name_label.size = Vector2(1280, 50)
	godot_name_label.position = Vector2(0, 460)
	godot_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_godot_container.add_child(godot_name_label)
	
	# 2. TPC 스플래시 컨테이너
	_tpc_container = Control.new()
	_tpc_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tpc_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tpc_container.modulate.a = 0.0
	_tpc_container.visible = false
	_splash_layer.add_child(_tpc_container)
	
	var tpc_tex := load("res://Asset/Image/TPC.png") as Texture2D
	if tpc_tex != null:
		var tpc_logo := TextureRect.new()
		tpc_logo.texture = tpc_tex
		tpc_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tpc_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tpc_logo.size = Vector2(1280, 720)
		tpc_logo.position = Vector2.ZERO
		tpc_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tpc_container.add_child(tpc_logo)
	
	# 첫 번째 스플래시 단계 실행
	_play_splash_step(0)

func _play_splash_step(index: int) -> void:
	_current_splash_index = index
	
	if _splash_tween != null and _splash_tween.is_valid():
		_splash_tween.kill()
		
	if index == 0:
		if _godot_container != null:
			_godot_container.visible = true
			_godot_container.modulate.a = 0.0
		if _tpc_container != null:
			_tpc_container.visible = false
			
		_splash_tween = create_tween()
		_splash_tween.tween_property(_godot_container, "modulate:a", 1.0, 1.2)
		_splash_tween.tween_interval(1.5)
		_splash_tween.tween_property(_godot_container, "modulate:a", 0.0, 1.0)
		_splash_tween.tween_callback(func():
			_play_splash_step(1)
		)
	elif index == 1:
		if _godot_container != null:
			_godot_container.visible = false
		if _tpc_container != null:
			_tpc_container.visible = true
			_tpc_container.modulate.a = 0.0
			
		_splash_tween = create_tween()
		_splash_tween.tween_property(_tpc_container, "modulate:a", 1.0, 1.2)
		_splash_tween.tween_interval(2.0)
		_splash_tween.tween_property(_tpc_container, "modulate:a", 0.0, 1.0)
		_splash_tween.tween_callback(func():
			_play_splash_step(2)
		)
	else:
		_end_splash_sequence()

func _skip_splash() -> void:
	# 클릭 또는 키 입력 한 번당 스플래시 하나씩만 스킵
	if _current_splash_index == 0:
		_play_splash_step(1)
	else:
		_play_splash_step(2)

func _end_splash_sequence() -> void:
	if _splash_tween != null and _splash_tween.is_valid():
		_splash_tween.kill()
	if _splash_layer != null:
		_splash_layer.queue_free()
		_splash_layer = null
	_show_main_menu()
