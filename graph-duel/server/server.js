'use strict';
// Graph Duel lobby + game server. Zero dependencies (own minimal WebSocket implementation).
//   node server.js            -> listens on $PORT or 8080
// Clients speak JSON over WebSocket. The server is authoritative: it holds every
// player's hidden position and every curve, and resolves damage itself.

const http = require('http');
const crypto = require('crypto');
const { parse, evaluate } = require('./formula');

const PORT = Number(process.env.PORT) || 8080;

// ----------------------------------------------------------------- rules
const CFG = {
  plane: 10,                       // plane spans -10..10 on both axes (4 quadrants)
  radius: 1 / Math.sqrt(Math.PI),  // circle with area 1 unit^2
  hp: 100,
  maxDmg: 40,                      // damage when the curve passes through the circle centre
  minDmg: 8,                       // damage when it only grazes the circle edge
  maxOps: 20,                      // formula complexity cap
  curveLife: 3,                    // a curve stays on the plane for this many rounds
  maxRounds: 25,                   // after this the highest HP wins
  placeSeconds: 90,
  plantSeconds: 60,
  relocateSeconds: 60,
  minPlayers: 2,
  maxPlayersLimit: 8,
};

// ----------------------------------------------------------------- geometry
// Distance from a point to the drawn part of a curve y = f(x), x in [-plane, plane].
function curveDistance(ast, px, py) {
  const P = CFG.plane;
  const step = 0.01;
  let best = Infinity, bx = 0, by = 0;
  let prevX = null, prevY = null;
  for (let x = -P; x <= P + 1e-9; x += step) {
    const y = evaluate(ast, x);
    const ok = Number.isFinite(y) && Math.abs(y) <= P;
    if (ok && prevX !== null && Math.abs(y - prevY) < 2) {
      // distance to segment prev -> cur
      const dx = x - prevX, dy = y - prevY;
      const l2 = dx * dx + dy * dy;
      let t = l2 > 0 ? ((px - prevX) * dx + (py - prevY) * dy) / l2 : 0;
      t = Math.max(0, Math.min(1, t));
      const cx = prevX + t * dx, cy = prevY + t * dy;
      const d = Math.hypot(px - cx, py - cy);
      if (d < best) { best = d; bx = cx; by = cy; }
    } else if (ok && prevX === null) {
      const d = Math.hypot(px - x, py - y);
      if (d < best) { best = d; bx = x; by = y; }
    }
    if (ok) { prevX = x; prevY = y; } else { prevX = null; prevY = null; }
  }
  return { d: best, x: bx, y: by };
}

function damageFor(d) {
  const f = Math.min(1, d / CFG.radius);
  return Math.round(CFG.maxDmg - (CFG.maxDmg - CFG.minDmg) * f);
}

// ----------------------------------------------------------------- minimal websocket
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

