---
inclusion: always
---

# Realtime API Spec

## 개요

이 프로젝트는 REST API보다 **웹소켓 기반 실시간 메시지**가 핵심이다. Godot 클라이언트는 Node.js 서버에 WebSocket으로 접속하고, 서버는 방 상태와 게임 상태를 주기적으로 브로드캐스트한다.

MVP 단계에서는 로그인 없이 임시 닉네임과 방 코드만 사용한다.

**이 문서는 클라이언트의 `client/scripts/autoload/MockServer.gd`(현재 서버 역할을 대신하는 목 구현)가 실제로 구현하고 있는 계약을 기준으로 작성됐다.** 서버를 구현할 때는 `MockServer.gd`를 참고 구현으로 삼고, 여기 정의된 메시지/필드/판정 상수와 동일하게 맞춘다. `GameData.gd`가 클라이언트 쪽 상태 계약(필드 이름)을 그대로 담고 있으므로, 서버가 준비되면 `MockServer`를 `NetworkClient`(WebSocket)로 교체하기만 하면 되도록 필드명을 반드시 일치시킨다.

## 연결

```text
ws://localhost:8080/ws
```

배포 환경에서는 서버 호스트에 맞춰 `wss://.../ws`를 사용한다.

## 공통 메시지 형식

모든 메시지는 JSON 문자열로 주고받는다.

```json
{
  "type": "message:type",
  "requestId": "optional-client-request-id",
  "roomId": "1234",
  "payload": {}
}
```

| 필드 | 설명 |
|---|---|
| `type` | 메시지 종류. `room:create`, `player:input` 같은 형식 |
| `requestId` | 클라이언트 요청 추적용 선택 필드 |
| `roomId` | 방 코드. 방 생성 전에는 생략 가능 |
| `payload` | 실제 데이터 |

## 핵심 설계 원칙 (MockServer 기준)

실제 구현에서 클라이언트는 **이동 입력과 대시(경찰 전용) 입력만** 서버에 보낸다. 새끼오리 획득/반납, 잡기(수감), 구출은 전부 **위치 기반으로 서버가 매 틱 자동 판정**하며, 별도의 클라이언트 액션 메시지가 없다. 즉:

- 오리가 새끼오리 반경 안에 들어오면 서버가 알아서 `carried` 상태로 전환한다 (`duckling:pickup` 같은 명시적 요청 없음).
- 오리가 둥지 반경 안에서 새끼오리를 데리고 있으면 서버가 알아서 반납 처리한다 (`duckling:deliver` 요청 없음).
- 경찰의 대시 경로(사각형 판정 영역)에 오리가 겹치면 서버가 알아서 수감 처리한다. 클라이언트는 "대시를 시작했다"는 사실과 방향만 보내고, 겹침 판정 자체는 서버가 위치로 계산한다.
- 갇히지 않은 오리가 감옥 근처(`RESCUE_RADIUS`)에 일정 시간(`RESCUE_DURATION`) 머무르면 서버가 자동으로 구출 진행률을 올리고, 다 차면 전원 석방한다. 이것도 명시적 요청이 없다.

서버를 구현할 때 이 자동 판정 로직을 `game:state` 브로드캐스트 틱 안에서 수행하면 된다 (아래 "서버 판정 로직 요약" 참고).

## 공통 객체

### Player

```json
{
  "playerId": "p1",
  "nickname": "duck01",
  "team": "duck",
  "character": "duck",
  "isMock": false,
  "position": { "x": 0, "y": 0, "z": 0 },
  "rotationY": 0,
  "state": "idle",
  "carryingDucklingId": null,
  "jailedUntil": null,
  "jailRemaining": null
}
```

| 필드 | 설명 |
|---|---|
| `isMock` | 클라이언트가 로컬 테스트용으로 추가한 가짜 플레이어인지 여부. 실서버 연동 시 항상 `false`로 취급하거나 필드 자체를 생략해도 된다. |
| `carryingDucklingId` | 스키마상 예약된 필드. 현재 MVP 구현은 개별 오리가 아니라 서버 내부 캐리어 큐로 관리하므로 항상 `null`이다. 새끼오리가 누구에게 딸려가는지는 `Duckling.carrierPlayerId` 쪽으로 확인한다. |
| `jailedUntil` | 스키마상 예약된 필드(타임스탬프 기반 해제 시각). 현재 MVP는 아래 `jailRemaining`(초 단위 카운트다운)을 대신 사용한다. 실서버 구현 시 둘 중 하나로 통일해도 무방하나, 클라이언트는 `jailRemaining`을 읽는다. |
| `jailRemaining` | **오리가 1명만 남아 있고 그 오리가 수감된 경우에만** 존재하는 필드(초). 매 틱 감소하다 0이 되면 자동 석방한다. 오리가 2명 이상이면 이 필드는 아예 없고, 대신 다른 오리가 구출해야 한다(구출 로직은 아래 참고). |

