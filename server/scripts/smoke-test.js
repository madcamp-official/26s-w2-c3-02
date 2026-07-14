'use strict';

// 서버를 자식 프로세스로 띄우고, 오리/경찰 두 WebSocket 클라이언트로 방 생성부터
// 게임 종료(수감)까지 한 판을 자동으로 훑으며 Docs/api-spec.md 필드명과 흐름이
// 실제로 일치하는지 확인한다. `npm run smoke-test`로 실행한다.

const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

const PORT = 8099; // 개발 중인 npm run dev(8080)와 충돌하지 않도록 별도 포트 사용
const URL = `ws://127.0.0.1:${PORT}/ws`;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

function onceType(ws, type, predicate) {
  return new Promise((resolve) => {
    function handler(data) {
      const msg = JSON.parse(data.toString());
      if (msg.type === type && (!predicate || predicate(msg))) {
        ws.off('message', handler);
        resolve(msg);
      }
    }
    ws.on('message', handler);
  });
}

function send(ws, type, payload, extra = {}) {
  const requestId = Math.random().toString(36).slice(2);
  ws.send(JSON.stringify({ type, requestId, ...extra, payload }));
  return requestId;
}

let failed = false;
function assert(cond, msg) {
  if (!cond) {
    failed = true;
    console.error(`FAIL: ${msg}`);
  } else {
    console.log(`PASS: ${msg}`);
  }
}

function distanceXZ(a, b) {
  return Math.hypot(a.x - b.x, a.z - b.z);
}

async function waitUntil(ws, type, predicate, maxTries, label) {
  for (let i = 0; i < maxTries; i++) {
    const msg = await onceType(ws, type);
    if (predicate(msg)) return msg;
  }
  throw new Error(`timed out waiting for ${label}`);
}

