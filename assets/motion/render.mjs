// Renders every scene (and the showreel) from window.seek(t) — deterministic, offline.
//
//   node build.mjs && node render.mjs                # all six scenes + showreel
//   node render.mjs chaos-to-rails local-gate        # just these
//   node render.mjs --no-reel | --reel-only
//
// Pipeline per scene:
//   Playwright screenshots at 180 Hz (3 sub-frames per 60 fps frame, centred on the frame time)
//   → ffmpeg tmix=3 (motion blur, 360° shutter at 60 fps) → lossless master (ffv1)
//   → out/<name>.mp4 (H.264, bt709) · out/<name>.webm (VP9) · out/<name>.gif (30 fps, ≤128 colours)
//   → out/<name>-poster.png (sharp still for prefers-reduced-motion) · out/contact/<name>.png
// Requires ffmpeg/ffprobe on PATH (or FFMPEG / FFPROBE env vars).
import { chromium } from 'playwright';
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SCENE_NAMES } from './scene-names.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(ROOT, 'out');
const CACHE = path.join(OUT, '.cache');
const FFMPEG = process.env.FFMPEG || 'ffmpeg';
const FFPROBE = process.env.FFPROBE || 'ffprobe';
const SUB = 3, MASTER = 60, GIF_FPS = 30;
const GIF_BUDGET = 1.5 * 1024 * 1024, GIF_HARD_CAP = 2.5 * 1024 * 1024;
const CONCURRENCY = +(process.env.RENDER_JOBS || 3);

const args = process.argv.slice(2);
const named = args.filter((a) => !a.startsWith('--'));
const scenes = args.includes('--reel-only') ? [] : (named.length ? named : SCENE_NAMES);
const doReel = !args.includes('--no-reel') && (named.length === 0 || named.includes('showreel'));
for (const n of scenes) if (n !== 'showreel' && !SCENE_NAMES.includes(n)) throw new Error(`unknown scene: ${n}`);

fs.mkdirSync(path.join(OUT, 'contact'), { recursive: true });
fs.mkdirSync(CACHE, { recursive: true });

