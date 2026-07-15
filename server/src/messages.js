'use strict';

const C = require('./constants');
const rooms = require('./rooms');
const gameLoop = require('./gameLoop');

function sendError(ws, requestId, code, message) {
  rooms.sendTo(ws, { type: 'error', requestId: requestId || null, payload: { code, message } });
}

function requireRoomAndPlayer(ws) {
  return rooms.findRoomAndPlayerBySocket(ws);
}

// ── 개별 메시지 핸들러 ────────────────────────────────────────────────────────

function handleRoomCreate(ws, msg) {
  const payload = msg.payload || {};
  const result = rooms.createRoom({
    nickname: payload.nickname,
    roomName: payload.roomName,
    isPrivate: payload.isPrivate,
    characterSkin: payload.characterSkin,
    taggerSkin: payload.taggerSkin,
    ws,
  });
  if (!result.ok) {
    sendError(ws, msg.requestId, result.code, result.message);
    return;
  }
  ws.roomId = result.room.roomId;
  ws.playerId = result.player.playerId;
  rooms.sendTo(ws, {
    type: 'room:joined',
    requestId: msg.requestId,
    roomId: result.room.roomId,
    payload: { playerId: result.player.playerId, isHost: true, state: rooms.serializeRoomState(result.room) },
  });
}

function handleRoomList(ws, msg) {
  rooms.sendTo(ws, { type: 'room:list', requestId: msg.requestId, payload: { rooms: rooms.listRooms() } });
}

function handleRoomJoin(ws, msg) {
  const payload = msg.payload || {};
  const result = rooms.joinRoom({
    roomId: msg.roomId,
    nickname: payload.nickname,
    joinCode: payload.joinCode,
    characterSkin: payload.characterSkin,
    taggerSkin: payload.taggerSkin,
    ws,
  });
  if (!result.ok) {
    sendError(ws, msg.requestId, result.code, result.message);
    return;
  }
  ws.roomId = result.room.roomId;
  ws.playerId = result.player.playerId;
  rooms.sendTo(ws, {
    type: 'room:joined',
    requestId: msg.requestId,
    roomId: result.room.roomId,
    payload: {
      playerId: result.player.playerId,
      isHost: result.room.hostPlayerId === result.player.playerId,
      state: rooms.serializeRoomState(result.room),
    },
  });
  gameLoop.broadcastRoomState(result.room);
}

function handleRoomLeave(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  rooms.removePlayer(room, player.playerId);
  ws.roomId = null;
  ws.playerId = null;
  if (rooms.rooms.has(room.roomId)) {
    gameLoop.broadcastRoomState(room);
  }
}

function handlePlayerSetNickname(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  rooms.setNickname(room, player.playerId, (msg.payload || {}).nickname);
  gameLoop.broadcastRoomState(room);
}

function handlePlayerSetReady(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  rooms.setReady(room, player.playerId, !!(msg.payload || {}).ready);
  gameLoop.broadcastRoomState(room);
}

function handleGameStart(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) {
    sendError(ws, msg.requestId, 'ROOM_NOT_FOUND', '방을 찾을 수 없습니다.');
    return;
  }
  if (room.hostPlayerId !== player.playerId) {
    sendError(ws, msg.requestId, 'NOT_HOST', '호스트만 게임을 시작할 수 있습니다.');
    return;
  }
  const started = gameLoop.startGame(room);
  if (!started) {
    sendError(ws, msg.requestId, 'INVALID_ACTION', '시작 조건이 충족되지 않았습니다.');
  }
}

function handlePlayerInput(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  const payload = msg.payload || {};
  if (room.phase !== 'countdown' && room.phase !== 'playing') return;
  if (typeof payload.phase === 'string' && payload.phase !== room.phase) return;
  if (payload.position) {
    player.position = { x: payload.position.x, y: payload.position.y, z: payload.position.z };
  }
  if (typeof payload.rotationY === 'number') {
    player.rotationY = payload.rotationY;
  }
}

