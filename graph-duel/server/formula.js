'use strict';
// Safe formula parser/evaluator for y = f(x). No eval(). Mirrors client/scripts/formula.gd.
// Supports: + - * / ^, parentheses, implicit multiplication (2x, 3sin(x), (x+1)(x-1)),
// constants pi and e, functions sin cos tan asin acos atan sinh cosh tanh exp ln log sqrt abs floor.

const FUNCS = {
  sin: Math.sin, cos: Math.cos, tan: Math.tan,
  asin: (v) => (v >= -1 && v <= 1 ? Math.asin(v) : NaN),
  acos: (v) => (v >= -1 && v <= 1 ? Math.acos(v) : NaN),
  atan: Math.atan, sinh: Math.sinh, cosh: (v) => Math.cosh(Math.max(-50, Math.min(50, v))), tanh: Math.tanh,
  exp: (v) => Math.exp(Math.max(-50, Math.min(50, v))),
  ln: (v) => (v > 0 ? Math.log(v) : NaN),
  log: (v) => (v > 0 ? Math.log10(v) : NaN),
  sqrt: (v) => (v >= 0 ? Math.sqrt(v) : NaN),
  abs: Math.abs, floor: Math.floor,
};

function tokenize(src) {
  const out = [];
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === ' ') { i++; continue; }
    if ((c >= '0' && c <= '9') || c === '.') {
      let j = i;
      while (j < src.length && ((src[j] >= '0' && src[j] <= '9') || src[j] === '.')) j++;
      const text = src.slice(i, j);
      const v = Number(text);
      if (!Number.isFinite(v) || (text.match(/\./g) || []).length > 1) throw new Error('Bad number: ' + text);
      out.push({ t: 'num', v });
      i = j;
    } else if (c >= 'a' && c <= 'z') {
      let j = i;
      while (j < src.length && src[j] >= 'a' && src[j] <= 'z') j++;
      const w = src.slice(i, j);
      i = j;
      if (w === 'x') out.push({ t: 'x' });
      else if (w === 'pi') out.push({ t: 'num', v: Math.PI, c: true });
      else if (w === 'e') out.push({ t: 'num', v: Math.E, c: true });
      else if (FUNCS[w]) out.push({ t: 'fn', v: w });
      else throw new Error('Unknown word: ' + w);
    } else if ('+-*/^(),'.includes(c)) {
      out.push({ t: 'op', v: c });
      i++;
    } else {
      throw new Error('Unexpected character: ' + c);
    }
  }
  // implicit multiplication
  const res = [];
  for (let k = 0; k < out.length; k++) {
    const a = out[k - 1];
    const b = out[k];
    if (a) {
      const closing = a.t === 'num' || a.t === 'x' || (a.t === 'op' && a.v === ')');
      const opening = b.t === 'num' || b.t === 'x' || b.t === 'fn' || (b.t === 'op' && b.v === '(');
      if (closing && opening && !(a.t === 'num' && b.t === 'num' && !a.c && !b.c)) res.push({ t: 'op', v: '*' });
    }
    res.push(b);
  }
  return res;
}

function parse(srcIn) {
  let src = String(srcIn).trim().toLowerCase().replace(/×/g, '*').replace(/÷/g, '/').replace(/−/g, '-').replace(/π/g, 'pi');
  src = src.replace(/^(y|f\(x\))\s*=/, '').replace(/\*\*/g, '^').replace(/\s+/g, ' ').trim();
  if (!src) throw new Error('Type a formula first.');
  if (src.length > 120) throw new Error('Formula too long.');
  const toks = tokenize(src);
  let pos = 0;
  let ops = 0;
  const peek = () => toks[pos] || { t: 'end' };
  const isOp = (v) => peek().t === 'op' && peek().v === v;

  function expr() {
    let a = term();
    while (isOp('+') || isOp('-')) {
      const op = peek().v; pos++;
      const b = term(); ops++;
      a = { k: 'bin', op, a, b };
    }
    return a;
  }
  function term() {
    let a = unary();
    while (isOp('*') || isOp('/')) {
      const op = peek().v; pos++;
      const b = unary(); ops++;
      a = { k: 'bin', op, a, b };
    }
    return a;
  }
  function unary() {
    if (isOp('-')) { pos++; return { k: 'neg', a: unary() }; }
    if (isOp('+')) { pos++; return unary(); }
    return power();
  }
  function power() {
    const base = atom();
    if (isOp('^')) { pos++; const ex = unary(); ops++; return { k: 'bin', op: '^', a: base, b: ex }; }
    return base;
  }
  function atom() {
    const p = peek();
    if (p.t === 'num') { pos++; return { k: 'num', v: p.v }; }
    if (p.t === 'x') { pos++; return { k: 'x' }; }
    if (p.t === 'fn') {
      pos++;
      if (!isOp('(')) throw new Error('Use parentheses: ' + p.v + '(...)');
      pos++;
      const arg = expr();
      if (!isOp(')')) throw new Error('Missing )');
      pos++; ops++;
      return { k: 'fn', n: p.v, a: arg };
    }
    if (isOp('(')) {
      pos++;
      const inner = expr();
      if (!isOp(')')) throw new Error('Missing )');
      pos++;
      return inner;
    }
    throw new Error('Unexpected end or symbol in formula.');
  }

  const ast = expr();
  if (pos < toks.length) throw new Error('Unexpected input near the end of the formula.');
  return { ast, ops, src };
}

function evaluate(n, x) {
  switch (n.k) {
    case 'num': return n.v;
    case 'x': return x;
    case 'neg': return -evaluate(n.a, x);
    case 'bin': {
      const a = evaluate(n.a, x), b = evaluate(n.b, x);
      switch (n.op) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/': return b !== 0 ? a / b : Infinity;
        case '^': return Math.pow(a, b);
      }
      return NaN;
    }
    case 'fn': return FUNCS[n.n](evaluate(n.a, x));
  }
  return NaN;
}

module.exports = { parse, evaluate };
