'use strict';

// client/scripts/autoload/MockServer.gd 의 시뮬레이션 로직을 그대로 포팅한다.
// 함수 이름은 MockServer.gd의 대응 함수를 유추할 수 있게 지었다 (Docs/api-spec.md
// "서버 판정 로직 요약" 표 참고).

const C = require('./constants');
const rooms = require('./rooms');

// ── 벡터 유틸 (XZ 평면) ──────────────────────────────────────────────────────

function pushOutOfProps(pos) {
  let result = { x: pos.x, z: pos.z };
  for (const obs of C.POND_OBSTACLES) {
    const minDist = obs.radius + C.DUCKLING_OBSTACLE_PADDING;
    let ox = result.x - obs.x;
    let oz = result.z - obs.z;
    let dist = Math.hypot(ox, oz);
    if (dist < minDist) {
      if (dist < 0.001) {
        ox = 1;
        oz = 0;
        dist = 0.001;
      }
      const nx = ox / dist;
      const nz = oz / dist;
      result = { x: obs.x + nx * minDist, z: obs.z + nz * minDist };
    }
  }
  return result;
}

function distancePointToSegment(p, a, b) {
  const abx = b.x - a.x;
  const abz = b.z - a.z;
  const lenSq = abx * abx + abz * abz;
  if (lenSq < 0.0001) {
    return Math.hypot(p.x - a.x, p.z - a.z);
  }
  let t = ((p.x - a.x) * abx + (p.z - a.z) * abz) / lenSq;
  t = Math.max(0, Math.min(1, t));
  const cx = a.x + abx * t;
  const cz = a.z + abz * t;
  return Math.hypot(p.x - cx, p.z - cz);
}

function randRange(min, max) {
  return min + Math.random() * (max - min);
}

// ── 브로드캐스트 헬퍼 ─────────────────────────────────────────────────────────

function broadcastRoomState(room) {
  rooms.broadcastToRoom(room, { type: 'room:state', roomId: room.roomId, payload: rooms.serializeRoomState(room) });
}

function broadcastGameState(room) {
  rooms.broadcastToRoom(room, { type: 'game:state', roomId: room.roomId, payload: rooms.serializeGameState(room) });
}

function broadcastEvent(room, event, data) {
  rooms.broadcastToRoom(room, { type: 'game:event', roomId: room.roomId, payload: { event, ...data } });
}

// ── 스폰 위치 ────────────────────────────────────────────────────────────────

function randomPlayerSpawnPosition() {
  const angle = randRange(0, Math.PI * 2);
  const distance = randRange(24.0, 58.0);
  return { x: Math.cos(angle) * distance, y: 0.0, z: Math.sin(angle) * distance };
}

function countdownPositionForIndex(index) {
  const offsets = [
    { x: -4.0, y: 0.0, z: 0.0 },
    { x: 4.0, y: 0.0, z: 0.0 },
    { x: 0.0, y: 0.0, z: 4.0 },
  ];
  const o = offsets[index % offsets.length];
  return { x: o.x, y: 2.2 + o.y, z: o.z };
}

function placePlayersInCountdown(room) {
  let i = 0;
  for (const player of room.players.values()) {
    player.state = 'idle';
    player.position = countdownPositionForIndex(i);
    player.rotationY = 0.0;
    i++;
  }
}

function placePlayersAtRoleSpawns(room) {
  for (const player of room.players.values()) {
    player.state = 'idle';
    player.position = randomPlayerSpawnPosition();
    player.rotationY = randRange(-Math.PI, Math.PI);
  }
}

function spawnDuckling(id, existingPositions) {
  // 감옥 섬 외부(XZ 15.0~88.0)의 물 영역 전체에 균일 밀도로 스폰시키되(면적 기준 균일
  // 분포를 위해 반지름 제곱을 랜덤화), 이미 배치된 새끼오리들과 DUCKLING_MIN_SEPARATION
  // 이상 떨어질 때까지 재시도하는 블루노이즈 방식으로 뭉침을 방지한다.
  const minDist = 15.0;
  const maxDist = 88.0;
  let spawnPos = { x: 0, z: 0 };
  for (let attempt = 0; attempt < C.DUCKLING_PLACEMENT_ATTEMPTS; attempt++) {
    const angle = randRange(0, Math.PI * 2);
    const dist = Math.sqrt(randRange(minDist * minDist, maxDist * maxDist));
    spawnPos = pushOutOfProps({ x: Math.cos(angle) * dist, z: Math.sin(angle) * dist });
    const farEnough = existingPositions.every(
      (other) => Math.hypot(spawnPos.x - other.x, spawnPos.z - other.z) >= C.DUCKLING_MIN_SEPARATION
    );
    if (farEnough) break;
  }
  return {
    ducklingId: id,
    position: { x: spawnPos.x, y: 0.0, z: spawnPos.z },
    state: 'spawned',
    carrierPlayerId: null,
    deliveryBatchId: null,
  };
}

