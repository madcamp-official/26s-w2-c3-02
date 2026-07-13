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

  ws.on('message', (data) => handleMessage(ws, data.toString()));
  ws.on('close', () => handleClose(ws));
  ws.on('error', (err) => console.error('[ws] connection error:', err));
});

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
  gameLoop.tickAll(delta);
}, SIM_INTERVAL_MS);

server.listen(PORT, () => {
  console.log(`[server] listening on ws://localhost:${PORT}/ws (health check: http://localhost:${PORT}/healthz)`);
});
