---
inclusion: always
---

# Project Structure

## 현재 상태

Godot 클라이언트는 `MockServer.gd`(로컬 목 서버)로 완전한 1판 흐름(로비→인게임→결과)이 동작하는 단계이다. `server/`는 아직 존재하지 않으며, 다음 단계는 `MockServer.gd`의 계약을 그대로 구현하는 Node.js 웹소켓 서버를 만들고 클라이언트의 `MockServer` 호출부를 실제 `NetworkClient`로 교체하는 것이다. 정확한 메시지/필드 계약은 [api-spec.md](api-spec.md)를 기준으로 한다.

실제 저장소 구조(스캐폴딩이 아니라 현재 존재하는 파일 기준):

```text
26s-w2-c3-02/
├─ README.md
├─ Docs/
│  ├─ product.md       # 게임 목표, 규칙, MVP 범위
│  ├─ tech.md           # LLM용 기술 스택/구현 규칙
│  ├─ structure.md      # 저장소 구조와 문서 관계 (이 문서)
│  ├─ api-spec.md       # 웹소켓 메시지 규약 (MockServer.gd 기준)
│  ├─ tech-spec.md      # 기술 후보와 리스크 메모
│  └─ Plan.md           # 클라이언트 병렬 개발 계획(A/B 트랙)
├─ client/
│  ├─ project.godot
│  ├─ scenes/
│  │  ├─ boot/         Boot.tscn
│  │  ├─ menu/         MainMenu / InventoryPreview3D 등           [A]
│  │  ├─ hud/          GameHUD.tscn                                [A]
│  │  ├─ world/        Game.tscn, Pond.tscn, props/                [B]
│  │  ├─ player/       Player.tscn                                 [B]
│  │  ├─ duckling/     Duckling.tscn                                [B]
│  │  └─ effects/      WaterWake.tscn 등 장식 이펙트                [B]
│  ├─ scripts/
│  │  ├─ autoload/     GameData / SceneRouter / MockServer .gd      [공동, MockServer는 서버 전환 대상]
│  │  ├─ menu/                                                      [A]
│  │  ├─ hud/                                                       [A]
│  │  ├─ world/                                                     [B]
│  │  ├─ player/                                                    [B]
│  │  ├─ duckling/                                                  [B]
│  │  └─ effects/                                                   [B]
│  └─ assets/
│     ├─ duck/  aligator/  duckling/                                [B]
│     ├─ island/  island_1/  rock/  rock_fbx/  Bush_temp_climate/
│     │  Grass_temp_climate/  flower/  lilypad/  Nest/               [B, 연못 지형·소품]
│     ├─ audio/
│     └─ ui/  (아이콘·폰트·버튼 이미지)                               [A]
└─ server/   ← 아직 없음. 다음 섹션의 구조로 새로 만든다.
   ├─ package.json
   ├─ src/
   │  ├─ index.js
   │  ├─ rooms.js
   │  ├─ gameLoop.js
   │  ├─ messages.js
   │  └─ constants.js
   └─ README.md
```

## 문서 관계

- **product.md**는 게임이 무엇을 해야 하는지 설명하는 기준 문서이다.
- **tech.md**는 LLM이 구현할 때 따라야 하는 기술 선택과 제약을 정리한다.
- **structure.md**는 폴더와 파일을 어디에 둘지 정한다.
- **api-spec.md**는 Godot 클라이언트(`MockServer.gd`)와 앞으로 만들 Node.js 서버가 주고받는 메시지 형식을 정의한다. 서버 구현의 1차 기준 문서다.
- **tech-spec.md**는 기술 조사와 의사결정 메모로 유지한다.
- **Plan.md**는 클라이언트 개발 단계에서의 A/B 트랙 소유권 분담 기록이다(서버 작업에는 직접 적용되지 않는다).

## 클라이언트 구조 (현재)