function countLiveDucklings(room) {
  let count = 0;
  for (const d of room.ducklings.values()) {
    if (d.state !== 'delivered') count++;
  }
  return count;
}

// ── 게임 시작/카운트다운/종료 ─────────────────────────────────────────────────

function startGame(room) {
  if (!rooms.canStartGame(room)) return false;

  rooms.assignRandomRoles(room);
  room.targetScore = rooms.countTeam(room, 'duck') * 10;

  room.broadcastTimer = 0;
  room.secondTimer = 0;
  room.countdownTimer = C.COUNTDOWN_SECONDS;
  room.phase = 'countdown';
  room.countdownSeconds = C.COUNTDOWN_SECONDS;
  room.remainingSeconds = C.GAME_DURATION_SECONDS;
  room.score = 0;
  room.winner = null;
  room.endReason = null;

  room.wanderState.clear();
  room.carryQueues.clear();
  room.playerMotion.clear();
  room.deliveringSettle.clear();
  room.deliveryBatches.clear();
  room.activeDashes.clear();
  room.nextDeliveryBatchId = 1;

  room.ducklings.clear();
  const placedPositions = [];
  for (let i = 0; i < C.MAX_DUCKLINGS_ON_MAP; i++) {
    const d = spawnDuckling(`d${i + 1}`, placedPositions);
    room.ducklings.set(d.ducklingId, d);
    placedPositions.push({ x: d.position.x, z: d.position.z });
  }
  room.nextDucklingId = C.MAX_DUCKLINGS_ON_MAP + 1;

  placePlayersInCountdown(room);
  broadcastGameState(room);
  return true;
}

function beginPlaying(room) {
  room.phase = 'playing';
  room.countdownSeconds = 0;
  placePlayersAtRoleSpawns(room);
  broadcastEvent(room, 'game_started', {});
  broadcastGameState(room);
}

function tickCountdown(room, delta) {
  room.countdownTimer = Math.max(0, room.countdownTimer - delta);
  const nextSeconds = Math.ceil(room.countdownTimer);
  if (nextSeconds !== room.countdownSeconds) {
    room.countdownSeconds = nextSeconds;
    broadcastGameState(room);
  }
  if (room.countdownTimer <= 0) {
    beginPlaying(room);
  }
}

function endGame(room, winner, reason) {
  room.phase = 'ended';
  room.countdownSeconds = 0;
  room.winner = winner;
  room.endReason = reason;
  broadcastEvent(room, 'game_ended', { winner, reason });
  broadcastGameState(room);
}

function returnToLobby(room) {
  room.phase = 'lobby';
  room.countdownSeconds = 0;
  room.remainingSeconds = 0;
  room.winner = null;
  room.endReason = null;
  room.ducklings.clear();

  room.deliveryBatches.clear();
  room.wanderState.clear();
  room.carryQueues.clear();
  room.playerMotion.clear();
  room.deliveringSettle.clear();
  room.activeDashes.clear();
  resetRescue(room);

  for (const player of room.players.values()) {
    player.state = 'idle';
    player.jailRemaining = null;
    player.position = rooms.spawnPositionForCharacter(player.character);
  }

  broadcastRoomState(room);
  broadcastGameState(room);
}

// ── 새끼오리: 배회 / 획득 / 추종 / 반납 ───────────────────────────────────────

function updateDucklingWander(room, delta) {
  for (const d of room.ducklings.values()) {
    if (d.state !== 'spawned') continue;
    const id = d.ducklingId;
    let w = room.wanderState.get(id) || { dir: { x: 0, z: 0 }, timer: 0 };
    w.timer -= delta;
    if (w.timer <= 0 || (w.dir.x === 0 && w.dir.z === 0)) {
      const angle = randRange(0, Math.PI * 2);
      w.dir = { x: Math.cos(angle), z: Math.sin(angle) };
      w.timer = randRange(C.WANDER_TURN_INTERVAL * 0.5, C.WANDER_TURN_INTERVAL * 1.5);
    }
    room.wanderState.set(id, w);

    const pos = d.position;
    const nextX = Math.max(-C.POND_BOUND, Math.min(C.POND_BOUND, pos.x + w.dir.x * C.WANDER_SPEED * delta));
    const nextZ = Math.max(-C.POND_BOUND, Math.min(C.POND_BOUND, pos.z + w.dir.z * C.WANDER_SPEED * delta));

    const pushedPos = pushOutOfProps({ x: nextX, z: nextZ });
    if (pushedPos.x !== nextX || pushedPos.z !== nextZ) {
      w.dir = { x: -w.dir.x, z: -w.dir.z };
      room.wanderState.set(id, w);
    }
    d.position = { x: pushedPos.x, y: pos.y, z: pushedPos.z };
  }
}

