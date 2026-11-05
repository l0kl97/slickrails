# Codex parity: the same Stop gate and Bash guard for the Codex CLI

**Status:** active · **As of:** 2026-10-21 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
Improvement plan, point 5, after the maintainer's decision "Parität = gleich stark in beiden": a session of the Codex CLI should be
held to the same standard as a Claude Code session — it may only end with green checks, and it may not bypass the git
hooks. Until now the installer only wired Claude Code (`.claude/settings.json`); for Codex there was the rules block in
`AGENTS.md` and nothing that enforces it. "Equally strong" is defined narrowly: the same deterministic gate, the same
failure handling, the same install proof — what a model catches in review is reported per agent, not promised.

## What was measured first (real Codex CLI 0.163.0-alpha.10.2, logged in, throwaway repos)
- Codex hooks use the same shape as Claude Code's (`hooks.json`, `matcher: "Bash"`, `tool_input.command`, exit 2 blocks). No project-dir variable exists, so the commands resolve the repo root with `git rev-parse --show-toplevel`.
- Exit 2 from a Stop hook is reported as `hook: Stop Blocked`; the model continues with the hook's stderr as its prompt.
- A timed-out Stop hook and a crashing one are `hook: Stop Failed` and the session ends: in the runs measured here **Codex is fail-open on timeout and crash, like Claude Code**, which is why the gate has its own deadline and treats a crash inside the script as red. (One machine, one version, `codex exec`.)
- Where the project's hooks apply (measured): a session started in a subdirectory of the project is covered (the commands resolve the repo root); a session started inside a **nested git repository** of the project gets none of the outer project's hooks — no hook ran at all, silently. Nothing in the kit can close that from the inside; start sessions at the project root.
- Observed on the side: when the gate blocked, the model rewrote the hook script so that it would pass. The gate (like the Bash guard) is a hint against honest mistakes, not a wall against an agent that edits its own guard — CI and branch protection are the boundary.

## Decisions
- `templates/codex-hooks.json` → `.codex/hooks.json`: the same two hooks as for Claude Code (Stop → `session-check.sh`, `PreToolUse` on `Bash` → `bash-guard.sh`); the scripts did not need a Codex variant. The Stop gate prints nothing on stdout (Codex wants JSON or nothing there) and answers with exit 2 + stderr.
- `install.sh --agent claude|codex|both`, default **both**. Detecting Codex by `PATH` is unreliable (on macOS it lives inside the ChatGPT app bundle — it was not on the `PATH` of the machine this was built on), and the file is small. The merge logic is shared with Claude's settings (jq, else node; foreign hooks and keys stay; idempotent; never rewrites invalid JSON).
- Trust: Codex skips new project hooks until they are reviewed (`/hooks`) and loads them only if the project's `.codex/` layer is trusted. The installer says so and never tries to trust on the user's behalf. `doctor` reports "configured" and states that trust is not verified; a missing `.codex/hooks.json` is only a warning (a Claude-only install is legitimate).
- Rejected: a second implementation of the gate for Codex; Python wrappers (plan A); an automatic hook-trust step; making Codex review the default reviewer (cross-review stays an option, no Codex review backend was built, layer L3 of the benchmark still reports BLOCKED).

## Where it lives
- `templates/codex-hooks.json`, `install.sh` (`--agent`, `install_hooks_file`, doctor), this repo's own `.codex/hooks.json` (dogfood, checked against the template by a test)
- `tests/run.sh` — block "Codex parity": template shape, `--agent` variants, merge/idempotence, doctor, and the hook contract with Codex-shaped input (exit codes, stdout empty, reason on stderr)
- `tests/benchmark/host/codex-gate.sh` — the real-host check (below)
- `docs/guides/agent-parity.md` — the user-facing matrix

## How to test it
1. `sh tests/run.sh` — expect 200+ passed (the "codex" and "doctor" groups cover the parity work).
2. `env BENCH_AI=1 sh tests/benchmark/host/codex-gate.sh` — runs five small prompts against the real Codex CLI and checks, each with a control (the checks read Codex's own hook report lines, so a changed output format of an alpha build breaks them, and finding 4b relies on the model running the command it is asked to run): (1) red checks → `Stop Blocked`; (2) a gate killed by the hook timeout → `Stop Failed` (the fail-open control); (3) the same slow check with the gate's own deadline → `Stop Blocked`; (4a) an ordinary `git commit` passes the PreToolUse guard; (4b) `git commit --no-verify` → `PreToolUse Blocked`. Last run: all confirmed.

## Limits & open items
- Waiting for Codex acceptance: the host check was run by Claude Code on the owner's machine with `--dangerously-bypass-hook-trust`; the real trust flow (`/hooks` review, project layer trust) and a long interactive session are unverified. Codex is not on `PATH` here; the script finds the app-bundle binary.
- The Bash guard judges Codex runs by Codex's own hook report, not by commits: the `workspace-write` sandbox forbids writes to `.git`, so a commit cannot be counted there.
- Codex hook timeouts for events other than the ones measured, `codex exec` versus the interactive TUI, and Linux/Windows Codex builds are unverified.
- The Stop gate's `stop_hook_active` handling was not needed for Codex (the gate keeps its own counter); in the single measured run Codex continued once after a block.
- `.codex/config.toml` inline hooks are not detected by `doctor`.

## History
- 2026-10-21: created (plan point 5, parity = equally strong in both). Host check against Codex CLI 0.163.0-alpha.10.2: all findings confirmed.
- 2026-10-21: self-review of 99819a9 (fresh reviewer). Finding: the hook commands exit 127 (= "Stop Failed", fail-open) when `git rev-parse --show-toplevel` does not point at the project (nested repo, submodule, no repo). Measured on the real Codex instead of guessed: a subdirectory of the project is covered; inside a nested git repository Codex runs none of the outer project's hooks at all, so the 127 path never occurs there but the session is silently uncovered → documented as a limit, no change to the commands. Also fixed: the commands of both templates are now executed by tests (repo root, subdirectory, a repo path with spaces; Mutants such as a typo in a script name are caught directly), "six prompts" was five, the wording "exactly like Claude Code" was too strong (one machine, one version, `codex exec`), `--agent=codex` is accepted, help text and README.de mention the Codex part.
