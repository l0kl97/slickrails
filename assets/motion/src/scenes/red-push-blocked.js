/* red-push-blocked (5 s) — pre-push runs the tests, two fail, the gate drops.
 * The two red tests flip green, push again, the commit passes the gate. */
(() => {
  const RAIL_Y = 506, GATE_X = 800, FAIL = [2, 5];
  SCENES['red-push-blocked'] = {
    w: 1000, h: 560, dur: 5, loop: true, xf: 0.25, poster: 4.7,
    alt: 'git push runs the tests in a pre-push hook, two fail and a red gate blocks the push; the tests are fixed and the push passes the green gate.',
    events: [{ t: 1.92, type: 'slam' }, { t: 2.8, type: 'flip', n: 0 }, { t: 3.1, type: 'flip', n: 1 }, { t: 3.97, type: 'chime', n: 1 }],
    build(root) {
      const g = el('g', {}, root);
      el('rect', { width: 1000, height: 560, fill: C.bg }, g);
      const termG = el('g', {}, g);
      panel(termG, 40, 32, 920, 380);

      const p1 = txt(termG, 64, 82, '', { fill: C.text });
      const run = txt(termG, 64, 130, 'pre-push: running tests…', { fill: C.muted });
      const spin1 = spinner(termG);
      const tests = [];
      for (let i = 0; i < 8; i++) {
        const x = 64 + i * 38, y = 150;
        const tg = el('g', {}, termG);
        const pass = el('rect', { x, y, width: 26, height: 26, rx: 4, fill: C.accent }, tg);
        const fail = el('rect', { x, y, width: 26, height: 26, rx: 4, fill: C.fail }, tg);
        tests.push({ tg, pass, fail, cx: x + 13, cy: y + 13, tIn: 0.75 + i * 0.12, fix: FAIL.indexOf(i) });
      }
      const bad = statusBar(termG, { x: 56, y: 196, w: 888, fill: C.fail, str: '✗ 2 failing — push blocked' });
      const p2 = txt(termG, 64, 290, '$ git push', { fill: C.text });
      const spin2 = spinner(termG);
      const good = statusBar(termG, { x: 56, y: 308, w: 888, fill: C.accent, str: '✓ all green — pushed' });
      const cur = caret(g);

      const r = rail(g, { x0: 40, x1: 960, y: RAIL_Y });
      const gt = gate(g, { x: GATE_X, y: RAIL_Y });
      const glow = glowFilter(g, 3);
      const dot = el('circle', { r: 8, fill: C.accent, filter: glow, cy: RAIL_Y }, g);

      return {
        seek(t) {
          set(p1, { text: '$ ' + typed('git push', t, 0.2, 30) });
          cur.at(p1, t < 0.6);

          set(run, { opacity: t >= 0.62 ? 1 : 0 });
          spin1.seek(t, 64 + width(run) + 22, 123, t >= 0.62 && t < 1.85);

          for (const x of tests) {
            const a = arrive(prog(t, x.tIn, x.tIn + 0.2));
            // flip: squash to 0 at the midpoint, colour swaps exactly there (no hue blending)
            const tf = x.fix >= 0 ? 2.7 + x.fix * 0.3 : Infinity;
            const f = prog(t, tf, tf + 0.2);
            const sy = f > 0 && f < 1 ? Math.abs(1 - 2 * f) : 1;
            const isFail = x.fix >= 0 && f < 0.5;
            show(x.fail, isFail); show(x.pass, !isFail);
            set(x.tg, { opacity: a, transform: `translate(${x.cx},${x.cy}) scale(${0.6 + 0.4 * a},${(0.6 + 0.4 * a) * sy}) translate(${-x.cx},${-x.cy})` });
          }

          const blocked = prog(t, 1.92, 2.0);
          const fixed = prog(t, 3.97, 4.1);
          bad.seek(arrive(prog(t, 1.9, 2.2)), 1 - 0.55 * fixed);
          const [sx, sy] = shake(t, 1.92, 3);
          set(termG, { transform: `translate(${sx},${sy})` });

          set(p2, { opacity: prog(t, 3.35, 3.42) });
          spin2.seek(t, 64 + width(p2) + 22, 283, t >= 3.42 && t < 3.95);
          good.seek(arrive(prog(t, 3.95, 4.25)));

          const close = arrive(prog(t, 1.92, 2.12)) * (1 - arrive(prog(t, 3.97, 4.2)));
          gt.seek({ close, red: blocked * (1 - fixed) });
          r.seek({ red: linear(prog(t, 1.95, 2.45)) * (1 - arrive(prog(t, 3.97, 4.3))), gx: GATE_X });

          // the pushed commit goes through the open gate
          const u = travel(prog(t, 4.05, 4.7));
          show(dot, u > 0 && u < 1);
          set(dot, { cx: lerp(640, 960, u), opacity: 1 - prog(t, 4.55, 4.7) });
        },
      };
    },
  };
})();
