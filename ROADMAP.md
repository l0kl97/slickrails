# Roadmap

What it takes for slickrails to be the default guardrails standard for
AI-built codebases. Ordered by leverage, not by ease.

Items marked *(release)* are code-complete in this repo and only wait
on the public GitHub release (publishing, rendering, listing). The
launch steps themselves live in [LAUNCH.md](LAUNCH.md).

## v1.2 — Distribution & first impression

- [x] **One-line install:** `bootstrap.sh` clones/updates
      `~/.slickrails` and links the `slickrails` command onto PATH
      (`init`, `doctor`, `version`, `upgrade`, `dossier`, `uninstall`)
- [x] **`npx slickrails` wrapper** — package ready in `npm/` *(release: `npm publish`)*
- [x] **Homebrew formula** — template in `packaging/homebrew/` *(release: fill sha256, push tap)*
- [x] **Demo GIF** — VHS tape + demo-repo script in `demo/` *(release: `brew install vhs`, record, embed)*
- [x] **Guides** — `docs/guides/` (team adoption, stacks); a full docs
      site (Astro Starlight) stays open *(release)*
- [ ] **Claude Code plugin distribution:** ship the kit as an
      installable Claude Code plugin (the mattpocock/skills model) —
      a third channel next to the curl installer and npx
- [x] **Reusable GitHub Actions** — composite actions in `actions/`
      (`pr-size`, `claude-review`) *(release: Marketplace listing)*

## v1.3 — Trust: measured, not claimed

- [x] **Seeded-bug benchmark** (`tests/benchmark/`): faults and clean
      controls against hooks, installer, Stop gate and review wrapper
- [x] **Codex CLI parity:** same Stop gate and Bash guard, measured on
      the real CLIs (`docs/guides/agent-parity.md`)
- [x] **Local gate** (`slickrails gate`): the pushed commit is checked
      in a disposable worktree before it leaves the machine
- [x] **Honest installer:** no silent `core.hooksPath` switch, merged
      agent settings, a first-commit command that passes
- [ ] **Run it on real hosts:** Linux, macOS and Windows (Git Bash) are
      green in GitHub CI; `slickrails protect` and the security workflow
      ran on the kit's own repo (1.5.0). Still open: the stack templates'
      setup actions and audit steps, the review workflows on GitHub,
      Codex's interactive trust flow
- [ ] **L3: Codex as a reviewer** in the benchmark (needs a review backend)

## v1.3 — Breadth

- [x] **Stacks:** Go, Rust, Ruby, JVM adapters (detection + checks + CI
      templates) — PHP, Elixir, Deno are good first issues
- [x] **Package-manager detection:** npm / pnpm / yarn / bun for local
      checks and a PM-aware `ci-node.yml`
- [ ] **Monorepo support:** works today via root commands
      (`pnpm -r test`); path-filtered per-package CI still open
- [x] **Windows** (Git Bash) — full suite green in CI and blocking
      since 2026-10-22
- [ ] **gitleaks scaffold:** `.gitleaks.toml` + `.gitleaksignore`
      generated on install
- [x] **`slickrails status`:** one screen per repo (health, checks,
      reviewer, open rules, dossiers; `--github` for CI and protection)
- [ ] **Across repos:** the same view over every repo in a folder
      (parses each `.slickrails/STATUS.md`)
- [x] **One set of checks:** every stack's CI runs the commands from
      `.slickrails/config.sh`, like the hooks (1.6.0)
- [x] **Update path:** `slickrails init` again replaces the files
      nobody edited (`.slickrails/manifest`, 1.6.0)
- [x] **Fresh clones:** an agent's first tool call switches the git
      hooks on (1.6.0); for humans it stays one `git config` line
- [ ] **Audit for yarn, bun and JVM** in `security.yml` (npm, pnpm,
      pip, Go, Rust and Ruby are covered)
- [ ] **Package check in CI:** new lockfile entries in a PR get the same
      age check as an agent's install
- [ ] **More registries in the package check:** cargo, go, gem, composer

## v2 — The AI-native gate

- [x] **Local pre-push AI review:** `.slickrails/ai-review.sh` runs
      `claude -p` over the outgoing diff — no daemon, opt-in via
      `CHECK_PREPUSH_REVIEW="1"`, degrades gracefully without the CLI
- [x] **Dossier autopilot (manual trigger):** `slickrails dossier`
      drafts `docs/features/<slug>.md` from a diff, never inventing
      what it can't know; automatic detection on merge still open
- [x] **Adaptive review:** learnings file + review profiles
      (quiet/chill/assertive) honored by every AI review; walkthrough +
      risk-ranked findings on PRs
- [x] **A review that starts where the last one ended:** a failed
      review's findings go to the next one; after a rebase the base is
      the default branch; lockfiles are left out; a cut diff is never
      reported as a pass (1.6.0)
- [ ] **Findings with identity:** addressed / still open / new per
      round, and a finding a human dismissed (with the reason) stays
      dismissed — the idea is pr-agent's
- [ ] **Profiles:** `--profile builder-org` (review in CI with
      `REVIEW_ON_ERROR=block`, code owners) and `--profile senior`
      (fewer process rules), from the outside review of 1.4.0
- [ ] **Dossier check:** the paths a dossier names still exist; a
      feature changed without its dossier is pointed out
- [ ] **Import boundaries in CI** per stack (dependency-cruiser and
      its equivalents)
- [ ] **Agent coverage matrix:** rules block ships in CLAUDE.md +
      AGENTS.md; session-level enforcement (Stop gate + Bash guard) is
      done and measured for Claude Code and Codex CLI
      (`docs/guides/agent-parity.md`); still open: Cursor, Gemini CLI,
      and Codex's real trust flow in an interactive session
- [ ] **Rule packs / translations:** `templates/de/` generalizes —
      fr, es, pt, ja

## Launch

The playbook — release checklist, Show HN and Reddit drafts, ten
good-first-issues, the 30-day case study — lives in
[LAUNCH.md](LAUNCH.md).
