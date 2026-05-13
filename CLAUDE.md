# CLAUDE.md — Last Road 개발 가이드

## 프로젝트 개요

**Last Road** — Godot 4.6 기반 Pseudo-3D 드라이빙 서바이벌 호러 게임
- 해상도: 1280x720 (고정, 리사이즈 불가)
- 렌더링: Mobile, Nearest Neighbor 텍스처 필터
- 언어: GDScript
- 타겟: Windows (Steam) 우선

## 핵심 아키텍처

### 씬 구조
단일 씬(`scenes/main.tscn`)에 `game_world.gd` 스크립트가 붙어있고, 모든 UI/게임플레이 노드는 `_ready()`에서 코드로 생성된다. `.tscn` UI 에디터를 사용하지 않는다.

### 게임 상태 머신 (game_world.gd)
```
playing → stage_clear → stage_exit → maintenance → playing
       → game_over
```

### 렌더링 파이프라인
1. 배경 (sky, mountain) — Sprite2D, 패럴렉스 스크롤
2. 도로 (road_renderer.gd) — 400 strips `_draw()` 방식
3. 빌보드 (billboard_manager.gd) — depth 정렬 스프라이트 풀
4. 비/와이퍼 (rain_renderer.gd) — CanvasLayer z=1
5. HUD/대시보드 (hud.gd) — CanvasLayer z=2
6. 루트UI (loot_ui.gd) — CanvasLayer z=12
7. 상점UI (shop_ui.gd) — CanvasLayer z=15

### Pseudo-3D 투영 모델 (BillboardManager)
```gdscript
depth = CAMERA_DEPTH(0.84) / dz          # dz = 세계 단위 거리
screen_x = 640.0 + curve_offset - cam_x * depth * 320.0
screen_y = HORIZON_Y(300) + depth * (ROAD_BOTTOM_Y(500) - HORIZON_Y)
scale = depth                             # 가까울수록 큼
```
모든 도로 오브젝트(적, 폐차, 나무, 장애물)가 이 투영 모델을 공유한다.

### 절차적 생성 시스템
모든 스폰 시스템(watcher, jumper, obstacle, scavenging, tree)은 결정적(deterministic) 시드 기반:
```gdscript
func _rand01(seed_val: int) -> float:
    var h := int(((seed_val + seed_offset) * 1103515245 + 12345) & 0x7fffffff)
    return float(h & 0xFFFF) / 65535.0
```
- `seed_offset`은 스테이지/런마다 `randi()`로 설정
- `SPACING_Z`, `SPAWN_CHANCE`는 `var`로 선언되어 route_type에 따라 동적 조정

## 코딩 규칙

### GDScript 스타일
- `snake_case` 변수/함수명, `PascalCase` 클래스명
- private 멤버: `_` 접두사 (`_hit_info`, `_anim_time`)
- 상수: `UPPER_SNAKE_CASE`
- 한국어 주석 사용 (코드베이스 전체가 한국어 주석)
- `const` → 고정값, `var` → 런타임 조정 필요한 값 (route modifier 등)

### 주요 공유 상수 (`billboard_manager.gd`에 통합 정의)
```
SCREEN_W = 1280, SCREEN_H = 720, HORIZON_Y = 300
ROAD_BOTTOM_Y = 500, ROAD_HW_MAX = 650, CAMERA_DEPTH = 0.84
STRIPE_INTERVAL = 1.2
COL_GRASS_A/B, COL_ROAD_A/B, COL_RUMBLE_W, COL_LANE_Y (도로 색상)
```
다른 파일에서는 `BillboardManager.SCREEN_W` 등으로 참조한다. `NUM_STRIPS`는 `road_renderer.gd`에만 정의 (400).

### 시그널 연결
시그널은 `game_world.gd`의 `_ready()`에서 코드로 연결한다. `.tscn` 에디터 연결 없음.

## 파일 구조

```
scripts/          # GDScript 18개
  game_world.gd   # 메인 컨트롤러 (상태 머신, 충돌, 진행)
  vehicle.gd      # 차량 물리 (속도, RPM, 연료, 조향)
  hud.gd          # 대시보드 UI 전체
  road_renderer.gd       # 도로 _draw()
  billboard_manager.gd   # depth 정렬 스프라이트 풀
  tree_renderer.gd       # 나무 빌보드
  rain_renderer.gd       # 비/와이퍼
  rearview_renderer.gd   # 백미러
  scavenging_system.gd   # 폐차 스폰/루팅
  obstacle_system.gd     # 바위 장애물
  watcher_system.gd      # 눈알 적
  jumper_system.gd       # 점퍼 적
  inventory_manager.gd   # 인벤토리 데이터
  loot_ui.gd             # 루팅 UI
  shop_ui.gd             # 상점/경로 선택 UI
  mirror_frame.gd        # 미러 프레임
  windshield_glass.gdshader  # 유리 셰이더

Asset/Image/      # 100+ PNG
  Character/      # 점퍼, 와쳐, 웬디고 스프라이트
  trees/          # tree_01~07, bush_01~08
  Obstacle/       # rock_01~09
  item/           # 아이템 아이콘 18종
  (루트)          # 대시보드, 하늘, 산, 도로 텍스처

Doc/              # GDD 마크다운 26개 + item-icons.json
Font/             # DS-DIGII.TTF (디지털 시계)
```

## 빌드 & 실행

```bash
# Godot 4.6 에디터에서 실행 (F5)
# 메인 씬: res://scenes/main.tscn
# 디버그 키: 0 → 스테이지 강제 클리어
```

## 주의사항

- hud.gd는 매우 크다 (1200+ 줄). 수정 시 해당 함수 근처만 읽을 것.
- `billboard_manager.gd`의 `add_entry()` 호출 순서가 렌더링 순서에 영향. `render_all()`에서 depth 정렬됨.
- 대시보드가 화면 하단 500~720px을 가린다. 도로 렌더링은 ROAD_BOTTOM_Y(500)까지만 의미 있음.
- 스테이지 클리어 연출 시 HUD를 숨기므로 하단 영역 노출에 주의.
- 상점 노드맵은 런 전체에 걸쳐 persistent (매 스테이지 재생성 아님).
