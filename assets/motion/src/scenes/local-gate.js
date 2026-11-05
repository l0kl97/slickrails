/* local-gate (6 s) — your push → gate → origin. A red commit bounces off the gate
 * and origin never sees it; a green commit passes and lands on origin. */
(() => {
  const Y = 240, GX = 500, A = { x: 60, w: 220 }, O = { x: 720, w: 220 };
  SCENES['local-gate'] = {
    w: 1000, h: 560, dur: 6, loop: true, xf: 0.25, poster: 5.5,
    alt: 'A red commit travels from your push to the gate and bounces back, origin never sees it; a green commit passes the gate and reaches origin.',
    events: [{ t: 1.45, type: 'slam' }, { t: 3.2, type: 'chime', n: 0 }, { t: 3.9, type: 'chime', n: 2 }],
    build(root) {
      const g = el('g', {}, root);
      el('rect', { width: 1000, height: 560, fill: C.bg }, g);
      const glow = glowFilter(g, 3);

      const r = rail(g, { x0: A.x + A.w, x1: O.x, y: Y });
      const trail = el('line', { y1: Y, y2: Y, x1: A.x + A.w, stroke: C.accent, 'stroke-width': 4, 'stroke-linecap': 'round' }, g);

      const node = (n, label) => {
        const ng = el('g', {}, g);
        const box = el('rect', { x: n.x + 0.5, y: Y - 49.5, width: n.w - 1, height: 99, rx: 10, fill: C.panel, stroke: C.line2 }, ng);
        const lit = el('rect', { x: n.x + 0.5, y: Y - 49.5, width: n.w - 1, height: 99, rx: 10, fill: 'none', stroke: C.accent, 'stroke-width': 2, opacity: 0 }, ng);
        const te = txt(ng, n.x + n.w / 2, Y + 8, label, { anchor: 'middle' });
        return { ng, box, lit, te };
      };
      const push = node(A, 'your push');
      const origin = node(O, 'origin');
      const gt = gate(g, { x: GX, y: Y });
      txt(g, GX, Y + 64, 'gate', { fill: C.muted, anchor: 'middle' });
      const rej = txt(g, GX, Y + 130, '✗ rejected — origin never saw it', { fill: C.fail, anchor: 'middle', weight: 600 });
      const ring = el('circle', { cx: O.x + O.w / 2, cy: Y, fill: 'none', stroke: C.accent, 'stroke-width': 2 }, g);
      const red = el('circle', { r: 10, cy: Y, fill: C.fail }, g);
      const green = el('circle', { r: 10, cy: Y, fill: C.accent, filter: glow }, g);
      txt(g, 500, 500, 'checks the pushed commit, not your working copy', { family: SANS, size: 24, fill: C.muted, anchor: 'middle' });

      return {
        seek(t) {
          // red commit: out to the gate (1.5), bounce home, fade
          const out = travel(prog(t, 0.6, 1.5)), back = arrive(prog(t, 1.5, 2.15));
          const rx = lerp(lerp(A.x + A.w + 20, GX - 30, out), A.x + A.w + 20, back);
          set(red, { cx: rx, opacity: prog(t, 0.45, 0.6) * (1 - prog(t, 2.2, 2.5)) });
          show(red, t > 0.45 && t < 2.5);

          const hit = prog(t, 1.45, 1.52);
          const close = arrive(prog(t, 1.3, 1.48)) * (1 - arrive(prog(t, 2.5, 2.75)));
          gt.seek({ close, red: hit * (1 - prog(t, 2.5, 2.6)) });
          r.seek({ red: linear(prog(t, 1.48, 1.9)) * (1 - arrive(prog(t, 2.4, 2.7))), gx: GX, glow: 0.35 });
          const ru = arrive(prog(t, 1.55, 1.85)) * (1 - prog(t, 2.6, 2.8));
          set(rej, { opacity: ru, transform: `translate(0,${(1 - ru) * 10})` });
          // origin stays dark while the red one is around: it never saw it
          set(origin.te, { opacity: 1 - 0.55 * prog(t, 1.5, 1.7) * (1 - prog(t, 2.6, 2.8)) });

          // green commit: all the way to origin
          const gu = travel(prog(t, 2.85, 3.9));
          const gx = lerp(A.x + A.w + 20, O.x - 6, gu);
          show(green, t > 2.7 && t < 4.0);
          set(green, { cx: gx, opacity: prog(t, 2.7, 2.85) * (1 - prog(t, 3.85, 3.95)) });
          set(trail, { x2: t > 2.85 ? gx : A.x + A.w, opacity: t > 2.85 ? 1 - 0.5 * prog(t, 4.0, 4.4) : 0 });

          const lu = arrive(prog(t, 3.85, 4.15));
          set(origin.lit, { opacity: lu });
          set(origin.te, { fill: lu > 0.5 ? C.accent : C.text });
          const pu = prog(t, 3.9, 4.5);
          show(ring, pu > 0 && pu < 1);
          set(ring, { r: lerp(40, 130, arrive(pu)), opacity: 0.5 * (1 - pu) });
        },
      };
    },
  };
})();