class Conn {
  constructor(socket) {
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.frag = [];
    this.alive = true;
    this.onmessage = () => {};
    this.onclose = () => {};
    socket.on('data', (d) => this.onData(d));
    socket.on('close', () => this.close());
    socket.on('error', () => this.close());
    this.ping = setInterval(() => this.sendFrame(0x9, Buffer.alloc(0)), 25000);
  }
  onData(d) {
    this.buf = Buffer.concat([this.buf, d]);
    for (;;) {
      if (this.buf.length < 2) return;
      const b0 = this.buf[0], b1 = this.buf[1];
      const fin = (b0 & 0x80) !== 0, op = b0 & 0x0f, masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f, off = 2;
      if (len === 126) { if (this.buf.length < 4) return; len = this.buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (this.buf.length < 10) return; len = Number(this.buf.readBigUInt64BE(2)); off = 10; }
      if (len > 65536) { this.terminate(); return; }
      const need = off + (masked ? 4 : 0) + len;
      if (this.buf.length < need) return;
      let payload = this.buf.subarray(off + (masked ? 4 : 0), need);
      if (masked) {
        const key = this.buf.subarray(off, off + 4);
        const out = Buffer.alloc(len);
        for (let i = 0; i < len; i++) out[i] = payload[i] ^ key[i & 3];
        payload = out;
      } else payload = Buffer.from(payload);
      this.buf = this.buf.subarray(need);
      if (op === 0x8) { this.sendFrame(0x8, Buffer.alloc(0)); this.close(); return; }
      if (op === 0x9) { this.sendFrame(0xa, payload); continue; }
      if (op === 0xa) continue;
      if (op === 0x1 || op === 0x0 || op === 0x2) {
        this.frag.push(payload);
        if (fin) {
          const msg = Buffer.concat(this.frag).toString('utf8');
          this.frag = [];
          try { this.onmessage(msg); } catch (e) { console.error('handler error', e); }
        }
      }
    }
  }
  sendFrame(op, payload) {
    if (!this.alive) return;
    const n = payload.length;
    let head;
    if (n < 126) head = Buffer.from([0x80 | op, n]);
    else if (n < 65536) { head = Buffer.alloc(4); head[0] = 0x80 | op; head[1] = 126; head.writeUInt16BE(n, 2); }
    else { head = Buffer.alloc(10); head[0] = 0x80 | op; head[1] = 127; head.writeBigUInt64BE(BigInt(n), 2); }
    this.socket.write(Buffer.concat([head, payload]));
  }
  send(obj) { this.sendFrame(0x1, Buffer.from(JSON.stringify(obj))); }
  terminate() { this.socket.destroy(); this.close(); }
  close() {
    if (!this.alive) return;
    this.alive = false;
    clearInterval(this.ping);
    try { this.socket.end(); } catch (_) { /* ignore */ }
    this.onclose();
  }
}

// ----------------------------------------------------------------- lobbies
const lobbies = new Map();   // key -> Lobby
let nextPlayerId = 1;

const clean = (s, n) => String(s == null ? '' : s).replace(/[\u0000-\u001f]/g, '').trim().slice(0, n);
const lobbyKey = (name) => name.toLowerCase();

class Lobby {
  constructor(name, password, maxPlayers) {
    this.name = name;
    this.password = password;
    this.maxPlayers = maxPlayers;
    this.players = [];          // join order
    this.creator = null;        // player id
    this.resetGame();
  }
  resetGame() {
    this.phase = 'lobby';       // lobby | placement | plant | relocate
    this.round = 0;
    this.curves = [];
    this.turnQueue = [];
    this.startOffset = 0;
    clearTimeout(this.timer);
    this.deadline = 0;
  }
  get inGame() { return this.phase !== 'lobby'; }
  alive() { return this.players.filter((p) => p.alive); }
  byId(id) { return this.players.find((p) => p.id === id); }
  broadcast(obj) { for (const p of this.players) p.conn.send(obj); }
  publicPlayers() {
    return this.players.map((p) => ({ id: p.id, name: p.name, hp: p.hp, alive: p.alive, done: !!p.done }));
  }
  lobbyUpdate() {
    this.broadcast({ type: 'lobby', lobby: this.name, max: this.maxPlayers, creator: this.creator, players: this.publicPlayers() });
  }
  state() {
    this.broadcast({
      type: 'state', phase: this.phase, round: this.round,
      turn: this.phase === 'plant' ? this.turnQueue[0] || null : null,
      seconds: this.deadline ? Math.max(0, Math.round((this.deadline - Date.now()) / 1000)) : 0,
      players: this.publicPlayers(),
    });
  }
  setTimer(seconds, fn) {
    clearTimeout(this.timer);
    this.deadline = Date.now() + seconds * 1000;
    this.timer = setTimeout(fn, seconds * 1000);
  }

