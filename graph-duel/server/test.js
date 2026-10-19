// Integration test: node test.js  (starts server on a random port, plays scripted games)
const assert = require('assert');
const { server, CFG, curveDistance } = require('./server');
const { parse } = require('./formula');

// formula unit checks
for (const [f, x, want] of [['2x+1', 3, 7], ['3sin(x)', 0, 0], ['x^2', -3, 9], ['-x^2', 2, -4], ['2^-x', 1, 0.5], ['(x+1)(x-1)', 3, 8], ['y=ln(e)', 1, 1], ['log(100)+abs(-2)', 0, 4], ['2pi', 0, 2 * Math.PI]]) {
  const { ast } = parse(f); const { evaluate } = require('./formula');
  assert(Math.abs(evaluate(ast, x) - want) < 1e-9, f);
}
for (const bad of ['', '2+', 'foo(x)', 'sin x', '1 2', '(x', 'x$']) assert.throws(() => parse(bad), bad);
assert(parse('sin(x)+cos(x)').ops === 3);
// geometry: y=3 passes through (2,3) at d=0 and graze test
{ const { ast } = parse('3'); assert(curveDistance(ast, 2, 3).d < 0.02); assert(Math.abs(curveDistance(ast, 2, 3.5).d - 0.5) < 0.02); assert(curveDistance(ast, 2, 6).d > 2.9); }
console.log('unit ok');

function client(port, label) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}`);
  const c = { ws, label, msgs: [], waiters: [], id: null };
  ws.onmessage = (e) => { const m = JSON.parse(e.data); c.msgs.push(m); if (m.type === 'joined') c.id = m.you; c.waiters = c.waiters.filter((w) => !w(m)); };
  c.open = new Promise((r) => (ws.onopen = r));
  c.send = (o) => ws.send(JSON.stringify(o));
  c.wait = (pred, ms = 3000) => new Promise((res, rej) => {
    const hit = c.msgs.find(pred); if (hit) { c.msgs.splice(c.msgs.indexOf(hit), 1); return res(hit); }
    const t = setTimeout(() => rej(new Error(label + ' timeout')), ms);
    c.waiters.push((m) => { if (pred(m)) { clearTimeout(t); c.msgs.splice(c.msgs.indexOf(m), 1); res(m); return true; } return false; });
  });
  return c;
}

(async () => {
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;
  const [a, b, d] = [client(port, 'A'), client(port, 'B'), client(port, 'D')];
  await Promise.all([a.open, b.open, d.open]);

  // lobby rules
  a.send({ type: 'create', lobby: 'Arena', password: 'pw', name: 'Alice', max: 2 });
  await a.wait((m) => m.type === 'joined');
  b.send({ type: 'join', lobby: 'arena', password: 'bad', name: 'Bob' });
  assert.match((await b.wait((m) => m.type === 'error')).msg, /Wrong/);
  b.send({ type: 'join', lobby: 'arena', password: 'pw', name: 'Bob' });
  await b.wait((m) => m.type === 'joined');
  d.send({ type: 'join', lobby: 'Arena', password: 'pw', name: 'Dan' });
  assert.match((await d.wait((m) => m.type === 'error')).msg, /full/);
  b.send({ type: 'start' });
  assert.match((await b.wait((m) => m.type === 'error')).msg, /creator/);
  a.send({ type: 'start' });
  await a.wait((m) => m.type === 'start'); await b.wait((m) => m.type === 'start');

  // placement
  a.send({ type: 'place', x: 2, y: 3 });
  b.send({ type: 'place', x: -5, y: -5 });
  await a.wait((m) => m.type === 'state' && m.phase === 'plant');
  const st = (await b.wait((m) => m.type === 'state' && m.phase === 'plant'));
  assert.strictEqual(st.round, 1);

  // plant turn order: wrong player rejected, right player ok
  const first = st.turn === a.id ? a : b, second = first === a ? b : a;
  second.send({ type: 'plant', formula: '1' });
  assert.match((await second.wait((m) => m.type === 'error')).msg, /not your turn/);
  first.send({ type: 'plant', formula: 'x*0+bad' });
  assert.match((await first.wait((m) => m.type === 'error')).msg, /Unknown/);
  const f1 = first === a ? '3' : '-5', f2 = first === a ? '-5' : '3';
  first.send({ type: 'plant', formula: f1 });
  await first.wait((m) => m.type === 'plant_ok');
  second.send({ type: 'plant', formula: f2 });
  await second.wait((m) => m.type === 'plant_ok');
  await a.wait((m) => m.type === 'state' && m.phase === 'relocate');

  // Alice stays/moves to (2,3.1) [on Bob's y=3 curve? Bob owns '-5' or '3' depending]; we just ensure deterministic: Alice owns '3'
  // first===a => Alice owns '3', Bob owns '-5'. else Alice owns '-5', Bob owns '3'.
  // Alice at (2,3) is on y=3 curve. If Bob owns y=3 (first===b) Alice is hit for 40. Bob moves to (-5,3): on y=3 curve; hit only if Alice owns it.
  a.send({ type: 'relocate', x: 2, y: 3 });
  b.send({ type: 'relocate', x: -5, y: 3 });
  const res = await a.wait((m) => m.type === 'round_result');
  const victimHp = res.hp[b.id];
  assert.strictEqual(victimHp, 60, 'victim should have lost 40');
  assert.strictEqual(res.hits.length, 1);
  const rb = await b.wait((m) => m.type === 'round_result');
  assert(rb.hits[0].formula, 'involved player sees formula');
  console.log('round 1 ok', JSON.stringify(res.hits));

  // keep playing: each round Alice plants y=3 (her turn), Bob plants -5; Bob stays on y=3 until dead
  let over = null, rounds = 1;
  while (!over && rounds < 6) {
    const stt = await a.wait((m) => m.type === 'state' && m.phase === 'plant' && m.round === rounds + 1, 9000);
    const order = stt.turn === a.id ? [a, b] : [b, a];
    for (const c of order) { c.send({ type: 'plant', formula: c === a ? '3' : '-5' }); await c.wait((m) => m.type === 'plant_ok'); }
    await a.wait((m) => m.type === 'state' && m.phase === 'relocate' && m.round === rounds + 1);
    a.send({ type: 'relocate', x: 2, y: 3 }); b.send({ type: 'relocate', x: -5, y: 3 });
    const r = await a.wait((m) => m.type === 'round_result'); rounds++;
    console.log('round', r.round, 'hp', JSON.stringify(r.hp), 'elim', r.eliminated);
    const go = await Promise.race([a.wait((m) => m.type === 'game_over', 300).catch(() => null)]);
    if (go) over = go;
  }
  assert(over, 'game should end'); assert.deepStrictEqual(over.winners, [a.id]);
  // lobby resets and creator can start a rematch
  a.send({ type: 'start' }); await a.wait((m) => m.type === 'start');
  // disconnect mid-game ends it for the remaining player
  b.ws.close();
  const go2 = await a.wait((m) => m.type === 'game_over'); assert.strictEqual(go2.reason, 'opponents_left');
  console.log('full game ok');
  for (const c of [a, b, d]) c.ws.close();
  server.close();
  setTimeout(() => process.exit(0), 100);
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
