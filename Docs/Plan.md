# 클라이언트 병렬 개발 계획 (2인)

## 이 계획의 범위

- **대상:** Godot 클라이언트만. **서버(Node.js)는 이 계획의 범위 밖**이다.
- **서버 공백 처리:** 서버가 채워야 할 상태(플레이어 위치, 새끼오리, 점수, 타이머, 감옥)는 **Mock 데이터**로 대체한다. 목표는 *서버 없이도 클라이언트를 끝까지 개발하고 시연할 수 있는 상태*를 만드는 것이다.
- **나중에 서버가 붙을 때:** Mock을 실제 네트워크 클라이언트로 교체만 하면 되도록, 데이터 계약(`GameData`)을 `api-spec.md`의 필드 이름과 동일하게 맞춘다.

### 목표 화면 흐름

```text
메인 화면 → 로비(방 생성/입장·준비·시작) → 인게임(이동·새끼오리 인솔·잡기/감옥) → 결과 화면 → 메인
```

---

## 병렬 작업 핵심 원칙 (Godot 충돌 방지)

Godot에서 머지 충돌은 거의 항상 **같은 파일을 두 명이 동시에 편집**할 때 난다. 특히 `.tscn`(노드 ID·`load_steps`·`ext_resource` 번호)과 `project.godot`이 위험하다. 그래서 다음을 규칙으로 한다.

1. **디렉터리 단위로 파일을 소유한다.** 자기 디렉터리 밖의 파일은 편집하지 않는다. (Git 충돌은 파일 단위 → 서로 다른 디렉터리는 거의 안 부딪힌다.)
2. **하나의 `.tscn`은 한 사람만 편집한다.** 같은 씬을 둘이 동시에 열지 않는다.
3. **`project.godot`은 Day 0에 함께 세팅하고 그 뒤로 동결한다.** InputMap·창 설정·오토로드 등록·메인 씬을 한 번에 다 넣어두고, 이후에는 원칙적으로 건드리지 않는다.
4. **씬 합성(화면 조립)은 `SceneRouter` 한 곳에서만 한다.** 씬끼리 서로 `instance` 하지 않는다. (예: 월드 씬이 HUD 씬을 품지 않는다. Router가 둘을 나란히 올린다.)
5. **공유 상태는 `GameData` 오토로드 인터페이스로만 주고받는다.** Day 0에 필드·시그널을 확정한 뒤, B는 이 파일을 **읽기만** 하고 편집하지 않는다.
6. **단독 테스트는 F6(현재 씬 실행)로 한다.** 자기 씬만 바로 실행하면 `project.godot`의 `main_scene`을 바꿀 필요가 없다.

---

## 폴더 & 소유권 맵

```text
client/
├─ project.godot                  [공동] Day 0 세팅 후 동결
├─ scenes/
│  ├─ boot/        Boot.tscn       [공동] Day 0 생성, 이후 거의 안 건드림
│  ├─ menu/        MainMenu / Lobby / Result .tscn      [A]
│  ├─ hud/         GameHUD.tscn                          [A]
│  ├─ world/       Game / Pond .tscn                     [B]
│  ├─ player/      Player.tscn                           [B]
│  └─ duckling/    Duckling.tscn                         [B]
├─ scripts/
│  ├─ autoload/    GameData / SceneRouter / MockServer .gd   [공동 정의 → A 소유, B 읽기만]
│  ├─ menu/                                              [A]
│  ├─ hud/                                               [A]
│  ├─ world/                                             [B]
│  ├─ player/                                            [B]
│  └─ duckling/                                          [B]
└─ assets/
   ├─ duck/  aligator/                                   [B]
   └─ ui/    (아이콘·폰트·버튼 이미지)                    [A]
```

| 영역 | 담당 | 편집 파일 | 공유 파일 접근 |
|---|---|---|---|
| 화면 흐름·메뉴·HUD·반응형 UI | **A** | `scenes/menu`, `scenes/hud`, `scripts/menu`, `scripts/hud`, `assets/ui`, `scripts/autoload` | `GameData` 읽기+시그널, `SceneRouter`·`MockServer` 소유 |
| 인게임 월드·캐릭터·새끼오리 | **B** | `scenes/world`, `scenes/player`, `scenes/duckling`, `scripts/world`, `scripts/player`, `scripts/duckling`, `assets/duck`, `assets/aligator` | `GameData` **읽기만** |

> 핵심: **B는 병렬 작업 중 공유 파일(`project.godot`, `autoload/`)을 편집하지 않는다.** 새 입력 액션·오토로드가 필요하면 Day 0에 미리 다 넣거나, A에게 요청해 A가 반영한다. 이렇게 하면 B의 커밋은 항상 자기 디렉터리 안에서만 발생한다.

---