  // ---- game flow
  start() {
    this.resetGame();
    this.round = 0;
    for (const p of this.players) { p.hp = CFG.hp; p.alive = true; p.pos = null; p.done = false; }
    this.startOffset = Math.floor(Math.random() * this.players.length);
    this.phase = 'placement';
    this.broadcast({ type: 'start', config: CFG, order: this.players.map((p) => p.id) });
    this.setTimer(CFG.placeSeconds, () => this.endPlacement());
    this.state();
  }
  endPlacement() {
    for (const p of this.alive()) {
      if (!p.pos) p.pos = { x: Math.round((Math.random() * 18 - 9) * 10) / 10, y: Math.round((Math.random() * 18 - 9) * 10) / 10 };
      p.done = false;
      p.conn.send({ type: 'placed', x: p.pos.x, y: p.pos.y });
    }
    this.beginRound();
  }
  beginRound() {
    this.round += 1;
    this.curves = this.curves.filter((c) => this.round - c.round < CFG.curveLife && this.byId(c.owner) && this.byId(c.owner).alive);
    const alive = this.players.filter((p) => p.alive);
    if (alive.length <= 1) return;
    const startIdx = (this.startOffset + this.round - 1) % this.players.length;
    // queue = alive players in join order, starting from the rotating starter
    const queue = [];
    for (let i = 0; i < this.players.length; i++) {
      const p = this.players[(startIdx + i) % this.players.length];
      if (p.alive) queue.push(p.id);
    }
    this.turnQueue = queue;
    for (const p of alive) p.done = false;
    this.phase = 'plant';
    this.armPlantTimer();
    this.state();
  }
  armPlantTimer() {
    this.setTimer(CFG.plantSeconds, () => this.advanceTurn(true));
  }
  advanceTurn() {
    this.turnQueue.shift();
    if (this.turnQueue.length === 0) return this.beginRelocate();
    this.armPlantTimer();
    this.state();
  }
  beginRelocate() {
    this.phase = 'relocate';
    for (const p of this.alive()) { p.done = false; p.pending = null; }
    this.setTimer(CFG.relocateSeconds, () => this.resolveRound());
    this.state();
  }
  maybeResolve() {
    if (this.phase === 'relocate' && this.alive().every((p) => p.done)) this.resolveRound();
  }
  resolveRound() {
    clearTimeout(this.timer);
    this.deadline = 0;
    for (const p of this.alive()) if (p.pending) p.pos = p.pending;
    const hits = [];
    for (const v of this.alive()) {
      for (const c of this.curves) {
        if (c.owner === v.id) continue;
        const r = curveDistance(c.ast, v.pos.x, v.pos.y);
        if (r.d <= CFG.radius) {
          hits.push({ victim: v.id, attacker: c.owner, curveId: c.id, formula: c.formula, d: r.d, dmg: damageFor(r.d), at: { x: r.x, y: r.y } });
        }
      }
    }
    const eliminated = [];
    for (const h of hits) this.byId(h.victim).hp -= h.dmg;
    for (const v of this.alive()) if (v.hp <= 0) { v.alive = false; eliminated.push(v.id); }
    const hpMap = {};
    for (const p of this.players) hpMap[p.id] = p.hp;
    for (const p of this.players) {
      const mine = hits.map((h) => {
        const involved = h.victim === p.id || h.attacker === p.id;
        const base = { victim: h.victim, attacker: h.attacker, dmg: h.dmg };
        return involved ? { ...base, curveId: h.curveId, formula: h.formula, d: h.d, at: h.at } : base;
      });
      p.conn.send({ type: 'round_result', round: this.round, hits: mine, hp: hpMap, eliminated });
    }
    // game end?
    const alive = this.alive();
    let over = null;
    if (alive.length <= 1) {
      let winners = alive.map((p) => p.id);
      if (alive.length === 0) {
        const best = Math.max(...this.players.map((p) => p.hp));
        winners = this.players.filter((p) => p.hp === best).map((p) => p.id);
      }
      over = { winners, reason: alive.length === 1 ? 'last_standing' : 'mutual_destruction' };
    } else if (this.round >= CFG.maxRounds) {
      const best = Math.max(...alive.map((p) => p.hp));
      over = { winners: alive.filter((p) => p.hp === best).map((p) => p.id), reason: 'round_limit' };
    }
    if (over) {
      const reveal = this.players.map((p) => ({ id: p.id, x: p.pos ? p.pos.x : null, y: p.pos ? p.pos.y : null }));
      const curves = this.curves.map((c) => ({ id: c.id, owner: c.owner, formula: c.formula }));
      this.broadcast({ type: 'game_over', ...over, hp: hpMap, positions: reveal, curves });
      this.resetGame();
      for (const p of this.players) { p.done = false; }
      this.lobbyUpdate();
      return;
    }
    // next round after a short pause so clients can show results
    this.phase = 'between';
    this.state();
    this.timer = setTimeout(() => this.beginRound(), 6000);
  }

