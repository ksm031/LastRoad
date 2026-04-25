# LAST ROAD 디자인 문서 — 개요

> *기름이 다 떨어지면 그냥 거기서 끝이다.*

**버전**: 1.8 (원본 2026-04-16) | **상태**: 리빙 문서 | **최근 변경**: 메타 진행 시스템 추가 (21-meta-progression.md)

원본 `LAST_ROAD_GDD.md`를 기능별로 분할한 문서 세트입니다. 토큰 효율을 위해 필요한 부분만 골라 읽으세요.

## 문서 목록

| 파일 | 담는 내용 | 언제 읽나 |
|------|---------|---------|
| [01-game-overview.md](01-game-overview.md) | 게임 한 줄 피치, 장르, 플랫폼, 경쟁작 비교, 4개 디자인 필러 | 게임 정체성·목표·핵심 가치 확인 |
| [02-core-loop.md](02-core-loop.md) | 속도 딜레마 시스템(핵심 긴장 구조), 코어 루프 다이어그램, 세션 루프 요약 | 게임플레이 흐름·기본 의사결정 구조 확인 |
| [03-driving.md](03-driving.md) | Pseudo 3D 드라이빙 구현 방식, 조작 입력, 속도 파라미터, 헤드라이트 조명 시스템 | 조작·구동·헤드라이트 관련 구현 |
| [04-resources.md](04-resources.md) | 기름·수리재료·정신력 3자원 시스템, 트렁크 용량, 얼굴 표정 연동 | 자원 수치·소모·획득 규칙 확인 |
| [05-parts.md](05-parts.md) | 5개 소켓 구조, 파츠 등급(고물/중고/희귀/저주받은), 내구도, 획득처 | 파츠 아이템·수리·소켓 로직 작업 |
| [06-threats.md](06-threats.md) | 자연 위협·적 위협·환각 위협 카테고리, 사슴머리(보스) | 위협 카테고리·환각 시스템 |
| [19-enemies.md](19-enemies.md) | 적 5종 (와쳐·러너·점퍼·워커·앰부서) 행동·충돌·설계 의도 | 적 AI·충돌 판정 구현 |
| [20-maintenance.md](20-maintenance.md) | 정비 구간 (파츠 교체·수리·잡품 판매·루트 선택) | 스테이지 간 정비 UI 구현 |
| [21-meta-progression.md](21-meta-progression.md) | 메타 진행 (포인트·스킬 트리·4브랜치 퍽 20종) | 런 간 성장·메인 메뉴 구현 |
| [07-vhs.md](07-vhs.md) | 자원 상태 → 화면 효과 매핑표, VHS 기본 레이어(스캔라인·그레인·타임코드) | 화면 효과·포스트프로세싱 |
| [08-monster-chase.md](08-monster-chase.md) | 괴물 추격 속도·거리 시스템, 룸미러 얼굴/포커싱 2모드, 거점 체류 제한, 엔딩 E | 괴물·룸미러·시간 압박 시스템 |
| [09-wiper.md](09-wiper.md) | 와이퍼 조작, 빗물 누적, 고장 조건, 라디오·정신력·색수차 연동 | 와이퍼·우천 연출 작업 |
| [10-progression.md](10-progression.md) | 4개 구간 구성, 3개 거점, 안전로/단축로 경로 선택, 난이도 커브 표 | 레벨 진행·구간별 튜닝 |
| [11-narrative.md](11-narrative.md) | 세계관, 톤, 운전자 혼잣말, 귀신 들린 라디오 3채널, 5개 엔딩 | 스토리·대사·라디오 스크립트 |
| [12-art-direction.md](12-art-direction.md) | 픽셀아트 규격, 빌보드 처리, 색수차 시스템, 컬러 팔레트, 스프라이트 목록 | 아트 에셋·비주얼 스타일 |
| [13-sound-design.md](13-sound-design.md) | 음악 방향, 라디오 사운드, 효과음 카테고리, 다이내믹 오디오 규칙 | 사운드 작업 |
| [14-ui-ux.md](14-ui-ux.md) | HUD 구성(최소화 원칙), 룸미러 인터랙션, 거점 UI, 온보딩 | UI 레이아웃·상호작용 |
| [15-tech-overview.md](15-tech-overview.md) | 엔진·해상도 설정, Pseudo 3D 핵심 로직, 도로·커브·언덕·시차 스크롤·전봇대 구현 | Godot 구현·셰이더·렌더링 |
| [16-glossary.md](16-glossary.md) | 용어 정의(구간, 소켓, 파츠, 정신력, VHS, 빌보드, 색수차 등) | 용어 참조 |
| [17-scavenging.md](17-scavenging.md) | 폐차 스폰·드롭 테이블, 수색 진행(칸 단위 프로그레스), 인벤토리 UI 조작, 실시간 진행 규칙 | 갓길 수색·인벤토리 상호작용 구현 |
| [18-radio.md](18-radio.md) | 죽음의 주파수 시스템, V키 줌인 조작, 주파수 전환 주기(구간별), 핸들 입력 잠금 규칙 | 라디오 조작·정신력 연동 구현 |

## 빠른 찾아보기

- **"괴물이 어떻게 접근하지?"** → [08-monster-chase.md](08-monster-chase.md)
- **"정신력이 낮으면 뭐가 바뀌지?"** → [04-resources.md](04-resources.md) + [07-vhs.md](07-vhs.md)
- **"적 종류별 행동은?"** → [19-enemies.md](19-enemies.md)
- **"색수차 강도 수치?"** → [12-art-direction.md](12-art-direction.md)
- **"Pseudo 3D 투영 코드?"** → [15-tech-overview.md](15-tech-overview.md)
- **"엔딩 조건은?"** → [11-narrative.md](11-narrative.md)
- **"갓길 폐차 수색은 어떻게?"** → [17-scavenging.md](17-scavenging.md)
- **"라디오 죽음의 주파수는?"** → [18-radio.md](18-radio.md)
- **"스테이지 클리어 후 정비는?"** → [20-maintenance.md](20-maintenance.md)
- **"전체 스테이지 구조·루트 선택은?"** → [10-progression.md](10-progression.md)

## 참고

- 섹션 간 상호 참조 시 파일명을 명시합니다 (예: *자세한 색수차 수치는 [12-art-direction.md](12-art-direction.md) 참조*).
- 원본 `LAST_ROAD_GDD.md`는 본 분할 완료 후 폐기되었습니다.
