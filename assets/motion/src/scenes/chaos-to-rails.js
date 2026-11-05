/* chaos-to-rails (6 s, hero) — "The agent keeps going; the rails keep it honest."
 * Tangled grey lines snap onto three rails; a dot runs the switch route past
 * hooks → tests → review (bottom rail up to the top rail, along the logo's diagonal). */
(() => {
  const RAILS = [200, 290, 380]; // top, middle, bottom
  const X0 = 40, X1 = 960;
  const ROUTE = [[40, 380], [340, 380], [385, 290], [560, 290], [605, 200], [960, 200]];
  const STATIONS = [
    { name: 'hooks', x: 220, y: 380 },
    { name: 'tests', x: 470, y: 290 },
    { name: 'review', x: 780, y: 200 },
  ];
  const T_RUN = [3.0, 5.4];
  // Chaos moves in 12 fps stop-motion steps (nervous), order moves at full frame rate (calm).
  // The half-step offset keeps step boundaries between 60 fps frames, so motion blur never
  // straddles two chaos states; it also makes identical GIF frames that compress to nothing.
  const STEP = 12;
  const stepT = (t) => (Math.floor(t * STEP + 0.5) - 0.5) / STEP;

  // Route arc length helpers.
  const segs = [];
  let L = 0;
  for (let i = 1; i < ROUTE.length; i++) {
    const [ax, ay] = ROUTE[i - 1], [bx, by] = ROUTE[i];
    const len = Math.hypot(bx - ax, by - ay);
    segs.push({ ax, ay, bx, by, s0: L, len });
    L += len;
  }
  const pointAt = (s) => {
    for (const g of segs) if (s <= g.s0 + g.len) { const u = clamp((s - g.s0) / g.len); return [lerp(g.ax, g.bx, u), lerp(g.ay, g.by, u)]; }
    return ROUTE[ROUTE.length - 1];
  };
  const sAtX = (x, y) => { for (const g of segs) if (g.ay === y && g.by === y && x >= g.ax && x <= g.bx) return g.s0 + (x - g.ax); return 0; };
  STATIONS.forEach((st) => (st.s = sAtX(st.x, st.y)));
  const sAt = (t) => L * travel(prog(t, T_RUN[0], T_RUN[1]));
  // Local time the dot reaches a station (for the showreel's sound cues).
  const timeAtS = (s) => { let lo = T_RUN[0], hi = T_RUN[1]; for (let i = 0; i < 30; i++) { const m = (lo + hi) / 2; if (sAt(m) < s) lo = m; else hi = m; } return lo; };

  const LABELS = [
    { str: 'agent writes code', x: 640, y: 128, to: 2 },
    { str: 'no tests', x: 230, y: 236, to: 1 },
    { str: 'secret in .env', x: 690, y: 452, to: 0 },
    { str: '--no-verify', x: 300, y: 486, to: 0, fade: true },
  ];

  SCENES['chaos-to-rails'] = {
    w: 1000, h: 560, dur: 6, loop: true, xf: 0.18, poster: 5.75,
    alt: 'Tangled grey lines snap onto three green rails; a dot passes the hooks, tests and review stations and the slickrails logo locks up.',
    events: [
      { t: 1.6, type: 'snap' },
      ...STATIONS.map((st, i) => ({ t: timeAtS(st.s), type: 'chime', n: i })),
      { t: 5.4, type: 'lock' },
    ],
    build(root) {
      el('rect', { width: 1000, height: 560, fill: C.bg }, root);
      const g = el('g', { transform: 'translate(0,24)' }, root); // optical centre: lockup + rails + labels
      const glow = glowFilter(g, 3);

      // Switch diagonals (dim), drawn once the rails exist.
      const diag = [[340, 380, 385, 290], [560, 290, 605, 200]].map(([a, b, c, d]) =>
        el('line', { x1: a, y1: b, x2: c, y2: d, stroke: C.accent, 'stroke-width': 3, 'stroke-linecap': 'round', opacity: 0 }, g));

      // Nine chaos lines; three end up on each rail.
      const R = rng(20261021);
      const N = 48;
      const order = [4, 0, 7, 2, 5, 8, 1, 6, 3]; // snap order
      const lines = [];
      for (let i = 0; i < 9; i++) {
        const ln = {
          k: i % 3, seed: 100 + i,
          base: 90 + R() * 380, xa: 40 + R() * 260, xb: 640 + R() * 320,
          amp: 50 + R() * 80, freq: 120 + R() * 140, sp: 0.5 + R() * 0.9, tilt: (R() - 0.5) * 0.5,
          tSnap: 1.6 + order.indexOf(i) * 0.12,
        };
        ln.grey = el('polyline', { fill: 'none', stroke: C.muted2, 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }, g);
        ln.green = el('polyline', { fill: 'none', stroke: C.accent, 'stroke-width': 3, 'stroke-linecap': 'round' }, g);
        lines.push(ln);
      }

      // Bright trail + dot.
      const trail = el('polyline', { points: ROUTE.map((p) => p.join(',')).join(' '), fill: 'none', stroke: C.accent, 'stroke-width': 4, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', 'stroke-dasharray': `${L} ${L}` }, g);

      // Stations.
      const st = STATIONS.map((s) => {
        const sg = el('g', {}, g);
        const box = el('rect', { x: s.x - 9, y: s.y - 9, width: 18, height: 18, rx: 2, fill: C.bg, stroke: C.muted2, 'stroke-width': 2 }, sg);
        const lit = el('rect', { x: s.x - 9, y: s.y - 9, width: 18, height: 18, rx: 2, fill: C.accent, filter: glow }, sg);
        return { ...s, sg, box, lit };
      });

      // Labels: chaos text → station text.
      const labels = LABELS.map((lb, j) => {
        const lg = el('g', {}, g);
        const a = txt(lg, 0, 0, lb.str, { fill: C.muted, anchor: 'middle' });
        const b = txt(lg, 0, 0, STATIONS[lb.to].name, { fill: C.muted, anchor: 'middle' });
        return { ...lb, lg, a, b, t0: 1.7 + j * 0.16 };
      });

      const dotHalo = el('circle', { r: 15, fill: C.accent, opacity: 0.2 }, g);
      const dot = el('circle', { r: 7, fill: C.accent, filter: glow }, g);

      // Lockup.
      const lock = el('g', {}, g);
      logo(lock, 318, 52, 64);
      wordmark(lock, 394, 108, 60);

      return {
        seek(t) {
          // Lines.
          for (const ln of lines) {
            const u = arrive(prog(t, ln.tSnap, ln.tSnap + 0.44));
            const tc = stepT(t), jt = Math.round(tc * STEP);
            const pts = [];
            for (let n = 0; n < N; n++) {
              const f = n / (N - 1);
              const xc = lerp(ln.xa, ln.xb, f);
              const yc = ln.base + ln.tilt * (xc - 500) + ln.amp * noise(ln.seed, xc / ln.freq + tc * ln.sp) + 4 * noise(ln.seed + 50, jt + n * 0.7);
              const xo = lerp(X0, X1, f), yo = RAILS[ln.k];
              pts.push(`${lerp(xc, xo, u).toFixed(1)},${lerp(yc, yo, u).toFixed(1)}`);
            }
            const p = pts.join(' ');
            set(ln.grey, { points: p, opacity: 0.55 * (1 - u) });
            set(ln.green, { points: p, opacity: 0.26 * clamp(u * 1.4) });
          }
          diag.forEach((d, i) => set(d, { opacity: 0.6 * prog(t, 2.6 + i * 0.12, 2.95 + i * 0.12) }));

          // Labels.
          for (const lb of labels) {
            const s = STATIONS[lb.to];
            const u = arrive(prog(t, lb.t0, lb.t0 + 0.5));
            const tc = stepT(t), jt = Math.round(tc * STEP);
            const jx = (1 - u) * 6 * noise(lb.t0 * 100, jt), jy = (1 - u) * 5 * noise(lb.t0 * 100 + 9, jt);
            const x = lerp(lb.x, s.x, u) + jx, y = lerp(lb.y, s.y + 44, u) + jy;
            set(lb.lg, { transform: `translate(${x.toFixed(1)},${y.toFixed(1)})` });
            // flicker ≤ 2.5 Hz, partial (never full off): reads as unstable, not as a strobe
            const fl = t < lb.t0 ? ((tc * 2.2 + lb.t0) % 1 < 0.72 ? 1 : 0.4) : 1;
            set(lb.a, { opacity: fl * (1 - prog(t, lb.t0 + 0.12, lb.t0 + 0.3)) });
            const litU = clamp((sAt(t) - s.s) / 30);
            set(lb.b, { opacity: lb.fade ? 0 : prog(t, lb.t0 + 0.22, lb.t0 + 0.42), fill: litU > 0.5 ? C.accent : C.muted });
          }

          // Stations: appear with the snap, light when the dot passes.
          const s = sAt(t);
          for (const x of st) {
            const ap = arrive(prog(t, 2.5, 2.9));
            const litU = clamp((s - x.s) / 24);
            const pulse = litU > 0 ? 1 + 0.5 * (1 - arrive(clamp((s - x.s) / 120))) : 1;
            set(x.sg, { opacity: ap, transform: `translate(${x.x},${x.y}) scale(${pulse}) translate(${-x.x},${-x.y})` });
            set(x.lit, { opacity: litU });
          }

          // Dot + trail.
          const running = t >= T_RUN[0] - 0.15;
          show(dot, running); show(dotHalo, running); show(trail, t >= T_RUN[0]);
          const [dx, dy] = pointAt(s);
          const dIn = arrive(prog(t, T_RUN[0] - 0.15, T_RUN[0] + 0.1));
          set(dot, { cx: dx, cy: dy, r: 7 * dIn });
          set(dotHalo, { cx: dx, cy: dy, r: 15 * dIn });
          set(trail, { 'stroke-dashoffset': L - s });

          // Lockup arrives at 5.4.
          const lu = arrive(prog(t, 5.4, 5.62));
          show(lock, lu > 0);
          set(lock, { opacity: lu, transform: `translate(0,${(1 - lu) * 14})` });
        },
      };
    },
  };
})();
