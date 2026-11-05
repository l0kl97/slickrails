/* slickrails motion kit — shared helpers.
 * Rule of the kit: every pixel is a pure function of t. No wall-clock time, no rAF state,
 * no unseeded randomness (tests/scenes.test.mjs enforces this). Scenes build their DOM once, then seek(t) only sets attributes. */

const C = {
  bg: '#0B0F0E', panel: '#121816', panel2: '#14201B', line: '#1E2724', line2: '#26302B',
  text: '#E8EDEA', muted: '#8FA39A', muted2: '#7E9086',
  accent: '#A8FF06', warn: '#E5A83B', fail: '#E5484D',
};
const MONO = 'ui-monospace, SFMono-Regular, Menlo, monospace';
const SANS = 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';
const NS = 'http://www.w3.org/2000/svg';
const SCENES = {};

const clamp = (x, a = 0, b = 1) => (x < a ? a : x > b ? b : x);
const lerp = (a, b, u) => a + (b - a) * u;
const prog = (t, a, b) => clamp((t - a) / (b - a));

// CSS cubic-bezier, solved by bisection (robust for every control point set).
function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const sx = (s) => ((ax * s + bx) * s + cx) * s;
  const sy = (s) => ((ay * s + by) * s + cy) * s;
  return (u) => {
    if (u <= 0) return 0;
    if (u >= 1) return 1;
    let lo = 0, hi = 1, s = u;
    for (let i = 0; i < 24; i++) {
      s = (lo + hi) / 2;
      if (sx(s) < u) lo = s; else hi = s;
    }
    return sy(s);
  };
}
const arrive = bezier(0.2, 0.8, 0.2, 1);   // brand easing for everything that lands
const depart = bezier(0.55, 0, 0.9, 0.35); // things that leave
const travel = bezier(0.4, 0, 0.6, 1);     // dots on rails
const linear = (u) => clamp(u);            // rail draws
const tw = (t, a, b, from, to, ease = arrive) => lerp(from, to, ease(prog(t, a, b)));

