# Claude Code and Codex: what slickrails enforces for each

slickrails holds both agents to the same deterministic standard. What a model *catches* in review differs by model
and is measured per agent (`tests/benchmark/`), not promised. This is what is enforced, and how sure we are.

| | Claude Code | Codex CLI |
|---|---|---|
| Rules block (`CLAUDE.md` / `AGENTS.md`) | ✓ instruction only | ✓ instruction only |
| Git hooks (pre-commit, pre-push, commit-msg) | ✓ (agent-independent) | ✓ (agent-independent) |
| Stop gate: the session ends only with green checks | ✓ `.claude/settings.json` | ✓ `.codex/hooks.json` |
| Bash guard: no `--no-verify` / `SLICKRAILS_SKIP=` | ✓ | ✓ |
| Bash guard: no destructive commands, no shell writes to guardrail files | ✓ | ✓ |
| Write protection for guardrail files in the agent's edit tools | ✓ Edit, Write, MultiEdit, NotebookEdit | ✗ `apply_patch` is not hooked (unverified whether Codex can) |
| Real-host check (`tests/benchmark/host/`) | ✓ `claude-stop-timeout.sh`, `claude-bash-guard.sh` | ✓ `codex-gate.sh` |
| Review backend for the local pre-push review | ✓ `claude -p` | ✓ `codex exec` (read-only, `--ephemeral`); checked once against Codex CLI 0.163.0-alpha.11.1 |

Evidence: for Claude Code and Codex the Stop gate and the Bash guard were each confirmed once against the real CLI on the machine this was
built on (see below); "equally strong" means the same deterministic mechanism, not identical evidence depth.

Install: `slickrails init` installs both (`--agent claude` or `--agent codex` for one; a Claude-only user can pass `--agent claude` to skip `.codex/`). `slickrails doctor` shows what is
installed — and says that it does not verify behavior.

## One-time steps per agent
- **Claude Code:** it asks you to trust a project's hooks the first time.
- **Codex:** new project hooks are skipped until you review and trust them (`/hooks` in the CLI), and they load only if the
  project's `.codex/` layer is trusted. slickrails never trusts anything on your behalf.
- **Git hooks:** `core.hooksPath` is local git config and is *not* cloned — run `git config core.hooksPath .githooks` in a fresh clone
  (`slickrails doctor` tells you). If another hook manager owns the path, call `.githooks/*` from it.

## What was measured (and where it is weaker)
- Both agents were **fail-open** in the runs measured here when a Stop hook times out or crashes (session ends silently; one machine,
  one version each). The gate therefore has its own deadline (`SLICKRAILS_STOP_DEADLINE_MS`, default 270 s, below the 300 s hook
  timeout) and treats a crash *inside the script* as red. If the hook command cannot even start, the agent sees a failed hook — that
  is outside the script's reach.
- **Where the hooks apply:** Claude Code resolves the project through `$CLAUDE_PROJECT_DIR`; Codex has no such variable, so the commands
  use `git rev-parse --show-toplevel`. A Codex session in a subdirectory is covered; one started inside a *nested git repository* of the
  project gets none of the outer project's hooks (measured: no hook ran). Start sessions at the project root.
- Both agents continue after a Stop hook exits 2 (the hook's stderr becomes the next prompt).
- An agent that is blocked can edit the guard script itself (seen with Codex). Since 2026-10-29 the guard blocks the obvious ways (shell
  writes, Claude Code's edit tools); Codex's `apply_patch` and anything less obvious still get through. The Stop gate and the Bash guard are
  hints for honest mistakes; CI and branch protection are the boundary.
- Codex's `workspace-write` sandbox does not allow writes to `.git`; the host check judges the guard by Codex's own hook report.

## Not verified
Codex's real trust flow in an interactive session, Linux/Windows builds of either agent, and any run that is not on the machine this was
measured on. See `docs/features/codex-parity.md`.
