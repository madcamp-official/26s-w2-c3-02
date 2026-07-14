'use strict';

const crypto = require('crypto');
const C = require('./constants');

// roomId -> Room
const rooms = new Map();

function generateRoomCode() {
  let code;
  do {
    code = '';
    for (let i = 0; i < C.ROOM_CODE_LENGTH; i++) {
      code += C.ROOM_CODE_CHARS[Math.floor(Math.random() * C.ROOM_CODE_CHARS.length)];
    }
  } while (rooms.has(code));
  return code;
}

function spawnPositionForCharacter(character) {
  if (character === 'aligator') {
    return { x: 40.0, y: 0.0, z: -40.0 };
  }
  return { x: -40.0, y: 0.0, z: 40.0 };
}

function makePlayer({ playerId, nickname, team, character, ws }) {
  const spawn = spawnPositionForCharacter(character);
  return {
    playerId,
    nickname,
    team,
    duckSkin: team === 'tagger' ? 'duck' : character || 'duck',
    character,
    position: spawn,
    rotationY: 0.0,
    state: 'idle',
    jailRemaining: null,
    deliveredDucklings: 0,
    ws,
  };
}

function serializePlayer(player) {
  const out = {
    playerId: player.playerId,
    nickname: player.nickname,
    team: player.team,
    character: player.character,
    isMock: false,
    position: player.position,
    rotationY: player.rotationY,
    state: player.state,
    carryingDucklingId: null,
    jailedUntil: null,
    deliveredDucklings: Number(player.deliveredDucklings || 0),
  };
  if (player.jailRemaining !== null && player.jailRemaining !== undefined) {
    out.jailRemaining = player.jailRemaining;
  }
  return out;
}

function serializeDuckling(d, queueIndex) {
  const out = {
    ducklingId: d.ducklingId,
    position: d.position,
    state: d.state,
    carrierPlayerId: d.carrierPlayerId,
  };
  if (d.deliveryBatchId) {
    out.deliveryBatchId = d.deliveryBatchId;
  }
  // carried 상태일 때만 의미 있음 — 클라이언트가 대열에서 몇 번째로 따라가는지(누구 뒤를
  // 이어야 하는지) 판단하는 데 쓴다. 좌표 자체는 서버가 더 이상 계산하지 않고, 이 순서
  // 정보만으로 각 클라이언트가 로컬에서 팔로우 위치를 재현한다.
  if (queueIndex !== undefined) {
    out.queueIndex = queueIndex;
  }
  return out;
}

function createRoomObject({ roomId, roomName, isPrivate }) {
  return {
    roomId,
    roomName: roomName || roomId,
    hostPlayerId: '',
    isPrivate,

    phase: 'lobby',
    countdownSeconds: 0,
    remainingSeconds: 0,
    score: 0,
    targetScore: C.TARGET_SCORE,
    winner: null,
    endReason: null,
    rescueProgress: 0.0,
    activeRescuerId: '',

    players: new Map(),
    ducklings: new Map(),

    // 내부 시뮬레이션 상태 (game:state로 나가지 않음) — gameLoop.js가 사용
    wanderState: new Map(),
    carryQueues: new Map(),
    deliveryBatches: new Map(),
    nextDeliveryBatchId: 1,
    nextDucklingId: 1,
    activeDashes: new Map(),

    isRescuing: false,
    rescueTimer: 0,
    allJailedTimer: -1,

    secondTimer: 0,
    broadcastTimer: 0,
    countdownTimer: 0,
  };
}

function makeDefaultRoomName(isPrivate) {
  const prefix = isPrivate ? '비공개방' : '공개방';
  let index = 1;
  let name = `${prefix} #${index}`;
  const usedNames = new Set(Array.from(rooms.values()).map((room) => room.roomName));
  while (usedNames.has(name)) {
    index += 1;
    name = `${prefix} #${index}`;
  }
  return name;
}

function createRoom({ nickname, roomName, isPrivate, characterSkin, ws }) {
  // 방의 참가코드는 별도로 관리하지 않고, 서버가 항상 무작위로 배정하는 4자리 roomId를
  // 그대로 참가코드로 사용한다(공개/비공개 모두 코드 자체는 존재).
  const roomId = generateRoomCode();
  const normalizedRoomName = (roomName || '').trim() || makeDefaultRoomName(!!isPrivate);

  for (const room of rooms.values()) {
    if (room.roomName === normalizedRoomName) {
      return { ok: false, code: 'ROOM_NAME_IN_USE', message: '이미 사용 중인 방 이름입니다.' };
    }
  }

  const room = createRoomObject({
    roomId,
    roomName: normalizedRoomName,
    isPrivate: !!isPrivate,
  });

  const playerId = crypto.randomUUID();
  const nick = (nickname || '').trim() || 'Player';
  const player = makePlayer({ playerId, nickname: nick, team: 'duck', character: characterSkin || 'duck', ws });
  room.players.set(playerId, player);
  room.hostPlayerId = playerId;

  rooms.set(roomId, room);

  return { ok: true, room, player };
}

function listRooms() {
  const out = [];
  for (const room of rooms.values()) {
    if (room.phase !== 'lobby') continue;
    const host = room.players.get(room.hostPlayerId);
    out.push({
      roomId: room.roomId,
      roomName: room.roomName,
      hostNickname: host ? host.nickname : '',
      playerCount: room.players.size,
      isPrivate: room.isPrivate,
    });
  }
  return out;
}

