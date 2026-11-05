# Contributing to slickrails

Thanks for wanting to make AI-built codebases safer. A few ground rules keep
this repo easy to maintain:

## Language

**English is the source of truth.** Every user-facing text lives in English
first. German translations are a courtesy and live next to the originals
(`README.de.md`, `SLICKRAILS.de.md`, `templates/de/`). If you change an
English file that has a German sibling, update the sibling too — or say so in
the PR so a maintainer can.

## Before you open a PR

1. Run the test suite: `sh tests/run.sh` — it must be green.
2. This repo dogfoods itself: the slickrails hooks are active here. Your
   commit will be checked for secrets, and larger commits need a body
   explaining *why* and *what*.
3. Keep PRs small (rule 12 applies to us too: < ~800 changed lines).
4. Shell code is POSIX `sh` — no bashisms. `shellcheck` runs in CI.

## What makes a good contribution

- New stack adapters (Go, Rust, Ruby, PHP, JVM) for `install.sh` + a CI template
- New agent integrations (the session-rules block should work everywhere)
- Test scenarios for edge cases the suite doesn't cover yet
- Translations (the `templates/de/` structure generalizes to any language)

## What we will say no to

- Anything that adds a daemon, a required cloud service, or telemetry.
  slickrails stays local, inspectable shell + YAML.
- Checks that cannot be overridden. Every guardrail keeps a loud,
  deliberate escape hatch.
