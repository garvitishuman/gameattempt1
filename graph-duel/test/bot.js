// Scripted opponent for the e2e test. node bot.js <port>
const port = process.argv[2] || 8080;
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
let me = null, phase = '', done = false;
const send = (o) => ws.send(JSON.stringify(o));
ws.onopen = () => {
  const tryJoin = () => send({ type: 'join', lobby: 'e2e', password: 'pw', name: 'Bot' });
  setTimeout(tryJoin, 1500);
};
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.type === 'error') { console.log('bot error', m.msg); if (/Wrong/.test(m.msg)) setTimeout(() => send({ type: 'join', lobby: 'e2e', password: 'pw', name: 'Bot' }), 1000); }
  if (m.type === 'joined') me = m.you;
  if (m.type === 'state') {
    if (m.phase === 'placement') send({ type: 'place', x: 1, y: 2.68 });
    if (m.phase === 'plant' && m.turn === me) send({ type: 'plant', formula: 'x' });
    if (m.phase === 'relocate' && phase !== 'relocate') send({ type: 'relocate', x: 1, y: 2.68 });
    phase = m.phase;
  }
  if (m.type === 'round_result') console.log('bot sees round', m.round, 'hits', m.hits.length, JSON.stringify(m.hp));
  if (m.type === 'game_over') { console.log('bot sees game over winners', m.winners, m.reason); setTimeout(() => process.exit(0), 200); }
};