function checkPickup(room) {
  for (const player of room.players.values()) {
    if (player.team !== 'duck') continue;
    for (const d of room.ducklings.values()) {
      if (d.state !== 'spawned') continue;
      const dist = Math.hypot(player.position.x - d.position.x, player.position.z - d.position.z);
      if (dist <= C.PICKUP_DISTANCE) {
        d.state = 'carried';
        d.carrierPlayerId = player.playerId;
        room.wanderState.delete(d.ducklingId);
        const queue = room.carryQueues.get(player.playerId) || [];
        queue.push(d.ducklingId);
        room.carryQueues.set(player.playerId, queue);
      }
    }
  }
}

function releaseDucklings(room, playerId, atPosition) {
  const queue = room.carryQueues.get(playerId) || [];
  if (queue.length === 0) return;
  for (const ducklingId of queue) {
    const d = room.ducklings.get(ducklingId);
    if (!d) continue;
    const angle = randRange(0, Math.PI * 2);
    const radius = randRange(1.0, 3.0);
    const dropX = atPosition.x + Math.cos(angle) * radius;
    const dropZ = atPosition.z + Math.sin(angle) * radius;
    const flatDrop = pushOutOfProps({ x: dropX, z: dropZ });

    d.position = { x: flatDrop.x, y: 0.0, z: flatDrop.z };
    d.state = 'spawned';
    d.carrierPlayerId = null;
    room.wanderState.delete(ducklingId);
  }
  room.carryQueues.set(playerId, []);
  broadcastGameState(room);
}

function updatePlayerMotion(room, delta) {
  for (const player of room.players.values()) {
    if (player.team !== 'duck') continue;
    const pos = player.position;
    const m = room.playerMotion.get(player.playerId) || { prevPos: pos, isMoving: false, idleSpin: 0 };
    let speed = 0;
    if (delta > 0) {
      speed = Math.hypot(pos.x - m.prevPos.x, pos.y - m.prevPos.y, pos.z - m.prevPos.z) / delta;
    }
    m.isMoving = speed > C.MOVING_SPEED_THRESHOLD;
    m.prevPos = pos;
    if (!m.isMoving) {
      m.idleSpin += delta * C.CIRCLE_SPIN_SPEED;
    }
    room.playerMotion.set(player.playerId, m);
  }
}

function updateDucklingFollow(room, delta) {
  for (const [playerId, queue] of room.carryQueues) {
    if (queue.length === 0) continue;
    const player = room.players.get(playerId);
    if (!player) continue;
    const playerPos = player.position;
    const motion = room.playerMotion.get(playerId) || { isMoving: false, idleSpin: 0 };

    if (motion.isMoving) {
      let leaderPos = playerPos;
      for (let i = 0; i < queue.length; i++) {
        const d = room.ducklings.get(queue[i]);
        if (!d) continue;
        const current = d.position;
        const toLeaderX = current.x - leaderPos.x;
        const toLeaderZ = current.z - leaderPos.z;
        const dist = Math.hypot(toLeaderX, toLeaderZ);
        let dirX = 0;
        let dirZ = -1; // Vector3.BACK -> (0,0,1) in Godot, but sign only matters when dist>0.01
        if (dist > 0.01) {
          dirX = toLeaderX / dist;
          dirZ = toLeaderZ / dist;
        } else {
          dirX = 0;
          dirZ = 1;
        }
        let nextPos;
        if (dist > C.FOLLOW_LEASH) {
          nextPos = { x: leaderPos.x + dirX * C.FOLLOW_LEASH, y: current.y, z: leaderPos.z + dirZ * C.FOLLOW_LEASH };
        } else {
          const targetX = leaderPos.x + dirX * C.FOLLOW_SPACING;
          const targetZ = leaderPos.z + dirZ * C.FOLLOW_SPACING;
          const lerpSpeed = Math.max(C.FOLLOW_LERP_MIN, C.FOLLOW_LERP_SPEED - i * C.FOLLOW_LERP_FALLOFF);
          const t = Math.max(0, Math.min(1, delta * lerpSpeed));
          nextPos = {
            x: current.x + (targetX - current.x) * t,
            y: current.y,
            z: current.z + (targetZ - current.z) * t,
          };
        }
        d.position = nextPos;
        leaderPos = nextPos;
      }
    } else {
      const count = queue.length;
      for (let i = 0; i < count; i++) {
        const d = room.ducklings.get(queue[i]);
        if (!d) continue;
        const angle = motion.idleSpin + ((Math.PI * 2) / count) * i;
        const targetX = playerPos.x + Math.cos(angle) * C.CIRCLE_RADIUS;
        const targetZ = playerPos.z + Math.sin(angle) * C.CIRCLE_RADIUS;
        const current = d.position;
        const t = Math.max(0, Math.min(1, delta * C.CIRCLE_LERP_SPEED));
        d.position = {
          x: current.x + (targetX - current.x) * t,
          y: current.y,
          z: current.z + (targetZ - current.z) * t,
        };
      }
    }
  }
}

