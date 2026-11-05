/* agent-cant-finish-red (7 s, the differentiator) — two panes, identical timing.
 * The agent claims it is done, the Stop hook slams in, the claim is taken back,
 * the fix lands, tests go green, the session may end. One gate serves both. */
(() => {
  const RAIL_Y = 470, GATE_X = 500, FAILS = [1, 4];
  const PANES = [{ name: 'Claude Code', x: 20 }, { name: 'Codex CLI', x: 510 }];
  const W = 470, Y = 24, H = 352;

  function pane(parent, { name, x }) {
    const g = el('g', {}, parent);
    const body = el('g', {}, g);
    panel(body, x, Y, W, H);
    txt(body, x + 20, Y + 40, name, { family: SANS, weight: 600 });
    el('line', { x1: x + 1, x2: x + W - 1, y1: Y + 60.5, y2: Y + 60.5, stroke: C.line2 }, body);
    const bars = [320, 230, 280].map((bw, i) => ({ bw, r: el('rect', { x: x + 20, y: Y + 80 + i * 22, height: 10, rx: 5, fill: C.muted2, opacity: 0.5 }, body), t0: 0.35 + i * 0.2 }));
    const DONE = 'Done! All tasks complete.';
    const done = txt(body, x + 20, Y + 172, '', { fill: C.text });
    const fixBar = el('rect', { x: x + 20, y: Y + 160, height: 10, rx: 5, fill: C.muted2, opacity: 0.5 }, body);
    const stop = statusBar(body, { x: x + 12, y: Y + 192, w: W - 24, fill: C.fail, str: 'Stop blocked: tests are red.' });
    const tests = [];
    for (let i = 0; i < 6; i++) {
      const tx = x + 20 + i * 34, ty = Y + 254;
      const tg = el('g', {}, body);
      const pass = el('rect', { x: tx, y: ty, width: 24, height: 24, rx: 4, fill: C.accent }, tg);
      const fail = el('rect', { x: tx, y: ty, width: 24, height: 24, rx: 4, fill: C.fail }, tg);
      tests.push({ tg, pass, fail, cx: tx + 12, cy: ty + 12, i, fix: FAILS.indexOf(i) });
    }
    const end = txt(body, x + 20, Y + 324, '✓ checks green — session may end', { fill: C.accent, weight: 600 });
    const cur = caret(body);
    // stub from the pane down to the shared rail
    const sx = x + W / 2;
    el('line', { x1: sx, x2: sx, y1: Y + H, y2: RAIL_Y, stroke: C.line2, 'stroke-width': 2 }, g);
    const stubR = el('line', { x1: sx, x2: sx, y1: Y + H, stroke: C.fail, 'stroke-width': 2 }, g);
    const stubG = el('line', { x1: sx, x2: sx, y1: Y + H, stroke: C.accent, 'stroke-width': 2 }, g);

    return (t) => {
      for (const b of bars) set(b.r, { width: b.bw * arrive(prog(t, b.t0, b.t0 + 0.35)) });

      // claim → slam → take it back (backspace) → fix
      const shown = t < 2.6 ? typed(DONE, t, 1.25, 55) : DONE.slice(0, Math.floor(DONE.length * (1 - prog(t, 2.6, 2.95))));
      set(done, { text: shown });
      cur.at(done, (t > 1.2 && t < 1.8) || (t > 2.6 && t < 3.0));
      set(fixBar, { width: 300 * arrive(prog(t, 3.0, 3.7)) });

      const slam = arrive(prog(t, 2.0, 2.16));
      stop.seek(slam > 0 ? 1 : 0, (0.4 + 0.6 * slam) * (1 - 0.6 * prog(t, 4.7, 4.9)));
      set(stop.g, { transform: `translate(0,${(1 - slam) * -26})` });
      const [kx, ky] = shake(t, 2.0, 4);
      set(body, { transform: `translate(${kx},${ky})` });

      for (const x of tests) {
        const a = arrive(prog(t, 2.05 + x.i * 0.04, 2.25 + x.i * 0.04));
        const tf = x.fix >= 0 ? 3.95 + x.fix * 0.3 : Infinity;
        const f = prog(t, tf, tf + 0.2);
        const sy = f > 0 && f < 1 ? Math.abs(1 - 2 * f) : 1;
        const isFail = x.fix >= 0 && f < 0.5;
        show(x.fail, isFail); show(x.pass, !isFail);
        set(x.tg, { opacity: a, transform: `translate(${x.cx},${x.cy}) scale(1,${sy}) translate(${-x.cx},${-x.cy})` });
      }

      const eu = arrive(prog(t, 4.8, 5.1));
      set(end, { opacity: eu, transform: `translate(${(1 - eu) * -12},0)` });

      set(stubR, { y2: lerp(Y + H, RAIL_Y, linear(prog(t, 2.0, 2.15))), opacity: 1 - prog(t, 4.75, 4.85) });
      set(stubG, { y2: lerp(Y + H, RAIL_Y, linear(prog(t, 4.75, 4.9))) });
    };
  }

  SCENES['agent-cant-finish-red'] = {
    w: 1000, h: 560, dur: 7, loop: true, xf: 0.25, poster: 6.2,
    alt: 'Claude Code and Codex CLI side by side: each claims it is done, a Stop hook blocks the session because tests are red, the agent fixes them and may end once checks are green.',
    events: [{ t: 2.0, type: 'slam' }, { t: 4.05, type: 'flip', n: 0 }, { t: 4.35, type: 'flip', n: 1 }, { t: 4.8, type: 'chime', n: 2 }],
    build(root) {
      const g = el('g', {}, root);
      el('rect', { width: 1000, height: 560, fill: C.bg }, g);
      const panes = PANES.map((p) => pane(g, p));
      const r = rail(g, { x0: 20, x1: 980, y: RAIL_Y });
      const gt = gate(g, { x: GATE_X, y: RAIL_Y });
      txt(g, 500, 540, 'same gate, both agents', { family: SANS, size: 24, fill: C.muted, anchor: 'middle' });
      return {
        seek(t) {
          panes.forEach((p) => p(t)); // parity: same function, same t
          const close = arrive(prog(t, 2.08, 2.28)) * (1 - arrive(prog(t, 4.85, 5.1)));
          gt.seek({ close, red: prog(t, 2.08, 2.16) * (1 - prog(t, 4.85, 5.0)) });
          r.seek({ red: linear(prog(t, 2.12, 2.6)) * (1 - arrive(prog(t, 4.85, 5.2))), gx: GATE_X });
        },
      };
    },
  };
})();