## Day 0 — 공동 선행 작업 (페어, 1회)

이 단계만 함께 앉아서 하고, 끝나면 계약을 커밋·동결한 뒤 갈라진다.

1. **폴더 구조 생성** — 위 소유권 맵대로 빈 디렉터리를 만든다.
2. **`project.godot` 세팅 (이후 동결)**
   - **InputMap:** `move_up` `move_down` `move_left` `move_right`(WASD+방향키+터치), `interact`(획득/반납/잡기/구출 공용 액션), `pause`.
   - **창/표시:** 가로 모드 고정, 뷰포트 스트레치(`canvas_items`), 최소 해상도, 모바일 `sensor_landscape`.
   - **오토로드 등록:** `GameData`, `SceneRouter`, `MockServer`.
   - **메인 씬:** `scenes/boot/Boot.tscn`.
3. **`GameData` 계약 확정 (동결)** — `api-spec.md`와 같은 필드로 정의. 이후 B는 읽기만.

   ```gdscript
   # scripts/autoload/GameData.gd (autoload: GameData)
   extends Node

   var local_player_id: String = ""
   var phase: String = "lobby"          # lobby | countdown | playing | ended
   var remaining_seconds: int = 0
   var score: int = 0
   var target_score: int = 5
   var winner = null                    # "duck" | "tagger" | null
   var players: Array = []              # {playerId, team, character, position{x,y,z}, rotationY, state, carryingDucklingId, jailedUntil}
   var ducklings: Array = []            # {ducklingId, position{x,y,z}, state, carrierPlayerId}

   signal room_state_changed
   signal game_state_changed
   signal game_event(event: String, data: Dictionary)
   ```

4. **`MockServer` 스켈레톤** — 타이머로 가짜 `game:state`/`game:event`를 만들어 `GameData`를 채우고 시그널을 쏜다. (예: 새끼오리 몇 마리 스폰, 타이머 감소, 가상 플레이어 1명이 원을 그리며 이동.) 서버 자리를 이 파일이 대신한다.
5. **`SceneRouter` 스켈레톤** — 화면 전환 담당. 인게임 진입 시 **B의 `Game.tscn`과 A의 `GameHUD.tscn`을 나란히 올려** 합성한다. (씬끼리 서로 참조하지 않게 하는 유일한 합성 지점.)

   ```gdscript
   # scripts/autoload/SceneRouter.gd (autoload: SceneRouter)
   extends Node
   # go_to("main_menu" | "lobby" | "game" | "result")
   # "game" 진입 시 world(3D) + hud(CanvasLayer)를 한 스크린 노드 아래 형제로 add_child
   ```

**Day 0 완료 기준:** Boot 실행 → MainMenu 표시 → (더미 버튼으로) 인게임 진입 시 B의 빈 월드와 A의 빈 HUD가 동시에 올라온다. 이 뼈대가 서면 갈라진다.

---

## A 트랙 — 화면 흐름 & UI - 조예준

**소유:** `scenes/menu`, `scenes/hud`, `scripts/menu`, `scripts/hud`, `assets/ui` + 오토로드(`SceneRouter`/`MockServer`/`GameData`).

- **메인 화면** (`MainMenu.tscn`): 닉네임 입력, 방 만들기 / 방 코드 입장 버튼 → `SceneRouter.go_to("lobby")`.
- **로비** (`Lobby.tscn`): 참가자 목록·준비 상태·방 코드 표시, 게임 시작 버튼. `GameData.room_state_changed`를 구독해 목록을 갱신(초기엔 MockServer가 가짜 참가자 제공).
- **결과 화면** (`Result.tscn`): 승패·개인 기록 표시, 다시 하기 / 메인으로.
- **인게임 HUD** (`GameHUD.tscn`, CanvasLayer): 남은 시간, 점수/목표, 감옥 상태, 모바일 조작 버튼(이동 패드·`interact` 버튼). `GameData.game_state_changed`/`game_event` 구독으로 갱신.
- **반응형 UI:** 가로 모드 고정, Anchor/Safe Area 기준 배치, PC·모바일 공통. (창 설정은 Day 0에 잡힌 값 사용.)
- **흐름 연결:** 모든 화면 전환을 `SceneRouter`로 처리. 버튼 → Router 호출만 하고, 실제 판정은 (나중에) 서버가 하므로 지금은 MockServer가 대신.

**A 단독 테스트:** 각 메뉴/HUD 씬을 F6로 실행, MockServer 데이터로 UI 갱신 확인.

---

## B 트랙 — 인게임 월드 & 캐릭터 - 박수현

**소유:** `scenes/world`, `scenes/player`, `scenes/duckling`, `scripts/world`, `scripts/player`, `scripts/duckling`, `assets/duck`, `assets/aligator`. **공유 파일은 읽기만.**