// Seeded PRNG (mulberry32) + hash-based value noise.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}
function hash(i, s) {
  let h = Math.imul(i ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul((s + 0x632be5ab) | 0, 0xc2b2ae35);
  h ^= h >>> 13; h = Math.imul(h, 0x27d4eb2f); h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
function noise(s, x) {
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(hash(i, s), hash(i + 1, s), u) * 2 - 1;
}
// Small decaying shake after an impact at t0 (stepped at 30 Hz so it reads as a hit, not a blur).
function shake(t, t0, amp = 3, dur = 0.2, seed = 1) {
  const u = prog(t, t0, t0 + dur);
  if (u <= 0 || u >= 1) return [0, 0];
  const k = Math.floor(t * 30), a = amp * (1 - u) * (1 - u);
  return [a * (hash(k, seed) * 2 - 1), a * (hash(k, seed + 7) * 2 - 1)];
}

let _uid = 0;
const uid = (p) => `${p}${++_uid}`;
function el(tag, attrs = {}, parent) {
  const e = document.createElementNS(NS, tag);
  set(e, attrs);
  if (parent) parent.appendChild(e);
  return e;
}
function set(e, attrs) {
  for (const k in attrs) {
    const v = attrs[k];
    if (k === 'text') { if (e.textContent !== v) e.textContent = v; }
    else e.setAttribute(k, v);
  }
  return e;
}
const show = (e, on) => e.setAttribute('display', on ? 'inline' : 'none');
const typed = (str, t, t0, cps = 30) => str.slice(0, Math.floor(clamp((t - t0) * cps, 0, str.length)));

function txt(parent, x, y, str, o = {}) {
  return el('text', {
    x, y, text: str, fill: o.fill || C.text, 'font-family': o.family || MONO,
    'font-size': o.size || 22, 'font-weight': o.weight || 400,
    'text-anchor': o.anchor || 'start', style: 'white-space:pre',
    ...(o.ls ? { 'letter-spacing': o.ls } : {}),
  }, parent);
}
const width = (te) => (te.textContent ? te.getComputedTextLength() : 0);

// Glow: max 6 px blur by brand rule (stdDeviation 3).
function glowFilter(parent, std = 3) {
  const id = uid('glow');
  const f = el('filter', { id, x: '-50%', y: '-50%', width: '200%', height: '200%' }, el('defs', {}, parent));
  el('feGaussianBlur', { stdDeviation: std, result: 'b' }, f);
  const m = el('feMerge', {}, f);
  el('feMergeNode', { in: 'b' }, m);
  el('feMergeNode', { in: 'SourceGraphic' }, m);
  return `url(#${id})`;
}
function clipRect(parent, x, y, w, h, rx = 0) {
  const id = uid('clip');
  const cp = el('clipPath', { id }, el('defs', {}, parent));
  const r = el('rect', { x, y, width: w, height: h, rx }, cp);
  return { url: `url(#${id})`, rect: r };
}

function panel(parent, x, y, w, h) {
  return el('rect', { x: x + 0.5, y: y + 0.5, width: w - 1, height: h - 1, rx: 10, fill: C.panel, stroke: C.line2, 'stroke-width': 1 }, parent);
}

// Block caret (steady, never blinks: no flashing).
function caret(parent) {
  const r = el('rect', { width: 12, height: 26, fill: C.text, opacity: 0.85 }, parent);
  return { at(te, on) { show(r, on); if (on) set(r, { x: +te.getAttribute('x') + width(te) + 2, y: +te.getAttribute('y') - 20 }); } };
}

// Arc spinner, rotation is a pure function of t.
function spinner(parent) {
  const g = el('g', {}, parent);
  el('circle', { r: 9, fill: 'none', stroke: C.line2, 'stroke-width': 3 }, g);
  const a = el('circle', { r: 9, fill: 'none', stroke: C.muted, 'stroke-width': 3, 'stroke-dasharray': '16 41', 'stroke-linecap': 'round' }, g);
  return { seek(t, x, y, on) { show(g, on); if (on) { set(g, { transform: `translate(${x},${y})` }); set(a, { transform: `rotate(${(t * 420) % 360})` }); } } };
}

// Status bar that slides in from the left inside its own row clip.
function statusBar(parent, { x, y, w, h = 42, fill, str, ink = C.bg, size = 22, weight = 600 }) {
  const cl = clipRect(parent, x, y, w, h, 6);
  const g = el('g', { 'clip-path': cl.url }, parent);
  const inner = el('g', {}, g);
  el('rect', { x, y, width: w, height: h, rx: 6, fill }, inner);
  const te = txt(inner, x + 16, y + h / 2 + 8, str, { fill: ink, size, weight });
  return {
    g, te,
    // u: slide progress 0..1, dim: final opacity multiplier
    seek(u, dim = 1) {
      show(g, u > 0);
      set(inner, { transform: `translate(${(u - 1) * w},0)` });
      set(g, { opacity: dim });
    },
  };
}

// Rail: dim base, green line, red overlay that spreads out from a gate position.
function rail(parent, { x0, x1, y, w = 3 }) {
  const g = el('g', {}, parent);
  const L = { y1: y, y2: y, 'stroke-width': w, 'stroke-linecap': 'round' };
  el('line', { ...L, x1: x0, x2: x1, stroke: C.line2 }, g);
  const green = el('line', { ...L, x1: x0, x2: x1, stroke: C.accent }, g);
  const redL = el('line', { ...L, stroke: C.fail }, g);
  const redR = el('line', { ...L, stroke: C.fail }, g);
  return {
    g,
    seek({ draw = 1, red = 0, gx = (x0 + x1) / 2, glow = 0.55 }) {
      set(green, { x2: lerp(x0, x1, draw), opacity: glow * (1 - 0.85 * clamp(red * 3)) });
      show(redL, red > 0); show(redR, red > 0);
      if (red > 0) {
        set(redL, { x1: gx, x2: lerp(gx, x0, red) });
        set(redR, { x1: gx, x2: lerp(gx, x1, red) });
      }
    },
  };
}

// Gate: a barrier that drops across the rail (closed, red) or retracts into its beam (open, green).
function gate(parent, { x, y, s = 1 }) {
  const g = el('g', { transform: `translate(${x},${y}) scale(${s})` }, parent);
  const glow = glowFilter(g, 2.5);
  const post = { width: 4, fill: C.muted2, rx: 1 };
  el('rect', { ...post, x: -22, y: -62, height: 88 }, g);
  el('rect', { ...post, x: 18, y: -62, height: 88 }, g);
  el('rect', { x: -22, y: -66, width: 44, height: 6, rx: 2, fill: C.muted2 }, g);
  const cl = clipRect(g, -16, -60, 32, 120);
  const bar = el('g', { 'clip-path': cl.url }, g);
  const barG = el('rect', { x: -8, width: 16, height: 56, rx: 3, fill: C.accent }, bar);
  const barR = el('rect', { x: -8, width: 16, height: 56, rx: 3, fill: C.fail }, bar);
  const lampG = el('circle', { cy: -80, r: 6, fill: C.accent, filter: glow }, g);
  const lampR = el('circle', { cy: -80, r: 6, fill: C.fail, filter: glow }, g);
  return {
    g,
    // close: 0 open .. 1 closed; red: 0 green .. 1 red
    seek({ close = 0, red = 0 }) {
      // colour is a hard switch, never a blend: red over green would mix a hue the brand doesn't have
      const isRed = red >= 0.5, by = lerp(-108, -28, close);
      set(barG, { y: by }); set(barR, { y: by });
      show(barR, isRed); show(barG, !isRed);
      show(lampR, isRed); show(lampG, !isRed);
    },
  };
}

// Logo: the shapes of assets/logo.svg verbatim (injected at build time), placed and scaled.
function logo(parent, x, y, size) {
  const g = el('g', { transform: `translate(${x},${y}) scale(${size / 48})` }, parent);
  g.innerHTML = LOGO_SHAPES;
  return g;
}
// Wordmark exactly as assets/header.html sets it: slickr + "ai" in accent + ls.
function wordmark(parent, x, y, size, anchor = 'start') {
  const te = el('text', {
    x, y, 'font-family': SANS, 'font-size': size, 'font-weight': 700,
    'letter-spacing': `${-0.035 * size}`, fill: C.text, 'text-anchor': anchor,
  }, parent);
  te.innerHTML = `slickr<tspan fill="${C.accent}">ai</tspan>ls`;
  return te;
}

// Piecewise-linear time remap [[outT, inT], ...] — used by the showreel to retime scenes.
function remap(map, t) {
  if (t <= map[0][0]) return map[0][1];
  for (let i = 1; i < map.length; i++) {
    const [a, la] = map[i - 1], [b, lb] = map[i];
    if (t <= b) return lerp(la, lb, (t - a) / (b - a));
  }
  return map[map.length - 1][1];
}
function unmap(map, l) {
  for (let i = 1; i < map.length; i++) {
    const [a, la] = map[i - 1], [b, lb] = map[i];
    if (l >= la && l <= lb && lb > la) return lerp(a, b, (l - la) / (lb - la));
  }
  return null;
}
