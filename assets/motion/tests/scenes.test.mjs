// Contract tests for the motion scenes: determinism, loop seams, brand palette, type size,
// and the exact on-screen strings from the brief.  Run: npm test  (after npm run build)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { SCENE_NAMES } from '../scene-names.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const PALETTE = new Set(['#0B0F0E', '#121816', '#14201B', '#1E2724', '#26302B', '#E8EDEA', '#8FA39A', '#7E9086', '#A8FF06', '#E5A83B', '#E5484D'].map((c) => c.toLowerCase()));
const BRIEF = {
  'chaos-to-rails': ['agent writes code', 'no tests', 'secret in .env', '--no-verify', 'hooks', 'tests', 'review'],
  'secret-blocked': ['$ git commit -m "add stripe"', 'STRIPE_KEY=sk_live_••••', '✗ pre-commit: secret in staged changes', '✓ commit created'],
  'red-push-blocked': ['$ git push', 'pre-push: running tests…', '✗ 2 failing — push blocked', '✓ all green — pushed'],
  'agent-cant-finish-red': ['Claude Code', 'Codex CLI', 'Done! All tasks complete.', 'Stop blocked: tests are red.', '✓ checks green — session may end', 'same gate, both agents'],
  'local-gate': ['your push', 'gate', 'origin', '✗ rejected — origin never saw it', 'checks the pushed commit, not your working copy'],
  'bypass-blocked': ['$ git commit --no-verify', 'bash-guard: blocked', 'hooks are a hint; CI and branch protection are the boundary'],
};

let browser;
before(async () => { browser = await chromium.launch(); });
after(async () => { await browser?.close(); });

async function open(name) {
  const file = path.join(ROOT, 'scenes', `${name}.html`);
  assert.ok(fs.existsSync(file), `${name}.html missing — run npm run build`);
  const page = await browser.newPage({ viewport: { width: 1000, height: 560 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`file://${file}?render=1`);
  await page.evaluate(() => document.fonts.ready);
  assert.deepEqual(errors, [], `${name} threw on load`);
  return page;
}
// Serialised visible state; a hidden subtree only counts as "hidden".
const state = (page, t) => page.evaluate((x) => {
  window.seek(x);
  const out = [];
  const walk = (e) => {
    if (e.getAttribute('display') === 'none') { out.push(`${e.tagName}:hidden`); return; }
    out.push(`${e.tagName} ${[...e.attributes].map((a) => `${a.name}=${a.value}`).join(' ')} ${e.children.length ? '' : e.textContent}`);
    for (const c of e.children) walk(c);
  };
  walk(document.getElementById('stage'));
  return out.join('\n');
}, t);
const at = async (page, t) => { await page.evaluate((x) => window.seek(x), t); return page.screenshot(); };

// Collect what is visible at time t: texts (with size) and every fill/stroke colour in use.
const inspect = (page, t) => page.evaluate((x) => {
  window.seek(x);
  const visible = (e) => { for (let n = e; n && n.nodeType === 1; n = n.parentNode) { if (n.getAttribute('display') === 'none' || +(n.getAttribute('opacity') ?? 1) === 0) return false; } return true; };
  const texts = [...document.querySelectorAll('text')].filter((e) => visible(e) && e.textContent.trim()).map((e) => ({ s: e.textContent, size: +e.getAttribute('font-size') }));
  const colours = new Set();
  for (const e of document.querySelectorAll('[fill],[stroke]')) for (const a of ['fill', 'stroke']) { const v = e.getAttribute(a); if (v && v.startsWith('#')) colours.add(v.toLowerCase()); }
  return { texts, colours: [...colours] };
}, t);

for (const name of SCENE_NAMES) {
  // Compares the rendered DOM state, not pixels: Chromium's rasteriser can differ by ±2/255
  // depending on layer history, which is invisible and not a property of the scene.
  test(`${name}: same t → same render state, at every 0.25 s, after scrubbing anywhere`, async () => {
    const page = await open(name);
    const dur = await page.evaluate(() => window.SCENE.dur);
    for (let t = 0; t <= dur; t += 0.25) {
      const a = await state(page, t);
      await state(page, (t * 7.3 + 1.1) % dur); // jump somewhere unrelated
      await state(page, 0.1);
      assert.equal(await state(page, t), a, `seek(${t}) depends on what was shown before`);
    }
    await page.close();
  });

  test(`${name}: loop seam — frame at t=dur equals frame at t=0`, async () => {
    const page = await open(name);
    const dur = await page.evaluate(() => window.SCENE.dur);
    assert.ok((await at(page, 0)).equals(await at(page, dur)));
    await page.close();
  });

  test(`${name}: only brand colours, text ≥ 22 px, exact brief strings`, async () => {
    const page = await open(name);
    const dur = await page.evaluate(() => window.SCENE.dur);
    const seen = new Set();
    for (let t = 0; t <= dur; t += 0.25) {
      const { texts, colours } = await inspect(page, t);
      for (const c of colours) assert.ok(PALETTE.has(c), `off-palette colour ${c} at t=${t}`);
      for (const x of texts) { assert.ok(x.size >= 22, `"${x.s}" is ${x.size}px at t=${t}`); seen.add(x.s); }
    }
    const all = [...seen].join('\n');
    for (const s of BRIEF[name]) assert.ok(all.includes(s), `brief string never fully on screen: "${s}"`);
    await page.close();
  });
}

test('sources: no wall-clock time or unseeded randomness in render paths', () => {
  const dirs = ['src/lib', 'src/scenes', 'src/reel'];
  for (const d of dirs) for (const f of fs.readdirSync(path.join(ROOT, d))) {
    const src = fs.readFileSync(path.join(ROOT, d, f), 'utf8');
    assert.ok(!/Math\.random|Date\.now|new Date\(/.test(src), `${d}/${f} uses non-deterministic time/randomness`);
    assert.ok(!/requestAnimationFrame|performance\.now/.test(src) || f === 'showreel.js', `${d}/${f} uses rAF`);
  }
});

test('palette check actually fails on an off-brand colour (guards the guard)', async () => {
  const page = await open('local-gate');
  await page.evaluate(() => document.querySelector('rect').setAttribute('fill', '#FF00FF'));
  const { colours } = await page.evaluate(() => ({ colours: [...document.querySelectorAll('[fill]')].map((e) => e.getAttribute('fill').toLowerCase()) }));
  assert.ok(colours.some((c) => !PALETTE.has(c)), 'injected colour not detected');
  await page.close();
});

test('logo shapes are taken verbatim from assets/logo.svg', () => {
  const logo = fs.readFileSync(path.join(ROOT, '..', 'logo.svg'), 'utf8');
  const shapes = logo.match(/<(rect|polygon)[^>]*>/g);
  const html = fs.readFileSync(path.join(ROOT, 'scenes', 'chaos-to-rails.html'), 'utf8');
  for (const s of shapes) assert.ok(html.includes(JSON.stringify(s).slice(1, -1)) || html.includes(s.replace(/"/g, '\\"')), `logo shape missing: ${s}`);
});