- **기존 `main.tscn` 리팩터링:** 현재 한 씬에 뭉쳐 있는 것을 분리한다.
  - `Pond.tscn`(연못 바닥·둥지·감옥·장애물) / `Player.tscn`(오리·악어 이동+카메라) / `Duckling.tscn`(새끼오리) / `Game.tscn`(월드 루트, 위 씬들을 조합).
  - 현재 [player.gd](client/scripts/player.gd)는 `scripts/player/`로 옮겨 재사용.
- **플레이어 캐릭터** (`Player.tscn`): WASD/방향 이동(이미 구현됨), 카메라, 오리/악어 모델 스왑. 로컬 조작은 즉시 반응.
- **원격 플레이어 표시:** `GameData.players`를 읽어 다른 플레이어를 스폰/이동. 위치는 보간(lerp)으로 부드럽게. (초기엔 MockServer의 가짜 플레이어로 검증.)
- **연못 맵** (`Pond.tscn`): 둥지·감옥 위치 마커, 이동 가능 영역, 장애물. 좌표는 서버와 공유할 `{x,y,z}` 기준.
- **새끼오리** (`Duckling.tscn`): `GameData.ducklings`를 읽어 스폰/획득/반납 상태를 시각화(있음/운반 중/반납됨). 판정 로직은 서버 몫이므로 지금은 상태 표시만.

**B 단독 테스트:** `Game.tscn`을 F6로 실행 → MockServer 데이터로 캐릭터·새끼오리가 움직이는지 확인. `project.godot`은 건드리지 않는다.

---

## 통합 지점 (충돌이 날 수 있는 유일한 곳)

1. **인게임 합성:** `SceneRouter`가 `Game.tscn`(3D) + `GameHUD.tscn`(CanvasLayer)을 한 스크린 노드의 형제로 올린다. → **A만** Router를 편집하고, B는 `Game.tscn` 경로만 A에게 알려준다. 씬 파일 자체는 서로 편집하지 않는다.
2. **데이터 계약:** 둘 다 `GameData`를 통해서만 상태를 읽는다. 필드가 바뀌어야 하면 **함께** 수정하고 즉시 공유한다(드물어야 정상).
3. **`project.godot`:** 새 InputMap 액션/오토로드가 필요하면 A가 반영하고 커밋을 먼저 푸시 → B가 pull. 같은 커밋에서 둘이 동시에 편집하지 않는다.

> 나머지 파일은 디렉터리로 분리돼 있어 병렬로 자유롭게 작업해도 충돌이 나지 않는다.

---

## 진행 순서 / 마일스톤

| 단계 | 내용 | A | B |
|---|---|---|---|
| **M0 (페어)** | Day 0 뼈대: 폴더·`project.godot`·`GameData`·`MockServer`·`SceneRouter`·`Boot` | 함께 | 함께 |
| **M1** | 화면 뼈대 서기 | MainMenu·Lobby·Result 전환 완성 | `main.tscn` → Pond/Player/Duckling/Game 분리 |
| **M2** | Mock 데이터로 채우기 | HUD가 타이머·점수·감옥 표시 | 캐릭터·새끼오리가 GameData 따라 움직임 |
| **M3** | 인게임 합성 통합 | Router가 Game+HUD 동시 로드 | Game.tscn을 통합 대상으로 정리 |
| **M4** | 반응형·마감 | 가로모드·Safe Area·모바일 조작 버튼 | 카메라·모델·맵 디테일, 보간 튜닝 |

**매 단계 끝:** 각자 자기 디렉터리 커밋 → 푸시 → 상대가 pull → F6로 상대 씬 한번 실행해 깨지지 않는지 확인.

---

## 체크리스트 (매일 종료 전)

- 내 커밋이 **내 디렉터리 밖 파일**을 건드리지 않았는가? (`git status`로 확인)
- `Game.tscn`/`GameHUD.tscn`을 각각 F6로 단독 실행했을 때 정상인가?
- Boot → 메뉴 → 인게임 진입 시 월드와 HUD가 함께 올라오는가?
- `GameData` 필드가 `api-spec.md`와 여전히 일치하는가?
- MockServer만으로 한 판 흐름(로비→인게임→결과)이 끊기지 않는가?

---

## 서버 연동 (범위 밖 / 추후)

이 계획은 클라이언트만 다룬다. 서버가 준비되면 **`MockServer`를 실제 `NetworkClient`(WebSocket)로 교체**하고, 동일한 `GameData` 필드/시그널을 채우게 한다. 클라이언트 코드(A·B의 화면·월드)는 `GameData`만 바라보므로 수정이 거의 필요 없다. 서버 메시지 규약은 `api-spec.md`를 기준으로 한다.
