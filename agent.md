# agent.md — Last Road AI 에이전트 작업 지침

## 역할

Godot 4.6 GDScript 게임 개발 전문 에이전트. "Last Road" 프로젝트의 기능 구현, 버그 수정, 리팩토링을 수행한다.

## 작업 원칙

### 1. 코드 먼저 읽기
- 수정 대상 파일을 반드시 읽은 후 편집한다.
- 특히 `game_world.gd`, `hud.gd`는 크기가 크므로 관련 함수만 검색해서 읽는다.
- 기존 패턴을 따른다 (새 패턴 도입 금지).

### 2. 기존 시스템 활용
- 새 스프라이트 → `billboard_manager.gd`의 `add_entry()` 사용
- 새 적/오브젝트 → 기존 watcher/jumper/obstacle 시스템 패턴 복제
- UI 요소 → 코드로 생성 (`_ready()`에서), `.tscn` 에디터 사용 안 함
- 절차적 배치 → `_rand01(seed)` 패턴 사용, `seed_offset` 지원

### 3. Pseudo-3D 투영
도로 위 모든 오브젝트는 `BillboardManager`의 투영 모델을 따른다:
```gdscript
var depth := BillboardManager.CAMERA_DEPTH / dz
var road_cx := BillboardManager.get_road_cx(depth, cam_x, curve_x)
var ground_y := BillboardManager.get_ground_y(depth, hill_px)
var road_hw := BillboardManager.get_road_hw(depth)
```
직접 좌표 계산하지 말고 반드시 이 static 함수들을 사용한다.

### 4. 셰이더
- 헤드라이트 셰이더: 각 시스템(watcher, jumper)이 자체 `ShaderMaterial` 풀을 관리
- `light_height` uniform으로 depth 기반 조명 제어
- 새 셰이더가 필요하면 인라인 문자열(`const SHADER := """..."""`)로 작성

### 5. 한국어
- 주석은 한국어로 작성
- 변수/함수명은 영어 snake_case
- 커밋 메시지는 영어

## 시스템 간 의존성

```
game_world.gd (마스터)
  ├── vehicle.gd          # 입력 → 속도/조향/연료
  ├── road_renderer.gd    # scroll_z, cam_x, curve_x, hill_px
  ├── billboard_manager.gd # 렌더링 허브
  │   ├── tree_renderer.gd
  │   ├── scavenging_system.gd
  │   ├── obstacle_system.gd
  │   ├── watcher_system.gd
  │   └── jumper_system.gd
  ├── hud.gd              # 게이지, 라디오, 와이퍼, 오버레이
  │   └── rearview_renderer.gd
  ├── rain_renderer.gd
  ├── inventory_manager.gd
  ├── loot_ui.gd
  └── shop_ui.gd
```

모든 시스템은 `game_world.gd`의 `_process(delta)`에서 `update_state()` 호출로 갱신된다.

## 충돌 처리 패턴

```gdscript
# game_world._process() 내부:
if system.check_collision(vehicle):
    # 효과 적용 (속도 감소, 정신력 감소 등)
```
각 시스템의 `check_collision()`은:
1. 현재 차량 레인과 오브젝트 레인 비교
2. `dz` (세계 단위 거리) 임계값 비교
3. 쿨다운(`_hit_info`) 확인
4. hit 등록 후 `true` 반환

## 스테이지 진행 흐름

```
1. _on_shop_depart_requested(route_type)
   → _apply_route_modifiers(route_type)  # 시스템별 seed_offset, 난이도 설정
   → 차량/스크롤 리셋
   → _game_state = "playing"

2. 플레이 중 scroll_z >= STAGE_LENGTH
   → _game_state = "stage_clear"
   → 2초 대기 → _advance_to_next_stage()

3. _advance_to_next_stage()
   → _game_state = "stage_exit"
   → 차 멀어지는 연출 (billboard) + 카메라 틸트
   → 페이드 아웃 → shop_ui.open()
```

## 경로 선택 맵 (shop_ui.gd)

Slay the Spire 스타일 노드맵:
- `MAP_COLS=7`, `MAP_PATHS=4`
- 런 시작 시 한 번 생성, 게임오버 또는 클리어까지 유지
- `_player_node_idx`로 현재 위치 추적
- `_selectable_nodes`는 현재 노드의 connections에서 계산
- 노드 타입: normal, danger, wreck, rest, event (컬럼별 가중치 다름)

## 자주 하는 실수 방지

- `SPACING_Z`, `SPAWN_CHANCE`가 `const`인지 `var`인지 확인 (route modifier 필요 시 `var`)
- `scroll_z`는 스테이지마다 0으로 리셋됨 → 절대 위치가 아닌 상대 위치
- `cam_x`는 -1~1 범위 (좌/중앙/우), `round()`로 레인 정수화
- `billboard_mgr.render_all()`은 `_process()` 끝에서 한 번만 호출
- `_map_generated` 플래그로 맵 재생성 방지 (상점 열 때마다 호출되는 `_build_routes()`)
- 대시보드 영역(y=500~720)은 HUD 숨길 때 노출됨에 주의

## GDD 참조

`Doc/` 폴더에 26개 설계문서가 있다. 새 기능 구현 전 관련 GDD를 확인한다:
- 적/위협 → `06-threats.md`, `19-enemies.md`
- 드라이빙 → `03-driving.md`, `15-tech-overview.md`
- 리소스 → `04-resources.md`
- UI → `14-ui-ux.md`
- 상점 → `20-maintenance.md`
- 스토리 → `11-narrative.md`, `22-true-ending.md`
- 아이템 → `17-scavenging.md`, `Doc/item-icons.json`