### Duckling

```json
{
  "ducklingId": "d1",
  "position": { "x": 4, "y": 0, "z": -2 },
  "state": "spawned",
  "carrierPlayerId": null,
  "deliveryBatchId": null
}
```

| 필드 | 설명 |
|---|---|
| `deliveryBatchId` | `state == "delivering"`일 때만 존재. 같은 타이밍에 반납된 새끼오리들을 하나의 알림(`duckling_delivered` 이벤트)으로 묶기 위한 내부 식별자. |

### GameState

```json
{
  "roomId": "1234",
  "phase": "playing",
  "countdownSeconds": 0,
  "remainingSeconds": 172,
  "score": 1,
  "targetScore": 5,
  "players": [],
  "ducklings": [],
  "winner": null,
  "endReason": null,
  "rescueProgress": 0.0,
  "activeRescuerId": ""
}
```

| 필드 | 설명 |
|---|---|
| `countdownSeconds` | `phase == "countdown"`일 때 남은 정수 초. 그 외에는 0. |
| `endReason` | `phase == "ended"`일 때만 값이 있다. `"duck_goal"` \| `"time_up"` \| `"all_ducks_jailed"` |
| `rescueProgress` | 0.0~1.0. 현재 구출 시도 중인 진행률(HUD 게이지용). 구출 중이 아니면 0. |
| `activeRescuerId` | 현재 구출을 진행 중인(감옥 근처에 머무는) 오리의 `playerId`. 없으면 빈 문자열. |

## ENUM

| 필드 | 값 |
|---|---|
| `team` | `duck`, `tagger` |
| `character` | `duck`, `aligator` — MVP는 캐릭터가 팀에 고정된다(오리 팀=`duck`, 경찰 팀=`aligator`). 캐릭터 스킨 선택은 초기 범위 밖이다. |
| `phase` | `lobby`, `countdown`, `playing`, `ended` |
| `player.state` | `idle`, `jailed` — MVP 구현에는 `moving`/`carrying` 상태를 별도로 두지 않는다(움직임 여부는 위치 변화로 클라이언트가 자체 판단, 캐리 여부는 `Duckling.carrierPlayerId`로 판단). |
| `duckling.state` | `spawned`, `carried`, `delivering`, `delivered` — 반납 판정 즉시 사라지지 않고, 둥지까지 헤엄쳐 들어가는 `delivering` 중간 상태를 거친 뒤 `delivered`가 된다. |
| `winner` | `duck`, `tagger`, `null` |
| `endReason` | `duck_goal`, `time_up`, `all_ducks_jailed` |

## 클라이언트 → 서버

### `room:create`

방을 생성한다. 방 코드를 직접 지정할 수도 있고(빈 문자열이면 서버가 4자리 숫자 코드를 랜덤 생성), 방 이름을 지정할 수도 있다.

```json
{
  "type": "room:create",
  "requestId": "req-1",
  "payload": {
    "nickname": "host",
    "roomId": "",
    "roomName": "우리방"
  }
}
```

- `roomId`를 지정하면 정확히 4자리 숫자여야 한다. 아니면 `INVALID_MESSAGE`, 이미 쓰이는 코드면 `ROOM_CODE_IN_USE`.
- 방을 만든 사람은 자동으로 오리 팀(`duck`)으로 로비에 입장한다. 캐릭터/팀은 이후 `player:selectTeam`으로 바꿀 수 있다.

서버 응답: `room:joined`

### `room:list`

참가 가능한 공개/비공개 방 목록을 요청한다(로비 화면의 "게임 목록").

```json
{
  "type": "room:list",
  "requestId": "req-0",
  "payload": {}
}
```

서버 응답: `room:list`

### `room:join`

기존 방에 입장한다. 비공개 방은 `joinCode`가 필요하다.

```json
{
  "type": "room:join",
  "requestId": "req-2",
  "roomId": "1234",
  "payload": {
    "nickname": "player2",
    "joinCode": ""
  }
}
```

