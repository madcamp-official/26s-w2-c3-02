---
inclusion: always
---

# Project Structure

## 현재 상태

초기 기획 단계이다. `Docs/` 아래 문서가 먼저 준비되어 있으며, 실제 Godot 클라이언트와 Node.js 서버 코드는 이후 단계에서 추가한다.

예상 저장소 구조는 다음을 기준으로 한다.

```text
26s-w2-c3-02/
├─ README.md
├─ Docs/
│  ├─ product(reference).md      # 게임 목표, 규칙, MVP 범위
│  ├─ tech(reference).md         # LLM용 기술 스택/구현 규칙
│  ├─ structure(reference).md    # 저장소 구조와 문서 관계
│  ├─ api-spec(reference).md     # 웹소켓 메시지 규약
│  └─ tech-spec.md               # 기술 후보와 리스크 메모
├─ client/
│  └─ godot/
│     ├─ project.godot
│     ├─ scenes/
│     │  ├─ lobby/
│     │  ├─ game/
│     │  ├─ player/
│     │  ├─ duckling/
│     │  └─ ui/
│     ├─ scripts/
│     │  ├─ network/
│     │  ├─ player/
│     │  ├─ game/
│     │  └─ ui/
│     └─ assets/
│        ├─ characters/
│        ├─ environment/
│        ├─ props/
│        └─ audio/
└─ server/
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

- **product(reference).md**는 게임이 무엇을 해야 하는지 설명하는 기준 문서이다.
- **tech(reference).md**는 LLM이 구현할 때 따라야 하는 기술 선택과 제약을 정리한다.
- **structure(reference).md**는 폴더와 파일을 어디에 둘지 정한다.
- **api-spec(reference).md**는 Godot 클라이언트와 Node.js 서버가 주고받는 메시지 형식을 정의한다.
- **tech-spec.md**는 기술 조사와 의사결정 메모로 유지한다.

## 클라이언트 구조

- `scenes/lobby/`: 방 생성, 방 입장, 캐릭터 선택 화면
- `scenes/game/`: 연못 맵, 게임 월드 루트 씬
- `scenes/player/`: 오리, 악어, 수달, 거위 등 플레이어 캐릭터 씬
- `scenes/duckling/`: 새끼오리 스폰 및 운반 대상 씬
- `scenes/ui/`: 타이머, 점수, 결과 화면, 모바일 조작 UI
- `scripts/network/`: 웹소켓 연결, 메시지 송수신, 서버 상태 반영
- `scripts/game/`: 게임 상태, 스폰, 점수, 승패 UI 처리

## 서버 구조

- `index.js`: 웹소켓 서버 시작점
- `rooms.js`: 방 생성, 입장, 퇴장, 방 상태 관리
- `gameLoop.js`: 타이머, 스폰, 승패 판정, 주기적 브로드캐스트
- `messages.js`: 클라이언트 메시지 라우팅과 검증
- `constants.js`: 게임 시간, 이동 속도, 감옥 시간, 목표 점수 등 상수

## 구현 순서

1. Godot에서 단일 플레이어 이동과 연못 맵을 만든다.
2. Node.js 웹소켓 서버와 연결한다.
3. 여러 플레이어의 위치를 동기화한다.
4. 새끼오리 스폰, 획득, 둥지 반납을 구현한다.
5. 술래 잡기, 감옥, 탈출 규칙을 구현한다.
6. 로비, 방 코드, 게임 시작/종료 UI를 붙인다.
7. 모바일 화면과 데스크탑 화면을 함께 테스트한다.

## 네이밍 규칙

- Godot 씬 파일은 역할이 보이게 `Player.tscn`, `GameWorld.tscn`, `Lobby.tscn`처럼 작성한다.
- GDScript 파일은 씬 이름과 맞춘다.
- 서버 메시지 타입은 `room:create`, `game:state`, `player:input`처럼 `영역:동작` 형식을 사용한다.
- 좌표는 서버와 클라이언트 모두 `{ "x": number, "y": number, "z": number }` 형식을 사용한다.