function nearestNest(pos) {
  let nearest = C.NEST_POSITIONS[0];
  let minDist = Math.hypot(pos.x - nearest.x, pos.z - nearest.z);
  for (const nest of C.NEST_POSITIONS) {
    const dist = Math.hypot(pos.x - nest.x, pos.z - nest.z);
    if (dist < minDist) {
      minDist = dist;
      nearest = nest;
    }
  }
  return { nest: nearest, dist: minDist };
}

function checkDeliver(room) {
  for (const player of room.players.values()) {
    if (player.team !== 'duck') continue;
    const queue = room.carryQueues.get(player.playerId) || [];
    if (queue.length === 0) continue;

    const { nest, dist } = nearestNest(player.position);
    if (dist > C.DELIVER_DISTANCE) continue;

    const deliveringDucklings = [];
    for (const ducklingId of queue) {
      const d = room.ducklings.get(ducklingId);
      if (d) deliveringDucklings.push(d);
    }
    if (deliveringDucklings.length === 0) {
      room.carryQueues.set(player.playerId, []);
      continue;
    }

    const batchId = `delivery_${room.nextDeliveryBatchId}`;
    room.nextDeliveryBatchId += 1;
    room.deliveryBatches.set(batchId, {
      playerId: player.playerId,
      playerName: player.nickname,
      total: deliveringDucklings.length,
      delivered: 0,
      targetNestPos: nest,
    });

    for (const d of deliveringDucklings) {
      d.state = 'delivering';
      d.carrierPlayerId = null;
      d.deliveryBatchId = batchId;
    }

    room.carryQueues.set(player.playerId, []);
  }
}

function deliverDuckling(room, d) {
  d.state = 'delivered';
  room.score += 1;

  const batchId = d.deliveryBatchId;
  d.deliveryBatchId = null;

  room.ducklings.delete(d.ducklingId);
  if (countLiveDucklings(room) < C.MAX_DUCKLINGS_ON_MAP) {
    const existingPositions = Array.from(room.ducklings.values()).map((o) => ({ x: o.position.x, z: o.position.z }));
    const newDuckling = spawnDuckling(`d${room.nextDucklingId++}`, existingPositions);
    room.ducklings.set(newDuckling.ducklingId, newDuckling);
  }

  if (!batchId || !room.deliveryBatches.has(batchId)) {
    broadcastEvent(room, 'duckling_delivered', { ducklingId: d.ducklingId, count: 1 });
    if (room.score >= room.targetScore) endGame(room, 'duck', 'duck_goal');
    return;
  }

  const batch = room.deliveryBatches.get(batchId);
  batch.delivered += 1;
  if (batch.delivered < batch.total) return;

  room.deliveryBatches.delete(batchId);
  broadcastEvent(room, 'duckling_delivered', {
    ducklingId: d.ducklingId,
    count: batch.total,
    playerId: batch.playerId,
    playerName: batch.playerName,
  });
  if (room.score >= room.targetScore) endGame(room, 'duck', 'duck_goal');
}