서버 응답: `room:joined` 또는 `error`(`ROOM_NOT_FOUND`, `INVALID_JOIN_CODE`, `ROOM_FULL`, `GAME_ALREADY_STARTED`)

### `player:selectTeam`

로비에서 팀(오리/경찰)을 바꾼다. 캐릭터는 팀에 종속되므로 별도 캐릭터 선택 메시지는 없다(팀이 `tagger`면 캐릭터는 자동으로 `aligator`, `duck`이면 `duck`).

```json
{
  "type": "player:selectTeam",
  "roomId": "1234",
  "payload": {
    "team": "tagger"
  }
}
```

경찰(`tagger`) 자리는 방당 1명(`MVP_TAGGER_COUNT`)까지만 허용된다. 이미 차 있으면 요청은 무시되거나(현재 클라이언트 동작) `INVALID_ACTION`으로 응답한다.

### `player:setNickname`

로비에서 닉네임을 바꾼다.

```json
{
  "type": "player:setNickname",
  "roomId": "1234",
  "payload": {
    "nickname": "새로운닉네임"
  }
}
```

### `game:start`

호스트가 게임을 시작한다. 경찰 1명 + 오리 1~2명(`MVP_DUCK_COUNT`)이 모두 채워져 있어야 시작 가능하다.

```json
{
  "type": "game:start",
  "roomId": "1234",
  "payload": {}
}
```

시작하면 서버는 `countdown` 페이즈로 전환하고(`COUNTDOWN_SECONDS`초), 새끼오리를 스폰한 뒤 카운트다운이 끝나면 `playing`으로 전환하며 `game_started` 이벤트를 보낸다.

### `player:input`

플레이어 이동 입력을 보낸다. Godot 클라이언트는 즉시 로컬 이동을 반영하고, 위치를 주기적으로 서버에 보고한다.

```json
{
  "type": "player:input",
  "roomId": "1234",
  "payload": {
    "position": { "x": 12.3, "y": 0, "z": -4.1 },
    "rotationY": 1.57,
    "sequence": 120
  }
}
```

> MVP는 클라이언트 권위(client-authoritative) 이동을 쓴다. 서버는 받은 좌표를 그대로 신뢰하고 다른 판정(획득/반납/수감/구출)에 사용한다. 치팅 방지가 필요해지면 이동 검증 로직을 추가로 도입한다.

### `player:dash`

경찰(`tagger`)이 대시를 시작한다. 클라이언트는 대시 시작/도착 지점과 지속 시간만 계산해서 보내고("입력 보고"), 그 경로에 오리가 겹치는지 판정하는 건 전적으로 서버 몫이다(`MockServer.gd`의 `begin_dash()` 참고 — 이전엔 이 판정이 클라이언트의 월드 씬 스크립트에 있었다가 서버 쪽으로 옮겨졌다).

```json
{
  "type": "player:dash",
  "roomId": "1234",
  "payload": {
    "startPosition": { "x": 10, "y": 0, "z": 5 },
    "endPosition": { "x": 19.8, "y": 0, "z": 5 },
    "duration": 0.25
  }
}
```

- 쿨타임(`DASH_COOLDOWN`) 중에는 클라이언트가 먼저 막지만, 서버도 마지막 대시 시각을 기준으로 재검증하는 것을 권장한다(치팅 방지).
- 서버는 이 메시지를 받으면 시작/도착 좌표로 만든 경로(폭 `DASH_CATCH_HALF_WIDTH`)를 `duration`초 동안 유지하며 **매 틱** 오리 위치와 비교한다(한 번만 검사하는 게 아니라 대시가 지속되는 동안 계속 검사 — 오리가 대시 도중 경로 안으로 들어오는 경우도 놓치지 않기 위해서다). 겹치는 순간 즉시 수감 처리하고 `player_jailed` 이벤트를 보낸다. 지연 없이 "부딪힌 순간 = 수감"이 되도록 구현하는 것이 중요하다(연출상 그렇게 맞춰져 있음).

### `room:leave` / `game:returnToLobby`

게임 종료 후 로비로 돌아가거나 방을 나갈 때 사용한다(결과 화면의 "다시 하기"/"나가기"). 로비로 돌아가면 서버는 모든 플레이어 상태를 `idle`로 초기화하고 스폰 위치로 되돌린다.

