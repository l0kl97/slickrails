# Readable post URLs (slugify)

**Status:** active · **As of:** 2026-11-28 · **Built by:** the blog's developer with Claude Code

## The ask (plain language)
"Our post links look like `/posts/8f3a91`. I want `/posts/ueber-aepfel-birnen` instead, made from the title.
German titles too, so ä becomes ae, not a. And please no links that end in the middle of a word."

## Decisions
- **Umlauts are spelled out** (ä → ae, ß → ss), other accents are dropped (é → e). That is how German readers type
  a URL. Rejected: dropping the dots (ä → a), which turns "Bären" into "baren".
- **At most 60 characters, cut at a dash.** Long enough for a real title, short enough to share. Rejected: a hash
  suffix for long titles (unreadable again).
- **No silent fallback.** A title without letters or digits ("!!!") throws a `RangeError`, anything but a string a
  `TypeError`. The caller decides what to show; an empty slug would have produced the link `/posts/`.
- No dependency (`slugify` packages exist): ten lines of our own are easier to review than a new package.

## Where it lives
- `src/slugify.js`: `slugify(title)` and `MAX_LENGTH`
- `test/slugify.test.js`: the cases below, including the refusals

## How to test it
1. `pnpm test` (runs `node --test`; the pre-push hook runs the same).
2. By hand: `node -e 'import("./src/slugify.js").then(m => console.log(m.slugify("Über Äpfel & Birnen!")))'`
   prints `ueber-aepfel-birnen`.

## Limits & open items
- Two posts with the same title get the same slug; making it unique is the caller's job (not built yet).
- Only German special letters are spelled out; other scripts (Greek, Cyrillic) end up empty and are refused.

## History
- 2026-11-28: created.
- 2026-11-28: long titles ended mid-word ("…-and-what-we-lea") → `slice(0, 60)` cut at the character limit → cut at
  the last dash before it; repro test "long titles are cut at a word boundary" first, then the fix.
