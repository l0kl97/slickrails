# slickrails — The Rulebook

This document is the standard for every project, new or existing. It is
pulled into each repo by `install.sh` and is binding for humans, CI, and
AI coding sessions alike.

It steals the best ideas from three worlds:
- **no-mistakes:** gate before the push, isolated, auto-fix the mechanical, escalate the judgment calls.
- **git-lrc:** review along risk categories, project-owned rules as a versioned file (`.slickrails/rules.md`).
- **Our own scar tissue:** browser smoke tests for critical flows (Node unit tests don't catch browser-only bugs).

---

## The 12 Rules

### 1. Repro test before bugfix
Every bugfix starts with a test that reproduces the bug and is **red**.
Only then comes the fix, until the test is green. No fix without a repro
test — otherwise you never know whether the bug is gone or just currently
invisible.

### 2. Critical flows get smoke tests in a real browser
Anything a user experiences as core functionality (login, create, pay,
save) has a Playwright smoke test running in a real browser. Node unit
tests are not enough (browser-only bugs like `node:crypto` imports in
client code stay invisible otherwise). Native apps get the equivalent:
XCUITest or an end-to-end run of the real app.

### 3. Green before push
The `pre-push` hook runs typecheck + tests locally before anything
leaves the machine. What is red locally does not get pushed. The hook
checks the pushed commit against a clean working tree (a dirty tree
blocks the push, because the checks would describe something else).
For a stricter variant, opt in to the local gate (`slickrails gate
init`, then `git push gate <branch>`): the pushed commit is checked
out into a disposable worktree, checked with its own
`.slickrails/config.sh`, and forwarded to the real remote only when
green — the working copy no longer matters. It is the core idea of
kunchenguid/no-mistakes, without the daemon, the TUI and the agent
pipeline (see `docs/features/local-gate.md`).

### 4. No secrets in the repo
`pre-commit` scans staged changes for secrets (gitleaks, with fallback
patterns) and blocks `.env` files. The same scan runs again in CI —
double bottom.

### 5. main is protected
Nobody pushes directly to `main`/`master`. Changes go through branches +
PRs, and a PR merges only with green CI. Branch protection is set up via
`slickrails protect` (gh CLI), which reads the settings
back from GitHub and reports what actually holds: required status
checks alone do not force a PR, and admins are only bound by the rules
unless `ENFORCE_ADMINS=0` is set.

### 6. Every PR gets an AI review
Before merge, a review runs — by default locally before every push, with
the developer's own `claude` or `codex` CLI (`.slickrails/ai-review.sh`,
no API key), or by hand via `/code-review`; teams that want it enforced
server-side add `claude-review.yml` with `slickrails github-review`. It reviews along the
risk categories: correctness, reliability, security, performance,
maintainability. Project-specific focus areas live in
`.slickrails/rules.md` and feed into every review.

For repos where security carries real weight, an opt-in deep tier
exists: `templates/workflows/security-review-ai.yml` wraps Anthropic's
official security-review action (semantic diff analysis, severity
ratings, line-level PR comments, false-positive filtering). It is not
part of the default install because it spends extra tokens per PR and,
per Anthropic, is not hardened against prompt injection — trusted PRs
only; on public repos, require approval for external contributors
before workflows run. The template pins the action to a commit SHA
(upstream publishes no tags), scans every commit of a PR (the action
alone only scans the first one) and skips fork PRs.

### 7. Dependencies under control
Dependabot is enabled, and the security workflow runs `npm audit` /
`pip-audit` (per stack) on every PR. Known CVEs block the merge.

### 8. Definition of Done
A feature is done when: code + tests + docs update exist and the smoke
tests are green. "Works on my machine" is not a state.
And: tests only count if they exercise real failure modes — invalid
input, error responses, boundary values. Happy-path-only tests are false
confidence and a review finding.

### 9. One test stack per language
- TypeScript/Node: **Vitest** (unit) + **Playwright** (smoke/E2E)
- Python: **pytest**
- Swift: **swift test / XCTest** (+ XCUITest for UI)

No parallel frameworks in the same repo. New projects start on this
stack; existing ones migrate opportunistically.

### 10. Gaps are visible, not secret
After install, every repo has a `.slickrails/STATUS.md`: which rules are
already enforced, which are not yet. A gap is a TODO with a date — not a
silent omission.

### 11. Context survives (the builder rule)
In a builder organization, people without a software background ship
features with AI tools. The context — the ask, the decisions, the test
path — then lives only in a chat history and in someone's head, and both
are gone when a developer has to fix a bug two months later and the
commit says two lines. Therefore, mechanically enforced:

- **Feature dossiers:** every feature has `docs/features/<slug>.md` —
  the ask in plain language (the original request!), decisions, where it
  lives, how to test it, bugfix history. The AI session writes and
  maintains it; the human doesn't need to know how to document.
- **Commit bodies:** the `commit-msg` hook blocks commits with ~30+
  changed lines and no explanatory body (why + what).
