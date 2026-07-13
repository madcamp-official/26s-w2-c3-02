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

const HANDLERS = {
  'room:create': handleRoomCreate,
  'room:list': handleRoomList,
  'room:join': handleRoomJoin,
  'room:leave': handleRoomLeave,
  'player:setNickname': handlePlayerSetNickname,
  'game:start': handleGameStart,
  'player:input': handlePlayerInput,
  'player:dash': handlePlayerDash,
  'game:returnToLobby': handleGameReturnToLobby,
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
