# Adopting slickrails in an existing team

The kit is built for retrofit — but a team is not a repo. The order
matters more than the tooling.

## Week 1 — visible, not enforced

1. Run `slickrails init` on one repo (a busy one, not a museum).
2. Commit the result and walk the team through `.slickrails/SLICKRAILS.md` in 15
   minutes. The pitch is not "more process": it is *"the AI does the
   documenting, the hooks catch what reviews miss, and nobody pushes a
   secret again."*
3. Leave branch protection OFF for the first week. Let the local hooks
   speak for themselves — the first time pre-commit catches a real
   secret, the argument is over.

## Week 2 — enforce the cheap layers

4. `slickrails protect` — required checks on main, admins
   bound by them (`ENFORCE_ADMINS=0` opts out). The script reads the
   settings back from GitHub and says what holds; pull requests stay
   optional (required checks alone do not force them).
5. The AI review runs locally before every push with each developer's own `claude` or `codex` (no key, no minutes). To enforce it server-side too: `slickrails github-review`, then install the [Claude GitHub App](https://github.com/apps/claude) and set the `CLAUDE_CODE_OAUTH_TOKEN` (subscription, `claude setup-token`) or `ANTHROPIC_API_KEY` secret (`/install-github-app` in Claude Code does both). A shared team secret should be an API key: an OAuth token is tied to the subscription of the person who created it.
   Optional: `slickrails init --status-mod` offers everyone the slickrails status line in Claude Code.
6. Create the `size-ok` label and tell everyone about rule 12's limit
   *before* the first PR gets blocked by it.

## Week 3+ — the builder layer

7. Backfill feature dossiers for the 5–10 features people actually ask
   about ("how does billing work again?"). Don't backfill everything —
   rule 10 says gaps are visible, not secret; `.slickrails/STATUS.md`
   tracks the rest.
8. Non-developers building with AI: their session writes the dossier
   (the CLAUDE.md/AGENTS.md block makes it the agent's job). Their only
   duty is noticing when it didn't happen.

## Objections you will hear

- **"Hooks slow me down."** pre-commit is seconds; pre-push is your
  test suite — if that is slow, that was already your problem, and
  `SLICKRAILS_SKIP=1` exists for genuine emergencies (loudly).
- **"Our repo is special."** `.slickrails/config.sh` is four lines —
  point the checks at whatever the repo really uses.
- **"We already have husky/pre-commit."** Keep it: `install.sh` never
  overwrites, and it does not switch an existing `core.hooksPath` either —
  it tells you the slickrails git hooks are NOT active and marks it in
  `.slickrails/STATUS.md`. Call `.githooks/pre-commit`, `pre-push` and
  `commit-msg` from your hook manager (or switch the path knowingly).
  `slickrails doctor` shows whether the hooks are active in a clone
  (`core.hooksPath` is local git config and is not cloned). The parts
  they don't have are the AI review, the session enforcement, and the
  dossiers.