function updateDelivering(room, delta) {
  for (const d of room.ducklings.values()) {
    if (d.state !== 'delivering') continue;
    const current = d.position;

    let targetNest = C.NEST_POSITIONS[0];
    const batchId = d.deliveryBatchId;
    if (batchId && room.deliveryBatches.has(batchId)) {
      targetNest = room.deliveryBatches.get(batchId).targetNestPos;
    }

    const toNestX = targetNest.x - current.x;
    const toNestZ = targetNest.z - current.z;
    const dist = Math.hypot(toNestX, toNestZ);
    if (dist > C.NEST_ARRIVE_DISTANCE) {
      const step = Math.min(C.DELIVER_MOVE_SPEED * delta, dist);
      d.position = {
        x: current.x + (toNestX / dist) * step,
        y: current.y,
        z: current.z + (toNestZ / dist) * step,
      };
      continue;
    }

    d.position = { x: targetNest.x, y: targetNest.y, z: targetNest.z };
    const settled = (room.deliveringSettle.get(d.ducklingId) || 0) + delta;
    room.deliveringSettle.set(d.ducklingId, settled);
    if (settled >= C.NEST_SETTLE_TIME) {
      room.deliveringSettle.delete(d.ducklingId);
      deliverDuckling(room, d);
    }
  }
}

// ── 대시 판정 ────────────────────────────────────────────────────────────────

function beginDash(room, playerId, startPos, endPos, duration) {
  broadcastEvent(room, 'dash_started', { playerId });
  room.activeDashes.set(playerId, {
    a: { x: startPos.x, z: startPos.z },
    b: { x: endPos.x, z: endPos.z },
    timeLeft: duration,
  });
}

function checkDashCatch(room, a, b) {
  for (const player of room.players.values()) {
    if (player.team !== 'duck') continue;
    if (player.state === 'jailed') continue;
    const p = { x: player.position.x, z: player.position.z };
    if (distancePointToSegment(p, a, b) <= C.DASH_CATCH_HALF_WIDTH) {
      jailPlayer(room, player.playerId);
    }
  }
}

function updateDashCatches(room, delta) {
  for (const [dasherId, dash] of room.activeDashes) {
    dash.timeLeft -= delta;
    if (dash.timeLeft <= 0) {
      room.activeDashes.delete(dasherId);
      continue;
    }
    checkDashCatch(room, dash.a, dash.b);
  }
}

// ── 감옥 / 구출 ──────────────────────────────────────────────────────────────

function countDuckPlayers(room) {
  return rooms.countTeam(room, 'duck');
}

function countJailedDucks(room) {
  let count = 0;
  for (const p of room.players.values()) {
    if (p.team === 'duck' && p.state === 'jailed') count++;
  }
  return count;
}

function randomReleasePos() {
  const angle = randRange(0, Math.PI * 2);
  return {
    x: C.JAIL_POSITION.x + Math.cos(angle) * C.JAIL_RELEASE_RADIUS,
    y: 0.0,
    z: C.JAIL_POSITION.z + Math.sin(angle) * C.JAIL_RELEASE_RADIUS,
  };
}

function resetRescue(room) {
  room.rescueTimer = 0;
  room.isRescuing = false;
  room.activeRescuerId = '';
  room.rescueProgress = 0.0;
}

function releasePlayer(room, playerId, isRescue) {
  const releasePos = randomReleasePos();
  const player = room.players.get(playerId);
  if (!player) return;
  player.state = 'idle';
  player.jailRemaining = null;
  player.position = releasePos;

  if (isRescue) {
    broadcastEvent(room, 'player_rescued', { targetId: playerId, rescuerId: room.activeRescuerId, releasePosition: releasePos });
  } else {
    broadcastEvent(room, 'player_released', { playerId, releasePosition: releasePos });
  }
  broadcastGameState(room);
}

function rescueAllJailed(room) {
  const jailedIds = [];
  for (const p of room.players.values()) {
    if (p.team === 'duck' && p.state === 'jailed') jailedIds.push(p.playerId);
  }
  for (const pid of jailedIds) releasePlayer(room, pid, true);
}

function jailPlayer(room, playerId) {
  const player = room.players.get(playerId);
  if (!player) return;
  if (player.state === 'jailed') return; // 이미 수감 중

  player.state = 'jailed';
  if (countDuckPlayers(room) === 1) {
    player.jailRemaining = C.JAIL_SECONDS;
  } else {
    player.jailRemaining = null;
  }
  const catchPos = { ...player.position };
  player.position = { ...C.JAIL_POSITION };
  releaseDucklings(room, playerId, catchPos);

  resetRescue(room);
  broadcastEvent(room, 'player_jailed', { playerId });

  const totalDucks = countDuckPlayers(room);
  if (totalDucks > 1 && countJailedDucks(room) >= totalDucks) {
    // 잡히는 동작(수감 처리)은 즉시 일어나지만, 종료 메세지는 ALL_JAILED_END_DELAY초 뒤
    // updateAllJailedEnd에서 다시 확인 후 띄운다 (대시를 누른 순간 바로 승리 메세지가
    // 뜨는 것처럼 보이는 문제 방지).
    room.allJailedTimer = C.ALL_JAILED_END_DELAY;
    broadcastGameState(room);
    return;
  }
  broadcastGameState(room);
}