- **PR template:** why / what / how tested / risks — plus a dossier
  checkbox.

### 12. Small, reviewable PRs
AI makes huge changes cheap — and unreviewable. A PR stays under ~800
changed lines (excluding lockfiles); `pr-size.yml` blocks above that.
Deliberate exceptions (generated code, migrations) get the `size-ok`
label — a visible decision instead of a waved-through monster.

---

## Escape hatch (allowed, but loud)

Emergency pushes bypass the hook with `SLICKRAILS_SKIP=1 git push`, and
`git commit --no-verify` bypasses commit hooks. Condition: the reason
goes in the commit message. Skips exist for broken CI environments, not
for red tests.

## The layer model

| Layer | When | What | Duration |
|---|---|---|---|
| pre-commit | every commit | secrets scan, .env block, lint (staged) | seconds |
| commit-msg | every commit | body required above ~30 changed lines | seconds |
| post-merge | after every merge | close-the-loop reminders: dossier, changelog | seconds |
| pre-push | every push | typecheck + tests | < 2 min |
| CI (PR) | every PR | lint, typecheck, tests, build, security scan, smoke | minutes |
| Review | before merge | AI review (+ human for judgment calls) | minutes |
| Session | when the AI wants to say "done" | Stop hook: typecheck + tests | < 2 min |

Local: fast and strict on the mechanical. CI: complete and
incorruptible. Review: for everything that needs judgment.

## Session layer: enforcement instead of promises

The rules block in the project's `CLAUDE.md`/`AGENTS.md` is an
instruction — the Stop hook in `.claude/settings.json` is the
enforcement. It runs the moment an AI session wants to finish its task:
if there are uncommitted changes or commits that are not on the
upstream/default branch yet, `.slickrails/session-check.sh` runs
the checks from `config.sh` and blocks finishing while they are red
(exit 2 → the session must fix first). The hook never leaves the
decision to the host: it has its own deadline
(`SLICKRAILS_STOP_DEADLINE_MS`, default 270 s — a host timeout would
let the session end silently), a crash counts as red, a state that was
already checked green is not checked again, and after 3 blocks at an
unchanged state it lets the session end with a loud "NOT done".
The same Stop gate and guard are wired for the Codex CLI
(`.codex/hooks.json`; `install.sh --agent claude|codex|both`, default
both) — see `docs/guides/agent-parity.md` for what is enforced and
measured per agent. A `PreToolUse` Bash guard (`.slickrails/bash-guard.sh`) blocks the
obvious bypasses by an agent (`git … --no-verify`, `SLICKRAILS_SKIP=`,
writing to the guardrail files) and commands that destroy work or data
(`git reset --hard`, forced pushes, `rm -rf ~`, database resets); the way
out belongs to the human (`SLICKRAILS_ALLOW_BYPASS=1` or
`SLICKRAILS_ALLOW_DESTRUCTIVE=1` in the agent's environment, or running
the command themselves). It is a hint, not a boundary — CI and branch
protection are what hold. Mechanical checks belong in
deterministic hooks, not delegated to subagents — a hook cannot be
talked out of it. Fresh AI instances (no author bias) handle the
judgment side: `/code-review` locally, `claude-review.yml` on the PR.
Per repo, `CHECK_SESSION` in `config.sh` overrides what the Stop hook
runs.

## Scope boundary: LLM-feature guardrails

This rulebook protects *our code*. Once a product itself ships LLM
features (chat, generation, agents), it additionally needs app-level
guardrails: PII redaction, prompt-injection defense, output validation
(structured instead of parsing free text). Frameworks like guardrails-ai
(hub: Detect PII, Detect Prompt Injection, Provenance) are the right
tool for that — that is product code and belongs in the product's repo,
not in this kit.

## The 10 classic AI-code pitfalls — and where they get caught

| Pitfall | Caught by |
|---|---|
| Insecure defaults (validation, secrets, injection) | Secrets: pre-commit + gitleaks CI. Validation/injection: AI-review category Security |
| Subtle logic errors / edge cases | Rule 1 (repro tests), AI-review category Correctness |
| Skill attrition | Not solvable by tooling. Mitigation: dossiers + commit bodies in plain language — you can read back and understand what was built |
| Maintenance nightmares (deprecated APIs, messy structure) | AI-review category Maintainability, lint in CI |
| Ignored architecture / conventions | `.slickrails/rules.md` feeds into every review — that file exists for exactly this |
| False test confidence (happy path only) | Rule 8: failure-mode tests required; review flags happy-path-only as a finding |
| Hidden concurrency flaws | AI-review category Reliability: races + DB transactions under load; smoke in a real browser |
| Bloated pull requests | Rule 12 + `pr-size.yml` (~800-line limit, `size-ok` label as deliberate exception) |
| License/IP risk | Partial: review flags verbatim-looking foreign code; dependency licenses via audit. Residual risk remains — verify sources when in doubt |
| Missing operational context (logging, timeouts, monitoring) | AI-review category Operations; default rule in `rules.md`: external calls need timeout + error handling + logging |
