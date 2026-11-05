# Security Policy

slickrails is a set of local shell hooks and GitHub Actions templates. It runs
no daemon, phones no home, and collects no telemetry.

## Reporting a vulnerability

If you find a security issue — e.g. a way to smuggle secrets past the
pre-commit scan, a command-injection vector through `.slickrails/config.sh`,
or a malicious-repo scenario against `install.sh` — please **do not open a
public issue**. Email kontakt@jonahjeschkeit.com with the details and a
reproduction. You will get a response within a week.

## Scope notes

- The fallback secrets scanner (used when `gitleaks` is not installed) is
  pattern-based and intentionally simple; it is a safety net, not a guarantee.
  Install `gitleaks` for real coverage.
- `.slickrails/config.sh` is sourced by the hooks. It is part of the target
  repository and therefore as trusted as the repository itself.
