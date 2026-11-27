# Dependabot only for the ecosystems a repo has

**Status:** active · **As of:** 2026-11-27 · **Built by:** Atlas with Claude Code (Linear SLI-129)

## The ask (plain language)
"`slickrails init` legt `.github/dependabot.yml` mit den Einträgen github-actions, npm und pip an. Das passiert auch
bei unbekanntem Stack („generic“) und in Repos ohne `package.json` bzw. Python-Abhängigkeiten. Die npm- und pip-Läufe
haben dann nichts zu prüfen, enden rot und erzeugen nur Rauschen im Actions-Tab." Seen in slickfab on 2026-11-24
(fixed there by hand). Wanted: npm only with a Node manifest or lockfile, pip only with a Python dependency file,
github-actions as soon as `.github/workflows/` has files, and a repo with the old file keeps it (the new one lands
next to it as `.slickrails-new`).

## Decisions
- One template per combination (`templates/dependabot/<ecosystems>.yml`; the full set stays
  `templates/dependabot.yml`) → the file still goes through `place()`, so the manifest's update path and the
  `.slickrails-new` rule apply unchanged. Rejected: assembling the file from fragments in a temp file — `place()`
  records the template's path in the manifest, a temp path would change on every run and break the update path.
- A repo with an unchanged old file gets `.slickrails-new`, not a silent replacement: the template changed (another
  file), which `place()` treats as "someone decides", like a change of `--lang` or stack.
- Detection looks at the repo root only, because every entry uses `directory: "/"`. npm: `package.json`,
  `package-lock.json`, `npm-shrinkwrap.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, `bun.lock`. pip:
  `requirements*.txt`, `requirements*.in`, `pyproject.toml`, `Pipfile`, `Pipfile.lock`, `uv.lock`, `poetry.lock`.
  Separate from `STACK` on purpose: a repo can be Node and Python at once.
- No ecosystem at all → no `dependabot.yml`. In practice github-actions is always there, since the installer places
  `security.yml` and `pr-size.yml` first.

## Where it lives
- `install.sh`, workflows section: `DEP_ECOS` detection and the `place` of the matching variant.
- `templates/dependabot.yml` (all three) and `templates/dependabot/*.yml` (the subsets).
- `tests/run.sh`: the `dep_case` block in the installer section, the "init again" cases after it, and the variant
  check next to the workflow YAML check.

## How to test it
1. `sh tests/run.sh` — the `installer: dependabot.yml — …` lines (workflows only, Node, Python, both, files below the
   root, Go), the three "init again" / own-file lines and `dependabot templates: …` must pass.
2. By hand: `slickrails init` in an empty git repo → `.github/dependabot.yml` has only `github-actions`.

## Limits & open items
- Monorepos with `package.json` or Python files only in subdirectories get no npm/pip entry (the entries would need
  their own `directory`). Not covered by this change.
- Other ecosystems (Go modules, Cargo, Bundler, Maven/Gradle, Swift) are still not added to Dependabot.
- The variants repeat the blocks of the full template; the variant test checks names and YAML, not that the blocks are
  byte-equal to the full template.

## History
- 2026-11-27: created (SLI-129). Symptom: red npm and pip Dependabot runs in a repo without Node or Python (slickfab)
  → cause: one fixed template with all three ecosystems → fix: a variant per detected combination, placed via
  `place()`; tests red first.
