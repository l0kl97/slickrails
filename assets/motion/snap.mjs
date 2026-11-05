// Dev helper: sharp stills at given times, tiled into one sheet for a quick look.
// node snap.mjs <scene> <t1,t2,...> [out.png]
import { chromium } from 'playwright';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const [name, times = '0', out = path.join(ROOT, 'out/.cache', `snap-${name}.png`)] = process.argv.slice(2);
const FFMPEG = process.env.FFMPEG || 'ffmpeg';
const ts = times.split(',').map(Number);
const dir = path.join(ROOT, 'out/.cache/snap');
fs.mkdirSync(dir, { recursive: true });
const browser = await chromium.launch();
const isReel = name === 'showreel';
const page = await browser.newPage({ viewport: isReel ? { width: 1920, height: 1080 } : { width: 1000, height: 560 } });
await page.goto(`file://${path.join(ROOT, 'scenes', name + '.html')}?render=1`);
const errs = [];
page.on('pageerror', (e) => errs.push(e.message));
await page.evaluate(() => document.fonts.ready);
for (let i = 0; i < ts.length; i++) {
  await page.evaluate((t) => window.seek(t), ts[i]);
  await page.screenshot({ path: path.join(dir, `${String(i).padStart(3, '0')}.png`) });
}
await browser.close();
if (errs.length) console.error(errs);
const cols = Math.min(ts.length, isReel ? 2 : 3);
const scale = isReel ? 960 : 1000;
execFileSync(FFMPEG, ['-y', '-v', 'error', '-framerate', '1', '-i', path.join(dir, '%03d.png'),
  '-vf', `scale=${scale}:-1,tile=${cols}x${Math.ceil(ts.length / cols)}:padding=6:color=0x444444`,
  '-frames:v', '1', out]);
fs.rmSync(dir, { recursive: true });
console.log(out);
