// ChanChan FPS server: serves the game files and runs online 1v1 / 2v2 matches (first to 5 rounds).
// Run: npm start  (PORT env var, default 3000)
const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 3000;
const ROOT = __dirname;
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.wav': 'audio/wav', '.ogg': 'audio/ogg',
  '.mp3': 'audio/mpeg', '.txt': 'text/plain; charset=utf-8',
};
// only these folders/files are served; server code and node_modules stay private
const PUBLIC = [/^\/index\.html$/, /^\/lib\//, /^\/img\//, /^\/sounds\//, /^\/Assets\//];

const server = http.createServer((req, res) => {
  let urlPath;
  try { urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname); } catch { res.writeHead(400); return res.end(); }
  if (urlPath === '/') urlPath = '/index.html';
  const file = path.normalize(path.join(ROOT, urlPath));
  if (!file.startsWith(ROOT + path.sep) || !PUBLIC.some(r => r.test(urlPath))) { res.writeHead(404); return res.end('not found'); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(data);
  });
});

// ── MATCH RULES ──
const RULES = { winScore: 5, prestart: 3, roundTime: 100, post: 3, maxHit: 150 };
const MODES = { '1v1': 1, '2v2': 2 };   // players per team
const SPAWNS = {
  blue: [[-3, -24, 0], [3, -24, 0]],     // [x, z, yaw°]; yaw 0 faces +z
  red: [[3, 24, 180], [-3, 24, 180]],
};

const rooms = new Map();
let nextId = 1;

function makeCode() {
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  let c;
  do { c = Array.from({ length: 4 }, () => A[Math.floor(Math.random() * A.length)]).join(''); } while (rooms.has(c));
  return c;
}
const send = (ws, msg) => { if (ws.readyState === 1) ws.send(JSON.stringify(msg)); };
const broadcast = (room, msg, exceptId) => { for (const p of room.players.values()) if (p.id !== exceptId) send(p.ws, msg); };
const teamOf = (room, team) => [...room.players.values()].filter(p => p.team === team);

function lobbyInfo(room) {
  return {
    t: 'lobby', room: room.code, mode: room.mode, host: room.host, phase: room.phase, score: room.score,
    players: [...room.players.values()].map(p => ({ id: p.id, name: p.name, team: p.team })),
  };
}

function startRound(room) {
  room.round += 1;
  room.phase = 'prestart';
  room.timer = RULES.prestart;
  const spawns = {};
  for (const team of ['blue', 'red']) {
    teamOf(room, team).forEach((p, i) => {
      const s = SPAWNS[team][i % SPAWNS[team].length];
      p.hp = 100; p.dead = false;
      p.state = { p: [s[0], 0, s[1]], yaw: s[2], pitch: 0, w: 'rifle' };
      spawns[p.id] = s;
    });
  }
  broadcast(room, { t: 'round', phase: 'prestart', round: room.round, score: room.score, timer: room.timer, spawns });
}

function endRound(room, winner, reason) {
  if (winner) room.score[winner] += 1;
  room.phase = 'post';
  room.timer = RULES.post;
  broadcast(room, { t: 'round', phase: 'post', round: room.round, score: room.score, winner, reason, timer: room.timer });
}

function endMatch(room, winner) {
  room.phase = 'end';
  broadcast(room, { t: 'end', winner, score: room.score });
  room.phase = 'lobby';
  broadcast(room, lobbyInfo(room));
}

function checkRoundOver(room) {
  if (room.phase !== 'live') return;
  const blueAlive = teamOf(room, 'blue').filter(p => !p.dead).length;
  const redAlive = teamOf(room, 'red').filter(p => !p.dead).length;
  if (blueAlive === 0 || redAlive === 0) endRound(room, blueAlive > 0 ? 'blue' : redAlive > 0 ? 'red' : null, 'elim');
}

function tickRoom(room, dt) {
  if (room.phase === 'lobby' || room.phase === 'end') return;
  room.timer -= dt;
  if (room.phase === 'prestart' && room.timer <= 0) {
    room.phase = 'live';
    room.timer = RULES.roundTime;
    broadcast(room, { t: 'round', phase: 'live', round: room.round, score: room.score, timer: room.timer });
  } else if (room.phase === 'live' && room.timer <= 0) {
    // time out: more players alive wins, then more total HP; otherwise a draw
    const alive = t => teamOf(room, t).filter(p => !p.dead);
    const hp = t => alive(t).reduce((s, p) => s + p.hp, 0);
    const b = alive('blue').length, r = alive('red').length;
    endRound(room, b !== r ? (b > r ? 'blue' : 'red') : hp('blue') !== hp('red') ? (hp('blue') > hp('red') ? 'blue' : 'red') : null, 'time');
  } else if (room.phase === 'post' && room.timer <= 0) {
    const w = room.score.blue >= RULES.winScore ? 'blue' : room.score.red >= RULES.winScore ? 'red' : null;
    if (w) endMatch(room, w); else startRound(room);
  }
  // 20 Hz snapshot of everyone
  broadcast(room, {
    t: 'snap', timer: room.timer, phase: room.phase,
    ps: [...room.players.values()].map(p => ({ id: p.id, ...p.state, hp: p.hp, dead: p.dead })),
  });
}

