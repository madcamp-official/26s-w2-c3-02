# server

Node.js + `ws` 기반 웹소켓 서버. 방(room) 단위 인메모리 상태 관리, 실시간 위치/상태 동기화 담당.

메시지/필드 계약은 [Docs/api-spec.md](../Docs/api-spec.md)를 기준으로 한다. `client/scripts/autoload/MockServer.gd`의 판정 로직(획득/반납/대시-수감/구출/자동탈출/카운트다운/승패)을 그대로 포팅했다.

## 실행

```bash
npm install
npm run dev      # node --watch src/index.js — 파일 변경 시 자동 재시작
# 또는
npm start        # node src/index.js
```

기본적으로 `ws://localhost:8080/ws`에서 대기한다. 포트를 바꾸려면 `PORT` 환경변수를 지정한다:

```bash
PORT=9000 npm run dev
```

헬스체크: `GET /healthz` → `200 ok`.

## 스모크 테스트

서버를 자식 프로세스로 띄우고(별도 포트 8099), 오리/경찰 두 WebSocket 클라이언트로 방 생성 → 참가 → 팀 선택 → 게임 시작 → 새끼오리 획득/반납 → 대시로 수감까지 한 판을 자동으로 훑는다.

```bash
npm run smoke-test
```

## 파일 구조

- `src/index.js` — HTTP + WebSocketServer 부트스트랩, 연결 lifecycle, 전체 방 시뮬레이션 tick 루프
- `src/constants.js` — `Docs/api-spec.md`의 게임 상수 표 + 새끼오리 회피용 정적 장애물 좌표(`Pond.tscn`에서 한 번 추출해 하드코딩)
- `src/rooms.js` — 방 생성/목록/입장/퇴장/팀선택/닉네임, Room·Player·Duckling 데이터 구조 및 직렬화
- `src/gameLoop.js` — 카운트다운/타이머/새끼오리 AI(배회·획득·추종·반납)/대시 판정/감옥·구출·자동탈출/승패 판정
- `src/messages.js` — 클라이언트 메시지 타입 → 핸들러 라우팅, 에러 응답
- `scripts/smoke-test.js` — 위 스모크 테스트 스크립트
