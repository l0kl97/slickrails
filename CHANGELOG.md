# Changelog

All notable changes to slickrails are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Rulebook chapters "After the merge: the deploy layer" (feature flags, preview environments, staged rollout,
  rollback, error monitoring) and "Access: agents never hold production keys", English and German — recommendations,
  nothing is installed
- Setup check in CI: the `ci` job of every stack template runs `.slickrails/setup-check.sh` and fails when the git
  hooks, the checks in `config.sh` or the agents' session hooks are missing or empty (a broken setup was silent:
  every hook passed). Repository variable `SLICKRAILS_SETUP_CHECK=warn|off` is the way out
- `.github/CODEOWNERS` template for sensitive paths (auth, payments, migrations, infrastructure, the guardrails),
  placed fully commented out; enforced with `CODEOWNER_REVIEWS=1 slickrails protect`
- `CODEOWNER_REVIEWS=1 slickrails protect`: every PR needs one approving review, from a code owner where it touches
  their paths; a new push dismisses the approval. Needs a second person (nobody approves their own PR)

### Changed
- `slickrails protect` requires pull requests on main (0 approving reviews, so a solo developer merges their own PR;
  `REQUIRE_PR=0` opts out). Before, a commit whose checks had passed could still be pushed straight to main
- `slickrails protect` takes the required check names from the branch's last check runs: a matrix job reports
  `ci (ubuntu-latest)` and never `ci`, which blocked every merge. `REQUIRED_CHECKS="a; b"` names them directly (`;`, since a matrix name can contain a comma)
- `bootstrap.sh` clones without the README media (`assets/`, `demo/`, about 6 MB) by sparse checkout. The sources of the README media (motion pipeline with its own `package.json`, VHS
  tape, header renderer) left this repo; the rendered GIFs stay for the README

### Fixed
- `bootstrap.sh` builds a fresh clone next to the install dir and moves it into place when the checkout is complete;
  an install with a `.git` but no files (interrupted checkout) is checked out on the next run
- `bootstrap.sh` creates a `SLICKRAILS_BIN` that does not exist yet instead of linking into `~/.local/bin`

## [1.4.0] — 2026-11-05

First public release. The history before it lives in a private repository; the feature dossiers in
`docs/features/` keep the why of every change, and older entries below cite commits from that history.

### Added
- A 20-second trailer at the top of the README (`assets/slickrails-trailer.mp4`)
- The Bash guard blocks commands that destroy work or data (`git reset --hard`, `git clean -f`, `git push --force`, any forced push onto main/master, `git checkout/restore .`, `rm -r` on `/ ~ $HOME . .. * .git`, `migrate:fresh`/`db:drop`/`prisma migrate reset`/…, `DROP`/`TRUNCATE` through a database client); the human runs them or sets `SLICKRAILS_ALLOW_DESTRUCTIVE=1`
- Write protection for the guardrail files (`.slickrails/*.sh`, `.githooks/`, `.claude/settings(.local).json`, `.codex/hooks.json`): shell writes are blocked for both agents, Claude Code's edit tools too (the guard's matcher is now `Bash|Edit|Write|MultiEdit|NotebookEdit`; re-running the installer widens an existing Bash-only entry)
- Package check (`.slickrails/dep-check.sh`, called by the Bash guard): an agent's `npm/pnpm/yarn/bun add|install <name>`, `pip install`, `uv add`, `poetry add` is blocked when the package was first published less than 30 days ago (npm: with fewer than 1000 downloads last week); a name that is not on npm/PyPI is pointed out, private registries and workspace packages are left alone; fails open without network; `SLICKRAILS_ALLOW_NEW_DEPS=1`
- `slickrails doctor` probes the installed hooks instead of only finding them: the Bash guard must block a `--no-verify` probe and let `git status` through, pre-commit must block a staged test key (run in a scratch repo)
- Local AI review with the user's own CLI: `REVIEW_CLI` = auto (claude, else codex) | claude | codex; Codex runs `codex exec` read-only and without a stored session (found on PATH or in the ChatGPT app on macOS). No API key, no GitHub App
- Setup follows what is installed: when the installer writes `config.sh` it turns the pre-push review on with the claude or codex CLI it finds (`--agent codex` prefers codex), says so when it finds neither; `--review auto|claude|codex|off` or `SLICKRAILS_REVIEW`. `slickrails doctor` points out an off review when a reviewer CLI is there

