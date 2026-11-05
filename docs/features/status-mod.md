# slickrails-status: the status line in Claude Code

**Status:** active · **As of:** 2026-10-30 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
The maintainer: "let's make it so there is a small mod terminal where you see what the slickrails status is … I trust you,
optimise it as far as it makes sense. Remember it is not only about me, I want to spread this."
In the same message: the local review becomes the default and the GitHub review something you set up if you want it.

## Decisions
- **A status line, not a pane.** One line next to the prompt costs no screen width and is always there:
  `slickrails ✓ guard · review claude · checks ✓ · 6 rules open`. `/slickrails` prints the whole `slickrails status`.
- **The kit decides, the mod shows.** The mod runs `slickrails status --porcelain` (key=value lines: hooks, guard,
  review, last gate result, rules, dossiers) and formats them. No logic is duplicated in TypeScript; the porcelain
  output skips the doctor run and the network, so it is cheap enough after every turn (refreshed at most every 15 s).
- **"Checks ✓/✗" is the Stop gate's last real result**, written to `.git/slickrails-last-gate` (`green|red <epoch>`)
  each time it ran the checks; a clean tree that needed no check leaves the last result as it was.
- **Fail quiet:** no slickrails CLI or not a slickrails repo → the line is empty, never wrong.
- **Distribution:** the kit repo is a plugin marketplace (`.claude-plugin/marketplace.json` → `mods/slickrails-status`).
  `slickrails init --status-mod` writes `extraKnownMarketplaces` + `enabledPlugins` into the project's
  `.claude/settings.json`, so Claude Code offers it to everyone who trusts the repo; without the flag the installer
  prints the two `/plugin` commands. `SLICKRAILS_MARKETPLACE` points at a fork.
- The mod finds the CLI on PATH, else at `~/.slickrails/bin/slickrails` (where the one-line installer puts it).

## Where it lives
- `mods/slickrails-status/` — manifest, `hooks/register.ts`, `hooks/register.test.ts`.
- `.claude-plugin/marketplace.json` — the marketplace entry.
- `scripts/status.sh` `--porcelain`; `templates/session-check.sh` writes the gate result; `install.sh --status-mod`.

## How to test it
1. `claude plugin validate mods/slickrails-status` and `claude plugin test mods/slickrails-status` (line format, empty
   outside a repo, session start shows it, `/slickrails` answers).
2. `sh tests/run.sh` — `status --porcelain: …`, `session-check: records a … result`, `installer: --status-mod …`.

## Limits & open items
- Claude Code only (mods are a Claude Code feature); Codex users have `slickrails status` in the terminal.
- No icon yet (the plugin directory wants a square PNG before a catalog listing).
- The marketplace is the kit's GitHub repo: while it is private, only people with access can install the mod.

## History
- 2026-10-30: created
- 2026-11-02: symptom: on a checkout whose Stop gate never ran, `slickrails status` (and `--porcelain`) printed "No such file or directory" → cause: the shell reports a missing `<` file before `2>/dev/null` applies → fix: read the gate file only when it exists (test red first).