- `scenes/menu/`, `scripts/menu/`: 메인 화면(사이드바+콘텐츠), 로비 오버레이, 인벤토리 3D 프리뷰
- `scenes/hud/`, `scripts/hud/`: 인게임 HUD(타이머, 점수, 감옥/구출 게이지, 대시 쿨타임 도넛, 이벤트 토스트)
- `scenes/world/`, `scripts/world/`: `Game.tscn`(월드 루트, 플레이어/HUD 조합 지점), `Pond.tscn`(연못 지형·둥지·감옥·장애물), 대시 판정(`game.gd`)
- `scenes/player/`, `scripts/player/`: 오리/악어 공용 `Player.tscn` — 이동, 대시, 물 위 부유/출렁임 연출
- `scenes/duckling/`, `scripts/duckling/`: 새끼오리 스폰·추종·상태 시각화
- `scenes/effects/`, `scripts/effects/`: 판정과 무관한 장식 이펙트(물결 웨이크 등) — `product.md`의 "판정과 무관한 장식 오브젝트는 동기화 대상에서 제외" 원칙에 따라 서버와 동기화하지 않고 클라이언트가 로컬로만 처리
- `scripts/autoload/`: `GameData`(공유 상태, 서버 필드와 이름을 맞춤), `SceneRouter`(화면 전환), `MockServer`(현재 서버 역할 — **서버 완성 후 `NetworkClient`로 교체할 대상**)

## 서버 구조 (앞으로 만들 것)

`MockServer.gd`가 하는 일을 그대로 Node.js로 옮긴다는 감각으로 나눈다.

- `index.js`: 웹소켓 서버 시작점, 연결 수립/해제 처리
- `rooms.js`: 방 생성, 입장, 목록 조회, 퇴장, 방 상태 관리 (`MockServer.gd`의 `create_room`/`join_room`/`list_rooms`/`return_to_lobby`에 대응)
- `gameLoop.js`: 카운트다운, 타이머, 새끼오리 배회/획득/추종/반납, 대시 판정, 감옥/구출/자동탈출, 승패 판정, 주기적 브로드캐스트 (`MockServer.gd`의 `_process` 이하 전체에 대응 — [api-spec.md](api-spec.md)의 "서버 판정 로직 요약" 참고)
- `messages.js`: 클라이언트 메시지 라우팅과 검증 ([api-spec.md](api-spec.md)의 클라이언트→서버 메시지 목록에 대응)
- `constants.js`: [api-spec.md](api-spec.md)의 "초기 게임 상수" 표를 그대로 옮긴다. 클라이언트 연출(쿨타임 게이지, 판정 반경 표시 등)과 어긋나지 않도록 값을 반드시 일치시킨다.

## 서버 연동 시 구현 순서

1. `constants.js`에 api-spec.md 상수 표를 옮긴다.
2. `rooms.js`로 방 생성/목록/입장/로비 상태 브로드캐스트를 구현한다.
3. `gameLoop.js`로 카운트다운→플레이 진입, 위치 브로드캐스트(`game:state`)를 구현한다.
4. 새끼오리 스폰·배회·자동 획득·추종·자동 반납을 구현한다(전부 위치 기반, 클라이언트 요청 없음).
5. `player:dash` 처리와 대시 경로-오리 겹침 판정, 감옥/구출/자동탈출을 구현한다.
6. 승패 판정(`game_ended`)과 로비 복귀를 구현한다.
7. 클라이언트의 `MockServer` 호출부를 `NetworkClient`(WebSocket)로 교체한다. `GameData` 필드는 그대로 두고 값을 채우는 주체만 바뀐다.

## 네이밍 규칙

- Godot 씬 파일은 역할이 보이게 `Player.tscn`, `GameWorld.tscn`, `Lobby.tscn`처럼 작성한다.
- GDScript 파일은 씬 이름과 맞춘다.
- 서버 메시지 타입은 `room:create`, `game:state`, `player:input`처럼 `영역:동작` 형식을 사용한다.
- 좌표는 서버와 클라이언트 모두 `{ "x": number, "y": number, "z": number }` 형식을 사용한다.