async function main() {
  const server = spawn(process.execPath, [path.join(__dirname, '..', 'src', 'index.js')], {
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  server.stdout.on('data', (d) => process.stdout.write(`[server] ${d}`));
  server.stderr.on('data', (d) => process.stderr.write(`[server:err] ${d}`));

  await wait(500);

  try {
    const duckWs = await connect();
    const tagWs = await connect();

    let respPromise = onceType(duckWs, 'room:joined');
    send(duckWs, 'room:create', { nickname: '플레이어A' });
    let resp = await respPromise;
    const roomId = resp.roomId;
    const playerAId = resp.payload.playerId;
    assert(!!roomId && resp.payload.isHost === true, `room:create -> room:joined (roomId=${roomId}, isHost=true)`);

    respPromise = onceType(tagWs, 'room:joined');
    send(tagWs, 'room:join', { nickname: '플레이어B', joinCode: roomId }, { roomId });
    resp = await respPromise;
    const playerBId = resp.payload.playerId;
    assert(resp.payload.isHost === false, 'room:join -> room:joined (isHost=false)');

    // 역할은 대기실에서 고르지 않고 game:start 시 서버가 무작위로 배정하므로, 어느 소켓이
    // 오리/경찰이 됐는지는 시작 후 game:state를 보고 판별한다.
    const gameStartedPromise = onceType(duckWs, 'game:event', (m) => m.payload.event === 'game_started');
    send(duckWs, 'game:start', {}, { roomId });
    await gameStartedPromise;
    console.log('PASS: game:start -> countdown -> game_started 이벤트 수신 (역할 무작위 배정)');

    const playingState = await waitUntil(
      duckWs,
      'game:state',
      (m) => m.payload.phase === 'playing',
      50,
      'phase=playing'
    );
    assert(playingState.payload.ducklings.length > 0, `playing 진입, 새끼오리 ${playingState.payload.ducklings.length}마리 스폰`);

    const taggerPlayer = playingState.payload.players.find((p) => p.team === 'tagger');
    assert(!!taggerPlayer && taggerPlayer.character === 'aligator', '무작위 배정된 경찰의 character=aligator');
    const duckWsIsTagger = taggerPlayer.playerId === playerAId;
    const tagWsIsTagger = taggerPlayer.playerId === playerBId;
    assert(duckWsIsTagger !== tagWsIsTagger, '두 플레이어 중 정확히 한 명이 경찰로 배정됨');
    const duckSocket = duckWsIsTagger ? tagWs : duckWs;
    const tagSocket = duckWsIsTagger ? duckWs : tagWs;

    const nestPos = { x: -58.5, y: 1.68, z: 58.5 };
    let nearestDuckling = playingState.payload.ducklings[0];
    for (const d of playingState.payload.ducklings) {
      if (distanceXZ(d.position, nestPos) < distanceXZ(nearestDuckling.position, nestPos)) nearestDuckling = d;
    }

    // 오리를 (둥지에서 가장 가까운) 새끼오리 위치로 이동 -> 자동 획득 확인
    send(duckSocket, 'player:input', { position: nearestDuckling.position, rotationY: 0 }, { roomId });
    const pickedUpState = await waitUntil(
      duckSocket,
      'game:state',
      (m) => {
        const d = m.payload.ducklings.find((x) => x.ducklingId === nearestDuckling.ducklingId);
        return d && d.state === 'carried';
      },
      30,
      'duckling pickup'
    );
    assert(!!pickedUpState, `새끼오리 자동 획득 (ducklingId=${nearestDuckling.ducklingId})`);

    // 오리를 둥지로 이동 -> delivering 전환 확인. 둥지까지 걷는 연출/도착 판정은 이제
    // 클라이언트(duckling.gd)가 로컬로 하고 'duckling:deliver'로 알려줘야 서버가 점수를
    // 준다 — 실제 클라이언트가 하는 것과 동일하게 여기서도 명시적으로 보내준다.
    send(duckSocket, 'player:input', { position: nestPos, rotationY: 0 }, { roomId });
    const deliveringState = await waitUntil(
      duckSocket,
      'game:state',
      (m) => {
        const d = m.payload.ducklings.find((x) => x.ducklingId === nearestDuckling.ducklingId);
        return d && d.state === 'delivering';
      },
      30,
      'duckling delivering 전환'
    );
    assert(!!deliveringState, 'delivering 상태로 전환 확인');

    send(duckSocket, 'duckling:deliver', { ducklingId: nearestDuckling.ducklingId }, { roomId });
    const deliveredState = await waitUntil(duckSocket, 'game:state', (m) => m.payload.score >= 1, 30, 'score >= 1');
    assert(deliveredState.payload.score >= 1, `둥지 반납 -> score=${deliveredState.payload.score}`);

    // 경찰이 오리 위치를 관통하는 대시를 보내 수감 확인
    const latest = await onceType(duckSocket, 'game:state');
    const duckPos = latest.payload.players.find((p) => p.team === 'duck').position;
    const jailedEventPromise = onceType(duckSocket, 'game:event', (m) => m.payload.event === 'player_jailed');
    send(
      tagSocket,
      'player:dash',
      {
        startPosition: { x: duckPos.x - 5, y: 0, z: duckPos.z },
        endPosition: { x: duckPos.x + 5, y: 0, z: duckPos.z },
        duration: 0.25,
      },
      { roomId }
    );
    await jailedEventPromise;
    console.log('PASS: player:dash -> player_jailed 이벤트 수신');

    const jailedState = await waitUntil(
      duckSocket,
      'game:state',
      (m) => {
        const p = m.payload.players.find((x) => x.team === 'duck');
        return p && p.state === 'jailed';
      },
      20,
      'player.state === jailed'
    );
    const jailedDuck = jailedState.payload.players.find((p) => p.team === 'duck');
    assert(jailedDuck.state === 'jailed', `수감 후 player.state === 'jailed' (실제: ${jailedDuck.state})`);
    assert(typeof jailedDuck.jailRemaining === 'number', '오리 1명뿐이라 jailRemaining 필드 존재(자동탈출 대상)');

    console.log(failed ? '\n일부 검증 실패' : '\n모든 시나리오 통과');
  } catch (err) {
    failed = true;
    console.error('스모크 테스트 중 예외:', err);
  } finally {
    server.kill();
    await wait(200);
  }

  process.exit(failed ? 1 : 0);
}

const HARD_TIMEOUT_MS = 60000;
const hardTimeout = setTimeout(() => {
  console.error(`FAIL: smoke test exceeded hard timeout (${HARD_TIMEOUT_MS}ms) — likely stuck awaiting a message that never arrived`);
  process.exit(1);
}, HARD_TIMEOUT_MS);
hardTimeout.unref();

main();