function joinRoom({ roomId, nickname, joinCode, characterSkin, ws }) {
  const room = rooms.get(roomId);
  if (!room) {
    return { ok: false, code: 'ROOM_NOT_FOUND', message: '존재하지 않는 방입니다.' };
  }
  if (room.phase !== 'lobby') {
    return { ok: false, code: 'GAME_ALREADY_STARTED', message: '이미 게임이 시작된 방입니다.' };
  }
  if (room.players.size >= C.MAX_PLAYERS) {
    return { ok: false, code: 'ROOM_FULL', message: '방 인원이 가득 찼습니다.' };
  }
  if (room.isPrivate && (joinCode || '') !== room.roomId) {
    return { ok: false, code: 'INVALID_JOIN_CODE', message: '참가코드가 올바르지 않습니다.' };
  }

  const playerId = crypto.randomUUID();
  const nick = (nickname || '').trim() || 'Player';
  const player = makePlayer({ playerId, nickname: nick, team: 'duck', character: characterSkin || 'duck', ws });
  room.players.set(playerId, player);

  return { ok: true, room, player };
}

function countTeam(room, team) {
  let count = 0;
  for (const p of room.players.values()) {
    if (p.team === team) count++;
  }
  return count;
}

// 대기실에서 팀을 직접 고르지 않고, 게임 시작 시 서버가 무작위로 역할을 배정한다.
function assignRandomRoles(room) {
  const players = Array.from(room.players.values());
  for (let i = players.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [players[i], players[j]] = [players[j], players[i]];
  }
  // 1인 디버그 모드에서는 TAGGER_COUNT(1)가 인원수(1)와 같아 슬라이스 방식이 항상
  // 그 한 명을 경찰로 고정시켜버린다. 이 경우엔 50% 확률로 아예 경찰을 안 뽑아
  // 오리/경찰이 랜덤으로 나오게 한다.
  const taggerCount = players.length <= C.TAGGER_COUNT && Math.random() < 0.5 ? 0 : C.TAGGER_COUNT;
  const taggerIds = new Set(players.slice(0, taggerCount).map((p) => p.playerId));
  for (const p of players) {
    if (taggerIds.has(p.playerId)) {
      p.team = 'tagger';
      p.character = 'aligator';
    } else {
      p.team = 'duck';
      p.character = p.duckSkin || 'duck';
    }
  }
}

function setNickname(room, playerId, nickname) {
  const player = room.players.get(playerId);
  if (!player) return;
  player.nickname = (nickname || '').trim() || 'Player';
}

// 역할은 게임 시작 시 무작위로 배정되므로, 시작 조건은 팀 구성이 아니라 인원수로만 판단한다.
function canStartGame(room) {
  const count = room.players.size;
  // Temporary solo-test mode: allow starting with one player while UI/gameplay is being tuned.
  return count >= 1 && count <= C.MAX_PLAYERS;
}

function removePlayer(room, playerId) {
  room.players.delete(playerId);
  room.carryQueues.delete(playerId);
  room.activeDashes.delete(playerId);

  if (room.players.size === 0) {
    rooms.delete(room.roomId);
    return;
  }

  if (room.hostPlayerId === playerId) {
    room.hostPlayerId = room.players.keys().next().value;
  }
}

function findRoomAndPlayerBySocket(ws) {
  if (!ws.roomId || !ws.playerId) return { room: null, player: null };
  const room = rooms.get(ws.roomId);
  if (!room) return { room: null, player: null };
  return { room, player: room.players.get(ws.playerId) || null };
}

function sendTo(ws, message) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function broadcastToRoom(room, message) {
  for (const player of room.players.values()) {
    sendTo(player.ws, message);
  }
}

function serializeRoomState(room) {
  const players = [];
  for (const p of room.players.values()) players.push(serializePlayer(p));
  return {
    players,
    hostPlayerId: room.hostPlayerId,
    joinCode: room.roomId,
    roomName: room.roomName,
    isPrivate: room.isPrivate,
  };
}

function serializeGameState(room) {
  const players = [];
  for (const p of room.players.values()) players.push(serializePlayer(p));
  const queueIndexById = new Map();
  for (const queue of room.carryQueues.values()) {
    queue.forEach((ducklingId, index) => queueIndexById.set(ducklingId, index));
  }
  const ducklings = [];
  for (const d of room.ducklings.values()) {
    ducklings.push(serializeDuckling(d, queueIndexById.get(d.ducklingId)));
  }
  return {
    roomId: room.roomId,
    phase: room.phase,
    countdownSeconds: room.countdownSeconds,
    remainingSeconds: room.remainingSeconds,
    score: room.score,
    targetScore: room.targetScore,
    players,
    ducklings,
    winner: room.winner,
    endReason: room.endReason,
    rescueProgress: room.rescueProgress,
    activeRescuerId: room.activeRescuerId,
  };
}

module.exports = {
  rooms,
  createRoom,
  listRooms,
  joinRoom,
  assignRandomRoles,
  setNickname,
  canStartGame,
  removePlayer,
  findRoomAndPlayerBySocket,
  sendTo,
  broadcastToRoom,
  serializePlayer,
  serializeDuckling,
  serializeRoomState,
  serializeGameState,
  spawnPositionForCharacter,
  countTeam,
};
