'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const C = require('./constants');
const gameLoop = require('./gameLoop');
const { handleMessage, handleClose } = require('./messages');

const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
// Docker 이미지에는 Godot Web export 결과물(web/)을 서버 코드와 함께 담아, 정적 파일과
// WebSocket을 같은 origin/포트에서 서빙한다(별도 CORS/wss 설정 없이 동작하게 하기 위함).
const PUBLIC_DIR = path.resolve(process.env.PUBLIC_DIR || path.join(__dirname, '../../web'));
const INDEX_FILE = process.env.PUBLIC_INDEX || 'pol_duck.html';

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
};

function serveStatic(req, res) {
  const urlPath = req.url === '/' ? `/${INDEX_FILE}` : req.url.split('?')[0];
  const filePath = path.join(PUBLIC_DIR, decodeURIComponent(urlPath));

  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end();
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end();
      return;
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }
  if (req.method === 'GET') {
    serveStatic(req, res);
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  ws.roomId = null;
  ws.playerId = null;
  ws.isAlive = true;
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  // 메시지 처리 중 예외가 하나라도 새어나가면 Node 프로세스 전체가 죽어 모든 방/연결이
  // 함께 날아간다(Docker가 재시작해도 인메모리 rooms 상태는 복구되지 않음). 한 연결의
  // 잘못된 메시지가 다른 모든 방에 영향을 주지 않도록 여기서 반드시 막는다.
  ws.on('message', (data) => {
    try {
      handleMessage(ws, data.toString());
    } catch (err) {
      console.error('[ws] message handler error:', err);
    }
  });
  ws.on('close', () => {
    try {
      handleClose(ws);
    } catch (err) {
      console.error('[ws] close handler error:', err);
    }
  });
  ws.on('error', (err) => console.error('[ws] connection error:', err));
});

// 대기실에서 기다리는 동안은 서버·클라이언트 모두 보낼 메시지가 없어 연결이 완전히
// 유휴 상태가 되는데, 앞단 리버스 프록시(nginx 등)는 일정 시간(기본 60초 내외) 트래픽이
// 없는 연결을 끊어버린다. 그러면 handleClose → removePlayer의 "빈 방 삭제" 규칙에 따라
// 방장이 기다리던 방이 통째로 사라진다. 서버가 주기적으로 ping을 보내 연결을 살아있게
// 유지한다(브라우저/Godot 클라이언트는 프로토콜 수준에서 pong을 자동 응답). 두 주기
// 연속 pong이 없으면 죽은 연결로 보고 정리한다.
const HEARTBEAT_INTERVAL_MS = 30 * 1000;
setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_INTERVAL_MS);

// 방마다 setInterval을 따로 두지 않고, 전체 방을 한 번에 순회하는 단일 시뮬레이션
// 루프를 돈다. Docs/api-spec.md의 STATE_TICK_RATE(10Hz)는 game:state 브로드캐스트
// 주기이고, 이 tick 자체는 그보다 촘촘한 SIM_TICK_HZ(30Hz)로 판정을 갱신한다.
const SIM_INTERVAL_MS = 1000 / C.SIM_TICK_HZ;
// GC pause, 다른 방의 무거운 연산 등으로 콜백이 밀리면 delta가 순간적으로 커져
// 이동/판정 계산이 한 번에 크게 튈 수 있으므로, 정상 틱 간격의 몇 배로 상한을 둔다.
const MAX_DELTA_SECONDS = (SIM_INTERVAL_MS / 1000) * 3;
let lastTick = Date.now();
setInterval(() => {
  const now = Date.now();
  const delta = Math.min((now - lastTick) / 1000, MAX_DELTA_SECONDS);
  lastTick = now;
  try {
    gameLoop.tickAll(delta);
  } catch (err) {
    console.error('[loop] tick error:', err);
  }
}, SIM_INTERVAL_MS);

server.listen(PORT, () => {
  console.log(`[server] listening on ws://localhost:${PORT}/ws (health check: http://localhost:${PORT}/healthz)`);
});
