---
inclusion: always
---

# Realtime API Spec

## 개요

이 프로젝트는 REST API보다 **웹소켓 기반 실시간 메시지**가 핵심이다. Godot 클라이언트는 Node.js 서버에 WebSocket으로 접속하고, 서버는 방 상태와 게임 상태를 주기적으로 브로드캐스트한다.

MVP 단계에서는 로그인 없이 임시 닉네임과 방 코드만 사용한다.

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
  "roomId": "ABCD",
  "payload": {}
}
```

| 필드 | 설명 |
|---|---|
| `type` | 메시지 종류. `room:create`, `player:input` 같은 형식 |
| `requestId` | 클라이언트 요청 추적용 선택 필드 |
| `roomId` | 방 코드. 방 생성 전에는 생략 가능 |
| `payload` | 실제 데이터 |

## 공통 객체

### Player

```json
{
  "playerId": "p1",
  "nickname": "duck01",
  "team": "duck",
  "character": "duck",
  "position": { "x": 0, "y": 0, "z": 0 },
  "rotationY": 0,
  "state": "idle",
  "carryingDucklingId": null,
  "jailedUntil": null
}
```

### Duckling

```json
{
  "ducklingId": "d1",
  "position": { "x": 4, "y": 0, "z": -2 },
  "state": "spawned",
  "carrierPlayerId": null
}
```

### GameState

```json
{
  "roomId": "ABCD",
  "phase": "playing",
  "remainingSeconds": 180,
  "score": 2,
  "targetScore": 5,
  "players": [],
  "ducklings": [],
  "winner": null
}
```

## ENUM

| 필드 | 값 |
|---|---|
| `team` | `duck`, `tagger` |
| `character` | `duck`, `crocodile`, `otter`, `goose` |
| `phase` | `lobby`, `countdown`, `playing`, `ended` |
| `player.state` | `idle`, `moving`, `carrying`, `jailed` |
| `duckling.state` | `spawned`, `carried`, `rescued` |
| `winner` | `duck`, `tagger`, `null` |

## 클라이언트 → 서버

### `room:create`

방을 생성한다.

```json
{
  "type": "room:create",
  "requestId": "req-1",
  "payload": {
    "nickname": "host",
    "character": "duck"
  }
}
```

서버 응답: `room:joined`

### `room:join`

기존 방에 입장한다.

```json
{
  "type": "room:join",
  "requestId": "req-2",
  "roomId": "ABCD",
  "payload": {
    "nickname": "player2",
    "character": "crocodile"
  }
}
```

서버 응답: `room:joined` 또는 `error`

### `player:selectCharacter`

로비에서 캐릭터를 바꾼다.

```json
{
  "type": "player:selectCharacter",
  "roomId": "ABCD",
  "payload": {
    "character": "otter"
  }
}
```

### `game:start`

호스트가 게임을 시작한다.

```json
{
  "type": "game:start",
  "roomId": "ABCD",
  "payload": {}
}
```

### `player:input`

플레이어 이동 입력을 보낸다. 모바일 터치와 데스크탑 클릭 모두 목표 방향 또는 목표 위치로 변환해 전송한다.

```json
{
  "type": "player:input",
  "roomId": "ABCD",
  "payload": {
    "moveDirection": { "x": 0.6, "z": -0.8 },
    "sequence": 120
  }
}
```

### `duckling:pickup`

오리가 새끼오리 획득을 시도한다.

```json
{
  "type": "duckling:pickup",
  "roomId": "ABCD",
  "payload": {
    "ducklingId": "d1"
  }
}
```

### `duckling:deliver`

오리가 둥지에서 새끼오리 반납을 시도한다.

```json
{
  "type": "duckling:deliver",
  "roomId": "ABCD",
  "payload": {
    "ducklingId": "d1"
  }
}
```

### `player:tag`

술래가 오리 잡기를 시도한다.

```json
{
  "type": "player:tag",
  "roomId": "ABCD",
  "payload": {
    "targetPlayerId": "p2"
  }
}
```

## 서버 → 클라이언트

### `room:joined`

방 입장 성공을 알린다.

```json
{
  "type": "room:joined",
  "roomId": "ABCD",
  "payload": {
    "playerId": "p1",
    "isHost": true,
    "state": {}
  }
}
```

### `room:state`

로비 상태를 브로드캐스트한다.

```json
{
  "type": "room:state",
  "roomId": "ABCD",
  "payload": {
    "players": [],
    "hostPlayerId": "p1"
  }
}
```

### `game:state`

게임 중 서버 권한 상태를 주기적으로 브로드캐스트한다.

```json
{
  "type": "game:state",
  "roomId": "ABCD",
  "payload": {
    "roomId": "ABCD",
    "phase": "playing",
    "remainingSeconds": 172,
    "score": 1,
    "targetScore": 5,
    "players": [],
    "ducklings": [],
    "winner": null
  }
}
```

### `game:event`

점수, 감옥, 스폰처럼 UI 효과가 필요한 이벤트를 알린다.

```json
{
  "type": "game:event",
  "roomId": "ABCD",
  "payload": {
    "event": "player_jailed",
    "playerId": "p2"
  }
}
```

이벤트 후보:

| event | 설명 |
|---|---|
| `duckling_spawned` | 새끼오리 생성 |
| `duckling_picked` | 새끼오리 획득 |
| `duckling_delivered` | 새끼오리 둥지 반납 |
| `player_jailed` | 오리 감옥 이동 |
| `player_released` | 오리 감옥 해제 |
| `game_started` | 게임 시작 |
| `game_ended` | 게임 종료 |

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
| `INVALID_MESSAGE` | 메시지 형식이 잘못됨 |
| `ROOM_NOT_FOUND` | 방이 없음 |
| `ROOM_FULL` | 방 인원이 가득 참 |
| `GAME_ALREADY_STARTED` | 이미 게임이 시작됨 |
| `NOT_HOST` | 호스트만 가능한 요청 |
| `INVALID_ACTION` | 현재 상태에서 불가능한 행동 |
| `SERVER_ERROR` | 서버 내부 오류 |

## 초기 게임 상수

| 이름 | 기본값 | 설명 |
|---|---:|---|
| `MAX_PLAYERS` | 6 | 방 최대 인원 |
| `GAME_DURATION_SECONDS` | 180 | 제한 시간 |
| `TARGET_SCORE` | 5 | 오리 팀 목표 반납 수 |
| `JAIL_SECONDS` | 8 | 감옥 유지 시간 |
| `TAG_DISTANCE` | 1.4 | 잡기 성공 거리 |
| `PICKUP_DISTANCE` | 1.2 | 새끼오리 획득 거리 |
| `DELIVER_DISTANCE` | 1.8 | 둥지 반납 거리 |
| `STATE_TICK_RATE` | 10 | 초당 상태 브로드캐스트 횟수 |