  // ---- actions
  place(p, x, y) {
    if (this.phase !== 'placement' || !p.alive) return;
    const pos = validPos(x, y);
    if (!pos) return p.conn.send({ type: 'error', msg: 'Pick a spot on the plane.' });
    p.pos = pos; p.done = true;
    p.conn.send({ type: 'placed', x: pos.x, y: pos.y });
    this.state();
    if (this.alive().every((q) => q.done)) this.endPlacement();
  }
  plant(p, formula) {
    if (this.phase !== 'plant' || this.turnQueue[0] !== p.id) return p.conn.send({ type: 'error', msg: 'It is not your turn.' });
    let parsed;
    try { parsed = parse(formula); } catch (e) { return p.conn.send({ type: 'error', msg: e.message }); }
    if (parsed.ops > CFG.maxOps) return p.conn.send({ type: 'error', msg: `Too complex (max ${CFG.maxOps} operations).` });
    // reject curves that are entirely off-plane
    let visible = 0;
    for (let x = -CFG.plane; x <= CFG.plane; x += 0.05) {
      const y = evaluate(parsed.ast, x);
      if (Number.isFinite(y) && Math.abs(y) <= CFG.plane) visible++;
    }
    if (visible < 4) return p.conn.send({ type: 'error', msg: 'That curve never appears on the plane.' });
    const curve = { id: `${this.round}-${p.id}-${Math.random().toString(36).slice(2, 6)}`, owner: p.id, formula: parsed.src, ast: parsed.ast, round: this.round };
    this.curves.push(curve);
    p.done = true;
    p.conn.send({ type: 'plant_ok', curve: { id: curve.id, formula: curve.formula, round: curve.round, expires: curve.round + CFG.curveLife - 1 } });
    this.broadcast({ type: 'planted', by: p.id });
    this.advanceTurn();
  }
  pass(p) {
    if (this.phase !== 'plant' || this.turnQueue[0] !== p.id) return;
    p.done = true;
    this.broadcast({ type: 'planted', by: p.id, passed: true });
    this.advanceTurn();
  }
  relocate(p, x, y) {
    if (this.phase !== 'relocate' || !p.alive || p.done) return;
    const pos = validPos(x, y);
    if (!pos) return p.conn.send({ type: 'error', msg: 'Pick a spot on the plane.' });
    p.pending = pos; p.done = true;
    p.conn.send({ type: 'relocated', x: pos.x, y: pos.y });
    this.state();
    this.maybeResolve();
  }

  removePlayer(p) {
    const idx = this.players.indexOf(p);
    if (idx < 0) return;
    const wasTurn = this.phase === 'plant' && this.turnQueue[0] === p.id;
    this.players.splice(idx, 1);
    this.turnQueue = this.turnQueue.filter((id) => id !== p.id);
    this.curves = this.curves.filter((c) => c.owner !== p.id);
    if (this.players.length === 0) { clearTimeout(this.timer); lobbies.delete(lobbyKey(this.name)); return; }
    if (this.creator === p.id) this.creator = this.players[0].id;
    this.broadcast({ type: 'left', id: p.id, name: p.name });
    if (!this.inGame) return this.lobbyUpdate();
    const alive = this.alive();
    if (alive.length <= 1) {
      const hpMap = {};
      for (const q of this.players) hpMap[q.id] = q.hp;
      this.broadcast({ type: 'game_over', winners: alive.map((q) => q.id), reason: 'opponents_left', hp: hpMap, positions: [], curves: [] });
      this.resetGame();
      return this.lobbyUpdate();
    }
    if (this.phase === 'placement' && alive.every((q) => q.done)) return this.endPlacement();
    if (wasTurn) { if (this.turnQueue.length === 0) return this.beginRelocate(); this.armPlantTimer(); }
    if (this.phase === 'relocate') return this.maybeResolve();
    this.state();
  }
}