function updateAutoJailRelease(room, delta) {
  if (countDuckPlayers(room) !== 1) return;

  const releaseIds = [];
  for (const player of room.players.values()) {
    if (player.team !== 'duck') continue;
    if (player.state !== 'jailed') continue;
    const remaining = (player.jailRemaining ?? C.JAIL_SECONDS) - delta;
    player.jailRemaining = remaining;
    if (remaining <= 0) releaseIds.push(player.playerId);
  }

  for (const playerId of releaseIds) {
    room.activeRescuerId = '';
    releasePlayer(room, playerId, false);
  }
}

function updateAllJailedEnd(room, delta) {
  if (room.allJailedTimer < 0) return;

  const totalDucks = countDuckPlayers(room);
  if (totalDucks <= 1 || countJailedDucks(room) < totalDucks) {
    room.allJailedTimer = -1;
    return;
  }

  room.allJailedTimer -= delta;
  if (room.allJailedTimer <= 0) {
    room.allJailedTimer = -1;
    endGame(room, 'tagger', 'all_ducks_jailed');
  }
}

function updateJailAndRescue(room, delta) {
  updateAutoJailRelease(room, delta);
  const jailedCount = countJailedDucks(room);

  if (jailedCount === 0) {
    if (room.isRescuing) resetRescue(room);
    return;
  }

  const jailPos = C.JAIL_POSITION;
  let potentialRescuerId = '';
  for (const p of room.players.values()) {
    if (p.team !== 'duck') continue;
    if (p.state === 'jailed') continue;
    const dist = Math.hypot(p.position.x - jailPos.x, p.position.z - jailPos.z);
    if (dist <= C.RESCUE_RADIUS) {
      potentialRescuerId = p.playerId;
      break;
    }
  }

  if (potentialRescuerId === '') {
    if (room.isRescuing) resetRescue(room);
    return;
  }

  if (!room.isRescuing) {
    room.isRescuing = true;
    room.activeRescuerId = potentialRescuerId;
    room.rescueTimer = 0;
    broadcastEvent(room, 'rescue_started', { rescuerId: potentialRescuerId });
  }

  if (room.activeRescuerId !== potentialRescuerId) {
    resetRescue(room);
    return;
  }

  room.rescueTimer += delta;
  room.rescueProgress = Math.max(0, Math.min(1, room.rescueTimer / C.RESCUE_DURATION));

  if (room.rescueTimer >= C.RESCUE_DURATION) {
    rescueAllJailed(room);
    resetRescue(room);
  }
}

// ── 매 틱 진입점 ─────────────────────────────────────────────────────────────

function tick(room, delta) {
  if (room.phase === 'countdown') {
    tickCountdown(room, delta);
    return;
  }
  if (room.phase !== 'playing') return;

  room.secondTimer += delta;
  if (room.secondTimer >= 1.0) {
    room.secondTimer -= 1.0;
    room.remainingSeconds = Math.max(0, room.remainingSeconds - 1);
    if (room.remainingSeconds <= 0) {
      endGame(room, 'tagger', 'time_up');
      return;
    }
  }

  updateDucklingWander(room, delta);
  checkPickup(room);
  updatePlayerMotion(room, delta);
  updateDucklingFollow(room, delta);
  checkDeliver(room);
  updateDelivering(room, delta);
  updateDashCatches(room, delta);
  updateJailAndRescue(room, delta);
  updateAllJailedEnd(room, delta);

  room.broadcastTimer += delta;
  if (room.broadcastTimer >= 1 / C.STATE_TICK_RATE) {
    room.broadcastTimer = 0;
    broadcastGameState(room);
  }
}

function tickAll(delta) {
  for (const room of rooms.rooms.values()) {
    tick(room, delta);
  }
}

module.exports = {
  startGame,
  beginDash,
  jailPlayer,
  returnToLobby,
  endGame,
  tick,
  tickAll,
  broadcastRoomState,
  broadcastGameState,
};