function leave(room, p) {
  room.players.delete(p.id);
  if (room.players.size === 0) { rooms.delete(room.code); return; }
  if (room.host === p.id) room.host = room.players.keys().next().value;
  broadcast(room, { t: 'left', id: p.id });
  if (room.phase !== 'lobby') {
    // a team emptied mid-match: the other side wins
    const b = teamOf(room, 'blue').length, r = teamOf(room, 'red').length;
    if (b === 0 || r === 0) return endMatch(room, b > 0 ? 'blue' : 'red');
    checkRoundOver(room);
  }
  broadcast(room, lobbyInfo(room));
}

const wss = new WebSocketServer({ server });
wss.on('connection', ws => {
  const me = { id: nextId++, ws, name: 'player', team: 'blue', hp: 100, dead: false, state: { p: [0, 0, 0], yaw: 0, pitch: 0, w: 'rifle' } };
  let room = null;

  ws.on('message', raw => {
    let m;
    try { m = JSON.parse(raw); } catch { return; }
    if (!m || typeof m.t !== 'string') return;

    if (m.t === 'create' || m.t === 'join') {
      if (room) return;
      me.name = String(m.name || 'player').slice(0, 12) || 'player';
      if (m.t === 'create') {
        if (!MODES[m.mode]) return send(ws, { t: 'error', msg: '모드가 올바르지 않아요' });
        room = { code: makeCode(), mode: m.mode, players: new Map(), host: me.id, phase: 'lobby', round: 0, score: { blue: 0, red: 0 }, timer: 0 };
        rooms.set(room.code, room);
      } else {
        const r = rooms.get(String(m.room || '').toUpperCase());
        if (!r) return send(ws, { t: 'error', msg: '방을 찾을 수 없어요' });
        if (r.players.size >= MODES[r.mode] * 2) return send(ws, { t: 'error', msg: '방이 꽉 찼어요' });
        if (r.phase !== 'lobby') return send(ws, { t: 'error', msg: '이미 경기 중인 방이에요' });
        room = r;
      }
      me.team = teamOf(room, 'blue').length <= teamOf(room, 'red').length ? 'blue' : 'red';
      room.players.set(me.id, me);
      send(ws, { t: 'welcome', id: me.id });
      broadcast(room, lobbyInfo(room));
      return;
    }
    if (!room) return;

    switch (m.t) {
      case 'team': {   // switch sides in the lobby if there's space
        const per = MODES[room.mode];
        if (room.phase === 'lobby' && (m.team === 'blue' || m.team === 'red') && teamOf(room, m.team).length < per) {
          me.team = m.team;
          broadcast(room, lobbyInfo(room));
        }
        break;
      }
      case 'start':
        if (me.id !== room.host || room.phase !== 'lobby') return;
        if (!teamOf(room, 'blue').length || !teamOf(room, 'red').length) return send(ws, { t: 'error', msg: '양 팀에 최소 1명씩 있어야 해요' });
        room.score = { blue: 0, red: 0 };
        room.round = 0;
        startRound(room);
        break;
      case 'state':
        if (room.phase === 'lobby' || me.dead || !Array.isArray(m.p)) return;
        me.state = { p: m.p.slice(0, 3).map(Number), yaw: +m.yaw || 0, pitch: +m.pitch || 0, w: m.w === 'knife' ? 'knife' : 'rifle', ads: !!m.ads };
        break;
      case 'shot':    // cosmetic: muzzle flash + tracer on everyone else's screen
        if (room.phase === 'live' && !me.dead) broadcast(room, { t: 'shot', id: me.id, o: m.o, e: m.e }, me.id);
        break;
      case 'anim':    // cosmetic: knife swing on everyone else's screen
        if (!me.dead) broadcast(room, { t: 'anim', id: me.id, name: String(m.name || '') }, me.id);
        break;
      case 'hit': {
        const target = room.players.get(m.target);
        if (room.phase !== 'live' || me.dead || !target || target.dead || target.team === me.team) return;
        const dmg = Math.max(0, Math.min(RULES.maxHit, Number(m.dmg) || 0));
        target.hp -= dmg;
        broadcast(room, { t: 'hp', id: target.id, hp: Math.max(0, target.hp), by: me.id, head: !!m.head });
        if (target.hp <= 0) {
          target.dead = true;
          broadcast(room, { t: 'kill', killer: me.id, victim: target.id, head: !!m.head, w: m.w === 'knife' ? 'knife' : 'rifle' });
          checkRoundOver(room);
        }
        break;
      }
    }
  });

  ws.on('close', () => { if (room) leave(room, me); });
});

let last = Date.now();
setInterval(() => {
  const now = Date.now();
  const dt = (now - last) / 1000;
  last = now;
  for (const room of rooms.values()) tickRoom(room, dt);
}, 50);

server.listen(PORT, () => console.log(`ChanChan server on http://localhost:${PORT}`));