function validPos(x, y) {
  x = Number(x); y = Number(y);
  const P = CFG.plane;
  if (!Number.isFinite(x) || !Number.isFinite(y) || Math.abs(x) > P || Math.abs(y) > P) return null;
  return { x: Math.round(x * 100) / 100, y: Math.round(y * 100) / 100 };
}

// ----------------------------------------------------------------- connection handling
function handleConn(conn) {
  const me = { id: nextPlayerId++, conn, name: 'Player', hp: CFG.hp, alive: true, pos: null, done: false, lobby: null };
  const err = (msg) => conn.send({ type: 'error', msg });

  conn.onclose = () => { if (me.lobby) me.lobby.removePlayer(me); me.lobby = null; };

  conn.onmessage = (raw) => {
    let m;
    try { m = JSON.parse(raw); } catch { return; }
    if (!m || typeof m.type !== 'string') return;
    const L = me.lobby;

    if (m.type === 'create' || m.type === 'join') {
      if (L) return err('Already in a lobby.');
      const name = clean(m.lobby, 24), pw = clean(m.password, 32), nick = clean(m.name, 16) || 'Player ' + me.id;
      if (!name) return err('Enter a lobby name.');
      if (!pw) return err('Enter a password.');
      me.name = nick;
      if (m.type === 'create') {
        if (lobbies.has(lobbyKey(name))) return err('That lobby name is taken. Pick another.');
        const max = Math.max(CFG.minPlayers, Math.min(CFG.maxPlayersLimit, Math.floor(Number(m.max)) || 2));
        const lob = new Lobby(name, pw, max);
        lobbies.set(lobbyKey(name), lob);
        lob.players.push(me); lob.creator = me.id; me.lobby = lob;
      } else {
        const lob = lobbies.get(lobbyKey(name));
        if (!lob || lob.password !== pw) return err('Wrong lobby name or password.');
        if (lob.inGame) return err('That game has already started.');
        if (lob.players.length >= lob.maxPlayers) return err('That lobby is full.');
        // unique nicknames inside a lobby
        let n = nick, k = 2;
        while (lob.players.some((p) => p.name === n)) n = `${nick} ${k++}`;
        me.name = n;
        lob.players.push(me); me.lobby = lob;
      }
      me.hp = CFG.hp; me.alive = true; me.pos = null; me.done = false;
      conn.send({ type: 'joined', you: me.id, name: me.name, lobby: me.lobby.name, config: CFG });
      me.lobby.lobbyUpdate();
      return;
    }
    if (!L) return err('Join a lobby first.');
    switch (m.type) {
      case 'start':
        if (L.creator !== me.id) return err('Only the room creator can start.');
        if (L.inGame) return;
        if (L.players.length < CFG.minPlayers) return err('Need at least 2 players.');
        return L.start();
      case 'place': return L.place(me, m.x, m.y);
      case 'plant': return L.plant(me, m.formula);
      case 'pass': return L.pass(me);
      case 'relocate': return L.relocate(me, m.x, m.y);
      case 'leave': L.removePlayer(me); me.lobby = null; return conn.send({ type: 'left_lobby' });
    }
  };
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'content-type': 'text/plain' });
  res.end(`Graph Duel server OK. Open lobbies: ${lobbies.size}\n`);
});
server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key || String(req.headers.upgrade).toLowerCase() !== 'websocket') { socket.destroy(); return; }
  const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
  handleConn(new Conn(socket));
});

if (require.main === module) {
  server.listen(PORT, () => console.log(`Graph Duel server listening on :${PORT}`));
}
module.exports = { server, CFG, curveDistance, damageFor };
