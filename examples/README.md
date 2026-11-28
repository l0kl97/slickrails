# Examples: slickrails on a small project

Two tiny projects, each set up with the current kit, so you can see what `slickrails init` writes and try the
guardrails before you put them into your own repository.

| Example | Stack | The feature | Its dossier |
|---|---|---|---|
| [`node-pnpm/`](node-pnpm/) | Node 20+, pnpm, `node --test` | `slugify(title)`: readable post URLs | [`docs/features/slugify.md`](node-pnpm/docs/features/slugify.md) |
| [`python/`](python/) | Python 3.9+, pytest | `parse_duration("1h30m")`: durations as people type them | [`docs/features/duration-input.md`](python/docs/features/duration-input.md) |

Everything else in them comes from the installer: `.githooks/`, `.slickrails/` (rulebook, checks in `config.sh`,
manifest), `.github/` (CI, PR size, security, Dependabot), the agent hooks in `.claude/` and `.codex/`, and the rules
block in `CLAUDE.md` and `AGENTS.md`.

**The dossier is the part to read.** It holds what a chat history loses: what was asked, in the asker's words, what
was decided and why, where the code lives, how to test it, and what went wrong once (symptom → cause → fix).

## Try it in three steps

The examples are not in the installed kit (`bootstrap.sh` leaves them out to keep it small). Take them from a clone:
`git clone --depth 1 https://github.com/l0kl97/slickrails`. The commands below use the Python example and need
`python3 -m pip install pytest`; for `node-pnpm/` you need pnpm, and `python3 -m pytest -q` becomes `pnpm test`.

**1. Copy the example out and make it a repository.** Git does not copy the hooks setting, so it is switched on once.

```sh
cp -R slickrails/examples/python ~/try-slickrails && cd ~/try-slickrails
git init -q && git config core.hooksPath .githooks
git add -A && git commit -m "Start from the slickrails example" -m "Why: try the guardrails" -m "What: the example as it ships"
```

The first commit is large, so the commit-msg hook wants a body (why and what). Without `-m` for the body it says so.

**2. Commit a secret.** The pre-commit hook blocks it (with gitleaks if installed, otherwise with its own patterns).

```sh
printf 'AWS_KEY = "AKIA%s"\n' ABCDEFGHIJKLMNOP > src/settings.py
git add src/settings.py && git commit -m "Add settings"     # → slickrails[pre-commit]: Blocked — ... secrets
git rm -q --cached src/settings.py && rm src/settings.py
```

**3. Push with a red test.** Break the function, commit, push to a local remote: the pre-push hook runs the tests
from `.slickrails/config.sh` and stops the push.

```sh
sed -i.bak 's/    return total$/    return total + 1/' src/duration/__init__.py && rm src/duration/__init__.py.bak
git commit -qam "Count one minute more"
git init -q --bare ../try-remote.git && git push ../try-remote.git HEAD:main   # → Blocked — Tests is red
```

Undo the change (`git revert --no-edit HEAD`), push again, and it goes out.

With Claude Code or Codex open in the copy, the agent hooks join in: the Bash guard blocks `--no-verify` and edits
to the guardrail files, and the Stop gate runs the checks before the session ends (both ask once to be trusted).

## For kit maintainers

The kit files in the examples are generated. After a change to a template or to `install.sh`, rebuild them with

```sh
sh scripts/build-examples.sh
```

and commit the result. `tests/run.sh` builds them again in a temporary folder and fails when the committed examples
differ, or when their manifest names an older kit version. The build keeps each example's own files (code, tests,
dossier, its `.gitignore` lines) and replaces everything the installer writes. It runs with `--review off`, so the
examples do not depend on the AI CLI of whoever builds them; switch the local review on with
`CHECK_PREPUSH_REVIEW="1"` in `.slickrails/config.sh`.
