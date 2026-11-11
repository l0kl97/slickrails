# README motion: scene GIFs + showreel

**Status:** active (sources archived) · **As of:** 2026-11-11 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
"Make a dynamic motion graphics video that shows what an incredible motion designer you are,
like it's your showreel for a résumé. Go all out." The brief attached to that ask: six README
animations for slickrails (one GIF per scene, 1000×560, ≤ 1.5 MB, seamless loop, brand
palette only, exact on-screen copy from the brief, no generic AI-motion tropes) plus an optional
15 s 1920×1080 showreel at 120 BPM with an `OfflineAudioContext` soundtrack. The concept line:
**"The agent keeps going; the rails keep it honest."** Every scene uses one motif: a green rail,
a station, a gate that is open (green) or closed (red).

## Decisions
- **Scenes are SVG built once, then `seek(t)` sets attributes.** Pure function of t, no wall clock,
  seeded PRNG + value noise for the chaos. Rejected: CSS animations / WAAPI (not frame-exact when
  stepped from Playwright), canvas (text is softer and harder to test).
- **One shared lib (`src/lib/motion.js`) with brand components:** rail, gate, panel, status bar,
  caret, spinner. `build.mjs` inlines lib + scene + the shapes of `assets/logo.svg` into
  self-contained `scenes/<name>.html`. The logo is copied, never redrawn.
- **Seamless loops by construction:** a second instance frozen at t=0 fades in over the last
  0.18–0.3 s, so the frame at t=dur is pixel-identical to t=0 (tested). `bypass-blocked` ends red and
  starts green, so it dips through the background instead of blending red into green (a blend would
  invent a mustard hue).
- **Colour changes are hard switches** (gate, test flips at the squash midpoint). Crossfading red over
  green produced off-brand intermediate hues.
- **Motion blur:** 180 Hz sub-frames centred on each 60 fps frame time, `tmix=3` → lossless ffv1
  master. Looping scenes wrap negative sub-frame time, so the blur is also correct across the seam.
  GIF = every second master frame (30 fps).
- **The showreel is an edit, not new footage:** it re-times the six scene modules with piecewise time
  maps so that cuts (1.0 / 4.0 / 9.0 / 13.0 s) and gate slams land on beats (four slams cascade on
  5.0 / 5.5 / 6.0 / 6.5 s in a 2×2 grid). Sound follows picture: each scene exports its `events`,
  the reel maps them to reel time, and the synth places slams, flips and chimes on them.
- **No invented copy.** Test results are shown as coloured blocks rather than invented test names;
  the agent's work is shown as abstract bars rather than fake code.
- **Fonts:** system mono + `system-ui`, no web fonts (the brief allows Inter only base64-embedded,
  and the system stack keeps the pages network-free).

## Where it lives
Since 2026-11-11 only the rendered GIFs live in this repo; the sources moved to the maintainer's private archive
repository (the history before the public release), see History.
- `assets/motion/out/<scene>.gif`: the six README animations (this repo)
- `demo/slickrails-demo.gif`, `assets/header.png`, `assets/slickrails-trailer.{mp4,jpg}`: the other README media (this repo)
- Archive only: `assets/motion/src/lib/motion.js` (easing, PRNG/noise, components), `src/scenes/*.js` (one module
  per scene), `src/reel/` (showreel + soundtrack), `build.mjs` → `scenes/*.html`, `render.mjs` (Playwright + ffmpeg,
  writes `out/` and `out/REPORT.md`), `tests/scenes.test.mjs`, the poster PNGs; `demo/demo.tape` +
  `demo/setup-demo-repo.sh` (VHS); `assets/header.html` + `render-header.sh`
- Embedded in `README.md` and `README.de.md` (hero, the commit/push pair, parity, bypass, gate)
- `bootstrap.sh` clones without `assets/` and `demo/` (sparse checkout): installed kits carry no media

## How to test it
In the archive repository:
1. `cd assets/motion && npm ci && npx playwright install chromium-headless-shell`
2. `npm run build && npm test`: render state is a pure function of t (checked every 0.25 s after
   scrubbing elsewhere), loop seam pixel-identical, only palette colours, all text ≥ 22 px, every
   brief string fully on screen, no wall-clock/unseeded randomness in sources, the palette check
   catches an injected off-brand colour, logo shapes verbatim.
3. `node render.mjs` (needs `ffmpeg`/`ffprobe` on PATH), then read `out/REPORT.md` (ffprobe numbers,
   GIF budget, seam, contrast) and look at `out/contact/*.png` (every 0.5 s).
4. Preview a scene live: open `scenes/<name>.html` in a browser; `?t=2.4` freezes at a time.

## Limits & open items
- Not verified: GitHub's own GIF rendering (camo proxy, mobile apps).
- Glyph widths depend on the render host's system fonts; renders were made on macOS (SF Mono / SF Pro).
- GIF cannot honor `prefers-reduced-motion`; the poster PNGs exist for pages that can switch.
- These tests need Playwright + Chromium, so they are not wired into `tests/run.sh` (POSIX sh, no deps).

## History
- 2026-10-21: created
- 2026-10-21: `secret-blocked` strike-through length was measured per frame with
  `getComputedTextLength()` while its row was scaled → sub-pixel drift depending on what was shown
  before (caught by the purity test) → measure once at build time.
- 2026-10-21: hero GIF was 2.56 MB (budget 1.5): the chaos phase alone cost 1.96 MB because every
  frame redrew every line → chaos now moves in 12 fps stop-motion steps, offset by half a step so a
  step boundary never falls inside a motion-blur window; order stays fluid at 30 fps (deliberate
  contrast) → 1.32 MB at full 128 colours / 30 fps.
- 2026-10-21: showreel frames on cuts blended both shots (blur sub-frames straddled the cut) → scenes
  declare `cuts`, the renderer clamps sub-frames to their frame's side. The reel's chaos shot was
  re-timed 1.6× and its stop-motion steps ghosted → it now plays at 1.0× from 0.6 s.
- 2026-10-21: REPORT showed GIFs at 33.33 fps: ffprobe reports the 3 cs GIF timebase; real delays
  are 3/3/4 cs = 30 fps → the report computes frames ÷ duration.
- 2026-10-21: merged into the 1.3.0 release: GIFs embedded in both READMEs, the static hero
  `assets/chaos-to-rails.svg` removed; videos and contact sheets kept out of git (the showreel files and the
  original commit 602461b are archived outside the repo).
- 2026-11-11: an outside review of 1.4.0 found the media weighing down every install ("inspectable shell you can
  read in an afternoon", but `bootstrap.sh` cloned ~6 MB of GIFs, video and a Node pipeline with its own
  `package.json`) → the sources moved to the private archive repo, the rendered media stay for the README, and
  `bootstrap.sh` leaves `assets/` and `demo/` out of the clone. Rejected: a separate public media repo (one more
  repo to keep in sync for files only the README uses), taking the media to the private archive (the README could
  not show them). First CI run: on Windows the media were still cloned — Git Bash rewrote the sparse patterns
  (`'/*'`, `'!/assets/'`) into Windows paths → the patterns are written into `.git/info/sparse-checkout` instead.
