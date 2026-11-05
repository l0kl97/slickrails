/* showreel (15 s, 1920×1080, 120 BPM → one beat = 0.5 s)
 * "The agent keeps going; the rails keep it honest."
 * The reel is an edit, not new footage: it re-times the six README scenes with
 * piecewise time maps so that every cut and every gate slam lands on a beat.
 *
 *  0.0  intro    one clean rail draws and wipes in the first half of the line
 *  1.0  CUT      chaos-to-rails, full frame (chaos sped up, snap on the beat)
 *  4.0  CUT      2×2 grid; four gates slam on four consecutive beats (5.0 5.5 6.0 6.5)
 *  9.0  CUT      agent-cant-finish-red; the Stop hook slams on 10.0
 * 13.0  CUT      outro: the rail glides up, logo locks, stations light on 13.5 14.0 14.5
 */
(() => {
  const W = 1920, H = 1080, DUR = 15, BEAT = 0.5;
  const S = 1.92; // 1000×560 scene → 1920×1075
  const CUTS = [1.0, 4.0, 9.0, 13.0];

  // Clip = scene instance + time map (reel t → scene t) + visible window.
  const FULL = [
    // chaos plays at 1.0× from 0.6 s: keeps its 12 fps steps on the 60 fps frame grid (no blur ghosts)
    { name: 'chaos-to-rails', a: 1.0, b: 4.0, map: [[1.0, 0.6], [2.0, 1.6], [3.0, 3.0], [4.0, 5.25]] },
    { name: 'agent-cant-finish-red', a: 9.0, b: 13.0, map: [[9.0, 0.25], [10.0, 2.0], [12.0, 5.4], [13.0, 6.6]] },
  ];
  // Grid: local = reel - offset, offsets chosen so the gates fall on 5.0 / 5.5 / 6.0 / 6.5.
  const GRID = [
    { name: 'secret-blocked', off: 5.0 - 2.22 },
    { name: 'red-push-blocked', off: 5.5 - 1.92 },
    { name: 'bypass-blocked', off: 6.0 - 1.1 },
    { name: 'local-gate', off: 6.5 - 1.45 },
  ].map((c, i) => ({ ...c, a: 4.0, b: 9.0, map: [[c.off, 0], [c.off + 20, 20]], i }));
  const CELL = 0.93, GAP_X = 20, GAP_Y = (H - 2 * 560 * CELL) / 3;
  const cellPos = (i) => [GAP_X + (i % 2) * (1000 * CELL + GAP_X), GAP_Y + Math.floor(i / 2) * (560 * CELL + GAP_Y)];

  const sceneT = (c, t) => clamp(remap(c.map, t), 0, SCENES[c.name].dur - (SCENES[c.name].xf || 0) - 0.01);

  // Every sound cue, derived from the picture.
  function cues() {
    const out = [{ t: 0, type: 'riser', len: 1.0 }];
    for (let k = 0; k < 4; k++) out.push({ t: k * 0.25, type: 'tick' });
    CUTS.forEach((t) => out.push({ t, type: 'cut' }));
    for (const c of [...FULL, ...GRID]) {
      for (const e of SCENES[c.name].events || []) {
        const rt = unmap(c.map, e.t);
        if (rt != null && rt >= c.a && rt < c.b) out.push({ ...e, t: rt });
      }
    }
    [13.5, 14.0, 14.5].forEach((t, n) => out.push({ t, type: 'station', n }));
    out.push({ t: 13.5, type: 'lock' });
    return out.sort((x, y) => x.t - y.t);
  }

  REEL = {
    w: W, h: H, dur: DUR, bpm: 120, poster: 14.8, cues,
    build(root) {
      el('rect', { width: W, height: H, fill: C.bg }, root);
      const glow = glowFilter(root, 3);

      // ── intro: the rail is the wipe that writes the line ──────────────────────────
      const intro = el('g', {}, root);
      const RY = 2.4 + 290 * S, RX0 = 960 + (40 - 500) * S, RX1 = 960 + (960 - 500) * S;
      el('line', { x1: RX0, x2: RX1, y1: RY, y2: RY, stroke: C.line2, 'stroke-width': 4, 'stroke-linecap': 'round' }, intro);
      const iRail = el('line', { x1: RX0, y1: RY, y2: RY, stroke: C.accent, 'stroke-width': 4, 'stroke-linecap': 'round' }, intro);
      const iClip = clipRect(intro, RX0, RY - 120, 0, 110);
      const iText = txt(intro, RX0, RY - 36, 'The agent keeps going;', { size: 64, fill: C.text });
      set(iText, { 'clip-path': iClip.url });
      const iTicks = [0, 1, 2, 3].map((k) => el('rect', { x: lerp(RX0, RX1, (k + 1) / 5) - 3, y: RY - 14, width: 6, height: 28, rx: 2, fill: C.muted2 }, intro));
      const iDot = el('circle', { r: 10, cy: RY, fill: C.accent, filter: glow }, intro);

      // ── full-frame clips ──────────────────────────────────────────────────────────
      const full = FULL.map((c) => {
        const g = el('g', {}, root);
        return { ...c, g, inst: SCENES[c.name].build(el('g', {}, g)) };
      });

      // ── grid ───────────────────────────────────────────────────────────────────────
      const gridG = el('g', {}, root);
      const grid = GRID.map((c) => {
        const [x, y] = cellPos(c.i);
        const cg = el('g', {}, gridG);
        const cl = clipRect(cg, 0, 0, 1000, 560, 10 / CELL);
        const inner = el('g', { 'clip-path': cl.url }, cg);
        const inst = SCENES[c.name].build(inner);
        el('rect', { x: 0.5, y: 0.5, width: 999, height: 559, rx: 10 / CELL, fill: 'none', stroke: C.line2, 'stroke-width': 1.5 }, cg);
        return { ...c, cg, inst, x, y };
      });

      // ── outro ─────────────────────────────────────────────────────────────────────
      const outro = el('g', {}, root);
      const OY = 760, OX0 = 120, OX1 = 1800;
      const oRailBase = el('line', { x1: OX0, x2: OX1, stroke: C.line2, 'stroke-width': 4, 'stroke-linecap': 'round' }, outro);
      const oRail = el('line', { x1: OX0, x2: OX1, stroke: C.accent, 'stroke-width': 4, 'stroke-linecap': 'round', opacity: 0.4 }, outro);
      const oTrail = el('line', { x1: OX0, stroke: C.accent, 'stroke-width': 5, 'stroke-linecap': 'round' }, outro);
      const STX = [600, 960, 1320], ST = ['hooks', 'tests', 'review'];
      const oSt = STX.map((x, i) => {
        const sg = el('g', {}, outro);
        const box = el('rect', { x: x - 12, width: 24, height: 24, rx: 3, fill: C.bg, stroke: C.muted2, 'stroke-width': 2.5 }, sg);
        const lit = el('rect', { x: x - 12, width: 24, height: 24, rx: 3, fill: C.accent, filter: glow }, sg);
        const lb = txt(sg, x, 0, ST[i], { size: 32, anchor: 'middle', fill: C.muted });
        return { x, sg, box, lit, lb };
      });
      const oDot = el('circle', { r: 11, fill: C.accent, filter: glow }, outro);
      // lockup as in assets/header.html: mark + wordmark, vertically centred, measured then centred
      const lockG = el('g', {}, outro);
      const logoG = el('g', {}, lockG);
      logo(logoG, 0, 0, 150);
      const wmG = el('g', {}, lockG);
      wordmark(wmG, 171, 129, 150);
      const bb = lockG.getBBox();
      set(lockG, { transform: `translate(${960 - (bb.x + bb.width / 2)},${400 - (bb.y + bb.height / 2)})` });
      const tag = el('text', { x: 960, y: 590, 'font-family': MONO, 'font-size': 36, 'text-anchor': 'middle', fill: C.muted, style: 'white-space:pre' }, outro);
      tag.innerHTML = `The agent keeps going; <tspan fill="${C.text}">the rails keep it honest.</tspan>`;

      const on = (t, a, b) => t >= a && t < b;

      return {
        seek(t) {
          // intro (0–1): linear rail draw on the beat grid, the tip writes the line
          show(intro, on(t, 0, 1.0));
          if (on(t, 0, 1.0)) {
            const u = linear(prog(t, 0.05, 0.95));
            const x = lerp(RX0, RX1, u);
            set(iRail, { x2: x });
            set(iClip.rect, { width: Math.max(0, x - RX0) });
            set(iDot, { cx: x, opacity: prog(t, 0, 0.06) });
            iTicks.forEach((tk, k) => set(tk, { fill: x >= +tk.getAttribute('x') ? C.accent : C.muted2 }));
          }

          // full-frame clips with a slow push-in
          for (const c of full) {
            const vis = on(t, c.a, c.b);
            show(c.g, vis);
            if (!vis) continue;
            c.inst.seek(sceneT(c, t));
            const z = S * (1 + 0.035 * prog(t, c.a, c.b));
            set(c.g, { transform: `translate(960,540) scale(${z}) translate(-500,-280)` });
          }

          // grid: cells deal in staggered after the cut, then play in parallel
          const gv = on(t, 4.0, 9.0);
          show(gridG, gv);
          if (gv) for (const c of grid) {
            const u = arrive(prog(t, 4.0 + c.i * 0.08, 4.45 + c.i * 0.08));
            c.inst.seek(sceneT(c, t));
            const s = CELL * lerp(0.94, 1, u);
            const cx = c.x + 500 * CELL, cy = c.y + 280 * CELL + (1 - u) * 24;
            set(c.cg, { opacity: u, transform: `translate(${cx},${cy}) scale(${s}) translate(-500,-280)` });
          }

          // outro (13–15)
          const ov = on(t, 13.0, DUR + 1);
          show(outro, ov);
          if (ov) {
            // the rail carries over from the last clip's rail position and glides into place
            const fromY = 540 + (470 - 280) * S * 1.035;
            const y = lerp(fromY, OY, arrive(prog(t, 13.0, 13.45)));
            set(oRailBase, { y1: y, y2: y }); set(oRail, { y1: y, y2: y });
            const dx = lerp(240, 240 + 720 * 2.0, prog(t, 13.0, 15.0)); // 720 px/s → stations on 13.5 / 14.0 / 14.5
            set(oTrail, { x2: dx, y1: y, y2: y });
            set(oDot, { cx: dx, cy: y });
            oSt.forEach((s, i) => {
              const ap = arrive(prog(t, 13.1 + i * 0.06, 13.45 + i * 0.06));
              const litU = clamp((dx - s.x) / 16);
              const pulse = 1 + 0.45 * (1 - arrive(clamp((dx - s.x) / 200))) * (litU > 0 ? 1 : 0);
              set(s.box, { y: y - 12 }); set(s.lit, { y: y - 12, opacity: litU });
              set(s.lb, { y: y + 62, fill: litU > 0.5 ? C.accent : C.muted });
              set(s.sg, { opacity: ap, transform: `translate(${s.x},${y}) scale(${pulse}) translate(${-s.x},${-y})` });
            });
            const lu = arrive(prog(t, 13.05, 13.5)), wu = arrive(prog(t, 13.15, 13.6));
            set(logoG, { opacity: lu, transform: `translate(0,${(1 - lu) * 30})` });
            set(wmG, { opacity: wu, transform: `translate(0,${(1 - wu) * 30})` });
            const tu = arrive(prog(t, 14.0, 14.4));
            set(tag, { opacity: tu, transform: `translate(0,${(1 - tu) * 16})` });
          }
        },
      };
    },
  };

  // Boot (same contract as the scenes: seek(t) only).
  const stage = document.getElementById('stage');
  const R = REEL.build(el('g', {}, stage));
  window.SCENE = { name: 'showreel', w: W, h: H, dur: DUR, loop: false, poster: REEL.poster, cuts: CUTS };
  window.seek = (t) => R.seek(t);
  window.renderAudio = () => renderSoundtrack(REEL.cues(), DUR, REEL.bpm);
  window.CUES = () => REEL.cues();
  const q = new URLSearchParams(location.search);
  if (q.has('render') || q.has('t')) { window.seek(+q.get('t') || 0); return; }
  const t0 = performance.now();
  const loop = () => { window.seek(((performance.now() - t0) / 1000) % DUR); requestAnimationFrame(loop); };
  loop();
})();
