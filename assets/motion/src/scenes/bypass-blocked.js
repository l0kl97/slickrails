/* bypass-blocked (4 s) — the agent tries --no-verify, bash-guard blocks it.
 * Honest caption: hooks are a hint, the boundary lives in CI and branch protection. */
(() => {
  const RAIL_Y = 330, GX = 500;
  SCENES['bypass-blocked'] = {
    w: 1000, h: 560, dur: 4, loop: true, xf: 0.3, xfMode: 'dip', poster: 3.4,
    alt: 'git commit --no-verify is blocked by bash-guard and a red gate drops; caption: hooks are a hint, CI and branch protection are the boundary.',
    events: [{ t: 1.1, type: 'slam' }],
    build(root) {
      const g = el('g', {}, root);
      el('rect', { width: 1000, height: 560, fill: C.bg }, g);
      const termG = el('g', {}, g);
      panel(termG, 40, 40, 920, 150);
      const p = txt(termG, 64, 92, '', { fill: C.text });
      const bar = statusBar(termG, { x: 56, y: 116, w: 888, fill: C.fail, str: 'bash-guard: blocked' });
      const cur = caret(g);
      const r = rail(g, { x0: 40, x1: 960, y: RAIL_Y });
      const gt = gate(g, { x: GX, y: RAIL_Y });

      const cap = el('text', { x: 500, y: 452, 'font-family': SANS, 'font-size': 26, 'text-anchor': 'middle', fill: C.text }, g);
      cap.innerHTML = `<tspan fill="${C.muted}">hooks are a hint;</tspan> CI and branch protection are the boundary`;

      return {
        seek(t) {
          set(p, { text: '$ ' + typed('git commit --no-verify', t, 0.2, 32) });
          cur.at(p, t < 1.1);
          const slam = arrive(prog(t, 1.1, 1.26));
          bar.seek(slam > 0 ? 1 : 0, 0.4 + 0.6 * slam);
          set(bar.g, { transform: `translate(0,${(1 - slam) * -24})` });
          const [sx, sy] = shake(t, 1.1, 4);
          set(termG, { transform: `translate(${sx},${sy})` });
          gt.seek({ close: arrive(prog(t, 1.12, 1.3)), red: prog(t, 1.12, 1.2) });
          r.seek({ red: linear(prog(t, 1.15, 1.6)), gx: GX });
          const cu = arrive(prog(t, 1.6, 2.0));
          set(cap, { opacity: cu, transform: `translate(0,${(1 - cu) * 12})` });
        },
      };
    },
  };
})();
