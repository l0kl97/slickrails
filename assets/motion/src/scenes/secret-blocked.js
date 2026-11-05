/* secret-blocked (5 s) — a masked key is typed into the diff, the pre-commit hook
 * stops the commit, the rail goes red and the gate drops. Line removed, rerun, green. */
(() => {
  const RAIL_Y = 506, GATE_X = 800;
  SCENES['secret-blocked'] = {
    w: 1000, h: 560, dur: 5, loop: true, xf: 0.25, poster: 4.7,
    alt: 'A masked STRIPE_KEY line is staged, the pre-commit hook blocks the commit and drops a red gate; the line is removed and the commit goes through on green.',
    events: [{ t: 2.22, type: 'slam' }, { t: 4.3, type: 'chime', n: 0 }],
    build(root) {
      const g = el('g', {}, root);
      el('rect', { width: 1000, height: 560, fill: C.bg }, g);

      // Diff view.
      const diffG = el('g', {}, g);
      panel(diffG, 40, 32, 920, 138);
      txt(diffG, 64, 70, '.env', { fill: C.muted });
      el('line', { x1: 41, x2: 959, y1: 86.5, y2: 86.5, stroke: C.line2 }, diffG);
      const row = el('g', {}, diffG);
      el('rect', { x: 41, y: 100, width: 918, height: 44, fill: C.panel2 }, row);
      const rowRed = el('rect', { x: 41, y: 100, width: 918, height: 44, fill: C.fail, opacity: 0 }, row);
      txt(row, 64, 129, '+', { fill: C.muted });
      const KEY = 'STRIPE_KEY=sk_live_••••';
      const keyT = txt(row, 96, 129, KEY, { fill: C.text });
      const KEY_W = width(keyT); // measured once: measuring per frame drifts with the row's scale
      set(keyT, { text: '' });
      const strike = el('line', { x1: 92, y1: 122, y2: 122, stroke: C.fail, 'stroke-width': 3, 'stroke-linecap': 'round' }, row);

      // Terminal.
      const termG = el('g', {}, g);
      panel(termG, 40, 186, 920, 210);
      const CMD = 'git commit -m "add stripe"';
      const p1 = txt(termG, 64, 228, '', { fill: C.text });
      const bar = statusBar(termG, { x: 56, y: 244, w: 888, fill: C.fail, str: '✗ pre-commit: secret in staged changes' });
      const p2 = txt(termG, 64, 318, `$ ${CMD}`, { fill: C.text });
      const ok = txt(termG, 64, 362, '✓ commit created', { fill: C.accent, weight: 600 });
      const cur = caret(g);

      const r = rail(g, { x0: 40, x1: 960, y: RAIL_Y });
      const gt = gate(g, { x: GATE_X, y: RAIL_Y });

      return {
        seek(t) {
          // typing: the key into the diff, then the commit command
          set(keyT, { text: typed(KEY, t, 0.3, 26) });
          set(p1, { text: '$ ' + typed(CMD, t, 1.3, 38) });
          if (t < 1.25) cur.at(keyT, true);
          else if (t < 2.2) cur.at(p1, true);
          else cur.at(p1, false);

          // 2.2 commit runs → blocked
          const blocked = prog(t, 2.22, 2.3);
          const fixed = prog(t, 4.3, 4.45);
          bar.seek(arrive(prog(t, 2.2, 2.5)), 1 - 0.55 * fixed);
          set(rowRed, { opacity: 0.22 * prog(t, 2.3, 2.5) });
          const [sx, sy] = shake(t, 2.22, 3);
          set(termG, { transform: `translate(${sx},${sy})` });

          // 3.6 the line is struck and removed
          set(strike, { x2: lerp(92, 96 + KEY_W + 4, linear(prog(t, 3.6, 3.8))), opacity: t >= 3.6 ? 1 : 0 });
          const gone = arrive(prog(t, 3.8, 4.05));
          set(row, { opacity: 1 - gone, transform: `translate(0,122) scale(1,${1 - gone}) translate(0,-122)` });

          // rerun (history recall, no retyping) → created
          set(p2, { opacity: prog(t, 4.05, 4.12) });
          const okU = arrive(prog(t, 4.3, 4.55));
          set(ok, { opacity: okU, transform: `translate(${(1 - okU) * -12},0)` });

          // rail + gate
          const close = arrive(prog(t, 2.22, 2.42)) * (1 - arrive(prog(t, 4.3, 4.6)));
          gt.seek({ close, red: blocked * (1 - fixed) });
          const spread = linear(prog(t, 2.25, 2.75)) * (1 - arrive(prog(t, 4.3, 4.7)));
          r.seek({ red: spread, gx: GATE_X });
        },
      };
    },
  };
})();