function ff(argv, { input } = {}) {
  const p = spawn(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', ...argv], { stdio: [input ? 'pipe' : 'ignore', 'ignore', 'pipe'] });
  let err = '';
  p.stderr.on('data', (d) => (err += d));
  const done = new Promise((res, rej) => p.on('close', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg ${c}: ${err}\n${argv.join(' ')}`)))));
  return { p, done };
}
const write = (stream, buf) => new Promise((res, rej) => (stream.write(buf, (e) => (e ? rej(e) : res()))));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

async function openPage(browser, file, w, h) {
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`file://${path.join(ROOT, 'scenes', file)}?render=1`);
  await page.evaluate(() => document.fonts.ready);
  if (errors.length) throw new Error(`${file}: ${errors.join('; ')}`);
  return page;
}
const shot = (page) => page.screenshot({ type: 'png', animations: 'disabled', caret: 'hide' });

// Sub-frame n samples t = (n - 1) / 180: three samples centred on each 60 fps frame time.
// Looping scenes wrap negative time to the end, so the blur across the seam is correct too.
// Scenes may declare `cuts` (seconds); sub-frames are clamped to their frame's side of each cut.
async function renderMaster(page, meta, masterPath) {
  const frames = Math.round(meta.dur * MASTER) + (meta.loop ? 0 : 1);
  const { p, done } = ff(['-f', 'image2pipe', '-framerate', String(MASTER * SUB), '-i', '-',
    '-vf', `tmix=frames=${SUB},select='eq(mod(n\\,${SUB})\\,${SUB - 1})',setpts=N/${MASTER}/TB`,
    '-r', String(MASTER), '-c:v', 'ffv1', '-pix_fmt', 'bgr0', masterPath], { input: true });
  const cuts = meta.cuts || [];
  for (let n = 0; n < frames * SUB; n++) {
    let t = (n - 1) / (MASTER * SUB);
    // hard cuts stay hard: a sub-frame never samples the other side of a cut from its frame centre
    const centre = Math.floor(n / SUB) / MASTER;
    for (const c of cuts) {
      if (centre >= c && t < c) t = c;
      else if (centre < c && t >= c) t = c - 1e-6;
    }
    if (t < 0) t = meta.loop ? t + meta.dur : 0;
    await page.evaluate((x) => window.seek(x), t);
    await write(p.stdin, await shot(page));
  }
  p.stdin.end();
  await done;
  return frames;
}

const BT709 = ['-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv'];

async function encodeVideos(name, master, wav) {
  const audioIn = wav ? ['-i', wav] : [];
  const audioOut = wav ? ['-c:a', 'aac', '-b:a', '256k', '-shortest'] : ['-an'];
  await ff(['-i', master, ...audioIn, ...BT709, '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-tune', 'animation',
    '-movflags', '+faststart', ...audioOut, path.join(OUT, `${name}.mp4`)]).done;
  await ff(['-i', master, ...BT709, '-c:v', 'libvpx-vp9', '-crf', '22', '-b:v', '0', '-row-mt', '1', '-an', path.join(OUT, `${name}.webm`)]).done;
}

// GIF: every second master frame (30 fps). Text is never degraded; if over budget we spend
// fewer colours first, then fewer frames.
async function encodeGif(name, master) {
  const out = path.join(OUT, `${name}.gif`);
  const tries = [
    { colors: 128, fps: 30, dither: 'bayer:bayer_scale=4' },
    { colors: 96, fps: 30, dither: 'bayer:bayer_scale=4' },
    { colors: 64, fps: 30, dither: 'bayer:bayer_scale=5' },
    { colors: 64, fps: 20, dither: 'bayer:bayer_scale=5' },
  ];
  const attempts = [];
  for (const o of tries) {
    const step = MASTER / o.fps;
    await ff(['-i', master, '-filter_complex',
      `[0:v]select='not(mod(n\\,${step}))',setpts=N/${o.fps}/TB,split[a][b];` +
      `[a]palettegen=max_colors=${o.colors}:stats_mode=diff[p];` +
      `[b][p]paletteuse=dither=${o.dither}:diff_mode=rectangle`,
    '-r', String(o.fps), '-loop', '0', out]).done;
    const size = fs.statSync(out).size;
    attempts.push({ ...o, size });
    if (size <= GIF_BUDGET) break;
  }
  return attempts;
}

async function contactSheet(name, master, w) {
  // every 0.5 s, at half size, 4 per row
  await ff(['-i', master, '-vf', `select='not(mod(n\\,${MASTER / 2}))',scale=${Math.round(w / 2)}:-1,tile=4x4:padding=4:color=0x333333`,
    '-frames:v', '1', path.join(OUT, 'contact', `${name}.png`)]).done;
}

function probe(file) {
  const j = JSON.parse(execFileSync(FFPROBE, ['-v', 'error', '-show_entries',
    'format=duration,size:stream=codec_type,codec_name,width,height,avg_frame_rate,nb_frames', '-of', 'json', file]).toString());
  const v = j.streams.find((s) => s.codec_type === 'video');
  const a = j.streams.find((s) => s.codec_type === 'audio');
  const [num, den] = v.avg_frame_rate.split('/').map(Number);
  // GIF delays are 1/100 s: 30 fps is stored as 3,3,4 cs and ffprobe's avg_frame_rate reports the
  // 3 cs timebase (33.33). frames ÷ duration is the real playback rate.
  const fps = v.nb_frames && +j.format.duration ? +v.nb_frames / +j.format.duration : den ? num / den : 0;
  return { file: path.basename(file), codec: v.codec_name, w: v.width, h: v.height, fps: +fps.toFixed(2),
    frames: v.nb_frames, duration: +(+j.format.duration).toFixed(3), size: +j.format.size, audio: a ? a.codec_name : '—' };
}

async function renderScene(browser, name) {
  const page = await openPage(browser, `${name}.html`, 1000, 560);
  const meta = await page.evaluate(() => window.SCENE);
  const t0 = Date.now();
  // seam check: the frame at t = dur must equal the frame at t = 0
  let seam = 'n/a';
  if (meta.loop) {
    await page.evaluate(() => window.seek(0)); const a = await shot(page);
    await page.evaluate((d) => window.seek(d), meta.dur); const b = await shot(page);
    seam = a.equals(b) ? 'identical' : 'DIFFERS';
  }
  await page.evaluate((t) => window.seek(t), meta.poster);
  await page.screenshot({ path: path.join(OUT, `${name}-poster.png`), type: 'png' });
  const master = path.join(CACHE, `${name}.mkv`);
  await renderMaster(page, meta, master);
  await page.close();
  log(name, 'master', `${((Date.now() - t0) / 1000).toFixed(1)}s`);
  await encodeVideos(name, master);
  const gif = await encodeGif(name, master);
  await contactSheet(name, master, 1000);
  log(name, 'done', gif.map((g) => `${g.colors}c/${g.fps}fps=${(g.size / 1048576).toFixed(2)}MB`).join(' → '));
  return { name, meta, seam, gif };
}

async function renderReel(browser) {
  const page = await openPage(browser, 'showreel.html', 1920, 1080);
  const meta = await page.evaluate(() => window.SCENE);
  const wav = path.join(OUT, 'showreel.wav');
  fs.writeFileSync(wav, Buffer.from(await page.evaluate(() => window.renderAudio()), 'base64'));
  const cues = await page.evaluate(() => window.CUES());
  log('showreel', 'audio', cues.length, 'cues');
  await page.evaluate((t) => window.seek(t), meta.poster);
  await page.screenshot({ path: path.join(OUT, 'showreel-poster.png'), type: 'png' });
  const master = path.join(CACHE, 'showreel.mkv');
  await renderMaster(page, meta, master);
  await page.close();
  await encodeVideos('showreel', master, wav);
  await contactSheet('showreel', master, 1920);
  log('showreel', 'done');
  return { name: 'showreel', meta, cues };
}

// WCAG contrast of the text/background pairs the scenes actually use.
function contrast(a, b) {
  const L = (hex) => {
    const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  };
  const [x, y] = [L(a), L(b)].sort((m, n) => n - m);
  return (x + 0.05) / (y + 0.05);
}
const PAIRS = [
  ['text #E8EDEA', '#E8EDEA', 'bg #0B0F0E', '#0B0F0E'], ['text #E8EDEA', '#E8EDEA', 'panel #121816', '#121816'],
  ['muted #8FA39A', '#8FA39A', 'bg #0B0F0E', '#0B0F0E'], ['muted #8FA39A', '#8FA39A', 'panel #121816', '#121816'],
  ['accent #A8FF06', '#A8FF06', 'panel #121816', '#121816'], ['fail #E5484D', '#E5484D', 'bg #0B0F0E', '#0B0F0E'],
  ['bg #0B0F0E', '#0B0F0E', 'fail bar #E5484D', '#E5484D'], ['bg #0B0F0E', '#0B0F0E', 'accent bar #A8FF06', '#A8FF06'],
];

function report(results) {
  const mb = (b) => `${(b / 1048576).toFixed(2)} MB`;
  const L = ['# Render report', '', `Generated by \`render.mjs\` on ${new Date().toISOString().slice(0, 10)}. Numbers below come from \`ffprobe\`; nothing is hand-edited.`, ''];
  L.push('## Outputs', '', '| file | codec | size px | fps | frames | duration s | file size | audio |', '|---|---|---|---|---|---|---|---|');
  for (const r of results) {
    for (const ext of ['gif', 'mp4', 'webm']) {
      const f = path.join(OUT, `${r.name}.${ext}`);
      if (!fs.existsSync(f)) continue;
      const p = probe(f);
      L.push(`| ${p.file} | ${p.codec} | ${p.w}×${p.h} | ${p.fps} | ${p.frames ?? '—'} | ${p.duration} | ${mb(p.size)} | ${p.audio} |`);
    }
  }
  L.push('', '## README budget (GIF)', '', '| scene | duration | colours | gif fps | size | ≤ 1.5 MB | ≤ 2.5 MB cap | loop seam (t=dur vs t=0) |', '|---|---|---|---|---|---|---|---|');
  for (const r of results.filter((x) => x.gif)) {
    const g = r.gif[r.gif.length - 1];
    L.push(`| ${r.name} | ${r.meta.dur} s | ≤ ${g.colors} | ${g.fps} | ${mb(g.size)} | ${g.size <= GIF_BUDGET ? 'yes' : 'NO'} | ${g.size <= GIF_HARD_CAP ? 'yes' : 'NO'} | ${r.seam} |`);
    if (r.gif.length > 1) L.push(`|  ↳ budget fallback | | ${r.gif.map((x) => `${x.colors}c/${x.fps}fps ${mb(x.size)}`).join(' → ')} | | | | | |`);
  }
  L.push('', '## Contrast (WCAG 2.x, text pairs used on screen)', '', '| foreground | background | ratio | ≥ 4.5:1 |', '|---|---|---|---|');
  for (const [fa, f, ba, b] of PAIRS) { const c = contrast(f, b); L.push(`| ${fa} | ${ba} | ${c.toFixed(2)}:1 | ${c >= 4.5 ? 'yes' : 'NO'} |`); }
  const reel = results.find((r) => r.cues);
  if (reel) {
    L.push('', '## Showreel sound cues (derived from scene events)', '', reel.cues.map((c) => `\`${c.t.toFixed(2)} ${c.type}\``).join(' · '));
  }
  L.push('', '## Checked by construction (not measured from pixels)', '',
    '- Palette ≤ 128 colours per GIF: enforced by `palettegen=max_colors`.',
    '- Smallest on-screen text is 22 px at 1000 px width (mono 22 px; captions 24–26 px sans).',
    '- No flashing > 3 Hz: the only periodic change is the chaos-label flicker at 2.2 Hz, partial opacity, small area; impacts shake ≤ 4 px for 0.2 s.',
    '- Every scene paints its own opaque `#0B0F0E` background (no transparency).',
    '', '## Not verified', '',
    "- GitHub's own GIF rendering (camo proxy, mobile clients) — not testable from here.",
    '- GIF frame timing: GIF stores delays in 1/100 s, so 30 fps is written as alternating 3/4 cs delays (average 33.3 ms).',
    '- Fonts are the system stack (`ui-monospace` / `system-ui`). Renders were made on macOS (SF Mono / SF Pro); on other render hosts glyph widths differ.',
    '- `prefers-reduced-motion` cannot switch a README `<img>`; the poster PNG is provided for pages that can use `<picture>`/CSS.',
  );
  fs.writeFileSync(path.join(OUT, 'REPORT.md'), L.join('\n') + '\n');
}

const browser = await chromium.launch();
const results = [];
const queue = [...scenes];
await Promise.all([...Array(Math.min(CONCURRENCY, queue.length || 1))].map(async () => {
  while (queue.length) results.push(await renderScene(browser, queue.shift()));
}));
if (doReel) results.push(await renderReel(browser));
await browser.close();
results.sort((a, b) => [...SCENE_NAMES, 'showreel'].indexOf(a.name) - [...SCENE_NAMES, 'showreel'].indexOf(b.name));
report(results);
log('report → out/REPORT.md');
