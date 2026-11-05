# slickrails motion

**"The agent keeps going; the rails keep it honest."**
Six README animations and one 15 s showreel. All share one motif: a green rail, a station, and a gate
that is either open (green) or closed (red).

Every frame is a pure function of time. Each scene is an SVG page driven only by `window.seek(t)`,
and Playwright steps through it while ffmpeg encodes the frames.

| scene | length | what happens |
|---|---|---|
| `chaos-to-rails` | 6 s | tangled lines snap onto three rails; a dot runs the switch route past hooks → tests → review; logo locks up |
| `secret-blocked` | 5 s | masked `STRIPE_KEY` is staged, pre-commit blocks, gate drops; line removed, commit created |
| `red-push-blocked` | 5 s | pre-push runs tests, 2 fail, push blocked; tests flip green, pushed |
| `agent-cant-finish-red` | 7 s | Claude Code and Codex CLI side by side: "Done!" → Stop hook → fix → may end |
| `local-gate` | 6 s | red commit bounces off the gate, green one reaches origin |
| `bypass-blocked` | 4 s | `--no-verify` blocked by bash-guard; hooks are a hint, CI is the boundary |
| `showreel` | 15 s | 1920×1080, 120 BPM, soundtrack. An edit of the six scenes, cut on the beat |

## Render

```sh
cd assets/motion
npm ci && npx playwright install chromium-headless-shell   # once
npm run build        # src/ → scenes/*.html (self-contained, no network)
npm test             # determinism, loop seams, palette, type size, exact copy
node render.mjs      # → out/  (needs ffmpeg + ffprobe on PATH)
```

`node render.mjs secret-blocked` renders a single scene, `--no-reel` skips the showreel, and `--reel-only` renders only the showreel.
To preview, open `scenes/<name>.html` in a browser; it plays in real time, and `?t=2.4` freezes it at 2.4 s.

Outputs per scene in `out/`: `<name>.gif` (30 fps, ≤ 128 colours), `<name>.mp4`, `<name>.webm`,
`<name>-poster.png` (the resolved state, for reduced motion), plus `contact/<name>.png` (one frame every
0.5 s). The showreel also gets `showreel.wav`. `out/REPORT.md` holds the ffprobe numbers, the GIF
budget, the loop-seam check and contrast ratios.

## README snippets

```html
<p align="center"><img src="assets/motion/out/chaos-to-rails.gif" alt="Tangled grey lines snap onto three green rails; a dot passes the hooks, tests and review stations and the slickrails logo locks up." width="900"></p>
```

| scene | goes next to | alt text |
|---|---|---|
| `secret-blocked` | What you get | A masked STRIPE_KEY line is staged, the pre-commit hook blocks the commit and drops a red gate; the line is removed and the commit goes through on green. |
| `red-push-blocked` | What you get | git push runs the tests in a pre-push hook, two fail and a red gate blocks the push; the tests are fixed and the push passes the green gate. |
| `agent-cant-finish-red` | The part nothing else does | Claude Code and Codex CLI side by side: each claims it is done, a Stop hook blocks the session because tests are red, the agent fixes them and may end once checks are green. |
| `local-gate` | gate | A red commit travels from your push to the gate and bounces back, origin never sees it; a green commit passes the gate and reaches origin. |
| `bypass-blocked` | gate | git commit --no-verify is blocked by bash-guard and a red gate drops; caption: hooks are a hint, CI and branch protection are the boundary. |

A README `<img>` can't follow `prefers-reduced-motion`. Pages that can use `<picture>` or CSS should
show `out/<name>-poster.png` instead.

## How it's built

- `src/lib/motion.js`: the brand easing `cubic-bezier(.2,.8,.2,1)`, a seeded PRNG with value noise, and
  the components (rail, gate, panel, status bar, caret, spinner).
- `src/scenes/*.js`: one module per scene. Each builds its SVG once and exports `seek(t)` plus sound `events`.
- **Loops:** a second instance frozen at t=0 fades in at the end, so the frame at t=dur equals the frame at t=0.
- **Motion blur:** 3 sub-frames at 180 Hz, centred on each 60 fps frame, are merged with `tmix`. Looping
  scenes wrap time, so the blur stays correct across the seam too.
- **Showreel:** piecewise time maps re-time the scenes so that cuts and gate slams land on beats. The
  soundtrack (`src/reel/audio.js`, `OfflineAudioContext`) is driven by the same scene events.

Design decisions and their history: [`docs/features/readme-motion.md`](../../docs/features/readme-motion.md).
