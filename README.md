# 26s-w2-c3-02

## 공통과제 II : 협업형 실전 산출물 제작 (2인 1팀)

**목적:** 실시간 인터랙션, LLM Wrapper, Cross-Platform 중 하나의 옵션을 선택해 구현하며, 선택한 기술을 실제로 동작하는 형태의 산출물로 완성한다.

**선택 옵션:**

| 옵션 | 설명 |
|---|---|
| 실시간 인터랙션 | 사용자 간 상태 변화, 실시간 데이터 흐름, 스트리밍 응답 등 실시간성이 드러나는 기능을 구현 |
| LLM Wrapper | LLM API를 활용하여 AI 기능이 포함된 산출물을 구현 |
| Cross-Platform | 하나의 산출물을 여러 실행 환경에서 사용할 수 있도록 구현* |

> *데스크톱 앱 ↔ 모바일 앱; 혹은 다른 폼팩터에서의 앱; 웹만/웹 기반 프레임워크(Electron, Tauri 등) 대신 다른 프레임워크를 시도해보는 것을 적극 권장

**결과물:** 선택한 옵션이 적용된 작동 가능한 산출물, 실행 가능한 코드, 시연 자료 및 관련 문서

---

## 팀원

| 이름 | 학교 | GitHub | 역할 |
|---|---|---|---|
| 박수현 | 한양대학교 | [suh1088](https://github.com/suh1088) | 클라이언트/UI (Godot, 반응형 UI) |
| 조예준 | KAIST | [jossi-jossi](https://github.com/jossi-jossi) | 네트워크/백엔드 (Node.js, 웹소켓 동기화) |

---

## 선택 옵션

- [x] 실시간 인터랙션
- [ ] LLM Wrapper
- [x] Cross-Platform

---

## 기획안

- **산출물 주제:** 악어(술래)와 오리(도망자)가 3D 연못 위에서 대결하는 실시간 멀티플레이 경찰과 도둑잡기 게임
- **제작 목적:** Godot + WebSocket 기반 실시간 위치/상태 동기화를 구현하고, 하나의 코드베이스로 PC 웹과 모바일 앱을 동시 대응하는 크로스플랫폼 게임을 완성한다
- **선택 옵션:** 실시간 인터랙션, Cross-Platform
- **핵심 구현 요소:**
  - 오리(도둑) / 거위(술래) 역할 기반 실시간 멀티플레이 동기화 (위치, 포획, 구출, 새끼오리 획득 상태)
  - 가로 모드 고정 + Anchor/Safe Area 기반 반응형 UI로 PC 웹·모바일 앱 동시 대응
  - 연못 위 새끼오리 스폰 및 둥지 인솔, 감옥/구출 기믹을 포함한 게임 규칙 구현
- **사용 / 시연 시나리오:** 플레이어가 방을 만들거나 방 코드로 참가 → 로비에서 캐릭터(오리/거위 스킨) 선택 및 준비 → 게임 시작 후 오리는 제한 시간 내 새끼오리를 둥지로 인솔, 거위는 오리를 체포해 감옥에 가두며 방해 → 시간 종료 또는 승리 조건 달성 시 결과 화면에서 승패 및 개인 기록 확인
- **팀원별 역할:** 박수현(클라이언트/UI - Godot 엔진 조작, 3D 에셋 배치, 반응형 UI 세팅), 조예준(네트워크/백엔드 - Node.js 서버 구축, 웹소켓 동기화 로직, 서버 배포)

### 개발 일정

| 날짜 | 목표 |
|---|---|
| Day 1 | 문서 작성 & 개발환경 세팅 |
| Day 2 | Kenney 에셋으로 3D 연못 배치, 클릭/터치 방향 이동 조작계 구현 |
| Day 3 | 새끼오리 스폰·인솔·둥지 점수 등 싱글 플레이 핵심 로직 완성 |
| Day 4 | 거위 AI/조작 및 체포·감옥 기믹 구현, Node.js 웹소켓 서버 기초 세팅 |
| Day 5 | 실시간 위치 동기화 (Godot ↔ Node.js WebSocket) |
| Day 6 | 오브젝트/상태 동기화(포획·구출·새끼오리 획득) 및 데이터 꼬임 버그 디버깅 |
| Day 7 | 가로 모드 반응형 UI 마무리, 웹/서버 배포 및 크로스플랫폼 최종 QA |

---

## 구현 명세서

| 구현 요소 | 설명 | 우선순위 |
|---|---|---|
| 실시간 위치/상태 동기화 | 오리·거위의 이동, 포획, 구출, 새끼오리 획득 상태를 WebSocket으로 모든 클라이언트에 실시간 반영 | 필수 |
| 크로스플랫폼 반응형 UI | PC 웹과 모바일 앱에서 가로 모드 고정, Anchor/Safe Area 기반 UI로 동일하게 동작 | 필수 |
| 오리 & 악어 스킨 선택 | 로비에서 캐릭터 외형(스킨)을 선택할 수 있는 커스터마이징 기능 | 선택 |
| 대기방(로비) 화면 | 참가자 목록, 준비 상태, 방 코드/초대 기능을 갖춘 로비 화면 | 선택 |

---

## 아키텍처

<!-- 실시간 인터랙션: WebSocket/SSE/WebRTC 구조도 / LLM Wrapper: API 연동 흐름도 / Cross-Platform: 플랫폼 구성도 -->

- **클라이언트:** Godot Engine (GDScript) → PC 웹(WebGL/WASM 빌드) & 모바일 앱으로 동일 코드베이스 내보내기
- **서버:** Node.js + `ws` 라이브러리 기반 순수 웹소켓 서버, 방(room) 단위 인메모리 상태 관리
- **통신:** 클라이언트 ↔ 서버 간 JSON 메시지 기반 WebSocket 양방향 통신 (위치 갱신, 포획/구출 판정, 새끼오리 획득 이벤트 브로드캐스트)
- **배포:** Godot WebGL 빌드 → GitHub Pages/Vercel, Node.js 서버 → Render/AWS EC2 Free Tier

---

## 설계 문서

> 프로젝트 성격에 따라 필요한 항목만 작성

### 화면 / 인터페이스 설계

<!-- Figma 링크, 화면 이미지, CLI 사용 예시, 앱 화면 등 -->

전체 IA(정보 구조):

```
게임 실행
├─ 로딩
├─ 메인 화면
│  ├─ 빠른 참가 / 방 만들기 / 방 코드 참가
│  ├─ 캐릭터 꾸미기
│  └─ 설정
├─ 로비
│  ├─ 참가자 목록 / 준비 상태 / 방 설정
│  ├─ 초대 / 방 코드
│  └─ 게임 시작
├─ 역할 안내 (오리 역할 / 거위 역할)
├─ 인게임
│  ├─ 일반 플레이 / 오리 새끼 인솔 / 체포 시도
│  ├─ 수감 상태 / 구출 상태
│  └─ 일시정지 / 연결 끊김
└─ 결과 화면
   ├─ 승리 / 패배 / 개인 기록
   └─ 다시 하기 / 로비로 돌아가기 / 메인 화면
```

화면 레이아웃은 가로 모드 고정, 좌측 이동 입력 / 중앙 게임 시야 / 우측 행동 버튼 3분할 구조를 기준으로 하며, 상단 상태 바(남은 시간, 목표 진행도)는 Safe Area 안쪽에 배치한다.

### 데이터 구조

<!-- DB 스키마, JSON 구조, 파일 저장 방식 등 -->

별도 DB 없이 Node.js 서버 인메모리(`const rooms = {}`)로 방 단위 상태를 관리한다.

```json
{
  "roomId": "ABCD12",
  "players": {
    "playerId": {
      "role": "duck | goose",
      "position": { "x": 0, "y": 0, "z": 0 },
      "state": "normal | jailed | carrying"
    }
  },
  "ducklings": [
    { "id": "d1", "position": { "x": 0, "y": 0, "z": 0 }, "collected": false }
  ],
  "timeRemaining": 180
}
```

### API / 외부 서비스 연동

| Method / 방식 | Endpoint / 서비스 | 설명 | 요청 | 응답 | 비고 |
|---|---|---|---|---|---|
| WebSocket | `/ws` | 실시간 위치/상태 동기화 (이동, 포획, 구출, 새끼오리 획득) | `{ type, roomId, payload }` JSON | 같은 방 참가자에게 `{ type, payload }` 브로드캐스트 | Godot `WebSocketPeer` ↔ Node.js `ws` 라이브러리 |

---

## 산출물 및 실행 방법

- **산출물 설명:** 악어(거위)가 술래, 오리가 도망자가 되어 3D 연못 위에서 새끼오리 구출/체포를 겨루는 실시간 멀티플레이 캐주얼 게임
- **실행 환경:** PC 웹 브라우저(WebGL) / 모바일 앱, Node.js 웹소켓 서버
- **실행 방법:** 배포된 웹 링크 접속 또는 모바일 앱 실행 → 방 만들기/참가 → 로비에서 준비 완료 → 게임 시작
- **시연 영상 / 이미지:** (선택)

### 실행 방법

```bash
# 환경 설정
cp .env.example .env

# 의존성 설치
npm install   # 또는 pip install -r requirements.txt 등

# 실행
npm run dev   # 또는 python main.py 등
```

### 기술 구성

| 분류 | 사용 기술 |
|---|---|
| 핵심 기술 | Godot Engine (GDScript), Node.js, WebSocket (`ws`) |
| 실행 환경 | PC 웹(WebGL), 모바일 앱, Node.js 서버 |
| 데이터 저장 | 인메모리 (Node.js `rooms` 객체), 추후 필요 시 Redis 검토 |
| 외부 API / 서비스 | 없음 (프로토타입 단계 미도입) |
| 기타 | Kenney / Sketchfab / Poly Pizza 무료 3D 에셋(.gltf/.glb), GitHub Pages/Vercel, Render/AWS EC2 배포 |

---

## 회고 문서

> [KPT 방법론 참고](https://velog.io/@habwa/%EB%8B%A8%EA%B8%B0-%ED%94%84%EB%A1%9C%EC%A0%9D%ED%8A%B8-%ED%9A%8C%EA%B3%A0-KPT-%EB%B0%A9%EB%B2%95%EB%A1%A0)

### Keep — 잘 된 점, 다음에도 유지할 것

-
-
-

### Problem — 아쉬웠던 점, 개선이 필요한 것

-
-
-

### Try — 다음번에 시도해볼 것

-
-
-

### 팀원별 소감

**박수현:**

> 

**조예준:**

> 

---

## 참고 자료

### 실시간 인터랙션

**WebSocket**
- https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API
- https://techblog.woowahan.com/5268/
- https://tech.kakao.com/posts/391
- https://daleseo.com/websocket/
- https://kakaoentertainment-tech.tistory.com/110

**Socket.IO**
- https://socket.io/docs/v4/
- https://inpa.tistory.com/entry/SOCKET-%F0%9F%93%9A-Namespace-Room-%EA%B8%B0%EB%8A%A5
- https://adjh54.tistory.com/549
- https://fred16157.github.io/node.js/nodejs-socketio-communication-room-and-namespace/

**SSE (Server-Sent Events)**
- https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events
- https://developer.mozilla.org/ko/docs/Web/API/Server-sent_events/Using_server-sent_events
- https://api7.ai/ko/blog/what-is-sse

**TCP / UDP Socket**
- https://docs.python.org/3/library/socket.html
- https://inpa.tistory.com/entry/NW-%F0%9F%8C%90-%EC%95%84%EC%A7%81%EB%8F%84-%EB%AA%A8%ED%98%B8%ED%95%9C-TCP-UDP-%EA%B0%9C%EB%85%90-%E2%9D%93-%EC%89%BD%EA%B2%8C-%EC%9D%B4%ED%95%B4%ED%95%98%EC%9E%90

**gRPC Streaming**
- https://grpc.io/docs/what-is-grpc/core-concepts/
- https://tech.ktcloud.com/entry/gRPC%EC%9D%98-%EB%82%B4%EB%B6%80-%EA%B5%AC%EC%A1%B0-%ED%8C%8C%ED%97%A4%EC%B9%98%EA%B8%B0-HTTP2-Protobuf-%EA%B7%B8%EB%A6%AC%EA%B3%A0-%EC%8A%A4%ED%8A%B8%EB%A6%AC%EB%B0%8D
- https://tech.ktcloud.com/entry/gRPC%EC%9D%98-%EB%82%B4%EB%B6%80-%EA%B5%AC%EC%A1%B0-%ED%8C%8C%ED%97%A4%EC%B9%98%EA%B8%B02-Channel-Stub
- https://inspirit941.tistory.com/371
- https://devocean.sk.com/blog/techBoardDetail.do?ID=167433

**WebRTC**
- https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API
- https://webrtc.org/getting-started/overview
- https://web.dev/articles/webrtc-basics?hl=ko
- https://devocean.sk.com/blog/techBoardDetail.do?ID=164885
- https://beomkey-nkb.github.io/%EA%B0%9C%EB%85%90%EC%A0%95%EB%A6%AC/webRTC%EC%A0%95%EB%A6%AC/
- https://gh402.tistory.com/45
- https://on.com2us.com/tech/webrtc-coturn-turn-stun-server-setup-guide/

**QUIC / WebTransport**
- https://developer.mozilla.org/en-US/docs/Web/API/WebTransport_API
- https://datatracker.ietf.org/doc/html/rfc9000
- https://news.hada.io/topic?id=13888

#### KCLOUD VM / Cloudflare Tunnel 환경별 주의사항

| 환경 | 사용 가능(권장) 기술 | 포트/조건 | 주의할 기술 |
|---|---|---|---|
| **로컬 / 일반 VM** | HTTP/REST, WebSocket, Socket.IO, SSE, TCP Socket, gRPC Streaming, WebRTC, QUIC/WebTransport 등 대부분 가능 | 직접 포트 개방 가능. 예: 3000, 5000, 8000, 8080, 9000 등. 외부 공개 시 방화벽/보안그룹/공인 IP 설정 필요 | WebRTC는 STUN/TURN 필요 가능. QUIC/WebTransport는 HTTP/3 · UDP 지원 필요 |
| **KCLOUD VM (VPN 내부)** | HTTP/REST, WebSocket, Socket.IO, SSE, WebRTC 시그널링 | 접속 기기 VPN 필요. 기본 허용 포트: **22, 80, 443**. 개발 포트(3000, 8000, 8080 등)는 직접 접근 제한 가능 | TCP Socket은 포트 제한 있음. gRPC는 HTTP/2 설정 필요. WebRTC 미디어·UDP·QUIC/WebTransport 비권장 |
| **KCLOUD VM + Tunnel** | HTTP/REST, WebSocket, Socket.IO, SSE, WebRTC 시그널링 | VM의 `localhost:<port>`를 도메인에 연결. `localPort`는 **1024~65535**. 예: 3000, 8000, 8080 가능 | 순수 TCP Socket, UDP, WebRTC 미디어/DataChannel, QUIC/WebTransport 불가. gRPC 보장 어려움 |
| **외부 서비스 + 우리 도메인** | HTTP/REST, WebSocket, Socket.IO, SSE, WebRTC 시그널링 | Vercel/Netlify/Railway/Render/AWS/GCP 등에 배포 후 CNAME/A 레코드 연결. 보통 외부는 **443** 사용 | WebSocket/gRPC/TCP/UDP는 플랫폼 지원 여부 확인 필요. 서버리스 플랫폼은 장시간 연결 제한 가능 |
| **서버 없이 외부 SaaS 사용** | Supabase Realtime, Firebase, Pusher/Ably, LLM API Streaming | 직접 포트 관리 불필요. 각 서비스 SDK/API 사용 | 커스텀 TCP/UDP 서버 구현 불가. WebRTC는 STUN/TURN 필요할 수 있음 |

### LLM Wrapper

- https://github.com/teddylee777/openai-api-kr
- https://github.com/teddylee777/langchain-kr
- https://devocean.sk.com/blog/techBoardDetail.do?ID=167407
- https://mastra.ai/docs

### Cross-Platform

- https://flutter.dev/
- https://reactnative.dev/
- https://docs.expo.dev/
- https://kotlinlang.org/multiplatform/