```json
{
  "type": "game:returnToLobby",
  "roomId": "1234",
  "payload": {}
}
```

## 서버 → 클라이언트

### `room:joined`

방 입장 성공을 알린다.

```json
{
  "type": "room:joined",
  "roomId": "1234",
  "payload": {
    "playerId": "p1",
    "isHost": true,
    "state": {}
  }
}
```

### `room:list`

`room:list` 요청에 대한 응답. 참가 가능한 방 목록을 내려준다.

```json
{
  "type": "room:list",
  "payload": {
    "rooms": [
      {
        "roomId": "1234",
        "roomName": "Mock Duck",
        "hostNickname": "Mock Duck",
        "playerCount": 1,
        "isPrivate": true
      }
    ]
  }
}
```

`isPrivate == true`인 방은 목록 클릭 시 방 코드가 자동으로 입력창에 채워지되, 참가하려면 `joinCode`가 별도로 필요할 수 있다(현재 목 데이터 기준으로는 방 코드 자체가 참가 코드와 동일).

### `room:state`

로비 상태를 브로드캐스트한다.

```json
{
  "type": "room:state",
  "roomId": "1234",
  "payload": {
    "players": [],
    "hostPlayerId": "p1"
  }
}
```

### `game:state`

게임 중 서버 권위 상태를 주기적으로 브로드캐스트한다(`STATE_TICK_RATE`Hz). "공통 객체 > GameState" 스키마를 그대로 따른다.

```json
{
  "type": "game:state",
  "roomId": "1234",
  "payload": {
    "roomId": "1234",
    "phase": "playing",
    "countdownSeconds": 0,
    "remainingSeconds": 172,
    "score": 1,
    "targetScore": 5,
    "players": [],
    "ducklings": [],
    "winner": null,
    "endReason": null,
    "rescueProgress": 0.35,
    "activeRescuerId": "p3"
  }
}
```

### `game:event`

점수, 감옥, 구출처럼 UI 토스트/효과가 필요한 일회성 이벤트를 알린다.

```json
{
  "type": "game:event",
  "roomId": "1234",
  "payload": {
    "event": "player_jailed",
    "playerId": "p2"
  }
}
```

이벤트 후보(실제 클라이언트가 처리하는 것만 나열):

| event | payload 필드 | 설명 |
|---|---|---|
| `game_started` | (없음) | 카운트다운이 끝나고 실제 플레이가 시작됨 |
| `player_jailed` | `playerId` | 오리가 대시에 맞아 감옥으로 이동됨. 들고 있던 새끼오리는 그 자리에 흩뿌려지며 `spawned` 상태로 되돌아간다. |
| `rescue_started` | `rescuerId`(선택: `rescuerName`) | 자유로운 오리가 감옥 근처(`RESCUE_RADIUS`)에 머물기 시작해 구출 진행이 시작됨 |
| `player_rescued` | `targetId`, `rescuerId`, `releasePosition` | 구출 진행률이 다 차서 수감된 오리(들)가 전원 석방됨 |
| `player_released` | `playerId`, `releasePosition` | 오리가 1명뿐인 상황에서 `jailRemaining` 타이머가 다 돼 자동 석방됨(구출자 없음) |
| `duckling_delivered` | `ducklingId`, `count`, `playerId`(선택), `playerName`(선택) | 같은 타이밍에 반납된 새끼오리 묶음이 둥지에 도착함. `count`는 묶음 크기 |
| `game_ended` | `winner`, `reason` | 게임 종료. `winner`/`reason`은 GameState의 `winner`/`endReason`과 동일한 값 |

> 참고: `duckling_spawned`, `duckling_picked`, `player_jailed`에 대응하는 `player:tag` 같은 별도의 "시도" 메시지는 MVP 구현에 없다. 획득은 조용히 상태만 바뀌고(다음 `game:state` 틱에 반영), 대시로 인한 수감만 즉시 이벤트로 알린다.

### `error`

요청 처리 실패를 알린다.

```json
{
  "type": "error",
  "requestId": "req-2",
  "payload": {
    "code": "ROOM_NOT_FOUND",
    "message": "방을 찾을 수 없습니다."
  }
}
```

## 에러 코드

