# Launch Playbook

Maintainer checklist for the public launch. Code quality got us here;
distribution and first impression decide the rest.

## State (2026-11-12)

Done: the repo is public (one start commit, the older history lives in the maintainer's private archive),
topics and description are set, releases are tagged on GitHub, branch protection is on (`slickrails protect`:
pull requests required, the three CI systems, gitleaks, audit, size), the `size-ok` label exists, demo GIF,
header and motion graphics are embedded in both READMEs.

## Before launch day

- [ ] `npm publish` from `npm/` (name `slickrails`; the version there follows `VERSION`)
- [ ] Homebrew: fill the formula (`packaging/homebrew/slickrails.rb`) with the release tarball's sha256 and push
      the tap repo (`homebrew-slickrails`); then name both in the README's install section
- [ ] Enable Discussions; open the 10 good-first-issues below
- [ ] **Run the kit once against a throwaway GitHub repo** (the biggest unverified part): `slickrails init` for a
      Node and a Python project (the stack templates' setup actions and audit steps have never run), a PR with
      `claude-review.yml` using `CLAUDE_CODE_OAUTH_TOKEN` and the Claude GitHub App (`/install-github-app`),
      `security-review-ai.yml` with an API key, `slickrails gate` against the real remote
- [ ] Trust flow by hand: new project hooks in Claude Code (dialog) and Codex (`/hooks`), then a red-check session must block
- [ ] Look at the README once on the real GitHub page on a phone (GIFs through the camo proxy)

## Launch day (all channels the same day)

- [ ] Show HN (draft below)
- [ ] r/ClaudeAI + r/ChatGPTCoding (draft below)
- [ ] X/LinkedIn thread: demo GIF first, builder story second, link third
- [ ] Week 1 rule: answer every issue/comment < 24h

## Show HN draft

> **Show HN: slickrails – Guardrails for AI-built codebases**
>
> My team ships features built by people who don't write code — they
> build with Claude Code and Codex. It works, until a developer has to
> fix a bug two months later: the commit says two lines, the chat
> history that explained everything is gone, and nobody remembers why
> the feature exists.
>
> slickrails is one command that pulls an enforced standard into any
> repo: git hooks (secrets, red tests, thin commit messages), CI per
> stack, a PR size guard, AI review on every PR — and the part nothing
> else does: feature dossiers that the AI session itself writes and
> maintains, so the intent survives the chat.
>
> It works the same for Claude Code and Codex CLI: a Stop hook keeps
> the session from finishing while checks are red, a Bash guard stops
> `--no-verify`. I measured both against the real CLIs; a hook that
> times out lets the session through in both, so the gate has its own
> deadline. A seeded-bug benchmark (11/12 faults caught, 0/10 false
> positives on the deterministic layer) is in the repo, and so is the
> list of what I have not verified: branch protection and the review
> workflows on a real repo, Codex's interactive trust flow. The suite
> runs green on Linux, macOS and Windows (Git Bash) in CI. Hooks are hints; CI and branch
> protection are the boundary.
>
> Deliberately boring tech: POSIX shell + YAML, no daemon, no cloud
> account, no telemetry, MIT. The kit dogfoods its own hooks.
>
> https://github.com/l0kl97/slickrails

## r/ClaudeAI draft

> **I built guardrails for vibe-coded repos — the AI writes the docs, the hooks catch the rest**
>
> The failure mode isn't bad AI code — it's that the *context* dies
> with the chat. So: `slickrails init` installs hooks that block
> secrets and red pushes, a commit-msg hook that refuses 200-line
> diffs with 2-line messages, AI review on PRs, and a rule that every
> feature gets a dossier (original ask in plain language, decisions,
> test path) — written by the Claude session itself via a CLAUDE.md
> block, enforced by a Stop hook that won't let a session say "done"
> with red tests (Codex CLI gets the same). The PR review can use your
> Claude subscription token instead of an API key (documented by the
> action, not yet run by me on GitHub: say so in the thread). MIT, no daemon, no
> telemetry. Feedback very welcome.

## 10 good-first-issues (open on day one)

1. Stack adapter: PHP (composer.json → phpunit) — detection + ci-php.yml
2. Stack adapter: Elixir (mix.exs → mix test)
3. Stack adapter: Deno (deno.json → deno test)
4. `install.sh`: generate `.gitleaks.toml` + `.gitleaksignore` scaffold
5. commit-msg hook: make the threshold configurable per repo via config.sh (currently env only)
6. tests/run.sh: cover `slickrails upgrade` against a local remote
7. pr-size action: report the count as a PR comment, not only a failed check
8. Translate templates to French (`templates/fr/`) following `templates/de/`
9. docs: "slickrails + husky side by side" guide
10. Windows: a native PowerShell installer for people without Git Bash

## The case study (within a month)

Track for 30 days on real repos and publish: secrets blocked,
red pushes stopped, thin commits refused, dossiers written. Real
numbers beat any feature list.