function handlePlayerDash(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  if (room.phase !== 'playing' || player.team !== 'tagger') return;
  const payload = msg.payload || {};
  if (!payload.startPosition || !payload.endPosition) return;
  const duration = typeof payload.duration === 'number' ? payload.duration : C.DASH_DURATION;
  gameLoop.beginDash(room, player.playerId, payload.startPosition, payload.endPosition, duration);
}

function handleGameReturnToLobby(ws, msg) {
  const { room } = requireRoomAndPlayer(ws);
  if (!room) return;
  gameLoop.returnToLobby(room);
}

// 둥지까지 걸어가는 연출은 duckling.gd가 로컬로 그리고, 도착 판정도 클라이언트가 직접
// 내려서 알려준다(carried와 같은 이유로 좌표 자체가 서버 판정에 쓰이지 않으므로). 서버는
// 이 duckling이 실제로 이 방의 delivering 상태였는지만 확인하고 점수/삭제를 처리한다.
function handleDucklingDeliver(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  const ducklingId = (msg.payload || {}).ducklingId;
  const d = room.ducklings.get(ducklingId);
  if (!d || d.state !== 'delivering') return;
  gameLoop.deliverDuckling(room, d);
}

function handleGameForceEnd(ws, msg) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  gameLoop.endGame(room, 'tagger', 'debug_force_end');
}

// 클라이언트가 몇 초 안에 "서버와 살아있는지"를 스스로 판단하려면 유휴 상태(로비 등, 서버가
// 먼저 보낼 브로드캐스트가 없는 상황)에서도 주기적으로 왕복할 메시지가 필요하다. WebSocket
// 프로토콜 레벨 ping/pong은 Godot WebSocketPeer의 GDScript API로 직접 보낼 수 없어서,
// 애플리케이션 레벨로 별도 만든다 — 받는 즉시 그대로 돌려주기만 하면 된다.
function handlePing(ws, msg) {
  rooms.sendTo(ws, { type: 'pong', requestId: msg.requestId || null, payload: {} });
}

const HANDLERS = {
  'room:create': handleRoomCreate,
  'room:list': handleRoomList,
  'room:join': handleRoomJoin,
  'room:leave': handleRoomLeave,
  'player:setNickname': handlePlayerSetNickname,
  'player:setReady': handlePlayerSetReady,
  'game:start': handleGameStart,
  'player:input': handlePlayerInput,
  'player:dash': handlePlayerDash,
  'game:returnToLobby': handleGameReturnToLobby,
  'duckling:deliver': handleDucklingDeliver,
  'game:forceEnd': handleGameForceEnd,
  'ping': handlePing,
};

function handleMessage(ws, raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch (err) {
    sendError(ws, null, 'INVALID_MESSAGE', '메시지 형식이 잘못됨(JSON 파싱 실패)');
    return;
  }

  if (!msg || typeof msg.type !== 'string') {
    sendError(ws, msg && msg.requestId, 'INVALID_MESSAGE', 'type 필드가 필요합니다.');
    return;
  }

  const handler = HANDLERS[msg.type];
  if (!handler) {
    sendError(ws, msg.requestId, 'INVALID_MESSAGE', `알 수 없는 메시지 타입: ${msg.type}`);
    return;
  }

  try {
    handler(ws, msg);
  } catch (err) {
    console.error(`[messages] ${msg.type} handler error:`, err);
    sendError(ws, msg.requestId, 'SERVER_ERROR', '서버 내부 오류');
  }
}

function handleClose(ws) {
  const { room, player } = requireRoomAndPlayer(ws);
  if (!room || !player) return;
  rooms.removePlayer(room, player.playerId);
  if (rooms.rooms.has(room.roomId)) {
    gameLoop.broadcastRoomState(room);
  }
}

module.exports = { handleMessage, handleClose };