| code | 설명 |
|---|---|
| `INVALID_MESSAGE` | 메시지 형식이 잘못됨 (예: 방 코드가 4자리 숫자가 아님) |
| `ROOM_NOT_FOUND` | 방이 없음 |
| `ROOM_CODE_IN_USE` | `room:create` 시 지정한 방 코드가 이미 사용 중 |
| `ROOM_FULL` | 방 인원이 가득 참(`MAX_PLAYERS` 초과) |
| `INVALID_JOIN_CODE` | 비공개 방 참가 코드가 틀림 |
| `GAME_ALREADY_STARTED` | 이미 게임이 시작됨 |
| `NOT_HOST` | 호스트만 가능한 요청 |
| `INVALID_ACTION` | 현재 상태에서 불가능한 행동 (예: 경찰 자리가 이미 차 있는데 `tagger`로 전환 시도) |
| `SERVER_ERROR` | 서버 내부 오류 |

## 초기 게임 상수

`MockServer.gd`에 정의된 실제 값 기준. 서버 구현 시 동일한 값을 사용해야 클라이언트 연출(쿨타임 게이지, 판정 반경 등)과 어긋나지 않는다.

| 이름 | 기본값 | 설명 |
|---|---:|---|
| `MAX_PLAYERS` | 3 | 방 최대 인원 (MVP: 경찰 1 + 오리 1~2) |
| `TAGGER_COUNT` | 1 | 방당 경찰 정원 |
| `DUCK_COUNT_MIN` / `DUCK_COUNT_MAX` | 1 / 2 | 오리 인원 범위 |
| `GAME_DURATION_SECONDS` | 180 | 제한 시간 |
| `TARGET_SCORE` | 5 | 오리 팀 목표 반납 수 |
| `COUNTDOWN_SECONDS` | 3 | 게임 시작 전 카운트다운 |
| `INITIAL_DUCKLING_COUNT` | `TARGET_SCORE + 2` (=7) | 게임 시작 시 스폰되는 새끼오리 수 |
| `JAIL_SECONDS` | 8 | **오리가 1명뿐일 때만** 적용되는 자동 탈출 시간(초). 오리가 2명 이상이면 대신 아래 구출 규칙이 적용되며 자동 탈출은 없다. |
| `RESCUE_RADIUS` | 11.0 | 자유로운 오리가 감옥 중심으로부터 이 거리 안에 있어야 구출이 진행됨 |
| `RESCUE_DURATION` | 3.0 | 구출 진행이 다 차기까지 걸리는 시간(초). 진행 중 구출자가 반경을 벗어나거나 다른 오리로 바뀌면 진행률이 리셋된다. |
| `ALL_JAILED_END_DELAY` | 0.2 | 오리가 2명 이상일 때, 마지막 오리가 수감된 뒤 승리 메세지(`game_ended`)를 보내기 전 대기 시간(초). 수감 자체는 이 대기 없이 즉시 일어난다. |
| `JAIL_RELEASE_RADIUS` | 16.0 | 석방(자동 탈출/구출) 시 감옥 중심으로부터 이 반경의 원 위 랜덤 지점으로 이동 |
| `PICKUP_DISTANCE` | 2.4 | 오리와 새끼오리 사이, 이 거리 안이면 자동 획득 |
| `DELIVER_DISTANCE` | 6.0 | 오리와 (가장 가까운) 둥지 사이, 이 거리 안이면 자동 반납 시작 |
| `NEST_POSITIONS` | `(-58.5, 1.68, 58.5)`, `(58.5, 1.68, -58.5)` | 둥지가 2곳이며, 반납 시 더 가까운 쪽으로 판정한다 |
| `DASH_DISTANCE` | 9.8 | 경찰 대시 이동 거리(유닛) |
| `DASH_DURATION` | 0.25 | 대시 지속 시간(초) |
| `DASH_COOLDOWN` | 5.0 | 대시 쿨타임(초) |
| `DASH_CATCH_HALF_WIDTH` | 4.0 | 대시 경로 판정 사각형의 폭(경로 중심선으로부터 좌우 각각 이 거리 이내면 수감) |
| `STATE_TICK_RATE` | 10 | 초당 `game:state` 브로드캐스트 횟수 |
| `ROOM_CODE_LENGTH` | 4 | 방 코드는 4자리 숫자(`0-9`)만 사용한다. 영문 없음. |

## 서버 판정 로직 요약

실제 서버(`MockServer.gd`)가 매 틱 수행하는 순서. 새 백엔드를 구현할 때 참고한다.

