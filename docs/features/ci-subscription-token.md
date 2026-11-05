# CI review with a Claude subscription token (no API key needed)

**Status:** active, not run on real GitHub yet · **As of:** 2026-10-21 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
The maintainer: "Zu den CLAUDE API/Codex. Kann nicht auch die subscription genutzt werden? … Ich nutze Claude Code im Terminal,
warum brauchen die slickrails zusätzlich einen API Key?"

## Decisions
- **Local reviews never needed a key.** `ai-review.sh` runs `claude -p` and uses the CLI login; Codex uses its ChatGPT login. Only the GitHub workflows asked for `ANTHROPIC_API_KEY`.
- **`claude-review.yml` and the composite action take either secret.** Both inputs are passed (`claude_code_oauth_token` from `CLAUDE_CODE_OAUTH_TOKEN`, `anthropic_api_key` from `ANTHROPIC_API_KEY`); the one that is not set is an empty string. The official docs (code.claude.com/docs/en/github-actions, read 2026-10-21) name `CLAUDE_CODE_OAUTH_TOKEN` as the subscription credential (Pro, Max, Team, Enterprise; created with `claude setup-token`) and say that runs with an OAuth token use the subscription instead of API billing.
- **`security-review-ai.yml` keeps the API key.** The wrapped action (`anthropics/claude-code-security-review`) only has a `claude-api-key` input; the template says so.
- **Team advice:** the docs recommend an API key for a secret shared across repositories, because an OAuth token is tied to the subscription of the person who ran `claude setup-token`. `docs/guides/adopt-in-a-team.md` repeats that.

## Where it lives
- `templates/workflows/claude-review.yml`, `.github/workflows/claude-review.yml` (the kit's own copy), `actions/claude-review/action.yml`
- `install.sh` (next-step text), `README.md`, `README.de.md`, `docs/guides/adopt-in-a-team.md`, `templates/slickrails-status.md`, `templates/de/slickrails-status.md`
- `tests/run.sh` — block "AI review in CI: a Claude subscription token works as well as an API key"

## How to test it
1. `sh tests/run.sh` — four checks in that block (both secrets wired in both workflow files, action inputs optional, installer text).
2. Not tested: a real run on GitHub. Open questions: does the action accept an empty `anthropic_api_key` next to a set token; what does a run with no secret at all do (it must fail loudly, not look green); does subscription use in CI fit the plan's terms (unchecked).

## Limits & open items
- Passing both inputs is derived from the documented input list, not from a run.
- Terms: Codex' review pointed out that the consumer terms limit automated use except via API key or with explicit permission; whether the Action's documentation counts as that permission is a contract question nobody here has answered. The README tells users to check it and names the API key as the unambiguous choice.
- A subscription token draws from the owner's plan limits; a busy repo can use them up.

## History
- 2026-10-21: created; both secrets accepted in `claude-review.yml` and the composite action (commit ab5fe06).
- 2026-10-22: the first ready pull request of this repo answered one open question: without setup the review job fails loudly (red), it does not pass. The cause was not the missing secret but the missing Claude GitHub App ("Claude Code is not installed on this repository", the app token exchange returns 401). Our docs only named the secret. Now the installer, the workflow header and both READMEs name the app and `/install-github-app` (which installs the app and stores a subscription token in one go); a test keeps that text in place. Still unchecked: a run with app and token.