- `slickrails status [--github]`: one screen on where a repo stands — health (doctor's checks, summed up, problems named), the configured checks, the reviewer, the open rules from `.slickrails/STATUS.md`, the dossiers; with `--github` the last CI run of the branch and branch protection on main (each `gh` call bounded)

- `slickrails-status`, a Claude Code mod (`mods/`, offered through `.claude-plugin/marketplace.json`): one status line — guard, git hooks, local review, last session checks, open rules — refreshed after every turn, and `/slickrails` for the full status; `slickrails init --status-mod` offers it to the whole team through `.claude/settings.json`
- `slickrails status --porcelain` (key=value, no doctor run, no network) for the mod; the Stop gate records its last result (`.git/slickrails-last-gate`), shown as "Gate" in `slickrails status`
- `slickrails github-review` adds the server-side PR review later (workflow plus the App and secret steps)

### Changed
- The Node CI template caches the package manager's downloads (npm, pnpm, yarn, bun), keyed by the lockfile: runs on main fill the cache, PRs read it (the other stack templates cached already)
- The local AI review before push is the default review; the GitHub PR review (`claude-review.yml`) is opt-in (`--github-review` or `slickrails github-review`), so a fresh install needs no App, no secret and no Actions minutes for it. Rule 6 is "AI review before merge" and counts as in place when the local review runs
- The kit's own CI runs a draft PR on Linux only and the full Linux/macOS/Windows matrix when the PR is ready for review and on main (macOS minutes count 10x in a private repo on the free plan); the new scripts are shellchecked too
- Bundled install: the rulebook and the status live in `.slickrails/` (`SLICKRAILS.md`, `STATUS.md`); an older install's root files are moved there with their edits. The branch-protection script is no longer copied into the repo: `slickrails protect` runs the kit's (an unchanged old copy is removed)
- The installer is quiet: a count of added files (`--verbose` lists them) and only the next steps that apply to this repo

### Fixed
- Local AI review: the claude reviewer ran with every tool and once left a file it had written staged in the repo; it now reviews with Read, Grep and Glob only (codex already ran in its read-only sandbox)
- Local AI review: a diff git cannot build (no merge base, a shallow clone) counted as an empty diff and the push passed silently; it is now an ERROR (found by the real claude review of the script itself)
- pre-commit: with gitleaks installed, a low-entropy key (`sk-…`) slipped through, because the hook's own patterns ran only without gitleaks; they now always run

## [1.3.0] — 2026-10-22

### Added
- README animations (`assets/motion/`): six deterministic HTML scenes rendered to GIF with Playwright and ffmpeg (hero, secret blocked, red push blocked, agent cannot finish red, local gate, bypass blocked); the sources, a render report with sizes and contrast checks, and a test of the scenes are in the repo, the old static hero SVG is gone
- The PR review workflow (`claude-review.yml`) and the composite action `actions/claude-review` accept a Claude subscription token (`CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token`) as an alternative to `ANTHROPIC_API_KEY`; the local AI review never needed a key. `security-review-ai.yml` still needs an API key. Not yet run on real GitHub
- `post-merge` hook: close-the-loop reminders after every merge — code changed without a feature dossier or changelog entry gets a loud, non-blocking nudge (inspired by CodeRabbit's post-merge actions, local-first)
- Performance as an explicit review category in all AI reviews (excessive/repeated I/O, N+1 queries — AI-generated code shows ~8x more excessive I/O than human code, per CodeRabbit's AI-vs-human report)
- Validator memory duty in the agent rules block: every caught failure gets appended to `.slickrails/review-learnings.md`
- Opt-in deep security tier: `templates/workflows/security-review-ai.yml` wraps Anthropic's official security-review action (trusted PRs only — not hardened against prompt injection)
- `/security-review` duty for security-sensitive changes and a `docs/CONTEXT.md` vocabulary habit in the agent docs; Claude Code plugin distribution added to the roadmap
- Local gate, the core idea of kunchenguid/no-mistakes without daemon, TUI or agent pipeline (opt-in): `slickrails gate init|status|remove` adds a `gate` remote; `git push gate <branch>` checks the PUSHED commit in a disposable worktree with the project's own checks (setup, typecheck, tests, optional AI review) and forwards to the real remote only on green
- Seeded-bug benchmark (`tests/benchmark/`): seeded faults and clean controls against the template hooks, installer, Stop gate and review wrapper; real-review (L2) and host checks behind `BENCH_AI=1`; a Codex layer that reports BLOCKED until a Codex backend exists
- Codex CLI parity: `.codex/hooks.json` wires the same Stop gate and Bash guard for Codex (`install.sh --agent claude|codex|both`, default both; `slickrails doctor` reports Codex hooks and says that hook trust is not verified); `docs/guides/agent-parity.md`; a real-host check (`tests/benchmark/host/codex-gate.sh`) confirmed against Codex CLI 0.163.0-alpha.10.2
- `.slickrails/bash-guard.sh` (`PreToolUse` on Bash for Claude Code and Codex): blocks `--no-verify`, `git commit -n`, `SLICKRAILS_SKIP=` and switching hooks off via `core.hooksPath`; the way out belongs to the human (`SLICKRAILS_ALLOW_BYPASS=1`)
- `slickrails doctor` also checks the repo: `core.hooksPath` in this clone, executable hooks, an empty `config.sh`, Stop hook and Bash guard configured
- `REVIEW_ON_ERROR` (warn|block) and `REVIEW_TIMEOUT` for the local AI review; `ENFORCE_ADMINS` for the branch-protection script, which now reads the settings back from GitHub

### Changed
- pre-push checks what is pushed: the pushed commit must be HEAD and the working tree clean (tags on older commits only get a note)
- The local AI review takes the verdict from a JSON schema (with jq) or demands exactly `VERDICT: PASS|FAIL`; anything else is an ERROR line, never a PASS (exit 3 = not reviewed; pre-push says so instead of "All green")
- The Stop gate no longer fails open: it also checks committed-but-unpushed work, has its own deadline, treats a crash as red, caches green states and allows 3 blocks per unchanged state
- The installer no longer switches an existing `core.hooksPath` (it says the git hooks are NOT active and records it in `SLICKRAILS-STATUS.md`) and merges the slickrails hooks into an existing `.claude/settings.json` (jq or node)
- The opt-in security workflow pins the action to a commit SHA, scans every commit of a PR and skips fork PRs
- Review walkthroughs are grouped by behavior/flow instead of by file ("code is no longer the bottleneck — understanding is")
- CI: shellcheck excludes deliberate patterns; gitleaks-action bumped to v3

### Fixed
- The setup instructions for the PR review now name the Claude GitHub App (and `/install-github-app`); without it the review job fails no matter which secret is set
- Windows (Git Bash): the full suite is green and the Windows CI job blocks merges. The Stop gate and the local gate stop hung checks with Git Bash's `ps` (no `-A`/`-o`); `bootstrap.sh` installs a small launcher where `ln -s` copies instead of linking (the copied command could not find the kit); `\r` from jq's CRLF output no longer turns a review PASS into an ERROR or breaks the branch-protection read-back
- The Stop gate's deadline counts from the hook's start, like the host's timeout; time spent on git status and the state key used to come on top. A deadline used up before the checks could start does not start them, and a stop signal that gets lost (Git Bash) is re-sent for a bounded time instead of waiting for the checks (also in the local gate)
- Security workflow: the gitleaks job may read pull requests; without it the scan failed with 403 on every PR
- Local gate: with the AI review opted in, a push could pass unreviewed and silently when the real remote's HEAD pointed at a missing branch (a bare remote made with `master` as default that only received `main`). The review base now also falls back to the remote's `main`/`master`, and the review's own messages (e.g. "skipping") appear in the push output
- CI: shellcheck clean again; the gate, its hook and the Bash guard are now part of the shellcheck run; the doctor test no longer inherits `CI=true` from the runner. Linux and macOS green on GitHub; the experimental Windows job is not (see Honest limits in the README)
- The pre-push hook handed git's hook environment (`GIT_DIR` and friends) to the project's checks. From a linked worktree, a test suite that creates its own git repositories wrote into the real one instead (its config, branches, identity, even pushes to the real remote). Checks now run without those variables; the kit's own suite also clears them
- The installer's last "next step" ("commit the changes") produced a commit the commit-msg hook refused (a big first commit needs a body); it now prints a command that passes, and reminds about `core.hooksPath` in other clones and the one-time hook trust of Claude Code / Codex
- A rename onto `.env` (also `.ENV`, or a `.env` below a non-ASCII directory) is blocked by the pre-commit hook
- The branch-protection script no longer claims "main now only accepts PRs"; it reports what GitHub stored
- `slickrails doctor` no longer executes `config.sh`

## [1.2.0] — 2026-08-24

### Added
- `slickrails` CLI (`bin/slickrails`): init, doctor, version, upgrade, dossier, uninstall
- One-line bootstrap installer (`bootstrap.sh`) → `~/.slickrails` + PATH symlink
- npm wrapper package (`npm/`, publish pending) and Homebrew formula template (`packaging/homebrew/`)
- Demo GIF tape + demo-repo script (`demo/`), render pending on `vhs`
- Reusable composite GitHub Actions: `actions/pr-size`, `actions/claude-review`
- Stacks: Go, Rust, Ruby, JVM (detection, local checks, CI templates)
- Node package-manager detection (npm/pnpm/yarn/bun) for local checks and a PM-aware `ci-node.yml`
- Windows (Git Bash) as an experimental CI matrix entry
- Opt-in local pre-push AI review (`.slickrails/ai-review.sh`, `CHECK_PREPUSH_REVIEW="1"`, no daemon)
- `slickrails dossier`: drafts a feature dossier from a diff without inventing unknowns
- Adaptive reviews (CodeRabbit-inspired, local-first): `.slickrails/review-learnings.md` (waive/tighten finding types), `REVIEW_PROFILE` (quiet/chill/assertive), PR reviews open with a walkthrough and risk-ranked findings
- Guides: team adoption, stack matrix (`docs/guides/`)
- `LAUNCH.md`: release checklist, Show HN/Reddit drafts, ten good-first-issue seeds

### Changed
- `install.sh` also installs `.slickrails/ai-review.sh` and writes `CHECK_PREPUSH_REVIEW` into the generated config
- Test suite grown to 25 scenarios (new stacks, PM detection, CLI, bootstrap)

## [1.1.0] — 2026-08-24

### Added
- MIT license, contributing guide, security policy, issue templates
- English as the primary language; German docs preserved (`*.de.md`, `templates/de/`), selectable via `install.sh --lang de`
- Committed test suite (`tests/run.sh`) covering installer and every hook
- CI for the kit itself (shellcheck + test suite)
- `AGENTS.md` support: the session-rules block is written for any coding agent (Claude Code, Codex, Cursor, …), not just Claude
- `install.sh version` command
- `ROADMAP.md`

### Changed
- Kit dogfoods itself: slickrails is installed into its own repository

## [1.0.0] — 2026-08-24

### Added
- The rulebook (`SLICKRAILS.md`, 12 rules) with layered enforcement model
- Git hooks: pre-commit (secrets scan, .env block), commit-msg (body required for large commits), pre-push (typecheck + tests)
- Claude Code Stop hook: sessions cannot claim "done" while checks are red
- GitHub Actions: CI per stack (Node/Python/Swift), Playwright smoke, security scan, AI review, PR size guard, Dependabot
- Feature dossiers (`docs/features/`) for builder organizations: plain-language intent, decisions, test path, bugfix history
- Idempotent installer with stack detection; never overwrites existing files
- Branch protection setup script (gh CLI)
