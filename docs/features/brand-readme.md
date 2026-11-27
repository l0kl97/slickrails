# Public face after the brand: header, social preview

**Status:** active · **As of:** 2026-11-27 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
"The GitHub page looks like the approved brand." Recognition at launch (Show HN, Reddit, LinkedIn) and an image that
shows when someone shares the link. The brand: the mark "The Switch" (a switch that moves code onto the safe track),
acid lime `#A8FF06` on graphite `#0B0F0E`; on light ground ink `#14201B` with "ai" in `#4C7A00`. The assets were
already in `assets/`, but the README opened with the trailer and a text heading.

Asked for: the README (en + de) opens with the brand header in a light and a dark variant, the trailer right below;
a 1280×640 social preview in `assets/` (uploading it in the GitHub settings stays with the maintainer); the status
line mod shows the mark if the plugin metadata allows an icon; the README media stay out of the `bootstrap.sh` clone.

## Decisions
- **Spelling:** the running text says "slickrails" as before; the wordmark with the highlighted "ai" appears only in
  the header images (the maintainer's call).
- **`<picture>` with `prefers-color-scheme`:** GitHub picks the variant that fits the reader's theme; the fallback
  `<img>` is the dark header (the brand's home ground) and carries the alt text.
- **The text heading `# slickrails` is gone:** the header shows the name, and a heading between header and trailer
  would break "trailer right below". The alt text names the project for screen readers.
- **The dark header stays the existing `assets/header.png`.** The light one was rendered from the same layout
  (brand canvas: Space Grotesk 700 for the wordmark, IBM Plex Mono for the lines) with the light palette: background
  `#F3F5F4` (the canvas' light lockup), ink mark and wordmark, "ai" and the progress bar in `#4C7A00`. Same size
  (2560×800), so both variants sit in the same place.
- **Social preview:** the header layout scaled up for 1280×640, dark (GitHub shows it on every theme), well under
  GitHub's 1 MB limit.
- **Status line mod: no icon.** The plugin manifest has no icon field and `$.ui.status` takes plain text, so there is
  nothing to put the mark into. The line keeps starting with "slickrails".

## Where it lives
- `README.md`, `README.de.md`: the `<picture>` block at the top, the trailer below it
- `assets/header.png` (dark), `assets/header-light.png` (light), `assets/social-preview.png` (1280×640)
- `assets/logo.svg`, `logo-mono-*.svg`, `favicon.svg`: the mark itself (unchanged)
- `bootstrap.sh` clones without `assets/` and `demo/`, so none of this lands in an installed kit
- `tests/run.sh`, section "the public face": header order, both variants, alt text, every referenced media file
  exists and lies in `assets/` or `demo/`, header sizes match, social preview size and weight, and fixtures that
  prove each check fails on a broken README

## How to test it
1. `sh tests/run.sh` (the "public face" lines, plus "bootstrap: the clone leaves the README media out").
2. Open the repository page on GitHub in a light and a dark theme and at phone width: the header matches the theme,
   the trailer follows directly.
3. After the upload in Settings → General → Social preview: paste the repository link into a chat that unfurls links.

## Limits & open items
- The social preview only takes effect once the maintainer uploads it in the repository settings.
- The render source of the header images is not in this repository (like the motion sources, see `readme-motion.md`).

## History
- 2026-11-27: created (SLI-194)