1. **카운트다운**: `phase == "countdown"`이면 `COUNTDOWN_SECONDS`에서 매초 감소시키며 `countdownSeconds`만 업데이트해 브로드캐스트하고, 0이 되면 `playing`으로 전환 + 플레이어를 역할별 랜덤 스폰 위치로 배치 + `game_started` 이벤트.
2. **타이머**: `remainingSeconds`를 1초마다 감소. 0이 되면 `game_ended(winner="tagger", reason="time_up")`.
3. **새끼오리 배회**: `spawned` 상태의 새끼오리를 브라운 운동으로 이동시키되, 등록된 장애물(바위/덤불/나무/감옥 섬) 반경 밖으로 밀어낸다.
4. **획득 판정**: 오리 팀 플레이어와 `spawned` 새끼오리 사이 거리가 `PICKUP_DISTANCE` 이하면 `carried`로 전환하고 해당 플레이어의 캐리 큐에 추가.
5. **추종 이동**: 캐리 큐에 든 새끼오리들을 플레이어 뒤로 한 줄로 따라오게 이동시킨다(정지 중이면 플레이어 주변을 천천히 도는 대형으로 전환).
6. **반납 판정**: 캐리 큐가 있는 플레이어가 (가장 가까운) 둥지로부터 `DELIVER_DISTANCE` 이내면, 큐에 있던 새끼오리 전체를 `delivering` 상태로 전환하고 배치 ID를 부여한다. 즉시 점수를 주지 않는다.
7. **반납 애니메이션**: `delivering` 상태의 새끼오리를 둥지 좌표로 이동시키다가 도착하면 잠깐 머문 뒤(`NEST_SETTLE_TIME`) `delivered`로 전환 + 점수 +1. 같은 배치가 전부 도착하면 `duckling_delivered` 이벤트 1회 발송. 점수가 `TARGET_SCORE`에 도달하면 `game_ended(winner="duck", reason="duck_goal")`.
8. **대시 판정**: `player:dash` 메시지를 받으면 시작/도착 좌표로 만든 선분을 `duration`초 동안 활성 대시 목록에 등록하고, 그 동안 매 틱 수감되지 않은 모든 오리와의 최단 거리가 `DASH_CATCH_HALF_WIDTH` 이하인지 확인한다. 겹치는 틱에 그 오리를 즉시 수감(`jail_player`) + `player_jailed` 이벤트. 이때 들고 있던 새끼오리는 잡힌 자리 근처에 흩뿌려지며 다시 `spawned`로 돌아간다.
9. **자동 탈출(오리 1명)**: 오리가 정확히 1명이고 그 오리가 수감 중이면 `jailRemaining`을 매 틱 감소시키고, 0이 되면 `JAIL_RELEASE_RADIUS` 원 위 랜덤 위치로 석방(`player_released`).
10. **구출(오리 2명 이상)**: 오리가 2명 이상이고 1명 이상 수감돼 있으면, 갇히지 않은 오리 중 감옥 중심 `RESCUE_RADIUS` 이내에 있는 첫 번째 오리를 "구출자"로 삼아 `rescue_started` 이벤트(새 구출자로 바뀔 때만) 후 `RESCUE_DURATION` 동안 `rescueProgress`를 채운다. 구출자가 반경을 벗어나거나 다른 사람으로 바뀌면 진행률이 리셋된다. 다 차면 수감된 오리 전원을 `JAIL_RELEASE_RADIUS` 원 위 각자 다른 랜덤 위치로 석방(`player_rescued`).
11. **전원 수감 종료**: 오리가 2명 이상이고 방금 마지막 오리까지 수감됐다면, 수감 자체는 8번에서 즉시 처리하되 승리 메세지(`game_ended(winner="tagger", reason="all_ducks_jailed")`)는 `ALL_JAILED_END_DELAY`초 뒤에(그 사이 구출이 일어나지 않았을 때만) 보낸다.
12. **브로드캐스트**: 위 판정을 모두 반영한 뒤 `STATE_TICK_RATE` 주기로 `game:state`를 전송한다.

## MVP 스코프에서 의도적으로 뺀 것

- `duckling:pickup` / `duckling:deliver` / `player:tag` 같은 "시도" 메시지 — 전부 위치 기반 자동 판정으로 대체됨(위 참고).
- 캐릭터 스킨 선택(수달·거위 등) — 현재는 팀에 캐릭터가 고정된다(`duck`/`aligator`뿐).
- 방 6인 이상 지원 — 현재 MVP는 경찰 1 + 오리 최대 2, 총 3명 고정.
